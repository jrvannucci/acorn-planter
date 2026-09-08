:; exec sh "$(dirname "$0")/../acorn-planter/installers/install.sh" # POSIX shells take this line; the comment also swallows the CR of the CRLF line ending
@echo off
rem The generic acorn installer -- one file, every platform:
rem   Windows:     double-click this file, or run `.\GET_STARTED\install.cmd`
rem   macOS/Linux: run `sh ./GET_STARTED/install.cmd` (line 1 hands off to installers/install.sh;
rem                cmd.exe reads that same line as a label and skips it)
rem Batch files aren't subject to PowerShell's script execution policy, so
rem this launches installers\install.ps1 with the bypass already applied,
rem scoped to just this one run (it does NOT change your system's policy).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\acorn-planter\installers\install.ps1" %*
if errorlevel 1 (
    pause
    exit /b 1
)

rem `acorn` is a PowerShell function defined in your $PROFILE. This window is
rem plain cmd.exe (and install.ps1 itself just ran with -NoProfile besides),
rem so `acorn` can never work here no matter how install.cmd was launched.
rem Open a fresh, ordinary PowerShell window instead -- its profile loads
rem automatically, so `acorn` is ready immediately -- with a short welcome
rem banner, and leave it open (-NoExit) so there's an actual usable prompt
rem right after install finishes.
start "acorn" powershell -NoLogo -NoExit -Command "Write-Host ''; if (-not (Get-Command acorn -CommandType Function -ErrorAction SilentlyContinue)) { Write-Host 'ACORN is installed, but its PowerShell profile did not load. Review the installer policy guidance or run Get-ExecutionPolicy -List.' -ForegroundColor Yellow; return }; Write-Host 'acorn is installed and ready.' -ForegroundColor Green; Write-Host ''; Write-Host 'Try:'; Write-Host '  python / ipython          # the dev venv auto-activates in new shells like this one'; Write-Host '  acorn install <package>    # add packages to it'; Write-Host '  acorn venv myproject       # create another venv'; Write-Host '  acorn vscode               # open the bundled, self-contained VS Code'; Write-Host '  acorn summary              # see everything acorn has installed'; Write-Host ''; Write-Host 'Run acorn -h for the full command list.' -ForegroundColor DarkGray; Write-Host ''"
