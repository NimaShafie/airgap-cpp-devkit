@echo off
setlocal EnableDelayedExpansion

REM ====================================================
REM setup_grpc.bat
REM Single entry point for gRPC air-gap source build.
REM Supports multiple vendored versions with version selector.
REM
REM WHAT THIS DOES:
REM   1. Prompts user to select gRPC version
REM   2. Verifies vendored source parts via SHA256 (bash)
REM   3. Reassembles .tar.gz from parts (bash)
REM   4. Extracts source tree to src\ (bash)
REM   5. Initializes VS 2022 Insiders developer environment
REM   6. Copies source to C:\Users\Public\FTE_Software\grpc-<version>
REM   7. Builds gRPC with CMake
REM   8. Builds and launches the HelloWorld demo
REM
REM REQUIREMENTS:
REM   - Git Bash (bash.exe) on PATH
REM   - Visual Studio 2022 Insiders with Desktop C++ workload
REM   - Run from: grpc-source-build\ directory
REM ====================================================

REM -----------------------------
REM Step 0: Version selector
REM -----------------------------
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
    set "GRPC_FOLDER=grpc-1.76.0"
    set "EXTRACT_ROOT=grpc_unbuilt_v1.76.0"
) else if "!VERSION_CHOICE!"=="2" (
    set "GRPC_VERSION=1.78.1"
    set "GRPC_FOLDER=grpc-1.78.1"
    set "EXTRACT_ROOT=grpc-1.78.1"
) else (
    echo [ERROR] Invalid selection. Enter 1 or 2.
    pause
    exit /b 1
)

echo.
echo [INFO] Selected: gRPC v!GRPC_VERSION!
echo.

REM -----------------------------
REM Step 1: Define paths
REM -----------------------------
set "SOURCE_GRPC_FOLDER=src\!EXTRACT_ROOT!\"
set "DEST_ROOT=C:\Users\Public\FTE_Software"
set "DEST_GRPC=%DEST_ROOT%\!GRPC_FOLDER!"
set "OUTPUT_DIR=%DEST_GRPC%\outputs"
set "GRPC_EXAMPLES=%DEST_GRPC%\examples\cpp\helloworld"
set "GRPC_PROTOS=%DEST_GRPC%\examples\protos"
set "TARGET_CMAKE=%DEST_GRPC%\examples\cpp\cmake"
set "DEMO_DIR=%USERPROFILE%\Desktop\grpc_demo"
set "DEMO_HELLO=%DEMO_DIR%\helloworld"
set "GEN_DIR=%DEMO_HELLO%\generated"
set "DEMO_PROTOS=%DEMO_DIR%\protos"
set "LINK_CMAKE=%DEMO_DIR%\cmake"
set "VSDEVCMD=C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\Tools\VsDevCmd.bat"

REM -----------------------------
REM Step 2: Locate bash.exe
REM -----------------------------
echo *** Locating Git Bash ***
where bash.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] bash.exe not found on PATH.
    echo         Install Git for Windows and ensure Git Bash is on PATH.
    pause
    exit /b 1
)
echo [OK] bash.exe found.

REM -----------------------------
REM Step 3: Verify vendor parts via SHA256
REM -----------------------------
echo.
echo *** Verifying vendored source parts for v!GRPC_VERSION! ***
bash scripts/verify.sh !GRPC_VERSION!
if errorlevel 1 (
    echo [ERROR] Source verification failed.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 4: Reassemble .tar.gz from parts
REM -----------------------------
echo.
echo *** Reassembling source archive ***
bash scripts/reassemble.sh !GRPC_VERSION!
if errorlevel 1 (
    echo [ERROR] Reassembly failed.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 5: Extract source tree to src\
REM -----------------------------
echo.
echo *** Extracting source tree ***
if exist "src\!EXTRACT_ROOT!\" (
    echo [INFO] src\!EXTRACT_ROOT!\ already exists -- skipping extraction.
) else (
    bash -c "mkdir -p src && tar -xzf vendor/grpc-!GRPC_VERSION!.tar.gz -C src/"
    if errorlevel 1 (
        echo [ERROR] Extraction failed.
        pause
        exit /b 1
    )
    echo [OK] Source tree extracted to src\!EXTRACT_ROOT!\
)

REM -----------------------------
REM Step 6: Initialize VS Developer environment
REM -----------------------------
echo.
echo *** Initializing Visual Studio Developer Environment ***
if not exist "%VSDEVCMD%" (
    echo [ERROR] VsDevCmd.bat not found at:
    echo         %VSDEVCMD%
    echo         Adjust the VSDEVCMD path in this script if VS is installed elsewhere.
    pause
    exit /b 1
)
call "%VSDEVCMD%"
if errorlevel 1 (
    echo [ERROR] Failed to initialize VS developer environment.
    pause
    exit /b 1
)
echo [OK] VS developer environment initialized.

REM -----------------------------
REM Step 7: Create required demo directories
REM -----------------------------
for %%D in ("%DEMO_DIR%" "%DEMO_HELLO%" "%DEMO_PROTOS%") do (
    if not exist %%D (
        mkdir %%D
        if errorlevel 1 (
            echo [ERROR] Failed to create directory %%D.
            pause
            exit /b 1
        )
    )
)

REM -----------------------------
REM Step 8: Copy source to destination
REM -----------------------------
if not exist "%DEST_GRPC%\" (
    echo [INFO] Copying gRPC folder...

    set "SOURCE_GRPC_FOLDER=%CD%\%SOURCE_GRPC_FOLDER%"

    echo [DEBUG] Source: "!SOURCE_GRPC_FOLDER!"
    echo [DEBUG] Destination: "%DEST_GRPC%"

    if exist "!SOURCE_GRPC_FOLDER!\" (
        xcopy /E /I /Y "!SOURCE_GRPC_FOLDER!\*" "%DEST_GRPC%"
        if errorlevel 1 (
            echo [ERROR] Failed to copy gRPC folder.
            pause
            exit /b 1
        )
        echo [OK] gRPC v!GRPC_VERSION! copied to %DEST_GRPC%.
    ) else (
        echo [ERROR] Source folder not found: "!SOURCE_GRPC_FOLDER!"
        echo         Extraction may have failed -- check src\ directory.
        pause
        exit /b 1
    )
) else (
    echo [INFO] gRPC folder already exists at "%DEST_GRPC%".
)

if not exist "%DEST_GRPC%\" (
    echo [ERROR] Folder "%DEST_GRPC%" not found.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 9: Check if binaries need building
REM -----------------------------
echo.
echo *** Verifying necessary binaries ***
set "NEEDS_BUILD=0"
if not exist "%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" (
    echo [WARNING] grpc_cpp_plugin.exe not found in "%OUTPUT_DIR%\bin".
    set "NEEDS_BUILD=1"
) else (
    echo [INFO] Found grpc_cpp_plugin.exe in "%OUTPUT_DIR%\bin".
)

if "!NEEDS_BUILD!"=="1" (
    echo [INFO] Required binaries missing. Proceeding with build...
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
REM -----------------------------
REM Step 10: Build gRPC
REM -----------------------------
echo.
echo *** Building gRPC v!GRPC_VERSION! ***
set "MY_INSTALL_DIR=%DEST_GRPC%"
set "Path=%Path%;%MY_INSTALL_DIR%\bin"
cd "%DEST_GRPC%"
if errorlevel 1 (
    echo [ERROR] Unable to cd to gRPC installation.
    pause
    exit /b 1
)

if not exist "cmake\build\" ( mkdir "cmake\build" )
cd "cmake\build"
if exist * ( del * /Q )

cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_CXX_STANDARD=17 -DCMAKE_INSTALL_PREFIX="%MY_INSTALL_DIR%" ..\..
if errorlevel 1 (
    echo [ERROR] CMake configuration failed.
    pause
    exit /b 1
)

cmake --build . --config Release --target install -j 4
if errorlevel 1 (
    echo [ERROR] gRPC build failed.
    pause
    exit /b 1
)

:CopyFiles
REM -----------------------------
REM Step 11: Copy demo files
REM -----------------------------
echo.
echo *** Copying binaries to outputs folder ***
xcopy /E /I /Y "%MY_INSTALL_DIR%\bin\*" "%OUTPUT_DIR%\bin\"
xcopy /E /I /Y "%MY_INSTALL_DIR%\lib\*" "%OUTPUT_DIR%\lib\"
echo [OK] Binaries copied.

echo.
echo [INFO] Copying HelloWorld demo files...
xcopy /E /I /H /Y "%GRPC_EXAMPLES%\*" "%DEMO_HELLO%\"
if errorlevel 1 (
    echo [ERROR] Failed to copy HelloWorld demo files.
    pause
    exit /b 1
)

if not exist "%LINK_CMAKE%\common.cmake" (
    xcopy /E /I /H /Y "%TARGET_CMAKE%\*" "%LINK_CMAKE%\"
    if errorlevel 1 (
        echo [ERROR] Failed to copy cmake folder.
        pause
        exit /b 1
    )
)
echo [OK] Demo files copied.

REM -----------------------------
REM Step 12: Update CMakeLists.txt
REM -----------------------------
echo.
echo *** Updating HelloWorld CMakeLists.txt ***
powershell -Command "(Get-Content '%DEMO_HELLO%\CMakeLists.txt') -replace '../../protos/helloworld\.proto', '../protos/helloworld\.proto' | Set-Content '%DEMO_HELLO%\CMakeLists.txt'"
if errorlevel 1 (
    echo [ERROR] Failed to update CMakeLists.txt.
    pause
    exit /b 1
)
echo [OK] CMakeLists.txt updated.

REM -----------------------------
REM Step 13: Generate Protobuf Sources
REM -----------------------------
echo.
echo *** Generating protobuf sources ***
if not exist "%GRPC_PROTOS%\helloworld.proto" (
    echo [ERROR] helloworld.proto not found in "%GRPC_PROTOS%".
    pause
    exit /b 1
)
copy /Y "%GRPC_PROTOS%\helloworld.proto" "%DEMO_PROTOS%\helloworld.proto" >nul
cd "%DEMO_PROTOS%"
if not exist "%GEN_DIR%" ( mkdir "%GEN_DIR%" )
"%OUTPUT_DIR%\bin\protoc.exe" -I "%DEMO_PROTOS%" --cpp_out="%GEN_DIR%" --grpc_out="%GEN_DIR%" --plugin=protoc-gen-grpc="%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" helloworld.proto
if errorlevel 1 (
    echo [ERROR] Protoc generation failed.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.pb.h" (
    echo [ERROR] helloworld.pb.h not found.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.grpc.pb.h" (
    echo [ERROR] helloworld.grpc.pb.h not found.
    pause
    exit /b 1
)
echo [OK] Protobuf sources generated.

REM -----------------------------
REM Step 14: Build HelloWorld Demo
REM -----------------------------
echo.
echo *** Building HelloWorld demo ***
cd "%DEMO_HELLO%"
if exist ".build" ( rmdir /S /Q ".build" )
mkdir ".build"
cd ".build"
cmake -G "Visual Studio 18 2026" -A x64 -DCMAKE_PREFIX_PATH="%DEST_GRPC%" ..
if errorlevel 1 (
    echo [ERROR] CMake configuration for demo failed.
    pause
    exit /b 1
)
cmake --build . --config Release -j 4
if errorlevel 1 (
    echo [ERROR] Demo build failed.
    pause
    exit /b 1
)
echo [OK] Demo built successfully.

REM -----------------------------
REM Step 15: Launch Demo
REM -----------------------------
echo.
echo *********************
echo All tasks completed successfully!
echo gRPC v!GRPC_VERSION! installed at: %DEST_GRPC%
echo Build outputs: %OUTPUT_DIR%
echo Demo built in: %DEMO_HELLO%\.build\Release
echo.
echo Launching greeter_server.exe...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_server.exe"
echo Launching greeter_client.exe...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_client.exe"
echo.
echo Please verify that both server and client are running as expected.
echo *********************
pause
ENDOFFILE
echo "done"