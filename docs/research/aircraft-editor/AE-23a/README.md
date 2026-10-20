# AE-23a — bounded aircraft size controls

Date: 2026-10-19 (America/Bogota; runner timestamps use UTC). Godot 4.7.2 official Windows, Compatibility renderer, RTX 3090 / NVIDIA 617.42. Current behavior belongs to the [Workshop guide](../../../AIRCRAFT-WORKSHOP.md); remaining gates belong to the [AE plan](../../../plans/aircraft-editor.md).

## Delivered scope

The shared recipe bounds expand from 50–200% to **35–225%**. Tiny / Mini / Original / Large / Giant select 35/50/100/150/225%; Smaller and Larger divide/multiply by 1.1 and clamp explicitly. One action changes only size and creates one Undo entry. Loaded intermediate values retain full precision. The readout uses compiled wingspan and labels pending/invalid drafts as proposals. English and Spanish use the existing theme, scrolling inspector and compact View/Edit layout.

The baseline prescribed-RPM Stik is the current scale-capable aircraft. The compiler formulas, source aircraft, physical validator and simulation kernel are unchanged. Complete aircraft validation and the selected real-session start remain authoritative. At default settings the endpoint spans are 0.5334 m and 3.429 m. Both start airborne; neither passes the default-field runway solve. Geometric 225% is refused because the engine and wing inventory masses exceed the existing 5 kg component limit. No policy is silently substituted.

## Verification

The retained `checks/` reports record commands, engine output, exit status and diagnostics. Final passing suites cover compiler (314), experiments (95), parameter metadata (82), preview bounds (44), moving smoke preview (81), Workshop UI (113), trial (44), bundles (28), store (141), and selected starts (324, 15 frozen variants). The focused `test_workshop_sizes.gd` passes 79 checks and adds endpoint geometry/mass/wheel, persistence and UI edge-case checks; its final report is retained alongside these suites. All eight generated descriptors remain current. These are focused checks, not a claim that the entire repository test suite was run.

The size suite checks finite bounds, invalid combinations, source immutability, saved and portable variants, exact intermediate values, reciprocal stepping, endpoint no-ops, one-edit Undo/Redo, preservation of other settings, invalid text buffers and unsupported controls. Existing preview checks include the new physical endpoints; smoke checks include them at Front/Side/Top and beginning/middle/end of the illustrative pass.

Four final native captures are under `native-final/`, each with a geometry sidecar: Tiny EN 720p, Giant ES 1080p, Tiny ES 720p at 200% text, and an invalid Giant draft EN 1080p. The last shows proposed size and disabled Save/Test fly. Header/footer actions have no recorded overflow. At 200% text, the inspector scrolls and the preview uses View/Edit; all fields are not simultaneously visible. The sidecar's `visible` flag means tree visibility, not visibility after scroll clipping. This is a bounded visual review, not full accessibility, controller or platform acceptance.

## Flight recordings and timestep refinement

`baseline.orfl` contains 480 ticks at 240 Hz: stock trimmed airborne start, a roll command of 0.08 over ticks 120–239, otherwise zero roll; the other controls retain their initial values. `baseline-exact/` proves byte-exact replay. `authentic-candidates/` contains 35% and 225% frozen Workshop models run from the baseline body/internal checkpoint with candidate mass/inertia/configuration and the identical post-conditioning tape. Their full derived wheel profiles are retained in each log header. `authentic-small-exact/` and `authentic-large-exact/` verify each candidate log against its own recorded aircraft; all three replay reports have `complete=true`, `solver_changed=false`, no error and 481 rows. Candidate exact replay does **not** mean equivalence to the stock aircraft.

`summary.json` verifies exact tick/time and command-column equality for both candidate CSVs. `authentic-*-compare.json` compares trajectories against stock. Maximum position-component differences are 2.057 m (35%) and 3.096 m (225%); maximum attitude differences are 0.208 and 0.086 rad. These are two-second open-loop counterfactuals without pilot adaptation, not measured handling or physical validation.

The separate four-second refinement uses each candidate's trimmed start and a time-aligned roll pulse: +0.04 from 0.5–1 s, −0.04 from 1–1.5 s. Other inputs retain trim. Five valid policy/scale combinations complete at 240/480/960 Hz with finite state and no faults. At constant wing loading, endpoint position differences between 240 and 960 Hz are 0.007887 m at 35% and 0.001273 m at 225%; 480→960 differences are smaller than 240→480. Detailed state, minimum altitude, selected-start diagnostics and cost samples are in `accepted-refinement-final/refinement.json`.

Cost samples were taken on a shared busy host with concurrent checks and range roughly 749–1879 µs/tick across these runs. They do **not** pass or replace the 500 µs/tick performance gate. Isolated paired performance, longer maneuvers, field clearance/weather coverage, broad combinations and physical validation remain open.

## Diagnostics retained

- `diagnostics/probe.json` records an initial disposable-copy 25–400% probe. At 25%, wing area violates the existing minimum; geometric 33% also has sub-minimum component masses. At 300/400%, geometry and/or inventory limits fail. This supports choosing a bounded slice; it does not prove every intermediate combination.
- A plain raw-JSON 35% candidate was rejected because the loader reapplied the unscaled catalog wheel profile, exceeding the effective-wheel-mass fraction. Its input and failed report remain under `diagnostics/`. That path does not represent an authentic Workshop variant. The accepted recorder uses `Trial.freeze` and retains the derived model instead.
- The first probe attempted recording with physics disabled and was refused; the corrected baseline enables observation while manually stepping an unattached session. Both runner logs remain.
- An early refinement serializer converted unavailable nonfinite ground diagnostics to null. The final helper preserves them as explicit strings. A subsequent harness assertion mistakenly interpreted qualification `ok` as route availability; the final run checks `available` separately. Earlier runner reports remain; only `accepted-refinement-final/` is accepted evidence.

## Reproduce

Run the checked Godot wrapper from the repository root, with an unused output directory:

```powershell
python tools/godot/run_checked.py --label size-refinement --timeout 180 --out-dir tmp/size-checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/aircraft-editor/size_refinement.gd -- --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/new-size-refinement
python tools/godot/run_checked.py --label size-tape --timeout 120 --out-dir tmp/size-checks -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/aircraft-editor/size_flight_comparison.gd -- --baseline=C:/DEVELOPMENT/OpenRCsimulator/docs/research/aircraft-editor/AE-23a/baseline.orfl --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/new-size-recordings
```

Use the existing [flight logging commands](../../../FLIGHT-LOGGING.md) for exact replay/export and CSV comparison. Run each focused test through the same wrapper with `--script res://tests/test_workshop_sizes.gd` (or its suite name). Native captures use `research/aircraft-editor/capture_workshop.gd`, without `--headless`, plus `--size-controls`, size/language/text flags and a new absolute PNG destination. `manifest.json` pins retained artifacts and relevant source files; source hashes identify this shared working-tree snapshot, not an isolated commit.
