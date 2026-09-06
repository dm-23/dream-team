: << 'CMDBLOCK'
@echo off
REM Cross-platform polyglot launcher for Dream Team hook scripts.
REM On Windows cmd.exe runs the batch block below, which locates a bash and
REM calls the named script. On Unix the shell treats the block as a here-doc
REM fed to the no-op ":" builtin and falls through to the shell section.
REM
REM Hook scripts are intentionally extensionless: a command containing ".sh"
REM triggers Claude Code's Windows auto-detection, which would prepend its own
REM bash invocation and double-launch the script.
REM
REM Usage: run-hook.cmd <script-name> [args...]
REM
REM Technique adapted from the superpowers plugin (MIT).

if "%~1"=="" (
    echo run-hook.cmd: missing script name >&2
    exit /b 1
)

set "HOOK_DIR=%~dp0"

if exist "C:\Program Files\Git\bin\bash.exe" (
    "C:\Program Files\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    "C:\Program Files (x86)\Git\bin\bash.exe" "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

where bash >nul 2>nul
if %ERRORLEVEL% equ 0 (
    bash "%HOOK_DIR%%~1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %ERRORLEVEL%
)

REM No bash available: exit quietly. Sticky team mode is then unavailable,
REM but the session keeps working normally.
exit /b 0
CMDBLOCK

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
exec bash "${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
