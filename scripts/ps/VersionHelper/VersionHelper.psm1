$Script:Config = . { [CmdletBinding()] param() return $MyInvocation.MyCommand.Module.PrivateData.Settings }

enum VersionPart {
  Major
  Minor
  Patch
  Revision
}

enum ProjectType {
  Node
}

function Get-VersionConfiguration {
  [CmdletBinding()]
  param(
    [string]
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
      throw "Unsupported version parts detected in configuration: $($unsupportedValues -join ', '). Only follow values are supported: $($supportedValues -join ', ')"
    }

    $labelsWithDuplicatedValues = $configuration.GetEnumerator() | Where-Object { ($_.Value | Group-Object | Where-Object { $_.Count -gt 1 }).Count -gt 0 }

    if ($labelsWithDuplicatedValues.Length -gt 0) {
      throw "Label can't contain duplicated version parts to increment. Affected labels: $(($labelsWithDuplicatedValues.Key | Sort-Object) -join ', ')"
    }

    Write-Output $configuration
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

function Get-IncrementingVersionParts {
  [CmdletBinding()]
  param(
    [int]
    $PullRequestId,
    
    [string]
    $Owner,
    
    [string]
    $Repository,

    [string]
    $VersionConfigurationPath,

    [string]
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

function Get-PullRequestNumbers {
  [CmdletBinding()]
  param(
    [string]
    $SHA,
      
    [string]
    $Owner,
      
    [string]
    $Repository,

    [string]
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

    Write-Host "Getting all relatd PRs for SHA '$SHA'"
    $prs = Invoke-RestMethod -Method Get -Uri ($getLabelsUrl -f $Owner, $Repository, $SHA) -Headers $headers

    Write-Host "Found '$($prs.Length)' PRs"

    Write-Output ($prs | ForEach-Object { $_.number }) -NoEnumerate
  }

  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}

function Get-Version {
  [CmdletBinding()]
  param(
    [ProjectType]
    $ProjectType
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

function Set-Version {
  [CmdletBinding()]
  param(
    [ProjectType]
    $ProjectType,

    [switch]
    $IncrementMajor,

    [switch]
    $IncrementMinor,

    [switch]
    $IncrementPatch,

    [switch]
    $IncrementRevision,

    [string]
    $Suffix
  )

  begin {
    Write-Host "[$($MyInvocation.InvocationName)] - begin"
    $parsedVersionRegex = "(?<major>\d+)\.(?<minor>\d+)(\.(?<patch>\d+))?(\.(?<revision>\d+))?(?<suffix>.*)"
  }

  process {
    $currentVersion = Get-Version -ProjectType $ProjectType

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

function Submit-NewVersionLabel {
  [CmdletBinding()]
  param (
    [ProjectType]
    $ProjectType,

    [string]
    $SHA,
    
    [string]
    $Owner,
    
    [string]
    $Repository,

    [VersionPart]
    $DefaultIncrementingPart,

    [string]
    $VersionConfigurationPath,

    [string]
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

    $setVersionParams = @{
      ProjectType = $ProjectType
    }

    if ($relatedPRs.Length -eq 0) {
      $setVersionParams["Increment$((Get-Culture).TextInfo.ToTitleCase($DefaultIncrementingPart))"] = $true;
    }
    else {
      Get-IncrementingVersionParts -PullRequestId $relatedPRs[0] -Owner $Owner -Repository $Repository -VersionConfigurationPath $VersionConfigurationPath -AuthToken $AuthToken | ForEach-Object {
        $setVersionParams["Increment$((Get-Culture).TextInfo.ToTitleCase($_))"] = $true;
      } | Out-Null
    }

    $newVersion = Set-Version @setVersionParams

    Write-Output $newVersion
  }
  
  end {
    Write-Host "[$($MyInvocation.InvocationName)] - end"
  }
}