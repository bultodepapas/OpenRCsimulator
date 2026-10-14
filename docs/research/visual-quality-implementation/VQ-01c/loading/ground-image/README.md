# DT-11a — reuse the existing ground image bytes

2026-10-14. `Ground.grass_material()` now reuses one lazily computed default RGB8
image buffer, including all eight mip levels. Every build still receives a new
Image, ImageTexture and ShaderMaterial. The recipe, seed, shader, filtering,
lighting, terrain geometry and physics are unchanged. No asset was added.

## Attribution and implementation

The instrumented Home/Fly route on `067d1255` spent 134–142 ms per field build in
the ground-material/surface-configuration interval. The same 256×256 three-octave
noise recipe ran again at each transition. This route also exposed an inherited
`main.gd` call to the not-yet-committed `FlightSession.gear_state()` method. Its
[phase report](attribution/phases.json) and log are attribution only, not valid
flight or loading acceptance. No unrelated flight integration was changed here.

The isolated [material probe](material-parity.json) compares the original and
candidate constructors, alternating their order. All six pairs have identical
shader/uniform signatures and complete texture/mip bytes. Readback and signature
generation are outside the timed interval. After the first pair, median CPU
construction is **139.394 → 0.610 ms**. This includes texture submission, not GPU
draw time. First candidate construction still computes the recipe (140.541 ms in
this probe); there is no cold-generation improvement.

The cache retains exactly **262,143 image-data bytes**, not an unbounded seed map
or scene resource. This is the buffer size, not a measured RSS/VRAM change.
`grass_image(seed)` remains uncached and preserves explicit seed behavior. Only
the material's fixed default recipe uses the cache. Mutating an image, updating a
texture or changing a material uniform cannot affect another scene or later build.
Changing the recipe in source takes effect when its script starts a fresh process.

## Complete transition observations

To avoid the partially integrated gear interface, the comparison copies the
previously verified `5f7f4ad529940743bdc16e3d9691243a8a1c6cd8` archive/import
snapshot. Its original `ground.gd` is text-identical to the attribution/current
source after line-ending normalization. The candidate changes only that file.
[Source verification](source-verification.json) checks the archived inputs and
the prior import-generated files; [manifest](evidence-manifest.json) pins tools,
engines, treatment and retained reports. This is not current-HEAD or package
qualification.

Five serial process pairs alternate AB/BA, two real Home/Fly cycles per process,
using the existing loading probe, 1280×720, 4× MSAA, VSync, 60 FPS cap and Dummy
audio. Windows, Ryzen 9 5900X, RTX 3090, NVIDIA 610.88, Godot 4.7.2 `ed1daf0bf`.
OS/import/driver caches, foreground host activity, refresh and power state were
not frozen. A source-hash verification also ran during the campaign; these are
development observations, not idle-host release qualification.

| First post-draw boundary | Reference median | Candidate median | Paired result |
| --- | ---: | ---: | --- |
| Initial Home, engine elapsed | 7.843 s | 8.307 s | Mixed; candidate slower in 3/5 pairs |
| First Fly | 3.376 s | 2.869 s | All five improve, by 4.4–24.2% |
| Second Fly | 2.469 s | 1.998 s | Four improve; one regresses 0.15% |
| First return Home | 1.609 s | 1.271 s | All five improve, by 10.0–33.3% |

[Full paired distributions](pairs/metrics.json) include synchronous boundaries;
initial synchronous Home regresses in four pairs. The cache does not skip any
initial computation, but the measurements do **not** establish cold-load
non-regression. Do not attribute the entire transition difference to the measured
139 ms phase or pool these timings with older campaigns. Retain this bounded
repeated-work removal with exact output parity; keep the complete loading and
no-regression gates open. Home ≤5 s and first Fly ≤2 s are still missed.

All ten processes complete without engine errors/exit warnings: 20 unpaused first
flight draws at tick 12, 879 flight nodes, 549 return-Home nodes, zero reported
orphans and released observed audio playbacks. These short cycles do not qualify
Workshop/reset coverage, a 50-cycle production lifecycle or a 30-minute soak.

## Verification

- New cache regression: **16/16** in Windows headless and native Compatibility;
  **16/16** in Linux/WSL headless. The current shared tree also passes 16/16.
- Frozen-snapshot integration: field surfaces **19**, near grass **38**, field
  lifecycle **39**, world presentation context **17**, Workshop trial **36** checks
  pass. Workshop's deliberate frozen-presentation rejection emits its expected
  warning; no unexpected engine errors occur.
- A disposable shared-Image mutation is rejected by seven checks, including live
  and future-image isolation. Its errors are expected; the candidate is restored.
- The draft parsed outside `app/` before integration. `app/test.sh` automatically
  discovers the new `test_ground_image_cache.gd` through its existing test glob.

[Check commands/logs](checks/results.json) retain scope and warning details. The
full app suite, fresh exports, visual flight suite and native Linux/macOS display
qualification were not run. Exact image/uniform equality is not pilot readability
or hardware acceptance. No golden data changed.

## Reproduction and failure ledger

Run the focused regression with the pinned engine:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_ground_image_cache.gd
```

For CPU attribution, decompress `material_probe.gd.gz` and `ground_reference.gd.gz`
outside `app/`, then run the probe with `--path <candidate-app> --script <probe>`
and user arguments `--reference=<reference.gd> --output=<new-report.json>`. Omit
`--headless` for the retained native texture-readback path. The retained
`campaign.py.gz` and [campaign commands](pairs/campaign.json) describe the serial
process pairs; substitute new disposable paths and preserve both sibling `app/`
and `assets/` trees. The [loading guide](../../../../../../research/performance/README.md#homefly-loading-and-lake-geometry)
owns the probe contract.

The initial comparison copy omitted sibling authoring assets; model validation
correctly refused Home/Fly. Its failed log/command record is retained under
`failed-harness/`; it contributes no timing sample. The attribution revision's
gear-interface errors remain in `attribution/`. The fresh attribution import has
eight existing OBJ ambient-material warnings and no engine errors. Two scratch
Python preparation attempts failed before mutation (shell quoting and CRLF anchor
handling); corrected scripts are retained. The deliberate shared-Image mutation
is separately labelled as an expected failure.

API references checked 2026-10-14: Godot [Image.get_data / create_from_data](https://docs.godotengine.org/en/stable/classes/class_image.html)
and [PackedByteArray](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html).
The pinned-engine mutation and byte checks establish the ownership/parity result.

Next: isolate the remaining initial Home and first-Fly work on a consistent
current snapshot and an idle host. Native/package/soak gates and the ordered
[global plan](../../../../../plans/global-performance-visual-quality.md) remain open.
