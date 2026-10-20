# DT-11a / L11a — assemble the grass checksum once

2026-10-19. Official Godot 4.7.2-stable (`ed1daf0bf`), Windows x86_64,
Compatibility, Ryzen 9 5900X / RTX 3090 / NVIDIA OpenGL 617.42. Shared-host load,
power and OS caches were uncontrolled. These are complete CPU validation and
direct grass-construction measurements; full Home/Fly loading and FPS were not measured.

## Change

`NearGrass.validated_rows()` previously appended each of 6,000 formatted rows to
a growing checksum string. It now collects those same fragments in a local
`PackedStringArray` and [joins them](https://docs.godotengine.org/en/4.7/classes/class_string.html#class-string-method-join)
once before SHA-256. The three-line runtime change preserves the validation
order, integer formatting, row order and trailing newline. Accepted calls still
return the caller's original rows array; rejected calls still return an empty array.
The test's original concatenation-based digest remains an independent oracle.

This introduces no retained cache. The temporary array has at most 6,000 strings,
plus the joined canonical text during hashing. Peak memory/RSS was not measured.
No placement data, visual settings or simulation behavior changes.

The original source matches `app/render/near_grass.gd` at
`abdd9c7e559ceee2cafd2fd583f9413286b344bf` after line-ending normalization.
[Reference bytes](reference.gd.txt), [runtime/test patch](runtime.patch),
[source and engine identities](manifest.json), [raw commands](commands.json)
and [summary](summary.json) retain the comparison. Other tracks shared the tree;
the identified builder dependencies and exact output checks define this scope.
Luna Max helpers reviewed candidate semantics, regression cases and claim boundaries;
the lead integrated the change and ran measurements/tests serially.

## Native paired measurements

Five fresh processes reverse initial reference/candidate order. Each measures
eight alternating complete validations and six alternating complete builds for
each of three layouts: the normalized default field, a pilot translated by
`(+8, -6)` m, and the default field with a gravel exclusion polygon. Validation
timings start after JSON parsing. Build timings include file read, JSON parsing,
validation, clipping, mesh/material creation and all MultiMesh instances. Freeing,
frame waits, readback and comparison are outside the timers. The probe constructs
nodes off-tree; it does not measure drawing or run flight physics.

| Complete workload | Reference, ms | Candidate, ms | Reduction | Per-process reduction |
| --- | ---: | ---: | ---: | ---: |
| Validate 6,000 rows | 80.850 | 14.375 | 82.2% | 80.4–85.3% |
| Direct build: default field | 106.842 | 39.204 | 63.3% | 59.2–65.6% |
| Direct build: translated pilot | 105.163 | 35.936 | 65.8% | 62.0–66.0% |
| Direct build: gravel mask | 109.578 | 30.654 | 72.0% | 69.2–72.0% |

Values are medians of five process medians. There are 40 timed validations and
90 timed complete builds per variant. Every workload improves in every process,
exceeding the 5% adoption threshold. Absolute timings vary substantially: process
2 has higher reference and candidate times; it remains in the report. All five
measurement logs finish with exit zero and no engine errors or warnings.

All **90 native build pairs** preserve exact chunk names/counts, instance buffers,
mesh surface arrays, transforms, custom AABBs, shadow settings and shader parameters.
The 15 fixture comparisons also preserve exact clipped placement bytes.
Default/translated/masked layouts contain
4,533/3,732/791 clumps and 54,396/44,784/9,492 buffer floats respectively. Buffer-size
guards reject empty dummy-renderer readback. Each pair also checks independent
MultiMesh, mesh and material resources. State hashes are stable across processes.

Nine differential validation cases per process cover committed data, mixed integer
and float values, reversed/rehashed rows, a bad checksum, fractional or malformed
final rows, duplicate centers, points outside the disk and NaN. All preserve input
bytes and agree on acceptance, exact returned bytes and accepted-array identity.

`FieldBuilder` normally routes the default field with scenery through
`ImportedNearGrass`, which caches its validated rows. This change helps its first
validation, but does not accelerate subsequent cache hits. The direct builder is
used for the fallback/no-scenery route. These measurements establish neither
complete default-world startup savings nor repeated Home/Fly or FPS gains.

## Regression results and existing native diagnostics

[Candidate tests](tests.json) record **417 passing assertions in seven headless
suites**: near grass (40), imported near grass (59), scenery masks (34), mask
bounds (23), imported grass wind (204), ground materials (38), and field surfaces
(19). Two permanent assertions cover accepted mixed numeric types/array identity
and rejection of a fractional final yaw despite an unchanged canonical digest.

The wider native tests are **not clean passes**. `test_near_grass.gd` exits 1:
its existing standalone-registration assertion calls the editor-only
`global_shader_parameter_get_list()`, producing two engine errors and one failed
assertion. `test_imported_near_grass.gd` passes 59 assertions but reports six
missing `sim_clock`/`wind_vec` warnings. Three headless field-building suites also
report the existing unsupported-maple-material wind fallback warning.

[Reference tests](reference-tests.json) reproduce all these diagnostics using the
original validator in a disposable app copy with the same updated tests and
dependencies. The native measurement probe registers shader globals before
construction and does not use the editor-only inspection API; its exact-output
campaign is clean. The wider test harness issues remain separate work.

## Reproduce

Create a new output parent and extract the reference outside `app/`; retain its
original `res://` dependencies. Run the committed probe with the pinned native
engine (headless is rejected):

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --path app --audio-driver Dummy `
  --resolution 64x64 --position 4000,4000 `
  --script "$PWD/research/performance/grass_validation_probe.gd" -- `
  --reference="$PWD/tmp/near_grass_reference.gd" `
  --candidate="$PWD/app/render/near_grass.gd" --output="$PWD/tmp/grass-new/run-0.json"
```

Repeat in five fresh processes with new output files; add `--candidate-first` to
odd-numbered processes. Keep stdout/stderr through process exit, require exit zero,
`complete=true`, exact parity, matching source/data/probe hashes and no engine
errors or warnings. Do not overlap timing runs with other benchmarks. The recorded
host was shared, so absolute timings are local evidence rather than a hardware guarantee.
