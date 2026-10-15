$ErrorActionPreference = 'Stop'
$repo = 'C:\DEVELOPMENT\OpenRCsimulator'
$shadow = Join-Path $repo 'tmp\r04-groundstart-shadow\app'
$binary = Join-Path $repo '.tools\Godot_v4.7.2-stable_win64_console.exe'
$baseline = Join-Path $repo 'tmp\physics-audit-baseline-2026-10-14\app\physics'
$evidence = Join-Path $repo 'docs\research\physics-audit-2026-10-14\remediation\R04'
$baselineAero = Join-Path $baseline 'aero.gd'
$baselineTurbine = Join-Path $baseline 'turbine.gd'
$finalAero = Join-Path $repo 'app\physics\aero.gd'
$f02Turbine = Join-Path $evidence '..\R03\f02-only-turbine.gd'
$shadowAero = Join-Path $shadow 'physics\aero.gd'
$shadowTurbine = Join-Path $shadow 'physics\turbine.gd'

$cells = @(
    @{ name = 'original-aero_original-turbine'; aero = $baselineAero; turbine = $baselineTurbine },
    @{ name = 'original-aero_f02-turbine'; aero = $baselineAero; turbine = $f02Turbine },
    @{ name = 'final-aero_original-turbine'; aero = $finalAero; turbine = $baselineTurbine },
    @{ name = 'final-aero_f02-turbine'; aero = $finalAero; turbine = $f02Turbine }
)

$identity = [ordered]@{
    purpose = 'Controlled 2x2 force-law cause isolation using the preserved original Newton solver.'
    source_snapshot = 'tmp/physics-audit-baseline-2026-10-14/app, identified by remediation/R00/baseline-identity.json'
    solver_source = 'R04 ground_start_candidate.gd; _newton is preserved from the baseline and called directly by baseline_solver_probe.gd.'
    probe = 'R04/baseline_solver_probe.gd'
    cells = @()
}

try {
    foreach ($cell in $cells) {
        Copy-Item -LiteralPath $cell.aero -Destination $shadowAero -Force
        Copy-Item -LiteralPath $cell.turbine -Destination $shadowTurbine -Force
        $identity.cells += [ordered]@{
            name = $cell.name
            aero_sha256 = (Get-FileHash -LiteralPath $cell.aero -Algorithm SHA256).Hash
            turbine_sha256 = (Get-FileHash -LiteralPath $cell.turbine -Algorithm SHA256).Hash
        }
        $log = Join-Path $evidence ("old-newton-2x2-{0}.log" -f $cell.name)
        $output = & $binary --headless --path $shadow --script res://tests/baseline_solver_probe.gd 2>&1
        $exitCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath $log -Encoding utf8
        if ($exitCode -ne 0) {
            throw "Godot probe failed for $($cell.name) with exit code $exitCode; see $log"
        }
    }
    $identity | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidence 'r04-2x2-source-identities.json') -Encoding utf8
}
finally {
    Copy-Item -LiteralPath $finalAero -Destination $shadowAero -Force
    Copy-Item -LiteralPath $f02Turbine -Destination $shadowTurbine -Force
}
