param([string]$Godot = '')
$ErrorActionPreference = 'Stop'
$Repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Godot) {
    $Godot = Join-Path $Repository '.tools/Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Pinned Godot 4.7.2 is required. See docs/TOOLS.md, or pass -Godot <path>.'
}
& $Godot --path (Join-Path $Repository 'app') --script res://tools/inspect_hx700.gd
exit $LASTEXITCODE
