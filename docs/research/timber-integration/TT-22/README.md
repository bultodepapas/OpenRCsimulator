# TT-22 Turbo Lumber parts, prices and crash report

2026-10-20. Scope: Turbo Lumber economics and presentation. Flight dynamics, controls, physical inventory, collision responses and crash decisions are unchanged.

## Corrections

The previous propeller-strike binding charged $16.98 for a composite propeller-and-spinner row, contradicting its own source notes. The economic dossier now separates the $7.99 EFL5962 propeller reference from the $8.99 EFL17553 spinner reference. A blade strike replaces the propeller once and requests inspection of the spinner, motor and fuselage. A spinner probe maps to the spinner inspection. It never confirms spinner replacement merely because a blade struck the ground.

The physical assembly remains unchanged. Its inventory ID is owned once by the propeller economic row; the separately priced spinner has no duplicate physical ID. Consequently, explicit total-loss spinner reuse cannot earn a salvage credit until a physical subcomponent binding exists. The calculator reports this uncertainty instead of silently crediting it.

The [official-source audit](price-audit.md) rechecks 21 Turbo Timber Evolution reference offers, package contents, availability and manufacturer revisions. New observations dated October 20 are retained alongside the October 15–16 history; current Turbo selections use the new observations. The battery remains a $69.99 proxy on backorder, and the exact older recommended battery is discontinued. The current spring listing is in stock. Old and updated landing-gear SKUs are alternatives, and the wheel pack must be counted once across its three wheels.

The partial parts value remains **$465.87**. Four wing servos and two tail servos are counted once. Complete BNF/PNP packages are excluded from that parts sum. Fuselage, combined tail, main/tail gear, wiring/lights and labor retain unpriced scope where available listings do not establish complete coverage. This is not a full aircraft value or a complete repair quotation.

## Report

Turbo Lumber terminal reports open with an affected-parts table: part, action, quantity and estimate. Known charges appear first; inspections say **Pending**, not zero. Cents remain visible in the headline. Product SKU, sold-package description, package price, observation date and source are frozen with each incident and shown separately as reference information. Saved historical composite reports retain both their original amount and their propeller-and-spinner label.

Price assumptions and unresolved coverage follow the actionable rows. Spanish and large-text layouts retain visible actions and a scrollable parts list. Other aircraft keep their existing report layout. The shared catalog adds display provenance without changing monetary arithmetic.

## Evidence and reproduction

The [manifest](manifest.json) records source hashes, retained checks and capture identities. [English report](cost-en/cost-report.png), [Spanish large-text report](cost-es-large/cost-report.png), and the [production crash report](crash/crash-cost-report.png) use the current generated catalog. Their JSON receipts preserve calculated amounts and view immutability checks.

Use the pinned Godot executable and checked runner from [TOOLS](../../../TOOLS.md). Capture directories must be new.

```powershell
python research/crash-economics/build_catalog.py --check
python research/crash-economics/build_runtime.py --check
python research/crash-economics/test_runtime_data.py
python tools/godot/run_checked.py --out-dir tmp/timber-parts/checks --label report --timeout 120 --warnings-as-errors -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_accident_report.gd
python tools/godot/run_checked.py --out-dir tmp/timber-parts/checks --label capture --timeout 120 --warnings-as-errors -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/timber/visual-upgrade/review_cost.gd -- --review-out=C:/new/timber-cost --locale=en --viewport=1600x1000
python tools/godot/run_checked.py --out-dir tmp/timber-parts/checks --label crash --timeout 240 --warnings-as-errors -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/timber/visual-upgrade/review_flight.gd -- --aircraft=turbo-lumber-evolution --quick-flight --scenery=off --start=airborne --review-case=crash --review-crash-speed=38 --review-cost-report --review-out=C:/new/timber-crash-cost
```

For Spanish large text, use `--locale=es --viewport=1280x720 --text-scale=2`; the product caps effective text scale at 1.5. The flight fixture supplies a fixed input tape, retains the production accepted-contact observer, and checks that showing the final report changes neither its ledger nor the physics snapshot.

Regeneration required refreshing GP Extra's expected source hash because concurrent source edits had changed its bytes. Its priced physical signature was exactly unchanged; no GP price, part or mapping changed. The shared customization registry was regenerated from its current authored sources to resolve stale presentation hashes before native verification; no authored smoke or customization settings were changed for this task.
