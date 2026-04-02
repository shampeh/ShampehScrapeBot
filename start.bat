@echo off
title SHAMP.SCRAPE.BOT
echo Starting SHAMP.SCRAPE.BOT server...

where node >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ERROR: Node.js not found. Please install it from https://nodejs.org
    pause
    exit /b 1
)

cd /d "%~dp0"
start "" "%~dp0yt-dlp-gui.html"
node server.js
