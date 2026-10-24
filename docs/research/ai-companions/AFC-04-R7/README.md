# AFC-03/AFC-04 R7: stopped traffic and maneuver continuity

2026-10-23. This change corrects traffic observations and maneuver persistence;
it does not qualify general collision avoidance or enable aircraft contact.

## Runtime changes

- `Agent.observation()` retains a failed/crashed companion as a fixed-position
  traffic obstacle. It previously published its last flight velocity and bank,
  predicting motion while its visible aircraft and session remained frozen.
  The stationary packet uses world position and zero velocity/wind; active
  observations and physical state are unchanged. Stopped observations also avoid
  unnecessary wind, airdata and terrain work.
- `Pilot` preserves its held bank through empty/unusable traffic observations
  until the existing minimum hold and clear dwell both expire. The low-speed
  fallback remains active below 3 m/s. This is a defensive API correction: the
  healthy production manager normally supplies a valid player observation.
- `test_companions_traffic_lifecycle.gd` exercises the real observer/predictor,
  fault and crash states, nonzero prior bank, observer wind, state immutability,
  returning threats, delayed clear dwell and low-speed fallback.

No aircraft data, physics law, kernel, player input or golden flight was changed.
The implementation uses ordinary normalized controls and full `FlightSession`
stepping. The baseline is checkout `cb43600c`; raw sources, checked-run logs,
ORFLs, CSVs and replay reports are retained in `/tmp/openrc-ai/` on the test host.
The unrelated qualification work in this shared checkout has a separate owner.

## Evidence

The original 36-check regression failed 10 assertions before the fix and passed
all 36 afterward. Independent review found and reproduced the low-speed edge;
the corrected final regression passes 40 checks. Pilot, clearance, encounter
selection and external-session suites pass 24, 20, 191 and 65 checks respectively.

A real-session research fixture freezes another aircraft before tick zero, 45 m
or 60 m ahead, then flies the AI for 2,880 accepted ticks (12 seconds). Every AI
trajectory replays exactly with `complete=true`, `solver_changed=false`; each
frozen peer recording contains only its initial state, also exactly replayed.
These are research fixtures, not admitted production fleets or decision replays.

| Initial forward distance | Baseline minimum center distance | Candidate minimum center distance | 15 m center-separation target |
| --- | ---: | ---: | --- |
| 45 m | 10.6669 m | 12.3739 m | Both fail |
| 60 m | 19.3377 m | 22.4015 m | Both pass |

The measured improvements do not establish hull clearance, contact response,
physical realism or safety in arbitrary encounters. Aircraft-to-aircraft contact
remains disabled. Real midair/player/taxi contact belongs to the existing
[AFC-23 paired-contact gate](../../../../AI_FLIGHT_COMPANIONS_PLAN.md); avoiding
traffic must not become artificial collision immunity.

## Technical basis and remaining limits

NASA [DAIDALUS](https://nasa.github.io/daidalus/) requires its caller to supply
current ground-based aircraft states; lifecycle/freshness handling belongs at
that boundary. Its [configuration](https://github.com/nasa/daidalus/blob/master/Configurations/DO_365B_SUM.conf)
uses persistence and hysteresis. These support the input/state-management
patterns here, not transplanting aerospace separation limits or timing to RC
flight. [ArduPilot's avoidance implementation](https://github.com/ArduPilot/ardupilot/blob/master/ArduPlane/avoidance_adsb.cpp)
also distinguishes avoidance response from recovery.

Static scenery containment, explicit infeasible-avoidance handling, stall/terrain
recovery priorities, finite-fuel recovery, production runway activities and
multi-aircraft physical contacts remain open. The 3 m prediction allowance is
not a proven error bound. The pending traffic index accepts full-state packets;
its future runtime integration must also support stopped positional packets.
