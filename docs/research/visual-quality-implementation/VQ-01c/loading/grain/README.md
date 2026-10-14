# DT-11a — bake existing propeller grain and repair package verification

2026-10-14. Follow-up to the [default lake bake](../cold/README.md). The Stik now
loads its existing wood grain from a generated Image resource. All 524,301 RGB8
bytes, including ten mip levels, match the original recipe. No physics, geometry,
material, filtering, shader or golden-flight changes were made.

## Attribution and result

Separate instrumented Home runs identified aircraft construction as a remaining
synchronous cost: the detailed run spent 981 ms in the cold builder versus 100 ms
warm. A texture probe measured atlas/normal/grain creation at 41/194/1,699 ms.
These are separate observations, not additive phases of one run. The isolated
[parity probe](grain-parity.log.gz) measured original grain creation at 1,493,625 µs
and baked loading at 3,052 µs, with identical complete image data. The compressed
resource is 127,630 bytes. This removes repeated procedural work from process startup;
the existing shared texture cache still handles later scene construction.

Five serial fresh-process pairs alternated AB/BA on Windows, Ryzen 9 5900X,
RTX 3090, driver 610.88, pinned Godot 4.7.2 `ed1daf0bf`, Compatibility, 1280×720,
60 FPS cap, VSync enabled and Dummy audio. Each process completed two Home/Fly cycles.
OS, import and shader caches were uncontrolled; this is process-cold evidence,
not import-cold or cold-driver evidence. Host load/power/refresh were not frozen.
The median engine-clock Home first draw improved **10.747 → 8.809 s (18.0%)**;
all five pairs improved, but dispersion is substantial and the ≤5 s target is open.

| Pair | Baseline Home (s) | Baked Home (s) | Baseline synchronous Home (s) | Baked synchronous Home (s) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 10.954 | 10.315 | 4.481 | 3.838 |
| 2 | 12.183 | 11.957 | 5.260 | 3.551 |
| 3 | 10.747 | 8.809 | 4.374 | 2.973 |
| 4 | 9.345 | 8.518 | 3.854 | 2.821 |
| 5 | 8.660 | 6.309 | 3.540 | 2.331 |

[Raw commands/exits](campaign.json), all ten reports/logs and [full distributions](metrics.json)
are retained. Synchronous Home medians were 4.374 → 2.973 s. First Fly medians were
3.726 → 3.717 s, but the candidate was slower in four of five pairs (up to 0.475 s).
There is no demonstrated first-Fly benefit or closed no-regression gate. Warm Fly
medians were 2.676 → 2.541 s, also mixed across pairs. First-return Home medians were
1.836 → 1.742 s. Do not pool this campaign with the earlier lake campaign: background
variation and absolute timings differ. The mechanism/parity are established;
integrated performance qualification remains open.

All ten reports completed, with 546 Home/878 flight nodes, zero orphan nodes after
return and unpaused first draws at tick 12. Five logs still warn that two ObjectDB
instances leaked at exit (baseline pairs 3/4/5; candidate 1/3). This predates the
repair and remains unresolved; zero orphan nodes is not leak/soak acceptance.

## Implementation and package repairs

The [aircraft authoring guide](../../../../../../assets/aircraft/ugly-stik-60/README.md#generated-propeller-grain-dt-11a)
owns generation and freshness commands. The recipe remains in `ugly_stik_finish.gd`;
the external baker calls it directly. Literal resource loading keeps the image in
the model manifest dependency closure. Regenerate manifests through `build_models.py`.
Direct helper calls retain procedural fallback; the aircraft registry still rejects
missing or modified pinned dependencies before flight.

Clean export exposed two existing checks that no longer matched runtime behavior:

- The fixed-wing manifest export hook requested a nonexistent rotorcraft manifest.
  It now follows the runtime adapter's rotorcraft exclusion; existing airplane
  dependency/proof checks remain enabled.
- The field-pack smoke assumed four procedural grass quadrants even when imported
  grass was selected. It now validates the selected branch, actual source mesh/material,
  nonempty instance attributes and clump/triangle budgets. It still rejects empty or
  mismatched grass; detailed placement tests remain in their existing suites.

ZIP assembly also omitted the exporter-managed ground-vehicle native library.
Linux/Windows packaging now preserves the complete export directory and relative paths.
The actual Windows ZIP contained exactly the executable and DLL; extraction reproduced
both hashes and the extracted release executable completed its 240-tick flight trace.

## Verification and limits

| Check | Result |
| --- | --- |
| Exact grain/mips, texture reuse and material filtering | 7/7 Windows; 7/7 Linux; 7/7 fresh sparse clone before import |
| Image freshness / five model manifests | Pass |
| Model registry / package proofs | 75/75 and 29/29 |
| Imported grass / procedural near-grass | 27/27 and 38/38 |
| Fresh sparse checkout + owned overlay, no copied `.godot` | Import, Windows PCK and Windows release export exit 0; no engine errors |
| Full empty-project field smoke, imported / procedural | Both pass: 150 / 4,794 clumps, 1,680 trees, lake and cues |
| Actual embedded export resource parity | 7/7 through pinned editor probe beside exported DLL |
| Actual release executable and extracted ZIP executable | Both headless 1 s / 240-tick finite trimmed-flight traces pass |
| Embedded export Home/Fly | Two cycles through editor probe; complete, no engine errors |
| Updated packaging command / shell syntax | ZIP exact contents and byte parity pass; LF-normalized `bash -n` passes |

[Package commands](final-package-checks.json), [ZIP results](zip-check.json) and raw
traces are retained. `GodotProbe.exe` is the pinned editor engine copied beside the
DLL solely to execute external test scripts against the embedded export. It is not
shipped in the ZIP and its GUI run is not release-template GUI acceptance. The actual
release executable was tested through the application's trace entry point.

`current-tree-smoke.json` is an additional shared-tree observation including concurrent
controller changes; it is not the frozen benchmark baseline. No full `app/test.sh`,
full multiplatform `app/export.sh`, visual capture suite, pilot flight, Linux/macOS
package qualification, 50-cycle lifecycle run or 30-minute soak was performed here.
The manual export uses `export-manual` identity, not qualified release provenance.

## Failure ledger

Retain failed attempts as harness evidence; none enters the timing sample:

- `texture-phases.log.gz`: diagnostic attempted an unsupported static `call`; fixed
  probe uses direct method calls (`texture-phases-fixed.log.gz`).
- `pack-grain.log.gz` and `exported-grain.log.gz`: seven image checks passed, but
  missing native-library errors invalidated these runs. Putting the editor probe
  beside the exported DLL resolved the harness layout (`exported-grain-final.log.gz`).
- `export-windows.log.gz`: debug export failed because only release templates were
  installed. Release export passed; no dependency/template upgrade was introduced.
- `release-checks.json` / `release-grain.log.gz`: release template ignored the external
  tool script and remained at Home; that owned process was terminated. The replacement
  application trace and editor pack checks have distinct, passing roles.
- The previous lake report's export/grass failures remain historical; this report
  provides the clean-import/export and complete field-smoke follow-up.

## Identity and reproduction

[Manifest](evidence-manifest.json) pins final runtime/generator/check sources, engines,
PCK, executable, DLL, ZIP and retained artifacts. Large logs/source inventories are
losslessly gzip-compressed. `source-manifest.json.gz` records both benchmark snapshots:
`22b3e482` plus the preceding lake bake for baseline; candidate adds the grain runtime,
resource, generated Stik manifest and test only. Export-hook/grass-check repairs were
applied afterward and are pinned in `export-source-manifest.json.gz`; they were not
part of the timing treatment. ZIP assembly was validated against those exporter outputs.
The authoring guide and [loading probe guide](../../../../../../research/performance/README.md#homefly-loading-and-lake-geometry)
provide commands. Retained commands contain original absolute disposable paths;
substitute a new directory when reproducing. No large release binaries are committed.

Official API references checked 2026-10-14: [Image](https://docs.godotengine.org/en/stable/classes/class_image.html),
[ImageTexture](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html),
[ResourceSaver](https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html).
Pinned-engine byte parity, rather than live documentation version, establishes this bake.

Next: attribute remaining Home/first-Fly work and reproduce the mixed Fly results on
a controlled host before closing DT-11a. Native flight, leak/soak, visibility and quality
profile gates retain their order in the [global plan](../../../../../plans/global-performance-visual-quality.md).
