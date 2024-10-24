Best used with [Windows Terminal](https://apps.microsoft.com/detail/9n0dx20hk701?hl=en-US&gl=US)

# Setup

* Clone to your `Documents` folder, creating `Documents/PowerShell`
* Create a `env.ps1` file to set environment varialbes

### env.ps1 example

```
$Env:NPM_TOKEN = 'npm_xyz'
$env:COOKIECUTTER_TEMPLATE_DEFAULT = 'git@bitbucket.org:aferrydev/cdk-starter-template.git'
$env:COOKIECUTTER_TEMPLATE_CDKSTARTER = 'git@bitbucket.org:aferrydev/cdk-starter-template.git'
```

# Usage

## Git

### Shortcuts

Pattern is usually `g{first letter of command}{last letter of command}`

* `gph`: `git push`
* `gpl`: `git pull`
* `gfh`: `git fetch`
* `gco <branch>`: `git checkout <branch>`
* `gss`: `git status`

### Helpers

* `gct "message"`: `git commit -a -m "message"`
* `gsc`: pulls and then pushes
* `gacp "message"`: adds all files, commits with message, push
* `gbh <branch>`: `git checkout -b <branch>`
* `gmain`: checks out the latest version of `main` branch

### Workflow Functions

* `git-pushfromnewtemplate <new branch name> <existing repo name>`: for use when working from a cookie cutter template it:
    * renames the template folder
    * clones the repo which we want to push to
    * switches the newly cloned repo to the new branch
    * copies items from the template into the repo
    * pushes the repo
* `Invoke-SubDirectories <command>`: invokes the command in each subdirectory of the current directory
* `Invoke-CookieCutter <template name>`: invokes cookie cutter against a url in environment variable named `COOKIECUTTER_TEMPLATE_<template name>`. Defaults to `DEFAULT`



## Powershell

* `go <path>`: navigate to path, print directory
* `goo <partial path>`: navigates to a path based on a wildcard `*<partial path>*` match, example `goo serv` could navigate to `my-service-production`
