# GitVersion Test Repository

PowerShell test harness for validating GitVersion behavior against a specific
configuration. Each scenario runs in a disposable git submodule sandbox, so the
parent repository stays unchanged. Safe to experiment, easy to rerun. 🧪

## Repository Layout

```text
Config/
  ReleaseBranches.yml         Sample GitVersion configuration under test
Scripts/
  GitVersionTestSupport.ps1   Scenario builders and sandbox helpers
Tests/
  Test-GitVersionConfig.ps1   Pester test entry point
RUNME.ps1                     Built-in example scenarios
```

## Using the Dev Container

Use the included dev container. That is the preferred workflow and avoids local
tool installation. Open the repo, reopen in the container, and start testing. 🚀

In VS Code:

1. Open the folder in Visual Studio Code.
2. Install the Dev Containers extension if VS Code prompts for it.
3. Run the command `Dev Containers: Reopen in Container`.
4. Wait for the container to finish building.
5. Run the scripts from the repository root.

Typical commands:

```powershell
pwsh ./RUNME.ps1
```

The container provides the expected PowerShell and Git tooling for this repo,
so everyone works in the same environment. ✅

## Local Setup

Only use local installation if you are not using the dev container. Required
tools:

- PowerShell 7+
- Git
- GitVersion CLI as `gitversion`
- Pester 5+

## Run the Built-In Scenarios

Run the sample scenarios in `RUNME.ps1`:

```powershell
pwsh ./RUNME.ps1
```

This uses `Config/ReleaseBranches.yml` and gives you the quickest sanity check. 🎯

## Run the Test Harness Directly

To run custom scenarios:

```powershell
. ./Scripts/GitVersionTestSupport.ps1

$cases = @(
   (New-GitVersionScenarioBuilder -Name 'Main latest')
      .UseBranch('main')
      .ApplyVersionTag('v1.0.0')
      .AddCommits(6)
      .ApplyVersionTag('v1.1.0')
      .ExpectFullSemVer('1.1.0')
)

pwsh ./Tests/Test-GitVersionConfig.ps1 `
  -GitVersionYaml ./Config/ReleaseBranches.yml `
  -TestCases $cases
```

This is the path to use when you want to try new branch patterns or lock in a
regression test. 🛠️

## Building Scenarios

Scenarios use the fluent API in `Scripts/GitVersionTestSupport.ps1`.

```powershell
(New-GitVersionScenarioBuilder -Name 'Feature branch example')
   .UseBranch('feature/my-change')
   .ApplyVersionTag('v1.0.0')
   .AddCommits(2)
   .ExpectFullSemVer('1.1.0-my-change.1+2')
```

Read it left to right: choose a branch, add a tag if needed, add commits, then
declare the version you expect. Simple. ✨

## How the Tests Work

1. Creates a fresh disposable sandbox repository as a submodule named `Sandbox`.
2. Seeds the sandbox with `.GitVersion.yml` and a starter file.
3. Replays the scenario's branch, tag, and commit actions.
4. Runs `gitversion /nocache /output json` inside the sandbox.
5. Asserts that `FullSemVer` matches the expected value.

In short: each test gets its own tiny throwaway repo, GitVersion does its work,
and the result is checked against the expected version. No cleanup drama, no
history pollution. 🧼
