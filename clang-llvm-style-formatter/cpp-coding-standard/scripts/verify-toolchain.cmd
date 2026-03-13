@echo off
setlocal
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set REPO_ROOT=%%i
if not defined REPO_ROOT (
  echo ERROR: This script must be run inside a Git repository.
  exit /b 1
)
cd /d "%REPO_ROOT%"
echo core.hooksPath:
git config --local --get core.hooksPath
echo.
if exist "%REPO_ROOT%\.clang-format" (echo OK: found .clang-format) else (echo ERROR: missing .clang-format)
if exist "%REPO_ROOT%	ools\coding-standard\.clang-tidy" (echo OK: found .clang-tidy) else (echo ERROR: missing .clang-tidy)
where clang-format >nul 2>nul && clang-format --version || echo ERROR: clang-format missing
where clang-tidy >nul 2>nul && clang-tidy --version || echo WARNING: clang-tidy missing
where py >nul 2>nul && py -3 --version || where python >nul 2>nul && python --version || echo ERROR: Python missing
