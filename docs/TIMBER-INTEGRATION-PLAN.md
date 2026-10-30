# Turbo Lumber Evolution: integration and remaining work

Checked 2026-10-20 · Owner: aircraft/model track · Prefix: **TT-00…22**, including TT-13b/c and gates TT-A/B/C.

Runtime code, configuration and accepted data define current behavior. This plan owns TT status and acceptance; the [asset guide](../assets/aircraft/turbo-lumber-evolution/README.md) owns source identity, pipelines, model interfaces and current asset limitations.

## Current delivery

`turbo-lumber-evolution` is an **EXPERIMENTAL** catalog airplane with airborne and qualified three-point runway starts. Fixed wheels, neutral flaps, no slats/floats and assists off are the supported configuration. The finite pack is the default; [BAT](plans/battery-realism.md) owns battery modes, behavior and remaining energy work. Manual reference anchors, estimated inventory/aerodynamics/motor parameters and the borrowed two-blade propeller map remain distinct from physical validation.

The accepted r2 model uses authored crash sections and the shared manifest-driven GLB builder. `timber_model.gd` retains the inspector API. Current source, geometry and import settings belong to the asset guide; old r1 counts, import defaults, geometry findings and bespoke-builder designs are dated evidence.

## Ownership and authoritative homes

TT owns `assets/aircraft/turbo-lumber-evolution/`, its runtime asset, Turbo Lumber Evolution geometry/inspection tools, `research/timber/`, Turbo Lumber Evolution tests and `docs/research/timber-integration/`. External source deliveries stay unchanged. Generated geometry, physics, model manifests and Workshop descriptors are rebuilt through their source pipelines.

| Topic | Home / shared owner |
| --- | --- |
| Sources, build/check commands, adapter and asset advisories | [Asset guide](../assets/aircraft/turbo-lumber-evolution/README.md) |
| Flight-data assumptions and sensitivity | [TT-07 derivation](../research/timber/tt07/derivation.md), [sensitivity](../research/timber/tt07/sensitivity.md) |
| Physical fields, model/package interfaces and authoring | [Aircraft contract](AIRCRAFT_CONTRACT.md), [Blender handoff](BLENDER-AIRCRAFT-HANDOFF.md); AS/model owners |
| Motor/ESC and physical powertrain evidence | [Electric guide](ELECTRIC-PROPULSION-PLAN.md); EL |
| Energy, pack telemetry and endurance | [Battery guide](plans/battery-realism.md); BAT |
| Launch, state, replay and ground behavior | Physics/GP; [flight logging workflow](FLIGHT-LOGGING.md) |
| Product, audio, night/shadows, crash and exports | UI/AUD/FW/VQ/CR/export owners in the [registry](README.md#tracks-plans-and-step-ids) |

Inspect shared work before editing these seams. Keep aircraft node names stable and retain baseline replay evidence for any intentional physics change.

## Delivered foundations and evidence

TT-00/00-R1 inspected the incoming CAD and r1 delivery; TT-01/02/03/05 froze, measured, imported and articulated it; TT-06 registered the preview. TT-07/08/10/11/12 delivered generated data, experimental flight/product controls, runway support and electric sound. TT-19 integrated r2; AS-09/10 later moved construction into the common imported-model adapter.

The [Turbo Lumber Evolution research index](research/README.md#turbo-lumber-evolution-timber) links the original audits and delivery records. [TT-10](research/timber-integration/TT-10/README.md) records the playable r1 baseline; [TT-19](research/timber-integration/TT-19/README.md) records r2 source/package conformance, crash parts, captures and clearance limits. [AS-09/10](research/aircraft-standardization/AS-09-10-import/README.md) records the shared-builder migration. Their counts, hashes and commands describe those snapshots.

TT-13c's r1 generated crash map is historical; r2 consumes authored `openrc_section` tags. The former forward-extent discrepancy was an AABB artifact, resolved by TT-02. The remaining length mismatch and source-author corrections are listed in the asset guide.

TT-20 adds the separate render finish, construction details, factory lamp layout, bounded suspension presentation, contact dust and aircraft-specific cost-panel styling. Its [research and native verification](research/timber-integration/TT-20/README.md) preserve the distinction between visual evidence and physical qualification.

[TT-21](research/timber-integration/TT-21/README.md) optimizes repeated finish construction, wheel-hardware submissions and airborne dust observation. Paired measurements, exact native visual comparisons and flight/crash checks preserve the TT-20 appearance and simulation contracts.

[TT-22](research/timber-integration/TT-22/README.md) corrects propeller/spinner billing, refreshes dated commercial part-price references and presents affected parts first in the Turbo Lumber Evolution accident report. Incomplete coverage and inspection costs remain explicit; physics and collision decisions are unchanged.

## Remaining work

| ID | Work | Required proof / current status |
| --- | --- | --- |
| TT-02/03/05 follow-up | Independent owner review of dimensions, silhouette and control/material captures | Software metrology/articulation exists; owner visual review remains open. Preserve source identity and review the r2 advisories. |
| TT-04 | Material corrections and target-machine rendering cost | Partial: r2 reduction and bounded cowl material correction are integrated. Measure draw/frame cost at 20/50/100 m; resolve source marking/closure defects. Fewer triangles alone do not close this step. |
| TT-09 | Broader airborne handling/refinement envelope | Baseline trim, control directions, power response, glide and replay are verified. Stall/recovery, aerobatics, landing behavior and declared 240/480 Hz airborne agreement still need evidence. |
| TT-11 follow-up | Landing, bounce and prop-strike envelope | Settled support, taxi/steering and takeoff/refinement are verified. Keep the remaining contact envelope separate from runway-start qualification. |
| TT-13 | Distance/attitude readability, lighting/shadow policy and cost | Partial: model/flight captures and integration checks exist. Owner reading, target-machine cost and nav-lens/night-kit acceptance remain open. R2 crash sections replace TT-13c's old map. |
| TT-13b | Optional parked scenery snapshot | Not delivered; coordinate with scenery. Flyable catalog membership does not imply a parked-fleet entry. |
| TT-14 | Enable physical flight flaps on Turbo Lumber Evolution | Shared flap infrastructure exists, but Turbo Lumber Evolution declares `not_simulated`. Identify hinge/throw geometry and flap-on forces/stall/downwash/servo behavior; verify input → servo → loads → render, trim, reset/trace/replay and manual 20/35 mm with 16/30% elevator mix. Visual posing alone cannot close this step. |
| TT-15 | Flap/STOL approach, takeoff, landing and go-around envelope | Planned after TT-11/14: matched loadout, traces, refinement and sensitivity. No slat/float claim. |
| TT-16 | Independent physical qualification | Open: identified hardware/loadout, measured mass/CG/inertia, motor/ESC/prop/pack observations, held-out flight evidence and owner radio trial. Coordinate EL5, BAT-27/28 and validation. |
| TT-17 | Packaged experimental release qualification | Partial: TT-19 records local package conformance. Retain Turbo Lumber Evolution scene/data/LICENSE checks in all three platform packs, an exported Linux Turbo Lumber Evolution flight and release limitations. The general default-aircraft smoke is insufficient. The [beta notice](../app/assets/aircraft-notices/turbo-lumber-evolution.txt) records the 2026-10-30 authorization for this beta; the source manifest preserves the original delivery terms. |
| TT-18 | Slats, floats, reverse and assists | Deferred; require explicit scope, shared contracts and independent gates. |
| TT-19 follow-up | Corrected author delivery | Current r2 is integrated. Use the asset guide's source-advisory list; a correction needs new source identity and regenerated downstream proofs. |

## Gates

- **TT-A, asset:** source hashes, units/datum, hierarchy, signs, pivots, section ownership and deterministic import agree; material/silhouette review remains independent of software checks. Stop integration on a source/binding mismatch.
- **TT-B, experimental flight:** own attributed data, stable baseline flight, input/arming/pause/reset, correct state/trace identity and fleet regression checks. The delivered software baseline supports the experimental label.
- **TT-C, physical acceptance:** matched measurements, qualified ground/flap envelope, owner radio trial and target-machine performance. Missing physical/pilot evidence keeps the aircraft experimental.

The hardware revision depicted by the mesh, the length discrepancy and matched unassisted flight observations remain open facts. A stabilized BNF recording does not identify the unassisted aircraft response. Use the sourced [Turbo Timber Evolution reference](research/propulsion/EL1a/timber-reference.md), record SAFE/AS3X state and apply the project's uncertainty rules before making a physical-validation claim.
