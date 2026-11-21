@echo off
rem dot-Godough (C# build, then start)
cd /d "%~dp0"
dotnet build -v q -nologo || (pause & exit /b 1)
start "" "%USERPROFILE%\Godot_v4.6-stable_mono_win64\Godot_v4.6-stable_mono_win64.exe" --path "%~dp0." %*
