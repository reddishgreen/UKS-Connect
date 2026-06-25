@echo off
REM Simple batch file wrapper for plugin deployment
REM Usage: 
REM   deploy-plugin.bat  (will prompt for all credentials - RECOMMENDED for MFA)
REM   deploy-plugin.bat [OrgUrl] [Username] [Password]  (No MFA support)
REM   deploy-plugin.bat [OrgUrl] [ClientId] [ClientSecret] clientsecret
REM   deploy-plugin.bat [OrgUrl] oauth  (Use OAuth with MFA support)

setlocal EnableDelayedExpansion

REM Check if no parameters - run interactively
if "%~1"=="" goto :interactive

REM Check if second param is "oauth"
if /i "%~2"=="oauth" goto :oauth

REM Check if we have 3 parameters
if "%~3"=="" goto :interactive

REM Check if fourth param is "clientsecret"
if /i "%~4"=="clientsecret" goto :clientsecret

REM Default to username/password
goto :office365

:interactive
echo.
echo ========================================
echo Plugin Deployment Script
echo ========================================
echo.
echo Running in interactive mode...
echo You will be prompted for authentication method.
echo For MFA-enabled accounts, select OAuth (option 1).
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0deploy-plugin-simple.ps1"
goto :done

:oauth
echo.
echo Using OAuth authentication (supports MFA)...
echo A browser window will open for sign-in.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0deploy-plugin-simple.ps1" -OrgUrl "%~1" -UseOAuth
goto :done

:clientsecret
powershell -ExecutionPolicy Bypass -File "%~dp0deploy-plugin-simple.ps1" -OrgUrl "%~1" -ClientId "%~2" -ClientSecret "%~3" -UseClientSecret
goto :done

:office365
echo.
echo WARNING: Username/Password authentication does NOT support MFA!
echo If your account requires MFA, use: deploy-plugin.bat [OrgUrl] oauth
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0deploy-plugin-simple.ps1" -OrgUrl "%~1" -Username "%~2" -Password "%~3" -UseOffice365
goto :done

:done
if errorlevel 1 (
    echo.
    echo Deployment failed!
    pause
    exit /b 1
)

pause
