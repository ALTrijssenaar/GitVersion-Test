$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$toolPath = Join-Path $HOME '.dotnet/tools'
if ($env:PATH -notlike "*${toolPath}*") {
   $env:PATH = "${toolPath}:$($env:PATH)"
}

$gitVersionTool = Get-Command dotnet-gitversion -ErrorAction SilentlyContinue
if (-not $gitVersionTool) {
   dotnet tool install --global GitVersion.Tool | Out-Null
}
else {
   dotnet tool update --global GitVersion.Tool | Out-Null
}

$gitVersionShimPath = Join-Path $toolPath 'gitversion'
$dotnetGitVersionShimPath = Join-Path $toolPath 'dotnet-gitversion'
if (Test-Path -LiteralPath $gitVersionShimPath) {
   Remove-Item -LiteralPath $gitVersionShimPath -Force
}

if (-not (Test-Path -LiteralPath $dotnetGitVersionShimPath)) {
   throw "Expected GitVersion shim '$dotnetGitVersionShimPath' was not created."
}

New-Item -ItemType SymbolicLink -Path $gitVersionShimPath -Target $dotnetGitVersionShimPath -Force | Out-Null

$pesterModule = Get-Module -ListAvailable -Name Pester |
Sort-Object Version -Descending |
Select-Object -First 1

if (-not $pesterModule -or $pesterModule.Version -lt [version]'5.0.0') {
   Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck | Out-Null
}

& $gitVersionShimPath /version | Out-Null
