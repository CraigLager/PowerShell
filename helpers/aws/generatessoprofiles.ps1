#requires -Version 5.1
param(
  [string]$RoleName,        # '*' to emit ALL roles per account
  [string]$SSOStartUrl,
  [string]$SSORegion,
  [string]$DefaultRegion,
  [switch]$Persist          # set AWS_CONFIG_FILE at the User scope (survives new shells)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

########## Utilities ##########
function Test-AWSCLIInstalled {
  try { Get-Command aws -ErrorAction Stop | Out-Null; $true }
  catch { Write-Error "AWS CLI v2 not found in PATH."; $false }
}
function Get-AWSPaths {
  $awsDir = Join-Path $env:USERPROFILE ".aws"
  if (-not (Test-Path $awsDir)) { New-Item -ItemType Directory -Path $awsDir -Force | Out-Null }
  [pscustomobject]@{
    Dir        = $awsDir
    Settings   = Join-Path $awsDir "sso-script-settings.json"
  }
}
function Load-LastSettings {
  $p = Get-AWSPaths
  $d = @{ RoleName="ReadOnlyAccess"; SSOStartUrl=""; SSORegion="eu-west-2"; DefaultRegion="eu-west-2" }
  if (Test-Path $p.Settings) {
    try {
      $j = Get-Content $p.Settings -Raw | ConvertFrom-Json
      foreach ($k in $d.Keys) { if ($j.PSObject.Properties.Match($k)) { $d[$k] = $j.$k } }
    } catch { }
  }
  [pscustomobject]$d
}
function Save-Settings {
  param([string]$RoleName,[string]$SSOStartUrl,[string]$SSORegion,[string]$DefaultRegion)
  $p = Get-AWSPaths
  @{ RoleName=$RoleName; SSOStartUrl=$SSOStartUrl; SSORegion=$SSORegion; DefaultRegion=$DefaultRegion; LastUsed=(Get-Date) } |
    ConvertTo-Json | Set-Content -Path $p.Settings -Encoding UTF8
}
function Prompt-IfMissing {
  param([string]$Value,[string]$Prompt,[string]$Default,[switch]$Required)
  if ($Value) { return $Value }
  if ($Default) {
    $v = Read-Host "$Prompt (default: $Default)"
    if ([string]::IsNullOrWhiteSpace($v)) { $Default } else { $v }
  } else {
    do {
      $v = Read-Host $Prompt
      if (-not [string]::IsNullOrWhiteSpace($v) -or -not $Required) { return $v }
      Write-Host "This field is required" -ForegroundColor Yellow
    } while ($true)
  }
}
function Get-SSOAccessToken {
  param([string]$SSORegion,[string]$SSOStartUrl)
  $cacheDir = Join-Path $env:USERPROFILE ".aws\sso\cache"
  if (-not (Test-Path $cacheDir)) { return $null }
  $files = Get-ChildItem $cacheDir -Filter *.json | Sort-Object LastWriteTime -Descending
  foreach ($f in $files) {
    try {
      $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
      if ($j.accessToken -and $j.expiresAt -and $j.region -and $j.startUrl) {
        if ($j.region -eq $SSORegion -and $j.startUrl -eq $SSOStartUrl) {
          $exp = [DateTimeOffset]::Parse($j.expiresAt).UtcDateTime
          if ($exp -gt (Get-Date).ToUniversalTime()) { return $j.accessToken }
        }
      }
    } catch { }
  }
  $null
}
function SSO-ListAccounts {
  param([string]$Token,[string]$Region)
  $all=@(); $next=$null; $pageNum=0
  do {
    $args=@("sso","list-accounts","--access-token",$Token,"--region",$Region)
    if ($next) { $args += @("--next-token",$next) }
    $raw = & aws @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("aws sso list-accounts failed: {0}" -f $raw) }
    $page = $raw | ConvertFrom-Json
    $count = ($page.accountList | Measure-Object).Count
    $pageNum++; Write-Host ("  accounts page {0}: {1} items" -f $pageNum,$count)
    if ($count -gt 0) { $all += $page.accountList }
    $next = if ($page.PSObject.Properties['nextToken']) { $page.nextToken } else { $null }
  } while ($next)
  $all
}
function SSO-ListRolesForAccount {
  param([string]$Token,[string]$Region,[string]$AccountId)
  $roles=@(); $next=$null
  do {
    $args=@("sso","list-account-roles","--access-token",$Token,"--region",$Region,"--account-id",$AccountId)
    if ($next) { $args += @("--next-token",$next) }
    $raw = & aws @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("aws sso list-account-roles failed for {0}: {1}" -f $AccountId,$raw) }
    $page = $raw | ConvertFrom-Json
    if ($page.PSObject.Properties['roleList'] -and $page.roleList) { $roles += $page.roleList.roleName }
    $next = if ($page.PSObject.Properties['nextToken']) { $page.nextToken } else { $null }
  } while ($next)
  $roles | Sort-Object -Unique
}
function Build-ConfigText {
  param([array]$AccountRolePairs,[string]$SSOStartUrl,[string]$SSORegion,[string]$DefaultRegion)
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($p in $AccountRolePairs) {
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
function Write-FileNoBom { param([string]$Path,[string]$Text) [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false)) }
function Show-ConfigSummary {
  param([string]$Path)
  $content = if (Test-Path $Path) { Get-Content $Path -Raw } else { "" }
  $names = [regex]::Matches($content, '^\[profile\s+([^\]]+)\]', 'Multiline') | ForEach-Object { $_.Groups[1].Value }
  $count = ($names | Measure-Object).Count
  Write-Host ("Profiles in {0}: {1}" -f $Path,$count) -ForegroundColor Yellow
  $names | Sort-Object | Select-Object -First 10 | ForEach-Object { Write-Host ("  - {0}" -f $_) }
  if ($count -gt 10) { Write-Host ("  ... and {0} more" -f ($count-10)) }
}
function Set-AWSConfigEnv([string]$Path,[switch]$Persist) {
  if ($Persist) {
    [Environment]::SetEnvironmentVariable('AWS_CONFIG_FILE', $Path, 'User')
    $env:AWS_CONFIG_FILE = $Path
    Write-Host ("Set AWS_CONFIG_FILE (User) -> {0}" -f $Path) -ForegroundColor Green
  } else {
    $env:AWS_CONFIG_FILE = $Path
    Write-Host ("Set AWS_CONFIG_FILE (this shell) -> {0}" -f $Path) -ForegroundColor Green
  }
}

########## Main ##########
if (-not (Test-AWSCLIInstalled)) { exit 1 }

$last = Load-LastSettings
if (-not $RoleName)      { $RoleName      = Prompt-IfMissing -Prompt "Role name ('*' for all roles)" -Default $last.RoleName -Required }
if (-not $SSOStartUrl)   { $SSOStartUrl   = Prompt-IfMissing -Prompt "AWS SSO start URL"            -Default $last.SSOStartUrl -Required }
if (-not $SSORegion)     { $SSORegion     = Prompt-IfMissing -Prompt "AWS SSO region"               -Default $last.SSORegion }
if (-not $DefaultRegion) { $DefaultRegion = Prompt-IfMissing -Prompt "Default AWS region"           -Default $last.DefaultRegion }

if ($SSOStartUrl -notmatch '^https://') { throw "SSO start URL must start with https://" }
Save-Settings -RoleName $RoleName -SSOStartUrl $SSOStartUrl -SSORegion $SSORegion -DefaultRegion $DefaultRegion

# Prepare temp config for login
$awsDir = (Get-AWSPaths).Dir
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$loginCfg = Join-Path $env:TEMP ("aws-login.{0}.ini" -f ([guid]::NewGuid().ToString('N')))
$genCfg   = Join-Path $awsDir ("config.generated.{0}.ini" -f $ts)

$loginText = @(
  "[profile temp-sso-profile]"
  "sso_start_url = $SSOStartUrl"
  "sso_region = $SSORegion"
  "sso_account_id = 000000000000"
  "sso_role_name = placeholder"
  "region = $DefaultRegion"
  "output = json"
) -join [Environment]::NewLine
Write-FileNoBom -Path $loginCfg -Text $loginText

$prevCfg = $env:AWS_CONFIG_FILE
$env:AWS_CONFIG_FILE = $loginCfg
try {
  Write-Host "Opening browser for SSO login..." -ForegroundColor Cyan
  & aws sso login --profile temp-sso-profile
  if ($LASTEXITCODE -ne 0) { throw "SSO login failed." }
  Write-Host ("Successfully logged into Start URL: {0}" -f $SSOStartUrl) -ForegroundColor Green

  $token = Get-SSOAccessToken -SSORegion $SSORegion -SSOStartUrl $SSOStartUrl
  if (-not $token) { throw "Could not resolve a valid SSO access token from cache." }

  Write-Host "Discovering accounts..." -ForegroundColor Cyan
  $accounts = SSO-ListAccounts -Token $token -Region $SSORegion
  $acctCount = ($accounts | Measure-Object).Count
  Write-Host ("Total accounts: {0}" -f $acctCount)

  Write-Host "Enumerating roles..." -ForegroundColor Cyan
  $pairs = @()
  $total = $acctCount; $i = 0
  foreach ($a in $accounts) {
    $i++
    Write-Progress -Activity "Enumerating roles" -Status ("{0}/{1} acct {2}" -f $i,$total,$a.accountId) -PercentComplete ([int](100*$i/$total))
    $roles = SSO-ListRolesForAccount -Token $token -Region $SSORegion -AccountId $a.accountId
    $rc = ($roles | Measure-Object).Count
    Write-Host ("  acct {0}: {1} role(s)" -f $a.accountId, $rc)
    if ($RoleName -eq '*') {
      foreach ($r in $roles) { $pairs += [pscustomobject]@{ accountId = $a.accountId; role = $r } }
    } elseif ($roles -contains $RoleName) {
      $pairs += [pscustomobject]@{ accountId = $a.accountId; role = $RoleName }
    }
  }
  Write-Progress -Activity "Enumerating roles" -Completed
  Write-Host ("Account/role pairs discovered: {0}" -f $pairs.Count)

  if ($pairs.Count -eq 0) {
    if ($RoleName -eq '*') { throw "No roles discovered on any accounts." }
    else { throw ("No accounts expose role '{0}'." -f $RoleName) }
  }

  Write-Host ("Building config: {0}" -f $genCfg) -ForegroundColor Cyan
  $cfgText = Build-ConfigText -AccountRolePairs $pairs -SSOStartUrl $SSOStartUrl -SSORegion $SSORegion -DefaultRegion $DefaultRegion
  Write-FileNoBom -Path $genCfg -Text $cfgText
  Show-ConfigSummary -Path $genCfg

} finally {
  # restore original AWS_CONFIG_FILE even if things blow up
  if ($prevCfg) { $env:AWS_CONFIG_FILE = $prevCfg } else { Remove-Item Env:AWS_CONFIG_FILE -ErrorAction SilentlyContinue }
  $cur = if ($env:AWS_CONFIG_FILE) { $env:AWS_CONFIG_FILE } else { '<unset>' }
  Write-Host ("Restored AWS_CONFIG_FILE -> {0}" -f $cur) -ForegroundColor Yellow
  Remove-Item $loginCfg -ErrorAction SilentlyContinue
}

# Point AWS to the newly generated file
Set-AWSConfigEnv -Path $genCfg -Persist:$Persist

Write-Host "Verifying with aws configure list-profiles..." -ForegroundColor Yellow
aws configure list-profiles
