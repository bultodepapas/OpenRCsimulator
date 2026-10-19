# VQ-01c — automated flight and cloud/runtime follow-up

2026-10-19. Automated native flights reproduced the low ground FPS and a detached
storm-rendering error. Two presentation fixes are implemented. The isolated cloud
path uses less CPU; **an overall native FPS improvement is not established**.
Landing remains slow. All unfavorable runs and harness failures are retained.

## Repairs and boundaries

`StormBank.update_visual()` queried a camera through a null viewport while Home
constructed its World outside the scene tree. That script error interrupted
material initialization. It now handles the camera-free lifecycle, initializes
colors/fog and the origin periodic copy, then selects the real camera's copy after
attachment. It also supports detaching a retained World. The extended test against
the reference reports 45 checks / three failures and script errors; the candidate
passes all 45 without script errors. See [reference](storm-repro-clean.log) and
[candidate](storm-fixed.log).

`Atmosphere.update_clouds()` computed the same transport offsets twice; the storm
snapshot repeated offset work per layer. Packed sky arrays were also rebuilt for
unchanged quantized offsets. The candidate shares the computed offsets and keeps
one bounded packed-array cache. Accepted appearance/transport replacements
invalidate both derived caches. Uniform checks still run for each material,
including a newly constructed sky; snapshots retain detached public values. No
material/node references enter the caches. Clock rewinds, empty profiles, rejected
configuration, checkpoint restore and returned-snapshot mutation have regression
coverage. The limit remains the existing eight cloud layers.

[Exact four-file patch](candidate.patch), [reference sources](reference-src/render/atmosphere.gd),
[candidate sources](candidate-src/render/atmosphere.gd) and
[runtime hashes](runtime-identities.json) identify the changes. No solver,
aerodynamic/contact calculation, timestep/substep policy, command response, shader,
visual-quality setting or generated aircraft data was changed. Concurrent Workshop
and other tracks' work was preserved; primary-tree commits moved during this run.

## Automated native flights

The scripts instantiate production Main and use the normal session command
contract and 240 Hz engine callbacks. They do not manually advance physics during
the native flights. An external controller-selection flag prevents physical
devices from changing the scripted input stream. Two separate scenarios use the
Jensen Das Ugly Stik 60 and distant-storm appearance:

- Runway takeoff, climb, +15° / −15° bank targets and leveling: 5,760 ticks / 24
  simulation seconds. Lift-off is tick 685 (2.8542 s), maximum height 52.7585 m,
  bank extrema −16.1327° / +16.0560°.
- Existing landing-pilot approach fixture at 6 m / 12 m/s, followed by touchdown
  and rollout: 11,040 ticks / 46 simulation seconds. Touchdown is tick 2,045
  (8.5208 s), speed 10.4070 m/s. Final position is N 14.6460, E 42.8073,
  D −0.23429 m, with speed below 0.02 m/s inside the runway.
- Chase, pilot and orbit camera routing is exercised on the same schedule.
  End-of-scenario captures were inspected; no obvious new defect was seen in those
  views. This is not a complete camera/scenery artifact review or pixel identity.

Completed reference and candidate runs have identical hashes of **every accepted
tick's** numeric body, loads, inputs, auxiliary/continuous state and discrete modes:

| Scenario | SHA-256 |
| --- | --- |
| Takeoff/maneuvers | `c1e66cc035c1f898b2ef3d592c3bc885e58dd8a8ebc860a68a6ef892cb839cf2` |
| Landing/rollout | `77813c6e0d7311183808456f5600a19a25ba7bcd08dafd86cb35b945c7adc99a` |

That is 16,800 accepted ticks per completed two-scenario run, with no crash or
simulation fault. This supports equivalence for these input tapes, not physical
validation, all checkpoint/session fields or all aircraft. No golden was replaced.
These are separate takeoff and approach fixtures, not one continuous circuit.
Keyboard/controller device operation was not tested.

## Measurements

Godot 4.7.2 official `ed1daf0bf`, Compatibility/OpenGL, RTX 3090, driver 617.42,
Ryzen 9 5900X, Windows Balanced. Native viewport 1280×720, VSync 1, cap 60 FPS,
existing shadows/features enabled, Dummy audio. See
[host, settings and solver identities](source-and-host-identity.json),
[frozen overlay](frozen-overlay.json) and [computed summary](measurement-summary.json).

The cloud microbenchmark alternates reference/candidate order, with five samples
per variant, 500 warmup calls and 12,000 measured calls per sample, using the same
synthetic time sequence. Numbers below are medians divided by 12,000:

| Cloud workload | Reference µs/call | Candidate µs/call | Reduction |
| --- | ---: | ---: | ---: |
| Classic, update | 63.80 | 33.33 | 47.8% |
| Classic, update + snapshot | 109.10 | 50.57 | 53.7% |
| Prestorm, update | 149.09 | 73.13 | 50.9% |
| Prestorm, update + snapshot | 282.08 | 241.13 | 14.5% |

The last workload has substantial host variation; its retained samples must not be
replaced by a faster earlier result. [Raw times](cloud-raw-timing.log) and the
[executed benchmark](cloud-probes/benchmark_atmosphere_cloud_candidate.gd) are
headless **path-local CPU** evidence, not GPU, whole-frame or FPS measurements.

The completed native reference-3 / candidate-2 pair used GPU timing queries and
post-draw sampling. Both remained focused. These exploratory results are worse
for the candidate and are retained without attributing their cause:

| Scenario | Reference FPS | Candidate FPS | Reference p95/p99 ms | Candidate p95/p99 ms |
| --- | ---: | ---: | ---: | ---: |
| Takeoff/maneuvers | 57.56 | 45.42 | 20.38 / 22.41 | 29.08 / 41.22 |
| Landing/rollout | 23.35 | 13.28 | 56.69 / 65.30 | 85.79 / 93.74 |

A later pair disabled GPU queries and sampled process frames, with independent
draw-event counts. The candidate completed uninterrupted (1,279 and 1,047 draw
events respectively); the reference lost focus and required an explicit scripted
resume. It is **ineligible for FPS comparison**:

| Scenario | Candidate FPS / p95 ms | Reference FPS / p95 ms | Reference focus |
| --- | ---: | ---: | --- |
| Takeoff/maneuvers | 58.39 / 27.75 | 54.60 / 24.75 | interrupted |
| Landing/rollout | 15.93 / 79.83 | 15.08 / 81.80 | interrupted |

All table samples exclude ticks before 2,400 (ten **simulation** seconds); FPS is
sample count / summed monotonic intervals, percentiles use linear interpolation.
They do not meet the longer repeated wall-time acceptance protocol. The desktop
and CPU/GPU were shared, including other Godot processes; available host samples
are retained. Focus and host variation prevent a controlled global speedup claim.
These runs also do not isolate GPU-query observer overhead.

The extra [ground attribution probe](ground-audit/main-profile-result.json) used
the reference landing endpoint body with fresh auxiliary/continuous state, full
club field and lake, and manually stepped 480 accepted ticks headlessly. Wrappers
measured about 3,006.6 µs/tick: stage evaluations 2,040.5 µs (four calls), pre-tick
417.5, post-tick 257.5, substeps 6.4 and rotor momentum 2.5. This is not an exact
flight continuation or native FPS measurement; wrapper overhead is included.
The collision fixture has 4,980 proxies, 1,196 bins and five local-bin candidates.
Per-sweep world validation is a constant-time header check; full validation/bin
construction happens at setup. No speculative collision or physics patch follows
from this attribution. The slow landing/global frame-time issue remains unresolved.

## Verification and failed attempts

[Ten focused primary-tree suites](verification.json) pass **469 checks**, zero
failures, with no engine/script errors in their logs: atmosphere, cloud transport,
sky appearance config/checkpoint, storm bank/cell/events, sky render contracts,
World sky and sky routes. Headless render contracts are not GPU image tests.

The independent cloud expectations pass [102 checks](cloud-independent-final.log).
Disabling cache invalidation only in a disposable copy produces
[four expected failures](cloud-invalidation-mutation-2.log); restoring it passes.
The first mutation attempt only produced a CRLF-related parse failure and is not
counted as regression evidence. No deliberate mutant entered production.

The [forced-draw native lifecycle test](loading-storm-forced-candidate.json) passes
three real Home/Fly/Home routes with storm appearance: 655 nodes at Home each
time, zero orphan nodes, 12 retired flight playbacks released per cycle and the
final Home playback released on shutdown. Private settings are removed. Fresh
controller safety leaves these sessions paused at tick zero; this is a route and
resource test, not additional flight coverage. Forced draws make this a native
lifecycle check, **not natural first-frame latency or FPS evidence**. The original
natural-post-draw loading test hit its 180-second budget and published no JSON;
[failure record](failed-loading.json) and log remain separate.

Early native attempts paused on window focus loss. Original unsuccessful reports
are retained. The later opt-in harness resumes only that explicit pause through
the normal session API, records each event, and disqualifies interrupted runs from
FPS comparisons. Production focus safety is unchanged. A prior unprofiled harness
also exhausted its wall budget while waiting for post-draw; the replacement samples
process frames and counts draws independently. Forced capture draws happen only
after measurement. Neither failed run is counted as a completed flight.

The existing imported maple-tree wind/cull warning and aircraft-data warning remain;
they were not suppressed. Full `app/test.sh`, all-aircraft flight coverage,
package/export, physical audio output and a long memory soak were not run.
Stable short lifecycle counts do not establish absence of a memory leak.

## Reproduction and retained source

Exact command arrays appear in verification JSON; Python runners and executed
GDScript versions are retained. Native command shape:

```powershell
.tools/Godot_v4.7.2-stable_win64.exe --path <isolated-project>/app --audio-driver Dummy --windowed --resolution 1280x720 --max-fps 60 --script <audit>/native_flight_unprofiled.gd -- --output=<new-output.json> --resume-focus-loss
```

Restore scripts under `tmp/runtime-audit-3` to preserve their original relative
preload paths; the pilot source is also retained here. The disposable execution
project was frozen from base `72a2890ef` plus the recorded `f66127635` overlay;
reference/candidate serial swaps changed only the two recorded render scripts.
`runtime-identities.json` and source hashes identify the actual versions, rather
than the concurrently moving primary HEAD. The execution project ends restored to
the candidate. [Manifest](manifest.json) hashes the retained files; README is
excluded so documentation corrections do not alter measurement identities.
