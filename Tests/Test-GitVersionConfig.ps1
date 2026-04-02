<#
.SYNOPSIS
Runs Pester tests against a GitVersion configuration file.

.DESCRIPTION
Builds a fresh temporary git sandbox for each supplied scenario, replays the
recorded branch, tag, and commit actions, then asserts that gitversion returns
the expected FullSemVer.

.PARAMETER GitVersionYaml
Path to the GitVersion YAML file to test. Relative paths are resolved from the
repository root.

.PARAMETER TestCases
Optional array of scenario builders. When omitted, the script expects another
source to provide cases.

.EXAMPLE
pwsh ./Tests/Test-GitVersionConfig.ps1 -GitVersionYaml ./Config/ReleaseBranches.yml -TestCases $cases

Runs the supplied scenarios against the bundled sample configuration.
#>

param(
   [string]$GitVersionYaml = 'Config/ReleaseBranches.yml',
   [object[]]$TestCases
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-TestsRoot {
   # Keeps path resolution stable whether the script is called directly or via Pester.
   return (Split-Path -Parent $PSCommandPath)
}

function Get-RepoRoot {
   # Tests live one directory below the repository root.
   return (Split-Path -Parent (Get-TestsRoot))
}

function Resolve-ProvidedGitVersionYamlPath {
   <#
   .SYNOPSIS
   Resolves the GitVersion YAML path to an existing file.

   .DESCRIPTION
   Accepts either an absolute path or a repository-relative path and throws a
   clear error when the configuration file does not exist.
   #>
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$RepoRoot,
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$GitVersionYaml
   )

   $resolvedPath = if ([IO.Path]::IsPathRooted($GitVersionYaml)) {
      $GitVersionYaml
   }
   else {
      Join-Path $RepoRoot $GitVersionYaml
   }

   if (-not (Test-Path -LiteralPath $resolvedPath)) {
      throw "GitVersion yaml not found at provided path: $resolvedPath"
   }

   return $resolvedPath
}

. (Join-Path (Get-RepoRoot) 'Scripts/GitVersionTestSupport.ps1')

function Get-ResolvedTestCases {
   # Allows callers to inject cases directly while keeping a fallback hook.
   param([object[]]$InputCases)

   if ($null -ne $InputCases -and $InputCases.Count -gt 0) {
      return $InputCases
   }

   . (Join-Path (Get-RepoRoot) 'GitVersionTestCases.ps1')
   return (Get-GitVersionTestCases)
}

if (Get-Command -Name 'New-PesterConfiguration' -ErrorAction SilentlyContinue) {
   $global:PesterPreference = New-PesterConfiguration
   $global:PesterPreference.Output.Verbosity = 'Detailed'
}

BeforeDiscovery {
   $repoRoot = Get-RepoRoot
   $script:ResolvedGitVersionYamlPath = Resolve-ProvidedGitVersionYamlPath -RepoRoot $repoRoot -GitVersionYaml $GitVersionYaml
   $script:TestCases = Get-ResolvedTestCases -InputCases $TestCases

   $script:PesterCases = $script:TestCases | ForEach-Object {
      @{
         Name     = $_.Name
         Scenario = $_
      }
   }
}

Describe 'GitVersion repository behavior via temporary submodule' {
   BeforeAll {
      $repoRoot = Get-RepoRoot
      $script:ResolvedGitVersionYamlPath = Resolve-ProvidedGitVersionYamlPath -RepoRoot $repoRoot -GitVersionYaml $GitVersionYaml

      $script:ParentRepoPath = $repoRoot
      Write-Host ('Using GitVersion yaml: {0}' -f $script:ResolvedGitVersionYamlPath)
      $script:SandboxDefinition = (New-GitSubmoduleSandboxBuilder).InParentRepository($script:ParentRepoPath).WithSubmoduleRelativePath('Sandbox').WithGitVersionConfig($script:ResolvedGitVersionYamlPath).WithSeedFile((Join-Path $script:ParentRepoPath 'file.txt')).Build()
   }

   It '<Name>' -ForEach $script:PesterCases {
      # A fresh sandbox keeps git history isolated between scenarios.
      $sandbox = New-GitSubmoduleSandbox -Definition $script:SandboxDefinition

      try {
         $result = $Scenario.RunGitVersion($sandbox)
         $result.FullSemVer | Should -Be $Scenario.ExpectedFullSemVer
      }
      finally {
         Remove-GitSubmoduleSandbox -Sandbox $sandbox
      }
   }
}
