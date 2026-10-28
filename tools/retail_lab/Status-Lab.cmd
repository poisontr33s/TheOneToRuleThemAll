@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 goto use_python
py -3 "%~dp0lab.py" --status %*
goto finished
:use_python
python "%~dp0lab.py" --status %*
:finished
set "lab_exit=%errorlevel%"
pause
exit /b %lab_exit%
