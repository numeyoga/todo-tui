@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%.."
set "ESCRIPT_PATH=%PROJECT_DIR%\todo"

if exist "%ESCRIPT_PATH%" (
    where escript.exe >nul 2>nul
    if %errorlevel% equ 0 (
        escript.exe "%ESCRIPT_PATH%" %*
        exit /b %errorlevel%
    )
    where escript >nul 2>nul
    if %errorlevel% equ 0 (
        escript "%ESCRIPT_PATH%" %*
        exit /b %errorlevel%
    )
)

pushd "%PROJECT_DIR%"
mix run -e "TodoTxt.CLI.main(System.argv())" -- %*
set "EXIT_CODE=%errorlevel%"
popd
exit /b %EXIT_CODE%
