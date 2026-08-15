# Serves the DIME/store config files the FUT launcher downloads, and logs every
# request. Replaces the observe-only capture server now that the exact URLs are
# known: the client fetches DIME_FILES_PATH + {dimecfg.xml, storecfg.xml,
# storedesc-<locale>.xml} using ProtoHttp (DirtySock).
#
# Files are served from the local .\dime directory. Anything not present is
# answered 404 and logged, so a missing name shows up plainly instead of being
# masked by an empty 200.

param(
    [int] $Port = 80,
    # FIFA 13 hardcodes http://89.234.41.144:8080/onlineAssets/2012/fut as the
    # FUT dynamic-messages base (VA 0x0244a54c). A hosts file cannot redirect a
    # literal IP, so that address is added as a loopback alias and this server
    # is pointed at it. Default stays on loopback for the DIME role.
    [string] $BindAddress = '127.0.0.1',
    # The portable archive ships its XML under server\config. Older working
    # copies also had server\dime; defaulting to that absent folder made every
    # request return 404 while the listener itself looked healthy.
    [string] $Root = (Join-Path $PSScriptRoot 'config'),
    # Canonical XML extracted from this exact FIFA 13 installation.  The
    # hand-authored files in .\dime stay available for later controlled
    # experiments, but normal startup must see the real DIME schemas.
    [string] $CanonicalRoot = (Join-Path $PSScriptRoot '..\analysis\extracted'),
    # The store description file is per-locale: the client asks for
    # storedesc-<locale>.xml, and the locale is the one the game was installed
    # with. fre_fr is the default only because that is the installation this was
    # developed against -- change it to match yours (eng_us, ger_de, spa_es, ...)
    # and both the alias and the canonical filename follow.
    [string] $Locale = 'eng_us'
)

$ErrorActionPreference = 'Stop'
$traceSession = $env:FUT13_TRACE_SESSION
$logName = if ($traceSession) { "fut13-dime-$Port-$traceSession.log" } else { "fut13-dime-$Port.log" }
$logPath = Join-Path $PSScriptRoot $logName

$storeDescName = "storedesc-$Locale.xml"

# USE_LOCAL_CFGFILES makes FIFA 13 request these exact local-name variants.
# They are aliases, not invented documents: their payload is the corresponding
# DIME/store XML that the client has already successfully downloaded.
$aliases = @{
    'dimecfglocal.xml' = 'dimecfg.xml'
    'storecfglocal.xml' = 'storecfg.xml'
    'storedesclocal.xml' = $storeDescName
}

$canonicalFiles = @{
    'dimecfg.xml'  = 'installed-dimecfg.xml'
    'storecfg.xml' = 'installed-storecfg.xml'
    $storeDescName = "installed-$storeDescName"
}

function Write-Log([string] $Message) {
    # Full date, not just the time. The log is appended to across days, and a
    # time-only stamp made entries from a previous session read as if they had
    # just happened — which is exactly how a run from the day before was once
    # mistaken for live traffic during a trace.
    $line = '[{0:yyyy-MM-dd HH:mm:ss.fff}] {1}' -f (Get-Date), $Message
    [Console]::WriteLine($line)
    Add-Content -LiteralPath $logPath -Value $line
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse($BindAddress), $Port)
$listener.Start()
Write-Log ("DIME server on http://{0}:{1}/  root={2}  locale={3}" -f $BindAddress, $Port, $Root, $Locale)

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 5000
            $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 4096, $true)

            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Dispose(); continue }
            while ($true) {
                $h = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($h)) { break }
            }

            $path = ($requestLine -split '\s+')[1]
            $name = [System.IO.Path]::GetFileName(($path -split '\?')[0])
            $servedName = if ($name -and $aliases.ContainsKey($name)) { $aliases[$name] } else { $name }
            # v0.11: respect the installation locale. If an uncommon locale
            # has no local descriptor yet, fall back to the shipped English
            # descriptor rather than silently serving the old French fixture.
            if ($servedName -and $servedName -like 'storedesc-*.xml' -and
                -not (Test-Path -LiteralPath (Join-Path $Root $servedName))) {
                $servedName = 'storedesc-eng_us.xml'
            }

            # v0.13.17: match the working donor for all OPTIONAL DIME/Store
            # config groups. The donor ships no dimecfg/storecfg/storedesc
            # payloads; its cfg-file server returns 404 and fifa13.exe retries
            # these groups without treating them as the FUT launch gate. Our
            # dimecfg/storecfg files were hand-authored experiments, not retail
            # captures, so do not let them initialise Store objects. The only
            # launch-gating configuration remains the known-good FutCfg path.
            $donorOptionalConfig404 = $false
            if ($name -and (($name -like 'dimecfg*.xml') -or ($name -like 'storecfg*.xml') -or ($name -like 'storedesc*.xml'))) {
                $donorOptionalConfig404 = $true
            }

            $canonicalName = if ($servedName -and $canonicalFiles.ContainsKey($servedName)) { $canonicalFiles[$servedName] } else { $null }
            $canonicalFile = if ($canonicalName) { Join-Path $CanonicalRoot $canonicalName } else { $null }
            $file = if ($canonicalFile -and (Test-Path -LiteralPath $canonicalFile)) {
                $canonicalFile
            } elseif ($servedName) {
                Join-Path $Root $servedName
            } else {
                $null
            }
            if ($donorOptionalConfig404) { $file = $null }

            # Exact donor port-8080 fallback. Missing parsed content such as
            # storepackdescriptions gets text/json {}, but a request that looks
            # like an image must receive a real image/png payload. The donor
            # does this for .png/.jpg/.big/image paths so Flash's asset loader
            # completes with a non-zero width instead of parsing JSON as art.
            $donorGenericJson = $false
            $donorImagePlaceholder = $false
            if ($name -and $name -like 'storepackdescriptions.*.xml') {
                $file = $null
                $donorGenericJson = $true
                Write-Log ("STORE DONOR v0.13.20: generic JSON fallback for {0}" -f $name)
            } elseif ($name -and ($name -like 'packs_backgrounds_*.png' -or
                                  $name -like 'packs_icons_*.png')) {
                $file = $null
                $donorImagePlaceholder = $true
                Write-Log ("STORE DONOR v0.13.20: image placeholder fallback for {0}" -f $name)
            }

            if ($donorOptionalConfig404) {
                $bytes = [byte[]]@()
                $head  = "HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n"
                Write-Log ("404  {0}  -> donor optional-config parity (no synthetic dimecfg/storecfg/storedesc)" -f $requestLine)
            } elseif ($file -and (Test-Path -LiteralPath $file)) {
                $bytes = [System.IO.File]::ReadAllBytes($file)
                $extension = [System.IO.Path]::GetExtension($file).ToLowerInvariant()
                $contentType = switch ($extension) {
                    '.png'  { 'image/png' }
                    '.jpg'  { 'image/jpeg' }
                    '.jpeg' { 'image/jpeg' }
                    '.json' { 'application/json' }
                    default { 'text/xml' }
                }
                $head  = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                $source = if ($file -eq $canonicalFile) { "canonical:$canonicalName" } else { "custom:$servedName" }
                Write-Log ("200  {0}  -> {1} ({2} bytes)" -f $requestLine, $source, $bytes.Length)
            } elseif ($donorImagePlaceholder) {
                # Reuse a known-valid PNG already shipped by the package. Any
                # valid non-zero-size PNG is sufficient for this donor fallback.
                $placeholder = Join-Path $Root 'packs_backgrounds_3.png'
                if (-not (Test-Path -LiteralPath $placeholder)) {
                    $placeholder = Join-Path $CanonicalRoot 'packs_backgrounds_3.png'
                }
                if (-not (Test-Path -LiteralPath $placeholder)) {
                    throw "Donor image placeholder is missing: packs_backgrounds_3.png"
                }
                $bytes = [System.IO.File]::ReadAllBytes($placeholder)
                $head  = "HTTP/1.1 200 OK`r`nContent-Type: image/png`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                Write-Log ("200  {0}  -> donor image/png placeholder ({1} bytes)" -f $requestLine, $bytes.Length)
            } elseif ($donorGenericJson) {
                $bytes = [Text.Encoding]::UTF8.GetBytes("{}")
                $head  = "HTTP/1.1 200 OK`r`nContent-Type: text/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                Write-Log ("200  {0}  -> donor-generic:{{}}" -f $requestLine)
            } else {
                # Working donor behavior for every unknown 8080 content asset:
                # return an empty JSON object rather than inventing a payload.
                $bytes = [Text.Encoding]::UTF8.GetBytes("{}")
                $head  = "HTTP/1.1 200 OK`r`nContent-Type: text/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
                Write-Log ("200  {0}  -> donor-generic:{{}} (missing content asset: {1})" -f $requestLine, $name)
            }

            $headBytes = [Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($headBytes, 0, $headBytes.Length)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush()
        } catch {
            Write-Log ("ERR  {0}" -f $_.Exception.Message)
        } finally {
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
    Write-Log "DIME server stopped"
}
