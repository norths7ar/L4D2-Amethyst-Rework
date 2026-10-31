@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0Prepare-CampaignVPKs.ps1" %*
set "prepare_exit=%ERRORLEVEL%"
echo.
pause
exit /b %prepare_exit%
