@echo off
setlocal ENABLEDELAYEDEXPANSION
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set REPO_ROOT=%%i
if not defined REPO_ROOT (
  echo ERROR: This script must be run inside a Git repository.
  exit /b 1
)
cd /d "%REPO_ROOT%"

set USER_BIN=%LOCALAPPDATA%\cpp-coding-standard\llvmin
set VENDOR_BIN=%REPO_ROOT%	ools\coding-standardendor\windows\llvmin

call :ensure_tool clang-format.exe clang-format
if errorlevel 1 exit /b 1
call :ensure_tool clang-tidy.exe clang-tidy
exit /b 0

goto :eof

:ensure_tool
set TOOL_EXE=%~1
set TOOL_CMD=%~2
where %TOOL_CMD% >nul 2>nul
if %ERRORLEVEL%==0 (
  echo OK: %TOOL_CMD% already available on current user PATH.
  exit /b 0
)

echo %TOOL_CMD% not found on PATH.
if not exist "%VENDOR_BIN%\%TOOL_EXE%" (
  if /I "%TOOL_CMD%"=="clang-format" (
    echo ERROR: %TOOL_CMD% is required but no bundled portable binary was found.
    echo Expected: %VENDOR_BIN%\%TOOL_EXE%
    exit /b 1
  ) else (
    echo WARNING: %TOOL_CMD% is optional and no bundled portable binary was found.
    exit /b 0
  )
)

echo Installing %TOOL_CMD% to current user location:
echo   %USER_BIN%
if not exist "%USER_BIN%" mkdir "%USER_BIN%"
copy /Y "%VENDOR_BIN%\%TOOL_EXE%" "%USER_BIN%\%TOOL_EXE%" >nul
if errorlevel 1 (
  if /I "%TOOL_CMD%"=="clang-format" (
    echo ERROR: Failed to install %TOOL_CMD% to user directory.
    exit /b 1
  ) else (
    echo WARNING: Failed to install optional %TOOL_CMD%.
    exit /b 0
  )
)

call :ensure_user_path "%USER_BIN%"
where %TOOL_CMD% >nul 2>nul
if %ERRORLEVEL%==0 (
  echo OK: %TOOL_CMD% is now available.
  exit /b 0
)
if exist "%USER_BIN%\%TOOL_EXE%" (
  echo OK: %TOOL_CMD% installed to user directory.
  echo Open a new shell if PATH has not refreshed yet.
  exit /b 0
)
if /I "%TOOL_CMD%"=="clang-format" (
  echo ERROR: %TOOL_CMD% install did not succeed.
  exit /b 1
)
echo WARNING: Optional %TOOL_CMD% install did not fully succeed.
exit /b 0

:ensure_user_path
set TARGET_DIR=%~1
for /f "delims=" %%i in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::GetEnvironmentVariable('Path','User')"') do set USERPATH=%%i
if not defined USERPATH set USERPATH=
echo !USERPATH! | find /I "%TARGET_DIR%" >nul
if %ERRORLEVEL%==0 (
  echo OK: User PATH already contains %TARGET_DIR%
  exit /b 0
)
set NEWPATH=%TARGET_DIR%
if defined USERPATH set NEWPATH=%TARGET_DIR%;!USERPATH!
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Environment]::SetEnvironmentVariable('Path', '%NEWPATH%', 'User')"
if errorlevel 1 (
  echo WARNING: Could not persist user PATH. The tool is still installed in:
  echo   %TARGET_DIR%
  echo Add that directory to the current user's PATH manually.
  exit /b 0
)
set PATH=%TARGET_DIR%;%PATH%
echo OK: Added %TARGET_DIR% to current user PATH.
exit /b 0
