[CmdletBinding()]
param(
    [switch]$SkipPreflight,
    [switch]$NoAutoAttach,
    [string]$SessionId
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
foreach ($relativeDirectory in @('runtime', 'logs', 'artifacts')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $relativeDirectory) | Out-Null
}
$settings = Get-Content -LiteralPath (Join-Path $root 'local.settings.json') -Raw | ConvertFrom-Json

$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
if (-not (Select-String -LiteralPath $hostsPath -SimpleMatch '127.0.0.1 gosredirector.ea.com' -Quiet)) {
    throw 'Local DNS redirect is missing. Run .\SETUP_FIFA13_HOSTS.ps1 once as Administrator.'
}

if (-not $SkipPreflight) {
    & (Join-Path $root 'TEST_FIFA13_LOCAL.ps1')
}

if (-not $SessionId) { $SessionId = Get-Date -Format 'yyyyMMdd-HHmmss' }
& (Join-Path $root 'tools\restart_bridge.ps1') -SessionId $SessionId

if (-not $NoAutoAttach) {
    $fridaPackages = if ([System.IO.Path]::IsPathRooted([string]$settings.fridaSitePackages)) {
        [string]$settings.fridaSitePackages
    } else {
        Join-Path $root ([string]$settings.fridaSitePackages)
    }
    $previousPythonPath = $env:PYTHONPATH
    $env:PYTHONPATH = if ($previousPythonPath) { "$fridaPackages;$previousPythonPath" } else { $fridaPackages }
    $autoLog = Join-Path $root ("logs\autoattach-$SessionId.out.log")
    $autoErr = Join-Path $root ("logs\autoattach-$SessionId.err.log")
    try {
        $auto = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path $root 'tools\autoattach.ps1'), '-Python', $settings.python,
            '-LogDirectory', (Join-Path $root 'logs'),
            '-RuntimePath', (Join-Path $root 'runtime\processes.json'),
            '-SessionId', $SessionId) `
            -RedirectStandardOutput $autoLog -RedirectStandardError $autoErr `
            -WindowStyle Hidden -PassThru
    }
    finally { $env:PYTHONPATH = $previousPythonPath }

    $runtimePath = Join-Path $root 'runtime\processes.json'
    $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
    $entries = @($runtime.processes) + [pscustomobject]@{
        name = 'autoattach'
        pid = $auto.Id
        startedUtc = $auto.StartTime.ToUniversalTime().ToString('o')
    }
    @{ startedUtc = $runtime.startedUtc; processes = $entries } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $runtimePath -Encoding UTF8
}

Write-Host ''
Write-Host 'FIFA 13 local services are ready.' -ForegroundColor Green
Write-Host "Launch FIFA 13 normally from this installation: $($settings.gameDirectory)\fifa13.exe"
Write-Host 'The helper will attach only after the local Blaze login reaches the main-menu stage.'
Write-Host ("Reverse-engineering trace session: {0}" -f $SessionId) -ForegroundColor Cyan
Write-Host 'Use .\STOP_FIFA13_LOCAL.ps1 when finished.'
