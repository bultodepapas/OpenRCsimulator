# AFC-04 R8: terrain recovery without false traffic conflicts

2026-10-23 (America/Bogota). Follow-up to [R7](../AFC-04-R7/README.md).
Candidate verification; source-profile admission remains with the separate
qualification owner.

## Problem and repair

At 24 m local clearance, the predictor's terrain reserve is −1 m. That identical
penalty applied to every horizontal candidate and also controlled traffic-maneuver
acquisition and release. A player 1,000 m away could therefore trigger an avoidance
turn, suppress normal route guidance and retain the turn beyond its minimum hold.
Low terrain clearance alone could prevent the traffic-clear dwell from starting.

`app/ai/companions/pilot.gd` now retains a separate traffic margin for acquisition
and release. Combined terrain/traffic scores still rank candidate turns and remain
visible in diagnostics, alongside the separate traffic margin. Base terrain
recovery, pitch/throttle laws, bank limits and hold/dwell durations are unchanged.
No aircraft data, physics, session, player-control or qualification files changed.

`test_companions_terrain_traffic.gd` failed 11 of 60 checks before the fix and
passes all 60 afterward. It covers player/peer traffic, raised terrain, route
correction, real conflicts, low-clearance recovery, clear dwell, returning threats
and read-only observations. Existing pilot, clearance, lifecycle and external
session suites pass 24, 20, 40 and 65 checks respectively.

## Real-flight comparison

Three research flights use the same 24 m AGL reset-boundary spawn, trim, seed and
weather, followed by 2,880 ordinary FlightSession ticks (12 seconds): baseline with
a stopped peer 1,000 m ahead, baseline without traffic, and candidate with that peer.
No position or velocity is edited after reset.

The baseline with distant traffic held a maneuver for 339 planning samples,
beginning at tick zero. The candidate held none. The candidate's 2,881-row exact
replay CSV is byte-identical to the baseline no-traffic control, including every
logged control and trajectory value. CSV SHA-256:
`032feb859c20493deb867bc72e29e4a468db5a83a2699390f50ab7772f932f31`.

All five logs replay exactly with `complete=true`, `solver_changed=false`: three
full AI trajectories and two tick-zero frozen-peer snapshots. Replays establish
logged physics/input equivalence, not controller decision replay. The original
far-traffic run differed from the control by up to 0.318 normalized roll, 0.746
normalized pitch, 40.17 m north and 44.55 m east over the run. Both retained a
23.997 m minimum AGL. In this fixture, the change eliminates an irrelevant-traffic
disturbance; it does not qualify separation, terrain safety or physical realism.

Raw artifacts are retained under `/tmp/openrc-ai-next/` on the test host. The
research flight probe exposes altitude, distance and no-traffic controls so this
comparison can be reproduced without changing aircraft dynamics.
The [verification receipt](verification.json) pins sources and checked runs; the
[flight comparison](flight-comparison.json) retains run/replay identities and
per-channel differences. Raw absolute paths refer to this test host.

The integrated probe was also rerun: both no-traffic sides completed cleanly,
then the candidate far-peer case completed. All three canonical AI replays match
the no-traffic baseline CSV above. The initial scratch no-traffic run had a final
console-formatting error after writing its complete log/report; that harness bug
was fixed and the canonical rerun verifies clean completion.

From the repository root, extract the R7 baseline and select new output directories:

```sh
git show fa267602:app/ai/companions/agent.gd > /tmp/r8-baseline-agent.gd
git show fa267602:app/ai/companions/pilot.gd > /tmp/r8-baseline-pilot.gd
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --audio-driver Dummy \
  --script ../research/ai-companions/traffic_lifecycle_flight_probe.gd -- \
  --baseline-agent=/tmp/r8-baseline-agent.gd --baseline-pilot=/tmp/r8-baseline-pilot.gd \
  --height-agl=24 --distance=1000 --out=/tmp/r8-far-new
```

Repeat with `--no-traffic` and a different `--out` for the matched control. Replay
the resulting AI logs using the [flight logging workflow](../../../FLIGHT-LOGGING.md).

Independent regression review passes 54 baseline/candidate comparisons: genuine
close player/peer threats at 35 m and 24 m clearance retain identical commands
and combined/adjusted/selected scores; restored held turns and low-speed fallback
also match. This supports the narrow change to conflict acquisition and release.
Both established 12-second crossing scenarios retain byte-identical R7 replay
CSVs across all six AI/player logs; every replay is complete and solver-unchanged.
The project parser checks 1,320 resources with zero errors. It reports 1,145
warnings overall, including the pilot's two existing warnings; the new test has
none. This parser run does not instantiate scenes or qualify rendering.

The pilot-command microbenchmark uses 32 ABBA rounds with 32 calls per block:

| Fixed-input condition | Baseline µs/call | Candidate µs/call |
| --- | ---: | ---: |
| 24 m AGL, traffic 1,000 m away | 514.05 | 116.56 |
| 35 m AGL, traffic 1,000 m away | 109.95 | 110.25 |
| 35 m AGL, head-on traffic 24 m away | 499.28 | 510.57 |

Avoiding false candidate searches cuts the first workload by about 77%. Normal
clear-traffic cost is similar; the measured genuine-conflict cost rises about 2%.
The run passes seven correctness checks. Timing excludes configuration, manager,
FlightSession stepping, rendering and audio. It was pinned to CPU 11 while an
unrelated Godot process remained alive; this is not frame-pacing qualification.

## Remaining limits

Candidate-independent terrain penalties can still mask differences among turns
in a real conflict. One controller fixture selected a negative traffic margin
despite a positive-margin alternative. That ranking issue is retained as a
separate investigation; this repair does not introduce more aggressive turns or
claim a feasible combined escape when the terrain score is negative.

Production profile binding, general recovery/avoidance, taxi autonomy and physical
AI/AI/player contact remain open. R7's 45 m stopped-peer encounter still fails its
15 m center-separation target; this change does not claim to fix that scenario.
