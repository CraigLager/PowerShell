$scriptPath = $MyInvocation.MyCommand.Path
$directoryPath = Split-Path -Parent $scriptPath
$envScriptPath = "$directoryPath\env.ps1"

if (Test-Path $envScriptPath) {
    Write-Host "Loading Profile $scriptPath"
    . $envScriptPath
    Write-Host "ENV Loaded"
} else {
    Write-Host "env.ps1 not found"
}

Import-Module posh-git
Write-Host "posh-git Loaded"

New-Alias c code
New-Alias e explorer
New-Alias g git
New-Alias n npm
New-Alias note "C:\Program Files (x86)\Notepad++\Notepad++.exe"
New-Alias p pnpm


New-Alias gct git-commit
function git-commit {
	param ([string] $m)
	git commit -a -m $m
}

New-Alias gph git-push
function git-push{
	git push
}

New-Alias gpl git-pull
function git-pull{
	git pull
}

New-Alias gfh git-fetch
function git-fetch{
	git fetch
}

New-Alias gco git-checkout
function git-checkout {
	param ([string] $m)
	git checkout $m
}

New-Alias gsc git-sync
function git-sync{
	git pull
	git push
}

New-Alias gss git-status
function git-status{
		git status
}

New-Alias grepo git-clone-repo
function git-clone-repo{
	param ([string] $name)
	$prefix = (Get-Item -Path "Env:GIT_REPO_PREFIX").Value
	git clone "$prefix$name.git"
}

New-Alias gacp git-acp
function git-acp {
    param ([string] $m)
    git add .
    git commit -m $m
    git push
}

New-Alias gbh git-branch
function git-branch {
	param ([string] $m)
	git checkout main
	git pull
	git checkout -b $m
}

New-Alias gib New-GitIssueBranch
function New-GitIssueBranch {
    param (
        [string]$IssueNumber
    )

    # Get the branch prefix
    $branchPrefix = Get-IssueBranchName

    if (-not $branchPrefix) {
        Write-Error "Failed to generate branch prefix. Exiting."
        return
    }

    # Construct the full branch name
    $branchName = "$branchPrefix" -replace "{ISSUE_NUMBER}", $IssueNumber

    # Checkout main, pull updates, and create a new branch
    gbh $branchName
}

New-Alias gpr New-PullRequest
function New-PullRequest {
	$currentBranch = git rev-parse --abbrev-ref HEAD
	$currentRepoUrl = git config --get remote.origin.url
	$currentRepo = (($currentRepoUrl -split ":")[1]) -replace ".git", ""
	$pullRequestTemplate = (Get-Item -Path "Env:GIT_PR_TEMPLATE").Value
	$url = $pullRequestTemplate -replace "\{REPO\}", $currentRepo -replace "\{BRANCH\}", $currentBranch
	
	Start-Process $url
}

New-Alias gmain git-main
function git-main {
	git checkout main
	git pull
}

New-Alias go cdls
function cdls{
	param ([string] $path)
	Set-Location $path
	Get-ChildItem
}

New-Alias goo wild-cdls
function wild-cdls{
	param ([string] $path)
	cdls *$path*
}

function Invoke-SubDirectories {
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    # Loop through each subdirectory
    Get-ChildItem -Directory | ForEach-Object {
        # Navigate into the directory
        Set-Location $_.FullName
		
		Write-Command "$Command $Arguments"

        # Combine the command and arguments, and execute it
        try {
            & $Command @Arguments
        } catch {
            Write-Output "Failed to run '$Command $Arguments' in $($_.FullName)." --ForegroundColor Red
        }

        # Navigate back to the parent directory
        Set-Location ..
    }
}


function Get-IssueBranchName {
    # Get the current year and quarter
    $currentYear = (Get-Date).Year
    $shortYear = $currentYear.ToString().Substring(2) # Get the last two digits of the year
    $currentMonth = (Get-Date).Month
    $currentQuarter = [math]::Ceiling($currentMonth / 3)

    # Get the ISSUE_BRANCH_PREFIX environment variable
    $prefix = $env:GIT_ISSUE_BRANCH_TEMPLATE

    # Check if the variable is set
    if (-not $prefix) {
        Write-Error "The environment variable 'GIT_ISSUE_BRANCH_TEMPLATE' is not set."
        return
    }

    # Replace placeholders with current year (short) and quarter
    $resolvedPrefix = $prefix -replace '{QTR}', $currentQuarter -replace '{YEAR}', $shortYear

    return $resolvedPrefix
}


function Write-Command{
	param([string] $command)
	
	Write-Host (Get-Location) -ForegroundColor Magenta -NoNewline
	Write-Host "> " -ForegroundColor Magenta -NoNewline
	Write-Host "$command" -ForegroundColor Cyan
}

function Invoke-Refresh{
	Get-Process -Id $PID | Select-Object -ExpandProperty Path | ForEach-Object { Invoke-Command { & "$_" } -NoNewScope }
}

Clear-Host
Get-ChildItem