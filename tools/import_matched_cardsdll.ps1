[CmdletBinding()]
param([string]$Source)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$expected='35BDAC6BB2F37F4E3F674C5BB979BCB607FEB11CD09105631796D566590FFC06'
if(-not $Source){$Source=Read-Host 'Enter the full path to your legally obtained CL1298564 CardsDLLzf.dll'}
$Source=([string]$Source).Trim().Trim('"')
if(-not (Test-Path -LiteralPath $Source -PathType Leaf)){throw "File not found: $Source"}
$hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
if($hash -ne $expected){throw "Wrong CardsDLL hash. Expected $expected but found $hash. Nothing was copied."}
$required=Join-Path $root 'required'
New-Item -ItemType Directory -Force -Path $required|Out-Null
$dest=Join-Path $required 'CardsDLLzf.dll'
Copy-Item -LiteralPath $Source -Destination $dest -Force
$verify=(Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash
if($verify -ne $expected){throw 'Copied DLL failed verification.'}
Write-Host ('Imported matched CardsDLL to: {0}' -f $dest) -ForegroundColor Green
Write-Host 'RUN_LOCAL_FUT13.cmd will now back up/swap an incompatible installed DLL automatically.' -ForegroundColor Green
