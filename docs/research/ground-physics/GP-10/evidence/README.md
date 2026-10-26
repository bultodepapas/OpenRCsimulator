# GP-10 baseline and candidate replay evidence

Source base: `b85ce1047a3e7798ab22b330675fc0c9e4bce912`. The baseline was captured
from a clean main tree before GP-10 edits. The candidate used an isolated copy
of that commit plus the eight recorded GP runtime files and material metadata;
concurrent main wind edits were excluded. Exact UTC capture times, source/config
hashes and engine identity are retained in the [manifest](manifest.json),
[baseline receipts](baseline/manifest.json) and [candidate report](candidate/report.json).

Baseline solver:
`a47d31c6aa5cb73bf94feb4deb4130396a0a5d27863bc45cc4e2791dd45cc18d`.
Final candidate solver:
`588f3d32eca3221ee756ed2197c5765d4a992a3165268e738b2ed03501bd20f9`.
Engine: Windows Godot `4.8.beta1.official.4d10419ca`, executable SHA-256
`90a914f1815b31fec4959be7867b2b491a61a02b1e3cb1e251653c58b7ff855f`.

| Tape | Rows | Baseline exact replay | Final candidate | Native sample comparison |
| --- | ---: | --- | --- | --- |
| [Stik airborne](baseline/air/jensen_ugly_stik_60.orfl) | 261 | [report](baseline/stik-air-replay/replay.json) | [report](candidate/stik-air/replay.json), [CSV](candidate/stik-air/flight.csv) | [all bytes equal](candidate/stik-air-numeric-preservation.json), [CSV comparison](candidate/stik-air-comparison.json) |
| [P-51 airborne](baseline/air/p51d_mustang_120.orfl) | 261 | [report](baseline/p51-air-replay/replay.json) | [report](candidate/p51-air/replay.json), [CSV](candidate/p51-air/flight.csv) | [all bytes equal](candidate/p51-air-numeric-preservation.json), [CSV comparison](candidate/p51-air-comparison.json) |
| [Stik ground](baseline/ground/jensen_ugly_stik_60-ground.orfl) | 481 | [report](baseline/stik-ground-replay/replay.json) | [report](candidate/stik-ground/replay.json), [CSV](candidate/stik-ground/flight.csv) | [all bytes equal](candidate/stik-ground-numeric-preservation.json), [CSV comparison](candidate/stik-ground-comparison.json) |
| [P-51 ground](baseline/ground/p51d_mustang_120-ground.orfl) | 481 | [report](baseline/p51-ground-replay/replay.json) | [report](candidate/p51-ground/replay.json), [CSV](candidate/p51-ground/flight.csv) | [all bytes equal](candidate/p51-ground-numeric-preservation.json), [CSV comparison](candidate/p51-ground-comparison.json) |

All baseline replay reports have `complete: true`, `solver_changed: false` and
`status: ok`. All final candidate reports have `complete: true`,
`solver_changed: true` and `status: ok`; every CSV comparison has no divergence.
The existing [native comparator](candidate/check_numeric_preservation.gd) reuses
the flight-log APIs to compare body state, loads, inputs, auxiliary/continuous
state, modes, air data and mass arrays byte for byte at all **1,484 samples**.
This supplements finite-precision CSV comparison without labeling a changed
source experiment as historical exact replay.

The focused [air driver](baseline/record_air.gd) reuses the existing flight-log
test helpers for only Stik and P-51: [1,082 checks, zero failures](baseline/air/verification.json).
The retained [ground driver](baseline/record_ground.gd) records two seconds of
idle, low throttle and small steering input with gear down; see its
[scenario receipt](baseline/ground/scenario.json). Checked collections passed
[two baseline invocations](baseline/checks/results.xml) and
[four native candidate invocations](candidate/checks/results.xml).

Final candidate source hashes remained unchanged throughout replay. It includes
the long field-ID compatibility fix: normal IDs retain `field:<id>` and long IDs
use the separate `field_sha256:<digest>` namespace. Final `ground_surfaces.gd`
SHA-256 is `0977473117cd1381a911b39f3f8094008be2e6b188412f890ff746177f43b73e`.
Aircraft, field and wheel-profile source bytes match the baseline. The surface
JSON adds explicit material identity/provenance; every existing coefficient
quantity, unit, kind and source remains unchanged. These deltas are recorded in
[candidate source identity](candidate/source-identity-before.json).

Nine byte-preserved [source snapshots](candidate/source/) reconstruct the final
isolated candidate independently of temporary worktrees. The manifest binds
87 copied payload files, approximately 5.22 MiB, excluding corruption fixtures,
earlier candidate receipts and unrelated aircraft. Raw historical absolute
paths in reports remain provenance; local manifests and links identify the
retained files. Local attributes preserve captured bytes across Git checkouts.

## Repeat the candidate comparison

From the repository root in PowerShell, set `$Godot` to the matching console
executable and choose fresh source/output paths. Stop on any nonzero exit.

```powershell
$Repo = (Get-Location).Path
$Godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$Evidence = (Resolve-Path 'docs/research/ground-physics/GP-10/evidence').Path
$Source = Join-Path $Repo 'tmp/gp10-reproduce-source'
$Out = Join-Path $Repo 'tmp/gp10-reproduce-output'
$Manifest = Get-Content -Raw "$Evidence/manifest.json" | ConvertFrom-Json
git worktree add --detach $Source b85ce1047a3e7798ab22b330675fc0c9e4bce912
foreach ($Snapshot in $Manifest.candidate_source_snapshots) {
  $Target = Join-Path $Source $Snapshot.source_path
  New-Item -ItemType Directory -Path (Split-Path -Parent $Target) -Force | Out-Null
  Copy-Item -LiteralPath "$Evidence/$($Snapshot.path)" -Destination $Target
}
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label import --timeout 900 -- $Godot --headless --path "$Source/app" --audio-driver Dummy --import
$Models = @{
  'stik-air' = 'jensen_ugly_stik_60.json'; 'stik-ground' = 'jensen_ugly_stik_60.json'
  'p51-air' = 'p51d_mustang_120.json'; 'p51-ground' = 'p51d_mustang_120.json'
}
$Cases = (Get-Content -Raw "$Evidence/baseline/manifest.json" | ConvertFrom-Json).cases
foreach ($Case in $Cases) {
  $Name = $Case.case
  $Tape = "$Evidence/baseline/$($Case.orfl)"
  $Aircraft = "$Source/app/data/aircraft/$($Models[$Name])"
  python "$Source/tools/flight_log/flight_log.py" replay $Tape --godot $Godot --candidate $Aircraft --out "$Out/$Name"
  python "$Source/tools/flight_log/flight_log.py" compare "$Evidence/baseline/$($Case.export_csv)" "$Out/$Name/flight.csv" --out "$Out/$Name-comparison.json"
  python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label "$Name-native" --timeout 120 --require-text 'complete=true' -- $Godot --headless --path "$Source/app" --audio-driver Dummy --script "$Evidence/candidate/check_numeric_preservation.gd" -- "--log=$Tape" "--candidate=$Aircraft" "--report=$Out/$Name-native.json"
}
```

Baseline exact replay uses a clean worktree at the pinned commit, without the
candidate source overlay and without `--candidate`. See the
[flight logging contract](../../../../FLIGHT-LOGGING.md). Source hashes and both
fingerprints must match before attributing a rerun to this evidence.

These four short scenarios establish the captured numerical preservation only.
They do not cover every new geometry/material query, replace the separately
owned integration checks, or establish physical validation, full-fleet behavior,
performance, rendered quality or 1920×1080 acceptance. The inspected regression
[inventory](baseline/test-inventory.md) distinguishes proposed checks from runs.
