@echo off
echo Updating repository, applying content, and restarting after validation...
ssh l4d2-vps "sudo l4d2-update-and-restart"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Update and apply complete.) else (echo Update or apply failed with SSH exit code %result%.)
pause
exit /b %result%
