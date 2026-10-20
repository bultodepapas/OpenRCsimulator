# DT-11a / FW-24-R1 — reuse intrinsic star-catalogue data

2026-10-19. Official Godot 4.7.2-stable (`ed1daf0bf`), native Windows x86_64,
Compatibility, Ryzen 9 5900X / RTX 3090 / NVIDIA OpenGL 617.42. Shared-host load,
power, OS caches and other tracks were uncontrolled. This measures complete CPU
`Stars.build()` construction, not full World/Home/Fly loading, drawing or FPS.

## Change and ownership

Every eligible star-field build previously reparsed 5,080 catalogue rows and
recomputed their equatorial vectors, colours and flux. The renderer now retains
one prepared catalogue keyed by the complete file text. It still opens/reads the
file each call, so same-length and same-timestamp edits invalidate the cache.
Each placement applies the current sidereal-time/latitude basis. Cold preparation
creates the output and converts the private parsed rows in one pass.

Public `rows()` still returns freshly parsed raw data; placement dictionaries and
each build's MultiMesh, mesh and material remain independent. Empty/rejected text
and a failed open retire the prior cache. Row-level malformed data keeps the
reference's existing lack of validation; this change does not extend its schema.
Retention is bounded to one source string and one prepared set (5,080 value rows
for the shipped 114,389-byte catalogue), independent of the number of sky states.
Actual resident-memory cost and long-soak behavior were not measured. No nodes,
textures or materials enter the cache. Godot's [static-variable lifetime rules](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html#static-variables)
apply; this cache intentionally survives scene replacement.

The reference is `app/render/world/stars.gd` at
`5e2fbe32da2531928f01164fc9923cde943918f9`. Source/data/engine hashes are in
[summary.json](summary.json). Five verified reports match the integrated source,
probe and catalogue hashes. Luna Max helpers investigated candidates, drafted
regressions and reviewed ownership/invalidation; the lead integrated and verified.

## Native paired campaign

Five fresh processes reverse initial reference/candidate order. Each measures its
first call, ten alternating pairs with an explicitly empty candidate catalogue,
then ten alternating warm pairs at each of eight LST/latitude states. Source reads,
placement construction and complete render-resource creation are timed; freeing,
frame waits, readback and comparison are outside the intervals. Registering shader
globals before construction avoids the initial smoke probe's `sim_clock` warning.
The five verified process logs have no engine errors or warnings.

| Process | Warm reference median, ms | Warm candidate median, ms | Reduction |
| --- | ---: | ---: | ---: |
| 0 | 16.618 | 8.654 | 47.9% |
| 1 | 13.394 | 6.266 | 53.2% |
| 2 | 16.404 | 7.504 | 54.3% |
| 3 | 17.809 | 8.140 | 54.3% |
| 4 | 20.844 | 9.354 | 55.1% |

Median of process medians: **16.618 → 8.140 ms, 51.0% less repeated construction
time**. All five processes improve. These are 400 measured warm builds per variant.
[Verified reports and commands](verified-commands.json) retain every raw duration.

Cache-empty medians remain mixed: reference/candidate pairs in milliseconds are
**15.076/20.903, 21.672/21.060, 17.926/17.456, 22.152/20.797, 22.106/21.946**.
One process is 38.7% slower; the others are 0.7–6.1% faster. First-call readings
also vary with process/order. Cold-construction non-regression and startup benefit
remain unqualified. Do not sum construction savings into a Home/Fly or FPS claim.

All **40 native state pairs** preserve exact placement bytes, all **101,600 float32
MultiMesh buffer values**, and every star shader parameter. Latitudes include both
poles, the equator and ±40°; LST, cloud seeds and cloud offsets vary. The existing
astronomy checks continue to verify direction, colour and flux known answers.
The instance-buffer size guard rejects empty headless readback.

`run-*.json` and `final-*.json` are earlier candidate campaigns, not pooled with the
verified measurements. Their source/probe snapshots are retained as `trial-*.txt`;
the final revision also clears retained data after a failed file open.

## Verification and reproduction

The production renderer, updated test and probe parse. **Seven focused suites pass
all assertions**: stars 45, world sky 38, ephemeris 34, sky configuration 77,
presentation context 17, time-of-day render update 94 and sky checkpoint 45.
Native stars also passes **45/45**, without warnings or shutdown errors.
The new public-API regressions use a disposable in-memory script and test-owned
JSON; they cover repeated output, caller mutation, current basis, same-length
content changes, missing/empty catalogue recovery and independent render resources.
The shipped catalogue is never edited by the tests.

The strict initial warning ledger, [verification.json](verification.json), flags two
suites despite zero assertion failures: sky deliberately supplies `teatime`/`25h`,
and checkpoint loading reports the existing unsupported-maple wind fallback.
Both warning sets reproduce on the unchanged renderer; [summary.json](summary.json)
records their classification without suppressing the raw warnings. The first
disposable reference launch lacked sibling authoring assets and was refused; its
[failed setup log](reference-copy-missing-sources.log) is retained. The corrected
copy mounts the same source assets and passes all 45 checkpoint assertions.

Extract the reference outside `app/`, create a fresh output filename, then run:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy `
  --resolution 64x64 --position 4000,4000 `
  --script "$PWD/research/performance/stars_build_probe.gd" -- `
  --reference=<absolute-reference.gd> --candidate="$PWD/app/render/world/stars.gd" `
  --output=<new-report.json>
```

Repeat in fresh processes; alternate `--candidate-first`. The existing project
import is required. [Godot's manual timing guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html#manually-timing-functions)
explains repeated measurement. Full app CI, exports, full-night loading, first draw,
GPU/frame pacing, soak and other platforms remain outside this focused result.
Simulation code/data and golden flights are unchanged by this slice; parallel work
in the shared tree is preserved. `git diff --check` passes.
