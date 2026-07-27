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

    It "Should throw exception if provided path doesn't exist" {
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

    It "Should return exception if configuration contains unsupported parts" {
      Mock -CommandName Get-Content -MockWith {
        @{
          "bug"           = @("Patch", "Unsupported1")
          "enhancement"   = @("Unsupported1", "Minor")
          "breaking changes" = @("Major", "Unsupported2")
        } | ConvertTo-Json
      } -ModuleName VersionHelper

      { Get-VersionConfiguration -Path $fakePath } | Should -Throw "Unsupported parts detected in configuration: Unsupported1, Unsupported2. Only follow values are supported: Major, Minor, Patch, Revision, Suffix"
    }

    It "Should return exception if configuration contains duplicated parts to increment" {
      Mock -CommandName Get-Content -MockWith {
        @{
          "bug"           = @("Patch", "Patch")
          "enhancement"   = @("Minor", "Minor")
          "special label" = @("Revision")
        } | ConvertTo-Json
      } -ModuleName VersionHelper

      { Get-VersionConfiguration -Path $fakePath } | Should -Throw "Label can't contain duplicated parts to increment. Affected labels: bug, enhancement"
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
    $fakeAuthToken = New-Guid
    $fakePRNumber = 108

    @{
      "bug"              = @("Patch")
      "enhancement"      = @("Minor")
      "breaking changes" = @("Major")
      "misc"             = @("Revision")
      "suffix"           = @("Suffix")
      "suffix-patch"     = @("Suffix", "Patch")
    } | ConvertTo-Json > $versionConfigPath

    Mock -CommandName Invoke-RestMethod -MockWith { 
      @(
        @{
          number = 108
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

  Describe "General tests for method 'Submit-NewVersionLabel'" {
    BeforeEach {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            number = 108
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/commits/{2}/pulls" -f $fakeOwner, $fakeRepository, $fakeSHA)
      } -ModuleName VersionHelper

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      @{
        "version" = "2.3.4"
      } | ConvertTo-Json > "TestDrive:\package.json"
    }

    It "Should propagate authorization token to all Invoke-RestMethod calls" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -AuthToken $fakeAuthToken | Out-Null
      
      Should -Invoke -CommandName Invoke-RestMethod -ParameterFilter {
        ($Headers | ConvertTo-Json) -eq (@{ Authorization = "Bearer $fakeAuthToken"} | ConvertTo-Json)
      } -Times 2 -ModuleName VersionHelper
    }

    It "Should override increment parts" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -AuthToken $fakeAuthToken -OverrideIncrementParts @("Minor") | Out-Null
      
      $actual = Get-Version -ProjectType Node
      $actual | Should -Be "2.4.0"
    }

    It "Should use default increment part if there is no PR linked" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/commits/{2}/pulls" -f $fakeOwner, $fakeRepository, $fakeSHA)
      } -ModuleName VersionHelper

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -AuthToken $fakeAuthToken -DefaultIncrementingPart "Minor" | Out-Null
      
      $actual = Get-Version -ProjectType Node
      $actual | Should -Be "2.4.0"
    }

    It "Should use default increment part if there is no PR linked and no default increment part specified" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/commits/{2}/pulls" -f $fakeOwner, $fakeRepository, $fakeSHA)
      } -ModuleName VersionHelper

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -AuthToken $fakeAuthToken -DefaultIncrementingPart "Minor" | Out-Null
      
      $actual = Get-Version -ProjectType Node
      $actual | Should -Be "2.4.0"
    }
  }

  Describe "Testing project type 'Node'" {

    Describe "Without workspaces" {
  
      BeforeEach {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @()
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        @{
          "version" = "2.3.4"
        } | ConvertTo-Json > "TestDrive:\package.json"
      }
    
      It "Should increment major version" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "breaking changes"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
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
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
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
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5"
      }

      It "Should add suffix to version" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-rc"
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5-rc"
      }

      It "Should keep existing suffix" {
        @{
          "version" = "2.3.4-rc"
        } | ConvertTo-Json > "TestDrive:\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5-rc"
      }

      It "Should increment new suffix" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-rc"
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.4-rc.1"
      }

      It "Should increment existing suffix" {
        @{
          "version" = "2.3.4-rc.3"
        } | ConvertTo-Json > "TestDrive:\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.4-rc.4"
      }

      It "Should not throw exception if suffix doesn't exist but requested to be incremented" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix-patch"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5"
      }

      It "Should remove suffix" {
        @{
          "version" = "2.3.4-rc"
        } | ConvertTo-Json > "TestDrive:\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5"
      }

      It "Should not throw exception if suffix doesn't exist but requested to be removed" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
        
        $actual = Get-Version -ProjectType Node
        $actual | Should -Be "2.3.5"
      }
    }

    Describe "With workspaces" {
      BeforeEach {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @()
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        @{
          "workspaces" = @(
            "projects/test-project-1",
            "projects/test-project-2"
          )
        } | ConvertTo-Json > "TestDrive:\package.json"

        New-Item -Path "TestDrive:\projects\test-project-1" -ItemType Directory -Force
        @{
          "version" = "2.3.4"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-1\package.json"

        New-Item -Path "TestDrive:\projects\test-project-2" -ItemType Directory -Force
        @{
          "version" = "3.4.5"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-2\package.json"
      }

      It "Should increment major version for specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "breaking changes"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "4.0.0"
      }

      It "Should increment minor version for specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "enhancement"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.5.0"
      }

      It "Should increment patch version for specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6"
      }

      It "Should add suffix to version in specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2" -Suffix "-rc"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6-rc"
      }

      It "Should keep existing suffix in specified workspace" {
        New-Item -Path "TestDrive:\projects\test-project-1" -ItemType Directory -Force
        @{
          "version" = "2.3.4-alpha"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-1\package.json"

        New-Item -Path "TestDrive:\projects\test-project-2" -ItemType Directory -Force
        @{
          "version" = "3.4.5-beta"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-2\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4-alpha"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6-beta"
      }

      It "Should increment new suffix in specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2" -Suffix "-rc"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.5-rc.1"
      }

      It "Should increment existing suffix in specified workspace" {
        New-Item -Path "TestDrive:\projects\test-project-1" -ItemType Directory -Force
        @{
          "version" = "2.3.4"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-1\package.json"

        New-Item -Path "TestDrive:\projects\test-project-2" -ItemType Directory -Force
        @{
          "version" = "3.4.5-rc.3"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-2\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.5-rc.4"
      }

      It "Should not throw exception if suffix doesn't exist but requested to be incremented in specified workspace" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "suffix-patch"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -WorkspaceName "test-project-2"
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6"
      }

      It "Should remove suffix for specified workspace" {
        New-Item -Path "TestDrive:\projects\test-project-1" -ItemType Directory -Force
        @{
          "version" = "2.3.4-alpha"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-1\package.json"

        New-Item -Path "TestDrive:\projects\test-project-2" -ItemType Directory -Force
        @{
          "version" = "3.4.5-beta"
        } | ConvertTo-Json > "TestDrive:\projects\test-project-2\package.json"

        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -WorkspaceName "test-project-2" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4-alpha"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6"
      }

      It "Should not throw exception if suffix doesn't exist in specified workspace but requested to be removed" {
        Mock -CommandName Invoke-RestMethod -MockWith { 
          @(
            @{
              name = "bug"
            }
          )
        } -ParameterFilter {
          $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
        } -ModuleName VersionHelper
    
        Submit-NewVersionLabel -ProjectType Node -WorkspaceName "test-project-2" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
        
        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-1"
        $workspace1Version | Should -Be "2.3.4"

        $workspace1Version = Get-Version -ProjectType Node -WorkspaceName "test-project-2"
        $workspace1Version | Should -Be "3.4.6"
      }
    }
  }

  Describe "Testing project type 'Posh'" {
  
    BeforeAll {
      New-Item -Path "TestDrive:\\" -Name "TestModule" -ItemType Directory | Out-Null
    }

    AfterAll {
      Remove-Item -Path "TestDrive:\TestModule" -Recurse -Force | Out-Null
    }

    BeforeEach {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper

      Set-Content "@{
          RootModule        = ''
          ModuleVersion     = '2.3.4.5'
          GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
          Author            = 'Your Name'
          Description       = 'A brief description of your module'
          PowerShellVersion = '5.1'
      }" -Path "TestDrive:\TestModule\TestModule.psd1"
    }

    It "Should increment major part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "breaking changes"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "3.0.0.5"
    }

    It "Should increment minor part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "enhancement"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.4.0.5"
    }

    It "Should increment patch part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5.5"
    }

    It "Should increment revision part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "misc"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.4.6"
    }

    It "Should add suffix to version" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-posh"
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5-posh"
    }

    It "Should keep existing suffix" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = 'rc' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith {
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5-rc"
    }

    It "Should increment new suffix" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-rc"
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.4-rc1"
    }

    It "Should increment existing suffix" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = 'rc3' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.4-rc4"
    }

    It "Should not throw exception if suffix doesn't exist but requested to be incremented" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix-patch"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Version Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5.5"
    }

    It "Should throw exception if suffix contains incorrect symbols: <suffix>" -ForEach @( @{ suffix = "@108" }, @{ suffix = "important!" }, @{ suffix = "new feature" } ) {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      { Submit-NewVersionLabel Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix $suffix }
        | Should -Throw -ExpectedMessage "'Prerelease' string may contain only ASCII alphanumerics ``[0-9A-Za-z-``]"
    }

    It "Should throw exception if suffix specified along with revision" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4.5'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      { Submit-NewVersionLabel Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "alpha" }
        | Should -Throw "Suffix cannot be set if Revision is specified"
    }

    It "Should remove suffix" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '-alpha' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5"
    }

    It "Should not throw exception if suffix doesn't exist but requested to be removed" {
      Set-Content "@{
        RootModule        = ''
        ModuleVersion     = '2.3.4'
        GUID              = '5793c879-c461-4b9c-addb-abc3480a6007'
        Author            = 'Your Name'
        Description       = 'A brief description of your module'
        PowerShellVersion = '5.1'
        PrivateData       = @{ PSData = @{ Prerelease = '' }}
      }" -Path "TestDrive:\TestModule\TestModule.psd1"

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
      
      $actual = Get-Version -ProjectType Posh -PowerShellModuleName "TestDrive:\TestModule\TestModule.psd1"
      $actual | Should -Be "2.3.5"
    }
  }

  Describe "Testing project type 'Custom'" {
  
    BeforeAll {
      New-Item -Path "TestDrive:\\" -Name "CustomModule" -ItemType Directory | Out-Null

      @"
function Get-Version {
  param ()
  
  Write-Output (Get-Content "TestDrive:\CustomModule\version.txt")

}

function Set-Version {
  param (
    `$OldVersion,
    `$NewVersion
  )
  
  `$NewVersion | Out-File "TestDrive:\CustomModule\version.txt" -Force
}
"@ | Out-File "TestDrive:\CustomModule\CustomModule.psm1" -Force
    }

    AfterAll {
      Remove-Item -Path "TestDrive:\CustomModule" -Recurse -Force | Out-Null
    }

    BeforeEach {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @()
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper

      "2.3.4.5" | Out-File "TestDrive:\CustomModule\version.txt" -Force
    }

    It "Should increment major part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "breaking changes"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "3.0.0.5"
    }

    It "Should increment minor part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "enhancement"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.4.0.5"
    }

    It "Should increment patch part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5"
    }

    It "Should increment revision part" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "misc"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.4.6"
    }

    It "Should add suffix to version" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-custom"
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5-custom"
    }

    It "Should keep existing suffix" {
      "2.3.4.5-existing-suffix" | Out-File "TestDrive:\CustomModule\version.txt" -Force

      Mock -CommandName Invoke-RestMethod -MockWith {
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5-existing-suffix"
    }

    It "Should increment new suffix" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -Suffix "-rc"
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.4.5-rc.1"
    }

    It "Should increment existing suffix" {
      "2.3.4.5-rc.4" | Out-File "TestDrive:\CustomModule\version.txt" -Force

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.4.5-rc.5"
    }

    It "Should not throw exception if suffix doesn't exist but requested to be incremented" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "suffix-patch"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5"
    }

    It "Should remove suffix" {
      "2.3.4.5-rc.4" | Out-File "TestDrive:\CustomModule\version.txt" -Force

      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5"
    }

    It "Should not throw exception if suffix doesn't exist but requested to be removed" {
      Mock -CommandName Invoke-RestMethod -MockWith { 
        @(
          @{
            name = "bug"
          }
        )
      } -ParameterFilter {
        $Uri -eq ("https://api.github.com/repos/{0}/{1}/issues/{2}/labels" -f $fakeOwner, $fakeRepository, $fakePRNumber)
      } -ModuleName VersionHelper
  
      Submit-NewVersionLabel -ProjectType Custom -CustomPowershellModulePath "TestDrive:\CustomModule\CustomModule.psm1" -SHA $fakeSHA -Owner $fakeOwner -Repository $fakeRepository -VersionConfigurationPath $versionConfigPath -RemoveSuffix
      
      $actual = Get-Content "TestDrive:\CustomModule\version.txt"
      $actual | Should -Be "2.3.5.5"
    }
  }
}