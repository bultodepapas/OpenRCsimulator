# CR-29–32 — first playable accident-cost slice

2026-10-15. Godot 4.7.2 Windows Compatibility/headless. Implements the first slice explicitly allowed by the [economics plan](../../../plans/crash-damage-economics.md#9-delivery-steps-and-acceptance). The [current crash guide](../../../CRASH-DAMAGE-PLAN.md#accident-costs-in-the-current-game) owns player behavior; [CR-28](../CR-28/README.md) owns dated prices and source limitations.

## Delivered behavior

- `research/crash-economics/build_runtime.py` generates `app/data/economy/catalog.json` from the researched catalog, cost assumptions and aircraft catalog. All nine aircraft routes are represented. Baseline Ugly Stik and reconciled 61FX have complete economic coverage; the other seven explicitly retain missing coverage. Coverage is not price certainty or physical validation.
- `app/economy/catalog.gd` checks closed keys, route/offer/product references, bounded whole cents, physical inventory allocation, duplicate/orphan coverage and contact mappings. Runtime physical identity checks apply to the requested route, so an unrelated edited aircraft cannot invalidate an unchanged Stik. Numeric JSON values normalize to integers after validation. Invalid/missing economics never blocks flight.
- `app/economy/incident.gd` observes accepted aircraft contact events, never VFX classes, debris contacts or rejected solver stages. A real prop strike selects one replacement propeller and unresolved powertrain/mount inspection. Sustained contacts and repeated notifications cannot buy the same part twice. Journal limit: 128 new events; overflow remains an explicit unresolved condition.
- `app/economy/calculator.gd` computes integer-cent replacement, quoted repair, explicit reuse credit and inspection charges. Unknown costs remain null; a full-build price comparison is separate from assessed repair-cost bounds. Unbound labor cannot be salvaged. Grouped servos use their real physical count, not logical actuator count.
- `app/ui/accident_report.gd` shows a compact continuing-flight notice and a large terminal report, with details, inspect and restart. Report UI and manual restart work with VFX disabled. Pause hides the overlay; reopening history is view-only. English/Spanish use explicit USD; amounts below $100 retain cents in the headline.
- The latest immutable report snapshot is saved outside physics callbacks to `user://last_accident.json`, bounded to 256 KiB, via a temporary file and rename. It freezes aircraft identity, catalog identity, source information, accepted evidence and calculation. Per-frame write failures are not repeatedly retried; explicit reset/exit gets one retry. It is a latest-report archive, not a campaign balance or replay log.

Physical checkpoints do not contain the economics ledger. On restoring a compatible checkpoint, the accepted prop-strike latch can establish that propeller's known cost, but the report explicitly warns that previous damage history is unavailable. Invalid checkpoints leave the active report unchanged. Restart archives the report and creates a fresh ledger with no carried charges.

## Known-answer economics

| Assessment | Expected result |
| --- | --- |
| Full configured Stik build, no reuse | 99,433 cents = **US$994.33**, an estimated assembled replacement baseline |
| Same total-loss assessment, two explicitly reusable fuselage servos | 6,798-cent credit; **US$926.35** net |
| Same total-loss assessment, four explicitly reusable servos | 13,596-cent credit; **US$858.37** net |
| Accepted APC 12×6 prop strike | **US$5.39 known parts subtotal**, complete repair total unknown pending inspection |
| Terminal structural contact without component assessment | Inspection required; no invented total loss, free repair, or servo salvage |
| Empty incomplete fleet dossier | Unknown replacement and cost bounds, never a misleading zero-dollar quote |

The full-build and salvage cases are calculator fixtures, not automatically inferred physical crash outcomes. The runtime does not currently declare the 150 km/h tree example a calibrated total loss. Matching the worked economics is software evidence only.

## Verification

The focused checks are registered in `app/test.sh` (all `test_*.gd` scripts are discovered automatically). Reproduce with the pinned Godot binary from [TOOLS](../../../TOOLS.md):

```powershell
python research/crash-economics/build_catalog.py --check
python research/crash-economics/build_runtime.py --check
python research/crash-economics/test_runtime_data.py
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_economy_catalog.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_economy_calculator.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_accident_integration.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_accident_report.gd
```

The integration fixture uses production `main.tscn` with visual effects disabled. It checks exact healthy float64 state/aux/mode equality against an economics-disabled session, then induces the existing nose-over prop strike and a later terminal hull impact. It checks deduplication, unknown inspection costs, frozen archive identity, reset, invalid/valid checkpoint behavior, missing source identity, journal bounds and corrupt saved data. The crash presentation fixtures explicitly disable economic archives to avoid overwriting player history.

| Focused check | Result |
| --- | --- |
| Research/runtime generators | Both `--check` commands pass |
| Python runtime contract | 12 tests pass |
| [Runtime catalog](logs/catalog.log) | 73 checks pass |
| [Integer-cent calculator](logs/calculator.log) | 35 checks pass |
| [Production accident integration](logs/integration.log) | 24 checks pass |
| [Report UI](logs/ui.log) | 64 checks pass |
| [Production fleet crash regression](logs/crash-regression.log) | 179 checks pass |
| [Propeller visual feedback](logs/prop-feedback.log) | 16 checks pass |
| [Controller menus and accident-card routing](logs/controller.log) | 33 checks pass |

The fleet crash fixture prints a 24-instance ObjectDB exit-leak warning; its assertions pass, but this run is not leak qualification. The entire repository test suite and packaged executable matrix were not rerun for this bounded economics change.

Fresh-clone checkout verification used an isolated shared local clone with the current task inputs applied to its disposable index. `git checkout-index --all --force` with both `core.autocrlf=true` and `false` followed by both generator freshness checks and all 12 Python tests passed. Research JSON and runtime economic JSON use LF attributes; the aircraft catalog discovery hash canonicalizes UTF-8 text to LF, while physical aircraft identities continue hashing exact bytes under the existing aircraft checkout rules. No temporary index or checkout operation touched the working repository's index.

## Native UI evidence

The [capture reproducer](../../../../research/crash-economics/capture_report.gd) uses the real runtime catalog/calculator with both propeller-inspection groups, not a synthetic complete repair price. Captures use the native Compatibility renderer on an RTX 3090 and a neutral backdrop. Each accompanying JSON records the incomplete result and measured panel/action/detail bounds. These are layout checks, not physical or pilot acceptance.

- [English, 1280×720](cr32-accident-report-en-1280x720.png) — 56 px headline, **At least US$5.39**.
- [Spanish, 1280×720](cr32-accident-report-es-1280x720.png) — **Al menos US$5,39**, translated labels and controls.
- [Expanded source/inspection details, 3840×2160, scale 1.5](cr32-accident-report-en-details-scale-1.5-3840x2160.png).

The harness checks actual bounds at 1280×720, 1920×1080 and 3840×2160; expanded content remains scrollable and action controls remain reachable. Two defects found during native review were fixed before capture: stale container minimum sizes causing a viewport-sized card and an 8 px overflow of the expanded panel at 720p/scale 1.5. Reproduce a localized capture with Godot `--path app --script ../research/crash-economics/capture_report.gd -- --lang=es --size=1280x720 --out=<absolute.png>`; use `--scale=1.5 --details-bottom` for expanded content.

## CR-30/32-R1 — settlement and bounded publication

2026-10-15 follow-up. `observe()` now only ingests accepted evidence and queues a revision. `evaluate_pending()`/`flush()` compute and publish at the frame boundary; reset/exit also evaluate pending evidence before archiving. No UI signal, pricing or catalog/archive I/O runs in the contact callback. A source-identity change quarantines observations until frame-boundary rebinding, preserving the previous report and refusing stale prices.

The journal and its deduplication set remain capped at 128 events. Separate monotone facts retain the first confirmed propeller strike, restored strike latch and water exposure, so a late costly event cannot disappear after a long scrape history. Overflow still prevents a claim of complete evidence. A lake-bank ground impact alone no longer implies water exposure. Each fact is bounded to one record, and repeated overflow notifications cannot add purchases or grow the deduplication set.

`settlement.gd` uses accepted ticks, not render time: two seconds between consecutive supported samples, linear speed at most 0.25 m/s and angular speed at most 0.10 rad/s. Wheel compression above 0.00001 m or hull contact with the ground supplies support. This is an explicit presentation policy, not a calibrated landing/damage model. Paused duplicate ticks add no time; unsafe duplicate samples, bounces and tick gaps reset the pending dwell. The settled report remains nonterminal and read-only, with no restart action or solver pause. Movement dismisses the automatic card; a manually reopened report stays under player control. Movement before frame publication cancels a stale popup and permits a fresh dwell. After a card has been shown, automatic promotion occurs once per ledger; reset/checkpoint restore starts a new ledger/detector.

| Follow-up check | Result |
| --- | --- |
| [Production integration](logs/integration-r1.log) | 42 checks pass; includes actual prop strike, supported rest, queued-popup cancellation, resumed motion, terminal impact, source reload and reset/checkpoint/archive paths |
| [Settlement policy](logs/settlement.log) | 46 checks pass; bounds, pause, duplicate notifications, discontinuities and bounce/go-around reset |
| [Report UI](logs/ui-r1.log) | 73 checks pass; includes settled read-only behavior, focus release, movement dismissal and Spanish labels |
| [Catalog](logs/catalog-r1.log) / [calculator](logs/calculator-r1.log) | 73 / 35 checks pass |
| Controller routing | 33 checks pass with the production app root |
| Research/runtime generators and Python contract | Both freshness checks pass; 12 tests pass |

The integration fixture publishes the same 960-tick evidence tape at simulated 30, 60 and 144 Hz. Amounts, bounds, lines, evidence, unresolved reasons, source/catalog fields, event tick and revision match exactly; only the intentionally unique wall-clock incident identity is excluded. Healthy state/aux/modes still match an economics-disabled session exactly. The native [Spanish settled report](cr32-settled-es-1280x720.png) shows **Al menos US$5,39** in 56 px text; its [capture manifest](cr32-settled-es-1280x720.json) verifies panel/action bounds at 1280×720, 1920×1080 and 3840×2160. Reproduce with the existing capture command plus `--settled --lang=es`.

The [benchmark script](../../../../research/crash-economics/benchmark_incident.gd) and [measured result](benchmark-r1.json) record 100 samples after ten warmups on Windows, Ryzen 9 5900X, Godot 4.7.2 headless. Ingestion timings are amortized over 64 prebuilt observations per sample; they are not worst-case individual tick latencies.

| Isolated operation | Median | p95 | Maximum sample |
| --- | ---: | ---: | ---: |
| Empty healthy observation | 2.25 µs | 2.75 µs | 3.16 µs |
| New hull contact, history has room | 31.33 µs | 42.53 µs | 45.28 µs |
| New hull contact, history full | 32.20 µs | 39.70 µs | 42.83 µs |
| Construct a synthetic 100-component report | 2.72 ms | 3.72 ms | 4.18 ms |

The benchmark excludes source loading, session snapshot copying, support geometry queries, solver, UI and disk. It does not qualify the whole 500 µs physics budget, a packaged target or physical realism. The 100-part BOM is a software workload, not a researched aircraft valuation. Run `Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/crash-economics/benchmark_incident.gd -- --out=<absolute.json>` to reproduce. This follow-up did not rerun the whole repository suite or re-record golden flights.

## Remaining gates

CR-33–38 remain open: calibrated material/joint damage, aircraft-specific gear and tree outcomes, fuel/electric thermal damage, salvage qualification, complete fleet BOMs, damaged-flight integration and target-host/pilot acceptance. The initial schema selects non-overlapping cost lines; full package/repair-recipe optimization and labor-mode UI are pending. Complete incident replay and multi-flight archive browsing are also pending. No new physical failure thresholds or golden flight recordings were introduced.
