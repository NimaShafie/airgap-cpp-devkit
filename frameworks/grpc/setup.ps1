# Author: Nima Shafie
# =============================================================================
# setup.ps1
# gRPC air-gap source build — full pipeline including HelloWorld demo.
#
# Called via: setup.sh -> setup.bat -> setup.ps1
# Can also be run directly from Developer PowerShell:
#
#   cd frameworks\grpc
#   .\setup.ps1 -version 1.78.1 -dest "C:\Users\n1mz\AppData\Local\airgap-cpp-devkit\grpc-1.78.1"
#
# OPTIONS:
#   -version <ver>   gRPC version to build (1.76.0 or 1.78.1)
#   -dest    <path>  Install destination (if omitted, auto-detected)
#
# REQUIREMENTS:
#   - Visual Studio 2019 / 2022 / Insiders with Desktop C++ workload
#   - Git Bash (bash.exe) on PATH
#   - CMake installed to C:\Program Files\CMake\
#   - Run from: frameworks\grpc\ directory
# =============================================================================

param(
    [string]$version = "",
    [string]$dest    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

# -----------------------------
# Helpers
# -----------------------------
function Info  { param($m) Write-Host "[INFO] $m" }
function Warn  { param($m) Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Step  { param($m) Write-Host ""; Write-Host "*** $m ***" }
function Die   { param($m) Err $m; exit 1 }

function Require-Exit {
    param($code, $msg)
    if ($code -ne 0) { Die "$msg (exit $code)" }
}

# -----------------------------
# Step 1: Version selection
# -----------------------------
$GRPC_VERSION = $version

if (-not $GRPC_VERSION) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " gRPC Air-Gap Source Build"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "  Available versions:"
    Write-Host "    [1] gRPC v1.76.0  (production-tested)"
    Write-Host "    [2] gRPC v1.78.1  (candidate-testing)"
    Write-Host ""
    $choice = Read-Host "  Select version (1 or 2)"
    switch ($choice) {
        "1" { $GRPC_VERSION = "1.76.0" }
        "2" { $GRPC_VERSION = "1.78.1" }
        default { Die "Invalid selection. Enter 1 or 2." }
    }
}

switch ($GRPC_VERSION) {
    "1.76.0" { $GRPC_FOLDER = "grpc-1.76.0"; $EXTRACT_ROOT = "grpc_unbuilt_v1.76.0" }
    "1.78.1" { $GRPC_FOLDER = "grpc-1.78.1"; $EXTRACT_ROOT = "grpc-1.78.1" }
    default  { Die "Unknown version: $GRPC_VERSION. Supported: 1.76.0, 1.78.1" }
}

Info "Selected: gRPC v$GRPC_VERSION"

# -----------------------------
# Step 2: Determine install dest
# -----------------------------
if ($dest) {
    $DEST_GRPC = $dest
    Info "Install destination (from caller): $DEST_GRPC"
} else {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        $DEST_ROOT = "C:\Program Files\airgap-cpp-devkit"
        Info "Admin rights detected. Installing system-wide."
    } else {
        $DEST_ROOT = "$env:LOCALAPPDATA\airgap-cpp-devkit"
        Warn "No admin rights. Installing for current user only."
        Warn "Other users on this machine will NOT have access."
        Warn "Re-run as Administrator for system-wide install."
    }
    $DEST_GRPC = "$DEST_ROOT\$GRPC_FOLDER"
    Info "Install destination: $DEST_GRPC"
}

$OUTPUT_DIR    = "$DEST_GRPC\outputs"
$GRPC_EXAMPLES = "$DEST_GRPC\examples\cpp\helloworld"
$GRPC_PROTOS   = "$DEST_GRPC\examples\protos"
$TARGET_CMAKE  = "$DEST_GRPC\examples\cpp\cmake"
$DEMO_DIR      = "$env:USERPROFILE\Desktop\grpc_demo"
$DEMO_HELLO    = "$DEMO_DIR\helloworld"
$GEN_DIR       = "$DEMO_HELLO\generated"
$DEMO_PROTOS   = "$DEMO_DIR\protos"
$LINK_CMAKE    = "$DEMO_DIR\cmake"

# -----------------------------
# Step 3: Locate VsDevCmd.bat
# -----------------------------
Step "Locating Visual Studio"

$VS_CANDIDATES = @(
    # VS 2026 Insiders (v18)
    "C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\Tools\VsDevCmd.bat",
    # VS 2022 Insiders
    "C:\Program Files\Microsoft Visual Studio\2022\Insiders\Common7\Tools\VsDevCmd.bat",
    # VS 2022
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    # VS 2019
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
)

$VSDEVCMD = $null
foreach ($candidate in $VS_CANDIDATES) {
    if (Test-Path $candidate) {
        $VSDEVCMD = $candidate
        break
    }
}
if (-not $VSDEVCMD) {
    Die "VsDevCmd.bat not found. Install Visual Studio (2019/2022/Insiders) with Desktop C++ workload."
}
Info "Found VS: $VSDEVCMD"

# -----------------------------
# Locate cmake
# Prefer system install to avoid Git Bash cmake shadowing
# -----------------------------
$CMAKE_CANDIDATES = @(
    "C:\Program Files\CMake\bin\cmake.exe",
    "C:\Program Files (x86)\CMake\bin\cmake.exe"
)
$CmakeExe = $null
foreach ($c in $CMAKE_CANDIDATES) {
    if (Test-Path $c) { $CmakeExe = $c; break }
}
if (-not $CmakeExe) {
    $CmakeExe = "cmake"
    Warn "cmake not found at standard install path -- falling back to PATH cmake."
} else {
    Info "cmake: $CmakeExe"
}

# -----------------------------
# Step 4: Locate bash.exe
# -----------------------------
Step "Locating Git Bash"
$bashExe = Get-Command bash.exe -ErrorAction SilentlyContinue
if (-not $bashExe) { Die "bash.exe not found on PATH. Install Git for Windows." }
Info "bash.exe found: $($bashExe.Source)"

# -----------------------------
# Step 5: Verify vendor parts
# -----------------------------
Step "Verifying vendored source parts for v$GRPC_VERSION"
& bash.exe scripts/verify.sh $GRPC_VERSION
Require-Exit $LASTEXITCODE "Source verification failed"

# -----------------------------
# Step 6: Reassemble .tar.gz
# -----------------------------
Step "Reassembling source archive"
& bash.exe scripts/reassemble.sh $GRPC_VERSION
Require-Exit $LASTEXITCODE "Reassembly failed"

# -----------------------------
# Step 7: Extract source tree
# -----------------------------
Step "Extracting source tree"
$extractPath = Join-Path $ScriptDir "src\$EXTRACT_ROOT"
if (Test-Path $extractPath) {
    Info "src\$EXTRACT_ROOT already exists -- skipping extraction."
} else {
    & bash.exe -c "mkdir -p src && tar -xzf vendor/grpc-$GRPC_VERSION.tar.gz -C src/"
    Require-Exit $LASTEXITCODE "Extraction failed"
    Info "Source tree extracted to src\$EXTRACT_ROOT"
}

# -----------------------------
# Step 8: Copy source to dest
# -----------------------------
Step "Copying source to install location"
if (Test-Path $DEST_GRPC) {
    Info "gRPC folder already exists at $DEST_GRPC"
} else {
    if (-not (Test-Path $extractPath)) { Die "Source folder not found: $extractPath" }
    Info "Copying gRPC source to $DEST_GRPC ..."
    & xcopy /E /I /Y "$extractPath\*" "$DEST_GRPC\" | Out-Null
    Require-Exit $LASTEXITCODE "Failed to copy gRPC source"
    Info "gRPC v$GRPC_VERSION copied to $DEST_GRPC"
}

# -----------------------------
# Step 9: Create demo directories
# -----------------------------
Step "Creating demo directories"
foreach ($d in @($DEMO_DIR, $DEMO_HELLO, $DEMO_PROTOS)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Info "Created $d"
    }
}

# -----------------------------
# Step 10: Build gRPC
# -----------------------------
Step "Checking build status"
$pluginExe = "$OUTPUT_DIR\bin\grpc_cpp_plugin.exe"
$needsBuild = $true
if (Test-Path $pluginExe) {
    Info "Found grpc_cpp_plugin.exe."
    $ans = Read-Host "Binaries present. Rebuild gRPC? (y/n)"
    if ($ans -notmatch '^[Yy]') {
        Info "Skipping gRPC build."
        $needsBuild = $false
    }
} else {
    Warn "grpc_cpp_plugin.exe not found. Proceeding with build..."
}

if ($needsBuild) {
    Step "Building gRPC v$GRPC_VERSION"

    $cmakeBuildDir = "$DEST_GRPC\cmake\build"
    if (-not (Test-Path $cmakeBuildDir)) {
        New-Item -ItemType Directory -Path $cmakeBuildDir -Force | Out-Null
    }

    $buildScript = @"
@echo off
call "$VSDEVCMD" -arch=amd64
if errorlevel 1 exit /b 1
set CC=
set CXX=
cd /d "$cmakeBuildDir"
if errorlevel 1 exit /b 1
"$CmakeExe" -G Ninja -DCMAKE_BUILD_TYPE=Release -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_CXX_STANDARD=17 -DCMAKE_INSTALL_PREFIX="$DEST_GRPC" ..\..
if errorlevel 1 exit /b 1
"$CmakeExe" --build . --target install -j 4
if errorlevel 1 exit /b 1
"@

    $tmpBat = [System.IO.Path]::GetTempFileName() + ".bat"
    [System.IO.File]::WriteAllText($tmpBat, $buildScript, [System.Text.Encoding]::ASCII)

    Info "Activating VS environment (amd64) and running cmake build..."
    cmd.exe /c "`"$tmpBat`""
    $buildExit = $LASTEXITCODE
    Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
    Require-Exit $buildExit "gRPC build failed"
    Info "gRPC build complete."
}

# -----------------------------
# Step 11: Copy binaries to outputs
# -----------------------------
Step "Copying binaries to outputs folder"
$outBin = "$OUTPUT_DIR\bin"
$outLib = "$OUTPUT_DIR\lib"
if (-not (Test-Path $outBin)) { New-Item -ItemType Directory -Path $outBin -Force | Out-Null }
if (-not (Test-Path $outLib)) { New-Item -ItemType Directory -Path $outLib -Force | Out-Null }
& xcopy /E /I /Y "$DEST_GRPC\bin\*" "$outBin\" | Out-Null
& xcopy /E /I /Y "$DEST_GRPC\lib\*" "$outLib\" | Out-Null
Info "Binaries copied."

# -----------------------------
# Step 12: Copy HelloWorld demo files
# -----------------------------
Step "Copying HelloWorld demo files"
& xcopy /E /I /H /Y "$GRPC_EXAMPLES\*" "$DEMO_HELLO\" | Out-Null
Require-Exit $LASTEXITCODE "Failed to copy HelloWorld demo files"

if (-not (Test-Path "$LINK_CMAKE\common.cmake")) {
    & xcopy /E /I /H /Y "$TARGET_CMAKE\*" "$LINK_CMAKE\" | Out-Null
}
Info "Demo files copied."

# -----------------------------
# Step 13: Patch HelloWorld CMakeLists.txt
# -----------------------------
Step "Updating HelloWorld CMakeLists.txt"
$cmakeListsPath = "$DEMO_HELLO\CMakeLists.txt"
$content = Get-Content $cmakeListsPath -Raw
$content = $content -replace [regex]::Escape('../../protos/helloworld.proto'), '../protos/helloworld.proto'
Set-Content $cmakeListsPath $content
Info "CMakeLists.txt updated."

# -----------------------------
# Step 14: Generate protobuf sources
# -----------------------------
Step "Generating protobuf sources"
Copy-Item "$GRPC_PROTOS\helloworld.proto" "$DEMO_PROTOS\helloworld.proto" -Force
if (-not (Test-Path $GEN_DIR)) { New-Item -ItemType Directory -Path $GEN_DIR -Force | Out-Null }

$protocExe  = "$OUTPUT_DIR\bin\protoc.exe"
$grpcPlugin = "$OUTPUT_DIR\bin\grpc_cpp_plugin.exe"

& "$protocExe" -I "$DEMO_PROTOS" `
    --cpp_out="$GEN_DIR" `
    --grpc_out="$GEN_DIR" `
    "--plugin=protoc-gen-grpc=$grpcPlugin" `
    helloworld.proto
Require-Exit $LASTEXITCODE "Protoc generation failed"
Info "Protobuf sources generated."

# -----------------------------
# Step 15: Build HelloWorld demo
# -----------------------------
Step "Building HelloWorld demo"
if (Test-Path "$DEMO_HELLO\.build") {
    Remove-Item "$DEMO_HELLO\.build" -Recurse -Force
}
New-Item -ItemType Directory -Path "$DEMO_HELLO\.build" -Force | Out-Null

$demoScript = @"
@echo off
call "$VSDEVCMD" -arch=amd64
if errorlevel 1 exit /b 1
set CC=
set CXX=
cd /d "$DEMO_HELLO\.build"
if errorlevel 1 exit /b 1
"$CmakeExe" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$DEST_GRPC" ..
if errorlevel 1 exit /b 1
"$CmakeExe" --build . -j 4
if errorlevel 1 exit /b 1
"@

$tmpDemo = [System.IO.Path]::GetTempFileName() + ".bat"
[System.IO.File]::WriteAllText($tmpDemo, $demoScript, [System.Text.Encoding]::ASCII)

Info "Building HelloWorld demo..."
cmd.exe /c "`"$tmpDemo`""
$demoExit = $LASTEXITCODE
Remove-Item $tmpDemo -Force -ErrorAction SilentlyContinue
Require-Exit $demoExit "Demo build failed"
Info "Demo built successfully."

# -----------------------------
# Done
# -----------------------------
Write-Host ""
Write-Host "*********************"
Write-Host " gRPC v$GRPC_VERSION -- Build Complete"
Write-Host " Install location : $DEST_GRPC"
Write-Host " Build outputs    : $OUTPUT_DIR"
Write-Host " Demo             : $DEMO_HELLO\.build\"
Write-Host "*********************"
Write-Host ""

Info "Launching greeter_server.exe..."
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "cd '$DEMO_HELLO\.build'; .\greeter_server.exe"

Info "Launching greeter_client.exe..."
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "cd '$DEMO_HELLO\.build'; .\greeter_client.exe"

Write-Host ""
Write-Host "Please verify that both server and client are running as expected."