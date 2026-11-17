# OpenRC Simulator: strict shadow audit

17 November 2026 · Audit branch: `audit/shadows-2026-11-17`.

**Verdict:** the current implementation has useful native shadows and a deliberately simplified projected flight cue, but the combination is not qualified as convincing, coherent shadow coverage across the game. The missing aircraft self-shadow reported by the owner has a definite explanation when **Projected** is selected: that route suppresses native maps and draws onto a separate ground plane. In **Auto/Native**, a universal self-shadow failure was **not** established; source inspection finds normally lit aircraft bodies, so that complaint still needs the exact aircraft, material, light, camera and GPU frame.

This branch records **26 findings: 7 P1, 17 P2 and 2 P3**. It includes reproduced module defects, established representation limits, source-confirmed efficiency opportunities, design decisions and uncompleted native acceptance gates. It does not count all of these as new bugs. No production renderer, default, shader, aircraft asset or physics behavior is changed.

## Read the audit

| Deliverable | Contents |
| --- | --- |
| [Findings register](findings.md) | All 26 findings, exact source anchors, evidence class, consequences and acceptance conditions |
| [Technology review](technology-review.md) | Raster shadows, filtering, AO/contact shadows, NVIDIA/AMD techniques, current Apple RT progress and adoption decisions |
| [Validation and handoff](validation.md) | Executed checks, reproducible command, native scenario matrix, performance protocol and closure requirements |
| [Recorded observations](evidence/observations.json) | Machine-readable counterexamples from unchanged production modules |
| [Source index](evidence/source-index.json) | Frozen repository source identities and GitHub permalinks |
| [Source material inventory](evidence/asset-materials.json) | Five baseline-matched GLBs; 77 source materials and their alpha/emission metadata |
| [Reproduction runner](repro/run.py) and [audit probe](repro/probe.gd) | Bounded, exact-source headless campaign; no full-game or GPU qualification claim |

The authoritative implementation sequence remains [VQ-04b-S00…S12](../../plans/shadows.md). This dated audit supplies evidence and priorities to that sequence; it does not create a competing product plan.

## Frozen scope and evidence

| Item | Identity / limit |
| --- | --- |
| Repository | [bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator) |
| Audited source | [`3c91936ab8f9064daa798311b5fb3e89e28d3754`](https://github.com/bultodepapas/OpenRCsimulator/commit/3c91936ab8f9064daa798311b5fb3e89e28d3754), the inspected main baseline |
| Engine used for this campaign | Official Linux x86_64 Godot `4.8.beta2.official.cafc17a19`; full engine revision `cafc17a192acf67903910a68aeb3c076c0907a4b` |
| Executed | Checked import; 77 existing collection assertions; 50 existing blur assertions; 29 audit-specific assertions. **156 assertions passed**, zero checked engine warnings/errors. |
| Module integrity | 36 selected app files (34 runtime dependencies and two existing tests) copied byte-for-byte after matching their baseline Git blob; harness and engine hashes retained |
| Assets inspected | Five complete GLBs matched against their baseline Git blobs before reading material JSON; no asset substitutions |
| Not executed here | Full application startup/suite, screenshots, normal-speed flight, native GPU cost/residency, NVIDIA/Radeon/Apple hardware campaign or export-package qualification |

The headless fixture intentionally omits production autoloads, world assets and UI. A renderer name passed to the pure resolver is a policy input, not evidence that that renderer executed. Assertions that reproduce an undesirable behavior are successful audit evidence, not successful fixes. Raw checked logs and reports are under [evidence](evidence/).

## What currently owns the shadows

The baseline has five saved controls: **Quality** (Current/Low/Medium/High/Ultra), **Technique** (Auto/Native/Projected/Off), **Aircraft cue** (Auto/Sun/Vertical/Off), **Distance** (Auto/Near/Field/Far) and **Softness** (Auto/Hard/Soft). They share a process-wide native configuration owner; per-world lights can still veto casting or cap range. See [`shadow_settings.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/3c91936ab8f9064daa798311b5fb3e89e28d3754/app/render/shadow_settings.gd#L6-L105).

| Selected technique | Native directional maps eligible | Planar aircraft/field route eligible | Practical meaning |
| --- | --- | --- | --- |
| Auto | Yes | Yes | Preserves both existing routes; overlapping ground coverage needs qualification |
| Native | Yes | No | Supports surface-to-surface occlusion when the actual light, caster and material participate |
| Projected | No | Yes | Provides the supported planar cues; cannot supply aircraft self-shadow or arbitrary receivers |
| Off | No | No | Suppresses these direct-shadow routes; cloud transmission, AO and other ambient effects have separate contracts |

This table describes the recognized Compatibility, Mobile and Forward+ policy routes, not identical visual capability. Unsupported renderer fallback, source-level engine-off requests, cue overrides and activity-specific caps remain meaningful. Global `effective.native=true` is not proof that a particular light is casting.

### Native allocation and filtering

| Quality request | Directional atlas | Requested depth | Cascades | Filter enum before Hard override |
| --- | --- | --- | --- | --- |
| Current, normal Standard defaults | 4096² | 16-bit | 2 | 2 |
| Current, active High profile | 8192² | 32-bit | 4 | 3 |
| Low | 2048² | 16-bit | 2 | 1 |
| Medium | 4096² | 16-bit | 2 | 2 |
| High | 4096² | 32-bit | 4 | 3 |
| Ultra | 8192² | 32-bit | 4 | 4 |

These are requested configurations, not measured GPU formats or memory. Current inherits installed defaults and captured per-light base properties. The **High graphics profile** and **High shadow quality** are different controls. Near/Field/Far request 100/300/600 m; Auto respects the light's base, and ground activity can impose 35 m. Native quality does not resize the 256² aircraft projection or 256²–1024² field projections. For the default/Soft policy, active High graphics requests a 0.53° sun with directional PCSS, while Standard resolves to PCF; actual backend execution remains a native check. Hard sets source angle and filter to zero. Backend support is detailed in the [technology review](technology-review.md#raster-techniques-and-the-current-engine).

### Other shadow families

Aircraft projection uses a mesh snapshot, 256² MSAA mask, flat receiving plane and 13-tap blur. Field projection is bounded at 16 maps and 8,388,608 target pixels. The windsock has its own deforming caster. Clouds apply separate spatial direct-light transmission to ground/near-grass. High ambient occlusion supplies a different lighting term; the rejected contact-shadow experiment remains off. Selected landing and field lights explicitly disable local native shadows. Wreck blobs and propeller/rotor representations have their own limitations. Each is traced individually in the findings; a single Quality slider cannot make all of them consistent.

## Main findings

| ID | Priority | Finding | Evidence |
| --- | --- | --- | --- |
| [SA-01](findings.md#sa-01--projected-cannot-satisfy-aircraft-self-shadowing) | P1 | Projected cannot self-shadow aircraft | Reproduced routing; structural limitation |
| SA-02 | P1 | Auto retains potentially overlapping native and planar ground coverage | Source; paired images required |
| SA-03 | P1 | Projected hinges and mechanisms retain their binding pose | Reproduced installed geometry and redraw behavior |
| SA-04 | P1 | Planar reception/fade ignores terrain and nearer surfaces | Reproduced fixed plane; source |
| SA-05 | P2 | Projected masks discard alpha; custom alpha paints also risk native casting | Reproduced geometry; source/material review |
| SA-06 | P2 | Fixed low-sun aircraft and field cues use different directions | Reproduced 4.24854× projection-offset ratio |
| SA-07 | P2 | Angular cache reuse has no geometric error bound | Reproduced 49.27 mm synthetic counterexample |
| SA-08 | P1 | Projected lacks the same moving-vehicle route in other activities | Traced activity constructors |
| SA-09 | P2 | Home/Fly disagree on Vertical at zero celestial strength | Source call-chain mismatch |
| SA-10 | P2 | Four obsolete pending cloud seeds block the fifth current seed | Reproduced bounded admission failure |
| SA-11 | P2 | Initially Off/Native field setup still constructs projectors | Source; allocation/latency measurement pending |
| SA-12 | P2 | Geometry collection precedes map-count rejection | Source-confirmed avoidable path |
| SA-13 | P2 | Atlas telemetry reads the project default | Reproduced selected 8192 / reported 4096 mismatch |
| SA-14 | P2 | Global effective policy is not actual light/range activity | Reproduced veto; source cap |
| SA-15 | P2 | Cloud occlusion has no independent saved shadow control | Source/settings inventory |
| SA-16 | P2 | Cloud shade lacks consistent aircraft/water receiver coverage | Source; visual impact unmeasured |
| SA-17 | P2 | Useful local lights explicitly omit shadow casting | Source; selective-budget opportunity |
| SA-18 | P2 | Native field coverage admits only selected caster categories | Source; broader coverage gate |
| SA-19 | P2 | Rotating/stopped propeller and rotor coverage is incomplete | Source; time-averaged representation research |
| SA-20 | P3 | Wreck blobs need a declared ambient/contact-aid contract | Design decision; not automatically a night bug |
| SA-21 | P3 | Fixed and flowing time have different opacity contracts | Deliberate calibration; matched-state review |
| SA-22 | P2 | Disabled native routes still submit atlas configuration | Source; backend residency question remains open |
| SA-23 | P2 | Disabled aircraft cues retain captured CPU geometry | Intentional lifetime tradeoff; prior GPU fix preserved |
| SA-24 | P2 | Quality labels describe only part of shadow cost/capability | Source; preset qualification missing |
| SA-25 | P1 | Existing counters cannot establish total shadow cost | Measurement-boundary gap |
| SA-26 | P1 | Full fleet, motion, devices and packages remain unqualified | Acceptance/evidence gap |

Every entry has a detailed acceptance condition in the [register](findings.md). P1 is a release-quality priority for the shadow claim, not a crash/security severity. P2 estimates no millisecond saving until measured; P3 requires an explicit product decision.

## Aircraft material investigation

The review followed the common aircraft builder, imported-model conversion, procedural finishes, custom paints, RGB overlay and visual-detail adapters. It found **no blanket unshaded body or universal native casting disable**. The unshaded additive RGB overlay is distinct from the normally lit base material. Asset metadata supports that narrower conclusion:

| Baseline GLB | Source materials | Source alpha coverage | Follow-up |
| --- | --- | --- | --- |
| F4U Corsair 250 | 14 | 13 OPAQUE, 1 BLEND | Canopy/glass and emissive navigation materials |
| Turbo Lumber Evolution | 10 | 9 OPAQUE, 1 BLEND | Runtime adapter makes source glass opaque; source JSON alone would misdiagnose it |
| Avanti S A200 | 26 | 25 OPAQUE, 1 BLEND | Canopy, two-sided surfaces and six paint emission maps |
| Moonrunner X99 | 9 | 9 OPAQUE | Emissive livery map requires native material/image inspection |
| HX-700 | 18 | 18 OPAQUE | Two-sided surfaces and emissive blue LED material |

None of these 77 source materials declares glTF unlit. This does not prove the final Godot material, shadow pass, import result or apparent contrast. Emission can remain visible in shade; alpha-blended materials require a different casting policy from opaque/scissor/hash. The custom-skin path accepts alpha below one and selects blending, so a half-transparent body is a useful native counterexample. Source hashes and individual material properties are retained in [asset-materials.json](evidence/asset-materials.json).

## Remediation order

1. **Make the evidence trustworthy and reproduce the reported view.** Fix the atlas/policy receipt ambiguity (SA-13/14), capture the actual Native/Projected/Auto comparison and establish a whole-view cost boundary (SA-25). Preserve light energy, exposure, AA and camera.
2. **Resolve natural-shadow versus pilot-cue ownership.** Close SA-01/02/08 with a declared per-activity capability and demonstrated composition. For self-shadow in Native, inspect actual material/caster state and tune map coverage/bias before changing darkness or buying more resolution.
3. **Repair the concrete integration defects.** Reconcile fixed/flowing low-sun directions and Home/Fly cue strength (SA-06/09); reclaim unreferenced cloud entries with race-safe lifecycle tests (SA-10); follow moving hinges and receiver validity (SA-03/04/05).
4. **Remove avoidable work without erasing valid snapshots.** Address map-count preflight and disabled field initialization (SA-11/12); measure native atlas behavior (SA-22), then evaluate retained CPU geometry and bounded proxy reuse (SA-23). Do not undo the November 9 deferred-GPU correction.
5. **Qualify coherence and detail.** Exercise foliage/material alpha, cloud receivers, selected local lights, rotors, wrecks and twilight. Fit cache error and quality tiers to measured images and temporal behavior, rather than arbitrary angular/quality labels.
6. **Consider RT only against a remaining demonstrated failure.** Compare a bounded sun-visibility prototype with tuned native CSM/PCSS. Reuse qualified infrastructure, preserve the raster fallback and include acceleration-structure maintenance, denoising, history and packaging in the cost.

No numeric FPS improvement, GPU memory saving or visual fix is claimed by this branch. The [handoff matrix](validation.md) defines the work needed to close those claims on real hardware.
