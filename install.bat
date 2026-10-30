@echo off
rem Installs SR5 Tweak Menu into Saints Row (2022): dinput8.dll next to SaintsRow_DX12.exe,
rem the menu's files in TweakMenu\SRTweakMenu. Your mod.ini is kept if you have one.
rem Usage: install.bat ["path to the game's sr5 folder"]   (default: Epic's folder)
setlocal
set "HERE=%~dp0"
set "GAME=%~1"
if "%GAME%"=="" set "GAME=C:\Program Files\Epic Games\SaintsRow\sr5"
if not exist "%GAME%\SaintsRow_DX12.exe" goto :no_game
if not exist "%HERE%build\dinput8.dll" goto :no_dll
copy /y "%HERE%build\dinput8.dll" "%GAME%\dinput8.dll" >nul 2>nul && goto :dll_done
rem In use (the game or its launcher is running): move it aside, it's replaced on the next launch.
ren "%GAME%\dinput8.dll" "dinput8_old_%RANDOM%.dll" || goto :copy_failed
copy /y "%HERE%build\dinput8.dll" "%GAME%\dinput8.dll" >nul || goto :copy_failed
echo The game is running: the new host loads the next time it starts.
:dll_done
del /q "%GAME%\dinput8_old_*.dll" 2>nul
if not exist "%GAME%\TweakMenu\SRTweakMenu" mkdir "%GAME%\TweakMenu\SRTweakMenu"
copy /y "%HERE%SRTweakMenu\*.lua" "%GAME%\TweakMenu\SRTweakMenu\" >nul || goto :copy_failed
if not exist "%GAME%\TweakMenu\SRTweakMenu\mod.ini" copy "%HERE%SRTweakMenu\mod.ini" "%GAME%\TweakMenu\SRTweakMenu\" >nul
echo Installed. Start Saints Row with DirectX 12.
exit /b 0
:no_game
echo Saints Row (2022) not found in "%GAME%". Pass its sr5 folder: install.bat "D:\Games\SaintsRow\sr5"
exit /b 1
:no_dll
echo build\dinput8.dll is missing: run host\build.bat first.
exit /b 1
:copy_failed
echo Copying failed (is the game running?).
exit /b 1
