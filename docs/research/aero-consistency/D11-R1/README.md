# D11-R1 / D6e-R5 — Aileron authority and sport dual rates

2026-10-26. Software verification and model-consistency repair; physical flight
validation and owner handling acceptance remain open. Runtime/data and the
[player guide](../../../FIRST-LAUNCH.md) define current behavior.

## Diagnosis and decision

The owner reported slow rolls on the Ugly Stik, Corsair and jet. Investigation
separated device shaping, servo travel, aerodynamic authority, damping, inertia
and entry speed. Two Sol High reviewers independently traced the input chain and
reviewed aerodynamic conventions and the final change.

1. The live scene used normal rates while the flight-test battery used full
   rates. Normal aileron travel is 55.56% on the Stik, 79.81% on the Corsair and
   50% on the Avanti. Expo preserves full-stick endpoints; inertia principally
   changes the transient, so neither explains this travel reduction.
2. Conventional aircraft generators still derived local aileron effectiveness
   using uncoupled whole-aircraft lift slope. The runtime has used a calibrated
   section slope and induced-flow matrix since D11d. At zero angle of attack,
   local paired aileron derivatives were 25–33% below their authored oracles.
   The Stik local authority/damping ratio was 0.626 of its oracle; the other
   aircraft's weaker local damping offset more of their authority loss.
3. No degree/radian, per-surface factor-of-two, inertia solve or duplicate-damping
   error was found. [D11d](../D11d/README.md#findings-for-other-owners) already
   identified the Stik's authority gap as follow-up work.
4. The historical uncontrolled-roll trigger was **elevator overpull into stall**,
   followed by local-strip autorotation; see [D6e](../../radio-input/D6e/README.md)
   and the [elevator investigation](../../flight-dynamics/elevator-repair-2026-10-13.md).
   It was not evidence that all full-aileron inputs were defective. The owner
   approved full roll travel while retaining soft pitch/yaw and dual rates.

The derivation now solves `tau = Clda_right / Dright`, where
`Dright = -a0/(N*b) sum_i(y_i sum_right(E_ik))`, using the existing six equal-area
strips and calibrated section slope. The pure-Python authoring helper is
[aileron_effectiveness.py](../../../../research/aero/aileron_effectiveness.py).
The runtime parameter keeps its angle-effectiveness meaning; no loader override,
new force multiplier, inertia change or artificial roll-rate cap was added.
Generators regenerate Extra, P-51, Avanti, Corsair and Timber data. The authored
Stik changes the same quantity and provenance; glow/propeller variants inherit it.
Only that quantity and its source change in each aircraft JSON. Workshop base
identities are regenerated. The X8 has a distinct elevon law and is excluded.

The live default is **sport**: full aileron travel with normal keyboard expo and
normal pitch/yaw travel. Gamepad expo is applied once; physical radios retain
transmitter rates. **N** remains a two-position switch: sport ↔ normal by default,
full ↔ normal after `--rates=full`. Explicit `--rates=normal` keeps the legacy
normal/full pair. Technical `FlightSession` defaults remain full. HUD, help and
flight logs name the effective profile rather than inferring it from a boolean.

## Primary references and applicability

- [NACA TN 1670, printed p.45](https://ntrs.nasa.gov/api/citations/19930082297/downloads/19930082297.pdf):
  steady rolling moment balances aileron authority and roll damping; the helix
  parameter scales rate with airspeed/span. It does not prescribe these RC rates.
- [Original UltraStick25e coefficients](https://raw.githubusercontent.com/UASLab/OpenFlightSim/b020511223946b8642c73a35eacd17c4d5c09ddf/Simulation/aircraft/UltraStick25e/AeroOpenFlight.xml):
  ±0.0823 are individual right/left derivatives, confirming the paired convention.
- [Selig 2010, pp.5–6](https://m-selig.web.engr.illinois.edu/pubs/Selig-2010-AIAA-2010-7635-FullEnvelopeAeroSim.pdf):
  local control-dependent section loading and induced flow support this model
  structure. Its detailed control-edge geometry is more resolved than this
  six-strip half-wing approximation; it does not validate the chosen coefficients.

## Separate experiments

### Aircraft calibration only

The same `ft-card-v5` cases ran on all ten catalog fixed-wing aircraft, using
`trim_sweep,stall_power_off,vmax,roll_rate` and aerodynamic diagnostics. All four
cases were valid on all ten aircraft in both runs. A scratch one-parameter
candidate on the three reported aircraft preceded adoption. The test-card
controller uses full rates, so these are not default-input response measurements.

| Aircraft and entry speed | 360° right, before → after | 360° left, before → after |
|---|---:|---:|
| Stik, 15 m/s | 2.84 → 2.68 s | 3.05 → 2.81 s |
| Corsair, 49.67 m/s | 4.32 → 3.99 s | 4.53 → 3.82 s |
| Avanti, 29 m/s | 1.14 → 0.89 s | 1.14 → 0.89 s |

[All roll cases](evidence/roll-cases.json), [complete differences](evidence/fleet-comparison.md)
and baseline/candidate profiles retain the slower-speed cases, sideslip and height
outcomes. The 221 reported differences are predominantly roll trajectories and
roll-dependent stall recovery. Neutral trim/Vmax behavior is retained within the
comparison tolerance. A changed recovery trajectory is not evidence of better
physical recovery.

The Corsair still does not finish a roll within the card's limit at 19–23 m/s;
low-speed full-stick height loss and sideslip worsen in several cases. Faster
completion at cruise does not close that limitation. Aileron-only rolls also need
pitch/rudder coordination to retain height.

### Recorded input tapes

Baseline `.orfl` files were recorded **before** the aircraft change, exported and
replayed exactly, then candidate aircraft replayed the same post-rate input tape.
All reports are complete; the aircraft-only replay reports `solver_changed=false`.
This establishes an isolated data comparison, including the nearly unchanged
normal-rate low-alpha Stik/jet cases. It does not reapply the later sport shaping.

Separate live sport recordings use the same 0.5 s neutral / held-right-stick
schedule and launch selection. They have their own exact replays. Original and
sport post-rate commands intentionally differ, so this is not exact equivalence.
Additional current-source normal recordings isolate the profile choice from the
aircraft calibration; their summaries are retained beside the recordings.

For the current-source normal/sport pair, initial samples and every raw tick/input
sample match exactly. Each recording has a complete exact replay with
`solver_changed=false`; only the selected shaping profile changes. The
[profile comparison](evidence/input-profile-comparison.json) reports:

| Aircraft / initial TAS | Normal → sport peak body roll | Normal → sport height loss |
|---|---:|---:|
| Stik / 18.92 m/s | 123.0 → 216.6°/s | 21.32 → 25.54 m |
| Corsair / 47.67 m/s | 99.9 → 120.0°/s | 6.53 → 8.34 m |
| Avanti / 54.31 m/s | 351.8 → 945.7°/s | 23.31 → 27.77 m |

These are short uncoordinated held-stick flights (3 s on the Stik, 2.5 s on
Corsair/jet after the neutral interval), not steady roll-rate or height-retaining
maneuvers. The jet's high rate is substantial; the normal position remains
available immediately. The integrated body-p channel is not labelled completed
attitude rolls.

## Checks and limits

- The new runtime finite-difference regression failed 18 checks before the
  calibration. Afterward, **64 checks pass**, testing individual and paired
  ailerons at 0° and 4° against the authored oracle within 1% across stock
  conventional aircraft. This is a consistency tolerance, not a physical band.
- Six authoring-helper tests cover independent D11d known answers, tapered
  equal-area moments, separate forward reconstruction, scaling and invalid data.
- **71 rate checks pass**, including normal/sport/full, trim ordering, keyboard
  expo, gamepad single expo, radio bypass, remembered dual-rate positions and
  exact 120-tick replays across switches with correctly named events.
- Existing aerodynamic, regime/damping, control/servo, envelope, spin, Extra
  post-stall and Stik/Extra/P-51/Avanti/Timber handling checks passed. The real
  keyboard-to-scene end-to-end check also passed with the sport default.
- The deliberate Stik calibration changes three golden trajectories; they were
  recorded again with their original inputs and replayed. The glide remained
  within its original tolerance; re-recording only changes numerical roundoff
  there. Before/after reports are retained.

Increasing tau changes the geometric angles used for local stall and model
blending. Authored damping coefficients and neutral control derivatives are
unchanged, but damping, yaw, drag and wake along a controlled trajectory can
change. Full aileron near stall can stall one half-wing. The sport profile also
increases roll travel and is especially fast on the jet. Normal rates remain one
switch away; no claim of physical calibration or owner acceptance is made.

The changed Stik bytes and input-layer source also require companion admission
renewal. The [existing circuit matrix and production manager gates](../../ai-companions/AFC-02/aileron-2026-10-26/README.md)
pass before the pins are updated; the pre-existing stale solver pin is documented
separately from this repair.

The complete `app/test.sh` attempt is **not green**: after resource import it
stops in the parameter register on the concurrently integrated, unassigned
`intended_hull_support.control_envelope.max_angular_speed` parameter. The unrelated
`test_ui_help.gd` keyboard-navigation fixture also lands on Language instead of
Help and aborts; the normal rates/HUD/localization and real input tests pass.
Neither failure was bypassed or repaired as part of this change.

## Evidence and reproduction

[evidence/manifest.json](evidence/manifest.json) identifies retained compressed
recordings, CSVs, export/replay reports, profiles and test logs. Gzip is storage
compression only: decompress `.orfl.gz` and `.csv.gz` before using the existing
[flight-log tools](../../../FLIGHT-LOGGING.md). Preserve JSON reports with CSVs.
No pictures or new plotting system are included.

Baseline work began at `77962a27`; other sessions committed/merged the shared
working tree during investigation. Fleet manifests report the observed commits
and dirty paths. The isolated recorded data comparison reports its actual solver
identities; later sport recordings include the input-layer source change and
intervening shared-tree changes. Do not infer single-variable source equivalence
from the live before/after comparison alone.
