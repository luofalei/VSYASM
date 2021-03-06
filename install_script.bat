@echo OFF
setlocal enabledelayedexpansion

REM Defined cript variables
set YASMDL=http://www.tortall.net/projects/yasm/releases
set YASMVERSION=1.3.0

REM Store current directory and ensure working directory is the location of current .bat
set CALLDIR=%CD%
set SCRIPTDIR=%~dp0

REM Initialise error check value
SET ERROR=0

REM Check what architecture we are installing on
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    echo Detected 64 bit system...
    set SYSARCH=64
) else if "%PROCESSOR_ARCHITECTURE%"=="x86" (
    if "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
        echo Detected 64 bit system running 32 bit shell...
        set SYSARCH=64
    ) else (
        echo Detected 32 bit system...
        set SYSARCH=32
    )
) else (
    echo Error: Could not detect current platform architecture!"
    goto Terminate
)

REM Check if already running in an environment with VS setup
if defined VCINSTALLDIR (
    if defined VisualStudioVersion (
        echo Existing Visual Studio environment detected...
        if "%VisualStudioVersion%"=="15.0" (
            set MSVC_VER=15
            goto MSVCVarsDone
        ) else if "%VisualStudioVersion%"=="14.0" (
            set MSVC_VER=14
            goto MSVCVarsDone
        ) else if "%VisualStudioVersion%"=="12.0" (
            set MSVC_VER=12
            goto MSVCVarsDone
        ) else (
            echo Unknown Visual Studio environment detected '%VisualStudioVersion%', Creating a new one...
        )
    )
)

REM First check for a environment variable to help locate the VS installation
if defined VS140COMNTOOLS (
    if exist "%VS140COMNTOOLS%\..\..\VC\vcvarsall.bat" (
        echo Visual Studio 2015 environment detected...
        call "%VS140COMNTOOLS%\..\..\VC\vcvarsall.bat" >nul 2>&1
        set MSVC_VER=14
        goto MSVCVarsDone
    )
)
if defined VS120COMNTOOLS (
    if exist "%VS120COMNTOOLS%\..\..\VC\vcvarsall.bat" (
        echo Visual Studio 2013 environment detected...
        call "%VS120COMNTOOLS%\..\..\VC\vcvarsall.bat" >nul 2>&1
        set MSVC_VER=12
        goto MSVCVarsDone
    )
)

REM Check for default install locations based on current system architecture
if "%SYSARCH%"=="32" (
    set MSVCVARSDIR=
    set WOWNODE=
) else if "%SYSARCH%"=="64" (
    set MSVCVARSDIR=\amd64
    set WOWNODE=\WOW6432Node
) else (
    goto Terminate
)

reg.exe query "HKLM\SOFTWARE%WOWNODE%\Microsoft\VisualStudio\SxS\VS7" /v 15.0 >nul 2>&1
if not ERRORLEVEL 1 (
    echo Visual Studio 2017 installation detected...
    for /f "skip=2 tokens=2,*" %%a in ('reg.exe query "HKLM\SOFTWARE%WOWNODE%\Microsoft\VisualStudio\SxS\VS7" /v 15.0') do (set VSINSTALLDIR=%%b)
    call "!VSINSTALLDIR!VC\Auxiliary\Build\vcvars%SYSARCH%.bat" >nul 2>&1
    set MSVC_VER=15
    goto MSVCVarsDone
)
reg.exe query "HKLM\Software%WOWNODE%\Microsoft\VisualStudio\14.0" /v "InstallDir" >nul 2>&1
if not ERRORLEVEL 1 (
    echo Visual Studio 2015 installation detected...
    for /f "skip=2 tokens=2,*" %%a in ('reg.exe query "HKLM\Software%WOWNODE%\Microsoft\VisualStudio\14.0" /v "InstallDir"') do (set VSINSTALLDIR=%%b)
    call "!VSINSTALLDIR!\VC\bin%MSVCVARSDIR%\vcvars%SYSARCH%.bat" >nul 2>&1
    set MSVC_VER=14
    goto MSVCVarsDone
)
reg.exe query "HKLM\Software%WOWNODE%\Microsoft\VisualStudio\13.0" /v "InstallDir" >nul 2>&1
if not ERRORLEVEL 1 (
    echo Visual Studio 2013 installation detected...
    for /f "skip=2 tokens=2,*" %%a in ('reg.exe query "HKLM\Software%WOWNODE%\Microsoft\VisualStudio\13.0" /v "InstallDir"') do (set VSINSTALLDIR=%%b)
    call "!VSINSTALLDIR!\VC\bin%MSVCVARSDIR%\vcvars%SYSARCH%.bat" >nul 2>&1
    set MSVC_VER=13
    goto MSVCVarsDone
)
echo Error: Could not find valid Visual Studio installation!
goto Terminate

:MSVCVarsDone
REM Get the location of the current msbuild
powershell.exe -Command ((Get-Command msbuild.exe)[0].Path ^| Split-Path -parent) > msbuild.txt
findstr /C:"Get-Command" msbuild.txt >nul 2>&1
if not ERRORLEVEL 1 (
    echo Error: Failed to get location of msbuild!
    del /F /Q msbuild.txt >nul 2>&1
    goto Terminate
)
set /p MSBUILDDIR=<msbuild.txt
del /F /Q msbuild.txt >nul 2>&1
if "%MSVC_VER%"=="15" (
    set VCTargetsPath="..\..\..\Common7\IDE\VC\VCTargets"
) else (
    if "%MSBUILDDIR%"=="%MSBUILDDIR:amd64=%" (
        set VCTargetsPath="..\..\Microsoft.Cpp\v4.0\V%MSVC_VER%0"
    ) else (
        set VCTargetsPath="..\..\..\Microsoft.Cpp\v4.0\V%MSVC_VER%0"
    )
)

REM Convert the relative targets path to an absolute one
set CURRDIR=%CD%
pushd %MSBUILDDIR%
pushd %VCTargetsPath%
set VCTargetsPath=%CD%
popd
popd
if not "%CURRDIR%"=="%CD%" (
    echo Error: Failed to resolve VCTargetsPath!
    goto Terminate
)

REM copy the BuildCustomizations to VCTargets folder
echo Installing build customisations...
del /F /Q "%VCTargetsPath%\BuildCustomizations\yasm.*" >nul 2>&1
copy /B /Y /V "%SCRIPTDIR%\yasm.*" "%VCTargetsPath%\BuildCustomizations\" >nul 2>&1
if not exist "%VCTargetsPath%\BuildCustomizations\yasm.props" (
    echo Error: Failed to copy build customisations!
    echo    Ensure that this script is run in a shell with the necessary write privileges
    goto Terminate
)

REM Check if a yasm binary was bundled
if not exist "%SCRIPTDIR%\yasm\" (
    REM Download the latest yasm binary for windows goto Terminate
    call :DownloadYasm
) else (
    REM Use the bundled binaries
    copy /B /Y /V "%SCRIPTDIR%\yasm\yasm-%SYSARCH%.exe" "%SCRIPTDIR%\yasm.exe" >nul 2>&1
)

REM copy yasm executable to VC installation folder
echo Installing required YASM release binary...
del /F /Q "%VCINSTALLDIR%\yasm.exe" >nul 2>&1
move /Y "%SCRIPTDIR%\yasm.exe" "%VCINSTALLDIR%\" >nul 2>&1
set INSTALLED=1
if exist "%SCRIPTDIR%\yasm.exe" set INSTALLED=0
if not exist "%VCINSTALLDIR%\yasm.exe" set INSTALLED=0
if %INSTALLED% equ 0 (
    echo Error: Failed to install YASM binary!
    echo    Ensure that this script is run in a shell with the necessary write privileges
    del /F /Q "%SCRIPTDIR%\yasm.exe"  >nul 2>&1
    goto Terminate
)
echo Finished Successfully
goto Exit

:Terminate
SET ERROR=1

:Exit
cd %CALLDIR%
IF "%APPVEYOR%"=="" (
    pause
)
exit /b %ERROR%

:DownloadYasm
echo Downloading required YASM release binary...
set YASMDOWNLOAD=%YASMDL%/yasm-%YASMVERSION%-win%SYSARCH%.exe
powershell.exe -Command (New-Object Net.WebClient).DownloadFile('%YASMDOWNLOAD%', '%SCRIPTDIR%\yasm.exe') >nul 2>&1
if not exist "%SCRIPTDIR%\yasm.exe" (
    echo Error: Failed to download required YASM binary!
    echo    The following link could not be resolved "%YASMDOWNLOAD%"
    goto Terminate
)
goto :eof