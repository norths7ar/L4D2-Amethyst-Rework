@echo off
echo Restarting the L4D2 server...
ssh l4d2-vps "sudo l4d2-restart-now 'Windows shortcut'"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Restart complete.) else (echo Restart failed with SSH exit code %result%.)
pause
exit /b %result%
