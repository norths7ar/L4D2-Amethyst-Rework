@echo off
echo Updating repository, applying content, and restarting after validation...
ssh l4d2-coreyun "sudo l4d2-update-and-restart"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Content apply complete. Check output above for repository update status.) else (echo Update or apply failed with SSH exit code %result%.)
pause
exit /b %result%
