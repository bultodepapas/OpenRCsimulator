# Verification and evidence — Revision 3

**Date:** 15 November 2026 (America/Bogota).
**Current source:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`.
**Original prototype source:** `f41d0fd2eb5483c609bcd858bcf22776eb311e14`.
**Engine pin:** `4.8.beta2.official.cafc17a19`.

## Evidence classes

| Class | Completed work | Scope |
|---|---|---|
| New effects research | 24 questions, completed records, primary sources, concrete decisions, proposed checks and limitations | Research, not 24 passed tests |
| Source inspection | Current OpenRC plus selected exact-pin Godot noise/material/importer/particle-storage files | Code-path evidence; no runtime behavior or benchmark |
| Shader/geometry arithmetic | Executed Python probe and saved JSON | Ideal blend/layer order, mapping determinant and continuous-cone normal examples |
| Image-metric arithmetic | Executed synthetic comparison, JSON and inspected plot | Same local error under different averaging areas; no quality threshold |
| Texture/volume costs | Saved explicit format/resolution/mip arithmetic | No allocated memory, bandwidth or GPU timing measurement |
| Development preparation | Three proposed profiles and 34 planned cases, all `not_run` | Internal JSON consistency, not production schema compatibility |
| Independent review | Source, math, profiles and assembled-document review | Resolved documented research/specification issues |
| Artifact checks | Counts, local links, JSON parsing, preserved source/receipts and file hashes | Deliverable integrity |
| Retained research | 28 Revision 2 investigations and their numerical evidence | Original date/scope retained |
| Historical engine checks | Original 97 core and 14 visual-state checks, imports and headless fixture boot | Performed 14 November only; unchanged, not rerun |

No new Godot or Blender process, GPU render, native target measurement, audio audition, production flight, hardware control check, external asset adoption or physical calibration occurred in this round. The numerical probes are not the engine test suite. A planned capture, estimate, source branch or static JSON assertion is not a passed production gate.

## Reproduce the new arithmetic from the repository root

```sh
python3 research/afterburner/shader_evidence/analytic_probe.py
python3 research/afterburner/workflow_evidence/diagnostic_examples.py
```

The first uses standard Python. The second additionally uses Matplotlib to regenerate its PNG. Inputs, formulas, assumptions and scope are preserved in each script and JSON output. Image values are exact normalized linear grayscale 0/1, not sRGB bytes or HDR render buffers. File formatting or plot metadata may vary with a different dependency version; numerical scope is separate from byte reproducibility.

The texture-cost JSON supplies its dimensional assumptions and per-mip sums; it does not query a graphics driver. All native visual decisions, including the one-shell versus two-shell comparison, remain pending.

## Research corrections that matter

- Correct or account for the starter's negative-determinant mapping before changing face culling; derive deformation-consistent normals or justify a simpler facing approximation.
- Do not assume adding transparent shells preserves apparent brightness or color ordering.
- Prepare first noise generation during loading, and handle already-ready, empty/error and canceled resource states.
- Preserve particle channel ownership. A fixed seed in `CUSTOM.z` is not an animation clock.
- Separate the scheduler's reachable 25 records from its 32-record defensive capacity; inject a consumer-boundary case only through an explicitly owned seam.
- Separate optional metal glow from gas/aperture emission and from a cosmetic LED ring.
- Respect the conditional planar lake view's linear capture, masks and single presentation update.
- Distinguish initial Effects Off, On→Off cleanup and Off→On preparation.
- Inspect a conservative local plume region as well as the whole frame; do not adopt the synthetic PSNR numbers as gates.

## Historical receipts remain historical

Original engine receipts and logs are retained under `../2026-11-14/core-final/`, `visual-import/`, `visual-state/` and `visual-runtime/`; their bytes are unchanged. The original manifest retains its recorded identities, and the verification prose has repository-relative links. [Original verification](../2026-11-14/verification_2026-11-14.md) explains the original graphical-launch failure and headless limitations. [Round-two independent review](round2/independent_review.md) retains its distinct research/arithmetic scope. An unchanged engine pin does not transfer a historical result onto new source or a future integrated feature.

## Remaining evidence

Implement the actual component/adapter and qualify geometry, color, fog, depth, filtering, particles, loading and reflections on native Compatibility, Apple Silicon Mobile and selected High platforms at 1080p. Complete the earlier physics/fuel, controls, replay, native/Workshop and causal-audio gates. Real-engine realism still needs independent installation data and uncertainty.

Future headless repository checks follow the current configured test queue; native graphics, audio and performance keep their dedicated routes. No unavailable tool or software-rendered timing is represented here as a native qualification.
