# Scenery plan: current field and remaining gates

2026-10-16 · Revision 12 · Step prefix: **SC** · Gate: **SC**

**Status:** scenery is implemented and on by default. The owner requested that default on 2026-10-11. Gate SC readability and performance acceptance remains open. SC-18, SC-22 and SC-24 are partial; optional SC-19b and SC-21 remain parked.

**Owns:** app/scenery, its data and runtime assets, tools and scenery evidence listed in the [track registry](README.md#tracks-plans-and-step-ids). The visual field and physics collision world remain with their owners.

## Current implementation

The normal Home and flight routes include the complete club field: parking, open pit shelters, pavilion, people, field boundaries, hay bales, animals, distant landmarks, bushes, flowers, ambience and the analytic bird flock. The launch profile may enable the flock and ambience; reference captures can select birds-off explicitly.

Scenery can be disabled with OPENRC_SCENERY=off or --scenery=off. The shared attachment hook is a no-op when disabled, and capture/parity tools select their reference mode explicitly. Current default and opt-out evidence is in [SC-02a](research/scenery-implementation/SC-02a/README.md); the owner-reviewed view harness is in [SC-03](research/scenery-implementation/SC-03/README.md).

Placement data and source packages are documented in [scenery provenance](../assets/scenery/PROVENANCE.json). Baked models use deterministic vertex-colour meshes, merged by spatial cells. Optional quality tiers retain landmarks and deterministically remove ornament. Current Home postcards exist as scenery compositions; putting them into the menu is still UI work.

[SC-08-R1](research/scenery-implementation/SC-08-R1/README.md) refines picnic tables and benches with separate bevelled boards, sampled wood colour variation, fitted supports and hardware while retaining the existing cell batches and seating heights.

[SC-08-R2](research/scenery-implementation/SC-08-R2/README.md) gives the club sign legible identity graphics, a bevelled frame and fitted front/rear mounting details within its existing envelope and cell batch.

[SC-08-R3](research/scenery-implementation/SC-08-R3/README.md) adds fitted timber cladding, door hardware, vents, roof seams and drainage to the parking-side shed, reusing the existing timber source and cell batch.

[SC-08-R4](research/scenery-implementation/SC-08-R4/README.md) refines the pit folding chairs with tubular frames, hinges, rubber feet and curved cloth with edge binding, reusing the existing fabric source and cell batch.

Static object contact uses the separate float64 LU-05 collision world. [CR-17a local damage](research/crash-damage-investigations/CR-17a/README.md) removes failed fence pieces and lightweight props from their visual batches and subsequent contacts, with bounded material-specific effects and checkpoint/reset state. Large obstacles retain their main structure. Proxy dimensions, contact response and failure cutoffs are gameplay estimates. See the [LU-05 collision report](research/landscape-upgrade/LU-05/collision-report.md) for the original detector and measured cost.

## Remaining work

| ID | Remaining scope | Status |
| --- | --- | --- |
| SC-18 | Add remaining field-life motion from the shared wind service. | Partial: rotors and club flag use simulation time and wind; wind pump, canopy flutter and grazing heads are not done. |
| SC-22 | Offer the existing five postcard compositions from Home. | Partial: captures and compositions exist; menu integration belongs to UI-06. |
| SC-24 | Connect low/balanced/high scenery quality to product presets. | Partial: deterministic scenery tiers work; VQ-06 integration remains open. |
| SC-19b | Recorded ambient samples with per-file source and license proof. | Optional; not started. |
| SC-21 | Animated spectators. | Optional; not started. |

SC-19a synthesized ambience and SC-20 analytic birds are implemented. The current Home launch profile enables the decorative flock; the old birds-off default applies only to historical reference captures. SC-23 field palettes are implemented; the ground tint remains a landscape request.

Gate SC asks the owner to fly the Gate 2 maneuvers with default scenery and judge readability, frame-time p95, draw count and memory on the intended machine. Software captures and current Windows evidence do not close that review. The [prop source study](research/scenery-investigations/01-prop-asset-sources.md) and [landscape image review](research/scenery-investigations/05-landscape-image-review.md), [SC-01](research/scenery-implementation/SC-01/README.md), [SC-03](research/scenery-implementation/SC-03/README.md), and [SC-25 runway scenario](research/scenery-implementation/SC-25/README.md) preserve the source selection, implementation and flight/capture rationale.
