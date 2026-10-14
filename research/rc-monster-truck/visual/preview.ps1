param(
    [string]$Godot = '',
    [ValidateSet('es', 'en')][string]$Language = 'es',
    [ValidateSet('rest', 'bump', 'droop', 'cross')][string]$Pose = 'rest',
    [switch]$HideBody,
    [switch]$ShowProxies,
    [string]$Capture = ''
)
$ErrorActionPreference = 'Stop'
$RcvRepository = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if ($Godot -eq '') {
    $Godot = Join-Path $RcvRepository '.tools/Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw 'Godot 4.7.2 is required. Supply its executable with -Godot.'
}
$RcvArguments = @(
    '--path', (Join-Path $RcvRepository 'app'),
    '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility',
    '--script', (Join-Path $PSScriptRoot 'preview.gd'),
    '--', "--lang=$Language", "--pose=$Pose"
)
if ($HideBody) { $RcvArguments += '--body=hide' }
if ($ShowProxies) { $RcvArguments += '--proxies=show' }
if ($Capture -ne '') { $RcvArguments += "--capture=$([IO.Path]::GetFullPath($Capture))" }
& $Godot @RcvArguments
exit $LASTEXITCODE
