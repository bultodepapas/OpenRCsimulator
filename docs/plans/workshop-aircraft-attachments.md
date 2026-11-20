# Workshop aircraft attachments

**Date:** 2026-11-19. **Status:** checked internal implementation; no player-facing attachment or fit qualification is claimed.
**Owner:** Aircraft Workshop (AE), with AS/model authors for bindings and GP/physics for physical installations.
**Steps:** AE-27-00a through AE-27-07d. **Baseline:** `main` at `e0a733937e255bacfe95ff09db0fb3838697239f`.
**Planning branch:** `plan/workshop-aircraft-attachments-2026-11-19`.
**Implementation integration base:** `main` at `b69ac2d54871b0d798af7c61ac62d8f17e6abd3d`.

This is the authoritative attachment subplan of the [Aircraft Editor plan](aircraft-editor.md).
The [dated source review](../research/aircraft-editor/AE-27-00/README.md) records the inspected Workshop,
fleet, asset pipelines and limits. The [Workshop guide](../AIRCRAFT-WORKSHOP.md) remains the home for
implemented player behavior.

The [twenty internet investigations](../research/aircraft-editor/AE-27-R1/README.md) reinforce this
plan with simulator workflows, RC assemblies, open-source tools and community questions. Their
recommendations are incorporated below; they do not qualify an asset or physical installation.
The [first implementation record](../research/aircraft-editor/AE-27-I1/README.md) records the internal
selection contract, native wheel study, executed checks and the remaining player-facing work.

## 1. Product goal and delivery rule

Let players give compatible airplanes a different character: smaller or oversized wheels, another
landing-gear look, a three-blade propeller, or a pointed spinner, exposed hub or prop nut. Preserve the
playful aspect through a few attractive presets, including an exaggerated wheel option where it fits.

**Phases 1–4 change appearance only. Phases 5–7 introduce physical installations explicitly.**
An appearance selection never silently changes aircraft mass, balance, drag, thrust, wheel friction,
ground support, collision policy or water capability. Physical installations later create a newly
validated experimental build; existing cosmetic builds do not acquire physics through an update.

Start with one Ugly Stick wheel alternative and the complete existing edit/save/test/return flow.
Expand that working slice to more wheel sizes, Extra 300S and spinners, then propellers and complete
gear looks. Functional floats are the largest final step because the current airplane lake route is
terminal contact, with no buoyancy or water start.

### Player flow

Use **Workshop → Appearance → Parts** inside the current `workshop` screen. The four groups are
**Wheels**, **Landing gear**, **Propeller** and **Spinner**. Reuse the inspector, preview, Original/Draft
comparison, history, Save build, recovery, Library and Test fly. Extract a small parts panel instead
of adding all selection logic to the large Workshop host or creating another editor.

- Offer only authored choices for the selected aircraft configuration. Keep **Original** explicit.
- Use named presets: **Small**, **Standard**, **Large**, **XL / Fun**, where qualified. Final dimensions
  come from each aircraft's fit review; these names do not imply a universal scale factor.
- Mark cosmetic options **Appearance only — flight behavior unchanged**. Mark non-flyable fits
  **Preview only**; they can be saved and compared, but Test fly explains which selection to restore.
- Keep unsupported categories unobtrusive. Explain a relevant restriction, such as wheel pants,
  retract bays, a pusher propeller or a turbine, when the player encounters it.
- A wheel set or gear kit is one history operation. Resetting Parts restores its four slots; the
  Appearance page reset also restores paint/markings according to the existing page-reset contract.
- Compare lists selected parts and the cosmetic status. It must not invent weight, drag or performance
  deltas before a physical installation exists. Camera actions do not make the build dirty.
- A kit that excludes another selection, such as floats replacing wheels, offers a single reviewed
  change showing all affected slots. Cancel preserves the complete draft; Undo restores the set.
- Show the option's silhouette, changed parts, eligibility and any relevant compatibility reason
  beside the choice. Keep Save build and saved/unsaved status visible. A cosmetic label never promises
  more power, lighter flight, improved grass handling or water operation.
- Preserve category, scroll position, keyboard/controller focus and useful preview orientation while
  browsing. Use comparable camera orientation and shared framing for Original/Draft and option images;
  recompute bounds and refit both compared views when necessary so larger parts are not clipped.
- Clearly mark the selected option in the UI and keep the complete aircraft visible. Defer 3-D part
  highlighting unless existing infrastructure already supplies it. An optional future isolate view
  must be explicit and restore visibility on cancel/reset/failure. Camera actions remain outside
  document history. A failed thumbnail retains the saved build with a placeholder/retry.

### Optional appearance combinations after individual parts work

The following are design directions for Phase 4, not extra requirements for the first wheel PR.
Use only already-authored, approved selections; a named look resolves to the same stable option IDs,
compatibility checks and one history operation. It creates no second preset store or physical recipe.
The whole combination inherits its most restrictive availability. Reset Parts still affects only
the four attachment categories, not unrelated paint or setup edits.

| Proposed look | Visual character / candidate | Availability rule |
| --- | --- | --- |
| Classic | Original four part selections on any supported airplane. | Existing original configuration; reject unresolved explicit IDs before offering a repair. |
| Bush look | Bounded balloon-style wheels and, where authored, an exposed nut on the Stik. | Cosmetic flight only after the complete combination's fit review; no rough-field performance claim. |
| Sport look | Slim/treaded or approved pant-aware wheels, pointed spinner and optional three-blade appearance on the Extra. | Only already-qualified combinations; retain each installation's shaft/prop constraints. |
| XL / Fun | Deliberately exaggerated Stik tires with a distinct silhouette. | Preview only whenever ground/envelope fit fails; physical support is a later package. |
| Float study | Paired Stik floats, struts and coherent mounts replacing the wheel artwork. | Preview only; even after Phase 7, conversion requires an explicit new qualified physical build. |

The [research](../research/aircraft-editor/AE-27-R1/README.md#decisions-carried-into-the-plan) supplies
the inspiration and its limits. These are OpenRC appearance names, not branded replica commitments.

## 2. What the existing Workshop supplies

The source baseline has eleven fixed-wing configurations, eight player-selectable airplanes and
eight visual families. Some older planning prose still describes earlier fleet/profile versions;
use the pinned source inventory in the dated review for this work.

| Existing boundary | Reuse for attachments |
| --- | --- |
| `ui/workshop.gd` and its panels | One active document, six current pages, shared history, departure guards and retained trial return. Add a Parts subsection to Appearance. |
| `workshop/presentation.gd` | Closed presentation profile v4 and customization bindings v4. Add a versioned attachment selection contract; reserve the actual next version during integration with other presentation tracks. |
| `workshop/parameters.gd`, `compiler.gd` | Closed physical recipe and detached, capability-based compilation. Cosmetic selections stay outside them. |
| `workshop/store.gd`, `draft_store.gd`, `bundle.gd` | Variant record v2, immutable revisions, recovery and bounded data-only import/export. Extend their existing profile validation; do not introduce a second save store. |
| `workshop/trial.gd`, `start_qualification.gd` | Frozen identities and actual candidate/field/weather start checks. Enforce attachment flight eligibility on every launch path. |
| `render/airplane.gd`, `aircraft_customization.gd` | Manifest-selected builders and per-instance customization. Compose the accepted parts before dependent visual observers cache their targets. |
| `ui/workshop_preview.gd`, `workshop_thumbnail.gd` | Separate preview and thumbnail scenes. Part changes invalidate bounds, dependent rigs and cached images. |
| Model/customization generators and source proof | Authored nodes, exact model/binding hashes and exported presentation dependencies. Extend source pipelines; never hand-edit generated data. |

Paths in this table are relative to `app/`. Source locations and relevant functions are linked in
the [review](../research/aircraft-editor/AE-27-00/README.md#2-workshop-integration-map).

### 2.1 Implementation preflight against GitHub

The implementation preflight compared this branch at `9f20493631aa3013fbf28341bc9bcc9704fe48fd`
with GitHub `main`, still `e0a733937e255bacfe95ff09db0fb3838697239f`. There was no upstream
source drift at that check. Before publication, `main` advanced to
`b69ac2d54871b0d798af7c61ac62d8f17e6abd3d`; its three ClearView importer/guide commits were
merged into this branch without conflicts. They change the Creator's import/configuration workflow,
not the attachment registration or stock Stik model. Imported aircraft still receive no inferred
part compatibility. The focused implementation checks ran on the combined source.
Reading the actual consumers tightened the delivery order:

| Observed code boundary | Consequence for the first increments |
| --- | --- |
| `presentation.gd` is itself in the shared presentation proof set. The customization generator hashes it into every family's slot pin. | A profile edit is a fleet-wide presentation migration, even when only the Stik receives alternate wheels. Build the isolated contract first; regenerate every affected family together at integration. |
| Profile, smoke, rebind, transfer, mechanical-audio editing and airship adapters have explicit version branches. The exporter rejects mixed proof versions. | Allocate profile/binding/proof versions as one change. Preserve v1–v4 shapes, airship behavior, overlays and old source identities; test each reader rather than only changing a constant. |
| Thumbnails **and bundle import** call `Trial.freeze`; physical start qualification does not inspect presentation eligibility. | Separate visual preparation from strict flight admission at those two callers, and recheck the trusted selection at Workshop and CLI launch. A successfully compiled physical model is not attachment flight approval. |
| Preview reuses the airplane for Original/Draft, detects paint/marking/binding changes, and measures bounds when it builds the model. | Add explicit part invalidation, apply-error handling and bounds refresh during the full lifecycle increment. An isolated mesh swap is not complete preview integration. |
| Stik wheels already have named pivot/node handles and four material surfaces. The current contact test subtracts the **profile radius**, not a measured mesh radius. | Stage replacements on the existing mesh nodes, preserving observers and per-instance overrides. Independently measure the tire envelope and lowest vertex; the old contact test alone cannot qualify a larger wheel. |

The first **internal** increment therefore delivers a closed selection/resolution contract and a
same-envelope native tread prototype without changing the current profile, generated pins or public
Workshop flow. It does not complete AE-27-00b or qualify AE-27-01a. A separate integration increment
must finish the migration and complete player journey before a Parts selector is offered. This
keeps the first usable feature small while making its cross-cutting work explicit.

## 3. Aircraft rollout and restrictions

This matrix is a **proposed rollout**, not a declaration that alternate parts already fit. Every
non-stock option needs authored bindings and the relevant acceptance evidence. Sharing a visual
family allows asset reuse; it does not qualify every engine installation or saved configuration.

| Aircraft / exact catalog ID | Cosmetic rollout | Main restriction / later work |
| --- | --- | --- |
| Ugly Stick — `jensen-das-ugly-stik-60` | Pilot: wheels in Phase 1; spinner/hub styles in Phase 2; three blades in Phase 3; gear and float preview in Phase 4 | Named tricycle wheel pivots make it the first candidate. Author each set around its nose steering, gear flex and ground pose. No separate replaceable spinner socket is established today. First physical wheels and functional floats use this aircraft. |
| Extra 300S — `gp-extra-300s-60` | Second aircraft: bounded wheels and spinner choices in Phase 2; three blades in Phase 3 | Taildragger with separate main-wheel pants. A larger wheel may require an authored no-pants kit. Spinner/backplate sit in a tilted thrust frame. Preserve finite-glow admission. Floats are not proposed for its initial rollout. |
| Ugly Stick 6S — `stik-electric-6s` | Reuse qualified wheel assets in Phase 4; fit spinner/prop variants separately | Separate visual family with a different motor/shaft installation. The electric conversion does not inherit glow propeller/spinner approval. |
| Ugly Stick MAX-61FX — `stik-glow-61fx-2t` | Qualify compatible Stik visuals after the pilot | Technical configuration remains hidden from new-stock selection; preserve existing saved builds and per-configuration pins/prop size. |
| Ugly Stick MAX-55AX — `stik-glow-55ax-2t` | Same bounded follow-up | Qualify its own engine/prop configuration; no new stock-picker entry. |
| Ugly Stick FS-64V — `stik-glow-fs64v-4t` | Same bounded follow-up | Four-stroke installation and propeller dimensions need their own fit/identity evidence. |
| Turbo Lumber — `turbo-lumber-evolution` | Later fixed-gear candidate in Phase 4 after asset separation | Already has a three-blade propeller. Imported hub/spinner/blades are not clean independent replacement slots. Preserve tailwheel motion and the authored source delivery. No automatic float compatibility. |
| P-51D — `p51d-mustang-120` | Keep stock in the initial release | Stock four-blade propeller and retracting gear/doors. Wheel, spinner or blade changes need a later complete clearance/rig campaign. No generic XL wheels. |
| F4U Corsair — `f4u-corsair-250` | Keep stock in the initial release | Already three-blade; imported sampled retract motion, wing folding and multiple liveries. No inferred support from a visible wheel or propeller. |
| Vantage Jet — `sebart-avanti-s-a200-p100rx` | Retain original equipment | Turbine: no propeller or spinner category. Future wheel variants must fit retract bays, doors and all sampled poses. |
| MoonRunner X99 — `moonrunner-x99` | Retain original equipment; pusher prop research later | No landing gear; no wheel/float offers. Pusher variants need orientation, body/elevon and launch-clearance review. `skywalker-x8` is a historical alias, not another active airplane. |

The X-Cell helicopter, FPV quad, blimp and ground vehicles retain their separate contracts. Creator
imports and arbitrary user meshes do not gain attachment compatibility from a name or matching mesh.
An unregistered airplane continues to use its original configuration.
That default applies when no attachment selection was supplied; an explicit unsupported, unknown or
stale selection is refused without silently rewriting the saved record.

## 4. Design boundaries

### 4.1 Authored parts and configuration compatibility

Introduce one bounded attachment catalogue with stable option IDs and a generated per-family binding
extension to the existing customization contract. Keep installation eligibility declarative and
explicit per supported catalog configuration and capability combination; no aircraft-name branches
in the Workshop compiler or simulation kernel.

The authored contract records:

| Record | Required content |
| --- | --- |
| Slot | Stable ID, one of the four part categories, original assembly, explicit attachment frame, affected mesh targets and renderer-owned grouping. |
| Option | Stable option/revision ID, trusted asset or procedural factory, source/provenance, affected assembly, bounds and explicit original restore target. |
| Fit | Exact supported configurations/binding revision, slot/kit compatibility, wheel-pant dependencies, handedness, prop/hub dimensions, pose/clearance evidence and approved scale domain. |
| Availability | `cosmetic_flight` or `preview_only` in trusted registration, with a reason. Later physical packages use a separate admission result. A saved profile cannot promote its own availability. |
| Lifecycle | Wheel/steering/compression/prop handles, material ownership, crash-section mapping, cleanup and restore behavior. |

Saved selections contain only stable slot/option IDs under a versioned presentation extension. They
do not contain resource paths, scripts, transforms, mass, drag values, radii for the physics solver,
arbitrary blade counts or a player-controlled bypass flag. The binding/catalogue digest pins the exact
option definitions. Missing selection means the explicit original assembly for that profile version.
Apply that default only under a recognized schema/legacy read path. Unknown or stale explicit IDs
never fall back silently. A kit resolves all affected slots and observer references before one atomic
publish; conflicts are explained without changing unrelated selections or the saved draft.

Fit evidence describes the complete assembly, not just a nominal size or generic slot type:

| Assembly | Authoring dimensions and relationships to record |
| --- | --- |
| Wheel set | Tire diameter and width, axle/bore, offset, hub/retainer envelope, linked wheel roles, pant/no-pant partner, steering/flex poses and tread/sidewall style. |
| Spinner / exposed hub | Cone diameter/length, backplate, shaft frame/interface, retained washer/nut artwork and blade-root opening width/depth for each approved propeller. |
| Propeller | Visible blade count, diameter/pitch reference, hub dimensions, shaft orientation, handedness, spinner pairing, blur and damaged-state ownership. Pusher location does not imply reverse rotation. |
| Gear / floats | Complete members and suppressed stock parts, explicit fuselage mounts, front/rear orientation, clearance envelope and any visible steering linkage. Physical stations/volume/forces belong to later installation evidence. |

Evaluate the actual selection's aircraft configuration, binding revision, accepted installation/prop
dimensions, gear kit, wheel/pant set, propeller, spinner and scale domain. Recognized Original
components retain their accepted baseline; author and measure the interactions affected by the new
option. Do not require a Cartesian matrix of unoffered combinations or re-author unrelated stock
parts before shipping the wheel pilot. Manufacturer dimensions are reference evidence; shared axle
dimensions or catalog compatibility with another real airplane do not certify an OpenRC fit. See
[R06–R11](../research/aircraft-editor/AE-27-R1/README.md#rc-catalogs-and-actual-assemblies).

Begin with linked wheel sets, one spinner assembly and one propeller assembly. Keep free scaling,
independent left/right tires and free-positioned accessories outside this first contract. Scale the
accepted visual assembly once with the existing aircraft root; each option states its supported
Workshop size domain. Cosmetic support at 100% does not qualify the full 10–500% virtual-size range.

### 4.2 Cosmetic geometry must not become hidden physics

Changing a tire around a fixed axle changes its visible bottom, while current support remains at the
original contact point. Ground motion also uses the physical wheel radius and compression. Therefore:

- Author a display assembly, not just `mesh.scale *= factor`. Preserve existing pivot names and keep
  paired tires, hub/axle details, steering, flex and compression coherent.
- A bounded cosmetic alternative may reposition its own wheel/leg artwork to meet the unchanged
  support in the reviewed reference pose. It cannot move the aircraft root, physical contacts or
  propeller disc, or change collision/friction to hide a mismatch.
- Measure visible mismatch through the declared rest, steering, compression, pitch/roll and landing
  poses. Record the metric/tolerance with the option before approval; do not claim exact contact in
  every attitude. Review wheel-spin presentation independently of the solver's radius.
- If the fit is unacceptable, retain it as **Preview only**. This will likely apply to the most
  exaggerated tires until Phase 5. The same rule applies to spinners outside the accepted nose
  envelope and to incompatible wheel-pant combinations.
- Cosmetic three-blade props retain the accepted physical diameter/disc and shaft installation.
  Blade spacing, handedness, blur, broken stubs and reset must match the visible assembly. Keep
  installed powertrain sound unchanged in this scope; a blade count is not a new thrust or audio model.
- Float kits are **Preview only** through Phase 4. They must not launch on invisible wheels, enable a
  lake start or disable water crashes. Working water behavior starts only after Phase 7 qualification.

### 4.3 Composition and consumers

Use one shared visual resolver for preview, thumbnail and flight, with a caller-owned purpose. Stage
and validate a complete candidate assembly, then publish it atomically. On failure, retain the old
preview/profile or refuse flight preparation before replacing the retained session.

Resolve parts before paint/lighting/decal target binding and before propeller blur, ground animation,
damage/wreck presentation and shadows cache their targets. Rebuild only the observers affected by a
swap. Recompute visible bounds for preview fit and thumbnail identity. Original view always uses
original parts; two instances must not share mutable materials or visibility state.
Stable logical part handles must be rebound when an assembly is rebuilt; no observer may retain a
freed stock target. Cancel, reset and a refused swap restore the whole kit, including visibility.

`workshop_thumbnail.gd` currently uses `Trial.freeze()`. Split reusable frozen visual resolution from
flight admission, or supply an internal explicit purpose, so a valid preview-only build can still
save and render a thumbnail. Enforce flight eligibility at the actual trial/CLI/start boundary, not
only by disabling a button. Do not trust purpose or availability from an imported JSON record.

### 4.4 Persistence, source identity and migration

Preserve profile v1–v4 and variant v1/v2 read paths. Reuse existing immutable revisions, recovery,
bundles, dirty-state comparisons and stale-write protection. Allocate schema/proof versions together
with the decal, lighting and smoke owners when implementation starts; this plan does not reserve a
conflicting numeric version or assume another branch is merged.

Editing the current presentation validator changes the shared proof and therefore every generated
family's `slots_sha256`. Keep historical records structurally readable, but do not advertise
uninterrupted launch of old pinned builds. Current store rules prohibit in-place rebinding; use
reviewed rebind/Save a copy when supported and explain unavailability otherwise. Some historical
smoke profiles are deliberately not rebindable. Include the airship adapter, customization overlays,
export package marker, profile transfer, audio-edit promotion and all stock/empty predicates in the
migration review. An explicit unknown attachment must never be mistaken for an unbound default.

Keep `Trial.freeze` strict for flight by default. Thumbnail rendering and bundle import need an
explicit caller-owned visual preparation path; purpose/eligibility never comes from imported JSON.
The flight launcher must still enforce attachment eligibility before physical start qualification.

Cosmetic choices change presentation identity. **Within the same accepted source/descriptor/manifest
and physical recipe**, they must leave resolved aircraft bytes, physical model/wheel-profile hashes,
trial identity and deterministic physical results unchanged. The existing trial identity also includes
the model manifest and descriptor: authoring new sockets may change those pins. Preserve existing
records; use explicit reviewed rebind/Save a copy or a truthful unavailable state when old pins no
longer resolve. Do not promise unchanged identity across a generator/source migration.

Keep part assets/factories in the presentation proof/export closure when feasible. A necessary
physical model-manifest change follows its owning generator and migration contract; never omit a
dependency to manufacture parity. Old checkpoints retain their existing identity checks. Physical
`.orfl` replay does not reproduce arbitrary presentation choices or GPU history; visual replay is not
part of this feature.

### 4.5 Source pipeline, reusable assets and optional tools

The first Stik wheel assembly uses the existing native mesh/equipment source pipeline described in
its [geometry guide](../../assets/aircraft/ugly-stik-60/README.md) and the source audit. Preserve its
named pivots and generated binding identity. A separate engine GLB is not a reason to introduce or
optimize imports in the wheel pilot.

For each actual asset, retain source URL/creator or original generator, revision/hash, license,
modifications and reproducible output. Screen suitable reusable assets before authoring equivalents;
the [CC0 candidates in R16](../research/aircraft-editor/AE-27-R1/README.md#r16--poly-haven-and-kenney-are-reusable-wheel-assets-actually-suitable)
are potential references, not approved RC parts. Product pages supply ideas and dimensions, not
permission to redistribute their photographs, CAD or performance datasets.

Only if a selected attachment uses imported glTF, evaluate the
[R12–R14 tools](../research/aircraft-editor/AE-27-R1/README.md#open-source-tools-github-and-asset-libraries):

- Use the existing inspection/export tools first. Where useful, export namespaced custom properties
  and compile them into strict source-pinned bindings. glTF display names are not guaranteed unique;
  extras are not assumed to become runtime Godot metadata automatically.
- Pin the actual exporter and any adopted Khronos Validator version. Record settings, hashes and its
  report; resolve format errors and review warnings/unsupported extensions. Separately check OpenRC
  mount identity, hierarchy, transforms and dependency closure. Format validity is not a fit result.
- Evaluate glTF Transform or gltfpack offline only for a measured asset problem. Preserve the original
  export and verify named targets, pivots, materials and extras before/after selected transforms.
  Avoid blanket join/flatten and unverified compression extensions. Keep an optimization only with
  useful measured cost improvement and unchanged semantic bindings/fit on the pinned engine.

No new library, exporter or engine upgrade is required by this planning branch or the native wheel
MVP. Tool-code licenses and downloadable asset licenses are separate; preserve the applicable notices.

## 5. Incremental delivery

Every row below is a separate reviewable subphase, with a working original/default route. Dependencies
run in phase order; fleet extensions can follow independently after their shared contract is stable.
The source/planning portion of AE-27-00a is complete. [AE-27-I1](../research/aircraft-editor/AE-27-I1/README.md)
implements the isolated selection/resolver and native wheel study with 594 passing focused checks.
AE-27-00b and AE-27-01a are **partial**; all player-facing integration and qualification gates below
remain open. No option is promoted to cosmetic flight by these internal checks.

### Phase 0 — Freeze the contract and the pilot

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-00a | Source/fleet audit, ownership and first Ugly Stick fit inventory. Record actual node/assembly references and original-state evidence. | Source review delivered on this branch. Native fit measurements/captures remain to do; no replacement is marked qualified. |
| AE-27-00b | **Partial:** internal closed v1 selection/resolver and refusal fixtures implemented. Finish the presentation/profile/binding extension and migration behavior. | Old profiles remain readable, unknown/stale IDs refuse explicitly, defaults reproduce the existing assembly, and the physical recipe rejects visual fields. Coordinate profile versions and source proof before publishing generated bindings; current presentation stays v4. |

### Phase 1 — Ugly Stick wheels, the first complete feature

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-01a | **Partial:** detached same-envelope Twin-groove study implemented and measured headlessly. Keep all three pivots, linked main wheels, nose steering, gear flex and section metadata. Finish source proof and visual fit approval. | Original/alternative instances isolate materials; exact hardware buffers and Original recovery are checked. Native rendered rest/steering/compression review still establishes whether it is cosmetic-flight eligible. |
| AE-27-01b | Add Appearance → Parts → Wheels. Connect preview, Original/Draft, one-step Undo/Redo, reset, Save/load/recovery, thumbnail and trial/return through the shared document. | One accepted set survives the complete player journey. A refused set preserves the draft and prior flight. Cosmetic identity changes; physical identity and same-input flight results do not. |
| AE-27-01c | Add Small/Large/XL presets one at a time using the same binding. Clearly retain preview-only options when the visual fit fails. | A recorded fit result per preset and approved scale domain. No universal wheel-size slider or automatic certification of giant tires. |

**First release:** one airplane and one alternate wheel set with complete persistence. Ship flight use
only if its visual fit passes; the preview/save slice remains useful independently. Do not bundle a
spinner, new propeller or water model into this first change.
Include the pilot's authored dimensional fit record and comparable option view. Save status,
focus/camera retention and complete restoration are part of this existing journey, not separate
features or reasons to add another UI framework.

### Phase 2 — Spinners and the second airplane

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-02a | Introduce Original / Pointed / Nut / No spinner on Extra 300S using its explicit spinner/backplate and thrust frame. Author the equivalent Stik hub socket separately. | Shaft and fastening remain visible when appropriate; no duplicate stock cone/nut, broken tilt/rotation or prop intersection. Spinner extent passes the visual envelope gate; other choices stay preview-only. |
| AE-27-02b | Port the wheel selector to Extra through bindings only. Introduce a reviewed no-pants assembly where larger tires need it; retain the tailwheel/steering rig. | The UI/compiler has no Extra-specific transformation branch. Main/tail wheel choices and pant dependencies are explicit. Both aircraft pass save/Undo/trial/return and finite-glow admission remains unchanged. |

No spinner means a coherent exposed retention assembly, not an empty shaft. Nut is a separately
authored silhouette. Review backplate/washer/fastener dependencies and blade-root cutouts together;
changing one complete assembly must not leave duplicate stock hardware.

### Phase 3 — Cosmetic propeller choices

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-03a | Retain the original two-blade Stik propeller and author a three-blade option at the accepted diameter and correct shaft orientation. Generalize visible blade/stub construction; rebuild blur from the selected assembly. | Three evenly spaced blades, matching blur and broken stubs; two-blade restoration, prop strike and restart work. Engine/RPM/load/diameter/physical blade inputs and installed audio stay original. |
| AE-27-03b | Add Extra's three-blade option and validate the spinner/prop combination table. | Every offered combination fits; unavailable combinations explain why. Extra's existing two-name/180-degree construction is replaced through its source pipeline, not by changing a count constant alone. |

### Phase 4 — Gear looks, float preview and cosmetic release

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-04a | Add one Stik fixed-gear style and one complete float kit, including struts and wheel suppression. | Independent kit ownership, no duplicate wheels/legs, correct preview bounds and Undo. Float build saves/loads and thumbnails correctly, with Test fly refused as preview-only. |
| AE-27-04b | Qualify the electric Stik and hidden glow configurations individually. Assess Turbo Lumber after separating its imported wheel/hub/prop assemblies. | One data/binding addition per approved configuration; hidden variants remain hidden. Unsplit/incompatible assets stay original. Retractable aircraft and pusher work remain deferred. |
| AE-27-04c | Close the cosmetic release matrix across offered aircraft, parts and interactions. | All gates C1–C5 below pass for the advertised scope, including export/source proof and actual rendered review. All cosmetics retain their original physical behavior. No physical phase is enabled by this release. |

Optional named looks may follow once their individual parts qualify. Their absence does not block
the cosmetic release. They reuse the same compatibility resolver and retained document, and cannot
promote a preview-only part to flight eligibility.

### Phase 5 — First physical wheel package

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-05a | Define one installed Stik wheel package with sourced/estimated mass, station, intrinsic inertia, dimensions, wheel-profile/contact dependencies and bounded added drag. Extend the shared physical contract/compiler deliberately. | Explicit hardware selection is separate from cosmetic selection. Independent mass/CG/full-tensor accounting; stock components are replaced once, not added twice. Unknown or unsupported inputs cannot compile. |
| AE-27-05b | Integrate radius/inertia, support position, gear travel, tire/brake parameters where applicable, steering and ground/prop clearance as one coherent installation. Add modest aggregate parasite drag, with visible assumptions. | Pose/contact/visual agreement, runway trim/start and numerical admission pass. Reference/native behavior is qualified or explicitly selects the supported reference route. No half-updated visible wheel is offered as physical. |
| AE-27-05c | Qualify the first installation, then consider more sizes and Extra/Turbo Lumber under their own evidence. | Same-input baseline/candidate flights quantify weight/drag/taxi/landing differences. Checkpoint/reset/reload/events and physical-package identity are correct. Review installed damage/cost mappings or declare assessment unsupported. Start refusals remain authoritative. |

The physical MVP is a modest, understandable change in weight, balance, rolling behavior and drag.
Use the existing shared laws within their domain. Do not introduce a detailed tire or aircraft-wide
aerodynamic redesign merely to make a larger wheel feel different. AE-27-05a/b are internal additive
steps; player launch is enabled only when the complete installed package passes AE-27-05c.
Classify each physical input as measured, manufacturer-specified, manufacturer-computed or estimated,
with units, component quantity, source revision and limits. A per-wheel catalog mass is not a whole-kit
delta, and the visible mesh's scale is not a density or drag model. Community reports supply test
questions, never coefficients or approval of a rough-field operating domain.

### Phase 6 — Physical propulsion and other fixed-gear packages

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-06a | Qualify one physical three-blade package only when suitable diameter/pitch, Ct/Cp or equivalent load data, mass/inertia, RPM/domain and engine compatibility evidence exist. | Installed engine load, thrust/torque, angular momentum, energy/fuel behavior and prop-strike geometry agree. A cosmetic blade count is never multiplied into thrust coefficients. Without evidence, keep the visual option and defer this subphase. |
| AE-27-06b | Reuse the installed-package mechanism for other fixed gear and supported aircraft, one at a time. | No duplicated physical values, preserved mount/datum and full lifecycle/start/flight checks. Spinner styling remains cosmetic by default; physical mass is included only as part of an explicitly modeled installation. |

This phase is conditional on source data. It does not block the independently designed float work
once Phase 5's physical-package/identity boundary is available. Retractable conversions remain a
separate follow-up with gear-door and full-motion qualification.

[R11](../research/aircraft-editor/AE-27-R1/README.md#r11--propeller-data-what-can-support-a-later-physical-three-blade-package)
identifies APC's computed tables and UIUC's wind-tunnel data as candidate evidence sources. Preserve
the distinction between computation and measurement, identify the exact propeller and RPM/advance-ratio
domain, and review data rights before redistribution. No exact measured Stik/Extra three-blade match
was established. Do not substitute a different diameter/pitch curve or a blade-count multiplier.

### Phase 7 — Functional Ugly Stick floats

| ID | Work | Proof / exit condition |
| --- | --- | --- |
| AE-27-07a | Define a fixed-wing float installation and water capability with geometry/volume, locations, dry mass/inertia, buoyancy points and an explicitly limited hydrodynamic model. Reuse lake surface/environment queries. | AS/GP/physics own a closed module, parameters/provenance and force/contact/event contract. The shared kernel gains no Ugly Stick or water-specific branch. A decorative kit alone cannot select this law. |
| AE-27-07b | Implement bounded static flotation, damping, low-speed water support and an explicitly qualified water start/taxi route. | Independent displacement/equilibrium checks, roll/pitch restoration, passive drag/damping and timestep refinement; reset/checkpoint/rejected-step recovery. Preserve terminal water policy for every non-float aircraft and for unsupported float contact. |
| AE-27-07c | Add the declared takeoff/landing envelope: water-to-air and air-to-water transition, planing approximation only if justified, wave/wind limits, steering and prop/water-strike behavior. | No duplicated wheel support or simultaneous terminal/float response for the same event; hull immersion, overturning and unsupported speed conditions have explicit outcomes. Field/spawn/shore clearance qualifies through the real session. |
| AE-27-07d | Expose the physical float kit and Water start after the complete pilot flow qualifies. | Save/freeze/start/taxi/takeoff/land/return/restart and replay/recording pass in the admitted domain; installed damage/cost mappings are reviewed or assessment is explicitly unsupported. Rendered and physical/pilot evidence remain separate. Cosmetic float builds stay preview-only until explicitly converted to a new physical build. |

Initial water scope is one fixed float kit, one aircraft and the existing bounded lake environment.
Amphibious retracting wheels, arbitrary waves, full CFD, detailed spray forces and automatic support
for other airplanes are outside this first water implementation.

The [float research](../research/aircraft-editor/AE-27-R1/README.md#r19--float-experiences-which-scenarios-deserve-later-acceptance-tests)
adds concrete scenarios to W1: equilibrium/heel, low-throttle steering, acceleration through the
admitted takeoff envelope, prop/water clearance, water touchdown and restart. Wind, shore and
unsupported-speed cases need declared outcomes within the chosen domain. Community placement or
pitch advice does not set parameters; independent geometry, force-law evidence and validation remain
AE-27-07a work. The JSBSim gas-cell schema reviewed in R15 does not supply a floatplane water law.

## 6. Acceptance gates and proportionate verification

These are full feature gates; the internal [AE-27-I1 checks](../research/aircraft-editor/AE-27-I1/README.md#verification)
cover only the stated contract/mesh preparation and stock regressions, not complete C1–C5. Use the
[existing tool routes](../tools/README.md) and [Workshop commands](../TOOLS.md#aircraft-workshop).
Select focused checks for each changed boundary; broaden for the integrated release and required CI.
Do not rerun every native suite for a local selector or documentation edit.

| Gate | Required evidence |
| --- | --- |
| C1 — Contract and compatibility | Defaults; profile/record legacy readers; duplicate/unknown slots/options; stale catalogue/model/proof pins; malformed imports; unsupported aircraft/part combinations; failed migration leaves the record intact. Preview-only selections remain saveable/visible but are refused by every flight entry point. |
| C2 — Cosmetic physics parity | Within one source/package identity, compare original and every offered cosmetic-flight option with identical physical recipe, accepted start, field/weather and input tape. Exact resolved bytes/model and wheel-profile pins, mass/CG/inertia, propulsion/contact/strike configuration, and deterministic states/events remain equal. Cover relevant airborne, ground and strike paths. A generator migration is separately identified, never disguised as cosmetic parity. |
| C3 — Complete player lifecycle | Select → preview → Undo/Redo/reset → save/reopen/copy → bundle round trip → recovery → Test fly → pause/restart → return to the retained draft. Include stale preparation and missing-part failure, Original view, cancelled/failed thumbnail, source switch, failed save and existing unrelated pending edits. Preserve browsing focus/context; failures do not hide the plane or make a saved build inaccessible. No stock/shared-instance mutation. |
| C4 — Visual fit | Actual rendered front/side/underside views and relevant motion: steering, compression, pitch/roll, prop stationary/low/high RPM, strike/wreck/reset. Check hub/fastener, pants, shadows, skins, markings, lights and smoke. Record support/disc/envelope mismatch against the declared fit tolerance. Review 1920×1080 first; Apple Silicon Retina uses native-panel acceptance under the repository policy. EN/ES, keyboard/controller navigation, enlarged text and compact layout keep actions reachable. |
| C5 — Cost, packaging and cleanup | Record before/after preview/flight frame cost, allocations and loaded resource counts for the worst offered set on target hardware. Establish asset-specific geometry/material/texture budgets from the measured baseline. At least twenty swap/reset/close cycles show no accumulating nodes/materials or hidden processing. Original/off mode retains bounded cost; imported assets and procedural factories have exported source proofs and licenses. Optional optimization preserves bindings and shows a useful measured gain. No universal FPS claim from headless checks. |
| P1 — Physical installations | Independent mass/CG/six inertia terms; one-time replacement bookkeeping; validated contacts/profiles; honest estimated drag and compatible propulsion data. Real trim/start, contact reserve/timestep and baseline/candidate flight evidence; reset/reload/checkpoint/event/replay identity and applicable native/reference checks. Reviewed damage/economy companions and contact-to-component mappings, or explicit unsupported assessment. No renderer transforms used as solver state. |
| W1 — Water operation | Static buoyancy oracle, energy/passivity, bounded equilibrium and refinement; qualified water spawn/taxi/transition; correct terminal-versus-support arbitration, prop strike and shore behavior; stock non-float water regression. Complete rejected-step/reset/checkpoint lifecycle and declared physical/pilot evidence limits. |

Reuse/extend the relevant existing suites: `test_workshop_presentation.gd`,
`test_workshop_customization.gd`, `test_workshop_store.gd`, `test_workshop_trial.gd`,
`test_workshop_bundle.gd`, `test_workshop_preview.gd`,
`test_presentation_rebind.gd`, `test_workshop_sizes.gd`, `test_presentation_sources.gd`,
`test_gear_visual_contacts.gd`, `test_gear_flex.gd`, `test_propeller_blur.gd`,
`test_prop_strike.gd` and `test_extra_propeller_handedness.gd`. Add attachment-specific
fixtures where these do not cover the new behavior; existing suites do not already qualify parts.
Physical/water work additionally uses the appropriate wheel/contact/lake/flight-log suites. Keep
exact playback and same-input candidate comparison distinct as required by
[Flight Logging](../FLIGHT-LOGGING.md).

Check a non-default already-supported Workshop size and repeated accepted reload/prop-diameter sync.
The root scale and absolute prop-diameter synchronization must not scale an attachment twice, discard
its choice or restore cached stock blades. Preserve ordinary stock starts and old-build refusal rules.

Physical packages also follow the [damage/cost authoring contract](../AIRCRAFT_CONTRACT.md#damage-and-cost-authoring-dossier):
review inventory, gear/hull/prop mappings and companion source hashes; retain missing prices as
missing, never zero. Incomplete valuation does not invalidate otherwise valid flight physics.
Cosmetic parts retain the existing physical damage/economic identity and Workshop trial sandbox;
new wreck artwork alone cannot create a replacement charge. Verify affected crash-report routes.

## 7. Implementation map and ownership

The new paths below are proposals. Keep the feature in the existing Workshop/presentation subsystem;
add a new file only for a distinct responsibility. Existing source paths are linked in the review.

| Area | Proposed change / owner |
| --- | --- |
| Authored options | `assets/aircraft/attachments/` for owned option sources/provenance and fit declarations, coordinated with each aircraft generator; AS/model owners. Reuse existing licensed geometry before authoring replacements. |
| Generated catalogue and bindings | A bounded `app/data/aircraft_attachment_catalog.json`, plus attachment fields in the generated customization companion/overlay; extend `research/aircraft-standardization/build_customization.py` and source-proof export. AS owns schema/generated identity; AE consumes it. |
| Selection and compatibility | `app/workshop/attachments.gd` for data validation/resolution; integrate profile identity in `presentation.gd`. Keep stable IDs, original defaults, trusted availability and kit conflicts in one resolver. AE/AS. |
| Visual composition | `app/render/aircraft_attachments.gd`, invoked through existing airplane/customization composition. Own only its instances; coordinate paint/lighting, prop blur/strike, gear animation, damage sections and shadow caches. Model/render owners. |
| UI | `app/ui/workshop_parts.gd` composed into Appearance. Small hooks in Workshop history/reset/Compare/issues, preview and thumbnail. AE/UI. |
| Persistence and frozen visuals | Existing store/draft/bundle/rebind/profile-transfer/trial paths; no second database, save file or physical recipe for cosmetics. Separate preview eligibility from launch eligibility. AE. |
| Physical installs, Phase 5 onward | Extend the shared aircraft/module/mount contract, existing compiler/dependency discovery and owning source generators. GP/physics retain mass/contact/propulsion laws; AE supplies explicit selection and before/after explanation. |
| Water, Phase 7 | Shared fixed-wing module and session adapters using current lake/environment queries. AS/GP/physics own start/contact/event/replay; AE owns selection and UI admission. |
| Evidence | Future implementation receipts and lightweight captures under the relevant AE-27 step. This plan owns status; do not duplicate it in a parallel roadmap. |

Coordinate with existing AE-12/13 mass/mount work, AE-14…18 hardware modules, AE-19 portability,
AE-24 appearance/decal work, AS model standardization, GP ground support, FUEL/propulsion, CR damage,
lighting, smoke and skins. This subplan owns swappable attachments; it does not redefine their shared
laws or silently close their open gates. A future aerodynamic wing/tail package remains AE-21 work.

## 8. First implementation handoff

The first **player-facing** implementation PR should cover **AE-27-00b + AE-27-01a/01b**, stopping
at one baseline Ugly Stick wheel alternative. Precede it with reviewable internal increments:

1. Strict, independently versioned selection contract and trusted resolution, with explicit Original
   selections and unknown/stale-ID refusal. Keep it disconnected from v4 persistence and flight until
   the whole migration is ready; do not silently allocate a presentation version.
2. A native, same-envelope Stik tread prototype on the three existing mesh handles. Stage all resources
   before publishing, restore the exact original meshes/overrides, and test independent mesh bounds,
   instance isolation and failed staging. Keep its status unqualified and internal.
3. Coordinate the fleet-wide profile/binding/proof migration, then connect preview, history,
   save/recovery, thumbnail, bundle import, Workshop/CLI launch and return. Add the public selector only
   when those paths enforce the same trusted compatibility result.
4. Record native rest/steering/compression fit and lifecycle evidence. Give the alternative its actual
   flight-eligibility result; if it fails, retain the preview/save feature and narrow the geometry.

The internal tread prototype is a mechanism check, not a substitute for the Small/Large/XL work in
AE-27-01c and not an assertion that oversized tires preserve the original support geometry.

The PR is ready when it has a source-generated binding, strict profile and launch validation,
unchanged original behavior, one-step history, save/recovery/thumbnail integration, C1–C4 evidence for
that slice, and a bounded lifecycle/cost observation. Full C5 target/platform qualification stays
explicit until measured. Follow with one additional preset or one aircraft at a time; each PR names
its dependency and the user-visible result.

Do not start physical work to repair a cosmetic fit silently. Escalate that option to preview-only
or its explicitly scheduled physical phase. Do not implement props/floats/retractable conversions
inside the first wheel PR. The delivery order is additive: a later package can remain unavailable
without preventing players from using already-qualified appearance choices.
