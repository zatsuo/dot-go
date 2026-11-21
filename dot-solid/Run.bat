@echo off
rem dot-Godough Solid
cd /d "%~dp0"
start "" "%USERPROFILE%\Godot_v4.6-stable_mono_win64\Godot_v4.6-stable_mono_win64.exe" --path "%~dp0." %*
