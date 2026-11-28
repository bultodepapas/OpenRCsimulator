# Native software-renderer measurements

These results describe the hosted software installations below. They do not establish gaming-PC FPS, physical GPU frame time or VRAM use. The baseline is `71306784`; all selected candidate launches use production source `1e91cb28`. The [machine-readable summary](evidence/hosted-field-performance.json) retains each launch, host identity, source hashes, counters and coverage status.

## Comparison protocol

Each of the six scenes on each backend uses one VM and four native engine launches in A/B/B/A order. All 48 selected launches exited naturally with code 0. Each keeps 30 post-draw wall intervals after 60 warm-up frames and exclusion of the first recorded interval: 1,440 retained intervals in total. The output is 1920×1080, at 1× scale and 4× MSAA, with matched camera, scene, clock, seed and material settings. Different scenes and backends use different VMs; no cross-VM performance average is calculated.

The selected software backend is recorded from the engine's actual device line. The hosted image uses Mesa 25.2.8, LLVM 20.1.2, Ubuntu 24.04 and a Mesa worker limit of two. The receipts retain kernel and VM identity, but not CPU model/core count. That omission limits independent machine-to-machine timing reproduction even when the same workflow is used.

The [pilot recovery protocol](evidence/pilot-recovery-protocol.json) and [pavilion recovery protocol](evidence/pavilion-recovery-protocol.json) were committed before their recovery results existed. Each primary final-source job is selected whenever complete; otherwise a complete, source-identical recovery supplies all four launches from its own VM. Both attempts are retained, and timing is not used to select between them. The [pilot selection receipt](evidence/pilot-selection-final.json) and [pavilion selection receipt](evidence/pavilion-selection-final.json) identify the actual decisions and each source/run/job/archive identity.

## Render-loop wall time

A → B means baseline → candidate. Throughput is `1000 × interval count / summed milliseconds`, pooling only the two launches of one variant within one scene/VM. P50 is the median, and P95 uses the nearest-rank definition. The paired changes are B1/A1 and B2/A2 in chronological ABBA order; positive means higher observed throughput. Two launch pairs are insufficient to establish a small speed improvement, and consecutive frame intervals are correlated.

### OpenGL Compatibility / llvmpipe

| Scene | Loop FPS A → B | Wall P50 ms A → B | Wall P95 ms A → B | Paired throughput changes |
| --- | ---: | ---: | ---: | ---: |
| Lake overview | 0.550 → 0.551 | 1,816.53 → 1,814.85 | 1,830.95 → 1,826.37 | -0.04% / +0.33% |
| Lake shore | 0.559 → 0.561 | 1,787.74 → 1,781.96 | 1,826.83 → 1,799.10 | -0.27% / +0.99% |
| Pilot north | 0.547 → 0.551 | 1,825.57 → 1,817.59 | 1,842.40 → 1,831.76 | +0.75% / +0.46% |
| Field entry | 0.779 → 0.781 | 1,282.23 → 1,278.75 | 1,296.14 → 1,291.82 | +0.37% / +0.22% |
| Highway | 0.696 → 0.702 | 1,437.80 → 1,425.02 | 1,454.32 → 1,435.57 | +1.03% / +0.60% |
| Pavilion | 0.274 → 0.275 | 3,644.81 → 3,629.66 | 3,694.27 → 3,691.90 | +0.91% / -0.55% |

Actual device: `OpenGL API 4.5 (Core Profile) Mesa 25.2.8-0ubuntu0.24.04.5 - Compatibility - Using Device: Mesa - llvmpipe (LLVM 20.1.2, 256 bits)`.

### Vulkan Forward+ / software device

| Scene | Loop FPS A → B | Wall P50 ms A → B | Wall P95 ms A → B | Paired throughput changes |
| --- | ---: | ---: | ---: | ---: |
| Lake overview | 0.710 → 0.714 | 1,416.77 → 1,399.26 | 1,452.88 → 1,435.97 | +1.11% / -0.01% |
| Lake shore | 0.794 → 0.799 | 1,260.26 → 1,242.47 | 1,320.19 → 1,316.87 | -0.64% / +1.83% |
| Pilot north | 0.706 → 0.708 | 1,414.97 → 1,411.67 | 1,449.16 → 1,433.71 | +0.86% / -0.21% |
| Field entry | 1.002 → 1.013 | 998.36 → 985.66 | 1,015.18 → 996.70 | +2.25% / +0.08% |
| Highway | 0.817 → 0.817 | 1,223.47 → 1,223.14 | 1,233.28 → 1,232.24 | +0.08% / -0.04% |
| Pavilion | 0.388 → 0.388 | 2,577.13 → 2,573.03 | 2,613.47 → 2,606.07 | +0.81% / -0.66% |

Actual device: `Vulkan 1.4.318 - Forward+ - Using Device #0: Unknown - llvmpipe (LLVM 20.1.2, 256 bits)`.

## Rendering counters and process resources

Viewport CPU is an elapsed rendering counter that can include waits. It is not consumed process CPU time. Viewport GPU readings are retained positive polls with unverified query age; they are not proven to describe the same frame as each wall interval. Their differences across backends reflect different implementations and must not be treated as a CPU/GPU workload split. The pinned engine source and query limitations are explained in the [audit report](README.md#performance-acceptance).

| Backend / scene | Viewport CPU positive-poll P50 ms A → B | Viewport GPU positive-poll P50 ms A → B |
| --- | ---: | ---: |
| Forward+ / Lake overview | 0.674 → 0.532 | 1,403.19 → 1,384.51 |
| Forward+ / Lake shore | 0.481 → 0.514 | 1,240.73 → 1,224.14 |
| Forward+ / Pilot north | 0.573 → 0.579 | 1,399.48 → 1,396.44 |
| Forward+ / Field entry | 0.311 → 0.315 | 985.75 → 972.76 |
| Forward+ / Highway | 0.347 → 0.347 | 1,210.76 → 1,210.49 |
| Forward+ / Pavilion | 0.722 → 0.716 | 2,565.27 → 2,560.96 |
| GL / Lake overview | 1,807.143 → 1,805.764 | 1,807.17 → 1,805.79 |
| GL / Lake shore | 1,775.018 → 1,773.646 | 1,775.09 → 1,773.72 |
| GL / Pilot north | 1,808.440 → 1,802.515 | 1,817.07 → 1,811.09 |
| GL / Field entry | 1,267.484 → 1,263.889 | 1,275.63 → 1,272.13 |
| GL / Highway | 1,427.036 → 1,416.435 | 1,427.09 → 1,416.50 |
| GL / Pavilion | 3,631.167 → 3,615.688 | 3,638.11 → 3,622.79 |

Process resources are sampled at 1 Hz for the direct engine PID from startup through the selected scene and teardown. RSS is the highest observed resident-memory sample; CPU seconds are the sampled user-plus-system counter change. Neither is an exact lifetime total or true peak. Ranges below retain the two launches per variant. MiB means 1,048,576 bytes. Engine video-memory accounting is a logical resource counter, not physical VRAM.

| Backend / scene | Highest observed RSS MiB A → B | Sampled process CPU seconds A → B | Engine video-memory MiB, A/B | Draw calls, A/B |
| --- | ---: | ---: | ---: | ---: |
| Forward+ / Lake overview | 7,818.7–7,897.2 → 7,886.6–7,916.2 | 593.5–615.6 → 607.1–607.7 | 1,328.5/1,328.5 | 139/139 |
| Forward+ / Lake shore | 7,866.5–7,893.4 → 7,881.4–7,888.9 | 505.7–515.3 → 471.5–485.8 | 1,328.5/1,328.5 | 122/122 |
| Forward+ / Pilot north | 7,920.9–7,949.9 → 7,907.9–7,970.1 | 616.4–626.3 → 614.2–622.5 | 1,328.5/1,328.5 | 135/135 |
| Forward+ / Field entry | 4,804.9–4,824.6 → 4,816.9–4,827.6 | 300.9–302.8 → 298.9–300.8 | 1,301.1/1,301.1 | 28/28 |
| Forward+ / Highway | 4,928.9–4,933.1 → 4,922.9–4,942.6 | 355.9–356.9 → 355.9–356.6 | 1,302.4/1,302.4 | 49/49 |
| Forward+ / Pavilion | 5,768.1–5,771.2 → 5,783.6–5,788.9 | 703.5–706.0 → 705.7–707.3 | 1,302.4/1,302.4 | 287/287 |
| GL / Lake overview | 3,413.7–3,414.5 → 3,416.0–3,418.0 | 405.3–406.8 → 406.3–406.5 | 646.7/646.7 | 129/129 |
| GL / Lake shore | 3,332.9–3,334.5 → 3,333.4–3,334.7 | 375.3–378.7 → 377.1–380.3 | 646.7/646.7 | 108/108 |
| GL / Pilot north | 3,403.5–3,404.6 → 3,405.2–3,405.6 | 421.2–421.3 → 419.4–419.7 | 646.7/646.7 | 125/125 |
| GL / Field entry | 1,661.4–1,684.6 → 1,662.4–1,662.8 | 258.2–259.1 → 256.9–256.9 | 621.8/621.8 | 28/28 |
| GL / Highway | 1,851.7–1,854.7 → 1,853.4–1,897.7 | 278.6–281.2 → 277.1–282.4 | 621.8/621.8 | 47/47 |
| GL / Pavilion | 3,074.9–3,085.5 → 3,077.5–3,078.0 | 732.8–734.1 → 731.0–734.6 | 629.7/629.7 | 255/255 |

Resource-sampler coverage across the selected 48 launches: 45 complete, 3 partial. See each launch's `resource_sampler` object for channel counts, end-of-process errors, stop reason and caps. Coverage status is separate from the native engine's required successful exit.

## Replay the numbers without a rendering device

Use the reducer from this evidence commit with the [preserved numeric archive](evidence/field-benchmarks-final.zip) and its [manifest](evidence/field-benchmarks-final-manifest.json). Extract the archive to a new directory, then run:

```sh
python3 research/performance/native_visual_audit/reduce_hosted_fields.py /path/to/extracted-replay \
  --candidate 1e91cb28eaed0079837e9a49d9e0b5a90253ee3e --require-all \
  --out /tmp/openrc-replayed-performance.json
```

The reducer checks all 12 scene/renderer cases, exact source identity, renderer, settings, order, raw arrays, natural process exits and resource provenance. It recomputes wall/viewport statistics from the raw arrays and verifies each captured process-resource summary against its retained sidecar. The independent verifier also recalculated sampled RSS and user-plus-system CPU directly from the raw process samples. The original hosted archives additionally contain native PNGs and complete logs; their identities are listed in the [gallery manifest](evidence/image-gallery-manifest.json).

The nonselected [pilot attempt](evidence/pilot-alternate-final.zip) and [pavilion attempt](evidence/pavilion-alternate-final.zip) retain their available raw numeric and engine-log evidence separately. Missing files in an incomplete attempt remain missing. These alternate packages do not contribute launches to the selected 12-case summary.

## Remaining qualification

A named physical GPU, its driver and a fixed display/present configuration are still required to assess player FPS, GPU cost and physical memory use. The close roof fix deliberately enables normal-map work that the old absolute threshold skipped; no close-view hardware cost is claimed. The selected views are stationary. Motion aliasing, weather transitions, flight readability, all aircraft and all quality presets remain outside this measurement campaign.
