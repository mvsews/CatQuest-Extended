@echo off
setlocal
set "HYBRID_EXE=%~dp0CatQuest-Hybrid.exe"
if not exist "%HYBRID_EXE%" set "HYBRID_EXE=%~dp0dist\CatQuest-Hybrid.exe"
if exist "%HYBRID_EXE%" (
    "%HYBRID_EXE%" %*
    exit /b %ERRORLEVEL%
)
where python >nul 2>&1
if errorlevel 1 (
    echo CatQuest Hybrid standalone client is missing.
    echo Download CatQuest-Hybrid-Windows.zip and run CatQuest-Hybrid.exe from it.
    exit /b 9009
)
python "%~dp0client\catquest_client.py" hybrid %*
exit /b %ERRORLEVEL%
