# AFC-00-R1: AI companion cost attribution baseline

Date: 2026-10-20. This is a local headless software measurement for the
experimental one-to-three companion slice. It does not establish target-host
performance, rendered frame pacing, a 60 fps result, or physical validation.

## Method

The probe ran the production `FlightSession`, `Simulation`, companion manager,
agents and pilot. It used the default Club field, the production collision
inventory, lake context, calm weather, seed `20261020`, no visuals, no audio and
no real-time pacing. The pinned Godot 4.7.2-stable official console ran on a
Windows host with an AMD Ryzen 9 5900X.

Each case ran 240 warm-up ticks followed by 2,400 measured ticks at 240 Hz.
Cases ran serially for 0, 1, 2 and 3 companions. Every measured player and AI
tick was accepted. The report stores a bitwise SHA-256 state and command trace
for the player and each companion over every measured tick; packed simulation
state, prior state, auxiliary and continuous state, modes and loads feed the
state hash. Applied inputs and held AI command packets feed the command hash.

The timer buckets are exclusive. `player_session_guard` times the complete
player `FlightSession._physics_process` callback. `player_solver` is the
player `Simulation._physics_process` callback after subtracting the timed
manager `before_step` and `stepped` callbacks. It retains the solver, signal
dispatch and any other work in that callback. `ai_observation` delegates to
the production agent's `observation`; `ai_plan_prepare` delegates to the whole
production `prepare` call, including pilot planning when scheduled and per-tick
external command preparation; `ai_stepping` delegates to production `advance`.
`manager_overhead` is the remainder of the two manager callbacks after those
timed agent calls. The exclusive buckets sum to the measured player/session
callback duration. A separate envelope records the complete outer timing span
and the timer-wrapper gap.

Timed agent proxies add timer reads around delegated methods; they do not
change the method bodies or callback order. The checked report confirms zero
engine errors and a complete run. Godot printed its existing aircraft inertia
data warning during fixture setup.

## Results

The timing distributions and trace fingerprints are in
[`baseline-profile-valid.json`](baseline-profile-valid.json). The checked
runner report and raw engine log are under `checks/baseline-profile-valid-ccs77g17/`.

| Companions | Mean callback envelope | p50 | p95 |
| ---: | ---: | ---: | ---: |
| 0 | 1.177 ms | 1.216 ms | 1.500 ms |
| 1 | 2.630 ms | 2.692 ms | 3.164 ms |
| 2 | 4.838 ms | 4.288 ms | 7.925 ms |
| 3 | 6.042 ms | 5.800 ms | 7.931 ms |

Three-companion exclusive bucket means and p95s were:

| Bucket | Mean | p95 |
| --- | ---: | ---: |
| Player session guard | 129 µs | 153 µs |
| Player solver and signal work | 1,302 µs | 1,602 µs |
| AI observation | 121 µs | 157 µs |
| AI planning and command preparation | 155 µs | 480 µs |
| AI stepping | 4,301 µs | 5,582 µs |
| Manager remainder | 34 µs | 46 µs |

The largest measured cost at three companions is stepping their full AI
sessions. Observation is a smaller, direct opportunity: the manager refreshes
each observation at 240 Hz while `agent.prepare` calls `pilot.command` at 60 Hz.
The measured three-agent observation bucket averages 121 µs per global tick;
avoiding three unnecessary refreshes per four-tick decision period can save at
most about 91 µs per tick on this run, before timing variation. This is a modest
share of the 6.042 ms mean complete envelope. The pilot command packet must
still be prepared and validated and each AI session must still step at 240 Hz.

The 2- and 3-companion tails were noisy on this shared development host. Their
p95s exceed the earlier 4.1–7.3 ms preliminary range, so this one profile is a
captured baseline, not a stable host limit. Keep before/after runs on the same
machine and compare full samples, medians, p95s and trace hashes. The player
state and command fingerprints match across counts 0–3, and the companion
fingerprints are retained per count for candidate comparison.

The unqualified `baseline-profile.json` at this directory is an earlier probe
attempt with invalid empty-array hashing and an incorrect measured-tick count.
It is retained with its failed checked log for audit; use only
`baseline-profile-valid.json` as the accepted baseline.

## Candidate comparison

The post-optimization candidate used the same fixture, seed, pinned engine, serial
case order and 240 + 2,400 tick windows. The checked run completed with exit code 0,
`complete=true`, and zero diagnostics in the runner report. Godot printed the existing
aircraft inertia warning during fixture setup. Raw distributions, trace fingerprints,
profile identities and the runner log are in [`candidate-profile.json`](candidate-profile.json)
and [`checks/candidate-profile-o1qc8gwq/`](checks/candidate-profile-o1qc8gwq/).

| Companions | Baseline mean / p50 / p95 | Candidate mean / p50 / p95 |
| ---: | ---: | ---: |
| 0 | 1.177 / 1.216 / 1.500 ms | 1.256 / 1.196 / 1.827 ms |
| 1 | 2.630 / 2.692 / 3.164 ms | 3.087 / 2.766 / 5.368 ms |
| 2 | 4.838 / 4.288 / 7.925 ms | 3.634 / 3.819 / 4.760 ms |
| 3 | 6.042 / 5.800 / 7.931 ms | 4.951 / 5.102 / 6.465 ms |

These are single shared-host runs, not a stable speedup claim. The 0- and 1-agent
cases were slower in the candidate (mean changes +6.7% and +17.4%); the 2- and
3-agent means were lower (-24.9% and -18.1%). The original 2- and 3-agent p95s
were already noisy, and the 1-agent candidate had a high tail. Repeat measurements
are needed to separate implementation effects from host timing variation.

The candidate made 600 measured observation calls per companion in 2,400 ticks,
down from the 2,400 calls per companion implied by the baseline manager's every-tick
240 Hz refresh path. At three companions, the aggregate per-tick observation bucket
mean fell from 121 µs to 26 µs; the complete envelope mean fell from 6.042 ms to
4.951 ms. The candidate still prepared commands and advanced every companion on
every accepted physics tick. For each enabled roster case, the manager recorded
660 observation batches including 60 warmup batches and 600 measured batches.

Every player and companion state and command fingerprint matches the baseline
bit-for-bit for each 2,400-tick measured window, for all 0–3 companion counts.
`candidate-comparison.json` records every per-actor hash comparison and the before/
after bucket distributions. `candidate-source-receipt.json` records the candidate
capture and includes hashes for the profile loader, selected aircraft profile JSON,
and Club field profile JSON. The frozen baseline receipt remains
[`source-receipt.json`](source-receipt.json).

This evidence is limited to software timing and deterministic trace equivalence on
the measured host. It does not establish 60 fps, target-hardware performance,
rendered pacing, obstacle clearance, or physical validation.

## Reproduce

From the repository root, run the pinned engine through the checked runner and
choose a new output path for each capture:

```powershell
python tools/godot/run_checked.py --out-dir docs/research/ai-companions/AFC-00-R1/checks --label baseline-profile --timeout 600 --require-text "AFC PERFORMANCE PROFILE COMPLETE" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/performance_probe.gd -- --out=C:/captures/afc-profile.json
```

The baseline source and checked-run identities are recorded in
[`source-receipt.json`](source-receipt.json); candidate identities are in
[`candidate-source-receipt.json`](candidate-source-receipt.json). The earlier
AFC-00-06 complete callback reports remain separate captures; this profile adds
internal cost attribution and bitwise AI trace fingerprints.
