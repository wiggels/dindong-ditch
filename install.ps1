# dingdong-ditch installer for Windows
#
#   irm https://raw.githubusercontent.com/wiggels/dindong-ditch/main/install.ps1 | iex
#
# What it does:
#   1. Downloads the latest release binary and installs it to
#      %LOCALAPPDATA%\Programs\dingdong-ditch (checksum-verified).
#   2. Adds that directory to your user PATH.
#
# No admin needed: Zoom's sounds live in %APPDATA%\Zoom\bin, which is yours.
#
# Uninstall:
#   Remove-Item -Recurse "$env:LOCALAPPDATA\Programs\dingdong-ditch"
#   then remove that directory from your user PATH.

$ErrorActionPreference = "Stop"

$repo = if ($env:DINGDONG_REPO) { $env:DINGDONG_REPO } else { "wiggels/dindong-ditch" }
$target = "x86_64-pc-windows-msvc"  # ARM PCs run this fine via emulation
$installDir = Join-Path $env:LOCALAPPDATA "Programs\dingdong-ditch"

Write-Host "==> Finding latest release of $repo..." -ForegroundColor Green
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$tag = $release.tag_name
$version = $tag.TrimStart("v")
Write-Host "==> Latest release: $tag" -ForegroundColor Green

$asset = "dingdong-ditch-$version-$target.zip"
$base = "https://github.com/$repo/releases/download/$tag"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "dingdong-ditch-install"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    Write-Host "==> Downloading $asset..." -ForegroundColor Green
    Invoke-WebRequest -Uri "$base/$asset" -OutFile (Join-Path $tmp $asset)
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile (Join-Path $tmp "SHA256SUMS")

    Write-Host "==> Verifying checksum..." -ForegroundColor Green
    $sumLine = Get-Content (Join-Path $tmp "SHA256SUMS") | Where-Object { $_ -match [regex]::Escape($asset) }
    if (-not $sumLine) { throw "no checksum found for $asset" }
    $expected = ($sumLine -split '\s+')[0]
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp $asset)).Hash
    if ($actual -ne $expected) { throw "checksum verification failed for $asset" }

    Write-Host "==> Installing to $installDir..." -ForegroundColor Green
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Expand-Archive -Force -Path (Join-Path $tmp $asset) -DestinationPath $installDir
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# Add to the user PATH (registry) and the current session
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (($userPath -split ';') -notcontains $installDir) {
    Write-Host "==> Adding $installDir to your user PATH..." -ForegroundColor Green
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
}
if (($env:Path -split ';') -notcontains $installDir) {
    $env:Path = "$env:Path;$installDir"
}

Write-Host ""
Write-Host "==> Done! (open a new terminal if the command isn't found)" -ForegroundColor Green
Write-Host "      dingdong-ditch           # silence Zoom's doorbell"
Write-Host "      dingdong-ditch --fart    # make it fart"
Write-Host "      dingdong-ditch --aim     # party like it's 1999"
Write-Host "      dingdong-ditch --restore # bring the dingdong back"
