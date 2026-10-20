# AE-23b — 10–500% virtual aircraft sizes

**Date:** 2026-10-19, America/Bogota. **Status:** implemented game-size slice; physical, sustained-flight, wider field/configuration and isolated performance acceptance remain open. Windows, Godot 4.7.2 stable `ed1daf0bf`, Compatibility renderer, RTX 3090 / NVIDIA 617.42. The shared working tree was changing; [manifest.json](manifest.json) records exact source/artifact hashes rather than claiming a clean release revision.

The Workshop now offers Tiny 10%, Mini 50%, Original 100%, Large 200%, Giant 500%, intermediate choices, reciprocal smaller/larger steps, exact saved values and Undo/Redo. The baseline Stik spans 0.1524–7.62 m. Preview and smoke framing share the new limits. Current behavior belongs in the [Workshop guide](../../../AIRCRAFT-WORKSHOP.md); [AE-23a](../AE-23a/README.md) remains the historical 35–225% record.

## Physics and validation boundary

The existing compiler applies similarity transforms to dimensions, inventory, inertia, gear, collision hull and prescribed-RPM propulsion. Dry mass follows s² or s³; liquid volume follows s³. At default weight/tank settings, constant-wing-loading total mass is 0.027437 kg at 10% and 86.962653 kg at 500%; geometric total mass is 0.002879 kg and 359.832767 kg. These are virtual extrapolations, not validated real hardware. Aerodynamic coefficients retain their source estimates; Reynolds-number and hardware changes are not modelled.

Every base first passes the ordinary strict aircraft validator. Actual compiler transforms emit private dimensional bound factors, which are removed before serialization. An explicit loader allowlist accepts those factors only for transformed dimensional quantities. Contract structure, provenance, finite/type checks, control angles, coefficients and cross-field physical consistency remain checked. The ordinary file/import validator keeps its original bounds and rejects the oversized/undersized resolved raw candidates. The context is an internal compiler API, not an untrusted-data authorization mechanism. No simulation-kernel branch or generated aircraft-data edit was added.

The optional recipe `size_model: virtual_similarity_v1` selects compiler `openrc-aircraft-workshop-v1-virtual-size-1`; UI size actions select it explicitly. Out-of-legacy-range scales also select it. Old recipes without that field in 35–225% keep compiler-2 and exact normalized inputs. All 12 legacy before/after results, including refusals, match in [legacy-before.json](legacy-before.json) and [legacy-after.json](legacy-after.json). The new model alone scales the plausibility band with total dry-plus-liquid mass, avoiding the old giant liquid-mass mismatch. Storage validates the optional field; source-plus-recipe bundles reconstruct the virtual trial without weakening ordinary import.

## Verification

[summary.json](summary.json) indexes all checked runs, retained failures, control-tape equality, refinement and the golden comparison. Each `checks/*/report.json` records its exact command, exit status and engine-log hash.

| Gate | Accepted result |
| --- | --- |
| Virtual sizes | 78 checks: both endpoint mass policies, physical dimensions/mass, strict import refusal, unmodified source, domain/control validation, unsupported electric/finite-glow refusals, frozen starts; 10/100/500% disk and bundle round trips, malformed/future model refusal |
| Size UI / parameters / compiler / experiments | 79 / 82 / 314 / 95 checks pass; exact values, limits, Undo/Redo, pending invalid text and unsupported controls |
| Preview / smoke / Workshop UI | All pass; smoke 101 checks, endpoint framing and preview isolation |
| Trial / bundle / store / starts | 44 / 28 / 141 / 363 checks pass; starts cover 17 frozen variants |
| Ordinary aircraft / contract / fuel / electric / shaft | 88 / 2990 / 44 / 43 / 121 checks pass |
| Descriptor generation | All eight generated descriptors current |
| Golden flights | Four existing failures reproduced with identical numerical diagnostics using the pre-change loader; no golden re-recording |

The golden diagnostic injects the aircraft model derived by `fbfa008c67dd33512e7e329d353286b34cd539b5:app/physics/aircraft_data.gd` into the same session/test. Both runs fail `roll_15`, `pull_throttle`, `rudder_doublet`, and `glide_15` with byte-identical failure lines, verified in the summary. The captured old loader and diagnostic test are under [diagnostics/golden-baseline](diagnostics/golden-baseline/). This isolates the loader change; it does not establish that the whole tree passes its goldens.

Retained intermediate failures include an incomplete draft-test parse, an incorrect test expectation that liquid followed dry mass, the old runway expectation that every non-unit endpoint must refuse, and storage's missing `size_model` allowlist entry. The persistence draft also initially omitted mandatory stored recipe fields; it now uses complete defaults. The final runs correct these issues. Disposable relaxed-bound probes are diagnostic only and were never integrated. Archived diagnostic scripts retain their original scratch paths.

## Flight evidence

The old AE-23a baseline refused exact replay after intervening shared-tree changes; [diagnostics/baseline-before](diagnostics/baseline-before/) retains that refusal. A fresh [baseline.orfl](baseline.orfl) was recorded and replayed exactly **before** the production loader change: [baseline-exact/replay.json](baseline-exact/replay.json), complete, 480 ticks / 481 rows, `solver_changed=false`.

The final [comparison recording](recordings-final/comparison-recording.json) freezes authentic Workshop models at 10/100/500% and reuses the baseline checkpoint and 240 Hz post-conditioning input tape for two seconds. Candidate configuration, mass and inertia replace the baseline model values. The bounded roll pulse begins at tick 121. All candidates complete 480 ticks without faults. Recorded solver hashes differ from the original baseline (`solver_changed=true`), so these are candidate comparisons, not cross-source exact-equivalence claims.

Each candidate passes its own exact replay with `solver_changed=false`: [10%](exact-final-10/replay.json), [100%](exact-final-100/replay.json), [500%](exact-final-500/replay.json). Their CSVs have identical tick/time and four command columns to the baseline across 481 rows; evolving auxiliary state is not an input tape. The [100% comparison](compare-final-100.json) has zero position, velocity, quaternion-angle and angular-rate differences. [10%](compare-final-10.json) and [500%](compare-final-500.json) retain the measured response differences, without claiming physical validation or pilot adaptation.

Independent trimmed four-second trials at 240/480/960 Hz cover both policies at 10/100/500%. All 18 runs complete with finite state and no fault; [raw refinement](refinement-final/refinement.json) retains states, timings and start diagnostics.

| Scale / dry-mass policy | Final position difference, 240 vs 960 Hz | Runway / airborne |
| --- | --- | --- |
| 10% / constant wing loading | 0.019747 m | Available / available |
| 100% / constant wing loading | 0.002856 m | Available / available |
| 500% / constant wing loading | 0.000582 m | Refused / available |
| 10% / geometric | 0.007584 m | Refused / available |
| 100% / geometric | 0.002856 m | Available / available |
| 500% / geometric | 0.001147 m | Refused / available |

Runway refusals report an unresolved support pose / bounded line search; they never silently switch start mode. Timings were collected on a shared busy host and do not pass the isolated 500 µs runtime budget. Short airborne tapes do not qualify landing impacts, extreme maneuvers, long-duration behavior, every size/weight/power combination or every field.

## Native inspection

Reviewed [10% EN 1280×720](native/tiny-10-en720.png), [500% ES 1920×1080](native/giant-500-es1080.png), and [10% ES 1280×720 at 200% text](native/tiny-10-es720-large-text.png), with adjacent geometry JSON. Size shortcuts/readout and pinned actions fit. At 200% text the compact edit view scrolls; **View** restores inspection. The tiny mesh remains visibly tiny, while the giant fits the inspection camera. This is bounded layout inspection, not full accessibility or hardware acceptance.

## Reproduction

From the repository root, use unique new output directories. The checked runner detects script errors even when Godot exits zero. Other suite commands are recorded verbatim in their retained reports.

```powershell
python tools/godot/run_checked.py --label virtual-size --timeout 120 --out-dir tmp/size-checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_workshop_virtual_size.gd
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/aircraft-editor/size_refinement.gd -- --extreme --out=../tmp/size-refinement-new
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/aircraft-editor/size_flight_comparison.gd -- --extreme --baseline=../docs/research/aircraft-editor/AE-23b/baseline.orfl --out=../tmp/size-recordings-new
python tools/flight_log/flight_log.py replay docs/research/aircraft-editor/AE-23b/recordings-final/size-10.orfl --out tmp/size-exact-new
python research/aircraft-editor/build_descriptors.py --check
```

Exact replay requires the recorded solver identity. Use the original source snapshot if later changes invalidate that identity; preserve the refusal rather than relabeling a new run exact. The [remaining AE-23 gates](../../../plans/aircraft-editor.md) stay open.
