@echo off
setlocal
for /f "delims=" %%i in ('git rev-parse --show-toplevel') do set REPO_ROOT=%%i
cd /d "%REPO_ROOT%"
where py >nul 2>nul
if %ERRORLEVEL%==0 (
  py -3 tools\coding-standard\scripts\clang_format_staged.py
  if errorlevel 1 exit /b 1
  py -3 tools\coding-standard\scripts\clang_tidy_changed.py
  if errorlevel 1 exit /b 1
  exit /b 0
)
where python >nul 2>nul
if %ERRORLEVEL%==0 (
  python tools\coding-standard\scripts\clang_format_staged.py
  if errorlevel 1 exit /b 1
  python tools\coding-standard\scripts\clang_tidy_changed.py
  if errorlevel 1 exit /b 1
  exit /b 0
)
echo ERROR: Python not found.
exit /b 1
