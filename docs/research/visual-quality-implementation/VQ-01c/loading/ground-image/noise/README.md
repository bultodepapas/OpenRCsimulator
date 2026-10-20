# DT-11a — prepare ground-noise coordinates once

2026-10-19. Godot 4.7.2-stable (`ed1daf0bf`), Windows x86_64 Compatibility,
Ryzen 9 5900X / RTX 3090 / NVIDIA OpenGL 617.42. Shared-host load, power and
OS/driver caches were uncontrolled. This measures complete CPU image generation
and cache-empty ground-material creation/texture submission, not completed GPU
work, full Home/Fly loading or FPS.

## Change and scope

The 256×256 grass recipe sampled three value-noise octaves at every pixel,
repeating coordinate scaling, flooring, periodic wrapping and easing 196,608
times. `Ground.grass_image()` now prepares wrapped column indices, row offsets
and interpolation factors at 256 positions for each octave. Both pixel axes
share those tables. RNG seed/grid fill order, four-corner reads, interpolation
order, weighted accumulation, RGB8 conversion and mip generation are unchanged.

The interpolation tables use [PackedFloat64Array](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html)
to retain the original GDScript float precision. Four int32 tables and one
float64 table per octave have **18,432 bytes of temporary element payload**;
container overhead and peak RSS were not measured. They exist only during one
call. No additional persistent cache is introduced; the existing default cache
still retains one 262,143-byte image/mip buffer and creates fresh scene resources.
Explicit seeds remain uncached. `_value_noise()` remains unchanged.

The normal material path computes this image on its first cache miss and reuses
the bytes afterward. This repair targets that first generation; it does not
reduce repeated warm default-material work. No image asset, shader, geometry,
graphics setting or physics behavior changes.

## Paired native campaign

Five fresh processes alternate reference/candidate order. Each measures four
complete image pairs for seeds `1253`, `1254`, `0`, `-1`, and `2147483647`, six
cache-empty material pairs, then ten warm material pairs as a control. Cache
retirement occurs outside the timer; RNG/table preparation, all pixels/mips,
texture submission and material configuration are included in their respective
complete constructors. Readback, hashing and frame waits occur outside timings.
OS, import and driver caches are never cleared.

| Complete workload | Reference, ms | Candidate, ms | Reduction |
| --- | ---: | ---: | ---: |
| Image, seed 1253 | 162.376 | 111.429 | 31.4% |
| Image, seed 1254 | 164.180 | 108.528 | 33.9% |
| Image, seed 0 | 169.311 | 108.464 | 35.9% |
| Image, seed -1 | 165.468 | 105.487 | 36.2% |
| Image, seed 2147483647 | 163.931 | 110.091 | 32.8% |
| Cache-empty default material | 172.878 | 111.111 | **35.7%** |

Values are medians of five process medians. Every image workload improves in
every process; process reductions range from 26.3–41.8%. Complete cache-empty
material reductions range from 30.5–37.8%, clearing the 5% component adoption gate.
All five measurement logs exit zero without engine errors or warnings.

The unchanged warm-material control measures 0.310→0.290 ms. Its process results
are mixed, from 0.9% slower to 20.1% faster; this does not establish a warm-path
gain. Full startup, interactive loading, frame pacing and platform qualification
remain open. Do not sum this local saving into a Home/Fly or FPS claim.

All **100 image pairs** preserve complete RGB8 bytes, all eight mip levels,
dimensions/format and independent Image identities. All **30 native material
pairs** preserve every shader parameter, grass texture/mip bytes and independent
material/texture resources. Per-seed image hashes and material hashes are stable
across processes. These comparisons inspect resource content and submission;
they do not establish synchronous GPU upload completion or rendered pixel timing.

[Summary](summary.json), [raw commands](commands.json) and `run-*.json`/`run-*.log`
retain every duration and comparison. [Manifest](manifest.json) pins engine,
runtime, test, probe and dependency hashes. The [original source](reference.gd.txt)
matches `app/render/ground.gd` at `abdd9c7e559ceee2cafd2fd583f9413286b344bf`
after line-ending normalization; [runtime/test patch](runtime.patch) records the change.

The [snapshot inventory](snapshot.json) records 2,765 copied source/config/data
files and the shared-tree status. Only the candidate ground source and updated
test replace their baseline copies. Existing large assets/imports are hardlinked
as read-only inputs; no editor import is run. Both variants use this same snapshot.
Luna Max helpers discovered/drafted the candidate and reviewed arithmetic,
test-oracle independence and claim boundaries; the lead integrated and measured.

## Regression verification

[Focused checks](tests.json) pass **177 assertions in seven invocations**: image
cache (18 headless + 18 native), enhanced ground material (38 + 38), field
surfaces (19), world presentation context (17), and ground surfaces (29).
The image test now retains the original scalar per-pixel recipe as its reference,
including default/1254 comparisons and additional zero/negative-seed checks.
It preserves repeated-call determinism, cache limits, image/texture/material
ownership, mutation isolation and lighting-uniform checks. The oracle shares
the unchanged `_value_noise` helper; it independently checks table preparation,
not a hypothetical future defect inside that scalar helper.

[Additional checks](additional-checks.json) run the original generator with the
same updated test, repeat the 18 checks headless/native in the shared tree, and
verify the [deliberate index mutation](mutation.json). Replacing the right-hand
column index with the left in a disposable script is rejected by the scalar
oracle. This expected failure is not a successful performance sample.

The field-surface integration test emits the existing unsupported-maple-material
wind warning. The original generator reproduces the identical warning in the
same snapshot. The other six focused invocations and both shared-tree image
checks have no engine errors or warnings. Full app tests and exports were not run.

## Reproduce

Extract the original ground source outside `app/` and retain its `res://`
dependencies. Use a separate imported app snapshot, copy its mutable code/data,
and avoid editor imports during the comparison. Create a new output parent:

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --path <snapshot-app> --audio-driver Dummy `
  --resolution 64x64 --position 4000,4000 `
  --script "$PWD/research/performance/ground_noise_probe.gd" -- `
  --reference="$PWD/tmp/ground_reference.gd" `
  --candidate=<snapshot-app>/render/ground.gd --output="$PWD/tmp/ground-noise-new/run-0.json"
```

Repeat in five fresh processes with new outputs, adding `--candidate-first` to
odd-numbered runs. The probe refuses headless rendering and existing outputs.
Retain stdout/stderr through exit; require exit zero, `complete=true`, matching
source/spec/probe identities and all parity checks. Run timing serially without
other benchmarks. Use the actual Windows executable so an external timeout owns
the engine process rather than a console launcher.
