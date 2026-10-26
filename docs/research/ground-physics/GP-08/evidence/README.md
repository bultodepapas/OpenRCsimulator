# GP-08 preserved software baseline

Captured on 2026-10-25 before GP-09/GP-14 runtime edits, from commit
`cb2924b3676b72ee49497c92fe742b0b1dcd2d9c` on Windows. The pinned engine was
`4.8.beta1.official.4d10419ca`; executable SHA-256:
`90a914f1815b31fec4959be7867b2b491a61a02b1e3cb1e251653c58b7ff855f`.
The baseline solver fingerprint was
`713c1b5e69359d903d2c62c5c6b88b1d02e6ba4f05ffa4829893e2544de6f781`.
The source receipt records import-generated `.import` changes; runtime GDScript,
aircraft JSON and documentation were unchanged during capture and exact replay.
See [source identity](source-identity.json) and the [case manifest](manifest.json).

| Retained tape | Accepted ticks | Export | Exact replay | CSV comparison |
| --- | ---: | --- | --- | --- |
| [Stik airborne](air/jensen_ugly_stik_60.orfl) | 260 | [report](stik-air-export/export.json), [CSV](stik-air-export/flight.csv) | [report](stik-air-replay/replay.json), [CSV](stik-air-replay/flight.csv) | [zero divergence](stik-air-exact-comparison.json) |
| [P-51 airborne](air/p51d_mustang_120.orfl) | 260 | [report](p51-air-export/export.json), [CSV](p51-air-export/flight.csv) | [report](p51-air-replay/replay.json), [CSV](p51-air-replay/flight.csv) | [zero divergence](p51-air-exact-comparison.json) |
| [Stik ground](ground/jensen_ugly_stik_60-ground.orfl) | 480 | [report](stik-ground-export/export.json), [CSV](stik-ground-export/flight.csv) | [report](stik-ground-replay/replay.json), [CSV](stik-ground-replay/flight.csv) | [zero divergence](stik-ground-exact-comparison.json) |
| [P-51 ground](ground/p51d_mustang_120-ground.orfl) | 480 | [report](p51-ground-export/export.json), [CSV](p51-ground-export/flight.csv) | [report](p51-ground-replay/replay.json), [CSV](p51-ground-replay/flight.csv) | [zero divergence](p51-ground-exact-comparison.json) |

All four native replay reports have `mode: exact`, `status: ok`, `complete: true`
and `solver_changed: false`. They check every recorded numeric sample byte for
byte; exported CSV comparisons additionally report no divergence. Each CSV has
the initial sample plus every accepted tick: 261 airborne or 481 ground rows.
The `.orfl` files retain aircraft, environment and checkpoint identities, commands
and markers. Reports and CSVs are retained together.

The existing six-aircraft `test_flight_log.gd` passed **3,247 checks, zero failures**;
only its Stik/P-51 tapes are retained here. See [verification](air/verification.json),
[checked report](checks/flight-log-baseline-w3blmead/report.json) and
[engine log](checks/flight-log-baseline-w3blmead/engine.log).
The [ground driver](record_ground.gd) uses existing field loading, runway placement,
session stepping and the native recorder. Its two-second tape holds gear down,
idles for 0.5 seconds, then requests 15% throttle and a small late yaw command.
See [scenario receipt](ground/scenario.json),
[checked report](checks/ground-record-baseline-9wvi2mto/report.json) and
[engine log](checks/ground-record-baseline-9wvi2mto/engine.log).
The [checked collection](checks/results.xml) has two passed invocations and no
failed or invalid invocations. Each export/replay directory also retains its
native `godot.log`. Forty-two original artifacts were copied byte-for-byte;
this README is additional. Historical absolute paths in raw reports are capture
provenance; the relative links above and in the manifest identify retained files.

## Reproduce on the frozen source

From the repository root in PowerShell, set `$Godot` to the matching console
executable. Choose fresh source/output paths. Stop if any command returns nonzero.
Exact replay requires the frozen source and engine; the current changed solver
must not be substituted or used to overwrite these baselines.

```powershell
$Repo = (Get-Location).Path
$Godot = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
$Source = Join-Path $Repo 'tmp/gp08-repro-source'
$Out = Join-Path $Repo 'tmp/gp08-repro-evidence'
$Evidence = Join-Path $Repo 'docs/research/ground-physics/GP-08/evidence'
git worktree add --detach $Source cb2924b3676b72ee49497c92fe742b0b1dcd2d9c
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label import --timeout 900 -- $Godot --headless --path "$Source/app" --audio-driver Dummy --import
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label flight-log-baseline --timeout 180 --require-text '0 failures' -- $Godot --headless --path "$Source/app" --audio-driver Dummy --script res://tests/test_flight_log.gd -- "--out=$Out/air"
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label ground-record-baseline --timeout 120 --require-text 'complete=true' -- $Godot --headless --path "$Source/app" --audio-driver Dummy --script "$Evidence/record_ground.gd" -- "--out=$Out/ground"
$Cases = @{
  'stik-air' = 'air/jensen_ugly_stik_60.orfl'
  'p51-air' = 'air/p51d_mustang_120.orfl'
  'stik-ground' = 'ground/jensen_ugly_stik_60-ground.orfl'
  'p51-ground' = 'ground/p51d_mustang_120-ground.orfl'
}
foreach ($Case in $Cases.Keys) {
  python "$Source/tools/flight_log/flight_log.py" export "$Out/$($Cases[$Case])" --godot $Godot --out "$Out/$Case-export"
  python "$Source/tools/flight_log/flight_log.py" replay "$Out/$($Cases[$Case])" --godot $Godot --out "$Out/$Case-replay"
  python "$Source/tools/flight_log/flight_log.py" compare "$Out/$Case-export/flight.csv" "$Out/$Case-replay/flight.csv" --out "$Out/$Case-exact-comparison.json"
}
python "$Source/tools/godot/summarize.py" "$Out/checks" --junit "$Out/checks/results.xml"
```

Regenerated files can differ in timestamps, paths and timing diagnostics. Require
the same engine/source fingerprint, complete exact replay and zero numerical
divergence. To replay the retained tapes directly, use `$Evidence` instead of
`$Out` for the input tape paths and keep all new outputs in `$Out`.

These short tapes establish observed numerical replay and recorder preservation
on this source/engine/platform. They do not establish measured RC physics,
takeoff/landing quality, damaged-flight acceptance, performance, rendered quality,
cross-platform determinism or human pilot approval. No rendered application,
benchmark or additional baseline unit suite was run for this receipt. See the
[flight logging contract](../../../../FLIGHT-LOGGING.md) for candidate comparisons.
