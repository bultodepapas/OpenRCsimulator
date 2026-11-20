# AE-27-R1 — Twenty investigations for Workshop attachments

**Research date:** 2026-11-19 (America/Bogota). **Status:** research and planning only.
**Repository baseline:** `5228fc60d3cbad5bd54ebc6e50db9ea2bdf6e394` on
`plan/workshop-aircraft-attachments-2026-11-19`.
The [attachment plan](../../../plans/workshop-aircraft-attachments.md) owns delivery order and
acceptance; the [source audit](../AE-27-00/README.md) owns the inspected OpenRC behavior.

## Purpose and method

Strengthen the proposed wheels, landing gear, propeller and spinner feature with twenty distinct
research questions: five about games/simulators, six about RC catalogs and installations, five about
open-source tools/assets, and four about community experience. Multiple sources can answer one
question; twenty URLs would not by themselves constitute twenty investigations.

Technical observations below come from developer documentation, source repositories, manufacturer
catalogs/manuals or university research. Creator and Reddit posts supply firsthand preferences and
failure scenarios, not calibrated physics, representative demand estimates or proof of compatibility.
Each investigation separates observed evidence from the lead's proposed application and names a
phase and an observable acceptance condition. "Adopt" means incorporate into the plan, not implemented.

Sources were searched and retrieved on the research date. R17–R19 use search-indexed Reddit text;
attempts to open several full threads were unavailable. R20's two full threads were readable. Historic
manuals are labeled, and current documentation on moving `main`, `master`, `latest` or `stable` URLs
must be pinned again before tool adoption. The RealFlight PDF was read through its retrievable indexed
text after a direct download exceeded the retrieval size limit. No game was run, asset downloaded,
library installed, model fitted or physical coefficient validated in this research.

## Decisions carried into the plan

| Research | Decision | Delivery impact |
| --- | --- | --- |
| R01, R02, R05, R18 | Keep appearance and installed hardware separate, with visible effect labels and a protected original. | Reinforces cosmetic Phases 1–4; no automatic power, sound, weight or water change. |
| R03, R04, R07, R08, R10 | Author complete kits and approve combinations of configuration, gear, wheel/pants, propeller and spinner. | Extend AE-27-00b fit declarations; one transaction and Undo for dependent parts. |
| R06, R09, R17 | Give choices distinct silhouettes: smooth balloon tires, slim treaded tires, pointed cone, exposed fastener and nut. | Qualify presets individually; keep exaggerated failed fits as preview-only. |
| R02, R20 | Make Save, Original, reset, status and changed parts easy to understand; keep browsing context stable. | AE-27-01b and cosmetic release review; no separate editor or save system. |
| R12–R14, R16 | Use the existing native generator first; evaluate imported assets and offline tools only where needed. | Preserve mount identities and provenance; no new dependency blocks the native wheel pilot. |
| R11, R15, R19 | Classify measured, manufacturer-computed, estimated and anecdotal evidence honestly. | Better physical-wheel, propeller and water qualification in Phases 5–7. |

After the individual choices work, optional appearance combinations can give the feature a playful
identity: **Classic**, **Bush look**, **Sport look**, **XL / Fun** and **Float study**. These are OpenRC
design proposals, not copied game features, licensed branded kits or promised performance packages.
They resolve to existing approved option IDs and use the existing compatibility/history flow.
They do not enlarge the first implementation PR.

## Games and simulator workflows

### R01 — RealFlight: can visual changes remain separate from flight behavior?

**Sources:** [RealFlight G3 manual, aircraft editor](https://forums.realflight.com/downloads/RealFlight%20G3%20Manual.pdf)
(historic developer manual) and [KEmax overview](https://forums.realflight.com/KEmax/).

**Observed:** the G3 editor documents separate graphical and physics dimension scales, and states
that graphical scale does not change flight characteristics. KEmax describes a visual mesh format
and distinguishes exported color schemes, aircraft variants and complete airplanes. This is evidence
of an established separation of responsibilities, not evidence that current RealFlight offers the
exact interchangeable parts proposed here.

**Apply — adopt, AE-27-00b/01b/03a:** keep attachment selections in the presentation profile and make
Original a reliable comparison target. Save a customized build through existing revisions. Expose
physical installation changes later as an explicit action, so a visual wheel or blade choice never
quietly becomes an engineering parameter.

**Acceptance:** within the same accepted source/descriptor/model pins, selecting an appearance
alternative changes presentation identity while resolved physical bytes, contacts, propulsion and
same-input flight results remain equal. A source migration has its own rebind/copy decision.

**Limit:** the G3 manual is historical. Its visual scaling does not establish acceptable OpenRC tire
contact, arbitrary scale support, interchangeable mesh slots or permission to reuse RealFlight content.

### R02 — Aerofly RC: how can variants remain easy to discover, test and restore?

**Sources:** [Aerofly RC10 manual, model configurations](https://www.ikarus.net/en/rc10-manual/)
and [Aerofly RC9 manual, model editor](https://www.ikarus.net/en/aeroflyrc9-online-manual/).

**Observed:** RC10 documents model previews, favorites and model-specific setups or drive variants.
Some controls change mass or stall behavior. The RC9 editor documents Test, Save As, per-part and
all-part revert, and protected supplied models. These version-specific behaviors suggest useful
interaction patterns; they are not all cosmetic changes.

**Apply — adopt, AE-27-01b/04c:** keep a short choice list beside the aircraft, an explicit Original,
clear Save build status and the existing test/return journey. State whether a choice is appearance
only or preview only before selection. Later named looks can combine approved choices without
creating another editing mode or storage format.

**Acceptance:** a keyboard/controller user can select, compare, save, test where eligible and return
to the retained draft. Reset Parts affects the four attachment slots; page reset follows the existing
Appearance contract. Known defaults survive; named saved builds never overwrite stock.

**Limit:** the manuals do not demonstrate our wheel/spinner interchangeability or validate an
accessible OpenRC layout. Do not copy Aerofly's physical tuning behavior into cosmetic controls.

### R03 — SimplePlanes: what makes a reusable kit dependable?

**Sources:** [developer update v1.5.3](https://www.simpleplanes.com/Blog/View/490440/Update-v1-5-3)
and a creator's [Eurofighter Rapid Arming Kits](https://www.simpleplanes.com/a/uy6C3r/Eurofighter-Rapid-Arming-Kits).

**Observed:** the developer's historic update records a fix for an invalid subassembly preventing
the designer from loading. The creator describes labeled connected kits that reduce repetitive
assembly and avoid accidental connections. The latter is a firsthand workflow example, not an
official guarantee or a proposed combat feature for OpenRC.

**Apply — adopt the assembly pattern, AE-27-00b/02b/04a:** a wheel/pant set or float kit has an explicit
affected-part list and is resolved before it replaces the current assembly. Rebind dependent
materials, steering, damage and propeller handles. Keep freely positioned connectors and arbitrary
user subassemblies outside the first release.

**Acceptance:** one action changes the complete kit, one Undo restores it, and a malformed reference
or missing dependency refuses the candidate while preserving the editable document. Closing and
reopening the Workshop never leaves a partial assembly.

**Limit:** a historic fixed bug is a useful negative-test scenario, not a claim that today's game is
broken. Publicly shared craft do not establish redistribution rights for their meshes. This
investigation uses the original SimplePlanes; it does not mix its version history with SimplePlanes 2.

### R04 — BeamNG: how should compatible parts and defaults be represented?

**Source:** [BeamNG developer documentation, part/slot system](https://documentation.beamng.com/modding/vehicle/intro_jbeam/partslotsystem/).

**Observed:** BeamNG documents unique internal part names, slot types, parent/child choices and saved
slot-to-part mappings. Available children depend on preceding selections; absent configuration
entries can use defaults. This demonstrates a data-driven relationship between parts and presets.

**Apply — adopt a bounded version, AE-27-00b/02b/04a:** use stable IDs, explicit parent-kit dependencies
and per-aircraft approvals. A matching generic slot type is insufficient: the actual configuration,
wheel/pant set, prop/spinner pair, binding revision and supported scale domain must agree. Keep the
player UI at four understandable categories, even if authoring needs richer relationships.
Evaluate the actual selection and accepted installation dimensions; retain recognized Original
components under the existing baseline and qualify interactions affected by the new option. No
Cartesian matrix of unoffered combinations is required for the first wheel set.

**Acceptance:** an approved Extra larger-wheel/no-pants assembly changes and saves atomically;
an incompatible combination explains the conflict without mutating the draft. Missing selections
in recognized legacy versions resolve to Original. Explicit unknown, duplicated or stale IDs fail
validation, including on unsupported aircraft; they never silently become stock.

**Limit:** BeamNG parts can affect simulation. Its open mod system and exact slot semantics are
inspiration, not a schema to import or an OpenRC safety/compatibility oracle.

### R05 — X-Plane: how do detailed visuals coexist with authored physical geometry?

**Source:** [Plane Maker manual v12](https://developer.x-plane.com/manuals/planemaker/), especially
landing gear, propeller authoring and 3-D objects (manual dated 2024-05-13).

**Observed:** the manual distinguishes the flight-model ACF from detailed object overlays. It also
exposes separate gear size/location, steering and friction settings, and propeller geometry inputs.
Some fairings are physical Plane Maker bodies, so a familiar visual part name alone does not imply
that it is physics-free.

**Apply — adopt the boundary, AE-27-03a/05a–05c:** render cosmetic options through their authored frames;
later installed packages own their mass, inertia, drag and contact changes. A physical wheel swap is
an integrated installation, not a visible radius edit with an approximate weight multiplier.

**Acceptance:** the cosmetic propeller keeps the original physical disc and load while its rendered
blades, rotation, blur and damaged state agree. The first physical wheel package passes independent
mass/CG/tensor accounting, ground pose, steering, contact, clearance and real start qualification.

**Limit:** documentation of another simulator does not validate RC-scale coefficients or this
repository's implementation. No X-Plane objects or flight models are proposed for copying.

## RC catalogs and actual assemblies

### R06 — Large wheels: which dimensions and styles make useful presets?

**Source:** [DU-BRO Big Wheels catalog](https://www.dubro.com/products/big-wheels).

**Observed:** the catalog shows smooth inflatable tires with two-piece hubs and caps, and lists
diameter, axle diameter, width and per-wheel mass. For example, its 4-inch and 6-inch entries share a
5/32-inch axle but have different widths and weights. Matching one interface does not describe the
whole wheel.

**Apply — adopt, AE-27-00b/01a–01c:** author a smooth balloon-tire silhouette for Bush look and an
exaggerated XL / Fun study. Record outer diameter, width, bore/axle, offset, hub/retainer and tread
style in source fit evidence. These are authored dimensions, not new player-editable solver inputs.
Start with a modest alternative; let each additional size earn its own availability.

**Acceptance:** front, side and underside reviews cover hub/leg clearance, steering, compression,
ground-support mismatch and the approved aircraft-scale domain. A failed XL fit remains preview-only.
Catalog mass is not applied during cosmetic phases.

**Limit:** these are manufacturer examples, not measured Ugly Stick dimensions, friction, stiffness,
drag or inertia. The catalog's performance language is not a calibration dataset. Design references
do not grant rights to product photographs or CAD.

### R07 — Lightweight wheels and pants: when is a complete kit necessary?

**Sources:** [DU-BRO Super Lite](https://www.dubro.com/collections/tires-wheels/products/super-lite-wheels),
[Sullivan S854 wheel](https://sullivanproducts.com/products/s854-5-skylite-wheel-with-aluminum-hub)
and [Sullivan S889 pant bracket](https://sullivanproducts.com/products/s889-wheel-pant-attachment-bracket).

**Observed:** the foam wheel catalog supplies a different tread/hub construction and dimensional
table. Sullivan's wheel describes a removable hub and bearing for a 3/16-inch axle; its separate pant
bracket also specifies a 3/16-inch axle. Matching axle dimensions still leave pant envelope and
mounting clearances unresolved.

**Apply — adopt, AE-27-01a/02b:** offer a coherent wheel, hub, retainer and pant/no-pants assembly. A
larger Extra wheel can explicitly select the authored no-pants counterpart rather than intersecting
the original fairing. Use a slim treaded appearance as another possible style after the pilot.

**Acceptance:** each offered kit has no duplicate wheel, floating retainer or pant intersection in
its declared rest, steering and compression poses. Selection, cancel, reset and Undo restore the
entire assembly and its observer bindings.

**Limit:** the pages do not certify a combined Sullivan installation or any OpenRC aircraft. Listed
mass is per component and must not be mistaken for an aircraft package delta; physical bookkeeping
begins in Phase 5.

### R08 — Spinners: why must shape, shaft and blade openings be considered together?

**Sources:** [DU-BRO three-blade spinner](https://www.dubro.com/products/spinner-3-blade),
[DU-BRO fitting guide](https://www.dubro.com/blogs/du-bro-101/du-bro-101-how-to-install-spinners-nose-cones-on-rc-airplane)
and [Tru-Turn P-51-style spinner reference](https://www.truturn.com/product/3-p-51-3-blade-aluminum-spinner/).

**Observed:** DU-BRO lists multiple cone sizes and shaft adapters, and its guide checks blade-root
width/depth and opening clearance. Tru-Turn documents multiple shapes, blade-count variants,
backplates and separate adapters. The Tru-Turn page also announces suspended hobby manufacturing
in 2022; use it as a design reference, not a current purchasing recommendation.

**Apply — adopt, AE-27-02a/03b:** author the pointed spinner as a complete compatible cone/backplate
assembly. Validate the selected propeller and spinner as a pair, including root cutouts and shaft
frame. Extra retains its tilted thrust frame; the Stik gets its own authored socket.

**Acceptance:** all offered two-/three-blade pairs clear their openings, preserve handedness and
restore correctly through rotation, blur, strike and reset. Unsupported pairs cannot enter the draft
as half-applied changes.

**Limit:** a product's P-51-style label does not qualify the simulated P-51. Catalog proportions and
fitting rules are not universal OpenRC dimensions, aerodynamic coefficients or licensed geometry.

### R09 — Nut and no spinner: what should actually remain visible?

**Source:** [Tru-Turn, prop nuts versus prop hubs](https://www.truturn.com/difference-prop-nuts-prop-hubs/)
(manufacturer design reference; see R08's manufacturing-status qualification).

**Observed:** Tru-Turn distinguishes solid threaded nuts from larger hollow hubs with separate
adapters, and describes acorn and cone silhouettes. The terms describe distinct assemblies, not
just colors of a spinner cone.

**Apply — adopt, AE-27-02a:** give Nut and No spinner visibly different meanings. Nut selects an
authored nut-like finish. No spinner removes the decorative cone while retaining the appropriate
shaft, washer, retainer and any required backplate artwork. Resolve these details separately for
the Extra and each approved Stik installation.

**Acceptance:** front, side and oblique views show plausible retention without duplicate stock nuts,
an empty shaft or overlapping backplates. Every transition back to Original survives save/reopen,
spinning and reset, with physical recipe and installed audio unchanged.

**Limit:** the source is not a universal fastening specification or a qualification of the existing
OpenRC engine. The phase authors a visual assembly only; actual fastening mass and physical fit
require the later installed-package evidence.

### R10 — Float conversions: what is included in a real named kit?

**Sources:** [E-flite EFL5261 catalog](https://www.horizonhobby.com/product/float-set-timber-timber-10-year-air-tractor/EFL5261.html)
and [Turbo Timber Evolution manual, float installation](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/dw442b6efc/Manuals/EFL105250-Manual-EN.pdf).

**Observed:** the catalog names supported aircraft. The manual shows paired floats, crossmembers,
different front/rear struts, plates, fuselage supports and rudder linkages. It is a coordinated
assembly, not two unrelated meshes under an arbitrary airframe.

**Apply — adopt kit completeness, AE-27-04a; defer water behavior to 07a–07d:** independently author a
Stik-specific Float study with struts, coherent mounting and wheel suppression. Retain its preview-only
status through every save/thumbnail/launch path. The later working float kit has separately sourced
mass, displacement, station, forces and water admission.

**Acceptance:** select/Undo restores the complete gear set; a saved Float study produces a thumbnail
but cannot start a trial. Functional water work must independently pass equilibrium, start, taxi,
transition and terminal-contact arbitration checks.

**Limit:** the kit does not establish Ugly Stick compatibility, float volume/CG, hydrodynamic
coefficients or permission to copy proprietary geometry. A real Turbo Timber accessory also does
not automatically qualify OpenRC's Turbo Lumber asset or physical model.

### R11 — Propeller data: what can support a later physical three-blade package?

**Sources:** [APC performance methods/index](https://www.apcprop.com/performance-data-new/),
[APC 11x7E-3 table](https://www.apcprop.com/files/PER3_11x7E-3.dat),
[APC 11x7E-3 catalog](https://www.apcprop.com/product/11x7e-3/)
and the [UIUC Propeller Database](https://m-selig.ae.illinois.edu/props/propDB.html).

**Observed:** APC identifies its tables as geometry-based vortex-theory computations. The opened
three-blade table has simulation/version metadata and RPM/advance-ratio Ct/Cp fields. UIUC separately
publishes wind-tunnel measurements for model-aircraft/UAV propellers. APC's product page lists
right-hand rotation and a spacer for pusher applications: mounting aft and reverse rotation are
separate attributes.

**Apply — adopt provenance and fit metadata now; defer physical adoption to AE-27-06a:** record blade
count, physical diameter/pitch, hub interface and handedness. Cosmetic three blades retain the
existing physical disc, load and sound. Later evidence must identify the exact installed propeller,
test or computation method, revision, units and operating domain; compare with measured evidence
where an appropriate match exists.

**Acceptance:** no universal blade-count power multiplier or borrowed curve for another diameter,
pitch or engine. Phase 6 checks load, energy, thrust/torque and RPM domain for the actual package.

**Limit:** this research does not establish a measured three-blade match for the Stik/Extra, nor
redistribution rights for APC datasets/geometry. An available table is a candidate source, not an
accepted OpenRC coefficient set. MoonRunner work remains deferred.

## Open-source tools, GitHub and asset libraries

### R12 — Godot and glTF: how should mount identities survive authoring and import?

**Sources:** [glTF 2.0 specification, indices/names and extras](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html)
and [Godot import configuration](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html).

**Observed:** glTF names are optional and not guaranteed unique. Extras carry application data.
Godot documents an import-extension route that can convert Blender custom properties into node
metadata; that does not establish automatic runtime metadata for this project's engine version.

**Apply — adopt explicit bindings, AE-27-00b/01a:** generate revisioned mount/target bindings tied to
the exact model/source digest. Preserve the project's named aircraft, propeller, hinge and wheel
pivots. Treat namespaced extras as an optional authoring aid for imports, never an unvalidated second
runtime source of truth. The native Stik wheel pilot can use its existing generator directly.

**Acceptance:** missing, duplicate, renamed or stale targets refuse explicitly. Two instantiated
planes can swap independently; changing or freeing one leaves the other's materials, visibility and
handles intact. Regeneration reproduces the same accepted bindings.

**Limit:** latest documentation is not proof of behavior in pinned Godot 4.8 beta2. This pattern
requires no engine upgrade, global name search or new generic scene framework.

### R13 — glTF Transform and meshoptimizer: when is optimization worth adding?

**Sources:** [glTF Transform CLI](https://gltf-transform.dev/cli),
[gltfpack README](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md)
and [glTF Transform license](https://github.com/donmccurdy/glTF-Transform/blob/main/LICENSE.md).

**Observed:** glTF Transform supplies inspection and selectable optimization operations. gltfpack
can merge scene content and provides flags for retaining named nodes, materials and extras. Its
README and glTF Transform's license identify MIT licensing. Preservation flags alone do not prove
that OpenRC's pivots, references or importer behavior survive.

**Apply — adopt measurement-first evaluation; defer a dependency:** only an actual imported-asset
bottleneck justifies an offline experiment in AE-27-04b/C5 or the owning asset step. Keep the lossless
source and unoptimized export; use a pinned tool and selected transforms on a disposable copy.
Do not optimize the separate Stik engine GLB merely because its native wheels change.

**Acceptance:** compare hierarchy, mount frames, bindings and critical materials before/after, then
measure bytes, geometry/surface counts, texture cost and real preview/flight frame/resource cost.
Reject a semantic change or an optimization with no useful measured gain. Verify any emitted
extension on the actual engine.

**Limit:** neither a smaller file nor MIT tool code grants asset rights, guarantees frame-rate gains
or authorizes flattening swappable parts. No runtime optimizer is proposed.

### R14 — Blender export and Khronos Validator: what should an import gate prove?

**Sources:** [Khronos Blender exporter documentation](https://github.com/KhronosGroup/glTF-Blender-IO/blob/main/docs/blender_docs/scene_gltf2.rst),
[glTF Validator README](https://github.com/KhronosGroup/glTF-Validator/blob/main/README.md)
and [Validator license](https://github.com/KhronosGroup/glTF-Validator/blob/main/LICENSE).

**Observed:** the exporter can write custom properties to glTF extras when configured. The validator
checks glTF syntax/structure/resources, emits JSON issues/statistics and returns an error status for
detected errors. Its extension coverage is finite; its code is Apache-2.0.

**Apply — adopt a conditional authoring gate:** if a selected attachment uses glTF, record source
hash, exporter/version/settings and output hash; retain the validator report, resolve errors and
review warnings and unsupported extensions. Separately verify OpenRC's unique mount IDs, hierarchy,
transforms, dependency closure and exact binding digest. Pin/provision the tool before relying on it.

**Acceptance:** a malformed GLB fails format validation; a structurally valid GLB with a missing or
duplicated required mount fails the OpenRC check. A valid import still needs native rendered fit,
instance isolation and cosmetic parity evidence.

**Limit:** these are different checks. glTF validity is not fit, licensing or physical qualification.
They are not new prerequisites for AE-27-01a's native generated wheels; preserve and validate that
existing source pipeline instead.

### R15 — JSBSim: what can declarative installed-gear data teach us?

**Sources:** [C172P aircraft definition](https://github.com/JSBSim-Team/jsbsim/blob/master/aircraft/c172p/c172p.xml),
[JSBSim schema](https://github.com/JSBSim-Team/jsbsim/blob/master/JSBSim.xsd)
and [project README/legal notice](https://github.com/JSBSim-Team/jsbsim/blob/master/README.md).

**Observed:** the aircraft definition names separate nose/main bogey contacts with units, positions,
friction, suspension, steering and brake groups, plus structural contacts and a positioned propeller
thruster. The examined schema's buoyant-forces section uses gas cells; it is not evidence of a
floatplane water law. The project identifies the library as LGPL-2.1 and its aircraft approximations
as educational/entertainment models.

**Apply — adopt data completeness, AE-27-05a/05b:** describe the physical replacement as an installed
package with source/units, mount stations, replaced inventory, contact/steering/brake dependencies
and independent derived mass properties. Preserve OpenRC's shared vehicle-module boundary.

**Acceptance:** one replacement removes the old physical component exactly once; contact pose,
travel and clearance agree with the installation. Same-input taxi/landing comparisons and numerical
admission evaluate the assembled candidate.

**Limit:** no full-size C172 coefficient, XML asset or solver is being copied. JSBSim is not a new
runtime dependency, and its library license alone is not a complete per-asset provenance review.
Actual water-law research and validation remain Phase 7 work.

### R16 — Poly Haven and Kenney: are reusable wheel assets actually suitable?

**Sources:** [Poly Haven Old Tyre](https://polyhaven.com/a/old_tyre),
[Poly Haven asset license](https://polyhaven.com/license)
and [Kenney Racing Kit](https://kenney.nl/assets/racing-kit).

**Observed:** Poly Haven lists a CC0 worn automotive tire; its asset license permits reuse and
redistribution. Kenney lists a CC0 3-D racing/car kit. Neither listing establishes a matching RC tire,
hub, spinner, mounting frame or desired clean aircraft style.

**Apply — adopt source screening; defer these specific assets:** check suitable reusable sources
before creating equivalents, but keep the existing native generator as the pilot default. For an
actually chosen asset, retain its exact URL, creator, license, revision/download hash, modifications
and export provenance. Evaluate material cost, proportions, tread, pivot and rig fit together.

**Acceptance:** only a candidate with suitable geometry/style, reproducible source, reviewed rights
and declared bindings can enter the authored catalog. It must pass the same fit, two-instance and
C5 cost gates as an original mesh.

**Limit:** no downloaded asset was inspected. CC0 does not prove suitability, and a site's example
renders/logos are distinct from its licensed downloadable assets. These catalogs are potential
resources, not a promise that wheel art is already solved.

## Reddit and community questions

### R17 — Oversized wheels: is the playful idea recognizable to hobbyists?

**Sources:** [request for disproportionate wheels, 2023-09-07](https://www.reddit.com/r/RCPlanes/comments/16crvti/)
and [T-28 grass/landing-gear discussion, 2024-08-02](https://www.reddit.com/r/RCPlanes/comments/1eicwhd/t28_trojan_11_m_anyone_experience_how_the_landing/).
**Access:** search-indexed thread text; not a complete independently read discussion.

**Observed:** one poster explicitly wants exaggerated wheels on a small, non-scale model. Other
posts discuss wheel substitutions and differing experiences on grass. This supplies recognizable
language and use cases, not a representative market survey or measured performance benefit.

**Apply — adopt the playful presentation, AE-27-01c:** keep XL / Fun as a distinct authored style
instead of making every option look like a small engineering variation. Use side-by-side views and
a common visual scale to show the difference clearly. Bush look names an appearance; it does not
advertise improved grass handling while cosmetics leave contact behavior unchanged.

**Acceptance:** players can tell Standard, Large and XL apart, see availability before choosing,
and restore Original. The implementation review measures clipping, nose steering and ground mismatch;
exaggeration is allowed in preview when flight fit is not acceptable.

**Limit:** do not infer friction, added drag, safe tire size or Stik compatibility from these comments.
Physical rough-field behavior requires a separately qualified terrain/contact domain.

### R18 — Blade-count discussions: which misconception should the UI prevent?

**Sources:** [3 Blade Props, 2024-05-31](https://www.reddit.com/r/RCPlanes/comments/1d55xv5/)
and [Three Bladed Prop, 2024-05-07](https://www.reddit.com/r/RCPlanes/comments/1cmpq3e/).
**Access:** search-indexed thread text; full-thread retrieval was unavailable for the first source.

**Observed:** posters ask whether a third blade yields extra power without other changes or can be
substituted directly. Replies give conflicting broad rules and installation-specific exceptions.
That disagreement identifies a communication risk; it does not resolve propulsion physics.

**Apply — adopt clear effect copy, AE-27-03a/03b:** label the cosmetic three-blade option as a visible
change with unchanged flight behavior. Keep Compare free of invented thrust, speed or weight gains.
Leave installed engine/propeller sound unchanged. A future physical propeller is a distinct qualified
package using evidence of the kind evaluated in R11.

**Acceptance:** changing two to three visible blades does not change compiled propulsion, accepted
physical diameter, torque, thrust or audio configuration. Spinner pairing, blur and broken stubs
still reflect the chosen visible assembly.

**Limit:** reject generic percentage-power, fixed current-ratio and diameter-conversion rules from
comments. No commenter claim is used as an OpenRC coefficient or engine compatibility approval.

### R19 — Float experiences: which scenarios deserve later acceptance tests?

**Sources:** [custom floats with problems, July 2021](https://www.reddit.com/r/RCPlanes/comments/olt7yc/)
and [first-time float flying, August 2021](https://www.reddit.com/r/RCPlanes/comments/p01rps/).
**Access:** search-indexed thread text; full-thread retrieval was unavailable.

**Observed:** discussions raise balance and float placement, difficulty leaving the water, limited
low-speed steering without water rudders, acceleration and wind sensitivity. Those are candidate
failure scenarios. The actual installation example in R10 is the primary assembly reference.

**Apply — adopt a bounded test list, AE-27-07a–07d:** inspect equilibrium/heel, low-throttle steering,
acceleration through the declared takeoff envelope, prop/water clearance and transition back onto
water. Include wind and shore cases only within an explicitly admitted domain; reject unsupported
conditions instead of inventing force behavior.

**Acceptance:** the qualified pilot has explicit expected outcomes for rest, taxi, takeoff, landing,
overturning/unsupported contact and restart. Stock non-float aircraft retain terminal lake behavior.
No invisible wheel support or simultaneous terminal and buoyant response is allowed.

**Limit:** the threads do not supply validated step placement, CG ranges, float volume, damping or
planing coefficients. Do not copy suggested pitch angles or operating technique into the physics
law. This research does not close Phase 7's hydrodynamic evidence gap.

### R20 — Parts-selector complaints: how do we preserve the user's context?

**Sources:** [BeamNG configuration-saving question, 2023-01-14](https://www.reddit.com/r/BeamNG/comments/10c2f52/does_anyone_know_if_you_can_save_a_specific/)
and [parts-selector visibility discussion, 2023-06-19](https://www.reddit.com/r/BeamNG/comments/14dapgv/car_dissapearing_in_parts_selector_028/).
**Access:** full threads retrieved.

**Observed:** one user did not know a configured vehicle could be saved. Another thread mixes
discussion of selected-part isolation with an invisibility problem that the original poster later
attributes to a broken mod. It is not evidence of a confirmed built-in BeamNG defect.

**Apply — adopt UX hypotheses, AE-27-01b/04c:** keep Save build and saved/unsaved status visible; preserve
category, scroll/focus and useful camera orientation through changes. Highlight the selected part
option in the UI while retaining the whole aircraft in the preview. Defer 3-D part highlighting unless
the existing infrastructure supplies it. If an isolate mode is ever added, make it explicit and
restore visibility on cancel/reset/failure. Recalculate bounds when larger parts need more room.

**Acceptance:** repeated swaps do not jump the selection, lose keyboard focus or leave the airplane
hidden. A failed thumbnail leaves the saved build accessible with a retry/placeholder. Camera-only
actions do not dirty the build; Cancel and Undo preserve all unrelated draft edits.

**Limit:** these are small anecdotal samples, not proof of an optimal UI. Native 1080p/controller/EN-ES
review, plus the repository's Apple Retina exception, still determines whether the proposal works.

## Phase impact and scope control

| Phase | Research-driven addition | Still outside that phase |
| --- | --- | --- |
| 0 | Explicit assembly relationships, dimensional fit evidence, unknown-ID refusal and source bindings. | Universal part compatibility or a generic free-building editor. |
| 1 | One native Stik wheel set; clearer visual comparison, save status, focus/camera retention and complete restoration. | New import dependencies, multi-aircraft release, spinners or water physics in the first PR. |
| 2 | Pant/no-pant kits, proper nut/no-spinner assemblies, prop/spinner cutout evidence. | Automatic fit from matching axle or advertised product name. |
| 3 | Honest three-blade copy, unchanged installed sound and physics, compatible complete nose assembly. | Blade-count thrust multipliers or unqualified physical propellers. |
| 4 | Coherent float study; optional named appearance combinations; imported-asset tools only when justified. | Flyable decorative floats or a marketplace/community asset loader. |
| 5 | Per-component provenance/units and complete physical replacement/contact bookkeeping. | Treating catalog marketing or community anecdotes as calibration. |
| 6 | Exact propeller evidence, computation-versus-measurement labels and operating-domain checks. | Substituting an unrelated APC curve; delaying floats solely for a missing three-blade dataset. |
| 7 | Explicit water-equilibrium, steering, transition and failure scenarios. | Full CFD, arbitrary waves, amphibious retracts or universal float conversions. |

The first implementation remains **AE-27-00b + AE-27-01a/01b**, one alternate baseline Ugly Stick
wheel assembly with a complete edit/save/preview/test-where-eligible/return flow. The existing eight
phases and twenty-one implementation subphases remain the delivery structure. Research refines their
requirements; it does not turn twenty investigations into twenty new features or required dependencies.

## Review and verification

Three bounded read-only researchers investigated games, catalogs and open-source tools. The lead
retrieved the material original sources, resolved product/version and evidence-quality differences,
and authored the integrated recommendations. A separate adversarial pass reviewed the actual draft
for scope, defaults, kit restoration and the cosmetic/physical boundary. The lead accepted both scope
corrections: selection emphasis uses existing UI rather than requiring a new 3-D highlight effect,
and compatibility checks cover the actual offered combination and changed interactions rather than
an exhaustive Cartesian matrix. All eight phases and twenty-one implementation subphases remain.

The existing `tools/ci/check_docs.py` parser/checker resolved all **10 new local references** in the
two changed documents. A structural check confirmed exactly **20 ordered investigations**, each with
sources, observations, disposition, acceptance and limits, and the unchanged **21 implementation
subphase IDs**. Tracked/staged whitespace checks passed. The report contains **44 distinct external
source URLs**, with the access limitations stated above. These are documentation checks; no simulator
test, native render, tool installation, asset-fit test, benchmark or flight qualification is claimed.
