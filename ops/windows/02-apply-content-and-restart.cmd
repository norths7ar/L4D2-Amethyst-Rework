@echo off
echo Applying map content and restarting after validation...
ssh l4d2-vps "sudo l4d2-content-apply"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Apply complete.) else (echo Apply failed with SSH exit code %result%.)
pause
exit /b %result%
