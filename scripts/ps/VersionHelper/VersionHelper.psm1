$Script:Config = . { [CmdletBinding()] param() return $MyInvocation.MyCommand.Module.PrivateData.Settings }

<#
.SYNOPSIS
  List of supported parts of version to increment.
#>
enum VersionPart {
  Major
  Minor
  Patch
  Revision
}

<#
.SYNOPSIS
  List of supported types of projects.
#>
enum ProjectType {
  Node
  Posh
}

<#
.SYNOPSIS
  Reads and validates version configuration from specified file and returns it.
.EXAMPLE
  Get-VersionConfiguration -Path "C:\version-configuration.json"
.OUTPUTS
  Returns hashtable where key is a PR label and value is an array of parts need to be incremented in version.
#>
function Get-VersionConfiguration {
  [CmdletBinding()]
  param(
    [string]
    # Specifies the path to version configuration file.
    $Path
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
  }

  process {
    $returnDefaultConfiguration = $false

    if (-not([string]::IsNullOrEmpty($Path)) -and -not(Test-Path $Path)) {
      throw "Configuration path '$Path' doesn't exist"
    }

    if ([string]::IsNullOrEmpty($Path)) {
      Write-Host "Path is not specified, default configuration will be used"
      $returnDefaultConfiguration = $true
    }

    $configuration = $null

    if ($returnDefaultConfiguration -eq $false) {
      Write-Host "Getting configuration from file '$($Path)'..."
      $configuration = (Get-Content -Path $Path | ConvertFrom-JSON -AsHashtable)
    }
    else {
      $configuration = $Script:Config.DefaultVersionConfiguration
    }

    Write-Host "Validating the configuration..."

    $allValues = $configuration.Values
    $supportedValues = [VersionPart].GetEnumNames()
    $unsupportedValues = $allValues | ForEach-Object { $_ } | Where-Object { $supportedValues -notcontains $_ } | Sort-Object -Unique

    if ($unsupportedValues.Length -gt 0) {
      throw "Unsupported parts detected in configuration: $($unsupportedValues -join ', '). Only follow values are supported: $($supportedValues -join ', ')"
    }

    $labelsWithDuplicatedValues = $configuration.GetEnumerator() | Where-Object { ($_.Value | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0 }

    if ($labelsWithDuplicatedValues.Length -gt 0) {
      throw "Label can't contain duplicated parts to increment. Affected labels: $(($labelsWithDuplicatedValues.Key | Sort-Object) -join ', ')"
    }

    Write-Output $configuration
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

<#
.SYNOPSIS
  Returns incrementing parts of version based on labels in related PR.
.NOTES
  If parameter AuthToken is not specified then all API requests will be sent to GitHub anonymously. It applies some limitations:
  - you cannot use this method to work with private repositories;
  - GitHub has some quota for anonymous API requests, so such requests will be rejected.
.EXAMPLE
  Get-IncrementingParts -PullRequestId 108 -Owner "Alex" -Repository "WarfaceAim" -VersionConfigurationPath "C:\version-configuration.json"
  Get-IncrementingParts -PullRequestId 108 -Owner "Alex" -Repository "WarfaceAim" -VersionConfigurationPath "C:\version-configuration.json" -AuthToken "abcdef..."
.OUTPUTS
  Returns array of version parts need to be incremented.
#>
function Get-IncrementingParts {
  [CmdletBinding()]
  param(
    [int]
    # Specifies the id of pull request.
    $PullRequestId,
    
    [string]
    # Specifies the owner of repository the pull request was open against.
    $Owner,
    
    [string]
    # Specifies the repository name the pull request was open against.
    $Repository,

    [string]
    # Specifies the path to version configuration file.
    $VersionConfigurationPath,

    [string]
    # (Optional) Specifies the authentication token to invoke GitHub API.
    $AuthToken
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"

    $labelsConfiguration = Get-VersionConfiguration -Path $VersionConfigurationPath
    $getLabelsUrl = "https://api.github.com/repos/{0}/{1}/issues/{2}/labels"
  }

  process {
    Write-Host "Getting labels for PR '$PullRequestId'"

    $headers = @{}
    if (-not([string]::IsNullOrWhiteSpace($AuthToken))) {
      $headers["Authorization"] = "Bearer $AuthToken"
    }

    $prLabels = Invoke-RestMethod -Method Get -Uri ($getLabelsUrl -f $Owner, $Repository, $PullRequestId) -Headers $headers

    if ($null -eq $prLabels -or $prLabels.Length -eq 0) {
      throw "The PR doesn't contain any label"
    }

    Write-Host "The PR contains follow labels: $(($prLabels | ForEach-Object { $_.name }) -join ", ")"

    $supportedLabels = $prLabels | Where-Object { $labelsConfiguration.Keys -contains $_.name }

    if ($supportedLabels.Count -eq 0) {
      throw "You must specify one of following labels in PR: $($labelsConfiguration.Keys -join ", ")"
    }

    if ($supportedLabels.Count -gt 1) {
      throw "Only one of following labels can be used in PR: $($labelsConfiguration.Keys -join ", ")"
    }

    Write-Output ($supportedLabels | Select-Object -First 1 | ForEach-Object { $labelsConfiguration[$_.name] }) -NoEnumerate
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

<#
.SYNOPSIS
  Returns array of Pull Requests numbers linked to specified SHA.
.NOTES
  If parameter AuthToken is not specified then all API requests will be sent to GitHub anonymously. It applies some limitations:
  - you cannot use this method to work with private repositories;
  - GitHub has some quota for anonymous API requests, so such requests will be rejected.
.EXAMPLE
  Get-PullRequestNumbers -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" 
  Get-PullRequestNumbers -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" -AuthToken "abcdef..."
.OUTPUTS
  Returns array of version parts need to be incremented.
#>
function Get-PullRequestNumbers {
  [CmdletBinding()]
  param(
    [string]
    # Specifies the SHA the pull request numbers are needed to be found for.
    $SHA,
      
    [string]
    # Specifies the owner of repository the SHA was submitted to.
    $Owner,
      
    [string]
    # Specifies the repository name the SHA was submitted to.
    $Repository,

    [string]
    # (Optional) Specifies the authentication token to invoke GitHub API.
    $AuthToken
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
    $getLabelsUrl = "https://api.github.com/repos/{0}/{1}/commits/{2}/pulls"
  }

  process {

    $headers = @{}
    if (-not([string]::IsNullOrWhiteSpace($AuthToken))) {
      $headers["Authorization"] = "Bearer $AuthToken"
    }

    Write-Host "Getting all related PRs for SHA '$SHA'"
    $prs = Invoke-RestMethod -Method Get -Uri ($getLabelsUrl -f $Owner, $Repository, $SHA) -Headers $headers

    Write-Host "Found '$($prs.Length)' PRs"

    Write-Output ($prs | ForEach-Object { $_.number }) -NoEnumerate
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

<#
.SYNOPSIS
  Returns version for specified project type.
.EXAMPLE
  Get-Version -ProjectType Node
  Get-Version -ProjectType Posh -PowerShellModuleName MyModule
  Get-Version -ProjectType Posh -PowerShellModuleName C:\Modules\MyModule.psd1
.OUTPUTS
  Returns string version.
#>
function Get-Version {
  [CmdletBinding()]
  param(
    [ProjectType]
    # Specified the type of project.
    $ProjectType,

    [string]
    # Specified the PowerShell module name.
    $PowerShellModuleName
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
  }

  process {
    $version = [string]::Empty

    switch ($ProjectType) {
      ([ProjectType]::Node) {
        Write-Host "Getting version from 'package.json'"

        $version = (. npm pkg get version) -replace """", ""

        if ($LASTEXITCODE -ne 0) {
          throw "Something went wrong while getting version from 'package.json'"
        }

        if ([string]::IsNullOrWhiteSpace($version) -or $version -eq "{}") {
          throw "Version doesn't exist in 'package.json'"
        }
      }

      ([ProjectType]::Posh) {
        if ([string]::IsNullOrWhiteSpace($PowerShellModuleName)) {
          throw "Parameter 'PowerShellModuleName' is not specified"
        }

        $psModule = Get-Module -Name $PowerShellModuleName -ListAvailable

        if ($psModule.Length -eq 0) {
          throw "There is no module with name '$($PowerShellModuleName)'"
        }

        if ($psModule.Length -gt 1) {
          throw "There are $($psModule.Count) modules with name '$($PowerShellModuleName)'"
        }

        Write-Host "Getting version from manifest of module '$($PowerShellModuleName)'"

        $version = $psModule.Version.ToString()

        if ([string]::IsNullOrWhiteSpace($version)) {
          throw "Version doesn't exist in manifest of module '$($PowerShellModuleName)'"
        }
      }

      Default {
        throw "Project type '$ProjectType' is unsupported"
      }
    }

    Write-Output $version
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

<#
.SYNOPSIS
  Increments the version for specified project type and saves it.
.NOTES
  Please be aware of following logic implemented:
  - incrementing major part zeroes following parts of the version: minor and patch;
  - incrementing minor part zeroes patch part of the version.
  If suffix is not specified then it doesn't mean the existing suffix will be removed.
  To remove existing suffix you need to pass [string]::Empty to parameter Suffix.
.EXAMPLE
  Set-IncrementedVersion -ProjectType Node -IncrementMajor -IncrementRevision
  Set-IncrementedVersion -ProjectType Node -IncrementPatch -Suffix "-RC1"
  Set-IncrementedVersion -ProjectType Posh -PowerShellModuleName MyModule -IncrementMajor -IncrementRevision
  Set-IncrementedVersion -ProjectType Posh -PowerShellModuleName C:\Modules\MyModule.psd1 -IncrementPatch -Suffix "-RC1"

.OUTPUTS
  Returns incremented string version.
#>
function Set-IncrementedVersion {
  [CmdletBinding()]
  param(
    [ProjectType]
    # Specifies the type of project.
    $ProjectType,

    [string]
    # Specified the PowerShell module name.
    $PowerShellModuleName,

    [switch]
    # (Optional) Indicates whether the major part of version must be incremented.
    $IncrementMajor,

    [switch]
    # (Optional) Indicates whether the minor part of version must be incremented.
    $IncrementMinor,

    [switch]
    # (Optional) Indicates whether the patch part of version must be incremented.
    $IncrementPatch,

    [switch]
    # (Optional) Indicates whether the revision part of version must be incremented.
    $IncrementRevision,

    [string]
    # (Optional) Specified the suffix to be added to the incremented version.
    $Suffix
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
    $parsedVersionRegex = "(?<major>\d+)\.(?<minor>\d+)(\.(?<patch>\d+))?(\.(?<revision>\d+))?(?<suffix>.*)"
  }

  process {
    $currentVersion = Get-Version -ProjectType $ProjectType -PowerShellModuleName $PowerShellModuleName

    $newVersion = [string]::Empty

    Write-Host "Version currently contains value '$currentVersion'"

    $parsedVersionMatch = $currentVersion -match $parsedVersionRegex

    if (!$parsedVersionMatch) {
      throw "The version has incorrect format. Supported format: <major>.<minor>[.<patch>.<patch><suffix>]"
    }

    $newMajor = [int]$Matches["major"]
    $newMinor = [int]$Matches["minor"]
    $newPatch = $(if ($Matches["patch"]) { [int]$Matches["patch"] })
    $newRevision = $(if ($Matches["revision"]) { [int]$Matches["revision"] })
    $newSuffix = $Matches["suffix"]

    if ($IncrementMajor.IsPresent -and $null -ne $newMajor) {
      $newMajor++
      $newMinor = 0
      $newPatch = 0
    }

    if ($IncrementMinor.IsPresent -and $null -ne $newMinor) {
      $newMinor++
      $newPatch = 0
    }

    if ($IncrementPatch.IsPresent -and $null -ne $newPatch) {
      $newPatch++
    }

    if ($IncrementRevision.IsPresent -and $null -ne $newRevision) {
      $newRevision++
    }

    if ($null -ne $Suffix) {
      $newSuffix = $Suffix
    }

    $newVersion = "{0}{1}{2}{3}{4}" -f $newMajor,
    ".$newMinor",
    $(if ($null -ne $newPatch) { ".$newPatch" } else { [string]::Empty }),
    $(if ($null -ne $newRevision) { ".$newRevision" } else { [string]::Empty }),
    $(if ($null -ne $newSuffix) { $newSuffix } else { [string]::Empty })

    Write-Host "New version is '$newVersion'"

    switch ($ProjectType) {
      ([ProjectType]::Node) {
        Write-Host "Saving new version in 'package.json'"

        (& npm version --no-commit-hooks --no-git-tag-version $newVersion) | Out-Null

        if ($LASTEXITCODE -ne 0) {
          throw "Something went wrong while saving new version in 'package.json'"
        }
      }

      ([ProjectType]::Posh) {
        if ([string]::IsNullOrWhiteSpace($PowerShellModuleName)) {
          throw "Parameter 'PowerShellModuleName' is not specified"
        }

        $psModule = Get-Module -Name $PowerShellModuleName -ListAvailable

        if ($psModule.Length -eq 0) {
          throw "There is no module with name '$($PowerShellModuleName)'"
        }

        if ($psModule.Length -gt 1) {
          throw "There are $($psModule.Count) modules with name '$($PowerShellModuleName)'"
        }

        Write-Host "Saving new version in manifest of module '$($PowerShellModuleName)'"

        $lineToModifyRegex = "^\s*ModuleVersion\s*=\s*('|"")$currentVersion('|"")\s*$"
        $found = $false

        (Get-Content -Path $psModule.Path | 
          Foreach-Object { 
            if ($found -eq $false -and $_ -match $lineToModifyRegex) {
              $found = $true
              Write-Output ($_ -replace ([Regex]::Escape($currentVersion)), $newVersion)
            } else {
              Write-Output $_
            }
          }) | Set-Content $psModule.Path -Force

        if ($found -eq $false) {
          throw "Version related line was not found in file $($psModule.Path)"
        }

        Test-ModuleManifest -Path $psModule.Path -ErrorAction Stop | Out-Null
      }
  
      Default {
        throw "Project type '$ProjectType' is unsupported"
      }
    }

    Write-Output $newVersion
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

<#
.SYNOPSIS
  Reads the existing version for specified project type, increments accordingly and saves it.
  This is the main function of incrementing logic.
.NOTES
  If parameter AuthToken is not specified then all API requests will be sent to GitHub anonymously. It applies some limitations:
  - you cannot use this method to work with private repositories;
  - GitHub has some quota for anonymous API requests, so such requests will be rejected.
.EXAMPLE
  Submit-NewVersionLabel -ProjectType Node -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" -DefaultIncrementingPart "Revision" -VersionConfigurationPath "C:\version-configuration.json"
  Submit-NewVersionLabel -ProjectType Node -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" -DefaultIncrementingPart "Revision" -VersionConfigurationPath "C:\version-configuration.json" -AuthToken "abcdef..."
  Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName MyModule -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" -DefaultIncrementingPart "Revision" -VersionConfigurationPath "C:\version-configuration.json" -AuthToken "abcdef..."
  Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName C:\Modules\MyModule.psd1 -SHA "abcdef..." -Owner "Alex" -Repository "WarfaceAim" -DefaultIncrementingPart "Revision" -VersionConfigurationPath "C:\version-configuration.json" -AuthToken "abcdef..."
.OUTPUTS
  Returns incremented string version.
#>
function Submit-NewVersionLabel {
  [CmdletBinding()]
  param (
    [ProjectType]
    # Specifies the type of project.
    $ProjectType,

    [string]
    # Specified the PowerShell module name.
    $PowerShellModuleName,

    [string]
    # Specifies the SHA the pull request numbers are needed to be found for.
    $SHA,
    
    [string]
    # Specifies the owner of repository the SHA was submitted to.
    $Owner,
    
    [string]
    # Specifies the repository name the SHA was submitted to.
    $Repository,

    [VersionPart]
    # (Optional) Specifies the default incrementing part.
    # It's used in case there are no related pull requests for specified SHA.
    $DefaultIncrementingPart,

    [string]
    # Specifies the path to version configuration file.
    $VersionConfigurationPath,

    [string]
    # (Optional) Specifies the authentication token to invoke GitHub API.
    $AuthToken
  )
  
  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
  }
  
  process {
    $relatedPRs = Get-PullRequestNumbers -SHA $SHA -Owner $Owner -Repository $Repository -AuthToken $AuthToken | Select-Object -First 1

    if ($relatedPRs.Length -eq 0) {
      Write-Host "There is no PRs linked to commit '$SHA'"
      if ($null -eq $DefaultIncrementingPart) {
        Write-Host "No default version part to increment was specified, skipping creating new version label"
        exit 0
      }
      else {
        Write-Host "Version part '$DefaultIncrementingPart' will be incremented"
      }
    }

    $setIncrementedVersionParams = @{
      ProjectType = $ProjectType
      PowerShellModuleName = $PowerShellModuleName
    }

    if ($relatedPRs.Length -eq 0) {
      $setIncrementedVersionParams["Increment$((Get-Culture).TextInfo.ToTitleCase($DefaultIncrementingPart))"] = $true;
    }
    else {
      Get-IncrementingParts -PullRequestId $relatedPRs[0] -Owner $Owner -Repository $Repository -VersionConfigurationPath $VersionConfigurationPath -AuthToken $AuthToken | ForEach-Object {
        $setIncrementedVersionParams["Increment$((Get-Culture).TextInfo.ToTitleCase($_))"] = $true;
      } | Out-Null
    }

    $newVersion = Set-IncrementedVersion @setIncrementedVersionParams

    Write-Output $newVersion
  }
  
  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}