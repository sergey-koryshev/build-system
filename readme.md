# Build System

Set of scripts and GitHub workflows which helps to build and manage projects during CI.

## Folders Structure

- `scripts` - folder where scripts are located;
  - `ps` - the folder is dedicated to store PowerShell related scripts.

## Reusable Workflows

### Create Version Label

**Path:** `.github/workflows/create-version-label.yml`

Increments version of specified project and submit it to repository with commit:

```
[automated] Bumped My App version to 1.0.1 [skip ci]
```

and tag:

```
v1.0.1
```

**Input Parameters:**

- **REPO_TOKEN** - (secret) token with write permissions to repository;
- **app-name** - project name;
- **project-type** - project type: Node, Posh, Custom;
- **version-configuration-path** - full path to version configuration.
- **posh-module-name** - name of powershell module, needs to be specified in case of project type `Posh`;
- **posh-custom-module-path** - path to powershell module with custom logic to get/set version, needs to be specified in case of project type `Custom`;
- **skip-tag** - indicates if wether the workflow will create tag or not;
- **root-path** - root path of target project;
- **scripts-ref** - reference for version of scripts to use with the workflow, default value: `master`;

**Notes**

If you specify project type as `Custom` then you need to specify path to custom `PS` module which must have the following functions implemented:

```posh
function Get-Version {
  [CmdletBinding()]
  [OutputType([string])]
  param ()

  process {
    ...
  }
}

function Set-Version {
  [CmdletBinding()]
  param (
    [string]
    $OldVersion,

    [string]
    $NewVersion
  )
  
  process {
    ...
  }
}
```

### Pull Request Label Checker

**Path:** `.github/workflows/pr-label-checker.yml`

Checks that a PR contains labels specified in version configuration to ensure that version will be incremented.

**Input Parameters:**

- **version-configuration-path** - path to version configuration.
- **scripts-ref** - reference for version of scripts to use with the workflow, default value: `master`;

## PowerShell Scripts

### VersionHelper

This is a PS module which helps with incrementing version of specified project.

**Functions:**

- **Submit-NewVersionLabel** - reads the existing version for specified project type, increments accordingly and saves it. This is the main function of incrementing logic. More information: `Get-Help Submit-NewVersionLabel`.
- **Get-IncrementingParts** - returns incrementing parts of version based on labels in related PR. More information: `Get-Help Get-IncrementingParts`.
- **Get-VersionConfiguration** - reads and validates version configuration from specified file and returns it. More information: `Get-Help Get-VersionConfiguration`.
- **Get-PullRequestNumbers** - returns array of Pull Requests numbers linked to specified SHA. More information: `Get-Help Get-PullRequestNumbers`.
- **Get-Version** - returns version for specified project type. More information: `Get-Help Get-Version`.
- **Set-IncrementedVersion** - Increments the version for specified project type and saves it. More information: `Get-Help Set-IncrementedVersion`.