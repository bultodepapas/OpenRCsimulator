# DT-11a — reject crowded shoreline candidates before terrain queries

2026-10-19. **Adopted:** complete botanical construction improved **25.1%**, from
**69.008 to 51.686 ms**, across five fresh native processes. The runtime change
moves one existing rejection check; it adds no persistent cache or retained data.

## Mechanism and equivalence

`BotanicalHabitats._append_shore_plant()` previously sampled terrain and checked
footprints before testing distance to already selected plants. Crowded candidates
now fail the same spacing predicate first. Each avoided terrain query skips center
and four neighbor evaluations. Candidate generation, seed consumption, the strict
`distance < minimum_spacing` boundary, terrain acceptance and returned records stay
unchanged. Both predicates are read-only.

An instrumented layout probe records **141 → 56 shoreline queries** for the default
recipe, with the same **285 plants**, including 56 shoreline plants. Low/balanced
quality still use the same deterministic source recipe before selecting subsets.
A completely blocked shoreline retains all 3,584 terrain queries and returns no
shore plants, as before. These counters were collected outside timing runs.

All **30 timed whole-field pairs** match geometry and botanical metadata. The probe
hashes stable node names/classes, transforms, mesh arrays/bounds/primitive types,
MultiMesh buffers/counts/bounds, and the habitat's ordered plants, zones, species
groups and budgets. Field input bytes remain unchanged. It does not compare every
material property or rendered pixel.

The [layout probe](layout-parity.json) additionally matches complete serialized
plant records and leaves inputs unchanged in **18 cases**: three quality levels
across default, absent lake, shifted pilot, blocked shoreline, invalid lake and
foreign-field inputs. Invalid/foreign cases correctly remain empty.

## Measurement

Windows, official Godot 4.7.2-stable, RTX 3090, Compatibility renderer. Each process
builds six alternating reference/candidate pairs with unchanged inputs. Processes
2 and 4 reverse the initial variant. Pair zero remains in raw results but is
excluded from warm medians because unrelated asset caches are shared.

| Process | Botanical reference / candidate, ms | Whole-field reference / candidate, ms |
| --- | ---: | ---: |
| 1 | 67.390 / 51.686 | 838.668 / 806.335 |
| 2 | 70.682 / 62.086 | 848.430 / 946.808 |
| 3 | 70.197 / 52.982 | 824.332 / 774.140 |
| 4 | 69.008 / 49.697 | 807.577 / 728.517 |
| 5 | 45.244 / 32.512 | 599.276 / 593.207 |

The headline uses median-of-process-medians from [summary.json](summary.json).
Botanical construction improves in all five processes. Whole-field medians vary
substantially, including a slower candidate in process 2; this does **not** establish
a reliable whole-field or Home/Fly loading gain. Construction is detached, so it
does not measure frame rendering or GPU cost. Host/background activity and OS caches
were uncontrolled. The original exploratory run is also retained.

## Regression and lifecycle checks

Five targeted production suites pass:

- Downloaded habitats: **329 checks**, including six new checks for accepted seed
  advancement, rejection of an occupied seed, valid/spaced replacement, immutable
  selected plants and exhaustion after exactly 64 candidates.
- Botanical scene: **18 checks**.
- Woodland edge: **29 checks**.
- Field integration: **39 checks**, including independent Home/flight resources.
- Scenery build: all geometry, determinism and construction-budget checks pass.

The downloaded-habitat test originally failed 66 assertions on both the candidate
and an unchanged-reference control. Its whitelist omitted existing downloaded
grass/shrub assets, its farm assertion excluded existing margin accents, and its
triangle assertion predated those accents. The corrected test explicitly admits
the three already-authored assets, requires 24 farm-margin accents, preserves the
original 83,650 triangles and requires exactly 1,986 accent triangles (85,636 total).
The 90,000-triangle limit and all terrain/clearance/quality checks remain strict.
The repaired 329-check test passes against both algorithms. Original failures and
reference controls remain in [checked evidence](checks.json).

The final native [Home/Fly smoke](production-loading.json) completes three real
Fly/End-flight cycles. Each first draw is unpaused at tick 11; every return has zero
orphan nodes. Flight/Home node counts are 1,098/622. Audio releases and the isolated
settings sidecar is removed. It is a lifecycle smoke, not a paired loading benchmark.
The existing maple material/wind warning is retained; accepted checks have no engine
errors or ObjectDB leaks. No full CI, exports, long soak or other-platform tests ran.

## Evidence and reproduction

Baseline commit: `b81905b42303d5d0dfd0f4ed305f4861a655e7ae`. Runtime source matches
the retained candidate after newline normalization. [Runtime/test diff](runtime.patch),
[manifest](evidence-manifest.json), compressed source/data hash map, original scripts,
raw JSON and checked engine logs preserve the measurement and test repair.
The script/data hashes were checked between all timed processes; unrelated concurrent
tooling work was preserved.

For a current production regression:

```powershell
python tools/godot/run_checked.py --timeout 60 --require-text '329 checks, 0 failures' -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_downloaded_habitats.gd
```

For the paired measurement, decompress `reference.gd.gz`, `candidate.gd.gz`, the
four `field_*`/`scenery_*` snapshots and `field_compare.gd.gz` together outside `app/`.
In the four copied callers, replace the original
`C:/DEVELOPMENT/OpenRCsimulator/tmp/botanical-spacing-20261019` preload prefix with
that new absolute directory. Run from the repository root:

```powershell
$probe = (Resolve-Path tmp/botanical-repro/field_compare.gd).Path
python tools/godot/run_checked.py --timeout 120 --require-text 'field comparison pairs=6 failures=[]' -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script $probe -- --output="$PWD/tmp/botanical-pair-new.json"
```

Use new output files and fresh processes, alternating `--reverse`. Decompress
`layout_compare.gd.gz` beside the same scripts to run the 18-case comparison
headless with `-- --output=<new.json>`. To collect query counts, decompress and run
`make_trace.py.gz` there first, then add `--trace`. These commands use the remaining
current project dependencies; historical reproduction also needs the pinned source
and asset versions. No FPS, physical-validation or first-load improvement is claimed.
