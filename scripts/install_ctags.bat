@echo off
setlocal enabledelayedexpansion

:: 1. Check if ctags is already accessible in PATH
where ctags >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo [INFO] universal-ctags is already installed and available in system PATH.
    ctags --version
    goto :END
)

echo [INFO] Starting universal-ctags installation...

:: 2. Define installation directory
set "INSTALL_DIR=%LOCALAPPDATA%\ctags"
set "ZIP_FILE=%TEMP%\ctags_latest.zip"
set "EXTRACT_DIR=%TEMP%\ctags_temp"

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if exist "%EXTRACT_DIR%" rd /s /q "%EXTRACT_DIR%"

:: 3. Query GitHub API for the release ZIP (excluding .debuginfo archives)
echo [INFO] Fetching latest Windows release download link from GitHub...
for /f "tokens=*" %%I in ('powershell -NoProfile -Command "(Invoke-RestMethod -Uri 'https://api.github.com/repos/universal-ctags/ctags-win32/releases/latest').assets | Where-Object { ($_.name -like '*x64*.zip' -or $_.name -like '*win64*.zip') -and $_.name -notlike '*debuginfo*' } | Select-Object -First 1 -ExpandProperty browser_download_url"') do (
    set "DOWNLOAD_URL=%%I"
)

if "%DOWNLOAD_URL%"=="" (
    echo [ERROR] Failed to fetch the release download URL from GitHub.
    goto :ERROR_EXIT
)

:: 4. Download the release ZIP archive
echo [INFO] Downloading universal-ctags from: %DOWNLOAD_URL%
powershell -NoProfile -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%ZIP_FILE%'"
if not exist "%ZIP_FILE%" (
    echo [ERROR] Download failed.
    goto :ERROR_EXIT
)

:: 5. Extract files
echo [INFO] Extracting archive...
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%EXTRACT_DIR%' -Force"

:: Search recursively for ctags.exe in the extracted directory and copy its parent folder contents
set "FOUND_PATH="
for /f "delims=" %%F in ('dir /b /s "%EXTRACT_DIR%\ctags.exe" 2^>nul') do (
    set "FOUND_PATH=%%~dpF"
)

if defined FOUND_PATH (
    echo [INFO] Moving ctags binaries to %INSTALL_DIR%...
    xcopy "%FOUND_PATH%*" "%INSTALL_DIR%\" /E /Y /Q >nul
) else (
    echo [ERROR] Could not locate ctags.exe inside extracted files.
    goto :ERROR_EXIT
)

:: Clean up temporary extraction files
rd /s /q "%EXTRACT_DIR%"
del /f /q "%ZIP_FILE%"

:: 6. Update User PATH variable
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

:: 7. Verification
if exist "%INSTALL_DIR%\ctags.exe" (
    echo.
    echo ========================================================
    echo [SUCCESS] universal-ctags installed successfully!
    echo Executable path: %INSTALL_DIR%\ctags.exe
    echo ========================================================
) else (
    echo [ERROR] Installation failed. Binary missing from %INSTALL_DIR%.
    goto :ERROR_EXIT
)

goto :END

:ERROR_EXIT
echo [FAIL] Installation process encountered an error.
exit /b 1

:END
endlocal