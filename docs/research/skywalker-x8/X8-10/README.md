# X8-10: X8 verification

2026-10-25, Godot 4.8-beta1 on the development VM (no GPU; rendered checks under Xvfb). Software verification only: it shows the X8 is consistently integrated and flies plausibly, not that it matches a real X8 (X8-11).

## Existing fleet unchanged

| Check | Result |
| --- | --- |
| Golden flights | 4/4 unchanged after every kernel change |
| Byte-exact frozen references (`test_aero_flow`, `test_attached_flow`, `test_propulsion_scalar`, `test_slipstream_scalar`) | 0 differences; the tailless law is skipped there (no frozen predecessor) |
| Trims (`test_trim`, `test_trim_integrity`, `test_cruise_trim`, `test_electric_trim_reuse`, `test_launch_trim_cache`, `test_half_power_start`) | all pass |
| Schema–loader agreement (`test_schema_v2.py`) | 112 cases, 0 failures, X8 in the positive fleet |

## X8 integration

| Check | Result |
| --- | --- |
| `test_x8_flying_wing.gd` | 37/37: mix and saturation, eight fail-closed mutations, strips against the oracle, rudderless trims, glide, tolerant hull |
| `verify_skywalker_x8.gd`, `test_elevon_model_contract.gd` | 36/36, 25/25 |
| `test_aircraft_render_contract.gd` | 403/0: rendered elevon hinges equal the radio mix, saturation included |
| `test_regime_consistency.gd` | 100/0, X8 Cmq band 15 % (documented exception: 12.3 % at α 8°) |
| Contract, catalog, model manifest, crash labels and energy, economy, Workshop, runway, UI, failure, audio and trace suites (all 53 catalog-iterating scripts) | pass after the fleet-list and layout updates listed in [X8-04](../X8-04/README.md) and [LEARNINGS](../../../LEARNINGS.md) |
| Generators | X8-00 manifest, X8-02 assets/model, X8-06 physics, X8-09 costing, model manifests, customization, Workshop descriptors, economy runtime, mass/balance and schema all `--check` current |
| Running app (debug bridge, 1280×720 Xvfb) | Home → Fly → airborne start on the 6S pack at 24.8 V, trimmed level at 12.9 m/s, full roll answered, 0 engine errors or warnings, 0 leaked objects at exit |

## Flight-test card v5

[summary.md](flight-test/summary.md), [profile](flight-test/profile.md), [run.json](flight-test/run.json): 30 of 40 tests valid, no script errors; runway take-off, landing, dead-stick and go-around are skipped (no gear).

| Metric | Value | Reference |
| --- | --- | --- |
| Power-off stall | 8.8 m/s, wing drop left | 8.1–8.9 m/s estimated from CLmax and mass |
| Max level speed | 26.3 m/s | ≈28 m/s ±15 % (S05 drag, measured thrust); retail 90–100 km/h |
| Best idle glide ratio | 9.2 | 2026 flight drag 10.9 at 12 m/s |
| Full roll at start speed | 159°/s | flight-identified Clp −0.21 (strip prediction −0.45 would give about half) |
| Dutch roll ζ / spiral | 0.42 / halves in 1.4 s | NTNU 2026: ζ 0.48, spiral root −0.43 (halves in 1.6 s) |
| Spins | upright: spiral, no spin; inverted: spins (2.97 s per turn) | flying wings rarely spin upright; no X8 spin data |
| Hands off 30 s | 6° heading, 0.4 m height | — |

Rudder-dependent manoeuvres (knife edge, stall turn, snap roll) are reported but meaningless without a rudder.

## Open

Hand launch (X8-07); the strip model's roll and yaw damping against the 2026 flight set; owner flight evidence, drive measurements and EPO drop tests (X8-11); the failure catalog's logical yaw jam has no effect on a rudderless aircraft, and the Home control guide still lists the rudder keys.
