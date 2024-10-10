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
	git checkout -b $m
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

function git-pushfromnewtemplate{
	param ([string] $issueId, [string] $repoName)
	$currentFolder = Get-Item -Path .

	# rename `my-stack` -> `my-stack-template`
	Rename-Item -Path "$currentFolder\$repoName" -NewName "$repoName-template"
	
	if (Test-Path $repoName-template\node_modules) {
		# remove node_modules rather than copy it
		Remove-Item -Recurse -Force $repoName-template\node_modules
	}

	# clone the repo we will push to
	git clone git@bitbucket.org:aferrydev/$repoName.git
	
	cd $repoName
	
	# switch to new branch
	git checkout -b $issueId
	
	# copy template contents
	Copy-Item -Path "..\$repoName-template\*" -Destination "" -Recurse
	
	# restore pnpm
	pnpm i
	
	# push
	git add .
	git commit -m "Initial commit from project template"
	git push
	cd ..
	Start-Process "https://bitbucket.org/aferrydev/$repoName/pull-requests/new?source=$issueId&t=1"
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

function Invoke-CookieCutter{
	    param (
        [string]$EnvVarName = "DEFAULT"
    )
	$fullEnvName = "COOKIECUTTER_TEMPLATE_$EnvVarName".ToUpper();
	$repoUrl = (Get-Item -Path "Env:$fullEnvName").Value
	Write-Host $fullEnvName;
	Write-Host $repoUrl;
	Write-Command "cookiecutter $repoUrl"
	try {
        cookiecutter $repoUrl
    } catch {
        Write-Output "Failed to run cookiecutter with template '$repoUrl'."
    }
	cookiecutter git@bitbucket.org:aferrydev/cdk-starter-template.git
	
}

function Write-Command{
	param([string] $command)
	
	Write-Host (Get-Location) -ForegroundColor Magenta -NoNewline
	Write-Host "> " -ForegroundColor Magenta -NoNewline
	Write-Host "$command" -ForegroundColor Cyan
}



Clear-Host
Get-ChildItem