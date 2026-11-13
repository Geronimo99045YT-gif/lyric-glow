@echo off
title Lyric Glow - made by Chaz
cd /d "%~dp0"
set PY=
where python >nul 2>nul && set PY=python
if "%PY%"=="" where py >nul 2>nul && set PY=py
if "%PY%"=="" goto nopy
echo.
echo   Lyric Glow is running. Leave this window open while you use it.
echo   Close this window to stop it.
echo.
start "" http://127.0.0.1:8888/lyric-glow.html
%PY% server.py
goto :eof
:nopy
echo.
echo   Python isn't installed. Get it free at https://www.python.org/downloads/
echo   (tick "Add Python to PATH" in the installer), then run this again.
echo.
pause
