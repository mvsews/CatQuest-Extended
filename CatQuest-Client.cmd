@echo off
setlocal
python "%~dp0client\catquest_client.py" %*
exit /b %ERRORLEVEL%
