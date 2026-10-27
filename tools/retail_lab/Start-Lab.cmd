@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 goto use_python
py -3 "%~dp0lab.py" --install %*
goto finished
:use_python
python "%~dp0lab.py" --install %*
:finished
if errorlevel 1 pause
endlocal
