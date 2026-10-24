# VQ-01c — storm CPU work and Home livery retention, 2026-10-24

Follow-up: [all nine airplane configurations tested](all-planes.md), with native
frame-time screening, input checks and aircraft-specific performance findings.

Further follow-up: [allocation and repeated-work reductions](helpers.md), including
all-aircraft numeric parity and mixed native frame-time results.

Two bounded changes survived the investigation: `Main._update_storm()` now reads
the current atmosphere's sound speed without building a second full audio snapshot;
`AppRoot._rebuild_home_scene()` now passes the selected livery to the replacement
Home scene. Physics, control laws, rendering settings, assets and golden flights
were not changed. The ordinary soundscape still receives its full snapshot.

## Measurements

Windows, Ryzen 9 5900X, RTX 3090 (617.42), 64 GiB RAM, Godot
4.7.2.stable.official.ed1daf0bf. [CPU batches](sound-speed.json) were measured
headlessly on frozen production flight scenes, nine alternating batches of 150
calls after warmup. These are method costs, not whole-frame savings:

| Aircraft / atmosphere | Full snapshot, median µs | Getter, median µs |
| --- | ---: | ---: |
| Stik / calm | 61.75 | 2.58 |
| Extra / hot-high | 343.63 | 2.45 |
| P-51 / cool-dense | 72.48 | 2.44 |

All three getter values exactly matched both the snapshot and the original
temperature formula. The [retained probe](../../../../../research/performance/sound_speed_probe.gd)
records raw batches and source hashes; its command is in the
[performance tools guide](../../../../../research/performance/README.md#flightaudio-sound-speed-accessor-microprobe).
The older snapshot method remains available, so this comparison is reproducible
without replacing production source.

[Native A/B/B/A results](native-comparison.json) used active Stik flight,
Electrical Storm, fixed audio seed 27031, Compatibility, 4× MSAA, 1920×1080,
VSync at 60 Hz, 10 s warmup and 30 s collection per run. Extra frame diagnostics
were off. Audio used the Dummy driver. Original and current Main loaded against
the same shared audio source; only the storm caller differed.

| Run | FPS | p95 ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: | ---: |
| Before A1 | 60.00 | 17.424 | 18.157 | 19.692 |
| Current B1 | 60.00 | 18.640 | 19.454 | 28.498 |
| Current B2 | 60.00 | 17.588 | 18.859 | 23.918 |
| Before A2 | 59.97 | 17.552 | 19.058 | 38.283 |

**No FPS, frame-pacing, whole-process CPU, memory or latency improvement is
established.** Samples are below the existing 60 s native qualification minimum;
simulation windows differ by up to 18 starting ticks. Process peak RSS ranged
1246–1290 MiB and includes startup. One-second OS samples can miss brief peaks.
The comparison records source identities, configuration, endpoints, CPU/RSS and
hashes of local raw artifacts under `tmp/engineering-perf/native/`.

## Verification and actual interaction

- Regression Guardian: 79 checks passed across simulation (11), golden flights
  (4), storm (30), audio (18), and Home rebuilding (16). Golden data was not
  re-recorded. Selected Corsair Spectrum paint survives rebuilding, and weak
  references verify release of replaced/closed Home scenes.
  An earlier test revision failed an aircraft-restoration assertion. Its source
  was not preserved; changed assertion labels and file timestamps establish
  that it was a different test revision, not a same-source repeatability result.
  Five serial repeats of the final Home test then passed 16/16 checks each,
  with zero runner errors or warnings (`tmp/engineering-perf/home-repeatability/`).
- Seven script parse checks passed. After probe metadata changed, its final
  parse and three-case measurement passed again. One earlier probe invocation
  failed because its output path was relative; the corrected absolute path
  succeeded. The original receipt is retained locally, not counted as a pass.
- Native 1080p engine-input smoke: ten checks passed for roll, pitch, throttle,
  release to neutral, live tick advancement, and rendered pilot/chase/orbit
  cameras. Input events entered the normal engine input pipeline; this does
  not measure OS delivery or input-to-photon latency.
- Separate native UI smoke verified a 1080p window and selected/saved 8× MSAA
  and Extreme detail; their active rendering effect was not verified. It also
  exercised storm, Club → Green Paradise, airborne Stik → P-51, restart, focus
  pause and Resume.
  UI keyboard automation did not reliably deliver flight controls. This was
  bounded smoke testing, not human pilot or takeoff/landing acceptance.

Local receipts: `tmp/engineering-perf/regression/798f2a9a382f46dfb11d176cc5c83a28/`,
`final-probe/`, `controls/native-035nb6ck/`, and `qa/run-20261024-qa02/`, all under
`tmp/engineering-perf/` except the first fully specified path. Raw local receipts
are not a durable release qualification bundle.

## Remaining findings and limits

Direct-Main diagnostic exit intermittently reports 19 audio stream/playback
ObjectDB instances, reproduced with original source as well as current source.
Verbose originals identified only audio objects; the matching current short run
reported none. This neither proves an accumulating leak nor establishes a fix.
It is consistent with the earlier [audio retirement experiment](../loading/audio/README.md).
The probe bypasses AppRoot's coordinated Quit flow; ordinary UI smoke stderr was
empty. No production teardown delay or warning suppression was added.

Three earlier Home/Fly/Return cycles found flight readiness around 1.55–3.44 s
and first draw 1.67–3.62 s, but their 1920×1061 viewport and uncontrolled caches
prevent 1080p qualification or a comparative loading claim. Paused/crashed
startup captures were excluded from active-flight performance conclusions.
GPU diagnostics from a separate 1061-high capture are not an A/B GPU comparison.
Long sessions, broad aircraft coverage, OS input latency, VRAM and other hardware
or platforms remain unqualified. The full repository suite was not rerun; the
unrelated existing `docs/DECISIONS.md` merge conflict remains untouched.

Official Godot
[profiler documentation](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html)
also supports keeping script CPU measurements distinct from rendering timings.

Final Good Enemy review found no material correctness defect in either fix.
It emphasized that the VQ acceptance rule requires a gain over 5% of the affected
complete workload or removal of a named reproducible hitch/memory defect. These
helper timings and short native samples do not satisfy that gate. This record
supports a redundant-call reduction and a livery bug fix, not a qualified VQ
whole-game performance milestone. No broader milestone is marked complete.
