@echo off
setlocal
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set REPO_ROOT=%%i
if not defined REPO_ROOT (
  echo ERROR: This script must be run inside a Git repository.
  exit /b 1
)
copy /Y "%REPO_ROOT%	ools\coding-standard\.clang-format" "%REPO_ROOT%\.clang-format" >nul
if errorlevel 1 (
  echo ERROR: Failed to sync .clang-format to repo root.
  exit /b 1
)
echo OK: Synced root .clang-format from tools\coding-standard\.clang-format
