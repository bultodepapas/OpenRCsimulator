# GP-08 candidate numerical preservation

On 2026-10-25, the isolated GP-09/GP-14 candidate replayed the four frozen
[baseline tapes](../README.md), using the same aircraft JSON, initial checkpoint
and post-conditioning input/intervention tape. All official candidate reports
have `status: ok`, `complete: true`, and `solver_changed: true`.

Baseline solver:
`713c1b5e69359d903d2c62c5c6b88b1d02e6ba4f05ffa4829893e2544de6f781`.
Candidate solver:
`1a667bd1f63393d8e5b082adc934149c85e57fb12254efff72c4943f8fee605f`.
The same pinned Godot `4.8.beta1.official.4d10419ca` executable was used.

| Case | Rows | Official candidate | CSV comparison | Native numeric bytes |
| --- | ---: | --- | --- | --- |
| Stik airborne | 261 | [report](stik-air/replay.json), [CSV](stik-air/flight.csv) | [zero divergence](stik-air-comparison.json) | [all equal](stik-air-numeric-preservation.json) |
| P-51 airborne | 261 | [report](p51-air/replay.json), [CSV](p51-air/flight.csv) | [zero divergence](p51-air-comparison.json) | [all equal](p51-air-numeric-preservation.json) |
| Stik ground | 481 | [report](stik-ground/replay.json), [CSV](stik-ground/flight.csv) | [zero divergence](stik-ground-comparison.json) | [all equal](stik-ground-numeric-preservation.json) |
| P-51 ground | 481 | [report](p51-ground/replay.json), [CSV](p51-ground/flight.csv) | [zero divergence](p51-ground-comparison.json) | [all equal](p51-ground-numeric-preservation.json) |

Candidate mode deliberately omits historical exact-replay verification. CSV
equality also has finite decimal precision. The supplemental
[preservation check](check_numeric_preservation.gd) therefore uses the existing
`CLI.prepare_replay`, `Log._sample` and `CLI.disagreement` APIs to compare every
native numeric array byte, including the initial sample: body state, loads,
inputs, auxiliary state, continuous state, modes, air data and mass properties.
All four checks passed through the checked runner; see
[collection results](checks/results.xml). Native official logs remain beside
each replay report.

The [aggregate report](report.json) includes tape identities, aircraft source
hashes, engine hash and hashes of all seven modified runtime files. The source
base was `cb2924b3676b72ee49497c92fe742b0b1dcd2d9c`, with those explicitly listed
modifications. [Before](source-identity-before.json) and
[after](source-identity-after.json) receipts confirm those files did not change
during the runs. Statistics sources are included separately because the solver
fingerprint covers `physics/`, `sim/` and `failures/`, not statistics.

To repeat one case from the repository root in PowerShell, select the captured
candidate source and matching engine; choose a fresh output directory. Repeat
with the other tape/aircraft pairs listed in the baseline manifest. Stop if any
command returns nonzero.

```powershell
$Godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$Source = (Resolve-Path 'tmp/gp-implementation-20261025').Path
$Base = (Resolve-Path 'docs/research/ground-physics/GP-08/evidence').Path
$Out = Join-Path (Get-Location) 'tmp/gp08-candidate-repeat'
$Tape = Join-Path $Base 'ground/jensen_ugly_stik_60-ground.orfl'
$Aircraft = Join-Path $Source 'app/data/aircraft/jensen_ugly_stik_60.json'
python "$Source/tools/flight_log/flight_log.py" replay $Tape --godot $Godot --candidate $Aircraft --out "$Out/stik-ground"
python "$Source/tools/flight_log/flight_log.py" compare "$Base/stik-ground-export/flight.csv" "$Out/stik-ground/flight.csv" --out "$Out/stik-ground-comparison.json"
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label stik-ground-numeric-preservation --timeout 120 --require-text 'complete=true' -- $Godot --headless --path "$Source/app" --audio-driver Dummy --script "$Base/candidate/check_numeric_preservation.gd" -- "--log=$Tape" "--candidate=$Aircraft" "--report=$Out/stik-ground-numeric-preservation.json"
```

Check the recorded source hashes before attributing a rerun to this candidate.
These are changed-source experiments with byte-equal numeric samples on four
short scenarios. They do not certify historical exact replay on a changed
solver, physical realism, new accident classifications, performance or rendered
quality. No application or runtime source was modified by these checks.
