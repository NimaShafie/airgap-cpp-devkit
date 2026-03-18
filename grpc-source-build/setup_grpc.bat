@echo off
setlocal EnableDelayedExpansion
REM ====================================================
REM Setup Script for gRPC Installation and C++ HelloWorld Demo Build
REM ====================================================
REM Assumptions:
REM   - The gRPC distribution folder is available at:
REM         C:\Users\Public\FTE_Software\grpc-1.76.0
REM   - The folder grpc_unbuilt_v1.76.0 exists in the current directory.
REM   - gRPC build outputs (binaries and libraries) are under:
REM         %DEST_GRPC%\outputs
REM   - The original HelloWorld example is at:
REM         %DEST_GRPC%\examples\cpp\helloworld
REM   - Sample proto files are at:
REM         %DEST_GRPC%\examples\protos
REM   - The demo project will be created on your Desktop under:
REM         %USERPROFILE%\Desktop\grpc_demo
REM     with the following structure:
REM         grpc_demo\
REM             cmake\        (copied from %DEST_GRPC%\examples\cpp\cmake)
REM             protos\       (copied from %DEST_GRPC%\examples\protos)
REM             helloworld\   (copied from %DEST_GRPC%\examples\cpp\helloworld)
REM                 generated\  (for generated protobuf sources)
REM   - The original HelloWorld CMakeLists.txt uses:
REM         include(../cmake/common.cmake)
REM         get_filename_component(hw_proto "../../protos/helloworld.proto" ABSOLUTE)
REM     This script updates the proto file reference so it becomes:
REM         get_filename_component(hw_proto "../protos/helloworld.proto" ABSOLUTE)
REM     (The include line remains unchanged.)
REM ====================================================

REM -----------------------------
REM Step 0: Define paths
REM -----------------------------
set "GRPC_FOLDER=grpc-1.76.0"
set "SOURCE_GRPC_FOLDER=grpc_unbuilt_v1.76.0\"
set "DEST_ROOT=C:\Users\Public\FTE_Software"
set "DEST_GRPC=%DEST_ROOT%\%GRPC_FOLDER%"
set "OUTPUT_DIR=%DEST_GRPC%\outputs"
REM Original HelloWorld source folder
set "GRPC_EXAMPLES=%DEST_GRPC%\examples\cpp\helloworld"
REM Protos source folder from the gRPC distribution
set "GRPC_PROTOS=%DEST_GRPC%\examples\protos"
REM Working cmake folder (from examples\cpp\cmake)
set "TARGET_CMAKE=%DEST_GRPC%\examples\cpp\cmake"
REM Demo folder on Desktop
set "DEMO_DIR=%USERPROFILE%\Desktop\grpc_demo"
REM Destination for HelloWorld demo project files
set "DEMO_HELLO=%DEMO_DIR%\helloworld"
REM Folder for generated protobuf sources (inside HelloWorld demo)
set "GEN_DIR=%DEMO_HELLO%\generated"
REM Folder for demo protos (we copy helloworld.proto here)
set "DEMO_PROTOS=%DEMO_DIR%\protos"
REM We want to copy the working cmake folder into the demo root so that from the HelloWorld build
REM the relative include "../cmake/common.cmake" is valid.
set "LINK_CMAKE=%DEMO_DIR%\cmake"

REM -----------------------------
REM Step 1: Create required demo directories
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
REM Step 2: Ensure the gRPC folder exists by copying it.
REM -----------------------------
if not exist "%DEST_GRPC%\" (
    echo [INFO] Copying gRPC folder from the current location...
    
    set "SOURCE_GRPC_FOLDER=%CD%\%SOURCE_GRPC_FOLDER%"

    REM Debugging: Print paths
    echo [DEBUG] Source folder path: "%SOURCE_GRPC_FOLDER%"
    echo [DEBUG] Destination folder path: "%DEST_GRPC%"
    
    if exist "%SOURCE_GRPC_FOLDER%\" (
        echo [DEBUG] Source folder exists, proceeding to copy...
        xcopy /E /I /Y "%SOURCE_GRPC_FOLDER%\*" "%DEST_GRPC%"
        if errorlevel 1 (
            echo [ERROR] Failed to copy gRPC folder.
            pause
            exit /b 1
        )
        echo [OK] gRPC folder copied successfully.
    ) else (
        echo [ERROR] Source gRPC folder "%SOURCE_GRPC_FOLDER%" not found.
        pause
        exit /b 1
    )
) else (
    echo [INFO] gRPC folder already exists at "%DEST_GRPC%".
)

REM -----------------------------
REM Step 3: Verify that the gRPC folder exists.
REM -----------------------------
if not exist "%DEST_GRPC%\" (
    echo [ERROR] Folder "%DEST_GRPC%" not found.
    pause
    exit /b 1
)

REM -----------------------------
REM Step 4: Verify required binaries are present.
REM         Check for grpc_cpp_plugin.exe in %OUTPUT_DIR%\bin.
REM -----------------------------
echo.
echo *** Verifying necessary binaries in outputs folder ***
set "NEEDS_BUILD=0"
if not exist "%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" (
    echo [WARNING] grpc_cpp_plugin.exe not found in "%OUTPUT_DIR%\bin".
    set "NEEDS_BUILD=1"
) else (
    echo [INFO] Found grpc_cpp_plugin.exe in "%OUTPUT_DIR%\bin".
)

REM Automatically proceed with building if required binaries are missing
if "!NEEDS_BUILD!"=="1" (
    echo [INFO] Required binaries are missing. Proceeding with gRPC build...
    goto BuildGRPC
) else (
    set /p choice="Binaries are present. Do you want to rebuild gRPC? (y/n): "
    if /I "!choice!"=="y" (
        goto BuildGRPC
    ) else (
        echo [INFO] Skipping gRPC build step...
        goto CopyFiles
    )
)

:BuildGRPC
REM -----------------------------
REM Step 5: Build gRPC (if needed)
REM -----------------------------
echo.
echo *** Setting up gRPC build environment ***
set "MY_INSTALL_DIR=%DEST_GRPC%"
set "Path=%Path%;%MY_INSTALL_DIR%\bin"
echo Setting MY_INSTALL_DIR to: %MY_INSTALL_DIR%
echo Updating PATH.
cd "%DEST_GRPC%"
if errorlevel 1 (
    echo [ERROR] Unable to change directory to gRPC installation.
    pause
    exit /b 1
)

if not exist "cmake\build\" (
    mkdir "cmake\build"
)
cd "cmake\build"
echo [INFO] Clearing previous gRPC build files...
if exist * (
    del * /Q
)

echo [INFO] Configuring CMake for gRPC build...
cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF -DCMAKE_CXX_STANDARD=17 -DCMAKE_INSTALL_PREFIX="%MY_INSTALL_DIR%" ..\..
if errorlevel 1 (
    echo [ERROR] CMake configuration for gRPC failed.
    pause
    exit /b 1
)

echo [INFO] Building gRPC...
cmake --build . --config Release --target install -j 4
if errorlevel 1 (
    echo [ERROR] gRPC build and installation failed.
    pause
    exit /b 1
)

:CopyFiles
REM -----------------------------
REM Step 6: Copy demo files and working cmake folder.
REM         Copy HelloWorld demo files from %GRPC_EXAMPLES% to %DEMO_HELLO%.
REM         Copy the working "cmake" folder from %TARGET_CMAKE% into the demo root (%LINK_CMAKE%).
REM -----------------------------
echo.
echo *** Copying built binaries to outputs folder ***
xcopy /E /I /Y "%MY_INSTALL_DIR%\bin\*" "%OUTPUT_DIR%\bin\"
xcopy /E /I /Y "%MY_INSTALL_DIR%\lib\*" "%OUTPUT_DIR%\lib\"
echo [OK] Binaries and libraries copied.
echo.
echo [INFO] Copying HelloWorld demo files to demo folder...
xcopy /E /I /H /Y "%GRPC_EXAMPLES%\*" "%DEMO_HELLO%\"
if errorlevel 1 (
    echo [ERROR] Failed to copy HelloWorld demo files.
    pause
    exit /b 1
)

if not exist "%LINK_CMAKE%\common.cmake" (
    echo [INFO] Copying cmake folder into demo root...
    xcopy /E /I /H /Y "%TARGET_CMAKE%\*" "%LINK_CMAKE%\"
    if errorlevel 1 (
        echo [ERROR] Failed to copy cmake folder.
        pause
        exit /b 1
    )
) else (
    echo [INFO] Folder "%LINK_CMAKE%" already exists.
)
echo [OK] Demo files copied and cmake folder is available at "%LINK_CMAKE%".

REM -----------------------------
REM Step 7: Update HelloWorld CMakeLists.txt for correct proto reference.
REM         Replace "../../protos/helloworld.proto" with "../protos/helloworld.proto"
REM -----------------------------
echo.
echo *** Updating HelloWorld CMakeLists.txt for correct proto reference...
powershell -Command "(Get-Content '%DEMO_HELLO%\CMakeLists.txt') -replace '../../protos/helloworld\.proto', '../protos/helloworld\.proto' | Set-Content '%DEMO_HELLO%\CMakeLists.txt'"
if errorlevel 1 (
    echo [ERROR] Failed to update CMakeLists.txt.
    pause
    exit /b 1
)
echo [OK] CMakeLists.txt updated.

REM -----------------------------
REM Step 8: Generate Protobuf Sources
REM         Copy helloworld.proto from %GRPC_PROTOS% into the demo protos folder.
REM         Then run protoc (using absolute path) with -I set to %DEMO_PROTOS%
REM         to generate sources into "generated" folder (inside %DEMO_HELLO%).
REM -----------------------------
echo.
echo *** Generating protobuf sources for HelloWorld demo ***
if not exist "%GRPC_PROTOS%\helloworld.proto" (
    echo [ERROR] helloworld.proto not found in "%GRPC_PROTOS%".
    pause
    exit /b 1
)
copy /Y "%GRPC_PROTOS%\helloworld.proto" "%DEMO_PROTOS%\helloworld.proto" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy helloworld.proto to demo protos folder.
    pause
    exit /b 1
)
echo [INFO] helloworld.proto copied to demo protos at "%DEMO_PROTOS%".
cd "%DEMO_PROTOS%"
if not exist "%GEN_DIR%" (
    mkdir "%GEN_DIR%"
)
echo Running protoc to generate C++ sources into "generated" folder...
"%OUTPUT_DIR%\bin\protoc.exe" -I "%DEMO_PROTOS%" --cpp_out="%GEN_DIR%" --grpc_out="%GEN_DIR%" --plugin=protoc-gen-grpc="%OUTPUT_DIR%\bin\grpc_cpp_plugin.exe" helloworld.proto
if errorlevel 1 (
    echo [ERROR] Protoc generation failed.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.pb.h" (
    echo [ERROR] helloworld.pb.h not found in "generated". Protobuf generation may have failed.
    pause
    exit /b 1
)
if not exist "%GEN_DIR%\helloworld.grpc.pb.h" (
    echo [ERROR] helloworld.grpc.pb.h not found in "generated". Protobuf generation may have failed.
    pause
    exit /b 1
)
echo [OK] Protobuf sources successfully generated in "generated".

REM -----------------------------
REM Step 9: Build the HelloWorld Demo Example Using CMake
REM         Remove any existing ".build" folder in %DEMO_HELLO%, then configure and build.
REM         Use Visual Studio 2022 (x64) with -DCMAKE_PREFIX_PATH set to %DEST_GRPC%.
REM -----------------------------
echo.
echo *** Building the HelloWorld demo example ***
cd "%DEMO_HELLO%"
if exist ".build" (
    rmdir /S /Q ".build"
)
mkdir ".build"
cd ".build"
echo [INFO] Configuring CMake for demo build...
cmake -G "Visual Studio 18 2026" -A x64 -DCMAKE_PREFIX_PATH="%DEST_GRPC%" ..
if errorlevel 1 (
    echo [ERROR] CMake configuration for demo failed.
    pause
    exit /b 1
)
echo [INFO] Building demo using CMake...
cmake --build . --config Release -j 4
if errorlevel 1 (
    echo [ERROR] Building demo failed.
    pause
    exit /b 1
)
echo [OK] Demo built successfully.

REM -----------------------------
REM Step 10: Run the HelloWorld Demo
REM         Launch greeter_server.exe and greeter_client.exe from the Release folder.
REM         Open each in a new PowerShell window.
REM -----------------------------
echo.
echo *********************
echo All tasks completed successfully!
echo gRPC is installed at: %DEST_GRPC%
echo Build outputs are in: %OUTPUT_DIR%
echo The HelloWorld demo has been built in: %DEMO_HELLO%\.build\Release
echo.
echo Launching greeter_server.exe in a new window...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_server.exe"
echo Launching greeter_client.exe in a new window...
start powershell.exe -NoExit -Command "cd '%DEMO_HELLO%\.build\Release'; .\greeter_client.exe"
echo.
echo Please verify that both the server and client are running as expected.
echo *********************
pause