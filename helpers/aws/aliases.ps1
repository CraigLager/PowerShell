# aliases.ps1
#requires -Version 5.1
# Resolves to the folder this file lives in (…\helpers\aws)
$script:AwsHelperRoot = Split-Path -Parent $PSCommandPath

function Invoke-AWSGenerateSSOProfiles {
    <#
    .SYNOPSIS
      Wrapper that forwards parameters to generatessoprofiles.ps1
    .PARAMETER RoleName
    .PARAMETER SSOStartUrl
    .PARAMETER SSORegion
    .PARAMETER DefaultRegion
    .PARAMETER Persist
      If your script supports it; forwarded as-is.
    #>
    [CmdletBinding()]
    param(
        [string]$RoleName,
        [string]$SSOStartUrl,
        [string]$SSORegion,
        [string]$DefaultRegion,
        [switch]$Persist
    )

    $scriptPath = Join-Path $script:AwsHelperRoot 'generatessoprofiles.ps1'
    if (-not (Test-Path $scriptPath)) { throw "Script not found: $scriptPath" }

    # Forward all bound params by name; unbound remain defaulted by your script
    & $scriptPath @PSBoundParameters
}

# Optional short alias
Set-Alias gen-sso Invoke-AWSGenerateSSOProfiles
