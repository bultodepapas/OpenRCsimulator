# AFC-00…06: experimental airborne integration

Date: 2026-10-20. This is software integration evidence for the
[current companion guide](../../../AI-FLIGHT-COMPANIONS.md), not physical
validation or completion of Phase 0/1's full release gates.

## Implemented boundary

One full FlightSession/VehicleModel per AI. The player's original automatic driver
is preserved. All pilots receive detached states from before the same player tick;
only a successful player step advances them. Control decisions run every fourth
240 Hz tick; the held normalized packet is validated/staged again on every tick.
No kernel branch or physics coefficient was changed.

The first roster contains 1–3 Ugly Stiks in north-side circuits. It starts only at
tick zero. The player remains the only scenery-damage author; companions receive
its committed mask after finishing the common tick. Failed/crashed agents stop
individually and are bounded by the fixed roster; restart/removal clears them.
Airplane-to-airplane contact and shared fleet replay are not present.

Home and Pause use the existing screen stack and holds. Preferences are additive,
default Off and isolated from direct launches. Pause changes apply on restart;
Save as default is explicit. A failed settings save restores the prior flight
draft. Main refuses player-only paired checkpoints while companions remain.

## Player preservation

Before the session seam, `baseline.orfl` recorded 2,400 physics ticks with one
bounded roll tape. `baseline-exact.json` records successful exact replay under its
original solver source:

- Solver: `db936a40c0a1be297a3ed910823083ef9613f5e8528f58607980bd93355582ff`.
- Aircraft: `5ef239c6c0470d6870bf72656cfb12795833764b0bd57c7d93bc17f790bd2007`.
- `complete: true`; `solver_changed: false`.

`session-candidate.json` reruns the same tape and aircraft under the session seam:
`complete: true`, `solver_changed: true`. It is a solver-source candidate comparison,
not exact replay of the old source. `session-comparison.json` reports **no numerical
divergence across 2,401 rows**. Both exported CSVs were byte-identical, SHA-256
`8ea8bfa954ef93a2d8d42a93dbb009dc6878223ca2d5d0396604b4424ea5b6c4`;
one copy is retained as `player-tape.csv`.

Additional automated parity checks compare all accepted state, previous state,
auxiliary/continuous values, modes, inputs and loads for 10,000 ordinary versus
external-driver ticks. A separate 240-tick player tape produces identical player
state/aux/input bytes with and without three companions.

## Checked tests

The checked runner rejects Godot script/engine errors even when its process exits
zero. Successful runner reports/logs are retained under `checks/`.

| Check | Result/scope |
| --- | --- |
| `test_companions_config.gd` | 22 checks; bounds, unsupported choices, CLI overlays and missing/duplicate values |
| `test_companions_session.gd` | 42 checks; atomic packet validation, explicit driver, absolute spawn heading, holds and damage seam |
| `test_companions_manager.gd` | 43 checks; 10k parity, 240-tick player preservation, deterministic launch, one tick, refusal, damage publication and cleanup |
| `test_companions_pilot.gd` | 24 focused controller/configuration/encounter checks; long flights run separately |
| `test_companions_dialog.gd` | Keyboard/controller navigation, malformed seed, draft/Cancel, status and Remove |
| `test_companions_shell.gd` | Home persistence, live three-agent flight, Pause freeze, next-restart rebuild to two, save rollback, removal and direct-route isolation |
| Existing start-choice and aircraft-contact suites | 36 and 63 checks respectively |
| Existing session guards and flight-log suites | 32 and 3,247 checks respectively |
| Existing Home UI and full project parser | Passed; one existing unsupported tree-material warning in the UI run |

The existing Pause suite has one unresolved audio assertion: it expects the legacy
generator's `stream_paused` flag even though the current soundscape owns playback.
Its measured output was silent at −200 dB, and the remaining Pause/lifecycle checks
passed. Companions were disabled in that test. The failed report/log is retained;
this is not a claim that the complete application suite passes.

The rotorcraft CLI refusal probe deliberately exits `ERR_INVALID_PARAMETER` (31).
Its expected diagnostic was present and there were no engine errors; the generic
runner records that nonzero exit as `process_exit`, not a passing invocation.

The long [pilot matrix](../pilot/README.md) owns the calm/gentle 120-second scenarios,
observed flight envelopes and repeatability receipts. Short encounter tests show
bounded avoidance responses; they do not establish collision avoidance against
every player maneuver.

The external-driver matrix exposed a spawn integration bug: requested absolute
heading had been added to the trimmed start's existing heading. The corrected
spawn replaces heading while preserving trim pitch/roll. A regression uses a
nonzero original trim heading and checks attitude, velocity alignment and reset
identity. Pilot gains, the 40 m radius limit and aircraft physics were unchanged.

## Preliminary complete-callback costs

Host: Windows, AMD Ryzen 9 5900X, Godot 4.7.2-stable official. Native captures use
Compatibility/OpenGL on an RTX 3090. Two headless cost runs include the full Club
collision inventory, session guards, player solver, fleet snapshots, AI and AI
solvers. They exclude rendering, audio and real-time pacing. Each case warms up
240 ticks and measures 2,400 ticks. These are short local development measurements;
other workspace tracks were active, so they are not an isolated target-host lab.

| Companions | p50 tick, run 1 / 2 | p95 tick, run 1 / 2 | Mean tick, run 1 / 2 |
| --- | --- | --- | --- |
| 0 | 0.798 / 0.777 ms | 1.163 / 0.866 ms | 0.847 / 0.790 ms |
| 1 | 1.651 / 1.690 ms | 2.112 / 2.416 ms | 1.719 / 1.787 ms |
| 3 | 3.417 / 3.518 ms | 4.057 / 7.273 ms | 3.509 / 4.154 ms |

Both reports use the corrected absolute heading, are complete, and all aircraft
advanced every measured tick. The two three-aircraft runs have substantial tail
variation on this shared host; retain both rather than selecting the faster run. **The
2 ms p95 fleet target is not met**, including the one-companion case in these runs.
The off baseline also misses the existing 500 µs player target. Do not infer 60 fps
from these numbers. The controls explicitly label this an experimental slice,
recommend starting with one, and refuse counts above three. Physics stays at
240 Hz. Larger presets, automatic admission, renderer LOD and production
performance acceptance remain pending.

## Render inspection

`captures/` contains native 1280×720 Home/Pause settings, the pilot view and an AI
model closeup. The closeup changes only the inspection camera; it renders the
production builder at the accepted simulated CG/attitude. The capture fixture uses
isolated preference/controller paths, suppresses test input devices and confirms
companions have accepted at least one tick. This is visual inspection, not a
rendered frame-time or acoustic calibration result.

## Reproduce

From the repository root, use the pinned engine and checked runner:

```powershell
python tools/godot/run_checked.py --label companions-manager --timeout 180 -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_companions_manager.gd
python tools/godot/run_checked.py --label companions-cost --timeout 180 -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/ai-companions/cost_probe.gd -- --out=../tmp/companions-cost.json
python tools/godot/run_checked.py --label companions-capture --timeout 180 --require-text "COMPANION CAPTURES COMPLETE" -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/ai-companions/capture_companions.gd -- --out=../tmp/companions-captures
```

Outputs must be new paths. Run the long pilot matrix using its own documented
command. Baseline exact replay needs its recorded original solver source; current
source must use the candidate comparison workflow in
[flight logging](../../../FLIGHT-LOGGING.md). `source-receipt.json` pins the
implemented inputs for this evidence; concurrent unrelated commits are not a
substitute for those file hashes.

Open gates: full Phase 0/1 parity/contact regimes, profile/weather/seed coverage,
long-session fuel management, 50-cycle/20-minute resource soak, rendered pacing,
fleet replay, pilot review, translations, clean exports and platform packages.
All runway, multi-model, advanced activity, incident and busy-skies phases remain
pending in the active plan.
