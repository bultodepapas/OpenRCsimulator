# CR-22c-R2 — Avoid repeated contact presentation work

2026-10-14. Godot 4.7.2 `ed1daf0bf`, Windows. This follows
[R1](../CR-22c-R1/README.md). No solver, aircraft data, crash threshold or golden
flight changed. The full CR-22c frame-time and distance/class matrix remains open.

## Changes and decisions

- **Accept: consume soft contacts once per simulation tick.** Previously a contact
  marked `new` emitted another scuff, ground mark and audio event on every render
  update until the contact feed advanced. Holds did not suppress it. The director
  now skips paused/held feedback and already-consumed ticks. Empty feeds, backward
  ticks and explicit reset clear the relevant presentation state. An unseen contact
  waits for resume; reset permits another contact at the same tick.
- **Accept: cache wreck shadow inputs in the fixed 24-slot pool.** Exact world
  transforms and box sizes guard projection math and renderer writes. This is not
  a sleeping-body shortcut: frozen teleports, rotation, parent movement and shape
  changes refresh the shadow. Hiding, reset and preparation invalidate it.
- **Accept: calculate obstacle distance once per sorting candidate.** The existing
  range filter, distance formula, ID tie-break, 160-body limit, ordering, shapes,
  collision layers and independent materials remain unchanged. Both airplane and
  helicopter wreck callers use this utility.
- **Discard here:** replacing the range filter with the spatial nearby query
  (different selection geometry), sharing mutable physics materials (unneeded
  ownership change), and skipping shadows merely because bodies sleep (stale
  teleports). Distance LOD and broader effect-budget changes need separate evidence.

## Measurements

Manual microsecond timing follows Godot's
[CPU optimization guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html).
These are bounded CPU experiments on a shared host, not isolated GPU profiling or
FPS acceptance. Our Godot processes ran sequentially; other work could use the host.

The production wing-brush regression makes 12 render updates without advancing
simulation. Reference: **16,483 µs** and repeated scuffs/marks/audio. Candidate:
**47 µs**, no repeats. This is one diagnostic burst, not a latency distribution.
The regression fails 8 of 23 checks against the reference and passes all 23 with
the change; both preserve the solver checkpoint. See `soft-latest-*.log`.

Shadow benchmark: 16 alternating-order pairs per scenario, 300 updates of 24
slots per sample. Median µs per complete 24-slot update, headless:

| Scenario | Reference | Candidate |
| --- | ---: | ---: |
| Stationary visible | 72.44 | 30.49 |
| Moving | 86.01 | 82.07 |
| Hidden | 16.65 | 17.67 |

Stationary work fell 58%; hidden-slot invalidation adds about 1 µs per pool scan.
2,400 changing projections compare visibility, transform and opacity exactly,
including rotations, heights beyond the fade cutoff, hiding and shape/parent
changes. See `shadow-bench-final.json` and `.log`.

Scenery benchmark: the actual 4,980-proxy world, five impact locations, 12
alternating-order pairs per location in each of two runs. Median build time (ms):

| Location | Run 1 reference → candidate | Run 2 reference → candidate |
| --- | ---: | ---: |
| Vehicle | 21.332 → 17.303 | 34.079 → 22.944 |
| Building | 5.152 → 5.576 | 8.630 → 8.173 |
| Tree trunk | 9.382 → 7.916 | 11.298 → 9.080 |
| Lamp | 17.165 → 15.527 | 21.212 → 19.420 |
| Parked aircraft | 16.698 → 14.704 | 19.744 → 17.198 |

Keep the first run's building regression visible; host noise and allocation cost
matter. Four locations improve in both runs; the second run improves all five.
All **240 builds** preserve exact geometry, selection/order, layers and material
values, and leave the input world unchanged. The expected 160-body budget warnings
are retained. See `scenery-bench*.json` and logs. These costs exclude tree insertion
and do not establish the complete crash-frame cost.

The checked-in reproduction runner also passed with native OpenGL. Its stationary
shadow median was **50.64 → 20.08 µs** per pool update; moving was 57.81 → 57.08 µs,
hidden 11.40 → 11.90 µs. Scenery medians (ms) were vehicle 16.448 → 13.342,
building 3.596 → 3.936, tree trunk 6.334 → 5.657, lamp 14.903 → 13.172 and parked
aircraft 14.754 → 13.075. All output comparisons passed. The building case again
regressed slightly; this change is accepted for the larger nearby sets, without
claiming uniform improvement. Raw data, logs and runner identities are in `native/`.

## Verification and reproduction

All five changed/new GDScript files parse. Accepted checks:

| Check | Result |
| --- | --- |
| Soft-contact regression | 23/23, headless and native OpenGL; 23/23 repeated in the working tree |
| Shadow lifecycle | 11/11, headless and native OpenGL; 11/11 repeated in the working tree |
| Wreck surface sliding/rebound | 10/10 |
| Crash effects | 60/60 |
| Prop strike, later crash, reset | 16/16 |
| Five production scenery crash kinds | 56/56 |
| All eight airplane configurations, effects on/off physical checkpoints, crash/reset/reuse | 152/152 headless and 152/152 native OpenGL |

Native runs use NVIDIA RTX 3090 / driver 610.88, Compatibility. Audio is Dummy in
both modes, so the additional real-audio integration checks are not counted.
The eleven accepted test logs contain no engine/script errors, failed checks or
leak reports. `test_*.log` records the individual results. A separate read-only
review found no concrete lifecycle or selection correctness concern.

Sources and engine identity: `manifest.json`; original snapshot source hashes:
`snapshot-sources.json.gz`. The three original runtime files are retained as
`*-reference.gd.gz`. Final runtime/test hashes override the initial snapshot hashes.
Reference/candidate timing rows use variants 0/1. Independent checks run against
the frozen imported project, with only the accepted presentation/test overrides.

Run focused tests on an imported app with:

```text
godot --headless --audio-driver Dummy --path app --script res://tests/test_soft_contact_feedback.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_wreck_shadow_cache.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_landscape_runtime.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_crash_integration.gd
```

Drop `--headless` for rendered checks. Timing reproduction (new output directory;
also accepts `--native`):

```text
python research/crash-damage/cr-22c-r2/run.py --godot PATH_TO_GODOT --app app --out tmp/crash-r2-repro
```

To reproduce the negative soft-contact control, use a disposable imported app,
replace only `render/crash/director.gd` with `director-reference.gd.gz` decompressed,
and run the final soft-contact test. Do not overwrite an active working tree.

The soft-contact fixture retains its pre-existing colinear-camera warning and
aircraft inertia warning in both variants. Audio event assertions track the
procedural audio RNG; the tests use the Dummy audio device and are not listening
acceptance. Rendered fleet tests establish integration, not visual quality or zero
stutter. No full application/CI suite or physical validation is claimed here.
