@echo off
setlocal

echo ========================================================
echo   Running Verilog Toolchain Installers
echo ========================================================
echo.

:: 1. Call ctags installer
if exist "%~dp0install_ctags.bat" (
    echo [INFO] Executing install_ctags.bat...
    call "%~dp0install_ctags.bat"
) else (
    echo [ERROR] install_ctags.bat not found in the current directory.
)

echo.
echo --------------------------------------------------------
echo.

:: 2. Call Verible installer
if exist "%~dp0install_verible.bat" (
    echo [INFO] Executing install_verible.bat...
    call "%~dp0install_verible.bat"
) else (
    echo [ERROR] install_verible.bat not found in the current directory.
)

echo.
echo ========================================================
echo   All installation steps completed!
echo   Please restart Cursor / VS Code for PATH changes to take effect.
echo ========================================================
echo.

endlocal