# DT-11a — generated default lake geometry

Follow-up: [exact grain precomputation and clean package verification](../grain/README.md).
The measurements and failure ledger below retain this campaign's original scope.

2026-10-14. Follow-up to [bounded in-memory reuse](../README.md). Implemented:
precomputed default basin/water CPU arrays, reproducible generation, exact-input
invalidation and procedural fallback. Physics, shaders, materials and geometry are
unchanged. This is a loading repair; DT-11a and native/package acceptance remain open.

## Result and scope

Five alternating fresh-process pairs on Windows reduced the median engine-clock time
to Home's first draw from **9.576 s to 6.624 s** (30.8%). Every pair improved. The last
two pairs were slower for both variants; retain that dispersion and do not infer a
controlled hardware benchmark. Background load and OS/import/driver caches were not
controlled. The five-second Home target remains unmet, as does first Fly's two-second
target. Warm Fly was not consistently faster and is not an improvement claim.

| Pair / order | Baseline Home, s | Candidate Home, s | Baseline first Fly, s | Candidate first Fly, s |
| --- | ---: | ---: | ---: | ---: |
| 1 / baseline first | 8.980 | 6.505 | 2.461 | 2.523 |
| 2 / candidate first | 8.775 | 6.073 | 2.305 | 2.260 |
| 3 / baseline first | 9.576 | 6.624 | 2.284 | 2.256 |
| 4 / candidate first | 16.346 | 10.186 | 4.443 | 3.602 |
| 5 / baseline first | 12.392 | 9.274 | 3.152 | 3.300 |

Home uses `home_first_draw_engine_elapsed_usec`, not parent-process launch time.
Median Home from app-resource loading was 6.976 → 4.659 s. Each process performed
two real Home/Fly/Home cycles, giving five warm in-process repetitions per variant.
[Raw commands and exits](paired-loading.json), [derived values](summary.json) and all
ten individual reports/logs are retained. Engine: Godot 4.7.2 `ed1daf0bf`, Compatibility,
Ryzen 9 5900X / RTX 3090, NVIDIA 610.88, 1280×720, project 4× MSAA, VSync on,
60 FPS cap, Dummy audio. These observations do not qualify frame pacing or flight.

The initial isolated geometry experiment reduced the first default build from
2,774,557 µs to 18,461 µs. All eight default/warm/changed-input cases produced exact
matching mesh buffers. [Prototype report](geometry-parity.json) identifies its source;
it predates the compiled stamp and is attribution evidence, not final-source timing.

## Implementation contract

The generated resource is **739,572 bytes**. It holds CPU arrays, full normalized
lake/ground keys, engine and precision metadata, source hashes and array digests.
It seeds the existing single-entry caches; scenes still create independent meshes,
materials, probes and nodes. Ground-only changes can reuse water while regenerating
the basin. Custom lake inputs invalidate both entries. Missing or incompatible
resources use the original procedural builders.

The compiled stamp works when exported source scripts are compiled. Runtime verifies
the resource against that stamp; it does not read current source text. The source test
and generator `--check` detect stale source/stamp/arrays. Regenerate both outputs after
changing any covered sampler or renderer source. See the authoritative
[generation and check commands](../../../../../../tools/ground/README.md#dt-11a-default-lake-geometry).

## Final verification

| Check | Result |
| --- | --- |
| Bake parity, source freshness, metadata/invalidation | 18/18 on Windows and Linux; fresh procedural basin and water match every serialized array |
| Actual build with procedural builders disabled | Valid bake succeeds with exact reference buffers |
| Actual build with missing, stale-format or incomplete resource | All three regenerate exact reference buffers; no engine errors |
| Lake world | 27/27: independent scene resources and input invalidation |
| Field integration | 39 passing checks, including failed-start restoration |
| World presentation context | 17/17 |
| Fresh sparse Git checkout plus owned candidate overlay, no copied import cache | 18/18 and generator `--check` pass |
| Empty-project exported-lake smoke | Pass; resource and compiled source stamp load from the PCK |
| General field-pack smoke | **Fail** after the lake guard; vegetation UID fallback warnings and the legacy `NearGrass` assertion were observed; see the follow-up above for resolution |

[Final check commands](final-checks.json) and [fallback results](bake-guards.json) are
retained with logs. A separate [final-source native smoke](final-native.json) completed
two cycles: 546 nodes at Home, 878 in flight, zero orphan nodes after returns,
unpaused first draws at tick 12. Its Home time was 9.116 s and first/warm Fly were
2.870/2.172 s; it is not pooled into the earlier paired campaign.

Six of the ten paired logs and the final smoke report two ObjectDB instances leaked
at exit. Zero orphan nodes does not close that finding or the 50-cycle/30-minute soak.
All final passing check logs were scanned for engine errors. The full `app/test.sh`,
visual capture suite and pilot/platform acceptance were not run. No goldens changed.

## Export and failure ledger

`--editor --export-pack Windows` completed with exit zero, but its
[log](export-pack.log.gz) includes import/hash errors. The
[full empty-project smoke](check-pack.log.gz) passed the new lake guard and subsequently
failed in broader field/scenery checks. No matching baseline export was run, so this
report does not establish the origin of those failures. The focused `--lake-only`
check passes cleanly and does not replace full package acceptance. The manifest records
the experimental PCK hash/size; this package is not a release artifact.

Earlier excluded attempts remain visible:

- `loading-before.log.gz`: current shared tree encountered a controller integration
  parse error before a valid loading report. Timing moved to isolated source snapshots.
- `pair-1-baseline.log.gz` and `loading-pairs.json`: first snapshot omitted required
  aircraft authoring files/native extension state. The harness was repaired before
  the retained five-pair campaign; this failed attempt is not a timing sample.
- `test-bake-windows.log.gz` / `test-bake-linux.log.gz`: malformed-metadata tests
  initially emitted engine errors despite successful test exits. Explicit required-key
  guards removed those errors; final Windows/Linux logs pass cleanly.

## Identity, reproduction and next work

[Manifest](evidence-manifest.json) pins engines, final owned files, PCK and every
retained artifact. [Measured source inventory](isolated-source-manifest.json.gz) pins
both timing snapshots: `22b3e482` app plus the prior in-memory cache for the baseline,
and generated-resource loading for the candidate. Compressed `reference.gd`,
`measured-candidate.gd` and `measured-stamp.gd` preserve those overlays. The final
metadata omission guard was hardened after the paired timing snapshot; valid-buffer
geometry and loading strategy did not change. Final tests/smoke use
`final-candidate.gd.gz` and the [final isolated source inventory](final-isolated-source-manifest.json.gz).
`final-source-manifest.json` is the owned overlay used for export; the external pack
checker subsequently gained the explicit `--lake-only` mode, pinned in the main manifest.

Use the [loading probe commands](../../../../../../research/performance/README.md#homefly-loading-and-lake-geometry)
against separate frozen projects; serialize timing runs. Extract compressed source
snapshots with their original paths and regenerate the bake with the pinned engine.
Disposable fallback copies retain original absolute paths: update their bake paths
when relocating them, keep them outside `app/`, and run `bake_guards.gd` beside the
copies and `lake_terrain_reference.gd`. Gzip storage preserves original bytes.

Next: attribute remaining synchronous Home construction and first-flight setup on the
final source, resolve the broader package smoke, and collect qualified native/soak
evidence. Visibility, textures, shaders and quality-profile gates retain the order in
the [global plan](../../../../../plans/global-performance-visual-quality.md).
