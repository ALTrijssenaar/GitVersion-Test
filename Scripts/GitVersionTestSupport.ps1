<#
.SYNOPSIS
Provides reusable helpers for GitVersion scenario tests.

.DESCRIPTION
This script contains the scenario builder used by the test cases, sandbox
creation and cleanup helpers, and wrappers around git and gitversion command
execution. The helpers create an isolated submodule-based repository so test
scenarios can freely create branches, commits, and tags without mutating the
parent repository.

.NOTES
This file is intended to be dot-sourced by RUNME.ps1 and
Tests/Test-GitVersionConfig.ps1.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Records a sequence of git operations and replays them inside an isolated
# sandbox repository before invoking gitversion.
class GitVersionScenarioBuilder {
   [string]$Name
   [string]$Branch
   [string]$VersionTag
   [int]$CommitCount
   [string]$ExpectedFullSemVer
   hidden [bool]$IsReplayingActions
   hidden [string]$ReplayWorkingDirectory
   hidden [int]$ReplayCommitNumber
   hidden [System.Collections.ArrayList]$RecordedActions
   hidden [string]$NamePrefix

   GitVersionScenarioBuilder([string]$name) {
      if ([string]::IsNullOrWhiteSpace($name)) {
         throw 'Scenario name cannot be empty.'
      }

      $this.Name = $name
      $this.RecordedActions = [System.Collections.ArrayList]::new()
      $this.NamePrefix = $name
   }

   hidden [void] RefreshScenarioName() {
      $actionParts = [System.Collections.Generic.List[string]]::new()
      foreach ($action in $this.RecordedActions) {
         switch ($action.Type) {
            'UseBranch' {
               $actionParts.Add([string]$action.Value)
               continue
            }
            'ApplyVersionTag' {
               $actionParts.Add('tag {0}' -f [string]$action.Value)
               continue
            }
            'AddCommits' {
               $recordedCommitCount = [int]$action.Value
               $label = if ($recordedCommitCount -eq 1) { 'commit' } else { 'commits' }
               $actionParts.Add(('{0} {1}' -f $recordedCommitCount, $label))
               continue
            }
         }
      }

      $generatedPrefix = if ($actionParts.Count -gt 0) {
         $actionParts -join ' + '
      }
      else {
         'Scenario'
      }

      $generatedName = if ([string]::IsNullOrWhiteSpace($this.ExpectedFullSemVer)) {
         $generatedPrefix
      }
      else {
         '{0} = {1}' -f $generatedPrefix, $this.ExpectedFullSemVer
      }

      if ([string]::IsNullOrWhiteSpace($this.NamePrefix)) {
         $this.Name = $generatedName
         return
      }

      $this.Name = '{0}: {1}' -f $this.NamePrefix, $generatedName
   }

   [GitVersionScenarioBuilder] UseBranch([string]$branch) {
      $this.Branch = $branch

      if (-not $this.IsReplayingActions) {
         $null = $this.RecordedActions.Add([PSCustomObject]@{
               Type  = 'UseBranch'
               Value = $branch
            })
         $this.RefreshScenarioName()
      }

      if ($this.IsReplayingActions) {
         if ([string]::IsNullOrWhiteSpace($branch)) {
            throw "Scenario '$($this.Name)' does not define a branch to test"
         }

         if ($branch -eq 'main') {
            Invoke-GitCommand -WorkingDirectory $this.ReplayWorkingDirectory -Arguments @('checkout', 'main') -ErrorMessage 'Failed to checkout sandbox main branch' -SandboxPath $this.ReplayWorkingDirectory
         }
         else {
            Invoke-GitCommand -WorkingDirectory $this.ReplayWorkingDirectory -Arguments @('checkout', '-B', $branch) -ErrorMessage "Failed to create sandbox branch '$branch'" -SandboxPath $this.ReplayWorkingDirectory
         }
      }

      return $this
   }

   [GitVersionScenarioBuilder] AddCommits([int]$commits) {
      $this.CommitCount = $commits

      if (-not $this.IsReplayingActions) {
         $null = $this.RecordedActions.Add([PSCustomObject]@{
               Type  = 'AddCommits'
               Value = $commits
            })
         $this.RefreshScenarioName()
      }

      if ($this.IsReplayingActions) {
         for ($i = 1; $i -le $commits; $i++) {
            $this.ReplayCommitNumber += 1
            Invoke-GitCommand -WorkingDirectory $this.ReplayWorkingDirectory -Arguments @('commit', '--allow-empty', '-m', "test: test commit $($this.ReplayCommitNumber)") -ErrorMessage "Failed to create commit $($this.ReplayCommitNumber)" -SandboxPath $this.ReplayWorkingDirectory
         }
      }

      return $this
   }

   [GitVersionScenarioBuilder] ApplyVersionTag([string]$tag) {
      $this.VersionTag = $tag

      if (-not $this.IsReplayingActions) {
         $null = $this.RecordedActions.Add([PSCustomObject]@{
               Type  = 'ApplyVersionTag'
               Value = $tag
            })
         $this.RefreshScenarioName()
      }

      if ($this.IsReplayingActions -and -not [string]::IsNullOrWhiteSpace($tag)) {
         Invoke-GitCommand -WorkingDirectory $this.ReplayWorkingDirectory -Arguments @('tag', $tag) -ErrorMessage "Failed to create tag [$tag]" -SandboxPath $this.ReplayWorkingDirectory
      }

      return $this
   }

   [GitVersionScenarioBuilder] ExpectFullSemVer([string]$expectedFullSemVer) {
      $this.ExpectedFullSemVer = $expectedFullSemVer
      $this.RefreshScenarioName()
      return $this
   }

   [pscustomobject] RunGitVersion([pscustomobject]$Sandbox) {
      Write-Verbose ('Starting scenario: {0}' -f $this.Name)
      $scenarioPath = $Sandbox.SubmodulePath

      try {
         $this.IsReplayingActions = $true
         $this.ReplayWorkingDirectory = $scenarioPath
         $this.ReplayCommitNumber = 0

         Assert-PathIsSandbox -Path $scenarioPath -SandboxPath $scenarioPath

         return (Invoke-InDirectory -WorkingDirectory $scenarioPath -ScriptBlock {
               if ($this.RecordedActions.Count -eq 0) {
                  throw "Scenario '$($this.Name)' has no operations configured"
               }

               foreach ($operation in $this.RecordedActions) {
                  switch ($operation.Type) {
                     'UseBranch' {
                        $this.UseBranch([string]$operation.Value) | Out-Null
                        continue
                     }
                     'ApplyVersionTag' {
                        $this.ApplyVersionTag([string]$operation.Value) | Out-Null
                        continue
                     }
                     'AddCommits' {
                        $this.AddCommits([int]$operation.Value) | Out-Null
                        continue
                     }
                     default {
                        throw "Scenario '$($this.Name)' has unsupported operation type '$($operation.Type)'"
                     }
                  }
               }

               $gitVersionArguments = @('/nocache', '/output', 'json')
               $rawGitVersionJson = Invoke-ExternalCommand -WorkingDirectory $scenarioPath -FilePath 'gitversion' -Arguments $gitVersionArguments -ErrorMessage 'gitversion failed' -PassThru -TraceToVerbose
               $gitVersion = Convert-GitVersionJsonOutput -RawOutput $rawGitVersionJson -ScenarioName $this.Name
               Write-Verbose ($gitVersion | ConvertTo-Json -Depth 10)
               Write-Host ('Scenario result: {0}' -f $gitVersion.FullSemVer) -ForegroundColor White
               return $gitVersion
            })
      }
      finally {
         $this.IsReplayingActions = $false
         $this.ReplayWorkingDirectory = $null
         $this.ReplayCommitNumber = 0
         Write-Verbose ('Stopped scenario: {0}' -f $this.Name)
      }
   }
}

# Defines the filesystem layout used for a temporary test repository that is
# mounted into the parent repository as a submodule.
class GitSubmoduleSandboxBuilder {
   [string]$ParentRepoPath
   [string]$SubmoduleRelativePath = 'Sandbox'
   [string]$SupportRootPath
   [string]$GitVersionConfigPath
   [string]$SeedFilePath

   [GitSubmoduleSandboxBuilder] InParentRepository([string]$parentRepoPath) {
      $this.ParentRepoPath = $parentRepoPath
      return $this
   }

   [GitSubmoduleSandboxBuilder] WithSubmoduleRelativePath([string]$submoduleRelativePath) {
      $this.SubmoduleRelativePath = $submoduleRelativePath
      return $this
   }

   [GitSubmoduleSandboxBuilder] WithGitVersionConfig([string]$gitVersionConfigPath) {
      $this.GitVersionConfigPath = $gitVersionConfigPath
      return $this
   }

   [GitSubmoduleSandboxBuilder] WithSeedFile([string]$seedFilePath) {
      $this.SeedFilePath = $seedFilePath
      return $this
   }

   [pscustomobject] Build() {
      $resolvedSupportRootPath = $this.SupportRootPath
      if ([string]::IsNullOrWhiteSpace($resolvedSupportRootPath)) {
         $resolvedRepoName = [IO.Path]::GetFileName($this.ParentRepoPath)
         $resolvedSupportRootPath = Join-Path ([IO.Path]::GetTempPath()) ('{0}-gitversion-submodule-tests' -f $resolvedRepoName)
      }

      $resolvedSubmodulePath = Join-Path $this.ParentRepoPath $this.SubmoduleRelativePath
      $resolvedParentGitModulesPath = Join-Path (Join-Path $this.ParentRepoPath '.git/modules') $this.SubmoduleRelativePath

      return [PSCustomObject]@{
         ParentRepoPath        = $this.ParentRepoPath
         SubmoduleRelativePath = $this.SubmoduleRelativePath
         SubmodulePath         = $resolvedSubmodulePath
         SupportRootPath       = $resolvedSupportRootPath
         BareRemotePath        = Join-Path $resolvedSupportRootPath 'remote.git'
         GitVersionConfigPath  = $this.GitVersionConfigPath
         SeedFilePath          = $this.SeedFilePath
         GitModulesPath        = Join-Path $this.ParentRepoPath '.gitmodules'
         ParentGitModulesPath  = $resolvedParentGitModulesPath
      }
   }
}

function New-GitVersionScenarioBuilder {
   <#
   .SYNOPSIS
   Creates a GitVersion scenario builder.

   .DESCRIPTION
   Returns a fluent builder that records branch, tag, and commit operations and
   the expected FullSemVer result for a scenario.

   .PARAMETER Name
   Optional display name prefix for the scenario. When omitted, the name is
   generated from the recorded operations.

   .EXAMPLE
   New-GitVersionScenarioBuilder -Name 'Main latest'

   Creates a named scenario builder.
   #>
   param(
      [string]$Name
   )

   if ([string]::IsNullOrWhiteSpace($Name)) {
      $builder = [GitVersionScenarioBuilder]::new('Scenario')
      $builder.NamePrefix = $null
      $builder.RefreshScenarioName()
      return $builder
   }

   $builder = [GitVersionScenarioBuilder]::new($Name)
   $builder.RefreshScenarioName()
   return $builder
}

function New-GitSubmoduleSandboxBuilder {
   <#
   .SYNOPSIS
   Creates a sandbox definition builder.

   .DESCRIPTION
   Returns a builder that captures the parent repository path, submodule path,
   GitVersion configuration path, and optional seed file used to create a fresh
   test sandbox.
   #>
   [GitSubmoduleSandboxBuilder]::new()
}

function Remove-PathIfExists {
   # Centralized removal helper so sandbox cleanup remains idempotent.
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$Path
   )

   if (Test-Path -LiteralPath $Path) {
      Remove-Item -LiteralPath $Path -Recurse -Force
   }
}

function Invoke-InDirectory {
   # Ensures temporary location changes are always restored.
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$WorkingDirectory,
      [Parameter(Mandatory)]
      [ScriptBlock]$ScriptBlock
   )

   try {
      Push-Location -LiteralPath $WorkingDirectory
      & $ScriptBlock
   }
   finally {
      Pop-Location
   }
}

function Invoke-ExternalCommand {
   # Executes a process in a specific directory and normalizes exit code checks.
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$WorkingDirectory,
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$FilePath,
      [string[]]$Arguments = @(),
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$ErrorMessage,
      [switch]$PassThru,
      [switch]$TraceToVerbose
   )

   if ($TraceToVerbose) {
      $commandParts = @($FilePath)
      foreach ($argument in @($Arguments)) {
         if ([string]$argument -match '\s') {
            $commandParts += ('"{0}"' -f $argument)
         }
         else {
            $commandParts += $argument
         }
      }

      Write-Verbose ('[{0}] {1}' -f $WorkingDirectory, ($commandParts -join ' '))
   }

   $execution = Invoke-InDirectory -WorkingDirectory $WorkingDirectory -ScriptBlock {
      $output = & $FilePath @Arguments 2> $null
      [PSCustomObject]@{
         Output   = $output
         ExitCode = $LASTEXITCODE
      }
   }

   if ($execution.ExitCode -ne 0) {
      throw "$ErrorMessage (exit code: $($execution.ExitCode))"
   }

   if ($PassThru) {
      return $execution.Output
   }
}

function Invoke-ExternalCommandAllowFailure {
   # Mirrors Invoke-ExternalCommand but returns the exit code for cleanup paths.
   param(
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$WorkingDirectory,
      [Parameter(Mandatory)]
      [ValidateNotNullOrEmpty()]
      [string]$FilePath,
      [string[]]$Arguments = @(),
      [switch]$TraceToVerbose
   )

   if ($TraceToVerbose) {
      $commandParts = @($FilePath)
      foreach ($argument in @($Arguments)) {
         if ([string]$argument -match '\s') {
            $commandParts += ('"{0}"' -f $argument)
         }
         else {
            $commandParts += $argument
         }
      }

      Write-Verbose ('[{0}] {1}' -f $WorkingDirectory, ($commandParts -join ' '))
   }

   return (Invoke-InDirectory -WorkingDirectory $WorkingDirectory -ScriptBlock {
         $output = & $FilePath @Arguments 2> $null
         [PSCustomObject]@{
            Output   = $output
            ExitCode = $LASTEXITCODE
         }
      })
}

function Assert-PathIsSandbox {
   # Prevents git operations from escaping the disposable sandbox repository.
   param(
      [Parameter(Mandatory)]
      [string]$Path,
      [Parameter(Mandatory)]
      [string]$SandboxPath
   )

   $normalizedPath = [System.IO.Path]::GetFullPath($Path)
   $normalizedSandbox = [System.IO.Path]::GetFullPath($SandboxPath)
   $sandboxPrefix = $normalizedSandbox.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

   if (($normalizedPath -ne $normalizedSandbox) -and (-not $normalizedPath.StartsWith($sandboxPrefix, [System.StringComparison]::Ordinal))) {
      throw "SAFETY CHECK FAILED: Git command attempted outside Sandbox folder.`n" + `
         "  Working Directory: $Path`n" + `
         "  Allowed Sandbox:  $SandboxPath`n" + `
         'This is a safety mechanism to prevent accidental modification of the parent repository.'
   }
}

function Invoke-GitCommand {
   # Wraps git invocation and optionally enforces sandbox path safety.
   param(
      [string]$WorkingDirectory,
      [string[]]$Arguments,
      [string]$ErrorMessage,
      [switch]$PassThru,
      [string]$SandboxPath,
      [switch]$TraceToVerbose
   )

   # If SandboxPath is provided, validate that WorkingDirectory is within Sandbox
   if ($SandboxPath) {
      Assert-PathIsSandbox -Path $WorkingDirectory -SandboxPath $SandboxPath
   }

   $shouldTrace = $TraceToVerbose -or [bool]$SandboxPath
   Invoke-ExternalCommand -WorkingDirectory $WorkingDirectory -FilePath 'git' -Arguments $Arguments -ErrorMessage $ErrorMessage -PassThru:$PassThru -TraceToVerbose:$shouldTrace
}

function Invoke-GitCommandAllowFailure {
   # Cleanup operations often need git output without failing the entire test.
   param(
      [string]$WorkingDirectory,
      [string[]]$Arguments,
      [string]$SandboxPath,
      [switch]$TraceToVerbose
   )

   # If SandboxPath is provided, validate that WorkingDirectory is within Sandbox
   if ($SandboxPath) {
      Assert-PathIsSandbox -Path $WorkingDirectory -SandboxPath $SandboxPath
   }

   $shouldTrace = $TraceToVerbose -or [bool]$SandboxPath
   Invoke-ExternalCommandAllowFailure -WorkingDirectory $WorkingDirectory -FilePath 'git' -Arguments $Arguments -TraceToVerbose:$shouldTrace
}

function Convert-GitVersionJsonOutput {
   <#
   .SYNOPSIS
   Parses gitversion JSON output.

   .DESCRIPTION
   Normalizes raw command output, extracts the JSON payload when gitversion
   emits surrounding text, and validates that the fields required by the tests
   are present.

   .PARAMETER RawOutput
   Raw stdout returned by the gitversion CLI.

   .PARAMETER ScenarioName
   Scenario label used in error messages.
   #>
   param(
      [AllowNull()][object]$RawOutput,
      [string]$ScenarioName
   )

   $jsonText = if ($RawOutput -is [System.Array]) {
      $RawOutput -join "`n"
   }
   else {
      [string]$RawOutput
   }

   if ([string]::IsNullOrWhiteSpace($jsonText)) {
      throw "gitversion returned no JSON output for scenario '$ScenarioName'"
   }

   $trimmedJsonText = $jsonText.Trim()
   if (-not $trimmedJsonText.StartsWith('{')) {
      $startIndex = $trimmedJsonText.IndexOf('{')
      $endIndex = $trimmedJsonText.LastIndexOf('}')
      if ($startIndex -ge 0 -and $endIndex -gt $startIndex) {
         $trimmedJsonText = $trimmedJsonText.Substring($startIndex, ($endIndex - $startIndex + 1))
      }
   }

   try {
      $gitVersion = $trimmedJsonText | ConvertFrom-Json -ErrorAction Stop
   }
   catch {
      $preview = if ($trimmedJsonText.Length -gt 300) {
         $trimmedJsonText.Substring(0, 300)
      }
      else {
         $trimmedJsonText
      }

      throw "Failed to parse gitversion JSON for scenario '$ScenarioName'. Output preview: $preview"
   }

   if (-not $gitVersion.FullSemVer -or -not $gitVersion.SemVer -or -not $gitVersion.BranchName) {
      throw "gitversion JSON misses required fields for scenario '$ScenarioName'"
   }

   return $gitVersion
}

function Set-TestGitIdentity {
   # Uses deterministic identity values so disposable test commits are explicit.
   param(
      [string]$RepositoryPath,
      [switch]$TraceToVerbose
   )

   Invoke-GitCommand -WorkingDirectory $RepositoryPath -Arguments @('config', 'user.name', 'Pester Runner') -ErrorMessage "Failed to configure git user.name in '$RepositoryPath'" -TraceToVerbose:$TraceToVerbose
   Invoke-GitCommand -WorkingDirectory $RepositoryPath -Arguments @('config', 'user.email', 'pester@example.com') -ErrorMessage "Failed to configure git user.email in '$RepositoryPath'" -TraceToVerbose:$TraceToVerbose
}

function Remove-GitSubmoduleSandbox {
   <#
   .SYNOPSIS
   Removes a temporary Git submodule sandbox.

   .DESCRIPTION
   Deinitializes the submodule, removes generated working tree and git metadata,
   and deletes the support directory used to host the sandbox remote.

   .PARAMETER Sandbox
   Sandbox definition returned by New-GitSubmoduleSandbox.
   #>
   param([pscustomobject]$Sandbox)

   Write-Verbose ('Deinitializing submodule sandbox at: {0}' -f $Sandbox.SubmodulePath)

   Invoke-GitCommandAllowFailure -WorkingDirectory $Sandbox.ParentRepoPath -Arguments @('submodule', 'deinit', '-f', '--', $Sandbox.SubmoduleRelativePath) -TraceToVerbose | Out-Null

   Remove-PathIfExists -Path $Sandbox.SubmodulePath
   Remove-PathIfExists -Path $Sandbox.ParentGitModulesPath
   Remove-PathIfExists -Path $Sandbox.GitModulesPath

   Invoke-GitCommandAllowFailure -WorkingDirectory $Sandbox.ParentRepoPath -Arguments @('rm', '--cached', '--force', '--ignore-unmatch', '--', '.gitmodules') -TraceToVerbose | Out-Null
   Invoke-GitCommandAllowFailure -WorkingDirectory $Sandbox.ParentRepoPath -Arguments @('rm', '--cached', '--force', '--ignore-unmatch', '--', $Sandbox.SubmoduleRelativePath) -TraceToVerbose | Out-Null

   # Keep parent repo index clean without restoring files.
   Invoke-GitCommandAllowFailure -WorkingDirectory $Sandbox.ParentRepoPath -Arguments @('reset', '--', '.gitmodules', $Sandbox.SubmoduleRelativePath) -TraceToVerbose | Out-Null

   $submoduleParentDirectory = Split-Path -Parent $Sandbox.SubmodulePath
   if ((Test-Path -LiteralPath $submoduleParentDirectory) -and -not (Get-ChildItem -LiteralPath $submoduleParentDirectory -Force | Select-Object -First 1)) {
      Remove-Item -LiteralPath $submoduleParentDirectory -Force
   }

   Remove-PathIfExists -Path $Sandbox.SupportRootPath

   Write-Verbose ('Submodule sandbox deinitialized: {0}' -f $Sandbox.SubmodulePath)
}

function New-GitSubmoduleSandbox {
   <#
   .SYNOPSIS
   Creates a fresh Git submodule sandbox for a test scenario.

   .DESCRIPTION
   Builds a disposable repository seeded with the selected GitVersion
   configuration and file content, commits the initial state, and adds that
   repository to the parent repo as a submodule named by the sandbox
   definition.

   .PARAMETER Definition
   Sandbox definition produced by New-GitSubmoduleSandboxBuilder.

   .OUTPUTS
   PSCustomObject describing the created sandbox paths.
   #>
   param([pscustomobject]$Definition)

   Write-Verbose ('Initializing submodule sandbox at: {0}' -f (Join-Path $Definition.ParentRepoPath $Definition.SubmoduleRelativePath))

   $sandbox = [PSCustomObject]@{}
   foreach ($property in $Definition.PSObject.Properties) {
      $sandbox | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
   }

   Remove-GitSubmoduleSandbox -Sandbox $sandbox

   New-Item -ItemType Directory -Path $sandbox.SupportRootPath -Force | Out-Null
   New-Item -ItemType Directory -Path (Split-Path -Parent $sandbox.SubmodulePath) -Force | Out-Null

   Invoke-GitCommand -WorkingDirectory $sandbox.SupportRootPath -Arguments @('init', '--initial-branch=main', $sandbox.BareRemotePath) -ErrorMessage 'Failed to create sandbox source repository' -TraceToVerbose

   Set-TestGitIdentity -RepositoryPath $sandbox.BareRemotePath -TraceToVerbose

   Copy-Item -LiteralPath $sandbox.GitVersionConfigPath -Destination (Join-Path $sandbox.BareRemotePath '.GitVersion.yml') -Force
   if (Test-Path -LiteralPath $sandbox.SeedFilePath) {
      Copy-Item -LiteralPath $sandbox.SeedFilePath -Destination (Join-Path $sandbox.BareRemotePath 'file.txt') -Force
   }
   else {
      Set-Content -LiteralPath (Join-Path $sandbox.BareRemotePath 'file.txt') -Value 'seed'
   }

   Invoke-GitCommand -WorkingDirectory $sandbox.BareRemotePath -Arguments @('add', '.') -ErrorMessage 'Failed to stage sandbox source files' -TraceToVerbose
   Invoke-GitCommand -WorkingDirectory $sandbox.BareRemotePath -Arguments @('commit', '-m', 'initial commit') -ErrorMessage 'Failed to create initial sandbox commit' -TraceToVerbose

   Invoke-GitCommand -WorkingDirectory $sandbox.ParentRepoPath -Arguments @('-c', 'protocol.file.allow=always', 'submodule', 'add', '--force', $sandbox.BareRemotePath, $sandbox.SubmoduleRelativePath) -ErrorMessage 'Failed to create test submodule' -TraceToVerbose

   Set-TestGitIdentity -RepositoryPath $sandbox.SubmodulePath -TraceToVerbose

   Write-Verbose ('Submodule sandbox initialized: {0}' -f $sandbox.SubmodulePath)

   return $sandbox
}
