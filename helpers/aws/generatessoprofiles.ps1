#requires -Version 5.1
param(
  [string]$RoleName        = 'ReadOnlyAccess',   # use '*' to include ALL roles found per account
  [Parameter(Mandatory)][string]$SSOStartUrl,    # https://d-xxxx.awsapps.com/start
  [string]$SSORegion       = 'eu-west-2',
  [string]$DefaultRegion   = 'eu-west-2',
  [int]   $Concurrency     = 8,                  # threads for role discovery
  [string]$OutFile,                               # optional output path; default: ~/.aws/config.generated.YYYYMMDD-HHmmss.ini
  [switch]$SetForSession,                         # set AWS_CONFIG_FILE for this shell
  [switch]$Persist                                # set User AWS_CONFIG_FILE for all new shells
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

### --- Utilities --- ###
function Test-AWSCLIInstalled {
  try { Get-Command aws -ErrorAction Stop | Out-Null; $true } catch { throw "AWS CLI v2 not found in PATH." }
}
function Write-FileNoBom([string]$Path,[string]$Text) {
  [System.IO.File]::WriteAllText($Path,$Text,[System.Text.UTF8Encoding]::new($false))
}
function Get-SSOAccessToken {
  param([string]$SSORegion,[string]$SSOStartUrl)
  $dir = Join-Path $env:USERPROFILE ".aws\sso\cache"
  if (-not (Test-Path $dir)) { return $null }
  foreach ($f in Get-ChildItem $dir -Filter *.json | Sort-Object LastWriteTime -Descending) {
    try {
      $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
      if ($j.accessToken -and $j.expiresAt -and $j.region -eq $SSORegion -and $j.startUrl -eq $SSOStartUrl) {
        if ([DateTimeOffset]::Parse($j.expiresAt).UtcDateTime -gt (Get-Date).ToUniversalTime()) { return $j.accessToken }
      }
    } catch { }
  }
  $null
}
function SSO-ListAccounts {
  param([string]$Token,[string]$Region)
  $all=@(); $next=$null; $page=0
  do {
    $args=@('sso','list-accounts','--access-token',$Token,'--region',$Region)
    if ($next) { $args += @('--next-token',$next) }
    $raw = & aws @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("aws sso list-accounts failed: {0}" -f $raw) }
    $obj = $raw | ConvertFrom-Json
    $cnt = ($obj.accountList | Measure-Object).Count
    $page++; Write-Host ("  accounts page {0}: {1} items" -f $page,$cnt)
    if ($cnt -gt 0) { $all += $obj.accountList }
    $next = if ($obj.PSObject.Properties['nextToken']) { $obj.nextToken } else { $null }
  } while ($next)
  $all
}
function Build-ConfigText {
  param([array]$Pairs,[string]$SSOStartUrl,[string]$SSORegion,[string]$DefaultRegion)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($p in $Pairs) {
    $aid = $p.accountId; $role = $p.role
    if ($aid -notmatch '^\d{12}$') { continue }
    $name = "$($aid.ToLower())-$($role.ToLower())"
    $lines.Add("[profile $name]")
    $lines.Add("sso_start_url = $SSOStartUrl")
    $lines.Add("sso_region = $SSORegion")
    $lines.Add("sso_account_id = $aid")
    $lines.Add("sso_role_name = $role")
    $lines.Add("region = $DefaultRegion")
    $lines.Add("output = json")
    $lines.Add("")
  }
  [string]::Join([Environment]::NewLine, $lines.ToArray())
}
function New-TempLoginConfig {
  param([string]$SSOStartUrl,[string]$SSORegion,[string]$DefaultRegion)
  $p = Join-Path $env:TEMP ("aws-login.{0}.ini" -f ([guid]::NewGuid().ToString('N')))
  $text = @(
    "[profile temp-sso-profile]"
    "sso_start_url = $SSOStartUrl"
    "sso_region = $SSORegion"
    "sso_account_id = 000000000000"
    "sso_role_name = placeholder"
    "region = $DefaultRegion"
    "output = json"
  ) -join [Environment]::NewLine
  Write-FileNoBom -Path $p -Text $text
  $p
}
function Set-AWSConfigFile([string]$Path,[switch]$Persist) {
  if ($Persist) { [Environment]::SetEnvironmentVariable('AWS_CONFIG_FILE',$Path,'User') }
  $env:AWS_CONFIG_FILE = $Path
  $scope = $Persist.IsPresent ? "User + this shell" : "this shell"
  Write-Host ("AWS_CONFIG_FILE -> {0} ({1})" -f $Path,$scope) -ForegroundColor Green
}

### --- Threaded role discovery (runspaces) --- ###
function Get-AwsSsoPairsThreaded {
  <#
    .SYNOPSIS
      Threaded SSO role discovery with retries. Returns a flat list of PSCustomObjects:
        @{ accountId = '123456789012'; role = 'ReadOnlyAccess' }
      and error rows:
        @{ accountId = '...'; isError = $true; error = '...' }
  #>
  param(
    [Parameter(Mandatory)] [array]  $Accounts,
    [Parameter(Mandatory)] [string] $Token,
    [Parameter(Mandatory)] [string] $SSORegion,
    [Parameter(Mandatory)] [string] $RoleName,
    [int] $Concurrency = 8,
    [int] $MaxRetries  = 6
  )

  $iss  = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
  $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Concurrency, $iss, $Host)
  $pool.Open()

  $jobs = @()
  foreach ($a in $Accounts) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    $null = $ps.AddScript({
      param($AccountId,$Token,$Region,$RoleName,$MaxRetries)

      try {
        $allRoles = @()
        $next = $null
        do {
          # one page, with retry/backoff
          $attempt = 0
          do {
            $attempt++
            $args = @('sso','list-account-roles','--access-token',$Token,'--region',$Region,'--account-id',$AccountId)
            if ($next) { $args += @('--next-token',$next) }

            $raw = & aws @args 2>&1
            $exit = $LASTEXITCODE
            $rawText = ($raw -join "`n")  # <-- join array to single string

            if ($exit -eq 0) {
              $page = $rawText | ConvertFrom-Json
              if ($page.PSObject.Properties['roleList'] -and $page.roleList) {
                $allRoles += $page.roleList.roleName
              }
              $next = if ($page.PSObject.Properties['nextToken']) { $page.nextToken } else { $null }
              break
            }

            $retryable = $rawText -match 'TooManyRequests|Throttl|Rate exceeded|429|Timeout|timed out|RequestLimitExceeded'
            if ($retryable -and $attempt -lt $MaxRetries) {
              $sleep = [Math]::Min([Math]::Pow(2, $attempt), 10) + (Get-Random -Minimum 0 -Maximum 0.5)
              Start-Sleep -Seconds $sleep
            } else {
              throw ("list-account-roles failed for {0}: {1}" -f $AccountId, $rawText)
            }
          } while ($true)
        } while ($next)

        # Emit results
        if ($RoleName -eq '*') {
          foreach ($r in ($allRoles | Sort-Object -Unique)) {
            [pscustomobject]@{ accountId = $AccountId; role = $r }
          }
        } elseif ($allRoles -contains $RoleName) {
          [pscustomobject]@{ accountId = $AccountId; role = $RoleName }
        } else {
          # No match for this account; emit nothing
        }
      }
      catch {
        [pscustomobject]@{
          accountId = $AccountId
          isError   = $true
          error     = $_.Exception.Message
        }
      }
    }).AddParameter('AccountId',$a.accountId).AddParameter('Token',$Token).AddParameter('Region',$SSORegion).AddParameter('RoleName',$RoleName).AddParameter('MaxRetries',$MaxRetries)

    $jobs += [pscustomobject]@{ PS=$ps; Handle=$ps.BeginInvoke(); AccountId=$a.accountId; Done=$false }
  }

  $total = $jobs.Count
  $done  = 0
  $out   = New-Object System.Collections.ArrayList

  while ($done -lt $total) {
    foreach ($j in $jobs) {
      if (-not $j.Done -and $j.Handle.IsCompleted) {
        try {
          $res = $j.PS.EndInvoke($j.Handle)
          $arr = @($res)
          if ($arr.Count -gt 0) { [void]$out.AddRange($arr) }
        } finally {
          $j.PS.Dispose()
          $j.Done = $true
          $done++
          Write-Progress -Activity "Fetching roles (threaded)" -Status ("{0}/{1} accounts" -f $done,$total) -PercentComplete ([int](100*$done/$total))
        }
      }
    }
    Start-Sleep -Milliseconds 75
  }

  Write-Progress -Activity "Fetching roles (threaded)" -Completed
  $pool.Close(); $pool.Dispose()

  ,$out  # force array
}


### --- Main --- ###
if ($SSOStartUrl -notmatch '^https://') { throw "SSO start URL must start with https://" }
if ($Concurrency -lt 1) { throw "Concurrency must be >= 1" }
Test-AWSCLIInstalled | Out-Null

if (-not $OutFile) {
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutFile = Join-Path (Join-Path $env:USERPROFILE '.aws') ("config.generated.{0}.ini" -f $ts)
}
$dir = Split-Path $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# Temp login config (so we don't touch your real config during login)
$loginCfg = New-TempLoginConfig -SSOStartUrl $SSOStartUrl -SSORegion $SSORegion -DefaultRegion $DefaultRegion

$prevCfg = $env:AWS_CONFIG_FILE
$env:AWS_CONFIG_FILE = $loginCfg
try {
  Write-Host "Logging into SSO (browser opens)..." -ForegroundColor Cyan
  & aws sso login --profile temp-sso-profile
  if ($LASTEXITCODE -ne 0) { throw "SSO login failed." }
  Write-Host ("Logged into: {0}" -f $SSOStartUrl) -ForegroundColor Green

  $token = Get-SSOAccessToken -SSORegion $SSORegion -SSOStartUrl $SSOStartUrl
  if (-not $token) { throw "Could not resolve a valid SSO access token from cache." }

  Write-Host "Discovering accounts..." -ForegroundColor Cyan
  $accounts = SSO-ListAccounts -Token $token -Region $SSORegion
  $acctCount = ($accounts | Measure-Object).Count
  Write-Host ("Total accounts: {0}" -f $acctCount)

Write-Host ("Enumerating roles (threaded, concurrency={0})..." -f $Concurrency) -ForegroundColor Cyan
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$allRows = Get-AwsSsoPairsThreaded -Accounts $accounts -Token $token -SSORegion $SSORegion -RoleName $RoleName -Concurrency $Concurrency
$sw.Stop()

$errors = $allRows | Where-Object { $_.PSObject.Properties['isError'] -and $_.isError }
if ($errors) {
  Write-Warning ("{0} account(s) failed; will continue without them" -f ($errors.Count))
  $errors | Select-Object -First 10 | ForEach-Object { Write-Warning ("  {0}: {1}" -f $_.accountId, $_.error) }
  if ($errors.Count -gt 10) { Write-Warning ("  ... and {0} more" -f ($errors.Count - 10)) }
}

$pairs = $allRows | Where-Object { -not ($_.PSObject.Properties['isError'] -and $_.isError) }

Write-Host ("Account/role pairs discovered: {0} in {1:n1}s" -f $pairs.Count, $sw.Elapsed.TotalSeconds)
if ($pairs.Count -eq 0) {
  if ($RoleName -eq '*') { throw "No roles discovered on any accounts." }
  else { throw ("No accounts expose role '{0}'." -f $RoleName) }
}

  Write-Host ("Writing: {0}" -f $OutFile) -ForegroundColor Green
  $cfgText = Build-ConfigText -Pairs $pairs -SSOStartUrl $SSOStartUrl -SSORegion $SSORegion -DefaultRegion $DefaultRegion
  Write-FileNoBom -Path $OutFile -Text $cfgText
}
finally {
  if ($prevCfg) { $env:AWS_CONFIG_FILE = $prevCfg } else { Remove-Item Env:AWS_CONFIG_FILE -ErrorAction SilentlyContinue }
  Remove-Item $loginCfg -ErrorAction SilentlyContinue
}

# Point AWS to the newly generated file if requested
if ($SetForSession -or $Persist) { Set-AWSConfigFile -Path $OutFile -Persist:$Persist }

# Verify
Write-Host "Verifying profiles in generated file..." -ForegroundColor Yellow
$old = $env:AWS_CONFIG_FILE
try {
  $env:AWS_CONFIG_FILE = $OutFile
  aws configure list-profiles
} finally {
  $env:AWS_CONFIG_FILE = $old
}
