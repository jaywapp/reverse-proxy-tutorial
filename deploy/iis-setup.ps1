<#
.SYNOPSIS
    Creates IIS app pools and websites for the portal and the three sample apps.
    RUN AS ADMINISTRATOR.

.DESCRIPTION
    Layout created:
      SampleA  -> site "WebSolution-SampleA"  port 8081   (app served under /a)
      SampleB  -> site "WebSolution-SampleB"  port 8082   (app served under /b)
      SampleC  -> site "WebSolution-SampleC"  port 8083   (app served under /c)
      Portal   -> site "WebSolution-Portal"   port 80, host portal.jaywapp.com

    The portal (Production env) proxies /a /b /c to localhost:8081/8082/8083
    as configured in src\Portal\appsettings.Production.json.

    Prerequisites on the server:
      - .NET 9 Hosting Bundle (ASP.NET Core Module v2)
      - IIS with the "WebSocket Protocol" feature enabled (required by Blazor Server)

.PARAMETER PublishRoot
    Root of published output (deploy\publish by default).

.PARAMETER PortalHost
    Host header binding for the portal site. Default portal.jaywapp.com.
#>
param(
    [string]$PublishRoot = (Join-Path $PSScriptRoot "publish"),
    [string]$PortalHost  = "portal.jaywapp.com"
)

$ErrorActionPreference = "Stop"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator."
}

Import-Module WebAdministration

$sites = @(
    @{ Name = "WebSolution-SampleA"; Pool = "WebSolution-SampleA"; Path = "SampleA"; Port = 8081; HostHeader = "" },
    @{ Name = "WebSolution-SampleB"; Pool = "WebSolution-SampleB"; Path = "SampleB"; Port = 8082; HostHeader = "" },
    @{ Name = "WebSolution-SampleC"; Pool = "WebSolution-SampleC"; Path = "SampleC"; Port = 8083; HostHeader = "" },
    @{ Name = "WebSolution-Portal";  Pool = "WebSolution-Portal";  Path = "Portal";  Port = 80;   HostHeader = $PortalHost }
)

foreach ($s in $sites) {
    $physical = Join-Path $PublishRoot $s.Path
    if (-not (Test-Path $physical)) { throw "Missing published output: $physical (run publish-all.ps1 first)" }

    # App pool: No Managed Code (ASP.NET Core runs out of the ANCM, not the CLR pipeline)
    if (Test-Path "IIS:\AppPools\$($s.Pool)") { Remove-WebAppPool -Name $s.Pool }
    New-WebAppPool -Name $s.Pool | Out-Null
    Set-ItemProperty "IIS:\AppPools\$($s.Pool)" -Name managedRuntimeVersion -Value ""
    Set-ItemProperty "IIS:\AppPools\$($s.Pool)" -Name startMode -Value "AlwaysRunning"

    if (Test-Path "IIS:\Sites\$($s.Name)") { Remove-Website -Name $s.Name }
    if ($s.HostHeader) {
        New-Website -Name $s.Name -PhysicalPath $physical -ApplicationPool $s.Pool `
            -Port $s.Port -HostHeader $s.HostHeader | Out-Null
    } else {
        New-Website -Name $s.Name -PhysicalPath $physical -ApplicationPool $s.Pool `
            -Port $s.Port | Out-Null
    }
    Write-Host ("Created {0}  ->  {1}  (port {2}{3})" -f $s.Name, $physical, $s.Port,
        $(if ($s.HostHeader) { ", host $($s.HostHeader)" } else { "" })) -ForegroundColor Green
}

Write-Host ""
Write-Host "IIS sites created." -ForegroundColor Yellow
Write-Host "Add a hosts entry or DNS record so $PortalHost resolves to this server."
Write-Host "Verify WebSocket Protocol is enabled in IIS (required for Blazor Server)."
