# Wait for FIFA 13 to be ready, then attach the tracer — no manual cue needed.
#
# Attaching at process birth kills the client (it decrypts its own .text during
# startup), so the rule has always been "attach once it is idle at the main
# menu". The reliable machine-readable signal for that moment is `loginPersona`
# appearing in the current bridge log: the Blaze bootstrap completes just before
# the menu is interactive.
#
# Waits for: fifa13.exe running -> loginPersona in the newest bridge log -> a
# short settle delay -> attach.

param(
    [int] $Seconds = 3600,
    [int] $SettleSeconds = 6,
    [int] $TimeoutSeconds = 300,
    # The tracer needs a Python interpreter with Frida installed. There is no
    # interpreter bundled with this repository, so this resolves, in order: the
    # -Python argument, the FIFA13_PYTHON environment variable, then plain
    # `python` from PATH.
    [string] $Python = $(if ($env:FIFA13_PYTHON) { $env:FIFA13_PYTHON } else { 'python' }),
    # Where restart_bridge.ps1 writes the bridge log this script watches. Keep
    # the two scripts in agreement when changing it.
    [string] $LogDirectory,
    # Optional process manifest written by START_FIFA13_LOCAL.ps1. Recording
    # the exact tracer PID lets STOP_FIFA13_LOCAL.ps1 clean it up without ever
    # terminating unrelated Python processes.
    [string] $RuntimePath,
    [string] $SessionId
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path $root 'local.settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($Python -eq 'python' -and $settings.python) { $Python = [string]$settings.python }
    if ($settings.fridaSitePackages) {
        $fridaPackages = if ([System.IO.Path]::IsPathRooted([string]$settings.fridaSitePackages)) {
            [string]$settings.fridaSitePackages
        } else {
            Join-Path $root ([string]$settings.fridaSitePackages)
        }
        if (Test-Path -LiteralPath $fridaPackages) {
            $env:PYTHONPATH = if ($env:PYTHONPATH) {
                "$fridaPackages;$env:PYTHONPATH"
            } else {
                $fridaPackages
            }
        }
    }
}
if (-not $LogDirectory) { $LogDirectory = Join-Path $root 'logs' }
$tracer = Join-Path $PSScriptRoot 'trace_fifa13_futgate.py'
if (-not (Test-Path -LiteralPath $tracer)) { throw "Tracer script not found: $tracer" }

# Get-Command resolves a bare name against PATH and a full path against the file
# system, so both forms of -Python are handled here.
$resolved = Get-Command $Python -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
if (-not $resolved) {
    throw ("Python interpreter '{0}' not found.`r`nPass -Python <path to python.exe>, or set the FIFA13_PYTHON environment variable to the interpreter that has Frida installed." -f $Python)
}
$pythonExe = $resolved.Source

# Probing the import is the only reliable check: Frida is installed per
# interpreter, so `python` being on PATH says nothing about whether the tracer
# can run. stderr is deliberately not redirected -- the ImportError traceback is
# useful context next to the message below.
$runtimeChecker = Join-Path $PSScriptRoot 'check_python_runtime.py'
& $pythonExe $runtimeChecker --modules frida 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw ("Frida is not importable by {0}.`r`nInstall the tool dependencies into that interpreter:`r`n    & '{0}' -m pip install -r tools/requirements.txt`r`nOr point -Python (or the FIFA13_PYTHON environment variable) at an interpreter that already has Frida." -f $pythonExe)
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

Write-Host 'Waiting for fifa13.exe...' -ForegroundColor Cyan
while (-not (Get-Process fifa13 -ErrorAction SilentlyContinue)) {
    if ((Get-Date) -gt $deadline) { throw 'fifa13.exe is not starting' }
    Start-Sleep -Seconds 2
}
$game = Get-Process fifa13
Write-Host ("fifa13.exe PID {0}" -f $game.Id) -ForegroundColor Green

Write-Host 'Waiting for the Blaze session (loginPersona)...' -ForegroundColor Cyan
while ($true) {
    if ((Get-Date) -gt $deadline) { throw 'no loginPersona -- was the bridge restarted for this launch?' }
    $log = Get-ChildItem (Join-Path $LogDirectory 'bridge-*.out.log') -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log -and (Select-String -Path $log.FullName -Pattern 'loginPersona' -Quiet)) { break }
    Start-Sleep -Seconds 2
}
Write-Host 'Session established.' -ForegroundColor Green

Start-Sleep -Seconds $SettleSeconds
Write-Host 'Attaching the tracer...' -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$tracerOut = Join-Path $LogDirectory $(if ($SessionId) { "tracer-$SessionId.out.log" } else { 'tracer.out.log' })
$tracerErr = Join-Path $LogDirectory $(if ($SessionId) { "tracer-$SessionId.err.log" } else { 'tracer.err.log' })
$nativeTrace = if ($SessionId) { Join-Path $root ("artifacts\fifa13-native-$SessionId.jsonl") } else { $null }

# Codex may supply both `Path` and `PATH`. Start-Process copies the environment
# into a case-insensitive dictionary and otherwise fails before Python starts.
$pathKeys = @([Environment]::GetEnvironmentVariables().Keys |
    Where-Object { $_ -cmatch '^(Path|PATH)$' })
if ($pathKeys -contains 'Path' -and $pathKeys -contains 'PATH') {
    [Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
}

# Detached on purpose. Running the tracer in the foreground makes it share this
# wrapper's lifetime: when the caller considers the wrapper finished, the tracer
# dies with it and the journal stops at its `ready` event — which happened once,
# and looked exactly like "the game produced no events".
$tracerArgs = @($tracer, '--seconds', $Seconds)
if ($nativeTrace) { $tracerArgs += @('--log', $nativeTrace) }
$tracerProcess = Start-Process -FilePath $pythonExe -ArgumentList $tracerArgs `
    -RedirectStandardOutput $tracerOut `
    -RedirectStandardError  $tracerErr `
    -WindowStyle Hidden -PassThru
Start-Sleep -Seconds 4

# The started process object, not a name-and-start-time guess: the interpreter
# may be a venv python, a python3.exe or anything else -Python points at, and
# matching it by process name would be wrong for all of those.
if (-not $tracerProcess.HasExited) {
    Write-Host ("Tracer running, detached (PID {0})." -f $tracerProcess.Id) -ForegroundColor Green
    if ($RuntimePath -and (Test-Path -LiteralPath $RuntimePath)) {
        $runtime = Get-Content -LiteralPath $RuntimePath -Raw | ConvertFrom-Json
        $entries = @($runtime.processes) + [pscustomobject]@{
            name = 'tracer'
            pid = $tracerProcess.Id
            startedUtc = $tracerProcess.StartTime.ToUniversalTime().ToString('o')
        }
        @{ startedUtc = $runtime.startedUtc; processes = $entries } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $RuntimePath -Encoding UTF8
    }
} else {
    Write-Host ("The tracer exited immediately (code {0}) -- see {1}" -f $tracerProcess.ExitCode, $tracerErr) -ForegroundColor Red
}
