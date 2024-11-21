Best used with [Windows Terminal](https://apps.microsoft.com/detail/9n0dx20hk701?hl=en-US&gl=US), provides shortcuts and helper functions for engineers/developers

# Usage

## General/Powershell

* `c`: alias `code`
* `e`: alias `explorer`
* `g`: alias `git`
* `n`: alias `npm`
* `p`: alias pnpm
* `note`: alias `"C:\Program Files (x86)\Notepad++\Notepad++.exe"`

* `go <path>`: navigate to path, print directory
* `goo <partial path>`: navigates to a path based on a wildcard `*<partial path>*` match, example `goo serv` could navigate to `my-service-production`
* `Invoke-SubDirectories <command>`: invokes the command in each subdirectory of the current directory

## Git

### Shortcuts

Pattern is usually `g{first letter of command}{last letter of command}`

* `gph`: `git push`
* `gpl`: `git pull`
* `gfh`: `git fetch`
* `gco <branch>`: `git checkout <branch>`
* `gss`: `git status`

### Helpers

* `gct "<message>"`: `git commit -a -m "<message>"`
* `gsc`: pulls and then pushes
* `gacp "<message>"`: adds all files, commits with message, push
* `gbh <branch>`: `git checkout -b <branch>`
* `gmain`: checks out the latest version of `main` branch
* `grepo <repo name>`: `git clone {env.GIT_REPO_PREFIX}<repo name>

## Niche Functions

* `Invoke-Git-PushNewTemplate <new branch name> <existing repo name>`: for use when working from a cookie cutter template it:
    * renames the template folder
    * clones the repo which we want to push to
    * switches the newly cloned repo to the new branch
    * copies items from the template into the repo
    * pushes the repo
* `Invoke-CookieCutter <template name>`: invokes cookie cutter against a url in environment variable named `COOKIECUTTER_TEMPLATE_<template name>`. Defaults to `DEFAULT`

# Setup

* Clone to your `Documents` folder, creating `Documents/PowerShell`
* Create `env.ps1` file to set environment varialbes

### env.ps1 example

```
$Env:NPM_TOKEN = 'npm_xyz'
$env:COOKIECUTTER_TEMPLATE_DEFAULT = 'git@bitbucket.org:myorg/my-repo.git'
$env:COOKIECUTTER_TEMPLATE_SOMEPROJECT = 'git@bitbucket.org:myorg/some-project.git'
```
