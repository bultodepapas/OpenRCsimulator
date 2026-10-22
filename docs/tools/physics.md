# Physics and flight tools

Tools to change, measure and compare flight behavior. Each entry: purpose · when · command · result · gotchas. Shared runner, suite and flags: [shared](shared.md). [Back to the index](README.md).

Results here are model predictions. They do not establish physical validation.

## Flight-test battery

- **Purpose:** fly a fixed test card (card `ft-card-v5`, 40 tests: speeds, climb, glide, roll/pitch/yaw response, loop, Immelmann, Split-S, slow/point/snap rolls, stall turn, knife-edge, inverted, spins, stalls, engine-out, takeoff, landing, go-around, throttle steps) through the real session loop for each fixed-wing aircraft, then compare two runs case by case.
- **When:** after any change to aircraft data, aerodynamics, propulsion, controls or the session loop. Use it to validate a handling change such as roll rate.
- **Command:**
  ```sh
  G="$(app/get-godot.sh)"
  # 0. Once per checkout or app copy without an import cache (app/.godot/); otherwise every flight reports script errors.
  "$G" --headless --path app --audio-driver Dummy --import
  # 1. Candidate copy: the change goes here, not into the working tree. Copying .godot/ (~0.4 GB) skips a re-import.
  # The app reads res://../assets/, so the copy needs the repository's assets/ beside it.
  mkdir -p tmp/cand && rsync -a --exclude captures app/ tmp/cand/app/ && ln -s "$PWD/assets" tmp/cand/assets
  # ...edit tmp/cand/app/data/aircraft/<file>.json...
  # 2. Baseline (working tree) and candidate (--app), same --aircraft and --only.
  python3 research/flight-test/run.py --godot "$G" --out tmp/ft-base --aircraft <id> --only trim_sweep,stall_power_off,vmax,roll_rate
  python3 research/flight-test/run.py --godot "$G" --out tmp/ft-cand --aircraft <id> --only trim_sweep,stall_power_off,vmax,roll_rate --app tmp/cand/app
  # 3. Compare.
  python3 research/flight-test/compare.py tmp/ft-base tmp/ft-cand --out tmp/ft-compare.md
  ```
  Aircraft IDs: `"$G" --headless --path app --script "$PWD/research/flight-test/flight_test.gd" -- --list` prints `FT-AIRCRAFT <id>` lines. Current fixed-wing IDs: `jensen-das-ugly-stik-60`, `stik-glow-61fx-2t`, `stik-glow-55ax-2t`, `stik-glow-fs64v-4t`, `gp-extra-300s-60`, `p51d-mustang-120`, `sebart-avanti-s-a200-p100rx`, `turbo-lumber-evolution`.
- **Result:**
  - `run.py` prints `ok`/`FAIL` per aircraft and exits 1 only on a nonzero engine exit, a `SCRIPT ERROR`/`ERROR` line, a timeout or a missing profile. `FAIL … script errors N` with many errors usually means a missing import cache. Read `<out>/<id>/profile.md` for values and `<out>/run.json` for identities.
  - Each test has `valid`: whether the pilot flew what the card asks. An invalid test is a result, not a run failure. There are no pass/fail bands for the airplane.
  - `compare.py` ends with `**N change(s) beyond tolerance.**` (default max(0.01, 1 % of baseline)). Every listed change needs an explanation. `--fail-on-change` makes it exit 1.
  - Roll rate: test `roll_rate`, cases `1.3Vs_right/left`, `start_right/left`, `0.8Vmax_right/left`; fields `max_roll_rate_dps`, `time_to_360_s`, `height_change_m`, `max_sideslip_deg`. Related: `slow_roll`, `point_roll` (need `knife_edge,inverted_speeds`), `snap_roll`, and `modes` (roll time constant, no flight).
- **Gotchas:**
  - `--only` silently skips unknown names; check every name against the list in the [battery README](../../research/flight-test/README.md) (there is no test called `roll`).
  - Tests placed by Vs and Vmax (`roll_rate`, `power_step` and most figures) need `trim_sweep,stall_power_off,vmax` in the same `--only`, or they fall back to estimates.
  - Run baseline and candidate with the same `--aircraft` and `--only`. A fleet baseline against a one-aircraft candidate lists every missing aircraft as a change; a full baseline against an `--only` candidate lists every omitted test as removed unless you pass `--shared-tests`.
  - Runtime: four `--only` tests for one Stik take under a minute; the full card takes about 51 minutes for the fleet with four jobs.
  - Roll rate is speed dependent: compare all three case speeds, not one number.
  - Runs are deterministic: two runs of an unchanged tree compare with zero changes. A nonzero diff on identical trees is a bug.
  - Full workflow, card versions, `--diagnostics`, `spin_state.py` and `polar_fit.py`: [battery README](../../research/flight-test/README.md). Fleet baseline: [FT-05](../research/flight-test/FT-05/README.md).

## Aircraft data and generators

- **Purpose:** know whether an aircraft file may be edited by hand.
- **When:** before you change any value in `app/data/aircraft/*.json`.
- **Command:** find the owning generator, change its source, regenerate, then run its `--check`:

  | Data file | Generator (edit this, then `--check`) |
  | --- | --- |
  | `jensen_ugly_stik_60.json` | Hand-authored. After editing, regenerate the glow variants: `python3 research/glow-engines/build_installations.py` |
  | `stik_glow_*.json` | `research/glow-engines/build_installations.py` (writes CRLF; honor `.gitattributes`) |
  | `gp_extra_300s_60.json` | `research/extra-300/ex05/derive_physics.py` |
  | `p51d_mustang_120.json` | `research/p51/p51-05/derive_physics.py` |
  | `sebart_avanti_s_a200.json` | `research/avanti-s/av06/derive_physics.py` |
  | `turbo_lumber_evolution.json` | `research/timber/tt07/derive_physics.py` |
  | `xcell_60_research.json`, `hx700_electric_3d_experimental.json` | `research/helicopter/xcell/derive.py` (writes both; `hx700/derive.py` also writes the HX-700 file) |

  Unverified rows: confirm in the aircraft guide (`docs/*-PLAN.md`) before regenerating. Then run `python3 research/aircraft-standardization/build_models.py --check` and `python3 research/aircraft-editor/build_descriptors.py --check`.
- **Result:** each `--check` exits 0 and prints that outputs are current.
- **Gotchas:**
  - Quantities are `{value, unit, kind, source}`; a changed value needs a changed `source`. Format: [AIRCRAFT_CONTRACT](../AIRCRAFT_CONTRACT.md).
  - Roll response depends on aileron maximum throw and servo time (`controls`), and on the roll derivatives. `controls.rates` only shapes pilot input and is not an aerodynamic quantity.
  - Generators read and write the repository's `app/data`, not an `--app` copy. For a disposable candidate, edit the copy's JSON and fly only the aircraft you changed; regenerate dependents (for example the glow Stik variants) in the working tree when you adopt the change.
  - Changing a model's physics changes golden flights; see [golden flights](#golden-flights).

## Flight log and replay

- **Purpose:** record a flight (`.orfl`), export CSV, replay it exactly, and replay the same input tape against a candidate.
- **When:** flight-feel, controls or tuning changes (required by AGENTS.md).
- **Command:**
  ```sh
  G="$(app/get-godot.sh)"
  python3 tools/flight_log/flight_log.py record --godot "$G" --out tmp/flight.orfl      # needs a display; F10 start/stop, F11 marker
  python3 tools/flight_log/flight_log.py export tmp/flight.orfl --godot "$G" --out tmp/base
  python3 tools/flight_log/flight_log.py replay tmp/flight.orfl --godot "$G" --out tmp/exact
  python3 tools/flight_log/flight_log.py compare tmp/base/flight.csv tmp/exact/flight.csv --out tmp/exact.json
  ```
- **Result:** check `complete` and `solver_changed` in the reports. Exact replay of the baseline must match before a candidate comparison means anything.
- **Gotchas:** on Linux always pass `--godot` or set `GODOT` (the default is the Windows binary). Recovered prefixes and candidate runs never prove exact equivalence. Manual: [FLIGHT-LOGGING](../FLIGHT-LOGGING.md).

## Golden flights

- **Purpose:** replay recorded per-tick inputs and require the recorded state checkpoints; catches accidental physics changes.
- **When:** runs inside `app/test.sh` (`test_golden.gd`).
- **Command:** check: `python3 tools/godot/run_checked.py --timeout 300 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_golden.gd`. Re-record only after a deliberate, explained physics change: `… --script res://tests/record_golden.gd`.
- **Result:** one line per golden: `ok   golden <name> replays (<ticks> ticks): …` or `FAIL golden <name> …` with the mismatch message.
- **Gotchas:** never re-record to make a failure go away; explain the change in the commit and in the owning research report.

## Headless trace checks

- **Purpose:** validate trace CSVs.
- **Command:** `python3 app/tests/check_trimmed_flight.py <trace.csv> --duration=1.5`; `python3 app/tests/check_wind_trace.py <trace.csv>`; `python3 app/tests/check_atmosphere_trace.py <trace.csv> [--column]`.
- **Result:** exit 0 when the trace meets its contract.

## Benches and probes

| Tool | Command | Notes |
| --- | --- | --- |
| Physics cost | `"$(app/get-godot.sh)" --headless --path app --script res://tests/bench_physics.gd -- --aircraft=<id>` | Run alone on the target machine. Unverified on the dev VM. |
| Other benches | `app/tests/bench_{regimes,wind,radio_events,heli_performance,lake_session_airborne}.gd` | Same pattern. Unverified. |
| Parameter sensitivity | `"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/sensitivity/sensitivity.gd"` | Ugly Stik only. Unverified. |
| Part-throttle thrust, neutral points | `… --script "$PWD/research/flight-dynamics/power-climb/part_throttle_probe.gd" -- --out=<csv>`; `python3 research/flight-dynamics/power-climb/fleet_neutral_point.py` | Read-only; [tools](../../research/flight-dynamics/power-climb/README.md). |
| Modal dashboard | `python3 research/validation/dashboard.py --check` | Currently stale (exits 1). Red reference rows are diagnostics. [Validation tools](../../research/validation/README.md). |
| Workshop experiment runner | [TOOLS → Aircraft Workshop](../TOOLS.md#aircraft-workshop) | Static, tape and sweep analysis of one aircraft or bundle. |

## Track verifiers

Use fresh output directories. Fixture equivalence proves software preservation, not physical validity.

| Area | Entrypoint / authoritative contract |
| --- | --- |
| Aircraft authoring | `python3 research/aircraft-standardization/conformance.py --godot <godot> --out <fresh-dir> --parse-all`; [aircraft contract](../AIRCRAFT_CONTRACT.md). Optional `--package` checks exports. |
| Natural Random | `python3 research/natural-random/verify.py --godot <godot> --out <fresh-dir>`; [evidence](../research/natural-random/README.md). |
| Glow 2T/4T | `python3 research/glow-engines/verify_integration.py --godot <godot> --out <fresh-dir> --parse-all`; [current integration](../GLOW-ENGINES.md), [isolated kernels](../../research/glow-engines/README.md). |
| Helicopter | `python3 research/helicopter/verify_kernels.py --godot <godot> --out <fresh-dir>`; [session and checks](../HELICOPTER.md). |
| Bisonte ground vehicle | [runtime/experiments](../../research/rc-monster-truck/README.md), [native builder/parity](../../research/rc-monster-truck/native/README.md). |
| Electric coupling | [EL2a-P1](../../research/propulsion/el2a-p1/README.md), [EL2a-P2 event qualification](../../research/propulsion/el2a-p2/README.md). Reference runs use their pinned NumPy/SciPy environment. |
| Taildragger and nose-over | `python3 research/ground-contact/e5a/verify.py --out tmp/e5a-proof --mutations`; analogous `e5b/verify.py`. [E5a](../../research/ground-contact/e5a/README.md), [E5b](../../research/ground-contact/e5b/README.md). |
| Long-circuit sensitivity | `python3 research/landing/e4b/measure.py --out tmp/e4b-proof`; [E4b limits](../research/ground-contact/E4b/README.md). Completion does not mean every perturbation passed. |
| Radio calibration | `python3 research/input/d6b-r2/verify.py --out tmp/d6b-r2-proof`; [contract](../research/radio-input/D6b-R2/README.md). |
| Aircraft generators | Source pipelines in the aircraft guides; examples: [P51-05](../../research/p51/p51-05/derivation.md), [EX-05](../../research/extra-300/ex05/derivation.md), [AV-06](../../research/avanti-s/av06/derivation.md). |

Dated evidence: [research index](../research/README.md); experiment folders and their reports: [tools/input map](../../research/README.md).
