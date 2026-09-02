@echo off
echo Checking map content without changing files or restarting...
ssh l4d2-vps "sudo l4d2-content-apply --check"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Check complete.) else (echo Check failed with SSH exit code %result%.)
pause
exit /b %result%
