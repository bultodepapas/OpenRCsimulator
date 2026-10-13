# TT-07–12: playable experimental Timber

2026-10-12. Turbo Lumber Evolution is selectable and flies its own generated electric v2 dataset. Home offers airborne and runway starts. Fixed wheels, neutral flaps and assists off are the supported configuration. The [integration plan](../../../TIMBER-INTEGRATION-PLAN.md) retains physical and feature acceptance; the [derivation](../../../../research/timber/tt07/derivation.md) owns data assumptions and source mismatches.

## Implementation

`research/timber/tt07/inputs.json` and the imported geometry generate `app/data/aircraft/turbo_lumber_evolution.json`. Manual mass/span/CG and mesh contacts/hinges remain distinct from estimated inventory, aero, motor and tyre parameters. The selected UIUC APC Sport 11×7 map is explicitly borrowed for a three-blade 11×7.3 reference. Every declared estimate has a bounded offline sensitivity row. No other aircraft data or golden flight was regenerated.

The catalog enables EXPERIMENTAL status, with EN/ES limitations. Electric flight already uses the production coupled RK4 law; the integration supplies the aircraft, wheel profile, recorder endpoint callback, audio RPM reference and three-blade cue. The calm trim reader now accepts the electric v7 columns and independently reconstructs current, torque and power. Corrupted electrical values/configuration are rejected.

Runway qualification is centralized in FlightSession and consumed by Home and preferences. A generic three-contact taildragger support-plane seed fixes the initial ground solve: the former level seed converged to an unstable two-main-wheel equilibrium and left the tailwheel clear. The Stik keeps its previous seed arithmetic. Parked aircraft snapshots are an independent, optional subset of the flyable catalog.

The generated v2 schema/register were stale before this work: their generators already described `wing_section_cm_ac`, while the committed generated schema omitted it. Both were regenerated through their existing pipelines; the Timber uses the supported local wing couple and corresponding oracle Cm0.

## Verification

Pinned Godot 4.7.2, native Windows Compatibility on NVIDIA RTX 3090; headless tests use Dummy audio. Captures below use the real Home/flight routes and renderer. They establish visible integration, not a human readability trial.

Captures: [Home EN](home-en.png), [Home ES](home-es.png), [airborne flight](flight.png), [selected runway flight](runway.png). [Manifest](manifest.json) binds the retained captures, CLI trace and focused logs to the aircraft input bytes.

| Proof | Result |
| --- | --- |
| Generated data/schema and load boundary | Generator `--check`, structural schema, production loader and 10 Timber data checks pass; 2.190 kg, 60 mm longitudinal CG, valid full/carrier inertia |
| Real-session handling | 36 checks pass: all six roll/pitch/yaw command directions produce the intended body rotation; complete finite 7,201-row 30 s trim, bounded altitude/speed, throttle response, 0 RPM / 0 A after source-off, powered restart, descending glide, exact serialized electric/wheel checkpoint replay |
| Ground | 23 checks pass: selected runway launch, approximately 21.4765 N wheel support against 21.4766 N weight, idle motion below 5×10⁻¹⁴, both taxi yaw signs, visual steering, typed gear-overtravel rejection and takeoff |
| Ground refinement | 240/480 Hz takeoffs both lift at approximately 15.254 m/s; agreement here does not qualify the landing envelope |
| Existing Stik runway | 19 checks pass; start-choice 36 checks and Home/preferences runway checks pass |
| Product controls | Home/select/fly/pause/restart/end/reselect/preferences, real keyboard sampling and fake-radio calibration/failsafe pass |
| Render-rate independence | Complete checkpoint SHA-256 `44893a82ef66b24279b0073960b6471e571f53fef1c7132964646312fdb555bd` matches at 30/60/144 FPS after 480 ticks with real keyboard commands |
| Trace identity | 219 metadata checks pass, electric motor/bus columns present; exact aircraft input bytes checked on the 3 s CLI trace |
| Audio | Engine reference/blades 12 checks, soundscape 85 and existing engine audio 146 pass |
| Local force oracle | H4 12,500 and H12 12,501 byte comparisons pass with the optional post-H12 wing couple neutral in both copies; the enabled Timber couple separately matches the analytic strip sum exactly (−1.336670227369 Nm) |
| Render adapter | 213 hinge/rest checks pass; electric continuous layout/no-wash check passes all 39 checks |
| Presentation | Shadow 37 checks, field lights 49, crash pose 107, crash integration 95 and population checks pass |

Static full-throttle equilibrium is approximately 38.13 A. The ideal ESC permits a roughly 113 A throttle-up transient; the rating comparison applies only to settled static output. No current limiter or measured motor/propeller validation is claimed.

## Reproduce

From the repository root, using the pinned engine (native Windows can replace `$(app/get-godot.sh)` with `.tools/Godot_v4.7.2-stable_win64_console.exe`):

```sh
python3 research/timber/tt07/derive_physics.py --check
python3 research/timber/tt07/sensitivity.py --check
python3 research/timber/tt07/test_derive.py
python3 research/aircraft-data/schema/check.py app/data/aircraft/turbo_lumber_evolution.json
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_timber_data.gd
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_timber_handling.gd
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_timber_ground.gd
"$(app/get-godot.sh)" --headless --path app -- --aircraft=turbo-lumber-evolution --trace=/tmp/timber.csv --t=3
python3 app/tests/check_trimmed_flight.py /tmp/timber.csv --duration=3 --aircraft-input=app/data/aircraft/turbo_lumber_evolution.json
"$(app/get-godot.sh)" --path app -- --quick-flight --aircraft=turbo-lumber-evolution --start=runway
```

`app/test.sh` checks the new generator, sensitivity, authoring tests, GDScript tests, CLI flight and complete-checkpoint equality at 30/60/144 FPS. The CI aircraft generation section also checks the dataset.

## Limits and remaining acceptance

The broader `app/test.sh` attempt in a frozen Linux copy stopped at existing grass-generation byte freshness: committed `grass.json` contains CRLF while its generator emits LF; its parsed values match the recipe exactly. The existing P-51 H13 slipstream reference also fails 5,955/10,001 comparisons on an untouched HEAD copy with the same results as this tree. Those failures are recorded without changing another aircraft's physics or reference oracle. Of 25 affected GDScript test files, 24 pass; the remaining failure is that pre-existing P-51 oracle. UI/keyboard/radio/trace checks are also run separately.

Flap physics/input, a matched three-blade map, pack depletion, measured mass/inertia/motor losses, ground/landing/stall/aerobatic envelope, owner radio playtest, target performance acceptance and public packaged delivery remain open. Redistribution terms are still deferred by the owner. Software checks do not close Gate TT-C.
