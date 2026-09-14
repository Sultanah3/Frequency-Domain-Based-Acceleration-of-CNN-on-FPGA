@echo off
setlocal enabledelayedexpansion

:: 1. Check if verible-verilog-format is already accessible in PATH
where verible-verilog-format >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [INFO] verible-verilog-format is already installed and available in system PATH.
    verible-verilog-format --version
    goto :END
)

echo [INFO] verible-verilog-format not found. Starting installation...

:: 2. Define installation directory (User's AppData\Local\Verible)
set "INSTALL_DIR=%LOCALAPPDATA%\Verible"
set "ZIP_FILE=%TEMP%\verible_latest.zip"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

:: 3. Query GitHub API for the latest Windows release download URL
echo [INFO] Fetching latest Windows release download link from GitHub...
for /f "tokens=*" %%I in ('powershell -NoProfile -Command "(Invoke-RestMethod -Uri 'https://api.github.com/repos/chipsalliance/verible/releases/latest').assets | Where-Object { $_.name -like '*win64*.zip' -or $_.name -like '*win32*.zip' } | Select-Object -ExpandProperty browser_download_url"') do (
    set "DOWNLOAD_URL=%%I"
)

if "%DOWNLOAD_URL%"=="" (
    echo [ERROR] Failed to fetch the release download URL from GitHub.
    goto :ERROR_EXIT
)

:: 4. Download the release ZIP archive
echo [INFO] Downloading Verible from: %DOWNLOAD_URL%
powershell -NoProfile -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%'"
if not exist "%ZIP_FILE%" (
    echo [ERROR] Download failed.
    goto :ERROR_EXIT
)

:: 5. Extract files directly into the installation directory
echo [INFO] Extracting archive to %INSTALL_DIR%...
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%TEMP%\verible_temp' -Force"

:: Move extracted contents (Verible zip files contain a nested top-level folder)
for /d %%D in ("%TEMP%\verible_temp\*") do (
    xcopy "%%D\*" "%INSTALL_DIR%\" /E /Y /Q >nul
)

:: Clean up temporary extraction files
rd /s /q "%TEMP%\verible_temp"
del /f /q "%ZIP_FILE%"

:: 6. Add to User PATH variable if not already present
echo [INFO] Updating User PATH variable...
for /f "tokens=2*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"

echo !USER_PATH! | find /i "%INSTALL_DIR%" >nul
if %ERRORLEVEL% neq 0 (
    if defined USER_PATH (
        setx PATH "!USER_PATH!;%INSTALL_DIR%" >nul
    ) else (
        setx PATH "%INSTALL_DIR%" >nul
    )
    echo [SUCCESS] Added %INSTALL_DIR% to User PATH.
) else (
    echo [INFO] %INSTALL_DIR% is already in User PATH.
)

:: 7. Verify executable in local path
if exist "%INSTALL_DIR%\verible-verilog-format.exe" (
    echo [SUCCESS] verible-verilog-format installed successfully!
    echo [NOTE] Restart Cursor/VS Code or open a new Terminal window for PATH changes to take effect.
) else (
    echo [ERROR] Installation failed. Binary not found in %INSTALL_DIR%.
    goto :ERROR_EXIT
)

goto :END

:ERROR_EXIT
echo [FAIL] Installation process encountered an error.
exit /b 1

:END
endlocal