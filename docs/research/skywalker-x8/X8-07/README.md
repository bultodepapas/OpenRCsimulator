# X8-07: hand-launch start

2026-10-26. An airplane without landing gear has no runway start, so until now the X8 started trimmed in the air. X8-07 adds the hand launch as an explicit start choice: the airplane appears at the moment it leaves the hand and flies on the shared physics from there. No thrower is simulated. Software verification only; no measured X8 throw exists (open below).

## What it does

| Part | Behaviour | Code |
| --- | --- | --- |
| Offer | Fixed-wing catalog airplanes whose data has no `landing_gear` (today only the X8). A model never offers both ground starts. | `FlightSession.hand_launch_aircraft_supported`, `AircraftCatalog.hand_launch_supported` (cached) |
| Release point | The runway edge nearest the pilot, at the pilot's east coordinate (clamped to the runway): 9 m in front of the pilot on the Club field and Green Paradise. Height: terrain + 1.9 m. | `FlightSession.hand_launch_release` |
| Direction | Along the runway, toward the end with a headwind component of the mean wind (east-bound in calm air or a pure crosswind). | same |
| State | Wings level, body along the throw (α = 0 to it), pitch and flight path +5°, ground-relative speed 6.5 m/s (the wind is not added: airspeed is the throw plus the headwind), no rotation. | `_reset_hand_launch_start` → `Trim.state_for(6.5, 0, 5°, heading, pos)` |
| Motor | Throttle 100 %, shaft already at its full-throttle operating point at the throw's axial speed (electric: `Propulsion.steady_operating_point`). The pilot's trim is the selected launch trim (Home: level flight at 50 % throttle). | `_hand_launch_rpm`, `_reset_airborne_start(release, throttle, rpm, launch)` |
| Refusal | A geared airplane, a missing field or runway, or no motor operating point fails the selected start closed (paused, launch kind `failed`). There is no airborne fallback. | `reset()` |
| Trace | `launch_choice: hand_launch`, `launch_kind: hand_launch_release`, `launch_field_id`, exact release state, aux and continuous state | `_capture_launch` |
| Menus and routes | Home shows **Start: hand launch** where other airplanes show the runway and cycles to the airborne start. A saved ground start (`runway` or `hand_launch`) shows as whichever the airplane supports. Preferences accept `hand_launch` for gearless airplanes and default to it. `--start=hand_launch`; `--quick-flight` uses it for gearless airplanes. The loading screen says "Hand launch". Spanish strings added. | `ui/home.gd`, `app_state/preferences.gd`, `main.gd`, `app_root.gd`, `i18n/es.po` |

The Workshop start qualification and random scenarios are unchanged; their start choices are runway or airborne.

## Values

No source measures an X8, or any 2.5–3.5 kg UAV, leaving the hand. The speed is an estimate from analogues; the attitude and throttle follow manufacturer and autopilot guidance.

| Quantity | Value | Range | Basis | Kind |
| --- | --- | --- | --- | --- |
| Throw speed over the ground (standing overhand throw, 3 kg) | 6.5 m/s | 5–8 m/s; 7.5–10.5 m/s with running steps | A 1.8 kg Mini Talon log reads about 7 m/s at the throw [A5]; PicaSim default 6 m/s [P1]; ArduPilot's pusher floor of 4 m/s [A2] must lie below real throws; heptathletes put a 4 kg shot at 9.0–10.7 m/s, an upper bound [B1] | estimated |
| Release height | 1.9 m | 1.4–2.2 m | Overhead release of a 4 kg shot at 1.85–1.97 m [B1]; PicaSim 1.3 m [P1] | measured analogue |
| Attitude | wings level, +5°, body along the throw | 0–10° | "Apply full throttle and throw the aircraft directly into the wind, angled slightly up (5 to 10 degrees above the horizon)" (E-flite Opterra 2m, a 2 m pusher wing) [M1]; ArduPilot 0–5°, more "could cause a stall" [A1]; PicaSim aligns the body with the launch velocity [P2] | borrowed |
| Direction | into the wind | — | Every source: [A1, X1, M1, G1]; PicaSim and CRRCSim turn the launch into the wind [P2, C1] | consensus |
| Throttle | 100 %, motor spooled before release | 80–100 % | [M1]; PavLab lost an X8 to hand-launch stalls at 75 ± 25 % throttle and full up elevator: "Full throttle at launch (100%), no exceptions" [R1] | borrowed |

The X8's flying weight of 3.13 kg is at the top of the hand-launch range: the manufacturer lists "hand cast / catapult" at 2.5–3.0 kg (search snippet only) [S1], retailers list catapult or bungee [S2], and heavier builds used bungees [F4]. A hand launch works because the 6S pusher gives a thrust-to-weight ratio near 1. On a pusher the prop disc sweeps past the throwing hand; a documented X8 hand injury followed a prop change that made the model leave the hand faster [F2].

## Proof

| Check | Result |
| --- | --- |
| `test_hand_launch.gd` | 136/0: support only for the X8 and never with a runway start; release geometry (calm, both along-runway winds, crosswind, a pilot beyond the runway end, no runway, non-finite wind); launches under calm air, Home's gentle wind, 4 m/s along and across the runway, with the 50 % and the reference trim: release position, ground-relative speed, attitude, airspeed relative to the mean wind and never a tailwind, full throttle and motor speed, pilot trim kept, metadata; 4 s hands-off through the product tick gate without touching the ground; a restart repeats the release exactly; a dead-motor control crashes; a geared airplane and a fieldless session fail closed |
| `test_ui_runway.gd`, `test_ui_aircraft.gd` | Home shows and cycles the hand launch for the X8, Fly starts by hand at full throttle; preference defaults and fallbacks |
| Existing starts, Home and the running app | [X8-10 verification](../X8-10/README.md#hand-launch-x8-07): start, runway, trim, trace and Workshop suites pass, golden flights unchanged; the debug-bridge scenario [`x8_hand_launch.txt`](../../../../tools/debug/scenarios/x8_hand_launch.txt) launches, climbs, restarts and returns Home with 0 errors |

Hands-off after a calm 6.5 m/s release, the X8 sags 0.11 m and is 30 m up after 4 s. With full power and the 50 % trim it keeps pitching up into a loop. The pilot must fly it, as in reality.

Sensitivity (calm air, 50 % trim, hands off, release at 1.9 m), against an independent point-mass estimate by the research scout (constant 0.9 C_Lmax, T = 32 N·(1 − V/40)):

| Throw | OpenRC lowest CG height, full power | Point mass, full power | OpenRC, motor stopped |
| --- | --- | --- | --- |
| 4.0 m/s | crash at 0.77 s | — | — |
| 5.0 m/s | 1.15 m | 0.8 m | — |
| 6.5 m/s | 1.80 m | 1.8 m | crash at 0.95 s |
| 8.5 m/s | 1.90 m | 1.9 m (8.0 m/s) | crash at 1.25 s |

Power at release, not the throw, decides the outcome, which matches the field reports [R1, A5, A6].

A probe that steps `sim.step()` alone skips the session's contact and crash gate (`_session_after_input`): the airplane falls through the ground without a crash. The test steps through the gate like the product loop ([LEARNINGS](../../../LEARNINGS.md)).

## Open

- **Owner evidence:** one logged throw of a real X8 (GPS or flight controller: speed, pitch and height at release) replaces the estimated speed (X8-11).
- **Motor delay:** autopilot users start a pusher 0.2 s or more after release, above 4 m/s [A1, A2]. A delayed-motor option is not offered; it would crash the X8 at a 6.5 m/s throw in calm air (sensitivity above).
- **Throw scatter** (±1 m/s, ±5° pitch and roll) and a solo throw beside the pilot (PicaSim 1–2 m ahead, 1–3 m aside [P1]) are not modelled. The runway-edge release keeps the airplane in front of the pilot station along the flight line.
- **Wind near the ground:** the direction choice uses the field's mean wind. It does not apply a surface wind profile at the 1.9 m release height.

## Sources

Local copies (not redistributed) in `references/skywalker-x8/hand-launch/` for [A1], [A5], [B1], [B2], [F2], [M1], [X1], [X2]; accessed 2026-10-26.

- [A1] ArduPilot, Automatic Takeoff. https://ardupilot.org/plane/docs/automatic-takeoff.html
- [A2] ArduPilot, Plane parameters (TKOFF_THR_MINSPD, TKOFF_THR_MINACC, TKOFF_THR_DELAY, THR_SLEWRATE). https://ardupilot.org/plane/docs/parameters.html
- [A5] ArduPilot Discourse, "Hand launch crash repeatedly" (Mini Talon log). https://discuss.ardupilot.org/t/hand-launch-crash-repeatedly/76361
- [A6] ArduPilot Discourse, "Takeoff mode for hand launch with engine running at 60%". https://discuss.ardupilot.org/t/takeoff-mode-for-hand-launch-with-engine-running-at-60/139747
- [B1] Quintic, shot put case study. https://www.quintic.com/education/case_studies/shot_put.html
- [B2] Marques, Marinho, van den Tillaar (2010), J Sports Sci Med 9:524–526 (values only in a figure). http://jssm.org/volume09/iss3/cap/jssm-09-524.pdf
- [C1] CRRCSim launch presets (`src/config.cpp`, `src/crrc_main.cpp`). https://github.com/paparazzi/crrcsim-pprz
- [F2] diydrones, "Skywalker X8 hand injury" (2013). https://diydrones.com/profiles/blogs/skywalker-x8-hand-injury
- [F4] diydrones, "bungee launch X8 5.3kg". https://diydrones.com/profiles/blogs/bungee-launch-x8-5-3kg
- [G1] Model Airplane News, "5 steps to a perfect hand launch". https://www.modelairplanenews.com/5-steps-to-a-perfect-hand-launch/
- [M1] E-flite Opterra 2m manual, Hand Launching. https://horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFL11150-Manual-EN.pdf
- [P1] PicaSim `GameSettings.cpp` and `data/SystemSettings/Aeroplane/*.xml` (numbers only). https://github.com/Rowlhouse/PicaSim
- [P2] PicaSim `Aeroplane::LaunchNormal` (behaviour only). https://github.com/Rowlhouse/PicaSim/blob/main/source/PicaSim/Aeroplane.cpp
- [R1] PavLab-MIT, UAV Flight #1 Hot Report (X8 hand-launch stalls). Local: `references/skywalker-x8/models/pavlab/flight_report.pdf` ([X8-01](../X8-01/README.md))
- [S1] Skywalker X8 product page (search snippet only; connection refused). http://skywalkermodel.com/en/76.html
- [S2] ReadyMadeRC X8 page ([X8-01](../X8-01/README.md)). https://www.readymaderc.com/products/details/skywalker-model-x8-wing
- [X1] PX4, Fixed-wing Takeoff mode. https://docs.px4.io/main/en/flight_modes_fw/takeoff
- [X2] PX4 launch detection parameters. https://github.com/PX4/PX4-Autopilot/blob/main/src/modules/fw_mode_manager/launchdetection/launchdetection_params.yaml
