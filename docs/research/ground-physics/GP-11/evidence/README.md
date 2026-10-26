# GP-11 frozen numerical foundation cohort

This is the frozen **36-file selected overlay** captured with main HEAD `241eaf0b559b6ce96b38ff8b9c471e293828f8f1`, applied to the retained GP-10 baseline. It contains the shared rotor system, ring geometry/compliance, authored normal/steering profiles, normal stage composition, frozen-pose impulse adapter, bounded prescribed steering, fixed-datum final-alpha composition, damage assessment and kernel receipt contracts. The stock `FlightSession` remains byte-identical to the GP-10 baseline: these new force/steering/impulse laws are **not installed in stock flight**.

The [final report](candidate/report.json) records **3,469 checks in 21 suites**, plus four native comparisons: **25 checked invocations, all passing**. The [final JUnit summary](candidate/checks/results-final.xml) covers all 25. The hashes of **151 files: 146 physics/sim/failures scripts and five inputs**, remain unchanged between [before](candidate/source-before.json) and [after](candidate/source-after.json). The five aircraft/field/hardware inputs and four original tapes also retain their baseline bytes. [Copy origins](retention-origins.json) identify every byte-preserved original.

The cohort excludes subsequent integration-admission work, runtime step/event policy, physical traction-row assembly, session migration and combined production brake/shaft-stop handling. It contains the pure traction QP and generic impulse-row builders, not the later aircraft row producer. Damage assessment/receipt support does not establish physical breakup or accident continuation. These are software/conservation/preservation results, not measured aircraft calibration, pilot acceptance, performance measurements or a full-app qualification.

| Original tape | Samples | Exact baseline | Changed-source candidate | Native bytes |
| --- | ---: | --- | --- | --- |
| [Stik airborne](baseline/air/jensen_ugly_stik_60.orfl) | 261 | [report](baseline/stik-air-exact/replay.json) | [report](candidate/stik-air/replay.json), [CSV](candidate/stik-air/flight.csv) | [equal](candidate/stik-air-native.json) |
| [P-51 airborne](baseline/air/p51d_mustang_120.orfl) | 261 | [report](baseline/p51-air-exact/replay.json) | [report](candidate/p51-air/replay.json), [CSV](candidate/p51-air/flight.csv) | [equal](candidate/p51-air-native.json) |
| [Stik ground](baseline/ground/jensen_ugly_stik_60-ground.orfl) | 481 | [report](baseline/stik-ground-exact/replay.json) | [report](candidate/stik-ground/replay.json), [CSV](candidate/stik-ground/flight.csv) | [equal](candidate/stik-ground-native.json) |
| [P-51 ground](baseline/ground/p51d_mustang_120-ground.orfl) | 481 | [report](baseline/p51-ground-exact/replay.json) | [report](candidate/p51-ground/replay.json), [CSV](candidate/p51-ground/flight.csv) | [equal](candidate/p51-ground-native.json) |

All four exact baseline reports have `complete=true`, `solver_changed=false`, `status=ok`. All four candidate reports have `complete=true`, `solver_changed=true`, `status=ok`. The existing [native comparator](candidate/check_numeric_preservation.gd) compares every native body/load/input/auxiliary/continuous/mode/air/mass array byte at **1,484 samples**, including initial samples. All four CSV comparisons report no divergence. This is changed-source numerical preservation, not historical exact replay under the candidate solver.

Baseline solver: `588f3d32eca3221ee756ed2197c5765d4a992a3165268e738b2ed03501bd20f9`. Candidate solver: `7c065cef2b9182b0b87e147823028de867465de23dc64691448d17da621e3e6b`. Engine: Windows Godot `4.8.beta1.official.4d10419ca`; executable SHA-256 `90a914f1815b31fec4959be7867b2b491a61a02b1e3cb1e251653c58b7ff855f`.

Raw reports/logs and the [36 source snapshots](candidate/source/) are unchanged copies. Historical absolute temporary paths inside them remain provenance; retained relative paths are authoritative. The raw final report mentions an earlier 23-invocation partial XML; that superseded XML is omitted. Only `results-final.xml` is the retained checked summary. Corrupt tape fixtures and temporary stdout are omitted. [Manifest](manifest.json) hashes retained payloads; the later [Git attribute receipt](attribute-roundtrip.json) verifies fresh-checkout preservation with `autocrlf=true`.

## Reproduce

Use the exact engine above. Reconstruct the isolated source from commit `b85ce1047a3e7798ab22b330675fc0c9e4bce912`, first applying the nine [GP-10 source snapshots](../../GP-10/evidence/manifest.json) as described in [its reproduction instructions](../../GP-10/evidence/README.md#repeat-the-candidate-comparison), then copy each file listed in `candidate/overlay.json` from `candidate/source/<path>` to that source's `<path>`. Do not overlay current main or later runtime policies. Import the reconstructed app once with the pinned engine.

From the repository root, validate retained checked reports without launching Godot:

```powershell
python tools/godot/summarize.py docs/research/ground-physics/GP-11/evidence/candidate/checks
```

For a fresh reconstructed source `$Source`, pinned console executable `$Godot`, this evidence `$Evidence`, and new output directory `$Out`, repeat a candidate case with existing tools:

```powershell
$Tape = "$Evidence/baseline/air/jensen_ugly_stik_60.orfl"
$Aircraft = "$Source/app/data/aircraft/jensen_ugly_stik_60.json"
python "$Source/tools/flight_log/flight_log.py" replay $Tape --godot $Godot --candidate $Aircraft --out "$Out/stik-air"
python "$Source/tools/flight_log/flight_log.py" compare "$Evidence/baseline/stik-air-exact/flight.csv" "$Out/stik-air/flight.csv" --out "$Out/stik-air-comparison.json"
python "$Source/tools/godot/run_checked.py" --out-dir "$Out/checks" --label stik-air-native --timeout 180 --require-text 'complete=true' -- $Godot --headless --path "$Source/app" --audio-driver Dummy --script "$Evidence/candidate/check_numeric_preservation.gd" -- "--log=$Tape" "--candidate=$Aircraft" "--report=$Out/stik-air-native.json"
```

Repeat for the other three table entries. The 21 suite names are the `checked_invocations` entries with a non-null `checks` field in `candidate/report.json`; each maps to `res://tests/test_<label>.gd` and runs through the same checked runner. Stop on every nonzero exit and keep new output directories. Replay does not re-record or modify the original tapes.
