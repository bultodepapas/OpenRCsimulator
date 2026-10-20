param(
	[string]$OutputPath = "tmp/landscape-perf/botanical/exclusion-grid-probe.json"
)

$ErrorActionPreference = "Stop"
$repoPath = (Get-Location).Path
$godotPath = Join-Path $repoPath ".tools/Godot_v4.7.2-stable_win64_console.exe"
$projectPath = Join-Path $repoPath "app"
$probePath = Join-Path $repoPath "tmp/landscape-perf/botanical/botanical_grid_probe.gd"
$baselinePath = Join-Path $repoPath "tmp/landscape-perf/botanical/botanical_habitats.before.gd"
$reportPath = Join-Path $repoPath $OutputPath
$checkedRunner = Join-Path $repoPath "tools/godot/run_checked.py"
$checksPath = Join-Path $repoPath "tmp/landscape-perf/botanical/checks"

python $checkedRunner --label botanical-grid --timeout 120 --out-dir $checksPath `
	--require-text BOTANICAL_GRID_PROBE_COMPLETE -- $godotPath --headless `
	--path $projectPath --audio-driver Dummy --script $probePath -- $baselinePath $reportPath
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}
