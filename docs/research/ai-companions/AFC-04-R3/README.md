# AFC-04-R3 — wind-aware reachable-turn avoidance evidence

2026-10-20, native Windows Godot 4.7.2. This evidence evaluates the research
candidate [`reachable_pilot_r2.gd`](../../../../research/ai-companions/avoidance/reachable_pilot_r2.gd),
SHA-256 `1c512e4bdc0c606cc575397dfe8e1d6fe3e8bf6b9bc0894bd20ce11366d47eb8`.
The candidate predicts a banked turn from air-relative velocity and adds wind to
the resulting ground displacement. It keeps the production pilot as its parent
and leaves the no-traffic command path unchanged. It was not promoted to
production during these runs.

The runs used the isolated `tmp/afc04-isolated` mirror at commit
`2966595b1f243be3905e2699b71c0283195ae306`, with its `app/.godot/imported`
junction to the main imported cache. The candidate, parent pilot, pilot probe
and each encounter probe matched their retained SHA-256 identities. The calm and
gentle surveys used the same validated Stik/Club world, collision inventory and
lake as their reported context. [verification.json](verification.json) binds
these identities, the copied artifacts and the exact mirror world IDs.

## Flight results

The 148-check pilot matrix passed with zero failures. Its calm and gentle
120-second one-, two- and three-companion circuit runs completed all requested
ticks without refusal, crash or simulation fault. The seeded three-companion
calm replay matched its sampled state and command trace. Detailed outputs are in
[`pilot-matrix/`](pilot-matrix/).

Each 60-second encounter survey completed all 14,400 requested ticks. Physics ran
at 240 Hz and planning at 60 Hz. Every one of the six nominal route-intercept
cases stayed at least 30 m from the player in both weather presets:

| Seed / intercept | Calm minimum | Gentle-practice minimum |
| --- | ---: | ---: |
| 20261020 head-on | 61.090 m | 60.971 m |
| 20261020 crossing-left | 65.433 m | 65.615 m |
| 20261020 crossing-right | 41.336 m | 49.203 m |
| 20261021 head-on | 60.781 m | 61.395 m |
| 20261021 crossing-left | 58.465 m | 58.091 m |
| 20261021 crossing-right | 65.767 m | 65.808 m |

All six route cases completed without AI crash, fault or refusal. Their minimum
observed separation was 41.336 m in calm and 49.203 m in gentle-practice.

The calm R1 and R2 survey `trajectory.csv` files are byte-identical (9,015 rows,
SHA-256 `c28ff520cfcc4462df61db5a66b5754512670c23d9472120de50549303e3b5e3`).
The R1/R2 120-second matrix `flight_samples_1hz.csv` and `scenario_metrics.csv`
are also byte-identical; they match the retained
[AFC-04-R2 circuit-matrix files](../AFC-04-R2/circuit-matrix/README.md).
The R1 calm report and raw trajectory used for this comparison are in
[`r1-calm-comparison/`](r1-calm-comparison/).

The seventh, constructed `parallel-two-threats` fixture is reported separately.
It begins in an already-conflicting state: about 29 m from the player and 9.0 m
from the peer in calm, and 29 m / 8.21 m in gentle-practice. It completes without
a crash, but fails the 30 m player-separation gate. This fixture is not a valid
spawn or evidence against the six admitted route cases.

The complete survey reports, 10 Hz trajectories, runner logs, and deterministic
repeat data are retained in [`calm-survey/`](calm-survey/) and
[`gentle-survey/`](gentle-survey/). The overall survey gate remains marked false
because the constructed fixture is intentionally invalid at spawn.

## Static path and predictor diagnostics

The promoted static-trajectory helper checked each observed AI polyline against
the matching mirror collision world, terrain, lake, aircraft envelope and
protected footprints. All seven paths were clear in both surveys. Each 601-point
trajectory had a minimum reported terrain margin of 12.692 m in calm and
12.724 m in gentle-practice. The checker used a caller-supplied 0.5 m allowance
for geometric interpolation between the 10 Hz points.

That allowance does not bound controller tracking error, predictor error, or the
unobserved 240 Hz curve. The static check is a post-hoc geometry diagnostic, not
a maneuver-containment or safety certification. Its exact context and results
are in each survey's `static-path-clearance.json`.

Per-plan predicted threat distances were compared with synchronized piecewise
linear tracks, stopping at the next plan change/release and using the forecast's
0.25 s sample points. Calm produced 523 comparisons with prediction-minus-actual
distance residuals from −5.532 m to +0.673 m. Gentle-practice produced 562, from
−6.882 m to +0.991 m. These observed residuals include aircraft response and
10 Hz path reconstruction; they are neither a worst-case bound nor a safety
margin. The probe does not record the complete own-aircraft prediction state,
so own-position forecast error remains unmeasured.

The residuals are retained in each survey's
`predictor-vs-flown-per-plan.json`. The [analyzer](../../../../research/ai-companions/avoidance/analyze_reachable_plans.py)
and its [three synthetic tests](../../../../research/ai-companions/avoidance/test_analyze_reachable_plans.py)
remain under `research/ai-companions/avoidance/`. Static path assessment used the
[promoted checker](../../../../app/ai/companions/static_trajectory.gd) through a
research-only harness.

## Recorded route-intercept crossings

The production pilot and R2 candidate were also recorded for two fixed 20-second
crossing fixtures. The candidate completed both without crash, fault or refusal,
with minimum player separations of 59.820 m and 58.465 m; the production
baseline minima were 4.127 m and 3.860 m. All 12 baseline/candidate ORFL streams
replayed in exact mode with unchanged solver identity. The player tapes match
byte-for-byte between controller runs. The fixtures disable production spawn
admission and do not establish that gate. Full metrics, raw-file locations,
hashes, and replay details are in [`crossings/`](crossings/README.md).

## Scope and pending gates

These results support the narrow six-route, 60-second separation gate for this
Stik/Club candidate in calm and gentle-practice weather. They do not close the
plan's 20-minute endurance, general recovery, continuous containment, callback
cost or target-renderer gates. No physics, profile, scenery or golden-flight data
was tuned. The 120-second matrix is correctness evidence, not a performance
measurement.

Exact `.orfl` replay validates the recorded commands against the unchanged
solver; it does not run the AI controller. The intentionally conflicting
two-threat spawn remains separate from the valid six-route survey. See
[AFC-04-R2](../AFC-04-R2/README.md) for prior crossing evidence and
[AFC-12-R2](../AFC-12-R2/README.md) for the reusable static trajectory checker's
contract tests.
