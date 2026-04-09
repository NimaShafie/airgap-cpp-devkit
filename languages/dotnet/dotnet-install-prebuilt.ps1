# Author: Nima Shafie
# =============================================================================
# dotnet-install-prebuilt.ps1
# Installs .NET 10 SDK from prebuilt-binaries submodule.
# No internet access, no system installer, no elevation required for user install.
#
# Run from: languages/dotnet/ OR repo root
# Run in:   any PowerShell
#
# USAGE:
#   cd languages\dotnet
#   .\dotnet-install-prebuilt.ps1
#   .\dotnet-install-prebuilt.ps1 -dest "C:\MyPath\dotnet"
#
# OPTIONS:
#   -dest <path>    Install destination (default: auto-detected)
# =============================================================================

param(
    [string]$dest = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot     = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SDK_VERSION  = "10.0.201"
$PrebuiltDir  = Join-Path $RepoRoot "prebuilt-binaries\languages\dotnet\$SDK_VERSION"

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
        $dest = "C:\Program Files\airgap-cpp-devkit\dotnet"
        Info "Admin rights detected. Installing system-wide."
    } else {
        $dest = "$env:LOCALAPPDATA\airgap-cpp-devkit\dotnet"
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

$archiveName = "dotnet-sdk-$SDK_VERSION-win-x64.zip"
$parts = Get-ChildItem $PrebuiltDir -Filter "$archiveName.part-*" -ErrorAction SilentlyContinue | Sort-Object Name

if ($parts.Count -eq 0) {
    Die "No prebuilt parts found in $PrebuiltDir for SDK $SDK_VERSION"
}

Info "Found $($parts.Count) part(s):"
foreach ($p in $parts) { Info "  $($p.Name)  ($(Format-Size $p.Length))" }

# -----------------------------
# Step 3: Reassemble
# -----------------------------
Step "Reassembling archive from parts"

$tmpDir     = Join-Path $env:TEMP "dotnet-prebuilt-$SDK_VERSION"
$tmpArchive = Join-Path $tmpDir $archiveName

if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

Info "Reassembling..."
$outStream = [System.IO.File]::OpenWrite($tmpArchive)
try {
    foreach ($p in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $outStream.Write($bytes, 0, $bytes.Length)
    }
} finally { $outStream.Close() }
OK "Reassembled: $(Format-Size (Get-Item $tmpArchive).Length)"

# -----------------------------
# Step 4: Verify SHA256
# -----------------------------
Step "Verifying integrity"
$manifestPath = Join-Path $PrebuiltDir "manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $expectedHash = $manifest.platforms."windows-x64".sha256
    if ($expectedHash) {
        $actualHash = (Get-FileHash $tmpArchive -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $expectedHash.ToLower()) {
            Remove-Item $tmpDir -Recurse -Force
            Die "SHA256 mismatch!`n  Expected: $expectedHash`n  Actual:   $actualHash"
        }
        OK "SHA256 verified."
    } else {
        Warn "No hash in manifest -- skipping verification."
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

Remove-Item $tmpDir -Recurse -Force

# -----------------------------
# Step 6: Verify
# -----------------------------
Step "Verifying installation"
$dotnetExe = Join-Path $dest "dotnet.exe"
if (Test-Path $dotnetExe) {
    $ver = & "$dotnetExe" --version 2>&1
    OK "dotnet.exe found: $ver"
} else {
    Die "dotnet.exe not found at $dest -- extraction may have failed."
}

# -----------------------------
# Done
# -----------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " .NET SDK $SDK_VERSION installed successfully" -ForegroundColor Green
Write-Host " Location : $dest" -ForegroundColor Green
Write-Host " dotnet   : $dest\dotnet.exe" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Add to PATH for this session:"
Write-Host "  `$env:PATH = `"$dest;`$env:PATH`""
Write-Host ""
Write-Host "Verify:"
Write-Host "  dotnet --version"
Write-Host "  dotnet new console -n HelloWorld"
Write-Host "  cd HelloWorld && dotnet run"