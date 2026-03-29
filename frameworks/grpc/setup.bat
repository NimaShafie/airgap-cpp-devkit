REM Author: Nima Shafie
@echo off
cd /d "%~dp0"
echo [BAT DEBUG] Working dir: %CD%
echo [BAT DEBUG] Args: %*
setlocal EnableDelayedExpansion
echo [BAT DEBUG] DelayedExpansion enabled

REM ====================================================
REM setup_grpc.bat
REM Single entry point for gRPC air-gap source build.
REM
REM Called by setup_grpc.sh (bash wrapper) which handles:
REM   - Admin/user install mode detection
REM   - Install path selection
REM   - Logging and install receipt
REM
REM Can also be run directly from cmd.exe:
REM   setup_grpc.bat --version 1.76.0 --dest "C:\Program Files\airgap-cpp-devkit\grpc-1.76.0"
REM
REM If --dest is not provided, falls back to interactive prompt
REM and installs to C:\Users\Public\FTE_Software (legacy behavior).
REM
REM REQUIREMENTS:
REM   - Git Bash (bash.exe) on PATH
REM   - Visual Studio 2022 Insiders with Desktop C++ workload
REM   - Run from: frameworks/grpc\ directory (or via setup_grpc.sh)
REM ====================================================

REM -----------------------------
REM Step 0: Parse arguments
REM -----------------------------
set "GRPC_VERSION="
set "DEST_OVERRIDE="

:parse_args
if "%~1"=="" goto done_args
if /I "%~1"=="--version" (
    set "GRPC_VERSION=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="--dest" (
    set "DEST_OVERRIDE=%~2"
    shift
    shift
    goto parse_args
)
shift
goto parse_args
:done_args

REM -----------------------------
REM Step 1: Version selection
REM (skipped if --version was passed)
REM -----------------------------
if not "!GRPC_VERSION!"=="" goto version_set

echo.
echo ============================================================
echo  gRPC Air-Gap Source Build
echo ============================================================
echo.
echo  Available versions:
echo    [1] gRPC v1.76.0  (production-tested)
echo    [2] gRPC v1.78.1  (candidate-testing)
echo.
set /p VERSION_CHOICE=" Select version (1 or 2): "

if "!VERSION_CHOICE!"=="1" (
    set "GRPC_VERSION=1.76.0"
) else if "!VERSION_CHOICE!"=="2" (
    set "GRPC_VERSION=1.78.1"
) else (
    echo [ERROR] Invalid selection. Enter 1 or 2.
REM pause removed
    exit /b 1
)

:version_set
if "!GRPC_VERSION!"=="1.76.0" (
    set "GRPC_FOLDER=grpc-1.76.0"
    set "EXTRACT_ROOT=grpc_unbuilt_v1.76.0"
) else if "!GRPC_VERSION!"=="1.78.1" (
    set "GRPC_FOLDER=grpc-1.78.1"
    set "EXTRACT_ROOT=grpc-1.78.1"
) else (
    echo [ERROR] Unknown version: !GRPC_VERSION!
    echo         Supported: 1.76.0, 1.78.1
REM pause removed
    exit /b 1
)

echo.
echo [INFO] Selected: gRPC v!GRPC_VERSION!
echo.

REM -----------------------------
REM Step 2: Determine install dest
REM -----------------------------
if not "!DEST_OVERRIDE!"=="" (
    set "DEST_GRPC=!DEST_OVERRIDE!"
    echo [INFO] Install destination (from caller): !DEST_GRPC!
) else (
    REM Legacy fallback: detect admin rights, set path accordingly
    net session >nul 2>&1
    if %errorlevel% equ 0 (
        set "DEST_ROOT=C:\Program Files\airgap-cpp-devkit"
        echo [INFO] Admin rights detected. Installing system-wide.
    ) else (
        set "DEST_ROOT=%LOCALAPPDATA%\airgap-cpp-devkit"
        echo [WARNING] No admin rights. Installing for current user only.
        echo           Other users on this machine will NOT have access.
        echo           Re-run as Administrator for system-wide install.
    )
    set "DEST_GRPC=!DEST_ROOT!\!GRPC_FOLDER!"
    echo [INFO] Install destination: !DEST_GRPC!
)

set "SOURCE_GRPC_FOLDER=src\!EXTRACT_ROOT!\"
set "OUTPUT_DIR=!DEST_GRPC!\outputs"
set "GRPC_EXAMPLES=!DEST_GRPC!\examples\cpp\helloworld"
set "GRPC_PROTOS=!DEST_GRPC!\examples\protos"
set "TARGET_CMAKE=!DEST_GRPC!\examples\cpp\cmake"
set "DEMO_DIR=%USERPROFILE%\Desktop\grpc_demo"
set "DEMO_HELLO=!DEMO_DIR!\helloworld"
set "GEN_DIR=!DEMO_HELLO!\generated"
set "DEMO_PROTOS=!DEMO_DIR!\protos"
set "LINK_CMAKE=!DEMO_DIR!\cmake"

REM -----------------------------
REM Step 3: Locate VS VsDevCmd.bat
REM (search standard paths + fallback)
REM -----------------------------
set "VSDEVCMD="
for %%P in (
    "C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat"
) do (
    if exist %%P (
        set "VSDEVCMD=%%~P"
        goto found_vsdevcmd
    )
)
echo [ERROR] VsDevCmd.bat not found in any standard VS install location.
echo         Install Visual Studio 2022 (any edition) with C++ workload.
REM pause removed for non-interactive use
exit /b 1
:found_vsdevcmd
echo [INFO] Found VS: !VSDEVCMD!

REM -----------------------------
REM Step 4: Locate bash.exe
REM -----------------------------
echo *** Locating Git Bash ***
where bash.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] bash.exe not found on PATH.
    echo         Install Git for Windows and ensure Git Bash is on PATH.
REM pause removed
    exit /b 1
)
echo [OK] bash.exe found.

REM -----------------------------
REM Step 5: Verify vendor parts
REM -----------------------------
echo.
echo *** Verifying vendored source parts for v!GRPC_VERSION! ***
bash scripts/verify.sh !GRPC_VERSION!
if errorlevel 1 (
    echo [ERROR] Source verification failed.
REM pause removed
    exit /b 1
)

REM -----------------------------
REM Step 6: Reassemble .tar.gz
REM -----------------------------
echo.
echo *** Reassembling source archive ***
bash scripts/reassemble.sh !GRPC_VERSION!
if errorlevel 1 (
    echo [ERROR] Reassembly failed.
REM pause removed
    exit /b 1
)

REM -----------------------------
REM Step 7: Extract source tree
REM -----------------------------
echo.
echo *** Extracting source tree ***
if exist "src\!EXTRACT_ROOT!\" (
    echo [INFO] src\!EXTRACT_ROOT!\ already exists -- skipping extraction.
) else (
    bash -c "mkdir -p src && tar -xzf vendor/grpc-!GRPC_VERSION!.tar.gz -C src/"
    if errorlevel 1 (
        echo [ERROR] Extraction failed.
REM pause removed
        exit /b 1
    )
    echo [OK] Source tree extracted to src\!EXTRACT_ROOT!\
)

REM -----------------------------
REM Step 8: Initialize VS environment
REM -----------------------------
echo.
echo *** Initializing Visual Studio Developer Environment ***
call "!VSDEVCMD!"
if errorlevel 1 (
    echo [ERROR] Failed to initialize VS developer environment.
REM pause removed
    exit /b 1
)
echo [OK] VS developer environment initialized.

REM -----------------------------
REM Step 9: Create demo directories
REM -----------------------------
for %%D in ("!DEMO_DIR!" "!DEMO_HELLO!" "!DEMO_PROTOS!") do (
    if not exist %%D (
        mkdir %%D
        if errorlevel 1 (
            echo [ERROR] Failed to create directory %%D.
REM pause removed
            exit /b 1
        )
    )
)

REM -----------------------------
REM Step 10: Copy source to dest
REM -----------------------------
if not exist "!DEST_GRPC!\" (
    echo [INFO] Copying gRPC source to install location...
    set "SOURCE_GRPC_FOLDER=%CD%\%SOURCE_GRPC_FOLDER%"
    if exist "!SOURCE_GRPC_FOLDER!\" (
        xcopy /E /I /Y "!SOURCE_GRPC_FOLDER!\*" "!DEST_GRPC!"
        if errorlevel 1 (
            echo [ERROR] Failed to copy gRPC folder.
REM pause removed
            exit /b 1
        )
        echo [OK] gRPC v!GRPC_VERSION! copied to !DEST_GRPC!.
    ) else (
        echo [ERROR] Source folder not found: !SOURCE_GRPC_FOLDER!
REM pause removed
        exit /b 1
    )
) else (
    echo [INFO] gRPC folder already exists at "!DEST_GRPC!".
)

REM -----------------------------
REM Step 11: Check/build binaries
REM -----------------------------
echo.
echo *** Verifying necessary binaries ***
set "NEEDS_BUILD=0"
if not exist "!OUTPUT_DIR!\bin\grpc_cpp_plugin.exe" (
    echo [WARNING] grpc_cpp_plugin.exe not found. Proceeding with build...
    set "NEEDS_BUILD=1"
) else (
    echo [INFO] Found grpc_cpp_plugin.exe.
)

if "!NEEDS_BUILD!"=="1" (
    goto BuildGRPC
) else (
    set /p choice="Binaries present. Rebuild gRPC? (y/n): "
    if /I "!choice!"=="y" (
        goto BuildGRPC
    ) else (
        echo [INFO] Skipping gRPC build...
        goto CopyFiles
    )
)

:BuildGRPC
echo.
echo *** Building gRPC v!GRPC_VERSION! ***
set "MY_INSTALL_DIR=!DEST_GRPC!"
set "Path=%Path%;!MY_INSTALL_DIR!\bin"
cd "!DEST_GRPC!"
if errorlevel 1 (
    echo [ERROR] Unable to cd to !DEST_GRPC!
REM pause removed
    exit /b 1
)
if not exist "cmake\build\" ( mkdir "cmake\build" )
cd "cmake\build"
if exist * ( del * /Q )
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_CXX_STANDARD=17 -DCMAKE_INSTALL_PREFIX="!MY_INSTALL_DIR!" ..\..
if errorlevel 1 (
    echo [ERROR] CMake configuration failed.
REM pause removed
    exit /b 1
)
cmake --build . --config Release --target install -j 4
if errorlevel 1 (
    echo [ERROR] gRPC build failed.
REM pause removed
    exit /b 1
)

:CopyFiles
echo.
echo *** Copying binaries to outputs folder ***
xcopy /E /I /Y "!MY_INSTALL_DIR!\bin\*" "!OUTPUT_DIR!\bin\"
xcopy /E /I /Y "!MY_INSTALL_DIR!\lib\*" "!OUTPUT_DIR!\lib\"
echo [OK] Binaries copied.

echo.
echo [INFO] Copying HelloWorld demo files...
xcopy /E /I /H /Y "!GRPC_EXAMPLES!\*" "!DEMO_HELLO!\"
if errorlevel 1 (
    echo [ERROR] Failed to copy HelloWorld demo files.
REM pause removed
    exit /b 1
)
if not exist "!LINK_CMAKE!\common.cmake" (
    xcopy /E /I /H /Y "!TARGET_CMAKE!\*" "!LINK_CMAKE!\"
)
echo [OK] Demo files copied.

echo.
echo *** Updating HelloWorld CMakeLists.txt ***
powershell -Command "(Get-Content '!DEMO_HELLO!\CMakeLists.txt') -replace '../../protos/helloworld\.proto', '../protos/helloworld\.proto' | Set-Content '!DEMO_HELLO!\CMakeLists.txt'"
echo [OK] CMakeLists.txt updated.

echo.
echo *** Generating protobuf sources ***
copy /Y "!GRPC_PROTOS!\helloworld.proto" "!DEMO_PROTOS!\helloworld.proto" >nul
cd "!DEMO_PROTOS!"
if not exist "!GEN_DIR!" ( mkdir "!GEN_DIR!" )
"!OUTPUT_DIR!\bin\protoc.exe" -I "!DEMO_PROTOS!" --cpp_out="!GEN_DIR!" --grpc_out="!GEN_DIR!" --plugin=protoc-gen-grpc="!OUTPUT_DIR!\bin\grpc_cpp_plugin.exe" helloworld.proto
if errorlevel 1 (
    echo [ERROR] Protoc generation failed.
REM pause removed
    exit /b 1
)
echo [OK] Protobuf sources generated.

echo.
echo *** Building HelloWorld demo ***
cd "!DEMO_HELLO!"
if exist ".build" ( rmdir /S /Q ".build" )
mkdir ".build"
cd ".build"
cmake -G "Visual Studio 18 2026" -A x64 -DCMAKE_PREFIX_PATH="!DEST_GRPC!" ..
if errorlevel 1 (
    echo [ERROR] CMake configuration for demo failed.
REM pause removed
    exit /b 1
)
cmake --build . --config Release -j 4
if errorlevel 1 (
    echo [ERROR] Demo build failed.
REM pause removed
    exit /b 1
)
echo [OK] Demo built successfully.

echo.
echo *********************
echo  gRPC v!GRPC_VERSION! — Build Complete
echo  Install location : !DEST_GRPC!
echo  Build outputs    : !OUTPUT_DIR!
echo  Demo             : !DEMO_HELLO!\.build\Release
echo *********************
echo.
echo Launching greeter_server.exe...
start powershell.exe -NoExit -Command "cd '!DEMO_HELLO!\.build\Release'; .\greeter_server.exe"
echo Launching greeter_client.exe...
start powershell.exe -NoExit -Command "cd '!DEMO_HELLO!\.build\Release'; .\greeter_client.exe"
echo.
echo Please verify that both server and client are running as expected.
REM pause removed