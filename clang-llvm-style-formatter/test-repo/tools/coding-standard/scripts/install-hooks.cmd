@echo off
setlocal ENABLEDELAYEDEXPANSION
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set REPO_ROOT=%%i
if not defined REPO_ROOT (
  echo ERROR: This script must be run inside a Git repository.
  exit /b 1
)
cd /d "%REPO_ROOT%"

echo ==================================================
echo C++ Coding Standard Setup
echo Repo: %REPO_ROOT%
echo ==================================================
echo.

echo [1/6] Configuring repo-local Git hooks path...
git config --local core.hooksPath tools/coding-standard/hooks
if errorlevel 1 (
  echo ERROR: Failed to configure core.hooksPath
  exit /b 1
)
for /f "delims=" %%i in ('git config --local --get core.hooksPath') do set HOOKSPATH=%%i
echo OK: core.hooksPath = !HOOKSPATH!
echo.

echo [2/6] Checking required files...
if not exist "%REPO_ROOT%\.clang-format" (
  echo ERROR: Missing repo root .clang-format
  exit /b 1
)
echo OK: Found .clang-format
if not exist "%REPO_ROOT%	ools\coding-standard\.clang-tidy" (
  echo ERROR: Missing tools\coding-standard\.clang-tidy
  exit /b 1
)
echo OK: Found tools\coding-standard\.clang-tidy
if not exist "%REPO_ROOT%	ools\coding-standard\hooks\pre-commit" (
  echo ERROR: Missing tools\coding-standard\hooks\pre-commit
  exit /b 1
)
echo OK: Found hooks\pre-commit
if not exist "%REPO_ROOT%	ools\coding-standard\hooks\pre-commit.cmd" (
  echo ERROR: Missing tools\coding-standard\hooks\pre-commit.cmd
  exit /b 1
)
echo OK: Found hooks\pre-commit.cmd
echo.

echo [3/6] Checking clang-format on user PATH...
where clang-format >nul 2>nul
if errorlevel 1 (
  echo ERROR: clang-format was not found on PATH.
  echo Run tools\coding-standard\scripts\install-user-tools.cmd first, or provide clang-format on user PATH.
  exit /b 1
)
for /f "delims=" %%i in ('clang-format --version') do set CLANGFORMATVER=%%i
echo OK: !CLANGFORMATVER!
echo.

echo [4/6] Checking Python...
where py >nul 2>nul
if %ERRORLEVEL%==0 (
  for /f "delims=" %%i in ('py -3 --version 2^>^&1') do set PYTHONVER=%%i
  echo OK: !PYTHONVER!
  set PYTHONCMD=py -3
  goto :python_done
)
where python >nul 2>nul
if %ERRORLEVEL%==0 (
  for /f "delims=" %%i in ('python --version 2^>^&1') do set PYTHONVER=%%i
  echo OK: !PYTHONVER!
  set PYTHONCMD=python
  goto :python_done
)
echo ERROR: Python 3 was not found on PATH.
exit /b 1
:python_done
echo.

echo [5/6] Checking clang-tidy on user PATH...
where clang-tidy >nul 2>nul
if errorlevel 1 (
  echo WARNING: clang-tidy was not found on PATH.
  echo Formatting hooks will still work.
  echo Linting will be skipped until clang-tidy is installed.
) else (
  for /f "delims=" %%i in ('clang-tidy --version') do set CLANGTIDYVER=%%i
  echo OK: !CLANGTIDYVER!
)
echo.

echo [6/6] Running Python smoke test...
%PYTHONCMD% "%REPO_ROOT%	ools\coding-standard\scripts\clang_format_staged.py" --help >nul 2>nul
if errorlevel 1 (
  echo WARNING: Smoke test did not return success with --help.
  echo Continuing.
) else (
  echo OK: Python script invocation succeeded.
)
echo.
echo Setup complete.
echo Repo-local configuration only was changed.
echo No global Git configuration was modified.
exit /b 0
