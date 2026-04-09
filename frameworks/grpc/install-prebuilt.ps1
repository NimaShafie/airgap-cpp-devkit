# Author: Nima Shafie
# =============================================================================
# install-prebuilt.ps1
# Installs prebuilt gRPC binaries from the prebuilt-binaries submodule.
# No build required -- extracts directly to the destination path.
#
# Run from: frameworks/grpc/
# Run in:   any PowerShell
#
# USAGE:
#   cd frameworks\grpc
#   .\install-prebuilt.ps1 -version 1.78.1 -dest "C:\MyPath\grpc-1.78.1"
#
# OPTIONS:
#   -version <ver>    gRPC version to install (default: 1.78.1)
#   -dest    <path>   Install destination (default: auto-detected)
# =============================================================================

param(
    [string]$version = "1.78.1",
    [string]$dest    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot    = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$PrebuiltDir = Join-Path $RepoRoot "prebuilt-binaries\frameworks\grpc\windows\$version"

function Info  { param($m) Write-Host "[INFO] $m" }
function Warn  { param($m) Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Step  { param($m) Write-Host ""; Write-Host "*** $m ***" }
function Die   { param($m) Err $m; exit 1 }
function OK    { param($m) Write-Host "[OK] $m" -ForegroundColor Green }

function Require-Exit {
    param($code, $msg)
    if ($code -ne 0) { Die "$msg (exit $code)" }
}

function Format-Size {
    param($bytes)
    if ($bytes -gt 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -gt 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

# -----------------------------
# Step 1: Determine install dest
# -----------------------------
Step "Determining install destination"
if (-not $dest) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        $dest = "C:\Program Files\airgap-cpp-devkit\grpc-$version"
        Info "Admin rights detected. Installing system-wide."
    } else {
        $dest = "$env:LOCALAPPDATA\airgap-cpp-devkit\grpc-$version"
        Warn "No admin rights. Installing for current user only."
        Warn "Re-run as Administrator for system-wide install."
    }
}
Info "Install destination: $dest"

# -----------------------------
# Step 2: Check prebuilt parts exist
# -----------------------------
Step "Locating prebuilt parts"
if (-not (Test-Path $PrebuiltDir)) {
    Die "Prebuilt directory not found: $PrebuiltDir`nRun: git submodule update --init prebuilt-binaries"
}

$archiveName = "grpc-$version-windows-x64.zip"
$parts = Get-ChildItem $PrebuiltDir -Filter "$archiveName.part-*" -ErrorAction SilentlyContinue | Sort-Object Name

if ($parts.Count -eq 0) {
    Die "No prebuilt parts found in $PrebuiltDir for v$version"
}

Info "Found $($parts.Count) part(s):"
foreach ($p in $parts) { Info "  $($p.Name)  ($(Format-Size $p.Length))" }

# -----------------------------
# Step 3: Reassemble parts
# -----------------------------
Step "Reassembling archive from parts"

$tmpDir     = Join-Path $env:TEMP "grpc-prebuilt-$version"
$tmpArchive = Join-Path $tmpDir $archiveName

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

Info "Reassembling to $tmpArchive ..."
$outStream = [System.IO.File]::OpenWrite($tmpArchive)
try {
    foreach ($p in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $outStream.Write($bytes, 0, $bytes.Length)
    }
} finally {
    $outStream.Close()
}

$archiveSize = (Get-Item $tmpArchive).Length
OK "Archive reassembled: $(Format-Size $archiveSize)"

# -----------------------------
# Step 4: Verify SHA256
# -----------------------------
Step "Verifying archive integrity"

$manifestPath = Join-Path $PrebuiltDir "manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $expectedHash = $manifest.archives.zip.sha256
    if ($expectedHash) {
        $actualHash = (Get-FileHash $tmpArchive -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $expectedHash.ToLower()) {
            Remove-Item $tmpDir -Recurse -Force
            Die "SHA256 mismatch!`n  Expected: $expectedHash`n  Actual:   $actualHash"
        }
        OK "SHA256 verified."
    } else {
        Warn "No SHA256 in manifest -- skipping verification."
    }
} else {
    Warn "manifest.json not found -- skipping integrity check."
}

# -----------------------------
# Step 5: Extract
# -----------------------------
Step "Extracting to $dest"
if (Test-Path $dest) {
    $ans = Read-Host "Destination already exists. Overwrite? (y/n)"
    if ($ans -notmatch '^[Yy]') { Die "Aborted." }
    Remove-Item $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest -Force | Out-Null

# Use .NET for zip -- no 7-Zip dependency
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tmpArchive, $dest)

# -----------------------------
# Step 6: Cleanup temp
# -----------------------------
Remove-Item $tmpDir -Recurse -Force

# -----------------------------
# Verify key binaries
# -----------------------------
Step "Verifying installation"
$checks = @(
    "bin\protoc.exe",
    "bin\grpc_cpp_plugin.exe",
    "include\grpc\grpc.h",
    "lib\grpc.lib"
)
$allOk = $true
foreach ($c in $checks) {
    $p = Join-Path $dest $c
    if (Test-Path $p) {
        OK "$c"
    } else {
        Warn "Not found: $c"
        $allOk = $false
    }
}

Write-Host ""
if ($allOk) {
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " gRPC v$version prebuilt installed successfully" -ForegroundColor Green
    Write-Host " Location : $dest" -ForegroundColor Green
    Write-Host " protoc   : $dest\bin\protoc.exe" -ForegroundColor Green
    Write-Host " plugin   : $dest\bin\grpc_cpp_plugin.exe" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
} else {
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " gRPC v$version installed with warnings -- some files missing" -ForegroundColor Yellow
    Write-Host " Location : $dest" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
}