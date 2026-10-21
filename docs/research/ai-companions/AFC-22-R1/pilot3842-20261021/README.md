# Pilot 3842 checkpoint continuation supplement (2026-10-21 UTC)

This dated supplement reruns the offline fixed-roster continuation proof against the promoted pure-score pilot (`3842cbd…`) and the merged solver qualification (`2f4f35c…`). The harness pin migration changed only `PRODUCTION_PILOT_SHA256`; the profile path, controller dependency, captured state source identity, retired-checkpoint refusal, and legacy base-pilot fallback guard remain exact.

The checked Godot 4.7.2 run passed **79 checks with zero failures**. It captured the two-agent Club/Stik fixture at tick 137 and compared 240 continuation ticks: 240 physical frames, 240 command/controller frames, and 723 ORFL rows across the player and two companions. All three streams and their events compared exactly, apart from the existing documented header provenance and observer-only footer exclusions. The report embeds the complete 434-entry source hash map; a standalone copy is retained here with the checkpoint, runner report, engine log, and expected/restored decision manifests. Their SHA-256 values are in [the receipt](receipt.json).

The exact harness used in the private run is preserved in [sources](../sources/test_fleet_checkpoint-pilot3842-private-run.gd); the pre-promotion main harness is also preserved there byte-for-byte. `sources/**` is excluded from Git end-of-line conversion. The working-tree harness now pins the promoted pilot and its only code change is that hash constant.

The full run used the isolated private integration checkout at commit `63d4c479bf1e1baf5054b17f2c61e3e57c5b9fdd`, with the main-checkout pinned Godot executable. Main-worktree profile and manager gates are recorded in the [AFC-00-R3 promotion receipt](../../AFC-00-R3/promotion.json). The main checkout’s full checkpoint run was not repeated because the promoted application identity was parity-checked against the private clone and those profile/manager gates passed.

The six raw ORFL files remain on the evidence volume; their original paths, sizes, and hashes are listed in the receipt. This remains a same-build, same-process offline proof for one calm fixed roster. It does not add a `Main`/live-session restore path, establish flight realism, or make a cross-platform replay claim. Earlier AFC-22-R1 receipts and artifacts remain unchanged.

Reproduction command from the private checkout root:

```powershell
python tools/godot/run_checked.py --out-dir D:/OpenRCsimulator-AFC-work/evidence/checkpoints/runner-pilot3842-20261021 --warnings-as-errors --timeout 180 --require-text "PASS offline fleet checkpoint continuation" -- C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://../research/ai-companions/checkpoints/test_fleet_checkpoint.gd
```