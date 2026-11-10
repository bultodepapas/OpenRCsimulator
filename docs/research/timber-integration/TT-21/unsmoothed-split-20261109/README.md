# TT-21 — batch unsmoothed paint splits, 2026-11-09

Timber's paint repair previously called the scalar vertex copier for every
emitted corner, formatting smoothing keys even when the lookup was empty. The
new path groups source indices by material in their original encounter order,
then allocates and copies each supported channel once per material group.
Position, normal, color, both UV channels and four-component tangents retain
their exact values and order. Unsupported output slots remain absent.

Only empty smoothing lookups with well-formed arrays and String remaps use the
grouped path. Smoothed surfaces, partial triangles, negative/out-of-range indices,
short or wrong-typed channels, irregular source arrays and non-String remaps keep
the scalar path. Failed group-index appends or output preallocation discard the
partial bulk result and return to that path. No cross-frame cache was added.

## Native component measurements

[Evidence](evidence.json) retains raw trials, source/engine/import identities,
checked-run receipts, the correctness-only probe and untimed work counts.
Reproduce through the [performance tool contract](../../../../../research/performance/README.md).
Baseline: `5e673fbbdd4a2af94fb619eac87430d82f4d46c5` with the previously qualified
Timber integer-grid and shadow-decoder changes already present.

Windows 11 Pro, Ryzen 9 5900X, RTX 3090, NVIDIA OpenGL 617.42, official
`4.8.beta2.official.cafc17a19`, Compatibility. The native commands request a
1920×1080 window; these are construction/submission measurements without a
rendered-frame or pixel-resolution qualification. Each campaign uses five
alternating ABBA/BAAB groups, ten adjacent pairs, on already-imported resources.
Instantiation, input restoration and exact comparisons are outside timing.

| Complete cache-cold repair | Baseline median | Candidate median | Reduction | Faster adjacent pairs |
| --- | ---: | ---: | ---: | ---: |
| Native screen | 514.953 ms | 463.616 ms | 9.97% | 9/10 |
| Native repeat | 461.425 ms | 395.532 ms | 14.28% | 9/10 |

The observed median savings are 51.337 and 65.893 ms for this workload. Each
launch followed twelve seconds with no other Godot process observed. Other work
on this shared host was not continuously monitored during execution, and power
and thermal state were uncontrolled. Absolute costs varied substantially.

Warm control medians were 11.479→13.640 ms and 11.784→11.672 ms, with only 5/10
and 3/10 adjacent pairs faster. Warm observations remain mixed; these samples
establish neither a warm benefit nor warm non-regression. The warm code itself
is unchanged, but that is not a performance measurement.

An untimed instrumented stock repair found 39,168 split corners. All 27,150
empty-lookup corners qualify for the grouped path, avoiding their smoothing-key
formatting, dictionary queries and individual vertex-copy calls. The largest
grouped call stores 9,753 indices: **39,012 logical temporary bytes**, excluding
allocator capacity, dictionary/array overhead and existing buffers. Peak RAM and
VRAM were not measured; no memory reduction is claimed.

## Exactness and compatibility

- The retained correctness-only probe passes **3,022 checks**. Both native
  campaigns pass **3,126 checks**, including 300 seeded split cases, ownership
  witnesses and exact imported-model cold/warm comparisons. Their snapshots
  cover packed mesh arrays, serialized LOD records, formats, names, transforms
  and active material names; material objects are excluded.
- Four focused headless suites pass **405 checks**: split/LOD/identity 136, paint
  grid 157, actual stock/custom skin builds and material lifetime 89, texture/mip
  and paint parameters 23. The split/LOD suite also passes all 136 against the
  frozen baseline. Its compatibility assertions use the current adapter resources.
- Native LOD/identity and actual stock/custom paint suites pass **136 + 89**
  checks with zero engine errors or warnings. Fixtures cover interleaved material
  groups, duplicate/reordered indices, absent/empty/non-unit normals, present zero
  smoothing values, degenerate triangles, ignored tails, scalar fallbacks,
  complete tangent/UV/color channels and independently mutable output groups.

The exact current Timber paint identity is now
`375f9373e4755aad93a9907e829ed267e340c16142584991de0fb22aa4e9eedd`.
The compatibility update changes only that current identity and its test constant. The distributed
kit's legacy identity, files, paint mapping and source assets remain unchanged;
unrelated identities still refuse admission.

A key-skipping-only prototype passed parity and showed a 7.9% headless cold
reduction, but its native screen was inconclusive (−0.13%, 6/10 faster pairs).
That result led to grouping the actual channel-copy work; it is not counted as a
separately qualified native optimization. Procedural-paint inverse reuse was not
implemented because it would require broader identity/diagnostic qualification.

Raw runs remain under ignored `tmp/timber-split-20261109`; no images were added to
Git. Other tracks changed the shared checkout and HEAD advanced externally;
selected final helper/probe hashes stayed fixed across the accepted campaigns.
Full Home/Fly loading, first interactive frame, FPS, sustained hardware/platform
qualification, required CI and exports remain separate. This task changed no
physics law or generated aircraft data and performed no commit or push.
