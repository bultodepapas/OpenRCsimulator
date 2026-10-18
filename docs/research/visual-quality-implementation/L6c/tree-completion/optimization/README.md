# L6c / FW-23 / VQ-01c: bounded CPU optimization round

2026-10-18. Two source-preserving changes reduce presentation work. Woodland margins now use the existing hedge layout directly and construct only their final batches, removing 48 temporary hedge roots and their throwaway meshes. Field-world eye adaptation skips artificial-light queries when the daylight multiplier is zero and inputs are finite. No assets, density, graphics presets, physics or golden recordings change.

| Component | Reference | Candidate | Evidence |
| --- | ---: | ---: | --- |
| Balanced woodland margin construction | 9.994 ms | 6.247 ms | [Native Windows comparison](woodland/README.md) |
| High woodland margin construction | 12.686 ms | 8.642 ms | [Native Windows comparison](woodland/README.md) |
| Noon exposure query, landscape enabled | 35.767 µs | 8.842 µs | [Headless CPU comparison](exposure/README.md) |

Woodland values are medians of three process medians, with nine alternating warm pairs per tier per process on Windows Godot 4.7.2 / RTX 3090. Exposure values summarize 21 alternating blocks per case across three processes. These are component measurements, not FPS or total-loading improvements. Desktop/cache conditions were uncontrolled. Low-tier woodland construction is unchanged; exposure has small nighttime cost increases recorded in the linked report. Fixed-sun worlds and the explicit SDR lighting route do not benefit from the exposure change.

## Verification

All three native woodland runs preserve exact low/balanced/high scene snapshots, including instance buffers, transforms, colors, shader/material/texture settings and bounds. Final batches retain independent mesh ownership. Exposure preserves 2,160 sampled results, all 252 timed-block checksum pairs, 1,680 boundary/nonfinite-input cases and 360 adaptation transitions. Focused regressions pass: woodland 26 checks; field lights 86 with landscape enabled and 84 disabled; landscape lighting 54; world flow 26; presentation context 17.

The combined source completes three real Home/Fly/Home cycles at 1280×720 on the same native renderer: 611 nodes at Home, 1,090 in flight, zero orphans in every cycle, released audio and removed private settings. [Raw integration report](integration/report.json), [engine log](integration/run.log) and [source/fixture hashes](integration/identity.json). Controller safety keeps all first draws paused at tick zero; this checks loading and teardown, not active-flight performance. Known aircraft-data and static oak-material warnings remain; no engine errors occurred.

The full suite, exports, long soak and active-flight benchmark were not rerun for this bounded round. Earlier tree qualification remains separately scoped in the [completion report](../README.md). Source/input hashes identify these measurements; concurrent unrelated commits advanced the shared repository during the task, so this is not a frozen whole-project comparison.
