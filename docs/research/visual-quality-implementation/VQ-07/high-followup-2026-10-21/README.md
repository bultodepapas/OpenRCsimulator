# VQ-07: field-cue color parity and Windows restart

2026-10-21. Follow-up to the [High trial](../high-trial-2026-10-21/README.md).
Base `e6fee2e923af194e69f6bef8af2102997fd9d488`; final source and retained artifacts
are identified by `manifest.json`. High remains experimental.

## Implemented correction

**2026-10-22 correction:** the [raw-metadata GPU oracle](../material-tags-2026-10-22/README.md) disproves the vertex-stage normalization assumption below for barrier metadata. That portion is superseded; the fragment palette correction remains.

The High Home backdrop exposed a beige windsock and gray timber rails. The
windsock fabric/support and custom flightline-barrier shaders now normalize
authored vertex colors through the existing renderer-specific helper. Barrier
material tags, fitting tone and board variation use the same normalized values.
The generic scenery fence already uses StandardMaterial3D's sRGB flag and is unchanged.

Vertex normalization alone did not restore the timber. Separate native probes
disabled sky reflections and material specular: neither removed the gray rails.
Decoding the two sRGB-authored wood palette literals for RD restored their brown
appearance. Compatibility keeps the accepted literals; texture samples, lighting,
roughness, geometry, collision envelopes and physical state are unchanged. This
is a color-space repair, not an artistic darkening or reduced lighting quality.
Godot distinguishes [source-color inputs](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#using-source-color)
from raw numeric values; the native comparisons establish this particular fix.

The existing capture tool adds fixed `flightline` and `windsock` views. The source
restart probe checks the button is enabled and emits its production signal;
this covers the handler but does not substitute for an actual input test.

## Verification and limits

Windows / RTX 3090 / NVIDIA 617.42 / Godot 4.7.2 `ed1daf0bf`. Native GPU runs
were serialized. Static captures use 1920×1080, 4× MSAA and 90 settled draws.

- Six matched daytime views compile/render on both native renderers. Five
  Standard PNGs are byte-identical before/after; the lake differs at 1,061 pixels
  by at most 1/255 per channel. Do not call the entire set exact. See
  `standard-parity.json`; this is not a motion or full-platform qualification.
- The orange cloth ROI moves from mean RGB `[150.5,125.8,87.0]` to
  `[134.3,67.4,23.7]`, near Standard `[135.8,64.5,21.6]` (8-bit screenshot
  values, not photometry). `color-rois.json` records the coordinates.
- Existing checks: barrier 216, windsock 19, windsock motion 35 and graphics
  restart 42, all with zero failures. Source restart completes three distinct
  processes, Standard → High → Standard, with Home present and isolated saves
  unchanged. Child receipts/logs are retained in `source-restart/`.
- Actual menu input also completed the Windows packaged round trip on the
  preceding trial executable and the newly exported corrected executable.
  Process command lines, renderer logs, screenshots
  and unchanged preference-file hashes are retained under `packaged-ui/`.
  A release `--script` attempt timed out because that route was ignored;
  its failed checked-runner receipt is retained, not counted as passing.
- A final High 18:00 static field-cue capture renders the corrected colors under
  dusk lighting. The 00:00 capture is almost black: this isolated builder does
  not establish full World night exposure/lighting. Retain it as a tool-coverage
  limitation, not a passed night-readability check; the production night route
  from the preceding trial remains the appropriate integration entrypoint.
- Known Forward+ `OpVectorExtractDynamic` messages and seven Texture RID exit
  warnings remain. The maple wind warning is unchanged. No full app-suite,
  macOS/Linux, different-GPU or pilot-readability acceptance is claimed.

## Timing diagnosis, before these material edits

One native High active-flight diagnostic, actual 1920×1080, VSync on, no extra FPS
cap, 240 Hz simulation, 10 s warmup + 60 s sample: 3,599 wall intervals,
p50 16.653 ms, **p95 18.307 ms**, p99 19.892 ms. Root GPU p95 is **4.974 ms**;
render CPU p95 is 1.014 ms. The sample still misses the 18 ms gate. GPU query
results can lag; these observations do not establish the cause of wall pacing.
No effect budget was cut, and no speedup is claimed. `high-diagnostics.json` and
`diagnosis.json` preserve the raw sample and reducer caveats.

## Decision and next work

Retain the localized material corrections and capture coverage: they resolve
visible regressions using existing assets, without changing simulation or adding
passes. The Windows menu route has direct evidence; broader renderer/platform
qualification remains open. Next: flowing-time sky continuity and motion checks,
then presentation/pacing attribution and the prescribed repeated native pairs.
Static timing and a single diagnostic cannot promote High to a qualified preset.

The local unsigned Windows trial is
`D:/OpenRCsimulator-scratch/high-followup-20261021/release/OpenRC Simulator.exe`,
with the exporter-managed `openrc_ground_vehicle.dll` beside it. This manual
export is not the tagged multi-platform release pipeline. The manifest records
both binary hashes; `packaged-ui/final-package-*` records its native menu check.
