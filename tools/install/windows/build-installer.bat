@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT=%~dp0rex-installer.iss"
set "REPO_ROOT=%~dp0..\..\.."
for %%I in ("%REPO_ROOT%") do set "REPO_ROOT=%%~fI"
set "OUTDIR=%REPO_ROOT%\dist\windows"
set "TOOLS_DIR=%REPO_ROOT%\dist\tools"
set "PORTABLE_ROOT=%TOOLS_DIR%\innosetup-portable"
set "PORTABLE_HINT=%TOOLS_DIR%\innosetup-6.x.x-portable.zip"

if not exist "%OUTDIR%" mkdir "%OUTDIR%"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"

set "INNO_PORTABLE_ZIP_PATH="
if not "%~3"=="" (
  if exist "%~3" (
    set "INNO_PORTABLE_ZIP_PATH=%~f3"
  ) else (
    set "INNO_PORTABLE_URL=%~3"
  )
)
if defined INNO_PORTABLE_URL (
  echo.%INNO_PORTABLE_URL% | findstr /C:"..." >nul
  if not errorlevel 1 (
    echo [ERROR] Invalid URL placeholder detected: %INNO_PORTABLE_URL%
    echo [INFO] Use a real URL (not https://...).
    echo [INFO] Example:
    echo        tools\install\windows\build-installer.bat "C:\lua\lua.exe" 0.1.0 "https://example.com/innosetup-6.7.0-portable.zip"
    exit /b 1
  )
)

call :find_iscc
if not exist "%ISCC%" (
  echo [INFO] Inno Setup compiler not found. Bootstrapping portable archive...
  call :bootstrap_iscc_portable
  call :find_iscc
)
if not exist "%ISCC%" (
  echo [ERROR] Inno Setup compiler is still missing after portable bootstrap.
  echo [INFO] Put portable ZIP here:
  echo        %PORTABLE_HINT%
  echo [INFO] Or run with URL/path as 3rd arg:
  echo        build-installer.bat [lua.exe] [version] [zip-or-url]
  exit /b 1
)

set "APP_VERSION=0.1.0"
if not "%~2"=="" set "APP_VERSION=%~2"

set "LUA_EXE="
if not "%~1"=="" (
  if not exist "%~1" (
    echo [ERROR] Lua path not found: %~1
    exit /b 1
  )
  set "LUA_EXE=%~f1"
)
if not defined LUA_EXE (
  for /f "delims=" %%I in ('where lua.exe 2^>nul') do (
    if not defined LUA_EXE set "LUA_EXE=%%~fI"
  )
)

echo Building Rex installer...
echo   Repo    : %REPO_ROOT%
echo   Version : %APP_VERSION%
echo   ISCC    : %ISCC%
if defined INNO_PORTABLE_ZIP_PATH echo   InnoZip : %INNO_PORTABLE_ZIP_PATH%
if defined INNO_PORTABLE_URL echo   InnoURL : %INNO_PORTABLE_URL%
if defined LUA_EXE (
  echo   Lua    : %LUA_EXE%
) else (
  echo   Lua    : not found ^(installer will require lua.exe in PATH on target machine^)
)
echo.

if defined LUA_EXE (
  "%ISCC%" /DRepoRoot="%REPO_ROOT%" /DMyAppVersion="%APP_VERSION%" /DLuaExe="%LUA_EXE%" /O"%OUTDIR%" "%SCRIPT%"
) else (
  "%ISCC%" /DRepoRoot="%REPO_ROOT%" /DMyAppVersion="%APP_VERSION%" /O"%OUTDIR%" "%SCRIPT%"
)
if errorlevel 1 (
  echo.
  echo [ERROR] Build failed.
  exit /b 1
)

echo.
echo [OK] Installer created in:
echo   %OUTDIR%
exit /b 0

:find_iscc
set "ISCC="
if exist "%PORTABLE_ROOT%\ISCC.exe" set "ISCC=%PORTABLE_ROOT%\ISCC.exe"
if "%ISCC%"=="" (
  for /f "delims=" %%I in ('dir /s /b "%PORTABLE_ROOT%\ISCC.exe" 2^>nul') do (
    set "ISCC=%%~fI"
    goto :find_iscc_done
  )
)
:find_iscc_done
if "%ISCC%"=="" if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if "%ISCC%"=="" if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
goto :eof

:bootstrap_iscc_portable
set "PWSH="
for %%I in (powershell.exe pwsh.exe) do (
  where %%I >nul 2>nul
  if not errorlevel 1 if "%PWSH%"=="" set "PWSH=%%I"
)

set "PORTABLE_ZIP="
if defined INNO_PORTABLE_ZIP_PATH set "PORTABLE_ZIP=%INNO_PORTABLE_ZIP_PATH%"
if "%PORTABLE_ZIP%"=="" (
  for /f "delims=" %%I in ('dir /b /a-d /o-n "%TOOLS_DIR%\innosetup-*-portable.zip" 2^>nul') do (
    set "PORTABLE_ZIP=%TOOLS_DIR%\%%I"
    goto :portable_zip_selected
  )
)
:portable_zip_selected
if "%PORTABLE_ZIP%"=="" set "PORTABLE_ZIP=%TOOLS_DIR%\innosetup-portable.zip"

if not exist "%PORTABLE_ZIP%" (
  if "%INNO_PORTABLE_URL%"=="" (
    echo [ERROR] Portable archive not found.
    echo [INFO] Put file here:
    echo        %PORTABLE_HINT%
    echo [INFO] Or set URL / pass it as 3rd arg.
    exit /b 1
  )
  echo [INFO] Downloading Inno Setup portable archive...
  if not "%PWSH%"=="" (
    "%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';Invoke-WebRequest -Uri '%INNO_PORTABLE_URL%' -OutFile '%PORTABLE_ZIP%' -MaximumRedirection 5 -TimeoutSec 120"
  ) else (
    where curl.exe >nul 2>nul
    if errorlevel 1 (
      echo [ERROR] PowerShell/curl not found for portable download.
      exit /b 1
    )
    curl.exe -L --connect-timeout 20 --max-time 180 -o "%PORTABLE_ZIP%" "%INNO_PORTABLE_URL%"
  )
  if errorlevel 1 (
    echo [ERROR] Download failed:
    echo        %INNO_PORTABLE_URL%
    exit /b 1
  )
)

for %%I in ("%PORTABLE_ZIP%") do (
  if %%~zI LEQ 0 (
    echo [ERROR] Portable archive is empty:
    echo        %PORTABLE_ZIP%
    exit /b 1
  )
)

if /I not "%PORTABLE_ZIP:~-4%"==".zip" (
  echo [ERROR] Portable archive must be ZIP:
  echo        %PORTABLE_ZIP%
  exit /b 1
)

if "%PWSH%"=="" (
  echo [ERROR] PowerShell not found. Required for ZIP extraction.
  exit /b 1
)

echo [INFO] Extracting portable archive...
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';if (Test-Path '%PORTABLE_ROOT%') { Remove-Item -LiteralPath '%PORTABLE_ROOT%' -Recurse -Force };New-Item -ItemType Directory -Path '%PORTABLE_ROOT%' | Out-Null;Expand-Archive -LiteralPath '%PORTABLE_ZIP%' -DestinationPath '%PORTABLE_ROOT%' -Force"
if errorlevel 1 (
  echo [ERROR] Failed to extract portable ZIP:
  echo        %PORTABLE_ZIP%
  exit /b 1
)

goto :eof
