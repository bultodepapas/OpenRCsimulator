# R11 package-smoke probe: Windows source-copy validation

This is a clean native Windows validation of the external probe against the physical source copy `tmp/physics-audit-r11-final-scenarios-04/verified-app`. It validates the script and source-resource path, but it is **not** the exported-package gate: this run used `--path` and the source copy. The separate exported-binary run must start from an empty working directory without `--path app` and confirm its own packed-resource identities.

Command, from the repository root:

```powershell
$godot = (Resolve-Path '.tools/Godot_v4.7.2-stable_win64_console.exe').Path
$project = (Resolve-Path 'tmp/physics-audit-r11-final-scenarios-04/verified-app').Path
$probe = (Resolve-Path 'research/physics-audit-2026-10-14/remediation/r11_package_smoke.gd').Path
$out = [System.IO.Path]::GetFullPath('docs/research/physics-audit-2026-10-14/remediation/R11/package-smoke/windows-source-copy-clean')
& $godot --headless --path $project --audio-driver Dummy --script $probe -- "--out=$out" --runner=windows-physical-source-copy
```

Godot 4.7.2 stable completed with **34 checks, 0 failures**, and no script/runtime error. Both catalog entries loaded their expected IDs and exact data hashes. Each run used `dt=1/240 s`, recorded 240 explicit post-conditioning command ticks (one simulated second) plus the initial sample, and produced an ORFL accepted as complete with 241 rows and final tick 240. Each checkpoint at tick 240 restored successfully; the same explicit 60-tick continuation reproduced body, auxiliary, continuous, mode and tick values byte-for-byte, with no simulation fault.

| Catalog ID | Catalog status | Data SHA-256 | Slots (inputs / aux / continuous / modes) | Notable loaded capability |
| --- | --- | --- | --- | --- |
| `jensen-das-ugly-stik-60` | flyable | `5fe8ece91b7ebe92f304f764f0d50edc936ae5c4ab1d1c801cf20827ec1ee9b6` | 4 / 14 / 3 / 1 | three wheels; non-continuous shaft; not glow |
| `sebart-avanti-s-a200-p100rx` | experimental | `68d3fd42b28e30bf1dc210b838d945d517f062506749af14f995a5a5f39a83b6` | 6 / 16 / 4 / 1 | continuous turbine; retractable gear; three wheels |

The source solver fingerprint was `85d0b19b66d118bf4a735e253b4f2d5c0d1d73a7a35f11f6e146dfc16b207a1b`, matching the R11 final-scenarios-04 source identity. Exact replay was not attempted here. A compiled package without a source fingerprint must be analyzed against matching source; successful file inspection is not exact replay. The package run must report its actual fingerprint availability and must not claim exact replay.

Files in this directory:

- `probe.json` — command context, source/data identities, per-aircraft capabilities, log completeness and checkpoint-continuation results.
- `jensen-das-ugly-stik-60.orfl` and `sebart-avanti-s-a200-p100rx.orfl` — complete source-copy recordings; they are not exported-package recordings.

SHA-256:

| File | SHA-256 |
| --- | --- |
| `research/physics-audit-2026-10-14/remediation/r11_package_smoke.gd` | `4613749233124f705945d33f87f7873adb0677f26181540cd0592dd7666b5e14` |
| `probe.json` | `aa8ac3de3e7a9f979c5a781ad3cf85a13870acf1603abf1124a1af0943bec238` |
| `jensen-das-ugly-stik-60.orfl` | `c32c839ec6e284856dbdec000e2429755412725f6720ba227821cf26548ede9d` |
| `sebart-avanti-s-a200-p100rx.orfl` | `f2945fa575fde3789fd3f85a21b583e689dd3d2c6393d50844d484cf93bb62fa` |

The first preliminary attempt is retained under `../windows-source-copy/` with `DISQUALIFIED.txt`; all simulation checks passed, but its script emitted cleanup errors because it tried to free a `RefCounted` logger. The clean run above removed that invalid cleanup call and completed without those errors.
