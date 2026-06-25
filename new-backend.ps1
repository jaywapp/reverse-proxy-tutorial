<#
.SYNOPSIS
    Scaffolds a new Blazor Server backend app wired into the portal under /<prefix>.

.DESCRIPTION
    Automates everything in docs/09-extending.md:
      1. dotnet new blazor (Interactive Server) under src\<Name>
      2. References the Shared library and adds the project to the solution
      3. Sets PathBase "/<prefix>" and a Kestrel dev port in appsettings.json
      4. Rewrites Program.cs to use the Shared reverse-proxy helpers
      5. Swaps <base href="/"> for the shared <BaseHref /> component
      6. Registers route-<prefix> / cluster-<prefix> in the Portal config
         (appsettings.json for dev + appsettings.Production.json for IIS)

    After running, add the new app to run-local.ps1 and deploy\iis-setup.ps1
    (the script prints the exact lines to paste).

.PARAMETER Name
    Project name, e.g. "SampleD" or "Orders".

.PARAMETER Prefix
    URL path prefix without slashes, e.g. "d" -> portal.../d. Defaults to the
    lower-cased project name.

.PARAMETER DevPort
    Kestrel port for local dev. Default 5004.

.PARAMETER IisPort
    Port the app will bind to in IIS (used by the Production cluster address).
    Default 8084.

.EXAMPLE
    .\new-backend.ps1 -Name SampleD -Prefix d -DevPort 5004 -IisPort 8084
#>
param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Prefix = $Name.ToLower(),
    [int]$DevPort = 5004,
    [int]$IisPort = 8084
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$prefix = $Prefix.Trim('/')
$proj = "src\$Name"
$projDir = Join-Path $root $proj

if (Test-Path $projDir) { throw "$projDir already exists." }
if ($prefix -notmatch '^[A-Za-z0-9\-]+$') { throw "Prefix must be url-safe (letters/digits/hyphen)." }

Write-Host "1/6 Scaffolding Blazor Server app '$Name' ..." -ForegroundColor Cyan
dotnet new blazor -n $Name -o $projDir --interactivity Server | Out-Null

Write-Host "2/6 Adding Shared reference + solution entry ..." -ForegroundColor Cyan
dotnet add "$projDir\$Name.csproj" reference "$root\src\Shared\ReverseProxy.Backend.Shared.csproj" | Out-Null
dotnet sln "$root\ReverseProxyTutorial.sln" add "$projDir\$Name.csproj" | Out-Null

Write-Host "3/6 Writing appsettings.json (PathBase /$prefix, port $DevPort) ..." -ForegroundColor Cyan
$appsettings = @"
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*",
  "PathBase": "/$prefix",
  "Kestrel": {
    "Endpoints": {
      "Http": {
        "Url": "http://localhost:$DevPort"
      }
    }
  }
}
"@
Set-Content -Path "$projDir\appsettings.json" -Value $appsettings -Encoding utf8

Write-Host "4/6 Rewriting Program.cs ..." -ForegroundColor Cyan
$program = @"
using ReverseProxy.Backend.Shared;
using $Name.Components;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Behaves correctly behind the portal reverse proxy (forwarded headers).
builder.Services.AddBackendReverseProxy();

var app = builder.Build();

// Apply forwarded headers + the configured PathBase ("/$prefix"). Must run first.
app.UseBackendReverseProxy();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
}

app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.Run();
"@
Set-Content -Path "$projDir\Program.cs" -Value $program -Encoding utf8

Write-Host "5/6 Wiring <BaseHref /> into App.razor ..." -ForegroundColor Cyan
$appRazor = "$projDir\Components\App.razor"
(Get-Content $appRazor -Raw) -replace '<base href="/" />', '<BaseHref />' |
    Set-Content -Path $appRazor -Encoding utf8
$imports = "$projDir\Components\_Imports.razor"
Add-Content -Path $imports -Value "@using ReverseProxy.Backend.Shared" -Encoding utf8

Write-Host "6/6 Registering route/cluster in the Portal config ..." -ForegroundColor Cyan
# dev appsettings.json holds routes + clusters; Production overrides clusters only.
function Add-PortalEntry([string]$file, [string]$address, [bool]$includeRoute) {
    $json = Get-Content $file -Raw | ConvertFrom-Json
    if (-not $json.ReverseProxy) { $json | Add-Member ReverseProxy ([pscustomobject]@{}) -Force }
    if (-not $json.ReverseProxy.Clusters) { $json.ReverseProxy | Add-Member Clusters ([pscustomobject]@{}) -Force }

    $cluster = [pscustomobject]@{ Destinations = [pscustomobject]@{ d1 = [pscustomobject]@{ Address = $address } } }
    $json.ReverseProxy.Clusters | Add-Member "cluster-$prefix" $cluster -Force

    if ($includeRoute) {
        if (-not $json.ReverseProxy.Routes) { $json.ReverseProxy | Add-Member Routes ([pscustomobject]@{}) -Force }
        $route = [pscustomobject]@{ ClusterId = "cluster-$prefix"; Match = [pscustomobject]@{ Path = "/$prefix/{**catch-all}" } }
        $json.ReverseProxy.Routes | Add-Member "route-$prefix" $route -Force
    }
    $json | ConvertTo-Json -Depth 12 | Set-Content -Path $file -Encoding utf8
}
Add-PortalEntry "$root\src\Portal\appsettings.json"           "http://localhost:$DevPort/" $true
Add-PortalEntry "$root\src\Portal\appsettings.Production.json" "http://localhost:$IisPort/" $false

Write-Host ""
Write-Host "Done. '$Name' is served at portal.../$prefix" -ForegroundColor Green
Write-Host ""
Write-Host "Add it to run-local.ps1 `$apps:" -ForegroundColor Yellow
Write-Host "    @{ Name = `"$Name`"; Dir = `"src\$Name`"; Port = $DevPort },"
Write-Host ""
Write-Host "And to deploy\iis-setup.ps1 `$sites (after publishing):" -ForegroundColor Yellow
Write-Host "    @{ Name = `"WebSolution-$Name`"; Pool = `"WebSolution-$Name`"; Path = `"$Name`"; Port = $IisPort; HostHeader = `"`" },"
