# Remote Control installer for Windows.
#   irm https://brizzad.github.io/remote-control-site/install.ps1 | iex
# Run it in a normal (non-admin) PowerShell window; it asks for administrator
# rights once, to install the background service. Running it again upgrades
# the agent and keeps this computer's ID and account.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo = if ($env:RC_RELEASE_URL) { $env:RC_RELEASE_URL } else { 'https://github.com/brizzad/remote-control-site/releases/latest/download' }
$App = 'https://brizzad.github.io/remote-control-site/app/'
$Asset = 'rcagent-windows-x86_64.exe'

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }

if (-not [Environment]::Is64BitOperatingSystem) { throw 'Remote Control needs 64-bit Windows.' }

$dir = Join-Path $env:LOCALAPPDATA 'RemoteControl'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$exe = Join-Path $dir 'rcagent.exe'
$download = Join-Path $dir "$Asset.download"

Say 'Downloading Remote Control'
try {
  $sums = (Invoke-WebRequest -UseBasicParsing -Uri "$Repo/SHA256SUMS").Content
} catch {
  throw "Could not download the release checksums from $Repo (is there a release yet?): $($_.Exception.Message)"
}
if ($sums -is [byte[]]) { $sums = [Text.Encoding]::ASCII.GetString($sums) }
try {
  Invoke-WebRequest -UseBasicParsing -Uri "$Repo/$Asset" -OutFile $download
} catch {
  throw "Could not download Remote Control from $Repo (is there a release yet?): $($_.Exception.Message)"
}
$line = ($sums -split "`n") | Where-Object { $_ -match "^([0-9a-f]{64})  $([regex]::Escape($Asset))\s*$" } | Select-Object -First 1
if (-not $line) { Remove-Item $download; throw "$Asset is not listed in the release checksums." }
$expected = ($line -split '\s+')[0]
$actual = (Get-FileHash -Algorithm SHA256 $download).Hash.ToLowerInvariant()
if ($actual -ne $expected) { Remove-Item $download; throw "$Asset failed its checksum (expected $expected, got $actual); not installing it." }
Move-Item -Force $download $exe
Unblock-File $exe
& $exe --version
if ($LASTEXITCODE -ne 0) { throw "rcagent.exe does not run on this computer (exit code $LASTEXITCODE)." }
# Tests stop here (download and checksum only).
if ($env:RC_DOWNLOAD_ONLY) { Say "Downloaded and verified $Asset"; return }

$config = Join-Path $env:APPDATA 'RemoteControl\agent.json'
Say 'Setting up this computer'
# An existing setup is kept (rcagent setup --force replaces the account).
& $exe --config $config setup
if ($LASTEXITCODE -ne 0) { throw 'Setup did not finish.' }

Say 'Installing the background service (Windows asks for administrator rights)'
$p = Start-Process -FilePath $exe -ArgumentList @('--config', "`"$config`"", 'service', 'install') -Verb RunAs -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Service installation failed (exit code $($p.ExitCode))." }

Write-Host ''
& $exe --config $config status | Select-String '^id:' | ForEach-Object { Write-Host ($_ -replace '^id:\s*', 'Computer ID: ') }
Say "Connect from $App"
