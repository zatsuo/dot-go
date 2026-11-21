@echo off
rem Copy the shared scripts (solid / view / theme) from dot-godough
cd /d "%~dp0"
for %%f in (solid.gd pixel_view.gd xp.gd) do copy /y "..\dot-godough\scripts\%%f" "scripts\%%f"
pause
