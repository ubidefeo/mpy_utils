@echo off
REM The state of this script is experimental.
REM mpinstall.sh is the recommended script for installing packages.
REM
REM MicroPython Package Installer
REM Created by: Ubi de Feo and Sebastian Romero
REM 
REM Installs a MicroPython Package to a board using mpremote.
REM 
REM This script accepts an optional argument to compile .py files to .mpy.
REM Run the script with the optional argument:
REM
REM install.bat <package_directory> [mpy] [COM_PORT]

if "%1" == "" (
    echo Usage: %0 <package_directory> [mpy] [COM_PORT]
    exit /b 1
)

REM Set variables based on arguments
set "PKGNAME=%~nx1"
set "PKGDIR=%~nx1"
set "SRCDIR=%~f1"
set "LIBDIR=lib"
set "COMPORT=%3"
if "%COMPORT%" == "" set "COMPORT=COM3"
echo %COMPORT%

exit

REM Check if mpremote is installed
where mpremote >nul 2>nul
if errorlevel 1 (
    echo mpremote could not be found. Please install it by running:
    echo pip install mpremote
    exit /b 1
)

REM Check if device is present/connectable
:device_present
    setlocal
    set "error="
    for /f "tokens=*" %%i in ('mpremote connect %COMPORT% 2^>^&1') do set "error=%%i"
    if not "%error%" == "" (
        echo %error% | find "no device found" >nul
        if not errorlevel 1 (
            endlocal & exit /b 1
        )
    )
    endlocal & exit /b 0

call :device_present
if errorlevel 1 (
    echo No device found. Please connect a device and try again.
    exit /b 1
)

REM Check if a directory exists
REM Returns 0 if directory exists, 1 if it does not
:directory_exists
    setlocal
    set "error="
    for /f "tokens=*" %%i in ('mpremote connect %COMPORT% fs ls %1 2^>^&1') do set "error=%%i"
    if not "%error%" == "" (
        echo %error% | find "OSError: [Errno 2] ENOENT" >nul
        if %errorlevel% equ 0 (
            endlocal & exit /b 1
        ) else (
            endlocal & exit /b 0
        )
    )
    endlocal & exit /b 0

REM Copies a file to the board using mpremote
REM Only produces output if an error occurs
:copy_file
    echo Copying %1 to %2
    for /f "tokens=*" %%i in ('mpremote connect %COMPORT% cp %1 %2 2^>^&1') do set "error=%%i"
    if not "%error%" == "" (
        echo Error: %error%
    )
    exit /b

REM Deletes a file from the board using mpremote
REM Only produces output if an error occurs
:delete_file
    echo Deleting %1
    for /f "tokens=*" %%i in ('mpremote connect %COMPORT% rm %1 2^>^&1') do set "error=%%i"
    if not "%error%" == "" (
        echo Error: %error%
    )
    exit /b

echo Installing %PKGNAME%

REM If directories do not exist, create them
call :directory_exists "/%LIBDIR%"
if %errorlevel% neq 0 (
    echo Creating %LIBDIR% on board
    mpremote connect %COMPORT% mkdir "%LIBDIR%"
)

call :directory_exists "/%LIBDIR%/%PKGDIR%"
if %errorlevel% equ 0 (
    echo Deleting %LIBDIR%/%PKGDIR% on board
    set delete_folder=python -c "%PYTHON_HELPERS%delete_folder('/%LIBDIR%/%PKGDIR%')"
    mpremote connect %COMPORT% exec "%delete_folder%"
)
mpremote connect %COMPORT% mkdir "/%LIBDIR%/%PKGDIR%"

set "ext=py"
if "%2" == "mpy" (
    set "ext=mpy"
    echo .py files will be compiled to .mpy
)

for /f "tokens=*" %%i in ('mpremote connect %COMPORT% fs ls ":%LIBDIR%/%PKGDIR%"') do set "existing_files=%%i"

for %%f in (%SRCDIR%\*) do (
    set "filename=%%f"
    for %%i in ("%%~nf") do set "f_name=%%~ni"
    for %%i in ("%%~xf") do set "source_extension=%%~xi"
    set "destination_extension=%source_extension%"

    REM If examples are distributed within the package
    REM ensures they are copied but not compiled to .mpy
    if exist "%%~df" (
        if "%%~nxf" == "examples" (
            call :directory_exists "/%LIBDIR%/%PKGDIR%/examples"
            if %errorlevel% neq 0 (
                echo Creating %LIBDIR%/%PKGDIR%/examples on board
                mpremote connect %COMPORT% mkdir "/%LIBDIR%/%PKGDIR%/examples"
            )

            for %%e in ("%%~df\*") do (
                set "example_file=%%e"
                for %%j in ("%%~nje") do set "example_f_name=%%~nje"
                for %%j in ("%%~xje") do set "example_source_extension=%%~xje"
                set "example_destination_extension=%example_source_extension%"

                echo %existing_files% | find "%%~nje.%example_source_extension%" >nul
                if not errorlevel 1 (
                    call :delete_file ":/%LIBDIR%/%PKGDIR%/examples/%%~nje.%example_source_extension%"
                )

                if "%example_source_extension%" == ".py" (
                    echo %existing_files% | find "%%~nje.mpy" >nul
                    if not errorlevel 1 (
                        call :delete_file ":/%LIBDIR%/%PKGDIR%/examples/%%~nje.mpy"
                    )
                )

                call :copy_file %%e ":/%LIBDIR%/%PKGDIR%/examples/%%~nje.%example_destination_extension%"
            )
            goto :continue_loop
        )
    )

    if "%ext%" == "mpy" (
        if "%source_extension%" == ".py" (
            echo Compiling %SRCDIR%\%f_name%%source_extension% to %SRCDIR%\%f_name%.%ext%
            mpy-cross %SRCDIR%\%f_name%%source_extension%
            set "destination_extension=%ext%"
        )
    )

    REM Make sure previous versions of the given file are deleted.
    echo %existing_files% | find "%f_name%%source_extension%" >nul
    if not errorlevel 1 (
        call :delete_file ":/%LIBDIR%/%PKGDIR%/%f_name%%source_extension%"
    )

    REM Check if source file has a .py extension and if a .mpy file exists on the board
    if "%source_extension%" == ".py" (
        echo %existing_files% | find "%f_name%.mpy" >nul
        if not errorlevel 1 (
            call :delete_file ":/%LIBDIR%/%PKGDIR%/%f_name%.mpy"
        )
    )

    REM Copy either the .py or .mpy file to the board depending on the chosen option
    call :copy_file %SRCDIR%\%f_name%.%destination_extension% ":/%LIBDIR%/%PKGDIR%/%f_name%.%destination_extension%"
)

:continue_loop

if "%ext%" == "mpy" (
    echo cleaning up mpy files
    del %SRCDIR%\*.mpy
)

echo Done. Resetting target board ...
mpremote connect %COMPORT% reset
