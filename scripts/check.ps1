# Windows version of check.sh: format check, tests, place build and map checks.
# Uses the tools in .tools/ (or whatever rojo/lune/stylua are on PATH).
#   powershell -ExecutionPolicy Bypass -File scripts\check.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$env:PATH = "$(Resolve-Path .tools -ErrorAction SilentlyContinue);$env:PATH"

Write-Host '== Format (stylua)'
stylua --check src tests map tools
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host '== Tests (lune)'
lune run tests/run
$testsFailed = $LASTEXITCODE -ne 0

Write-Host '== Place build and map checks (rojo + lune)'
lune run tools/build
if ($LASTEXITCODE -ne 0) { exit 1 }
if ($testsFailed) { exit 1 }
