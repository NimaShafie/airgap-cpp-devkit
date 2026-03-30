REM Author: Nima Shafie
@echo off
REM ====================================================
REM setup.bat
REM Thin launcher — forwards all arguments to setup.ps1.
REM Do not add logic here.
REM ====================================================
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
exit /b %errorlevel%