@echo off
REM Script to download and setup libusb for Android NDK integration
REM Run from project root: scripts\setup_libusb.bat
REM Requires: curl or PowerShell (available on modern Windows)

setlocal enabledelayedexpansion

set LIBUSB_VERSION=1.0.27
set LIBUSB_DIR=android\app\src\main\jni\libusb
set LIBUSB_ZIP=libusb-%LIBUSB_VERSION%.tar.bz2
set LIBUSB_URL=https://github.com/libusb/libusb/releases/download/v%LIBUSB_VERSION%/%LIBUSB_ZIP%

echo ==^> Setting up libusb %LIBUSB_VERSION% for Android NDK

REM Create libusb directory
if not exist "%LIBUSB_DIR%" mkdir "%LIBUSB_DIR%"

if exist "%LIBUSB_DIR%\CMakeLists.txt" (
    echo ==^> libusb already appears to be present at %LIBUSB_DIR%
    echo     Delete it and re-run to re-download
    exit /b 0
)

REM Download using PowerShell (built-in on Windows 7+)
echo ==^> Downloading %LIBUSB_URL%...
powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%LIBUSB_URL%' -OutFile '%TEMP%\%LIBUSB_ZIP%'}"

if %errorlevel% neq 0 (
    echo Failed to download libusb. Check internet connection.
    exit /b 1
)

REM Extract using tar (built-in on Windows 10 1803+)
echo ==^> Extracting...
if exist "%TEMP%\libusb-%LIBUSB_VERSION%" rmdir /s /q "%TEMP%\libusb-%LIBUSB_VERSION%"

tar -xjf "%TEMP%\%LIBUSB_ZIP%" -C "%TEMP%"
if %errorlevel% neq 0 (
    echo tar extraction failed. Trying PowerShell extraction...
    powershell -Command "& {Add-Type -Assembly 'System.IO.Compression.FileSystem'; [System.IO.Compression.ZipFile]::ExtractToDirectory('%TEMP%\%LIBUSB_ZIP%', '%TEMP%\libusb-%LIBUSB_VERSION%')}"
)

REM Copy extracted files
xcopy /s /e /y "%TEMP%\libusb-%LIBUSB_VERSION%\*" "%LIBUSB_DIR%\"

REM Clean up
rmdir /s /q "%TEMP%\libusb-%LIBUSB_VERSION%"
del "%TEMP%\%LIBUSB_ZIP%"

echo ==^> libusb %LIBUSB_VERSION% extracted to %LIBUSB_DIR%
echo.
echo     Next step: ensure your CMakeLists.txt has:
echo         add_subdirectory(jni/libusb)
echo         target_link_libraries(usb_dac_driver libusb-1.0)
echo.
echo     The NDK build will automatically compile libusb from source.
