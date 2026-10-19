param(
	[ValidatePattern('^[A-Za-z0-9._-]+$')]
	[string]$RunLabel = "fixedtrim-45s"
)

$ErrorActionPreference = "Stop"
$frameRoot = $PSScriptRoot
$runRoot = Split-Path -Parent $frameRoot
$repoRoot = (Resolve-Path (Join-Path $frameRoot "..\..\..")).Path
$engine = Join-Path $runRoot "baseline\.tools\Godot_v4.7.2-stable_win64_console.exe"
$app = Join-Path $runRoot "baseline\app"
$userData = Join-Path $frameRoot "userdata"
$frameReport = Join-Path $frameRoot ($RunLabel + ".json")
$traceReport = $frameReport + ".trace.json"

if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw "Godot console binary missing: $engine" }
if (-not (Test-Path -LiteralPath $app -PathType Container)) { throw "Frozen baseline app missing: $app" }
if ((Test-Path -LiteralPath $frameReport) -or (Test-Path -LiteralPath $traceReport)) {
	throw "Refusing to overwrite an existing run artifact for '$RunLabel'. Choose a new RunLabel."
}
New-Item -ItemType Directory -Force -Path $userData | Out-Null

$savedAppData = $env:APPDATA
$exitCode = 1
Push-Location $repoRoot
try {
	$env:APPDATA = $userData
	& $engine --path $app --audio-driver Dummy --resolution 1280x720 --max-fps 60 `
		--script (Join-Path $frameRoot "native_frame_probe.gd") -- `
		("--frametimes=" + $frameReport) --warmup=5 --t=45 --start=airborne
	$exitCode = $LASTEXITCODE
}
finally {
	if ($null -eq $savedAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue }
	else { $env:APPDATA = $savedAppData }
	Pop-Location
}
exit $exitCode
