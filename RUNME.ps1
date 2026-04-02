<#
.SYNOPSIS
Runs the repository's built-in GitVersion regression scenarios.

.DESCRIPTION
Defines a representative set of GitVersion scenarios and invokes the Pester
test harness in Tests/Test-GitVersionConfig.ps1 against the bundled
configuration in Config/ReleaseBranches.yml.

This is the quickest way to validate that the sample configuration still
produces the expected versions for main, release, and feature branches.

.EXAMPLE
pwsh ./RUNME.ps1

Runs all built-in scenarios with the default configuration.

.NOTES
The script dot-sources Scripts/GitVersionTestSupport.ps1 and delegates test
execution to Tests/Test-GitVersionConfig.ps1.
#>

$global:VerbosePreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'Scripts/GitVersionTestSupport.ps1')

$cases = @(
   (New-GitVersionScenarioBuilder -Name 'Main latest').UseBranch('main').ApplyVersionTag('v1.0.0').AddCommits(6).ApplyVersionTag('v1.1.0').ExpectFullSemVer('1.1.0'),
   (New-GitVersionScenarioBuilder -Name 'Main unstable').UseBranch('main').ApplyVersionTag('v1.0.0').AddCommits(5).ExpectFullSemVer('1.1.0-alpha.5'),
   (New-GitVersionScenarioBuilder -Name 'Release latest').UseBranch('release/v4.6').ApplyVersionTag('v4.6.0').AddCommits(6).ApplyVersionTag('v4.6.1').ExpectFullSemVer('4.6.1'),
   (New-GitVersionScenarioBuilder -Name 'Release unstable').UseBranch('release/v4.6').ApplyVersionTag('v4.6.0').AddCommits(6).ExpectFullSemVer('4.6.1-beta.6'),
   (New-GitVersionScenarioBuilder -Name 'Release unstable').UseBranch('release/v4.7').ApplyVersionTag('v4.7.0').AddCommits(7).ExpectFullSemVer('4.7.1-beta.7'),
   (New-GitVersionScenarioBuilder -Name 'Release unstable').UseBranch('release/v4.8').ApplyVersionTag('v4.8.0').AddCommits(8).ExpectFullSemVer('4.8.1-beta.8'),
   (New-GitVersionScenarioBuilder -Name 'Feature').UseBranch('feature/test1').ApplyVersionTag('v1.0.0').AddCommits(1).ExpectFullSemVer('1.1.0-test1.1+1'),
   (New-GitVersionScenarioBuilder -Name 'Feature').UseBranch('feature/test1').ApplyVersionTag('v1.0.0').AddCommits(2).ExpectFullSemVer('1.1.0-test1.1+2'),
   (New-GitVersionScenarioBuilder -Name 'Feature').UseBranch('feature/test2').ApplyVersionTag('v1.0.0').AddCommits(2).ExpectFullSemVer('1.1.0-test2.1+2'),
   (New-GitVersionScenarioBuilder -Name 'Feature').UseBranch('feature/test2').ApplyVersionTag('v1.0.0').AddCommits(3).ExpectFullSemVer('1.1.0-test2.1+3'),
   (New-GitVersionScenarioBuilder -Name 'Feature complex').UseBranch('feature/user/alt').ApplyVersionTag('v1.0.0').AddCommits(3).ExpectFullSemVer('1.1.0-user-alt.1+3')
)

& (Join-Path $PSScriptRoot 'Tests/Test-GitVersionConfig.ps1') -GitVersionYaml (Join-Path $PSScriptRoot 'Config/ReleaseBranches.yml') -TestCases $cases
