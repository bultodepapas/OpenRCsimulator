# AFC-04-R2 — avoid descending into terrain recovery

2026-10-20, native Windows Godot 4.7.2. This increment repairs conflicting
avoidance and recovery altitude demands. **The 30 m moving-traffic separation
gate remains failed.** It does not qualify new activities, counts or aircraft.

## Diagnosis and correction

The two crossings that crashed in [AFC-04-R1](../AFC-04-R1/README.md) reproduced
with identical per-tick state/command digests. New recordings retain each AI and
coupled player up to the crash, plus a separate player session through all 2880
requested ticks. The independent session uses the exact same spawn specification
and solved trim controls; AI failure cannot truncate it.

The pitch sign and trim mapping are consistent: the pilot emits normalized
trim-relative stick demands; `FlightSession` applies the solved trim once.
Positive pitch commands elevator trailing-edge up. Both actual and desired
vertical velocities in the feedback law use NED metres per second, positive down.

The conflicting demands were visible in the first crossing:

| Time | AGL | Altitude target | Recovery | Pitch command | Throttle |
| --- | ---: | ---: | --- | ---: | ---: |
| 6.8 s | 29.952 m | 39.958 m | On | +1.000 | 1.000 |
| 7.2 s | 30.224 m | 25.000 m | Off | -1.000 | 0.098 |
| 7.6 s | 29.902 m | 39.967 m | On | +1.000 | 1.000 |

Slot zero's circuit target is 35 m above the field. A descending avoidance request
subtracts 10 m, but recovery switches on below 30 m and asks for current altitude
+10 m and full throttle. On crossing back above 30 m, the pilot resumes descending
toward 25 m. Both failed crossings show this cycle before the upset and crash.

Descending avoidance targets are now floored at **current local terrain +35 m**,
using `height - observed_clearance + BASE_HEIGHT_AGL_M`. The existing lowest circuit
band supplies a 5 m target margin above recovery activation. The recovery override
still runs last. Higher bands retain permitted descents to 45/65 m over level
terrain. No descending avoidance means no change to the existing controller path.
Pitch gains, actuator limits, aircraft data, physics and the recovery threshold
are unchanged.

This is a target bound, not a guaranteed clearance bound. The instantaneous terrain
sample does not predict rising terrain ahead, and the 5 m margin is not a certified
tracking envelope. The existing abrupt recovery switch can still be reached by
other disturbances; this repair does not qualify general upset recovery.

## Recorded crossing comparison

| Case | Baseline | Corrected |
| --- | --- | --- |
| 20261020 crossing-right: completed ticks / 2880 | 2438, terrain crash | 2880, no crash |
| Minimum terrain clearance | 0.369 m | 34.398 m |
| Peak absolute bank | 179.319° | 26.163° |
| Minimum player center distance | 7.306 m | **4.127 m** |
| 20261021 crossing-left: completed ticks / 2880 | 2422, terrain crash | 2880, no crash |
| Minimum terrain clearance | 0.270 m | 34.501 m |
| Peak absolute bank | 179.869° | 26.114° |
| Minimum player center distance | 7.156 m | **3.860 m** |

Each baseline crossing has three recovery-state switches in the retained 10 Hz
diagnostics; the corrected crossings have none. Peak corrected pitch demand is
0.066/0.046, compared with saturated ±1 demands in the failed flights. The corrected
first crossing repeats exactly through all requested ticks.

The correction removes these terrain crashes while reducing vertical separation
from the player. It is not an improvement to every safety metric. Horizontal
conflict resolution, reachable trajectories, reaction margins and maneuver
hysteresis are still required before claiming encounter avoidance.

The [baseline report](baseline/report.json) and [candidate report](candidate/report.json)
include per-tick state/command digests, failure reasons, minimum separations,
clearances, bank/control peaks, source identities and log hashes. `trajectory.csv`
adds altitude target, recovery state, pitch/bank angles and pitch rate to the
existing 10 Hz samples. State is observed after the tick; held guidance describes
the command that advanced it. These diagnostics never feed control back into the
session. The baseline exits 1 for its actual flight failures. A candidate survey
can exit zero for finite, complete, deterministic flights while explicitly
reporting a failed separation gate.

## Extended flights and integration gates

The [60-second survey](recovery-60s/report.json) completes all 14,400 ticks for
each of seven cases with finite results and no crash, refusal or simulation fault.
The constructed two-threat case repeats with an identical per-tick state/command
digest. Physics remains at 240 Hz and planning at 60 Hz, with actual session
terrain, lake and scenery collision inventory installed.

| Seed / case | Minimum AI AGL | Peak AI bank | Minimum player distance |
| --- | ---: | ---: | ---: |
| 20261020 head-on | 34.363 m | 26.169° | 11.846 m |
| 20261020 crossing-left | 34.413 m | 26.126° | 11.578 m |
| 20261020 crossing-right | 34.398 m | 26.163° | 4.127 m |
| 20261021 head-on | 34.469 m | 26.122° | 11.560 m |
| 20261021 crossing-left | 34.501 m | 26.114° | 3.860 m |
| 20261021 crossing-right | 34.509 m | 26.089° | 11.387 m |
| 20261020 constructed two-threat fixture | 34.451 m | 26.344° | 10.190 m |

The constructed fixture also misses its 15 m peer-clearance target (8.961 m).
Its initial conflict is a deliberate test setup, not an admitted production spawn.
That distinction does not protect against later player incursions: runtime does
not continuously enforce the 30 m separation target. The survey establishes
crash-free completion for these cases, not full route containment or general
recovery with traffic overhead.

The [circuit matrix receipt](checks/afc04r2-circuit-matrix-027vmke6/report.json)
reports **148 checks, zero failures** across the existing 120-second calm/gentle
one-, two- and three-aircraft scenarios and deterministic repeats. Both output
CSVs in [circuit-matrix](circuit-matrix/) are byte-identical to the original pilot
qualification. The 565.875 s elapsed time is a development-host measurement while
other checks ran; it is not a performance acceptance result.

After promoting the exact tested source and updating only its profile source pin,
**318 focused checks pass**: clearance 20, encounter prediction/selection 191,
pilot 24, profiles 30, manager 53. The new clearance suite covers all three bands,
raised terrain, both sides of the recovery threshold, unchanged observations,
lateral response and an overhead-traffic command fixture. This is not a moving
overhead-traffic flight qualification. The final suite fails four of twenty checks
on the retained baseline and passes on the candidate. Draft test paths in earlier
receipts are historical; the identical suite is now
`app/tests/test_companions_clearance.gd`.

[verification.json](verification.json) binds the sources, checked-runner receipts,
replays, comparisons and measured survey outcomes. Expected baseline failures are
kept separate from passing integration results. The accepted aircraft inertia
advisory appears during session setup; it does not establish physical validation.

## Replay and source provenance

All twelve baseline/candidate `.orfl` streams passed exact replay, each with
`status=ok`, `mode=exact`, `complete=true`, `solver_changed=false`. Each version
contains two AI logs, two coupled-player logs and two independent-player logs.
The independent-player CSVs match byte for byte across the full 2880-tick window,
including commands. Each coupled-player CSV matches its independent tape through
its entire recorded duration. The existing flight-log comparison tool also checks
the two full player tapes in `seed-*-player-comparison.json`.

Both baseline AI tapes were replayed again after the production pilot/profile
update. Their `replay-after-*` reports still show exact, complete replay with
`solver_changed=false`; their exported CSVs match the pre-update replays byte
for byte. Controller code changes do not rewrite a recorded command tape.

Complete log closure does not imply a successful requested flight: baseline AI
logs end at the crash. Exact replay consumes the recorded commands and does not
run the pilot. The closed-loop AI trajectories intentionally differ; identical
exogenous input and unchanged physics do not establish physical realism.

Baseline pilot: SHA-256
`51ccb3cdec3a4c898277c1b30542131c9938841dbde9debc0e45bf24601db1b3`,
recoverable at commit `545d74bd1d1fda29bd77a46b470af5085f830dfd`, path
`app/ai/companions/pilot.gd`, Git blob
`1994a3f14f9ab03e5cfc07bd14ac73d1c35b2b9f`.
Candidate SHA-256:
`1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`.
This exact source is now installed as `app/ai/companions/pilot.gd` and pinned by
the Stik companion profile. Its scope remains 1–3 airborne Experienced Stik
circuits on the qualified Club field/weather envelope.

The candidate was evaluated as `res://../tmp/afc04-r2-pilot-candidate.gd` before
promotion. `encounter_probe.gd` captures the selected pilot/probe identities before
running sessions. `pilot_probe.gd` now accepts the same optional `--pilot=res://...`
argument and prints its hash, allowing qualification without temporarily changing
the live source/profile pair. Current default behavior still loads the live pilot.

## Reproduce

From the repository root, use a new absolute output directory:

```powershell
python tools/godot/run_checked.py --label companions-crossings --timeout 300 --require-text "COMPANION ENCOUNTER SURVEY COMPLETE" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/encounter_probe.gd -- --record-crossings --out=C:/captures/companions-crossings-new
```

`--record-crossings` selects only the two recorded failure fixtures and repeats
the first. The default still runs six nominal geometries and the constructed
two-threat fixture. `--record-none --seconds=60` runs that broader survey without
large recordings. Recorded runs are bounded to 20 seconds; unrecorded runs to 60.
Fractional, repeated and out-of-range durations are refused before output creation.
Existing output directories are never reused. Neither survey is fleet restoration
or AI decision replay.

Keep source pins narrow. The next AFC-04 gate is resolving simultaneous moving
conflicts without sacrificing terrain clearance, including low-clearance traffic
overhead, with reproducible replay and post-encounter recovery. The multi-seed
endurance, trajectory-containment and target-hardware gates remain separate.
