# AE-27-00 — Workshop attachment source review

**Reviewed:** 2026-11-19 (America/Bogota). **Repository:** `bultodepapas/OpenRCsimulator`.
**Source:** `main`, commit `e0a733937e255bacfe95ff09db0fb3838697239f`.
**Outcome:** implementation plan and aircraft rollout; no runtime, asset or physical-data changes.
The [attachment plan](../../../plans/workshop-aircraft-attachments.md) owns proposed work and status.

## 1. Scope and evidence limits

Inspected the current Workshop editor and its presentation, compilation, persistence, recovery,
trial, preview/thumbnail and package seams; the complete fixed-wing catalog; relevant procedural and
imported model declarations; wheel/propeller observers; lake/session behavior; and existing ownership,
aircraft contracts and audit status. The [active external audit ledger](../../../../external%20Audits/CONSOLIDATED-AUDITS.md)
was consulted before interpreting historical issues. This review does not relabel past findings as
new defects or claim that older reproductions still fail.

This is a source review, not a Godot run, Blender inspection, native capture, physical measurement or
flight test. Mesh-node declarations do not prove replacement clearance. No non-stock part is currently
qualified by this evidence. Full binary aircraft deliveries were not visually inspected for this plan.
The engine getter pins Godot `4.8.beta2.official.cafc17a19`; the presentation source contract separately
uses its normalized `4.8.0` pin. Neither pin is changed here.

Evidence authority is current code/configuration at the commit above. Older Workshop prose retains
earlier fleet counts and profile v1/companion v2 descriptions; those passages are historical context,
not the schema baseline for new attachments. No unrelated documentation refresh is included.

## 2. Workshop integration map

| Observation | Original source / inspected boundary | Consequence for the plan |
| --- | --- | --- |
| The main document owns Appearance, Lighting, Smoke, Mechanical audio, Flight setup and Compare, with common history. Creator is composed inside that host. | [Workshop](../../../../app/ui/workshop.gd): `PAGE_IDS`, panel construction, `set_presentation`, `_history_snapshot`, `_request_trial`, Creator navigation. | Parts belongs inside Appearance and the existing document. Keep Creator and the separately supported airship paths intact. |
| Presentation fields are strictly versioned; current profile and companion versions are both 4. | [Presentation](../../../../app/workshop/presentation.gd): constants, `defaults`, `validate`, identity functions. | An attachment field needs an explicit extension and legacy readers; it cannot be slipped into a v4 payload or physical recipe. |
| Physical compilation clones/validates the base and uses declared capabilities. Wheel-profile inheritance is part of compilation. | [Parameters](../../../../app/workshop/parameters.gd), [compiler](../../../../app/workshop/compiler.gd): closed keys, `compile`, `_inherit_wheel_model`. | Cosmetic choices stay outside physical transforms and wheel-profile inputs. Hardware work later needs a shared declared contract. |
| Saved records publish immutable revisions with a presentation payload; recovery and bundles validate the same content. | [Store](../../../../app/workshop/store.gd), [draft store](../../../../app/workshop/draft_store.gd), [bundle](../../../../app/workshop/bundle.gd). | Reuse one transaction/history/recovery flow. Preserve exact old records and stale-write checks. |
| Trial preparation verifies sources and presentation, then builds an identity that also includes descriptor and model-manifest hashes. | [Trial](../../../../app/workshop/trial.gd): `freeze`; [descriptor](../../../../app/workshop/descriptor.gd): `verify_presentation`. | Cosmetic selections can preserve physical identity within one accepted source snapshot. Regenerating model inputs may require explicit rebind/copy or refusal; numerical sameness does not preserve all identities. |
| Profile transfer is a reviewed compatible-only operation, not a generic dictionary copy. | [Profile transfer](../../../../app/workshop/profile_transfer.gd): `propose`, domain/version handling; [presentation rebind](../../../../app/workshop/presentation_rebind.gd). | Add attachment compatibility to the existing review path, with one Undo and no target data loss. |
| The preview builds an aircraft, measures bounds and applies a profile; its change detection explicitly names current appearance fields. | [Preview](../../../../app/ui/workshop_preview.gd): `set_aircraft`, `set_presentation`, `_refresh_model_presentation`. | New parts must invalidate assembly/bounds/fit and dependent observers. Adding profile data alone does not refresh a preview. |
| Thumbnails use a separate scene and frozen trial/profile identity. | [Thumbnail](../../../../app/ui/workshop_thumbnail.gd): `Trial.freeze`, `_identity_for_frozen`, `_build_isolated_scene`; [cache](../../../../app/workshop/thumbnail_cache.gd). | Separate visual resolution from flight admission so valid preview-only builds retain thumbnails; include selected assembly identity in caching. |
| Flight builds the manifest-selected model, applies Workshop customization, and later attaches presentation consumers. | [Airplane adapter](../../../../app/render/airplane.gd): `build`, `apply_propeller_diameter`; [main](../../../../app/main.gd): `_build_world`, accepted model/prop synchronization. | Compose parts before consumers cache stock nodes; handle repeated absolute prop-diameter sync and root scaling without losing or double-scaling the selection. |
| Presentation proof has a closed source set and an initially empty raw-asset allowlist. | [Source proof](../../../../app/render/presentation_sources.gd): `SOURCE_PATHS_V3`, `RAW_ASSET_PATHS`, validation; [customization](../../../../app/render/aircraft_customization.gd). | Register trusted factories/assets and regenerate proof/export records. User-supplied paths never become resource-loader inputs. |
| Current fixed-wing start qualification uses the actual candidate and session. | [Start qualification](../../../../app/workshop/start_qualification.gd), [flight session](../../../../app/sim/flight_session.gd). | Gate every launch path, including local bundle/CLI launch. An enabled UI control is not flight admission. |

## 3. Fleet and asset observations

[AircraftCatalog](../../../../app/app_state/aircraft_catalog.gd) is the current inventory: **eleven
airplane configurations across eight visual families**, plus the separately classified X-Cell
rotorcraft. Three finite-glow Stiks have `player_selectable = false`; the eight remaining airplanes
are player-selectable. `skywalker-x8` resolves to `moonrunner-x99` as a historical alias.
The [vehicle roster](../../../../app/app_state/vehicle_roster.gd) also lists separate quad, airship
and ground activities; these are not additional eligible fixed-wing attachments.

| Family / source | Observed assembly | Planning inference / unverified work |
| --- | --- | --- |
| Jensen Stik and its three technical glow variants — [equipment](../../../../app/aircraft/ugly_stik_equipment.gd), [geometry source guide](../../../../assets/aircraft/ugly-stik-60/README.md) | Named `wheel_left_pivot`, `wheel_right_pivot`, `wheel_nose_pivot`; wheel meshes include tire/hub details. Gear flex, nose steering and sections consume the assembly. Prop geometry and broken stubs explicitly use two blade signs. Engine front drive/washer/nut are combined. | Best first wheel candidate. Preserve pivots and author complete alternatives. No separate swappable spinner socket or independently detachable nut is established by this source. Shared visual family does not qualify all prop/engine fits. |
| Electric Stik — [builder](../../../../app/aircraft/stik_electric_model.gd) | Reuses Stik main/nose gear constructors but has its own electric motor/shaft/prop presentation and visual family. | Reuse wheel assets after independent configuration checks; do not inherit glow spinner/prop approval. |
| Extra 300S — [builder](../../../../app/aircraft/extra_300s_model.gd) | Main wheel pivots, separate wheel pants, tail steering/wheel; named spinner/backplate beneath a tilted thrust frame. The stock two-blade loop uses `PI * k` and two blade names. | Suitable second aircraft. Oversized wheels need pant/axle/contact review. Three blades require authored generalized construction, not only a count change. Preserve the source geometry/physical generation boundary. |
| Turbo Lumber — [authored model bindings](../../../../assets/aircraft/model-bindings.json), [blur adapter notes](../../../../app/render/propeller_blur.gd) | Imported fixed taildragger with axle/steering bindings; stock three-blade propeller. Its spinner/backplate/bell and blades are not all separate replaceable resources. | Later candidate after authored mesh separation and proof. A three-blade choice is not a new feature for this stock model. |
| P-51D — [model](../../../../app/aircraft/p51d_model.gd), [compiled geometry](../../../../app/aircraft/p51d_geometry.gd) | Stock four-blade propeller/pointed spinner and retracting main/tail gear with doors. | Keep stock initially. Full retract/door/ground/prop clearance is required for any later replacement. |
| Corsair — [delivery guide](../../../../assets/aircraft/f4u-corsair-250/README.md), [bindings](../../../../assets/aircraft/model-bindings.json) | Imported three-blade prop, sampled retract articulation, wing fold/tailhook and multiple livery assets. | Do not offer generic wheel or prop swaps. Each affected motion/binding/livery needs qualification. |
| Vantage Jet — [delivery guide](../../../../assets/aircraft/avanti-s-a200/README.md), [bindings](../../../../assets/aircraft/model-bindings.json) | Turbine model with `rotor.present = false`, an empty compatibility marker, and sampled tricycle retract motion. | No propeller/spinner category. A marker named propeller is not proof of an installed propeller. Wheel options remain deferred. |
| MoonRunner X99 — [overlay](../../../../app/data/aircraft_model_overlays/moonrunner-x99.json) | Imported pusher propeller and no landing gear. | No wheels/gear/floats. Future pusher choices require orientation/body/elevon/launch review and proper asset separation. |

Aircraft configuration quantities, physical IDs and modules remain owned by the
[aircraft contract](../../../AIRCRAFT_CONTRACT.md). Stik geometry/appearance and Extra geometry
are source-generated; changes that affect model manifests must go through their owning pipelines.
The shared generators are [model manifests](../../../../research/aircraft-standardization/build_models.py),
[customization](../../../../research/aircraft-standardization/build_customization.py) and
[Workshop descriptors](../../../../research/aircraft-editor/build_descriptors.py).
The [documented regeneration order](../../../TOOLS.md#aircraft-workshop) governs dependent records.

## 4. Physics and presentation hazards that change the design

| Source observation | Evidence | Resulting boundary |
| --- | --- | --- |
| Wheel radius participates in rolling/slip/inertia behavior. Ground animation also uses accepted physical radius and compression. | [Ground wheels](../../../../app/physics/ground_wheels.gd), [ground profile](../../../../app/physics/aircraft_ground_profile.gd), [gear animation](../../../../app/render/ground_gear.gd). | Do not feed visual tire sizes into physics. Qualify an authored visual approximation; keep failed/huge fits preview-only. Physical replacements update the complete installation later. |
| Prop blur measures the selected meshes at attachment and uses the measured visible blade count. | [Propeller blur](../../../../app/render/propeller_blur.gd): `attach`, `profile`, `blur_fraction`. | Swap before measurement or rebuild the observer; include broken stubs, strike/wreck and reset. |
| Installed powertrain audio has its own blade/installation assumptions. | [Flight audio](../../../../app/audio/flight_audio.gd), [powertrain audio](../../../../app/audio/powertrain_audio.gd). | Retain current sound during cosmetic scope. A visual blade change does not grant a new physical or acoustic model. |
| The lake has bounded surface-height/contact queries; fixed-wing session metadata explicitly declares terminal water contact without buoyancy. | [Lake surface](../../../../app/physics/lake_surface.gd), [lake collision](../../../../app/sim/lake_collision.gd), [flight session](../../../../app/sim/flight_session.gd): lake collision response and trace metadata. | Functional floats require a new admitted water installation/start/contact law. Preview floats cannot inherit buoyancy from another vehicle family or suppress the existing crash route. |
| Physical mass/CG/inertia derive from complete inventory; support and hull/prop contracts are separately validated. | [Aircraft data](../../../../app/physics/aircraft_data.gd), [contact contract](../../../../app/physics/aircraft_contact_contract.gd), [Workshop compiler](../../../../app/workshop/compiler.gd). | Later physical replacements need one-time inventory replacement, stable mount/contact IDs and full derived-model validation, not a UI-only weight multiplier. |
| Exact recorded flight state is source/model/backend-bound and is not arbitrary appearance playback. | [Flight log](../../../../app/sim/flight_log.gd), [Flight Logging guide](../../../FLIGHT-LOGGING.md). | Preserve physical replay checks; scope cosmetic parity within one identity. Do not promise old/new manifest checkpoint compatibility or selected-look reconstruction. |
| Normal-play damage/cost assessment has versioned companions with reviewed physical hashes and explicit inventory/contact/prop mappings. Missing prices do not invalidate physical flight. | [Damage/cost authoring dossier](../../../AIRCRAFT_CONTRACT.md#damage-and-cost-authoring-dossier). | Later installations need reviewed mappings or an explicit unsupported assessment. Cosmetics do not create installed hardware charges; unknown prices never become zero. |

The existing glow/contact numerical admission and all unsupported combinations stay authoritative.
This review proposes no bypass and does not treat a historical failure as a newly reproduced bug.

## 5. Lead decisions and review disposition

Two bounded read-only helpers examined fleet/assets and the physics/integration boundary. Requested
route: `gpt-6.1-terra`, maximum reasoning. Effective provider execution details were not independently
verified. The lead inspected the material source boundaries and owns the plan and publication.

- Accepted: start on the baseline Stik; keep fleet eligibility explicit; preserve profile/physical
  separation and exact saved-build pins; compose selected meshes before their observers cache them.
- Adapted: a strict identical wheel-envelope rule would strand most wheel sizes in preview. Permit
  only a measured, bounded render-only approximation with an authored display assembly; no root or
  contact movement. Failed fits stay preview-only until the physical installation is ready.
- Chose preview-only float kits through the cosmetic release. An airborne-only visual demonstration
  was considered, but it would still show stock wheel/terminal-water behavior and complicate landing
  expectations. Functional float flight waits for the coherent water phase.
- Kept physical three-blade work conditional on suitable load/installation data. It cannot block
  useful cosmetic choices or be justified by multiplying the stock coefficients by blade count.
- Added the reviewer's damage/economy integration gate for physical packages, with the contract's
  explicit distinction between incomplete valuation and valid flight physics.

The follow-up helper review used supplied candidate contracts and the fleet matrix when local file
reads were delayed; it was not a complete independent line-by-line review of the finished document.

Only documentation checks apply to this branch. Implementation, native visual review, performance,
physical measurements and flight qualification remain the future gates in the plan.

## 6. Planning artifact verification

Validated the six documentation changes using the existing `tools/ci/check_docs.py` link/anchor
parser against candidate files and tracked source targets: **72 new references resolved**, **14
cited test filenames exist**, and **21 implementation subphase IDs are unique**. Tracked-document
whitespace checks passed. This is documentation/source-reference verification; no simulator test,
rendered fit check, benchmark or flight qualification was run or implied.
