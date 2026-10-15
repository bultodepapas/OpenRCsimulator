# CR-22c-R3 — Stop scanning resting chips

2026-10-15. Windows, Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL, RTX 3090 /
driver 610.88. Follows [R2](../CR-22c-R2/README.md). Presentation only: no flight
solver, aircraft data, crash thresholds or golden flights changed.

## Accepted change

`effects.gd` previously scanned every chip on every update until 12 seconds even
when all had settled. It also reassigned every particle clock on every update and
recomputed identical gravity/drag terms for each moving chip.

The chip loop now latches rest once every chip meets the existing rest predicate.
Start/reset initialize that state. Gravity/drag are calculated once per update,
with the same arithmetic order. Particle clocks change only when pause changes;
reset still explicitly restores every clock. No particles or visible chips are
removed. The energy timeline continues after chips settle, preserving delayed
battery venting, flare, fade and fuel exhaustion.

Rejected for this slice: turning off the entire update when chips settle (would
lose delayed energy effects), approximate rest thresholds, and extra per-chip
active-list bookkeeping. Existing thresholds and array order are retained.

## Evidence

The original and candidate run together with the same seed and inputs. Ten
class/energy combinations cover classes 0–4, fuel flash and delayed vent/flare,
pause/resume, reset/reuse, and varying deltas including zero, negative and values
above the existing clamp. **18,000 exact state comparisons pass per renderer**:
chip positions, velocities, rotations/spins, RNG state, age, energy strengths,
light, emitter states and rendered MultiMesh buffer. Headless does not expose a
meaningful rendered buffer; native OpenGL supplies that comparison. Private
chip state is compared in both modes.

CPU microbenchmark: 16 alternating AB/BA pairs per scenario; each sample calls
`update(0, paused)` 1,200 times to hold the workload constant. Settled cases first
advance naturally for 10 seconds and assert that every chip has zero velocity.
These are script-call costs, excluding engine particle stepping and GPU frame
time. Timing follows Godot's [manual CPU measurement guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html).
Our processes run sequentially on a shared host; this is not an isolated hardware
or frame-rate acceptance test.

| Scenario | Headless reference → candidate (µs/call) | Native reference → candidate (µs/call) |
| --- | ---: | ---: |
| Airborne chips | 91.589 → 88.490 | 97.324 → 93.696 |
| Settled chips before cutoff | 16.363 → 3.121 | 15.506 → 3.335 |
| Paused | 1.284 → 0.528 | 1.173 → 0.512 |
| Inactive | 1.222 → 0.508 | 1.204 → 0.500 |

Native settled-call CPU cost fell about 78%; the absolute saving is about 12 µs.
This does not establish higher FPS or eliminate the residual crash-frame spikes.
Raw pairs: `headless.json`, `native.json`; reference/candidate are variants 0/1.

## Regression checks

- Effects lifecycle: **66/66** headless and native, including rest before cutoff,
  retained chip poses, delayed battery effects, repeated pause and a fresh crash.
- Shader warmup/fade lifecycle: **18/18**.
- Presentation ladder and fleet palettes: **43/43**.
- Helicopter crash presentation: **44/44**.
- Final native fleet integration: **179/179**, all eight airplane configurations,
  including paired physical checkpoints, crash holds, resets and pool reuse.

An initial native fleet run failed one exact tick-100 arrival assertion for the
Avanti; its paired physics checkpoints still matched. The same test passed all
179 checks with `--fixed-fps 60`. Inspection found two uncontrolled conditions:
the coroutine could resume after catch-up ticks passed its target, and native
window focus loss intentionally pauses the production simulation. Adding only a
stop boundary still failed the arrival assertion on the 55AX (`fleet-native-bounded.log`).
The fixture now uses `stop_at_tick` for both sessions, explicitly resumes them
during only the controlled healthy-flight phase, then restores their old limits.
Crash hold/pause assertions remain intact. This changes the test, not production
focus handling or stepping. The initial failed log is retained as
`fleet-native.log`; the fixed-FPS control is `fleet-native-fixed.log`.
The final fixture passes without fixed FPS (`fleet-native-final.log`).

## Reproduction and identity

`manifest.json` records baseline Git identity, engine and final source hashes;
`reference.gd.gz` preserves the pre-change effects. No dependencies were upgraded.
The checked-in runner was also executed against the final working tree with native
OpenGL: another 18,000 comparisons passed (`reproduction/`). Accepted final logs
contain no engine/script errors or leak reports. Earlier failed fleet controls
remain explicitly separate above.
Run on an imported project with a new output directory:

```text
python research/crash-damage/cr-22c-r3/run.py --godot PATH_TO_GODOT --app app --out tmp/crash-r3-repro --native
godot --path app --audio-driver Dummy --script res://tests/test_crash_effects.gd
godot --path app --audio-driver Dummy --script res://tests/test_crash_integration.gd
```

Omit `--native` for the headless comparison; add `--headless` to standalone tests
for headless checks. Tests use Dummy audio and do not establish listening quality.
Existing aircraft-data warnings remain. Full CI, physical validation and a full
distance/class performance matrix are outside this slice.
