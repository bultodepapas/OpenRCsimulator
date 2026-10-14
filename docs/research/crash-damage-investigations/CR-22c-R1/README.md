# CR-22c-R1 — Crash and pre-impact stutter

2026-10-14. Native Windows, Godot 4.7.2 `ed1daf0bf`, Compatibility/OpenGL 3,
NVIDIA RTX 3090 / driver 610.88, 1280 × 720, 60 FPS cap. Presentation optimization;
no solver, crash threshold, aircraft data or golden-flight changes.

## Cause and change

Two distinct costs were isolated. A later FS64V trial spent **197.282 ms inside a
single `AirframeScuffs.add()`**, before the terminal crash; the frame took 260.33 ms.
The original scuff code enumerated mesh faces and intersected triangles repeatedly
in GDScript, including 18 projected grid points with edge retries. Warmed particles
alone therefore did not fix every hitch.

Scuffs now prepare one native `TriangleMesh` BVH per eligible mesh resource when
loading the selected aircraft. Contacts query those trees using live transforms
and visibility. Millimetre coordinates retain the original small-triangle
precision. Grid shape, edge retries, attachment, colours and the 24-mark cap are
preserved. Reset retains the geometry cache; replacing the aircraft bounds its
lifetime, replacing a mesh prunes stale entries, and `Resource.changed` invalidates
in-place edits. The texture is also prepared before contact. The implementation
uses Godot's [TriangleMesh API](https://docs.godotengine.org/en/stable/classes/class_trianglemesh.html)
and [native BVH traversal](https://github.com/godotengine/godot/blob/4.5/core/math/triangle_mesh.cpp).


The first exploratory impact blocked a frame for 142–459 ms across the eight
airplane configurations. Director setup took only 4–9 ms, including 1–4 ms in the
already pooled wreck. Most repeat impacts were near 18–20 ms. This separates the
dominant first-draw cost from synchronous breakup creation. The exploratory
manufactured contact also moved the camera abruptly; those numbers are diagnostic,
not the accepted flight comparison below.

Godot's Compatibility renderer needs real draws to prepare shader variants;
loading resources or creating hidden pools does not do that. See the
[official stutter guide](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html)
and [pipeline guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html).
Rendering the crash draw paths during setup substantially reduces the first-impact
stall. This is evidence for first-use rendering work, not a driver-level trace
attributing every millisecond to shader compilation.

- `shader_warmup.gd` submits disposable samples of the actual particle meshes and
  materials, chips, ground marks, airframe scuffs and wreck contact shadow in an isolated 64 × 64
  viewport. It uses the flight environment, MSAA and sun, with/without a fire light.
  Two synchronous `force_draw(false)` calls finish during setup without swapping
  the window buffers. Temporary nodes are freed immediately. The live pools,
  simulation, camera, audio and random seeds are unchanged. Headless and other
  renderers skip this Compatibility-specific work.
- `Effects.start()` previously called `restart()` on every emitter, then stopped
  the unwanted ones. Restart immediately activates CPU particles; stopping emission
  does not undo already emitted particles. It now starts only applicable effects.
  Delayed battery venting and gasoline fire start on demand; existing particles
  still fade after emission stops. See the
  [engine implementation](https://github.com/godotengine/godot/blob/4.7-stable/scene/3d/cpu_particles_3d.cpp)
  and [particle API](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html).

The warmup moves first-use work into flight setup; it does not make compilation
free. Its `usec` statistic includes forced viewport submissions, including work
that the ordinary first frame would otherwise perform. It is not an isolated
increment in loading latency.

## Accepted protocol

The project was frozen from the actual dirty working tree, with its imported
resources and manifest authoring dependencies. `sources.json.gz` records its
source identities. Only crash presentation differs between variants. The original
director/effects/scuffs are retained as compressed source for reproducing the reference.
Stage timing instrumentation is applied equally to both variants, outside pinned
aircraft builders. No background Godot benchmark was run concurrently by this task.
The host is shared; driver caches were not cleared. Other tracks ran headless
checks during earlier diagnostic trials; `diagnostics/concurrent-processes.json`
records one such overlap. No other Godot process was present at a mid-matrix check
of the final comparison. This is not a controlled hardware laboratory run.

Each aircraft gets a fresh process per variant, alternating reference/candidate
order across the fleet. After the camera settles above the impact site, the real
240 Hz solver flies a descending state into the ground. Inputs are disabled. Two
crashes per process exercise reset and warmed reuse. This is a synthetic initial
condition through the production solver, not a physical drop validation.

Frame intervals come from `process_frame` wall timestamps. The impact window
includes one preceding interval, the detected-impact interval and seven following
intervals: the director runs after the signal, so its first rendered frame must
not be omitted. First-motion initialization and capture readback are excluded.
Every raw result retains all 90 intervals, impact index, physical state, class,
setup/first-draw times and subsystem durations. Timing is not an automated pass/fail
test on shared hardware. Soft-contact presentation sampling depends on render
cadence, so paired flights can emit different counts of pre-impact scuffs despite
identical terminal solver states. The separate 32-contact geometry comparison
uses identical contact inputs to isolate that CPU improvement.

Paired final native runs (maximum interval within each impact window):

| Aircraft | First: reference → candidate (ms) | Repeat: reference → candidate (ms) |
| --- | ---: | ---: |
| gp-extra-300s-60 | 134.5 → 42.7 | 22.5 → 47.2 |
| jensen-das-ugly-stik-60 | 130.1 → 84.6 | 229.5 → 27.4 |
| p51d-mustang-120 | 76.8 → 33.4 | 33.5 → 50.0 |
| sebart-avanti-s-a200-p100rx | 89.7 → 42.2 | 66.6 → 17.2 |
| stik-glow-55ax-2t | 95.8 → 63.0 | 230.2 → 58.5 |
| stik-glow-61fx-2t | 112.8 → 63.8 | 57.2 → 30.2 |
| stik-glow-fs64v-4t | 88.6 → 58.5 | 61.9 → 30.8 |
| turbo-lumber-evolution | 37.1 → 35.8 | 29.3 → 52.7 |

The median first-impact peak across the eight configurations changed from
**92.8 to 50.6 ms** (45.4% lower). All 16 reference/candidate
terminal solver states and severity classes match exactly; every post-impact
checkpoint remained unchanged. These are individual shared-host trials, not
confidence intervals. Repeat results include regressions; the table retains them.
Raw intervals and CPU timings are in `measurements/`; `summary.json` also retains
setup and first-draw costs. The original 16-run warmup-only matrix is retained as
`diagnostics/summary.json`; its large repeated-contact spikes motivated the BVH fix.

The separate **32 identical scuff contacts** across the same fleet isolate CPU
work: median **31.965 → 1.439 ms**, maximum **242.674 → 3.832 ms**. BVH preparation
took 12.4–146.6 ms per selected aircraft in that headless comparison. Every mark
kept the same parent; maximum vertex difference was 0.446 mm (Extra, near a tangent
projection), below the existing millimetre-scale fitting tolerance. An independent
triangle oracle found no reduction in vertices on the skin: 18/18 except the Stik
nose spring, 17/18 in both versions. See `scuff-parity.json` and `.log`. Local-space
and world-space float32 intersection arithmetic are not bit-identical.


## Verification and limits

Final candidate checks on the frozen imported snapshot:

- `airframe_scuff_cache`: airframe scuff cache: 18 checks, 0 failed.
- `airframe_scuffs`: US-V12 airframe scuffs: 14 checks, 0 failed.
- `soft_contact_feedback`: 12 checks, 0 failed.
- `crash_warmup`: 18 checks, 0 failed.
- `crash_effects`: 60 checks, 0 failures.
- `crash_presentation_ladder`: 43 checks, 0 failed.
- `crash_integration`: 152 checks, 0 failed.
- `crash_warmup-native`: 18 checks, 0 failed.
- `soft_contact_feedback-native`: 12 checks, 0 failed.
- `crash_integration-native`: 168 checks, 0 failed.

The two new tests also passed against the current working tree (18 checks each);
warmup passed with native rendering too. The soft-contact fixture emits the same
pre-existing colinear pilot-camera warning in reference and candidate runs; both
pass all 12 assertions (`checks/baseline-soft.json`). The original native fixture
also logged two GL texture-leak messages at shutdown; the final candidate fixture
logged neither. Exit codes alone were not used to classify clean runs.

Earlier focused checks also passed for wrecks, breakup, sections, fracture, masses,
wreck surfaces, audio, causes, poses, snapshots, proportional effects and severity
(`checks/checks.json`). The sections negative fixtures emit their expected warnings.
`test_crash_energy.gd` has **one existing failure out of 206 checks**: the newly
present `hx700_electric_3d_experimental.json` has no explicit energy-test category.
The original reference produces the identical failure (`checks/reference-energy.log`).
It is unrelated to this presentation change and is not hidden or fixed here.

Native capture runs are separate from timing runs because PNG readback stalls the
GPU. Stik and jet crash/reset images are in `captures/`. Visual inspection covered
Stik first-impact frames +8/+55 and jet first-impact +8 / repeated-impact +55:
dust, fragments and contact shadows remain visible; the fuelled jet retains fire.
No full `app/test.sh`, fresh
asset import, export, low-end-GPU qualification or physical validation was performed.


The change does not close the full CR-22c class/distance budget, low-end GPU or
export qualification. Scenery secondary-body construction remains a separate
impact-time path; this measurement matrix covers ground impacts. Gate CR remains
open, and no physical validation is claimed.

Discarded experiments: adding samples of every wreck mesh did not show a useful
additional improvement; warming the actual window by temporarily moving its camera
also did not justify the state mutation. The retained helper warms only bounded
crash-specific resources and leaves the active camera alone. Distance LOD and
reducing physical wreck sections are not necessary for this fix.

## Reproduce

Use an isolated imported checkout with matching aircraft manifests and dependencies.
Do not import or instrument an actively edited shared project for measurement.

```powershell
python research/crash-damage/cr-22c-r1/run.py --godot <Godot-4.7.2.exe> --project <snapshot/app> --out <new-output-directory>
```

The runner executes all eight airplane configurations serially and rejects engine
errors or changed post-impact simulation checkpoints. `--aircraft <catalog-id>`
narrows the fleet. Focused checks: `test_crash_warmup.gd`, `test_crash_effects.gd`,
`test_crash_energy.gd`, `test_crash_integration.gd` and the remaining crash tests.
Run the warmup, soft-contact and integration checks natively as well as headlessly.
`test_airframe_scuffs.gd` checks curved skin/hinges; `test_airframe_scuff_cache.gd`
checks invalidation, replacement, visibility, reset reuse and weak-reference cleanup.

For subsystem timings, first run `instrument.py --project <disposable-snapshot/app>`.
It refuses repeat instrumentation. Restore the three compressed reference scripts
in a separate matching snapshot for the baseline. `scuff_parity.gd` compares 32
contacts against an extracted `reference_airframe_scuffs.gd`:

```powershell
& <Godot-4.7.2.exe> --headless --path <snapshot/app> --script research/crash-damage/cr-22c-r1/scuff_parity.gd -- --reference=<original-scuffs.gd> --out=<results.json>
```
