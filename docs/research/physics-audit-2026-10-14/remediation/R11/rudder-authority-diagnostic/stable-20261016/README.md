# Stable Stik rudder baseline — 2026-10-16

This preserved software baseline was recorded from source commit `f1ee9e7851ef2508e65fc6d90e8dae13c3705a03` (tree `cd3ee0c185508b9d43dc727abb54bd1ee8766f52`) using Godot `4.7.2.stable.official.ed1daf0bf`. The reports identify solver SHA-256 `5d70fa999ce9a328f7d8d8f7f8434d0f81be577af2994c6a9f04193b92353fed`. The aircraft JSON Git-blob SHA-256 is `8d493a9e05fdeff059a98c83c5e99bb875703930e98eb65c71bfb3348f629838`; the Windows CRLF checkout bytes used by the reports have SHA-256 `bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723`. See [receipt.json](receipt.json) for artifact hashes and the engine executable hash. The exported reports retain their original source-workspace paths as generated.

## Gate result

The 3-second right-first rudder doublet still fails the estimated software recovery screen of `|r(3 s)| ≤ 15°/s`: the 240 Hz sample is `−15.125273°/s`, and the 480 Hz sample is `−15.200616°/s`. These are diagnostic model outputs; they do not establish a physical handling limit or a real-aircraft defect. No coefficient, threshold, or test was changed for this snapshot.

The 12-second left/right recordings are extended diagnostics only. They do not replace or pass the 3-second acceptance screen. An exact replay of the 480 Hz record at the default 240 Hz rate is correctly rejected with `Physics tick rate differs`; `scripts/replay_480.gd` selects 480 Hz, and that matched-rate exact replay passes.

## Replay and comparison checks

All four exports and their matching exact replays report `complete=true`, `solver_changed=false`, and `status=ok`. Each of the four comparison reports has `status=ok`, no first divergence, and zero maximum absolute error and RMSE for every recorded numeric comparison. The export CSV and its matching exact-replay CSV were byte-identical in each case; each CSV is stored once under `exports/`, with replay CSV duplicates omitted. The expected mismatched-rate rejection is retained separately under `replays/negative-control/`.

This proves exact software replay for the identified source snapshot. It is not physical qualification or evidence that the aircraft’s modeled handling is accurate.

## Preserved files

### Load-selector diagnostic

The separately retained [`scripts/diagnose_blend.gd`](scripts/diagnose_blend.gd) and
[`diagnose-blend.log`](diagnose-blend.log) sample the unmodified 240 Hz maneuver at
721 endpoints. They reproduce the final `r = -15.125273049996°/s` and assert that
the selected aerodynamic yaw moment equals the blend of the global and local
moments within `1e-12 N·m` at every sample. Source commit `20dc6efe` has no changes
to `app/physics/`, `app/sim/` or the Stik input relative to the recording source.

The local contribution is intermittently active from 0.591667 to 2.6375 seconds;
at 1.25, 1.75 and 2 seconds it supplies the complete aerodynamic load. At 3 seconds
the selector uses only the global oracle: its yaw moment is `0.611433 N·m`, versus
`0.836715 N·m` from the unused local law at the same state. These are endpoint
diagnostics, not RK-stage histories or a causal attribution of the recovery error.
A local-law candidate must therefore distinguish its trajectory effects from any
subsequent regeneration of the oracle's derived rate coefficients.

### Recording inventory

- `flights/`: four original `.orfl` recordings.
- `scripts/`: the recorder and 480 Hz replay wrapper used for this diagnostic.
- `exports/`: one `flight.csv` and its `export.json` report per recording.
- `replays/`: the four successful matched-rate reports plus the rejected-rate control.
- `comparisons/`: the four exact CSV comparison reports.
- `receipt.json`: SHA-256 inventory and verification summary.

