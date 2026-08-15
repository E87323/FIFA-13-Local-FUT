[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$settingsPath = Join-Path $root 'local.settings.json'
if (-not (Test-Path -LiteralPath $settingsPath)) { throw "Missing $settingsPath" }
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

$gameExe = Join-Path $settings.gameDirectory 'fifa13.exe'
$cardsDll = Join-Path $settings.gameDirectory 'dlc\dlc_CardsDLL\dlc\CardsDLLzf.dll'
foreach ($path in @($gameExe, $cardsDll, $settings.python)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file is missing: $path" }
}

$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cardsDll).Hash
if ($dllHash -ne $settings.cardsDllSha256) { throw "CardsDLLzf.dll hash changed: $dllHash" }
Write-Host 'PASS fifa13.exe present + matched CardsDLL hash (CL1298564 Store profile)' -ForegroundColor Green

$fridaPackages = Join-Path $root $settings.fridaSitePackages
if (-not (Test-Path -LiteralPath $fridaPackages)) { throw "Frida package directory is missing: $fridaPackages" }
$previousPythonPath = $env:PYTHONPATH
$env:PYTHONPATH = if ($previousPythonPath) { "$fridaPackages;$previousPythonPath" } else { $fridaPackages }
try {
    $runtimeChecker = Join-Path $root 'tools\check_python_runtime.py'
    $fridaCheck = & $settings.python $runtimeChecker --modules frida --show-frida-version 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("Frida import failed: {0}" -f (($fridaCheck | Out-String).Trim())) }
    $fridaLine = @($fridaCheck | Where-Object { [string]$_ -like 'Frida *' } | Select-Object -First 1)
    Write-Host ("PASS {0}" -f ([string]$fridaLine).Trim()) -ForegroundColor Green
}
finally { $env:PYTHONPATH = $previousPythonPath }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\test_bridge_offline.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Offline Blaze bridge tests failed.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\test_http_offline.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Offline HTTP tests failed.' }

$proxyExe = Join-Path $root 'src\trace-proxy\out\Fut13Local.TraceProxy.exe'
if (-not (Test-Path -LiteralPath $proxyExe)) { throw "Trace proxy build is missing: $proxyExe" }
Write-Host 'PASS trace proxy build present' -ForegroundColor Green
Write-Host 'ALL FIFA 13 LOCAL PREFLIGHT TESTS PASSED' -ForegroundColor Green
