[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('IIS_SITE_NAME', 'IIS_DEPLOYMENT_ROOT', 'IIS_HTTP_PORT', 'IIS_HEALTH_URL', 'IIS_RELEASE_ID', 'IIS_PACKAGE_PATH')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Missing deployment setting: $name"
    }
}

Import-Module WebAdministration
$siteName = $env:IIS_SITE_NAME
$poolName = "$siteName-AppPool"
$port = [int]$env:IIS_HTTP_PORT
if ($port -lt 1 -or $port -gt 65535) { throw 'HTTP port must be between 1 and 65535.' }
if ($siteName -match '[\\/\[\]*?]' -or $env:IIS_RELEASE_ID -notmatch '^\d+$') {
    throw 'Invalid site name or release ID.'
}

$packagePath = [IO.Path]::GetFullPath($env:IIS_PACKAGE_PATH)
foreach ($file in @('web.config', 'DeploymentNetCore.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $packagePath $file) -PathType Leaf)) {
        throw "Published artifact is missing $file."
    }
}

# The VM needs the x64 .NET 10 Hosting Bundle, including the IIS native module.
if (-not (Get-WebGlobalModule | Where-Object Name -eq 'AspNetCoreModuleV2')) {
    throw 'Install the .NET 10 Hosting Bundle after IIS, then restart IIS and the agent.'
}
$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
$runtimes = & $dotnet --list-runtimes
if ($LASTEXITCODE -ne 0 -or -not ($runtimes -match '^Microsoft.AspNetCore.App 10\.0\.')) {
    throw 'The x64 ASP.NET Core 10 runtime is required on the VM.'
}

$releasePath = Join-Path ([IO.Path]::GetFullPath($env:IIS_DEPLOYMENT_ROOT)) "releases\$($env:IIS_RELEASE_ID)"
# A retry uses a new directory, preserving any release already serving traffic.
$releasePath = "$releasePath-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $releasePath -Force | Out-Null
Get-ChildItem -LiteralPath $packagePath -Force | Copy-Item -Destination $releasePath -Recurse -Force

$sitePath = "IIS:\Sites\$siteName"
$poolPath = "IIS:\AppPools\$poolName"
$siteExists = Test-Path -LiteralPath $sitePath
$previousPath = $null
if ($siteExists) {
    $site = Get-Item -LiteralPath $sitePath
    $previousPath = $site.physicalPath
    if ($site.applicationPool -ne $poolName) {
        throw "Existing site must use the dedicated application pool '$poolName'."
    }
}
if (-not (Test-Path -LiteralPath $poolPath)) {
    New-WebAppPool -Name $poolName | Out-Null
}
Set-ItemProperty -LiteralPath $poolPath -Name managedRuntimeVersion -Value ''
Set-ItemProperty -LiteralPath $poolPath -Name enable32BitAppOnWin64 -Value $false
Set-ItemProperty -LiteralPath $poolPath -Name processModel.identityType -Value 4

# Grant only this site's application pool read/execute access to the release.
& icacls.exe $releasePath /grant "IIS AppPool\${poolName}:(OI)(CI)RX" /T /Q
if ($LASTEXITCODE -ne 0) { throw 'Failed to grant the application pool access to the release.' }

try {
    if ($siteExists) {
        Set-ItemProperty -LiteralPath $sitePath -Name physicalPath -Value $releasePath
        if ((Get-WebAppPoolState -Name $poolName).Value -eq 'Started') {
            Restart-WebAppPool -Name $poolName
        } else {
            Start-WebAppPool -Name $poolName
        }
    } else {
        New-Website -Name $siteName -PhysicalPath $releasePath -ApplicationPool $poolName -Port $port | Out-Null
        if ((Get-WebAppPoolState -Name $poolName).Value -ne 'Started') { Start-WebAppPool -Name $poolName }
    }
    Start-Website -Name $siteName
    $healthy = $false
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $env:IIS_HEALTH_URL -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -eq 200) { $healthy = $true; break }
        } catch {
            Write-Warning "Health check attempt $attempt failed: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 5
    }
    if (-not $healthy) { throw "Health check failed: $($env:IIS_HEALTH_URL)" }
    Write-Host "Deployed release to $releasePath"
} catch {
    $failure = $_
    if ($siteExists) {
        Set-ItemProperty -LiteralPath $sitePath -Name physicalPath -Value $previousPath
        if ((Get-WebAppPoolState -Name $poolName).Value -eq 'Started') {
            Restart-WebAppPool -Name $poolName
        } else {
            Start-WebAppPool -Name $poolName
        }
        Start-Website -Name $siteName
        Write-Warning "Restored previous site path: $previousPath"
    } elseif (Test-Path -LiteralPath $sitePath) {
        Stop-Website -Name $siteName
    }
    throw $failure
}
