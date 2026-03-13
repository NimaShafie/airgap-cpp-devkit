@echo off
setlocal ENABLEDELAYEDEXPANSION
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set REPO_ROOT=%%i
if not defined REPO_ROOT (
  echo ERROR: This script must be run inside a Git repository.
  exit /b 1
)
cd /d "%REPO_ROOT%"
set SCRIPT_DIR=%REPO_ROOT%	ools\coding-standard\scripts
call "%SCRIPT_DIR%\sync-root-clang-format.cmd"
if errorlevel 1 exit /b 1
call "%SCRIPT_DIR%\install-user-tools.cmd"
if errorlevel 1 exit /b 1
call "%SCRIPT_DIR%\install-hooks.cmd"
if errorlevel 1 exit /b 1
echo.
echo C++ coding standard setup finished successfully.
exit /b 0
