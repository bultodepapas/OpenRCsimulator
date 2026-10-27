# D6-TRIM-01: natural out-of-trim airframes

2026-10-27 · physics/input D6 step, implemented in current source. Software evidence only: the magnitudes are calibrated in the simulator against RC trimming practice, not measured on built models, and no pilot has evaluated the feel yet.

## What it does

A built RC model never flies straight with its controls at neutral. Wing warps and panel incidence, stabiliser and fin offsets and linkage neutrals leave steady roll, pitch and yaw moments that the pilot trims out on the first flight. Trim practice (Home → Practice → Trim practice; [player guide](../../../FIRST-LAUNCH.md#trim-practice-current-source)) reproduces that:

- A checkbox enables it; an intensity of 0–100 % scales it (0 % is perfectly trimmed).
- **First flight only:** the airframe is drawn once per aircraft for the app session. The pilot's trims survive restarts and crashes, and the next Home flight of the same aircraft.
- **Every flight:** each reset (new flight, R, crash auto-restart) rigs a new airframe, and the trims return to the solved starting trim.
- The trims are never moved by the simulator. The start trim solver, the servo state, the inputs and the rendered surfaces never contain the error.

Defaults: off, 50 %, first flight only. Home airplane flights only; Natural Random, helicopters, cars and technical routes are unchanged unless the route passes `--out-of-trim`.

Edge rules:

- Enabled at 0 % flies a true airframe, but the chosen mode still governs the trims. First flight only keeps the pilot's trims across restarts; every flight returns them to the starting trim, on the runway too.
- An F5 data reload keeps the airframe and, on first flight only, the pilot's trim.
- Radio transmitter trims belong to the radio. Every flight resets only the simulator's own trims.

## Model

Each axis is drawn as an *equivalent trailing-edge angle*: the steady control deflection that would produce the same moment. [`app/sim/out_of_trim.gd`](../../../../app/sim/out_of_trim.gd) owns the draw and the conversion. [`FlightSession._deflections()`](../../../../app/sim/flight_session.gd) adds the offsets, in maximum-throw units, to the actual servo positions before the conventional surface mapping (aileron differential and elevon mixing included). Every aerodynamic path reads that one function: loads, wash, the ground start solve and the downwash lag. A pilot trim of exactly the opposite size therefore cancels the error at every speed and throttle.

| Axis | Full scale at 100 % | Represents |
| --- | --- | --- |
| Roll | 0.6° on each aileron (antisymmetric) | wing warp / panel incidence difference, aileron neutrals |
| Pitch | 0.8° elevator | stabiliser incidence (decalage), elevator neutral |
| Yaw | 1.2° rudder | fin offset, rudder neutral |

- **Draw:** per axis a signed fraction of the full scale. The magnitude is 0.25 + 0.75 × mean of two uniforms (mode 0.625), so 100 % always needs some trim on every axis; the sign is even. The draw is seeded and indexed: `seed × 65537 + airframe index` seeds Godot's PCG32.
- **Aircraft-specific:** the angle is a geometric rigging error, so each aircraft's own control power, stability and speed set its response. An axis without a surface gets no offset, because the pilot could not trim it: the X8 elevons have no yaw.
- **Not modelled:** CG or thrust-line errors (the trim needed would change with speed or power), a lateral weight imbalance (constant moment, worst at low speed), and warp outside the propwash (which would make the trim slightly throttle-dependent).

## Calibration

[`research/flight-dynamics/out-of-trim/probe_out_of_trim.gd`](../../../../research/flight-dynamics/out-of-trim/probe_out_of_trim.gd) flies every catalog airplane hands-off from Home's airborne start: trimmed level at half throttle, 150 m, calm. Each case uses one full-scale axis, a "typical" airframe (0.625 of full scale on every axis), and that airframe trimmed out with the opposite trim. A first pass at 1.2° pitch / 1.5° yaw gave ±20–23° pitch change in 2 s, up to 1.5 g on the jet, and several dives into the ground within 8 s. Pitch was lowered to 0.8° and yaw to 1.2°. Final values, 2 s after release (φ bank, Δθ pitch-attitude change, Δψ heading change):

| Aircraft | V0 m/s | roll+ φ | pitch+ Δθ | pitch− Δθ | yaw+ φ / Δψ | typical φ / Δθ | typical, trimmed out: largest Δθ, φ over 8 s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ugly Stik (electric) | 20.6 | +8.5° | +11.4° | −11.9° | +12.3° / +8.7° | +12.6° / −8.4° | 0.0°, 0.0° |
| Stik MAX-61FX | 30.5 | +13.8° | +15.5° | −16.0° | +18.8° / +9.7° | +19.0° / −11.4° | 0.2°, 0.0° |
| Stik MAX-55AX | 29.4 | +13.3° | +15.3° | −15.7° | +17.7° / +9.8° | +18.3° / −11.1° | 0.2°, 0.0° |
| Stik FS-64V | 22.9 | +9.8° | +12.8° | −13.4° | +13.5° / +8.9° | +12.7° / −9.8° | 0.1°, 0.0° |
| Extra 300S | 32.5 | +27.6° | +14.4° | −14.6° | −0.8° / +1.2° | +16.4° / −9.8° | 0.1°, 0.0° |
| P-51D | 46.0 | +10.8° | +14.9° | −14.9° | +10.2° / +5.4° | +12.1° / −10.3° | 0.0°, 0.0° |
| F4U Corsair | 49.3 | +6.2° | +14.1° | −14.4° | +17.5° / +5.1° | +11.4° / −9.6° | 0.0°, 0.0° |
| Ventage Jet | 56.0 | +27.0° | +15.0° | −15.1° | +6.5° / +2.3° | +20.9° / −9.8° | 0.1°, 0.0° |
| Timber | 17.9 | +5.8° | +6.5° | −6.8° | +3.4° / +2.7° | +5.5° / −4.3° | 0.0°, 0.0° |
| X8 | 14.6 | +2.9° | +7.7° | −7.9° | — | +1.8° / −4.9° | 0.0°, 0.1° |

The trimmed-out residual is each start's own hands-off drift (the untouched start shows the same values). Readings:

- Every airplane departs visibly within 2–5 s at 100 %, against the 5–10 s straight-and-level window that RC guidance expects of a *trimmed* model ([trim practice research](../../flight-dynamics/power-climb-2026-10-19/trim-practice-research.md#5-keeping-level-flight-hands-off)).
- Sensitivity differs by design. The Extra and the Ventage Jet (large ailerons, little dihedral) roll fastest. The high-dihedral Stik and Corsair turn a fin offset into bank. The Extra barely responds to a fin offset. The X8's sweep levels a roll error at a few degrees of bank.
- Typical 100 % corrections are a handful to a dozen presses per axis: 0.1° elevator steps, and 0.5 % of throw for aileron and rudder. That matches the "several clicks" of RC first flights and the transmitter step sizes in the same note.

Reproduce: `"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/out-of-trim/probe_out_of_trim.gd" -- --out=tmp/<new>` (about 6 minutes; writes `report.json`).

## Interfaces

- **Session:** `setup_out_of_trim(config, seed, airframes, key)` at tick zero, like `setup_failures`; the next reset rigs the airframe. `adjust_rudder_trim()` joins the aileron and elevator trims (refused without a rudder). `out_of_trim_status()` reports offsets in units and degrees and the pilot's trim beyond the start trim.
- **Rollback:** `_out_of_trim` and `_airframe_offset` are start-transaction owner fields, so a refused restart keeps the flying airframe and consumes no draw.
- **Technical helpers:** `trim_at()`, `try_runway_start()` and `reset_on_runway()` bypass the staging and the trim carry. They serve maneuver scripts, Workshop experiments and the runway scenario, none of which enables the feature.
- **Replay:** a non-zero offset wraps the checkpoint as `openrc-flight-checkpoint v13` (outermost; `airframe_physics_format`, `airframe_trim_offset`). A session without the feature restores it and replays bit for bit, which carries ORFL logs, whose header holds the checkpoint. Visual checkpoints unwrap it. Zero offsets never wrap, so existing formats, golden flights and traces are unchanged. Enabled traces add `airframe_trim_offset`, `airframe_trim_law` and `out_of_trim` metadata.
- **Shell:** preferences hold an additive `[trim_practice] config`; there is no schema change. AppRoot keeps the session-lifetime airframe registry and shares it by reference with each Home flight. The airframe key is the catalog ID, or the Workshop trial ID; the battery or fuel choice does not rebuild the airframe.
- **Keys and controllers:** `,` / `.` are keyboard rudder trim. The new controller actions `trim_yaw_left` / `trim_yaw_right` are optional and unbound by default, because the D-pad already holds aileron and elevator trim.
- **CLI:** `--out-of-trim=<0–100>`, `--out-of-trim-mode=first-flight|every-flight`, `--out-of-trim-seed=<n>`. Refused with `--scripted`.
- **Native kernel (NK-3):** the research oracle captures `session._deflections(aux)`, so it already sees the offset. A native stage evaluator must keep taking the session's deflections, or read `airframe_trim_offset`, rather than map servo positions itself.

## Verification

- [`test_out_of_trim.gd`](../../../../app/tests/test_out_of_trim.gd), 94 checks. An independent source review on 2026-10-27 found two confirmed defects, both now fixed and covered: an F5 reload lost the first-flight trim, and a restored airframe survived restarts in a session with the feature off. The checks cover:
  - configuration validation; draw determinism, bounds and distribution; offset conversion, including elevon yaw;
  - disabled settings fly bit-identical to the historical physics, with no new checkpoint format or metadata;
  - every flight: new airframe on restart and crash restart, trims returned to the start trim, aerodynamic deflections equal servo plus offset, rendered surfaces unchanged, measurable hands-off departure;
  - first flight only: trims and airframe survive restart, crash, F5 reload and the next flight, and a changed intensity rigs a new airframe;
  - a session without the feature restarts with a true airframe after restoring an out-of-trim checkpoint; tiny throws stay within the replayable bound;
  - a refused restart rolls back; X8 rudder-trim refusal;
  - exact v13 replay into a session without the feature, and rejection of malformed layers;
  - preferences round-trip and recovery; the dialog draft.
- [`test_trim_practice_routes.gd`](../../../../app/tests/test_trim_practice_routes.gd): Home keyboard path, Cancel/Apply, persistence, Home summary, the flight receiving the selection and the shared registry, and the card fitting at 1920×1080 and at the 1280×720 fallback.
- Updated: `test_controller_sections.gd` (two flight actions). The catalogs carry the 21 new messages in all eight languages (`test_ui_language.gd`).

## Open

- Pilot evaluation of the 100 % feel on the Stik, the Extra and the Ventage Jet, with keyboard and with a radio.
- Natural Random and the pause menu do not offer trim practice yet.
- Optional CG, thrust-line and lateral-balance components would make the trim speed- or power-dependent. They need source data before adoption.
