# VQ-04a — packed LOD index decoding, 2026-11-09

The Corsair shadow collector now reads two serialized u16 indices per native
32-bit word on little-endian hosts. Both halves remain unsigned through masking;
an odd trailing index still uses the original decoder. Every index in every LOD
is validated, including records that will not be selected. A failed output
allocation or incomplete word conversion rejects the record. The original scalar
path remains for big-endian hosts and 32-bit index records.

The [pinned engine conversion](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/variant/variant_call.cpp#L887-L899)
copies native-endian words; the one-time endian probe is therefore necessary.
This does not change geometry, tolerances, LOD choice, source admission, bounds,
face ordering, material ownership or the bind-time snapshot. No solver, aircraft
data, shader or saved graphics setting was changed by this optimization.

## Native component result

[Evidence](evidence.json) retains the source hashes, raw trials, rejected screens,
checked-run receipts, native capture metadata and PNG hashes. Reproduction lives
in the [shadow tool guide](../../../../../tools/shadows/README.md#paired-aircraft-collection-comparison).

Windows 11 Pro, Ryzen 9 5900X, RTX 3090, NVIDIA OpenGL 617.42, official
`4.8.beta2.official.cafc17a19`, Compatibility, 1920×1080 window. Five imported Corsair
gear/flap configurations, five ABBA/BAAB groups per configuration and campaign;
ten adjacent pairs per configuration. Both frozen baseline collectors are loaded
independently of the candidate. Instantiation, warmup and byte comparisons are
outside timing. Each timed result preserves exact arrays, format, bounds, counts
and representation/fallback metadata.

| Complete proxy collection | Baseline pooled median | Candidate pooled median | Reduction | Faster adjacent pairs |
| --- | ---: | ---: | ---: | ---: |
| Native screen | 119.438 ms | 116.691 ms | 2.30% | 40/50 |
| Native repeat | 123.747 ms | 121.148 ms | 2.10% | 35/50 |

Median adjacent-pair savings were 3.979 and 3.126 ms. These are equal-size pools
across five fixtures, not a guarantee for each pose: half-retracted gear was
0.28% slower in the first screen and 3.32% faster in the repeat. Absolute costs
also varied. No other Godot process was observed at either timing launch; the
whole run was not continuously monitored, and power/thermal state was not
controlled. This is a modest component screen, not sustained hardware acceptance.

The maximum extra logical data across all imported Corsair LOD records was
129,772 bytes for a packed-word buffer, or 259,544 bytes while an odd-length
prefix slice and word buffer coexist. Buffers are local to one record. These
bounds exclude allocator/object overhead and existing arrays; they are not
measured peak RAM/VRAM. No memory reduction is claimed.

## Correctness and rendering

Seven affected headless suites pass **744 checks**: proxy/decoder 444, deferred
startup 80, ownership 49, projector 47, cue controls 50, flight cues 20 and Home
geometry 54. Decoder cases cover unsigned high halves, both half-word positions,
odd/even triangle counts, every invalid index position, corrupt unselected LODs,
the 65,536/65,537 width boundary and forced scalar fallback. The two final
native comparison campaigns each pass 117 checks. Accepted checked invocations
have no engine errors or warnings.

The existing native trial passes eleven projected poses, seven production
binding/admission cases and four initially disabled routes at 1080p with MSAA 4×.
A second trial substitutes only the frozen proxy resource path in a derived tool;
the projected collector is byte-identical to its frozen baseline. All **126 PNGs**
match exactly, including 256² masks, 1080p receivers, cache controls and deferred
activation controls. The landing proxy receiver was visually inspected as a
positive visible-shadow witness. Images remain in ignored
`tmp/shadow-preparation-20261109`, not Git.

## Rejected experiments and remaining work

- Single-pass full/proxy traversal preserved geometry but complete-collector
  medians ranged from 4.2% slower to 4.3% faster. The runtime change was restored.
- Four indices per 64-bit word added lane/tail complexity without a convincing
  improvement over the simpler two-index candidate. It was not retained.
- A temporary native ArrayMesh for indexed gathering changed exact vertex bytes
  and made collection 36–40% slower. Its 55 comparison failures remain classified
  as rejected evidence; passing approximate synthetic checks did not promote it.

Baseline source was captured at `7e8ce3a4d`; HEAD advanced externally during the
work. Relevant accepted rendering hashes remained fixed; unrelated physics,
schema and scenery edits were preserved. Geometry preparation remains synchronous.
First interactive frame, cold launch, FPS, GPU passes and frame percentiles were
not measured. Full CI, exports and other hardware/platform qualification remain
separate. No commit or push was performed by this task.
