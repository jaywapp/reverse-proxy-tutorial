<#
.SYNOPSIS
    Publishes the portal and all backend apps into deploy\publish\<App> for IIS.

.PARAMETER OutputRoot
    Destination root. Defaults to deploy\publish next to this script.
#>
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot "publish")
)

$ErrorActionPreference = "Stop"
$repo = Split-Path $PSScriptRoot -Parent

# Name -> project file (relative to repo root). The Shared library is pulled in
# automatically as a project reference, so it does not need its own entry.
$projects = @(
    @{ Name = "Portal";  Path = "src\Portal\Portal.csproj" },
    @{ Name = "SampleA"; Path = "src\samples\SampleA\SampleA.csproj" },
    @{ Name = "SampleB"; Path = "src\samples\SampleB\SampleB.csproj" },
    @{ Name = "SampleC"; Path = "src\samples\SampleC\SampleC.csproj" }
)

foreach ($p in $projects) {
    $proj = Join-Path $repo $p.Path
    $out  = Join-Path $OutputRoot $p.Name
    Write-Host "Publishing $($p.Name) -> $out" -ForegroundColor Cyan
    dotnet publish $proj -c Release -o $out --nologo
    if ($LASTEXITCODE -ne 0) { throw "Publish failed for $($p.Name)" }
}

Write-Host ""
Write-Host "Done. Published apps are in: $OutputRoot" -ForegroundColor Green
Write-Host "Next: run deploy\iis-setup.ps1 as Administrator." -ForegroundColor Yellow
