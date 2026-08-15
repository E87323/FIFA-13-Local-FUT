[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $PSScriptRoot 'runtime\processes.json'
if (-not (Test-Path -LiteralPath $runtimePath)) {
    Write-Host 'No FIFA 13 local runtime manifest exists.'
    return
}

$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
foreach ($entry in @($runtime.processes)) {
    $process = Get-Process -Id ([int]$entry.pid) -ErrorAction SilentlyContinue
    if (-not $process) { continue }
    if ($process.StartTime.ToUniversalTime().ToString('o') -ne $entry.startedUtc) {
        Write-Warning "PID $($entry.pid) was reused; leaving it untouched."
        continue
    }
    Stop-Process -Id $process.Id -Force
    Write-Host "Stopped $($entry.name) (PID $($entry.pid))."
}
Remove-Item -LiteralPath $runtimePath -Force
