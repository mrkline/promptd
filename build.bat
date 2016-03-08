@echo off
SETLOCAL ENABLEEXTENSIONS

REM -------------
REM I could not figure out a way to get DigitalMars' make.exe to like
REM the Unix style Makefile. If there is a way to change the Makefile
REM to allow both make.exe (by DigitalMars, comes with the D installation)
REM and make on Linux/Mac OS X to use it, please let me know.
REM -------------

REM no spaces between var name and assignment!
SET ME=%~n0
SET PARENT=%~dp0
SET BUILD_DIR=%PARENT%\build
SET DC=dmd
SET DFLAGS=-wi -g

IF /I "%1"=="/debug" GOTO LABEL_DEBUG
IF /I "%1"=="--debug" GOTO LABEL_DEBUG
IF /I "%1"=="-d" GOTO LABEL_DEBUG
IF /I "%1"=="/release" GOTO LABEL_RELEASE
IF /I "%1"=="--release" GOTO LABEL_RELEASE
IF /I "%1"=="-r" GOTO LABEL_RELEASE

GOTO LABEL_AFTER_VARIABLES
:LABEL_DEBUG
SET DFLAGS=%DFLAGS% -debug
GOTO LABEL_AFTER_VARIABLES
:LABEL_RELEASE
SET DFLAGS=%DFLAGS% -O -release

:LABEL_AFTER_VARIABLES

rmdir /s /q %BUILD_DIR%
mkdir %BUILD_DIR%

echo on

%DC% %DFLAGS% -of%BUILD_DIR%\promptoglyph-vcs.exe promptoglyph-vcs.d systempath.d help.d vcs.d time.d color.d git.d
%DC% %DFLAGS% -of%BUILD_DIR%\promptoglyph-path.exe promptoglyph-path.d systempath.d help.d

