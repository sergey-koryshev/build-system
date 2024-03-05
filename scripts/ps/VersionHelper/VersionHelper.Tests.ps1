Import-Module VersionHelper -Force

Describe "Unit Tests for module 'VersionHelper'" -Tag "UnitTest" {

  Context "Unit Tests for method 'Get-VersionConfiguration'" {

    BeforeAll {
      $fakePath = "C:\some-existing-file.json"
      $fakeNotExistingPath = "C:\some-not-existing-file.json"
  
      Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
        $Path -eq $fakeNotExistingPath
      } -ModuleName VersionHelper

      Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
        $Path -eq $fakePath
      } -ModuleName VersionHelper

      Mock -CommandName Write-Host -MockWith { } -ModuleName VersionHelper
    }

    BeforeEach {
      Mock -CommandName Get-Content -MockWith { } -ModuleName VersionHelper
    }

    It "Should throw excpetion if provided path doesn't exist" {
      { Get-VersionConfiguration -Path $fakeNotExistingPath } | Should -Throw "Configuration path '$fakeNotExistingPath' doesn't exist"
    }

    It "Should return default configuration if path was not provided" {
      $expected = @{
        "bug"              = @("Patch")
        "enhancement"      = @("Minor")
        "breaking changes" = @("Major")
      }

      $actual = Get-VersionConfiguration

      ($actual | ConvertTo-Json) | Should -Be ($expected | ConvertTo-Json)
    }

    It "Should return exception if configuration contains unsupported version parts" {
      Mock -CommandName Get-Content -MockWith {
        @{
          "bug"           = @("Patch", "Unsupported1")
          "enhancement"   = @("Unsupported1", "Minor")
          "breaking changes" = @("Major", "Unsupported2")
        } | ConvertTo-Json
      } -ModuleName VersionHelper

      { Get-VersionConfiguration -Path $fakePath } | Should -Throw "Unsupported version parts detected in configuration: Unsupported1, Unsupported2. Only follow values are supported: Major, Minor, Patch, Revision"
    }

    It "Should return excpetion if configuration contains duplicated version parts" {
      Mock -CommandName Get-Content -MockWith {
        @{
          "bug"           = @("Patch", "Patch")
          "enhancement"   = @("Minor", "Minor")
          "special label" = @("Revision")
        } | ConvertTo-Json
      } -ModuleName VersionHelper

      { Get-VersionConfiguration -Path $fakePath } | Should -Throw "Label can't contain duplicated version parts to increment. Affected labels: bug, enhancement"
    }

    It "Should return configuration from specified file" {
      $expected = @{
        "bug"           = @("Patch")
        "special label" = @("Revision")
        "enhancement"   = @("Minor")
      }

      Mock -CommandName Get-Content -MockWith {
        $expected | ConvertTo-Json
      } -ModuleName VersionHelper

      $actual = Get-VersionConfiguration -Path $fakePath

      ([System.Collections.SortedList]$actual | ConvertTo-Json) | Should -Be ([System.Collections.SortedList]$expected | ConvertTo-Json)
    }
  }
}

Describe "e2e tests for module 'VersionHelper'" {

  BeforeAll {
    $originalWorkDirectory = Get-Location
    Set-Location -Path "TestDrive:\\"

    $fakeSHA = New-Guid
    $fakeOwner = New-Guid
    $fakeRepository = New-Guid
    $versionConfigPath = "TestDrive:\version-config.json"
    $projectFile = "TestDrive:\package.json"
    $fakeAuthToken = New-Guid

    @{
      "bug"              = @("Patch")
      "enhancement"      = @("Minor")
      "breaking changes" = @("Major")
    } | ConvertTo-Json > $versionConfigPath

    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          number = 108108108
        }
      )
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/commits/{2}/pulls" -f $fakeOwner, $fakeRepository, $fakeSHA)
    } -ModuleName VersionHelper

    Mock -CommandName Write-Host -MockWith { } -ModuleName VersionHelper
  }

  AfterAll {
    Set-Location $originalWorkDirectory
  }

  BeforeEach {
    Mock -CommandName Invoke-RestMethod -MockWith { 
      @()
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, 108108108)
    } -ModuleName VersionHelper

    @{
      "version" = "2.3.4"
    } | ConvertTo-Json > $projectFile
  }

  It "Should increment major version" {
    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          name = "breaking changes"
        }
      )
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, 108108108)
    } -ModuleName VersionHelper

    Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
    
    $actual = Get-Version -ProjectType Node
    $actual | Should -Be "3.0.0"
  }

  It "Should increment minor version" {
    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          name = "enhancement"
        }
      )
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, 108108108)
    } -ModuleName VersionHelper

    Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
    
    $actual = Get-Version -ProjectType Node
    $actual | Should -Be "2.4.0"
  }

  It "Should increment patch version" {
    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          name = "bug"
        }
      )
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, 108108108)
    } -ModuleName VersionHelper

    Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
    
    $actual = Get-Version -ProjectType Node
    $actual | Should -Be "2.3.5"
  }

  It "Should propagate authorization token to all Invoke-RestMethod calls" {
    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          name = "bug"
        }
      )
    } -ParameterFilter {
      $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, 108108108)
    } -ModuleName VersionHelper

    Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -AuthToken $fakeAuthToken | Out-Null
    
    Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter {
      ($Headers | ConvertTo-Json) -eq (@{ Authorization = "Bearer $fakeAuthToken"} | ConvertTo-Json)
    } -Times 2 -ModuleName VersionHelper
  }
}