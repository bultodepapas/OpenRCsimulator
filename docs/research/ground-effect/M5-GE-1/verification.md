# M5-GE-1 verification log

2026-10-12, Godot 4.7.2-stable Linux headless on the development VM (no GPU; captures not re-run here). Each row is the suite's own summary line. Software verification; no physical validation.

## Focused suites after integration

| Suite | Result |
| --- | --- |
| `tests/test_ground_effect.gd` (new) | 47 checks, 0 failed |
| `tests/test_aero_flow.gd` (H4/H12 byte-exact oracle parity) | 10,000 + 10,001 comparisons, 0 failed |
| `tests/test_downwash_lag.gd` (D11g, Cmα̇ −3.42 measured vs −3.56 theory) | 14 checks, 0 failed |
| `tests/test_aircraft_contract.gd` (v1/v2 same derivation, unconsumed fields) | 1,940 checks, 0 failures |
| `tests/test_aircraft_data.gd` | 87 checks, 0 failed |
| `tests/test_ground_contact.gd` (air loads bit-identical at the trimmed start) | 22 checks, 0 failed |
| `tests/test_strip_induced.gd`, `test_induced_integrity.gd` | 21 and 168 checks, 0 failed |
| `tests/test_dynamics.gd`, `test_tail_downwash.gd`, `test_damping_regimes.gd` | 7, 8 and 20 checks, 0 failed |
| `tests/test_takeoff_roll.gd` | 7 checks, 0 failed (lift-off 23.69 m, 20.99 m/s; before: 22.73 m, 20.62 m/s) |
| `tests/test_landing_maneuver.gd` (240/480 Hz, east/west, refinement) | 28 checks, 0 failed |
| `tests/test_landing_variations.gd` | 9 checks, 0 failed |
| `tests/test_runway_start.gd`, `test_ground_stiction.gd` | 19 and 25 checks, 0 failed |
| `tests/test_wind_flight.gd` (same-state loads with the session's ground; wind-on runway equilibrium) | 51 checks, 0 failed (3 failed before the `GroundStart` ground fix) |
| `tests/test_golden.gd` (four air goldens) | pass, not re-recorded |
| `tests/check_math_sensitivity.py` (H7 one-ULP and branch tapes) | pass after the oracle-branch anchor update |
| `tests/test_envelope.gd`, `test_physical_envelope.gd`, `test_spin.gd`, `test_modes.gd`, `test_trim.gd`, `test_checkpoint.gd`, `test_session_guards.gd`, `test_slipstream_downwash.gd`, `test_electric_session.gd` | 15, pass, 8, 42, 14, 90, 32, 15, 86 checks, 0 failed |
| `tests/test_trace_acceptance.py` (C7-R1) | 14 tests OK |
| `tests/test_pullup_cli.py` (D8b-R2, regenerated candidates) | 3 tests OK |
| `tests/test_swirl_optimization.gd` (randomized smooth fixtures without the free tail law drop the module) | 7 checks, 0 failed (failed once before the fixture adaptation) |

## Offline tools and schema

| Check | Result |
| --- | --- |
| `research/aircraft-standardization/build_schema.py --check`, `parameter_register.py --check` (152 paths) | current |
| `migrate.py --check-known`, `test_migrate.py` | 8 canonical v2 files; 5 tests OK |
| `tests/check_transcendentals.py`, float64 guard, shader TIME guard | pass |
| `research/aircraft-data/schema/check.py` (DATA-4a preflight) | 8 aircraft, 0 failed |
| `research/aircraft-data/schema/test_contract.py` (schema/loader agreement) | 1,916 cases (two new: nulling `downwash_gradient` with the module is schema-pass/loader-fail; without it, valid), 142 valid controls, 4 tests OK |
| `research/aircraft-standardization/test_schema_v2.py --godot` | pass |
| `research/test-tools.sh` | offline tool regressions passed |
| `research/validation/dashboard.py --check` (VAL-3, regenerated: digest only; 10 rows unchanged) | fresh |
| `research/flight-robustness/d8b-r2/make_candidates.gd -- --check` | 3 synthetic polar candidates verified |

## Complete suite

`app/test.sh` on the integrated tree (with the concurrent VQ-05 propeller-blur work present): import, generator freshness, guards, parse check of every script, 227 test scripts and every tail check (H7, L5, model contracts, trace acceptance, D8b-R2, weather/turbulence/atmosphere/time-of-day/shaft CLIs, per-aircraft trimmed traces, frame-time logger, fixed-step parity at 30/60/144 fps, E0b5/E0b6p wash transport, E5a/E5b taildragger fixtures): exit 0, 2026-10-12T23:51Z to 2026-10-13T00:29Z. A first complete run stopped at `test_swirl_optimization.gd` before its fixture adaptation; everything before that point had passed. `app/capture.sh` (Xvfb renders) was not run on this VM.
