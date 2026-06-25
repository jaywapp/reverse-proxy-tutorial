<#
.SYNOPSIS
    Builds and launches the whole solution locally for testing.

.DESCRIPTION
    Starts the sample Blazor Server apps and the YARP portal:
      - SampleA  http://localhost:5001  (served under /a)
      - SampleB  http://localhost:5002  (served under /b)
      - SampleC  http://localhost:5003  (served under /c)
      - Portal   http://localhost:5000  (routes /a /b /c to the apps)

    Open http://localhost:5000 and click through to /a /b /c. The URL stays on
    the portal domain while the content comes from each backend app.

.PARAMETER NoBuild
    Skip the build step (use the existing bin output).
#>
param([switch]$NoBuild)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$config = "Release"

# Name -> relative project directory. Backends live under src\samples.
$apps = @(
    @{ Name = "SampleA"; Dir = "src\samples\SampleA"; Port = 5001 },
    @{ Name = "SampleB"; Dir = "src\samples\SampleB"; Port = 5002 },
    @{ Name = "SampleC"; Dir = "src\samples\SampleC"; Port = 5003 },
    @{ Name = "Portal";  Dir = "src\Portal";          Port = 5000 }
)

if (-not $NoBuild) {
    Write-Host "Building solution..." -ForegroundColor Cyan
    dotnet build "$root\ReverseProxyTutorial.sln" -c $config --nologo
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
}

# Child processes inherit this; Development => Portal uses the dev backend ports
# (5001-5003) from appsettings.json instead of the IIS ports in Production.
$env:ASPNETCORE_ENVIRONMENT = "Development"

$procs = @()
foreach ($app in $apps) {
    $dir = "$root\$($app.Dir)\bin\$config\net9.0"
    $dll = "$dir\$($app.Name).dll"
    if (-not (Test-Path $dll)) { throw "Missing $dll - run without -NoBuild first." }
    Write-Host "Starting $($app.Name) on http://localhost:$($app.Port) ..." -ForegroundColor Green
    $p = Start-Process -FilePath "dotnet" -ArgumentList $dll -WorkingDirectory $dir -PassThru
    $procs += $p
}

Write-Host ""
Write-Host "All apps started. Portal: http://localhost:5000" -ForegroundColor Yellow
Write-Host "PIDs: $($procs.Id -join ', ')"
Write-Host "To stop: Get-Process -Id $($procs.Id -join ',') | Stop-Process"
