# AFC-04-R1 — strongest-threat selection and moving encounters

2026-10-20, native Windows Godot 4.7.2. This is a controller regression repair
and a moving-traffic survey. **Moving-encounter qualification failed.** Population,
activities, weather and aircraft eligibility are not expanded.

## Correction

The pilot replaced the strongest threat's lateral response but could keep a
previous, weaker threat's vertical demand. It now resets that vertical demand
whenever a stronger threat wins, before calculating the selected threat's own
vertical response. Strictly equal severities still retain the first observation;
the manager supplies stable order. Gains, prediction horizon, separation margins,
physics, aircraft data and golden flights are unchanged.

The new `app/tests/test_companions_encounters.gd` has 191 checks: horizon/clearance
boundaries, receding/co-moving/vertical/crossing traffic, span and closure margins,
self/malformed observations, large-coordinate translation, six permutations of a
unique strongest threat, full-controller altitude output, and read-only inputs.
Eighty seeded populations of 1/2/8/32 observations compare prediction severity
against independent interval minimization of squared range on [0, 6] seconds.
This tests the existing linear closest-approach policy, not a reachable maneuver
or high-count runtime qualification.

Before the repair, five checks failed, including a reversed dense-traffic fixture.
Afterward all 191 passed, as did the existing 24 pilot checks. The baseline and
first candidate receipts reference the draft's former research path; its contents
were then moved unchanged into the normal automatically discovered test suite.

## Circuit qualification and integration

The corrected source passed all **148** checks in the six 120-second calm/gentle
scenarios (one, two and three companions), plus two three-aircraft calm repeats.
Both [scenario metrics](circuit-matrix/scenario_metrics.csv) and
[one-second flight samples](circuit-matrix/flight_samples_1hz.csv) are byte-identical
to the [original matrix](../pilot/README.md). These are sampled trace comparisons;
the full every-tick replay proof below applies to the recorded two-threat fixture.
The matrix uses a stationary player reference and field surfaces, not the full
scenery/lake inventory. Its 423.891 s wall time is not a performance qualification.

The aircraft profile now pins the corrected controller hash and keeps its existing
circuits-only scope. Its fixed evidence reference still points to the original
pilot qualification page, which links this requalification. An attempted new
reference was rejected by the strict loader; the first profile/manager test
receipts retain that integration failure. The final checks use the supported
reference. No admission rule was relaxed.

Final checked-runner receipts, source identities and comparison assertions are
indexed by [verification.json](verification.json); raw logs remain in [checks](checks/).
Failed survey receipts remain failed and are not included in the passing check
total. Expected baseline regression failures and output-directory refusal are
also identified separately.

The final total is **500 focused checks** (encounters 191, pilot 24, profile 30,
manager 53, recording 156, shell 46), plus the 148 circuit checks. Recording and
shell processes exited zero but their initial runner invocations supplied the
wrong completion text. `verification.json` records reinspection of their retained
logs through the existing checked-runner scanner with the actual completion
markers; the original receipts are unchanged. Shell reported one scenery warning
about unsupported maple-tree wind material and no engine errors. This increment
does not qualify that renderer behavior.

## Moving-flight results

`research/ai-companions/encounter_probe.gd` advances real external-driver
`FlightSession`s at 240 Hz and samples guidance at 60 Hz. All commands for tick N
use observations from tick N before any session advances. Every session loads
the Club field, full scenery collision inventory and lake. Intruders retain their
solved trim controls and fly their actual dynamics. Only tick-zero airborne spawn
places state; no trajectory is teleported or corrected afterward.

Six cases place one intruder to meet the nominal circuit at six seconds:
head-on, crossing-left and crossing-right for seeds 20261020 and 20261021 (opposite
circuit directions). The actual encounter is measured, not assumed from that
placement. The maximum run is 12 seconds; a crash/refusal/fault ends the case.

| Seed / case | Minimum AI–player center distance | Completed ticks / 2880 | Result, both versions |
| --- | ---: | ---: | --- |
| 20261020 head-on | 12.483 m | 2880 | Misses 30 m |
| 20261020 crossing-left | 11.488 m | 2880 | Misses 30 m |
| 20261020 crossing-right | 7.306 m | 2438 | Misses 30 m; AI terrain crash |
| 20261021 head-on | 12.325 m | 2880 | Misses 30 m |
| 20261021 crossing-left | 7.156 m | 2422 | Misses 30 m; AI terrain crash |
| 20261021 crossing-right | 11.384 m | 2880 | Misses 30 m |

Every single-intruder case has an identical complete-run or failure-prefix
state/command digest before and after the repair. These failures predate the
repair. The raw [baseline](baseline/report.json) and [candidate](candidate/report.json)
reports retain failures, finite-state metrics, first avoidance tick, control peaks,
clearance, bank and source identities. Their 10 Hz `trajectory.csv` files retain
positions and held demands. Process exit 1 for both surveys is an unresolved
flight gate, not a passing check or an engine parse error.

The seventh case deliberately starts inside the margins: a co-moving player
29 m to the right at 35 m altitude, and a stronger companion threat 9 m below.
Observations are player first, then peer. This is a constructed selection fixture,
**not an admissible production spawn**.

| Constructed two-threat fixture | Baseline | Corrected |
| --- | ---: | ---: |
| Initial altitude target | 25 m | 35 m |
| Completed ticks / requested 2880 | 995 | 2880 |
| AI terrain crash | At 4.146 s | None in 12 s |
| Minimum AI–player distance, common first 995 ticks | 17.213 m | 11.638 m |
| Minimum AI–peer distance, common first 995 ticks | 8.392 m | 8.563 m |
| Minimum AI–player distance over each entire run | 17.213 m | 7.731 m |

The repair removes the stale descent and the crash in this fixture. It does
**not** improve every separation measure: player clearance is worse, even over
the common window. Choosing one strongest threat does not establish a safe
response to all traffic. The corrected fixture repeats exactly through all 2880
ticks. The baseline repeats the same crash-prefix digest, but its report correctly
keeps `exact_state_command_match=false` because that field also requires valid,
complete flights.

## Recorded baseline and replay

Both fixture versions retain `parallel-two-threats-{ai,player,peer}.orfl` with
start/end markers and individual SHA-256 values in their reports. All six streams
passed the existing exact-replay tool: `status=ok`, `mode=exact`, `complete=true`,
`solver_changed=false`. The baseline streams contain 996 rows (initial state plus
995 ticks); corrected streams contain 2881. Complete log closure does not mean
the requested baseline flight completed successfully.

Replay reports and every-tick CSVs are under each version's `replay-ai`,
`replay-player` and `replay-peer`. The player and peer replay CSVs match byte for
byte over the entire baseline prefix. The AI's closed-loop demands and trajectory
change. Replaying the baseline AI tape again with the corrected pilot installed
also yields the identical CSV (`baseline/replay-after-pilot-change`). The replay
does not run AI guidance: it proves unchanged physics for the same recorded input
tape, not equivalence of different closed-loop decisions or physical realism.

## Identities and reproduction

The original pilot is recoverable from commit
`a6524e3fd517898b8c8adac6210e20a58a989729`, path
`app/ai/companions/pilot.gd`, Git blob
`126e3496336bd7b079cd3e3e1a7ac4798c1ced29`. Its raw SHA-256 is
`6450514705530245d9fe607b6f712380c0e281cc7d7d2d4833a7f32654e5eade`.
The corrected pilot SHA-256 is
`51ccb3cdec3a4c898277c1b30542131c9938841dbde9debc0e45bf24601db1b3`.

Both surveys used probe SHA-256
`c2b5ddbd0c1b41451c37cfaa7be5dde4f8d0a5107b8ef0f50b35dfe9ff883b87`.
After the captures, the probe gained one early `return` after refusing an existing
output directory; flight logic is unchanged. The retained expected-refusal check
exits 2 before session setup. Do not overwrite or relabel the failed captures.
Removing that single return reconstructs the executed probe bytes exactly;
`verification.json` checks the resulting hash against both captures.

From the repository root, with a **new** absolute output directory:

```powershell
python tools/godot/run_checked.py --label companions-encounters --timeout 300 --require-text "COMPANION ENCOUNTER SURVEY COMPLETE" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/encounter_probe.gd -- --out=C:/captures/companions-encounters-new
python tools/flight_log/flight_log.py replay C:/captures/companions-encounters-new/parallel-two-threats-ai.orfl --out C:/captures/companions-replay-new
```

The survey currently fails its flight gate as above. Repeat replay for the player
and peer streams. For an older pilot, use a disposable checkout at the recorded
commit, or supply an explicitly preserved `res://` script with `--pilot=...`;
do not replace the live qualified source merely to reproduce a failure.

## Remaining AFC-04 work

Before runway behaviors or higher counts, retain logs for the two failing
crossings, diagnose the control/recovery path, and compare one candidate at a time
against those tapes and this closed-loop survey. Add an overhead-traffic case
while the clearance recovery guard is active. Evaluate reachable bank/climb
responses against every threat and terrain, including reaction margin, maneuver
hold and release hysteresis; preserve deterministic tie/yield behavior. Require
crash-free recovery after the encounter, explicit separation evidence and the
existing circuit regression matrix. Do not retune aircraft physics to pass AI
tests. The phase's multi-seed endurance, trajectory containment and performance
acceptance remain separate open gates.
