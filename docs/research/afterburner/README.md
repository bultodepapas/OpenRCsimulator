# Jet afterburner research

**Research date:** 15 November 2026. **Status:** proposal and standalone preparation; production integration remains pending.
**Reviewed source:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`. **Engine:** `4.8.beta2.official.cafc17a19`.

Start with the [proposed implementation plan](../../plans/jet-afterburner.md), then the [complete dated handoff](2026-11-15/handoff.md). The handoff retains all 52 investigation records, source registers, physical/audio/control integration, visual decisions and independent review. The standalone stream reports retain their own provenance and source context.

## Research and decisions

| Collection | Reports |
|---|---|
| 28 engineering investigations, I01–I28 | [Question register](2026-11-15/round2/investigation_plan.md), [physics](2026-11-15/round2/physics.md), [graphics](2026-11-15/round2/graphics.md), [audio](2026-11-15/round2/audio.md), [integration](2026-11-15/round2/integration.md), [independent review](2026-11-15/round2/independent_review.md) |
| 24 additional effects investigations, FX01–FX24 | [Question register](2026-11-15/effects/investigation_plan.md), [flame/turbine references](2026-11-15/effects/flame_reference.md), [geometry/shaders](2026-11-15/effects/shader_techniques.md), [Godot tools/assets](2026-11-15/effects/tools_assets.md), [authoring/views/diagnostics](2026-11-15/effects/effects_workflow.md), [independent review](2026-11-15/effects/independent_review.md) |
| Evidence identity and limits | [Current research verification](2026-11-15/verification.md), [original-delivery source manifest](2026-11-15/source_manifest.json), [selected source drift](2026-11-15/round2/source_drift.json) |
| Historical 14 November standalone run | [Original verification](2026-11-14/verification_2026-11-14.md), [original manifest](2026-11-14/source_manifest_2026-11-14.json), [core receipt](2026-11-14/core-final/report.json), [visual-state receipt](2026-11-14/visual-state/report.json) |

## Development material

The [experiment guide](../../../research/afterburner/README.md) indexes the original isolated Godot prototype, numerical programs/results, MIT license and [proposed visual-study fixtures](../../../research/afterburner/development/README.md). The three profiles are draft art specifications; all 34 capture cases remain `not_run`. They are not accepted production aircraft data or an executable native capture runner.

The original prototype's 16 files and eight engine receipt/log files retain their original bytes. Original manifest paths and receipt absolute paths describe the delivery/execution layout at that time; they are not a claim that scratch paths exist in a checkout or that old hashes certify revised prose. Package-level checksums/ZIP certification and superseded verification duplicates are not current repository evidence. The illustrative image-metric chart is regenerated locally from its retained script/data instead of committed as a screenshot.

No afterburner feature, physical wet map, sound bank, downloaded flame artwork, native capture or hardware qualification is installed by this branch. Exact source reading, synthetic arithmetic, standalone state tests and physical validation remain distinct. Use the current [contribution workflow](../../../CONTRIBUTING.md#make-a-change) for implementation.
