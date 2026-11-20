# Live sync into ONE open Roblox Studio window.
#
#   powershell -ExecutionPolicy Bypass -File scripts\serve.ps1
#
# 1. Builds the place once (also writes build/Map.rbxm and the monster grids).
# 2. Runs `rojo serve serve.project.json` on port 34872.
# 3. In Studio: open releases\NightShiftSupermarket.rbxl, Plugins tab > Rojo > Connect.
#
# From then on:
#   * editing anything in src/ appears in Studio at once;
#   * after changing map/, run `lune run tools/build` (in another terminal) and the new
#     map and grids are pushed into the same Studio window.
# Stop with Ctrl+C.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$env:PATH = "$(Resolve-Path .tools -ErrorAction SilentlyContinue);$env:PATH"

if (-not (Test-Path build/Map.rbxm)) {
	lune run tools/build
	if ($LASTEXITCODE -ne 0) { exit 1 }
}
rojo serve serve.project.json
