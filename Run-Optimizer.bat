@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Pro Universal Windows Optimizer - Launcher
cd /d "%~dp0"

REM =====================================================================
REM  Pro Universal Windows Optimizer  -  Bilingual launcher (.bat)
REM  -------------------------------------------------------------------
REM  EN: One-click entry point. It (1) elevates to Administrator,
REM      (2) finds the optimizer .ps1 next to this file, (3) makes sure
REM      PowerShell 7 (pwsh) is installed, then launches the script.
REM  PL: Punkt wejscia jednym kliknieciem. (1) podnosi uprawnienia do
REM      administratora, (2) znajduje plik .ps1 obok tego pliku,
REM      (3) sprawdza PowerShell 7 (pwsh) i uruchamia skrypt.
REM
REM  NOTE: console messages use plain ASCII on purpose (no Polish
REM        diacritics) so they render correctly on every code page.
REM =====================================================================

REM ---- 1. Detect UI language: pl => Polish, otherwise English --------
set "L=en"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-UICulture).TwoLetterISOLanguageName" 2^>nul`) do set "L=%%i"

REM ---- 2. Require Administrator (self-elevate if needed) -------------
net session >nul 2>&1
if %errorlevel%==0 goto :find_script
if /i "%L%"=="pl" (echo Podnosze uprawnienia do administratora...) else (echo Elevating to Administrator...)
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:find_script
REM ---- 3. Locate optimizer script (newest matching name first) ------
set "SCRIPT="
for /f "delims=" %%f in ('dir /b /a-d /o-n "Pro-Universal-Windows-Optimizer-*.ps1" 2^>nul') do if not defined SCRIPT set "SCRIPT=%~dp0%%f"
if defined SCRIPT goto :find_pwsh
for /f "delims=" %%f in ('dir /b /a-d "*.ps1" 2^>nul') do if not defined SCRIPT set "SCRIPT=%~dp0%%f"
if defined SCRIPT goto :find_pwsh
if /i "%L%"=="pl" (echo [BLAD] Nie znaleziono pliku .ps1 obok launchera.) else (echo [ERROR] No .ps1 found next to this launcher.)
if /i "%L%"=="pl" (echo Umiesc Run-Optimizer.bat w tym samym folderze co skrypt .ps1) else (echo Put Run-Optimizer.bat in the same folder as the .ps1 script.)
echo.
pause
exit /b 1

:find_pwsh
REM ---- 4. Find PowerShell 7 -----------------------------------------
set "PWSH="
for /f "delims=" %%p in ('where pwsh 2^>nul') do if not defined PWSH set "PWSH=%%p"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if defined PWSH goto :run
goto :no_pwsh

:no_pwsh
if /i "%L%"=="pl" (echo PowerShell 7 ^(pwsh^) nie zostal znaleziony - jest wymagany.) else (echo PowerShell 7 ^(pwsh^) was not found - it is required.)
where winget >nul 2>&1
if not %errorlevel%==0 goto :open_dl
set "ANS="
if /i "%L%"=="pl" (set /p "ANS=Zainstalowac teraz przez winget? [T/N]: ") else (set /p "ANS=Install now via winget? [Y/N]: ")
if /i "!ANS!"=="t" goto :winget
if /i "!ANS!"=="y" goto :winget
goto :open_dl

:winget
winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
set "PWSH="
for /f "delims=" %%p in ('where pwsh 2^>nul') do if not defined PWSH set "PWSH=%%p"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if defined PWSH goto :run
if /i "%L%"=="pl" (echo Instalacja nieukonczona - uruchom launcher ponownie po jej zakonczeniu.) else (echo Install incomplete - run the launcher again once it finishes.)
echo.
pause
exit /b 1

:open_dl
if /i "%L%"=="pl" (echo Otwieram strone pobierania PowerShell 7...) else (echo Opening the PowerShell 7 download page...)
start "" "https://aka.ms/powershell"
echo.
pause
exit /b 1

:run
if /i "%L%"=="pl" (echo Uruchamiam skrypt...) else (echo Launching the script...)
echo.
"!PWSH!" -NoProfile -ExecutionPolicy Bypass -File "!SCRIPT!" %*
set "RC=!errorlevel!"
echo.
if /i "%L%"=="pl" (echo Zakonczono. Kod wyjscia: !RC!) else (echo Finished. Exit code: !RC!)
pause
endlocal & exit /b %RC%
