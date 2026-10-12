# TT-06 — catalog preview entry and the shared test sweep

2026-10-12 · **Status: complete (software checks); owner sign-off of the shared edits pending.** Owning plan: [Timber integration](../../../TIMBER-INTEGRATION-PLAN.md). Guide: [asset README](../../../../assets/aircraft/turbo-lumber-evolution/README.md).

## Change

| File | Change |
| --- | --- |
| `app/app_state/aircraft_catalog.gd` | Fifth entry `turbo-lumber-evolution` (name "Turbo Lumber Evolution", Spanish "Turbo Tronco Evolución" through `es.po`: the fictional name the owner chose on 2026-10-12 so the product carries no manufacturer trademark; PREVIEW, `data = ""`, status note "Preview only: electric propulsion and flight data are not simulated yet."); `flyable_entries()` and `flyable_ids()` return the entries that carry data, in menu order. The entry was first registered as `eflite-turbo-timber-evolution` and renamed the same day together with the asset folders `*/aircraft/turbo-timber-evolution/` → `turbo-lumber-evolution/`; the delivery folder and the internal codename "Timber" are unchanged |
| `app/render/airplane.gd` | `TIMBER_ID`, `Timber` preload; `build()` dispatches to `timber_model.gd`; `datum()` is `(0, 0)` (the imported scene sits at D0); `apply_surfaces()` routes the Timber (and the Avanti) to their degree-based `apply_surfaces` |
| `app/i18n/es.po` | Spanish name, summary and status note |
| `app/tests/test_aircraft_catalog.gd` | Five IDs, four flyable, wrap on the last ID, adapter list with `TIMBER_ID`; a preview may carry a real propeller (`has_propeller == propeller.visible`) |
| `app/tests/test_projected_shadow.gd`, `test_world_field_lights.gd` | `TIMBER_ID` in the explicit lists (shadow footprint and night kit on the imported mesh) |
| `app/tests/test_aircraft_contract.gd`, `test_trace_metadata.gd`, `test_contact_policy.gd`, `test_aero_flow.gd`, `test_slipstream_scalar.gd`, `test_strip_induced.gd`, `test_wash_transport.gd`, `test_propulsion_scalar.gd`, `test_attached_flow.gd`, `test_aircraft_render_contract.gd`, `test_shaft_data.gd` | Iterate `flyable_entries()` / `flyable_ids()` (one line each): previews carry no data file. `test_contact_policy` compares its screened list with `flyable_ids()` |
| `app/tests/test_crash_pose.gd`, `test_crash_integration.gd`, `bench_regimes.gd`, `bench_wind.gd` | Flyable IDs only: `main.gd` refuses a preview flight scene with exit 1 unless `--scripted` |
| `app/tests/test_landscape_population.gd` | The parked fleet matches the **flyable** catalog (a preview has no baked snapshot; TT-13b decides) |
| `app/tests/test_crash_wreck.gd` | Builds every catalog model (the Timber included); for a preview, C4 requires detached groups but not an immediate release: the imported airframe is one mesh (wing, fuselage, tail), so there is no wing/engine group with zero delay. Splitting it for the crash twin is TT-13's decision |
| `app/tests/test_ui_aircraft.gd` | Counter 1 of 5; after the Avanti the Timber card shows "Preview", Fly disabled, no limits label, backdrop shows the model, arrows wrap; Spanish counter "Avión 4 de 5" |
| `app/aircraft/timber_model.gd` | Clears `scene_file_path` on the built root so `Node.duplicate()` copies the wrapped tree (the crash twin re-instantiated the GLB and lost the moved pivots) |
| `tools/scenery/place.py` | `catalog_fleet_ids()` skips PREVIEW entries, as `Catalog.flyable_ids()` does, so the generated `app/data/scenery/default.json` is unchanged and `test_scenery_loader.gd` keeps passing (scenery owner) |

Two tests not in the plan's list also enumerated the catalog: `test_landscape_population.gd` (parked fleet) and `test_crash_wreck.gd`; both are adapted as above and belong to the scenery and crash owners.

## Proof

```bash
# targeted (all exit 0): test_aircraft_catalog, test_projected_shadow, test_world_field_lights, test_landscape_population,
# test_scenery_build, test_aircraft_render_contract, test_ui_aircraft, test_crash_wreck (163 checks, 0 failed)
"$(app/get-godot.sh)" --headless --path app -- --aircraft=turbo-lumber-evolution --trace=/dev/null --t=1   # exit 1: "preview only, no flight data (use --scripted)"
"$(app/get-godot.sh)" --headless --path app -- --aircraft=turbo-lumber-evolution --scripted --frametimes=/tmp/ft.json --warmup=0 --t=1   # route scripted-fixed, 134 frames, 0 physics ticks
bash app/test.sh   # full suite, see the result line below
```

Full `app/test.sh` result (2026-10-12): the suite cannot complete on this tree for reasons outside the Timber change. The import, Python generator checks, float64 guard, parse check of every script and the tests up to `test_atmosphere_flight.gd` passed; that test fails one check ("reset recomputes a fresh trim for the extreme density") identically on a pristine `git archive HEAD` copy, so it predates this work. Every other `app/tests/test_*.gd` and the six model contracts were then run one by one: 216 passed; `test_crash_pose.gd` fails three Avanti checks on pristine HEAD too (pre-existing); `test_landing_maneuver.gd` needs 82–84 s alone on this VM, on pristine HEAD as well, so it exceeds the suite's 60 s per-script budget here (28 checks pass when run alone); `test_ui_help.gd` and `test_ui_runway.gd` failed once while a parallel session was editing `app/ui/update_notice.gd`, `app_root.gd` and `home.gd`, and pass when rerun alone; `test_scenery_loader.gd` was the one failure caused by TT-06 and is fixed by the `place.py` change above. A final run of a disposable copy of `app/test.sh` that skipped only those three tests (`test_atmosphere_flight.gd`, `test_crash_pose.gd`, `test_landing_maneuver.gd`) completed every other section with exit 0: 262 sections, the Timber identity/geometry section ("38 files, 12301268 bytes, visual revision r1-fb7586f19029: identical"), the Timber model contract ("PASS 283 checks"), the four trace smokes, the refused-aircraft route, the fixed-step hashes and the propwash/ground sections.

## Limits

The preview flies only the scripted visual circle; Fly is refused in Home and on the direct route. No physics, trace, trim, sound or ground behaviour exists for the Timber (TT-07…TT-12). The parked fleet and the crash twin keep their four-aircraft behaviour until TT-13/TT-13b. Home and Spanish strings are verified by `test_ui_aircraft.gd`; [home-timber-en.png](home-timber-en.png) and [home-timber-es.png](home-timber-es.png) (`app/tests/capture_ui.gd --screen=home --aircraft=turbo-lumber-evolution --lang=en|es`, Xvfb) show the card with "Aircraft 5 of 5" / "Avión 5 de 5", the preview note, Fly disabled and the model in the backdrop. In the field, the scripted visual circle was captured through the app's own capture route (`-- --aircraft=turbo-lumber-evolution --scripted --capture --t=2.5 --out=…`): [field-scripted-circle-closeup.png](field-scripted-circle-closeup.png) with `--inspect` (close-up camera, scenery behind); the same route from the pilot position (no `--inspect`, t = 4 s) shows the airplane as the small dot the circle's distance implies and is not kept here.
