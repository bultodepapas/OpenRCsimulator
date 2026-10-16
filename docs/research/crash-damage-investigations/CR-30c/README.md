# CR-30c — active-flight economics checkpoint

2026-10-16. An active-flight checkpoint now preserves the accident ledger together with the exact physics checkpoint. Restoring a nonterminal prop strike, explicit inspection or selected repair keeps its original incident identity, frozen prices, receipts and report. Duplicate events and inspection IDs remain idempotent after restore.

## Contract and integration

`app/economy/checkpoint.gd` validates `openrc-economics-checkpoint v1`. `Main.checkpoint()` adds the `openrc-flight-economics-checkpoint v1` envelope only when an active incident has damage. Healthy checkpoints retain their existing visual/sky/water format. The inner native ledger is bounded to 256 KiB, 128 journal entries and 16 inspection/repair records; inspection and repair histories each retain their 64 KiB limit. Native integers and packed float64 arrays survive `var_to_bytes` / `bytes_to_var`; JSON is not a checkpoint transport.

Before live mutation, restore checks the envelope digest, exact physics tick, aircraft/source identity, frozen catalog and recipe hashes, contact bindings, ordered events and receipts, final component decisions, salvage restrictions, repair provenance and supported-rest timer. Changing a catalog requires a fresh incident; a historical archived report remains viewable. SHA-256 detects changed payloads, not fraudulent inspection evidence or an untrusted client's authorship.

Economics preflight precedes the existing physics-owner restore. On owner failure neither physics nor economics is committed. On success, the ledger and two-second supported-rest dwell are restored, then the existing visual restore runs. A later visual failure retains the established partial-restore contract and explicitly reports `physics_restored` and `economics_restored`; this is not a new whole-world transaction. Synchronous reset/contact callbacks are suppressed only while the paired owner restore runs. Report calculation and disk writes remain outside accepted-tick callbacks.

Legacy physics-only checkpoints retain their existing behavior: known prop latches can be reported once, while an active contact or strike without economic history carries an incomplete-history caveat. No historical impact is invented from a currently active hull ID.

## Deliberate limits

Terminal crash checkpoints are refused by this economics envelope. The existing flight-owner restore clears terminal crash state; resuming its accident ledger alone would misrepresent the aircraft's state. Terminal reports remain view-only archives until CR-37 supplies paired damaged-flight state. This change does not implement full incident replay, physical inspection, automatic structural/thermal damage or workshop inventory transactions.

Restoring an earlier active checkpoint rewinds its live ledger, including any later crash. The existing single latest-report file is not a branch-history archive and can be replaced when the restored branch is next saved. Keeping multiple alternative accident histories requires a separate archive contract.

## Verification

Godot 4.7.2 headless tests exercise the real `Main` and `FlightSession` path as well as detached ledgers. The checkpoint suite passes 63 checks covering exact physical/report preservation; repeated contacts, inspections and selected repairs; repaired-material/labor provenance; catalog/recipe/binding changes; tampering, owner rejection, clock/order errors, erased restrictions, zeroed or removed decisions, nonfinite/object/cyclic inputs, journal overflow, legacy history and supported-rest timing. Selected repair provenance is recalculated against the frozen recipe book, and whole-aircraft disposition requires matching full-inspection evidence. Adjacent economics, large-report, visual, sky and water suites bring the focused run to 615 Godot checks, plus 26 Python tests and both generator freshness checks, all passing. Commands and hashes are recorded in [verification-2026-10-16.json](verification-2026-10-16.json).

Run from the repository root:

```powershell
& '.tools/Godot_v4.7.2-stable_win64_console.exe' --headless --path app --script 'res://tests/test_economy_checkpoint.gd'
python research/crash-economics/build_catalog.py --check
python research/crash-economics/build_runtime.py --check
python research/crash-economics/test_runtime_data.py
```

These checks establish software behavior, not real-airframe crash thresholds or pilot acceptance. The [active plan](../../../plans/crash-damage-economics.md) retains those gates.
