# AV-17-R4 fixed-brake gate, 2026-11-10

## Verdict

PASS on Windows x86-64 with an isolated candidate. The full gate reproduced all
16 original beta1 goldens, matched beta2 same-host candidate and historical
reference values and digests, and ran the candidate brake test: 258 checks,
0 failed. The final candidate-inventory and engine-identity checks passed.
This is exact software verification of the captured no-brake states and ticks,
not physical validation or general equivalence between the two laws.

`python tools/godot/test_fixed_brake_legacy.py` also passed all 25 tests. Its
negative controls cover changed, missing and duplicated Cmq blocks, unrelated
byte changes under a refreshed current pin, the prior pin, and the historical
pin. The AV-17-R4 data is accepted only when its exact Cmq block is replaced once
to recover the previous full-file SHA-256.

## Identities and evidence

- Candidate Avanti SHA-256: `77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9`.
- Previous Avanti SHA-256: `048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd`.
- Gate SHA-256: `2191a4c8e4a03018d692d7c2dc6b1a496fa4039dd11c466501e5aa8abac8e6f7`.
- Python test SHA-256: `f0eaf0f9d1cd8eee4dc3e1b49a26e0bfdcf13406873280f2c91adab38ae7d252`.
- Engines: `4.8.beta1.official.4d10419ca` and `4.8.beta2.official.cafc17a19`; exact console and GUI hashes are in [input-identities.json](input-identities.json).
- Gate inputs and captures are retained beside this report: [overlay hashes](reference-overlays.json), [original goldens](historical-goldens.json), [matched reference](matched-reference.json) and [candidate](candidate.json).
- All seven checked gate reports and the additional candidate import report under [checks](checks/) are complete and `ok`. Both bootstrap imports reported OBJ ambient-material warnings, with no checked errors.
- The candidate copy was made using the existing propwash copy routine, excluding `.godot`, captures, `.git` and `__pycache__`. Its 1,898-entry gate inventory matched both the source-before inventory and the gate's captured inventory; see [copy-identities.json](copy-identities.json). The source-after inventory differed at `render/airplane.gd` as unrelated work continued, so this pass applies to the identified isolated copy. The manifest covers the gate's scripts, data and named inputs, not all asset bytes; the scratch copy's adjacent `assets` link points to the shared repository assets.
- HEAD observed during this work was `096f0574162408ba18b3440b6f833c4214346df8`; a concurrent mixed commit included unrelated work, so the input inventory, not that commit alone, identifies this run. A path-scoped `git diff --check 3699b237 096f0574162408ba18b3440b6f833c4214346df8 -- tools/godot/fixed_brake_legacy.py tools/godot/test_fixed_brake_legacy.py tools/godot/README.md` passed.

## Rejected shared-tree run

The first shared-tree run reproduced the goldens, matched the capture comparison,
and completed 258 brake checks, but exited 1 at `candidate inputs changed during
the comparison`. It is not a full gate pass. `shared-run-drift.json` records 16
paths observed between its initial inventory and the later source-before inventory
of the isolated copy; these belong to concurrent flag, airship and workshop work.
The gate did not identify the exact time of each path's change.

## Commands

```powershell
python tools/godot/test_fixed_brake_legacy.py
python tools/godot/run_checked.py --label fixed-brake-isolated-candidate-import --timeout 1200 --out-dir C:/DEVELOPMENT/OpenRCsimulator/tmp/avanti-pitch-20261110/legacy-gate/isolated-import-receipts -- C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta2_win64_console.exe --headless --path C:/DEVELOPMENT/OpenRCsimulator/tmp/avanti-pitch-20261110/legacy-gate/candidate-01/app --audio-driver Dummy --import
python tools/godot/fixed_brake_legacy.py --godot C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta2_win64_console.exe --historical-godot C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta1_win64_console.exe --project C:/DEVELOPMENT/OpenRCsimulator/tmp/avanti-pitch-20261110/legacy-gate/candidate-01/app --out-dir C:/DEVELOPMENT/OpenRCsimulator/tmp/avanti-pitch-20261110/legacy-gate/isolated-receipts --scratch-dir C:/DEVELOPMENT/OpenRCsimulator/tmp/avanti-pitch-20261110/legacy-gate/isolated-scratch
```
