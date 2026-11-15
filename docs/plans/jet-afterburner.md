# Jet afterburner — proposed implementation plan

**Updated:** 15 November 2026. **Status:** research and standalone preparation; no production afterburner implementation is delivered here.
**Research baseline:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; **engine pin:** `4.8.beta2.official.cafc17a19`.
**First aircraft:** Vantage Jet (`sebart-avanti-s-a200-p100rx`), with a separate experimental installation and reusable engine/outlet contracts.

The [research index](../research/afterburner/README.md) leads to the complete dated handoff, 28 engineering investigations, 24 additional effects investigations, primary sources, analytical examples, proposed visual profiles and historical standalone receipts. This page owns the current proposed sequence; detailed findings retain their recorded date and evidence scope.

## Ownership and scope

This is a proposed capability alongside the existing [Vantage Jet](../AVANTI-S-PLAN.md) and [turbine realism](turbine-realism.md) tracks. The latter explicitly excludes afterburners. Implementation ownership and a registered step prefix must be agreed before production work. **AB-P0…P7 below are local handoff sequencing labels, not registered repository step IDs or completed milestones.**

Existing owners retain shared contracts: AV/turbine for propulsion and aircraft behavior; FUEL for inventory and mass; SF for numerical/kernel boundaries; AS/AE for schema, generation and Workshop; AUD for sound propagation; SM/VQ/FW for presentation and graphics; input/UI, FL and NK for controls, replay and native admission. Follow the [ownership registry](../README.md#tracks-plans-and-step-ids), [kernel contract](../STACK.md#boundaries-and-data-flow) and [aircraft contract](../AIRCRAFT_CONTRACT.md).

The first complete feature includes visible flame, a causal wet-exhaust sound layer, additional gross nozzle thrust and fuel demand, assignable controls, accepted telemetry, restart/pause/replay behavior and a distinguishable aircraft configuration. Artistic profiles and graphics quality never determine physical thrust. A cosmetic LED/show effect remains an explicitly different mode.

## Integration contract

1. Normalize the pilot request through existing semantic/controller actions and recovery rules. A request does not mean combustion has started.
2. Extend the float64 turbine model and accepted state through the existing 240 Hz flight kernel. Add incremental **gross nozzle force**, leaving inlet momentum accounting with its existing owner.
3. Add fuel demand through the same finite tank, cutoff event and live mass/CG contract. Do not create a render-owned fuel counter or scale dry net force by a universal boost multiplier.
4. Publish actual augmentation, accepted transitions, engine/outlet identity and pose-aligned presentation time. Render and audio consume accepted state, never speculative RK stages.
5. Version state/input layouts and replay/checkpoint identity; update every strict consumer and callback offset. Admit new native capability explicitly or select the reference path with a visible reason.
6. Preserve the installed dry turbine loop, then add a wet layer through the existing audio history, propagation, directionality and Doppler owner. A distant observer receives sound later than the visible light-off.

The [complete handoff](../research/afterburner/2026-11-15/handoff.md#3-one-physical-state-with-multiple-consumers) defines equations, source-level seams, proposed state transitions, controls, causal audio, input cancellation, Workshop and native boundaries. Wet maps remain explicitly estimated until supported by matching installation data; software checks do not identify a real P100 afterburner.

## Visual baseline and corrections to implement

Begin with a validated nozzle-attached tapered mesh, readable apparent core, softer mixing region and fading tip. Compare one shell first; add a separate core/root surface only when rear or inside views demonstrate a coverage failure. Keep hot-metal glow, cosmetic LEDs and independently controlled smoke distinct. Shock cells are optional art parameters without a universal RC spacing or temperature-to-RGB claim.

The retained starter needs the following examined corrections before integration:

- Account for its negative-determinant vertex mapping before changing face culling; derive deformation-consistent normals or justify a simpler facing approximation.
- Define the intended contribution before adding transparent layers. Preserve ordinary opaque depth testing, conservative deformed bounds and independent per-outlet material values.
- Use the aircraft's presented clock, bounded phases and filtered detail. Check internal projected pixels and motion, including pause, seek and long-clock boundaries.
- Prepare shared noise during selected-effect loading. The exact pinned noise source can generate its first update synchronously; handle already-ready, empty/error, canceled and teardown states.
- Respect the custom particle schedule and data packing. Existing `CUSTOM.z` is a seed, while the stock material uses it for an atlas frame. Compatibility does not supply manual emission, sub-emitters or trails as a portable baseline.
- Compose with existing fog, exposure and optional lake planar capture. Several views render one presentation state; they must not duplicate simulation, particle births or sound.
- Initial Effects Off allocates no AB-specific resources. On→Off releases owned resources and stops updates, with shared-cache ownership explicit; Off→On prepares the selected effect again.

The [24 effects investigations](../research/afterburner/2026-11-15/handoff.md#19-effects-research--24-new-investigations) compare geometry, blending, noise, flow maps, atlases, volumes, tools, authoring and evaluation. Material Maker and Blender remain optional offline authoring choices. No third-party flame art or new plugin dependency is selected by this branch.

## Pending sequence and proof

| Local label | Work | Required proof / status |
|---|---|---|
| AB-P0 | Agree owners, capability/schema, state/input layouts, callbacks, replay identity and native admission | **Pending:** explicit contracts and a preserved dry baseline; no ambiguous fuel coordinate or silent unsupported capability |
| AB-P1 | Implement the small presentation fixture/adapter; correct and compare geometry; bind the real JET outlet | **Pending:** native 1080p rear/inside/occlusion, color/fog, pause/seek, selected-loading and two-outlet isolation captures |
| AB-P2 | Add the reference physical response, incremental gross force and fuel law | **Pending:** pure-stage, event/cutoff, conservation and whole-session evidence; stock behavior retained |
| AB-P3 | Add semantic/AUX controls, recovery/cancellation, readable status and versioned recording | **Pending:** device fixtures, focus/disconnect/remap cases, lossless restore and truthful same-tape comparisons |
| AB-P4 | Integrate the wet sound layer and accepted events into the existing causal audio path | **Pending:** native listening/loop checks, no early or duplicate arrivals, single Doppler owner and bounded voices/history |
| AB-P5 | Complete the separate Vantage configuration and end-to-end player workflow | **Pending:** Workshop/catalog, start/trim, fuel/failure, aircraft switching, package contents and full-flight evidence |
| AB-P6 | Add optional particles, light, atlas/flow detail or haze only for documented visual needs | **Pending:** paired captures and bounded native cost on named renderer/hardware; secondary-view policy |
| AB-P7 | Port the qualified reference to native and prove reuse on another jet | **Pending:** backend parity/admission and a genuinely different engine/outlet installation |

AB-P1 is preparation for the complete feature; AB-P2 through AB-P5 supply the requested power, fuel, controls and sound. Optional volumes or haze do not block the first complete baseline. Do not make the whole turbine ECU/thermal roadmap a prerequisite or bypass its shared state/fuel contracts.

## Prepared material and evidence limits

| Prepared item | Location and meaning |
|---|---|
| Complete design and sources | [Dated handoff](../research/afterburner/2026-11-15/handoff.md); full 28 I and 24 FX records |
| Reusable preparation | [Experiment guide](../../research/afterburner/README.md); isolated prototype, analytical Python examples and saved numerical results |
| Art profiles and capture plan | [Fixture guide](../../research/afterburner/development/README.md); three draft profiles and 34 cases, all `not_run` |
| Historical evidence | [Verification](../research/afterburner/2026-11-15/verification.md); original 97 core and 14 visual-state checks are dated 14 November, not rerun or transferred to production |

Primary rendering qualification is native **1920×1080**, followed by higher resolutions; 720p is a fallback. Keep appearance, GPU execution, performance, native audio, controller behavior, numerical correctness and physical validation as separate evidence. No new Godot, GPU, flight or hardware test was performed for this documentation import. The original prototype is retained unchanged, including its documented limitations.

For this branch, check documentation links/content, JSON, evidence identity and the actual committed paths. Future runtime work follows [CONTRIBUTING](../../CONTRIBUTING.md#make-a-change), the [tool index](../tools/README.md) and the existing test/capture admission routes. The next concrete action is AB-P0 ownership/contract agreement and the bounded AB-P1 visual comparison.
