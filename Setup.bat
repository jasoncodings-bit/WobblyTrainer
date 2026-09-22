@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Wobbly Tools - Setup

rem ---------------------------------------------------------------------
rem  Installs Wobbly Tools (and the BepInEx loader it needs) into a Wobbly
rem  Life install.
rem
rem  Downloads the mod from GitHub. If the files happen to already be sat
rem  next to this script (you grabbed the whole repo, not just the .bat),
rem  it uses those instead and skips the download.
rem
rem  Copies only - nothing is ever deleted, so an existing BepInEx setup
rem  keeps any other mods already in plugins\.
rem
rem  Usage:  Setup.bat                 find the game automatically
rem          Setup.bat "C:\path\..."   install into a specific folder
rem ---------------------------------------------------------------------

set "REPO=jasoncodings-bit/WobblyMod"
set "GAMEEXE=Wobbly Life.exe"

set "SRC=%~dp0"
if "%SRC:~-1%"=="\" set "SRC=%SRC:~0,-1%"
set "DEST="
set "PAYLOAD="
set "TMPROOT=%TEMP%\WobblyToolsSetup"

echo.
echo  ==========================================
echo    Wobbly Tools - Setup
echo  ==========================================
echo.

call :find_game %1
if not defined DEST goto :no_game

echo.
echo  Game folder:
echo    %DEST%
echo.

call :get_payload
if not defined PAYLOAD goto :no_payload

rem --- install ---------------------------------------------------------
if /i "%PAYLOAD%"=="%DEST%" (
    echo  The files are already in place here - nothing to copy.
    goto :done
)

set "MODDIR=%DEST%\BepInEx\plugins\WobblyTools"
set "ACTION=Installing"
if exist "%DEST%\BepInEx\plugins\WobblyTools.dll" set "ACTION=Updating"

if "%ACTION%"=="Updating" (
    echo  Wobbly Tools is already installed here - updating it in place.
    echo  Your settings and tuner offsets are kept.
    echo.
) else (
    if exist "%DEST%\BepInEx\core\BepInEx.dll" (
        echo  BepInEx is already installed here. Other mods in plugins\ are
        echo  left alone.
        echo.
    )
)

rem Updating: clear the mod's own asset folders first, so an icon or sound
rem that was renamed or dropped in a newer version doesn't linger alongside
rem its replacement. Only these two go - settings.json and the *_offsets.json
rem beside them belong to the player, not to the package.
if exist "%MODDIR%\Icons" rmdir /s /q "%MODDIR%\Icons" 2>nul
if exist "%MODDIR%\Sfx" rmdir /s /q "%MODDIR%\Sfx" 2>nul

echo  %ACTION%...

rem /E all subfolders. /IS and /IT together mean "copy it even if robocopy
rem thinks it matches or was tweaked" - without them an update where the file
rem size happened to match would be skipped. Still no /PURGE, so anything
rem else in the game folder (other mods included) is left alone. The
rem exclusions are repo furniture that shouldn't end up in a game folder.
robocopy "%PAYLOAD%" "%DEST%" /E /IS /IT /NFL /NDL /NJH /NJS /NP ^
    /XF "Setup.bat" "README.txt" "README.md" "LICENSE" ".gitignore" "*.md" ^
    /XD ".git" ".github" >nul
if errorlevel 8 goto :copy_failed

if not exist "%DEST%\winhttp.dll" goto :copy_failed
if not exist "%DEST%\BepInEx\plugins\WobblyTools.dll" goto :copy_failed

:done
call :cleanup
echo.
echo  ==========================================
echo    Done. Launch Wobbly Life and press F2.
echo  ==========================================
echo.
echo  First launch takes a little longer than usual - BepInEx is setting
echo  itself up. If the menu doesn't appear, check that the game is the
echo  Windows version and that you launched it through Steam.
echo.
echo  To uninstall: delete winhttp.dll, doorstop_config.ini and
echo  .doorstop_version from the game folder, plus BepInEx\plugins\
echo  WobblyTools.dll and BepInEx\plugins\WobblyTools\.
echo.
pause
exit /b 0


rem =====================================================================
rem  Work out where the mod files are: beside this script, or from GitHub.
rem =====================================================================
:get_payload
if exist "%SRC%\BepInEx\core\BepInEx.dll" if exist "%SRC%\winhttp.dll" (
    set "PAYLOAD=%SRC%"
    echo  Using the files next to this script.
    exit /b 0
)

echo  Downloading Wobbly Tools from github.com/%REPO% ...
echo.

call :cleanup
mkdir "%TMPROOT%" 2>nul

call :download main
if not exist "%TMPROOT%\repo.zip" call :download master
if not exist "%TMPROOT%\repo.zip" (
    echo.
    echo  Download failed.
    echo.
    echo  Check that you're online, then try again. If your antivirus or a
    echo  work/school network blocks it, download the repo as a ZIP from
    echo    https://github.com/%REPO%
    echo  extract it, and run the Setup.bat inside it instead.
    echo.
    call :cleanup
    pause
    exit /b 1
)

rem Find the payload root inside the extracted tree: the folder that holds
rem BepInEx\core\BepInEx.dll. Doing it by search rather than by a fixed path
rem means it works whether the files sit at the repo root or in a subfolder,
rem and copes with the "<repo>-main\" wrapper GitHub puts in its zips.
for /f "delims=" %%F in ('dir /b /s "%TMPROOT%\extracted\BepInEx.dll" 2^>nul') do (
    if not defined PAYLOAD (
        for %%A in ("%%~dpF..\..") do set "PAYLOAD=%%~fA"
    )
)

if not defined PAYLOAD exit /b 0
if not exist "!PAYLOAD!\winhttp.dll" set "PAYLOAD="
exit /b 0

:download
rem  %1 = branch name. Leaves repo.zip in place only if it fully succeeded.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "Invoke-WebRequest -Uri 'https://github.com/%REPO%/archive/refs/heads/%1.zip' -OutFile '%TMPROOT%\repo.zip' -UseBasicParsing;" ^
  "Expand-Archive -LiteralPath '%TMPROOT%\repo.zip' -DestinationPath '%TMPROOT%\extracted' -Force" >nul 2>&1
if errorlevel 1 del /q "%TMPROOT%\repo.zip" 2>nul
exit /b 0

:cleanup
if exist "%TMPROOT%" rmdir /s /q "%TMPROOT%" 2>nul
exit /b 0


rem =====================================================================
rem  Work out which folder the game is in.
rem =====================================================================
:find_game
rem --- 1. explicit path passed on the command line (or dragged onto the bat) ---
if not "%~1"=="" (
    set "DEST=%~1"
    call :strip_slash DEST
    if exist "!DEST!\%GAMEEXE%" (
        echo  Using the folder you gave me.
        exit /b 0
    )
    echo  That folder has no %GAMEEXE% in it:
    echo    !DEST!
    echo.
    set "DEST="
)

rem --- 2. sitting inside the game folder already? ---
if exist "%SRC%\%GAMEEXE%" (
    set "DEST=%SRC%"
    echo  Found the game in this folder.
    exit /b 0
)
for %%P in ("%SRC%\..") do set "UP=%%~fP"
if exist "!UP!\%GAMEEXE%" (
    set "DEST=!UP!"
    echo  Found the game one folder up.
    exit /b 0
)

rem --- 3. ask Steam where its libraries are ---
echo  Looking for Wobbly Life via Steam...
set "STEAM="
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v InstallPath 2^>nul ^| find "InstallPath"') do set "STEAM=%%B"
if not defined STEAM for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Valve\Steam" /v InstallPath 2^>nul ^| find "InstallPath"') do set "STEAM=%%B"
if not defined STEAM for /f "tokens=2,*" %%A in ('reg query "HKCU\SOFTWARE\Valve\Steam" /v SteamPath 2^>nul ^| find "SteamPath"') do set "STEAM=%%B"

if defined STEAM (
    call :strip_slash STEAM
    set "STEAM=!STEAM:/=\!"
    call :try_library "!STEAM!"
    if defined DEST exit /b 0

    rem Every extra drive/library Steam knows about lives in this file. Paths
    rem in it are VDF-escaped, so a doubled backslash has to be collapsed.
    set "VDF=!STEAM!\steamapps\libraryfolders.vdf"
    if exist "!VDF!" (
        for /f usebackq^ tokens^=4^ delims^=^" %%L in (`findstr /i /c:"\"path\"" "!VDF!"`) do (
            if not defined DEST (
                set "LIB=%%L"
                set "LIB=!LIB:\\=\!"
                call :try_library "!LIB!"
            )
        )
        if defined DEST exit /b 0
    )
)

rem --- 4. give up and ask ---
echo.
echo  Couldn't find Wobbly Life automatically.
echo.
echo  Paste the folder that contains %GAMEEXE% and press Enter.
echo  (In Steam: right-click Wobbly Life - Manage - Browse local files,
echo   then copy the path from the address bar.)
echo.
set /p "DEST=  Game folder: "
rem %-form, not !-form: a literal quote inside a delayed-expansion
rem substitution confuses cmd's parser. This line isn't in a block, so
rem plain %DEST% expands fine.
set DEST=%DEST:"=%
call :strip_slash DEST
if not defined DEST exit /b 0
if not exist "!DEST!\%GAMEEXE%" set "DEST="
exit /b 0

:try_library
rem  %1 = a Steam library root; sets DEST if Wobbly Life lives under it.
set "CAND=%~1\steamapps\common\Wobbly Life"
if exist "%CAND%\%GAMEEXE%" (
    set "DEST=%CAND%"
    echo  Found it in a Steam library.
)
exit /b 0

:strip_slash
rem  %1 = name of a variable to trim a trailing backslash from.
call set "_V=%%%~1%%"
if "!_V:~-1!"=="\" set "_V=!_V:~0,-1!"
set "%~1=!_V!"
exit /b 0


rem =====================================================================
:no_game
echo.
echo  No Wobbly Life folder, so nothing was installed.
echo.
pause
exit /b 1

:no_payload
echo.
echo  Downloaded the repo, but it doesn't look like a Wobbly Tools package -
echo  no BepInEx\core\BepInEx.dll and winhttp.dll in it.
echo.
echo  If you're the one publishing it: the repo needs winhttp.dll,
echo  doorstop_config.ini, .doorstop_version and the BepInEx folder at its
echo  root (or all together in one subfolder).
echo.
call :cleanup
pause
exit /b 1

:copy_failed
echo.
echo  The copy didn't finish. The usual cause is the game still running,
echo  or the folder needing admin rights.
echo.
echo  Close Wobbly Life and Steam, then right-click Setup.bat and pick
echo  "Run as administrator".
echo.
call :cleanup
pause
exit /b 1
