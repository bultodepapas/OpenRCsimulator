# AFC-03/AFC-04 R7: stopped traffic and maneuver continuity

2026-10-24 UTC. This change corrects traffic observations and maneuver persistence;
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
  fallback remains active below 3 m/s while the held latch remains set. This is a defensive API correction: the
  healthy production manager normally supplies a valid player observation.
- `test_companions_traffic_lifecycle.gd` exercises the real observer/predictor,
  fault and crash states, nonzero prior bank, observer wind, state immutability,
  returning threats, delayed clear dwell and low-speed fallback.

No aircraft data, physics law, kernel, player input or golden flight was changed.
The implementation uses ordinary normalized controls and full `FlightSession`
stepping. The baseline is checkout `cb43600c`; raw sources, checked-run logs,
ORFLs, CSVs and replay reports are retained in `/tmp/openrc-ai/` on the test host.
The unrelated qualification work in this shared checkout has a separate owner.
The compact [verification receipt](verification.json), [matrix metrics](scenario_metrics.csv)
and stopped-peer reports ([45 m](stopped-peer-45m.json), [60 m](stopped-peer-60m.json))
retain source identities and results; their absolute raw-log paths refer to the
test host, not portable repository artifacts.

## Evidence

The original 36-check regression failed 10 assertions before the fix and passed
all 36 afterward. A low-speed differential probe reproduced the fallback edge;
the corrected final regression passes 40 checks. Pilot, clearance, encounter
selection and external-session suites pass 24, 20, 191 and 65 checks respectively;
these four suites were refreshed against the final pilot source after evidence audit.

Both baseline and final candidate pass the 148-check flight matrix: one, two and
three aircraft, calm and gentle-practice weather, each for 120 seconds plus seeded
repeat checks, without scripted encounters beyond the player and fleet. Both
metrics and 1 Hz flight-sample CSVs are byte-identical. Two
12-second crossing scenarios also preserve baseline state/command hashes and all
six replay CSVs exactly (`complete=true`, `solver_changed=false`). These establish
regression parity, not improved crossing behavior; actual routes may miss the
nominal intercept. Minimum matrix AGL is 34.31 m and maximum radial error 4.05 m.

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

Six 1920×1080 research-scene captures show the candidate banking past the stopped
peer through six seconds. They use the production aircraft model and real flight
sessions, but a lightweight scene and Mesa llvmpipe software rendering. They do
not qualify the production Main scene, frame rate or target GPU. Images remain
outside the repository. Engine validation before the concurrent UI/render merge
parsed 1,316 resources without errors; 1,143 inherited warnings remain.

Reproduce the stopped-peer experiment from the repository root (use a new output
directory each time; substitute 60 for the second distance):

```sh
git show cb43600c:app/ai/companions/agent.gd > /tmp/baseline-agent.gd
git show cb43600c:app/ai/companions/pilot.gd > /tmp/baseline-pilot.gd
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --audio-driver Dummy \
  --script ../research/ai-companions/traffic_lifecycle_flight_probe.gd -- \
  --baseline-agent=/tmp/baseline-agent.gd --baseline-pilot=/tmp/baseline-pilot.gd \
  --distance=45 --out=/tmp/stopped-peer-45m-new
```

The shared live profile still pins the prior controller (`3842cbd…`), while the
tested candidate is `02fb6dca…`. Production admission therefore remains blocked
until the qualification owner binds the verified candidate. The separate solver
repair now matches the current solver (`3a8ebbc5…`). No shared qualification files
were changed by this behavioral work.

Independent integration verification used a disposable project with only its
local controller profile rebound. Manager (53), observation parity (21), recording
(156), lifecycle (653), presentation (13) and Main shell (49) checks all pass, with
zero checked-runner engine diagnostics. Lifecycle includes 50 headless and 10
visual/audio cycles. Initial lifecycle/shell attempts failed because the disposable
fixture omitted authoring assets and a newly merged rendering script; corrected
fixture runs pass. These checks establish integration behavior with the candidate
profile, not admission through the unchanged shared production profile.

An observation-only ABBA microbenchmark passes 13 correctness checks, with 64
paired rounds per slot and 512 calls per block. Stopped observations fall from
19.2–19.6 to 2.1–2.2 µs/call (about 89% less work). Active snapshots remain
byte-identical, with a measured 2–4% higher cost (roughly 0.3–0.6 µs/call), possibly
guard overhead and/or noise. The i5-10500 run was pinned to CPU 11, but an unrelated
Godot process remained alive. This measures observation calls only, excluding
planning, physics, rendering and audio; it establishes no frame-pacing or whole-app
speedup. The receipt retains per-slot block-mean summaries and the raw-data hash.

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

## Final adversarial review

Good Enemy reviewed the completed implementation and verification independently,
checked source/report identities and reran the lifecycle test (40/40). It found no
new blocker in this repair. Its verdict retains the production-admission constraint,
the failed 45 m separation target and the future traffic-index packet requirement.
This is a verified candidate lifecycle improvement, not completed autonomous flight
or general collision avoidance. No further runtime edit followed that review.
