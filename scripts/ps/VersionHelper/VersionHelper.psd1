#
# Module manifest for module 'VersionHelper'
#
# Generated by: Sergey Koryshev
#
# Generated on: 12/6/2023
#

@{

  # Script module or binary module file associated with this manifest.
  RootModule = 'VersionHelper.psm1'

  # Version number of this module.
  ModuleVersion = '1.4.0'

  # ID used to uniquely identify this module
  GUID = '1e1ef6dc-cf07-4f8d-957a-ec3e39216af1'

  # Author of this module
  Author = 'Sergey Koryshev'

  # Copyright statement for this module
  Copyright = '(c) Sergey Koryshev. All rights reserved.'

  # Description of the functionality provided by this module
  Description = 'The PowerShell module helps to increment versions during CI'

  # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
  FunctionsToExport = @(
    'Submit-NewVersionLabel'
    'Get-IncrementingParts'
    'Get-VersionConfiguration'
    'Get-PullRequestNumbers'
    'Get-Version'
    'Set-IncrementedVersion'
  )

  # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
  CmdletsToExport = @()

  # Variables to export from this module
  VariablesToExport = @()

  # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
  AliasesToExport = @()

  # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
  PrivateData = @{
    Settings = @{
      DefaultVersionConfiguration = @{
        "bug"              = @("Patch")
        "enhancement"      = @("Minor")
        "breaking changes" = @("Major")
      }
    } 
  }
}

