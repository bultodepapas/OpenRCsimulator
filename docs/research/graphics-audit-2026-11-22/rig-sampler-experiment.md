# Nitro rig sampler — source-bound component experiment

**The numeric sampler has a measurable optimization opportunity in this isolated environment.** Two final checked processes produced byte-identical transforms and float32 accumulation results for the three experimental variants. Across the six process/workload summaries, the combined design reduced median paired elapsed component time by **19.6–27.7%**. This is neither a measured FPS gain nor a production-ready optimization.

This follows [U02](fourth-pass-ground.md#u02-nitro-visual-samplers-repeatedly-prepare-identical-axis-coordinates) and the existing [RCV-37 optimization](../rc-monster-truck/RCV-37/README.md). RCV-37 already prepared track metadata and scratch; its older Windows/Godot 4.7.2 timings are separate evidence, not this baseline.

## What was executed

The [reproducer](../../../research/performance/graphics-audit-2026-11-22/reproduce_rig_sampler.py) extracts `TrackSampler`, `_compile_track`, `_sample_compiled_track` and `_transform_from_floats` from main `7940a4081e10994f34c858c4acac3d7a1a271464`. Original declarations and bodies are copied unchanged into a small isolated `RefCounted` script; trailing separator whitespace is normalized. The same pinned manifest and **3,553,104-byte actual rig binary** are extracted from Git; the binary SHA-256 must match the manifest. Sparse working-directory absence does not prevent this Git-object extraction. No GLB or application import is performed.

The fixture uses official Linux x86_64 Godot `4.8.beta2.official.cafc17a19`, SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`, headless with Dummy audio. The installed engine was read without modifying its owning checkout. Both fixture import and script execution use the existing checked runner with warnings as errors; the component execution additionally requires a completion marker. This local environment had no configured pool/queue admission, display or `/dev/dri`; no physical-device, rendered or shared-host job was submitted. The reproducer refuses an enrolled performance run without inherited admission.

Each arm has separate compiled mutable sampler scratch. Runtime order is preserved: **205 ordinary mesh tracks followed by four wheel-pivot tracks** in FL/FR/RL/RR order. The current manifest contains 171 one-axis and 38 two-axis tracks: 247 per-track axis preparations but only five unique exact `(name, low, step, count)` mappings. Group identity uses exact double bit patterns during fixture compilation; it is not a name-only or rounded-key assumption.

| Arm | Difference from unchanged baseline |
| --- | --- |
| Baseline | Original numeric sampler and original `Array`-typed transform helper |
| Packed helper | Same sampling algorithm; only the runtime float32 result calls a `PackedFloat32Array`-typed transform helper. Manifest correction compilation retains the original `Array` helper. |
| Shared coordinates | Prepare the five group coordinates once per input set; use shared low/high indices and fractions in the same interpolation-mask order. Keep original transform helper. |
| Combined | Both preceding changes |

The shared-coordinate experiment changes preparation, per-track scratch writes and mask indexing together. Its time is a **design comparison**, not an isolated measurement of exactly 242 arithmetic operations. Its sampler `low_indices`, `high_indices` and `fractions` fields are not updated as in the baseline; complete sampler-object parity is not claimed.

## Correctness scope

For every arm, the probe compares `sampler.values.to_byte_array()` and `var_to_bytes(Transform3D)` immediately before reusing its buffers. **186 synthetic finite input sets × 209 tracks = 38,874 track/input cases**, each compared with three candidates: **116,622 comparisons per process**. Cases include neutral controls, all 32 low/high combinations of five inputs, individual grid knots/fractional/clamped cases and 128 deterministic interiors. All three processes, including the retained preliminary attempt, reported zero numeric failures and the same baseline output SHA-256 `419d35145267ac7ff18b1f2a256e505cc840d53ac23f88da8144d5b4e13c1485`. Repeating the cases in two final processes is repeatability evidence, not additional distinct coverage.

An untimed typed-argument witness passes a `PackedFloat32Array` into a function declared with `values: Array`; the pinned engine observes `TYPE_ARRAY` inside it. This confirms conversion behavior for that boundary. It does **not** count allocations or identify their cost; no allocator trace was collected. [Godot's Array reference](https://docs.godotengine.org/en/latest/classes/class_array.html) documents the packed-to-generic constructor; that moving documentation is explanatory, while the executed engine hash pins this observation.

The variants qualify only the current valid compiled metadata and finite authored sampler inputs. They do not qualify changed/invalid counts, source-data mutation or failure precedence. The shared design has no fallback for those cases in this deliberately isolated experiment. A production change needs a validated owner boundary or the original fallback, including count-one and malformed/empty/out-of-range behavior. Input sets are authored sampler coordinates, not recorded car physics states; wheel angles, inverse steering mapping and body state are outside the fixture.

## Timings and variability

Each workload has three warmup blocks per arm, then 12 rotating-order rounds containing all four arms. Each timed block samples the complete 209-track numeric set 18 times. Shared preparation, dispatch/indexing, result consumption and a small common checksum are inside the timing window. Source extraction, compilation, byte comparison, hashing, printing and file I/O are outside it. All slow blocks are retained. Values below are **medians of 12 block-average times per full rig numeric batch**, not per-frame p50/p95 or native CPU counters.

| Final process / workload | Baseline | Packed helper | Shared coordinates | Combined | Median paired combined reduction |
| --- | ---: | ---: | ---: | ---: | ---: |
| 01 / neutral | 1.191 ms | 1.136 ms | 0.962 ms | 0.868 ms | 27.7% |
| 01 / fractional interior | 1.781 ms | 1.654 ms | 1.486 ms | 1.328 ms | 23.8% |
| 01 / varying interiors | 1.676 ms | 1.532 ms | 1.401 ms | 1.282 ms | 21.8% |
| 02 / neutral | 1.419 ms | 1.298 ms | 1.103 ms | 1.025 ms | 26.4% |
| 02 / fractional interior | 1.734 ms | 1.655 ms | 1.438 ms | 1.381 ms | 19.6% |
| 02 / varying interiors | 1.668 ms | 1.571 ms | 1.387 ms | 1.346 ms | 20.8% |

The last column is the median of same-round percentage reductions, so it need not equal the percentage obtained from the two marginal medians in the table. Packed-helper median paired reductions were 4.7–6.5%; shared-coordinate reductions were 15.1–21.2%. The combined arm was faster in 68 of 72 paired blocks; shared coordinates in 70, and the packed helper in 64. Rounds within one process are not independent physical-machine replications. These elapsed measurements contain scheduler/runtime noise, have no thermal/CPU-frequency control or allocator attribution, and do not establish confidence intervals or device-wide gains.

The first attempt's engine import and component check both passed with zero warnings/errors. Its outer summary failed solely because the harness expected the CLI-style engine version but `Engine.get_version_info().string` uses a display-style string. The harness was corrected to construct the canonical version from the recorded version fields; two fresh final processes passed all outer checks and input-hash stability checks. The preliminary source, raw results and logs remain in [rig-sampler-evidence.json](rig-sampler-evidence.json) and are excluded from the table. Six checked engine invocations total were made (three imports, three components); no full application or regression suite ran.

## What the result supports next

The typed helper is the smallest candidate: it keeps the existing native engine math and packed representation, and has a narrower behavioral boundary than shared preparation. Validate it in the real RCV-37/full visual harness and measure the complete `draw`/process callback on matched Windows, Linux and Apple Silicon before shipping. The shared design additionally needs proof that actual mesh setters, synchronous notifications or reentry cannot mutate the shared inputs or compiled metadata between track calls. Preserve unspun wheel bases, engine/bell phases, input-state immutability, resource ownership and model rebuilds.

A larger native C++ batch sampler is an experiment only after boundary profiling. Match the exact mask/decode order and float32 writeback after each weighted term, including float64 intermediate arithmetic; do not introduce fused arithmetic, fast-math or a changed precision contract. Compare a native batch with the smaller built-in/typed-helper approach, including marshalling and node submission cost. None of these experiments changes float64 simulation or 240 Hz integration.

The complete live draw also performs state validation, body and wheel/bell transforms, setters, scene notifications and renderer work. Those were not measured, and this headless fixture creates no geometry. If a future measured component saving is `d` milliseconds on the frame's actual critical path and baseline frame time is `T`, the conditional uncapped rate is `1000/(T-d)`; GPU, display or scheduling limits can instead leave FPS unchanged. Substituting these component timings directly into an FPS claim would be unjustified.

Return to the [fourth-pass index](fourth-pass.md) for other vehicle, menu, rendering and native opportunities.
