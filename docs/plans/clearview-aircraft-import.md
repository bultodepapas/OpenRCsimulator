# ClearView aircraft import plan

**Date:** 2026-11-15; updated 2026-11-16. **Status:** implementation in progress; bounded readers, an experimental visual adapter, conservative v6 hinge proposals and source-declaration review are integrated. Flight, Home, portable-source and exported-platform gates remain open. **Owner:** Aircraft Creator / Workshop. **Steps:** AC-CV-00…14, a subtrack of AC. The [research and source inventory](../research/aircraft-creator/clearview-2026-11-15.md) records the inspected downloads, primary documentation, source identities and limits. The [Creator plan](aircraft-creator.md) continues to own AC-00…25 and its gates.

## 1. Product outcome

A player selects a locally downloaded ClearView aircraft ZIP, chooses an aircraft if the ZIP contains a pack, reviews its appearance and detected configuration, completes missing physical information, test-flies the exact candidate, saves a version, selects it in Home, and can reopen and fly it after restarting an exported OpenRC build. Import must explain what needs correction and preserve the player's source files.

Build a compatibility adapter into Aircraft Creator. Convert supported legacy visuals into its bounded, self-contained GLB representation; retain ClearView parameters as attributed observations and compile a separate, complete `openrc-aircraft v2` configuration through supported OpenRC laws. A faithful appearance and a numerically admissible aircraft are separate results. Reproducing ClearView trajectories or claiming real-aircraft fidelity is outside automatic conversion.

### Availability levels

| Result | What the player can do | Required evidence |
| --- | --- | --- |
| Preview | View the converted aircraft and original paint | Archive, AC3D, image, GLB and resource admission; complete visual dependencies |
| Draft | Correct placement, physical data and control bindings | Typed records, source provenance and actionable missing-field diagnostics |
| Experimental flight | Test an explicitly estimated or borrowed configuration | Supported topology and powertrain, complete v2 data, exact-context start checks and the applicable numerical gate |
| Saved aircraft | Reopen a published revision and launch it from Home | Immutable dependency closure, resolver, restart, recovery, replay and exported-platform gates |
| Physically qualified configuration | Use a configuration with a bounded realism claim | Independent measurements, calibration and held-out flight evidence for that installation |

Saving does not grant flight admission. A draft with an unsupported topology remains editable and previewable. Structural/decoder failures prevent even preview; a deliberately simplified preview must list every omitted feature. Do not represent an omitted motor, second wing, wheel or mixer as a complete flyable conversion.

## 2. Baseline and dependencies

The repository was inspected at `c930dcdbfe16d0f94f25d36c64e4384069730714`, with unrelated working-tree changes preserved. Relevant current boundaries:

| Existing component | Reuse | Remaining dependency |
| --- | --- | --- |
| `workshop/creator/source_importer.gd`, `glb_preflight.gd`, `png_check.gd` | Captured immutable bytes, strict GLB/PNG admission | ClearView ZIP/AC3D and original image formats are not admitted |
| `visual_builder.gd`, placement and part bindings | Runtime GLB loading, fresh instances, datum and articulation | Preserve legacy hierarchy and translate confirmed hinges |
| `definition.gd`, `compiler.gd`, `record_loader.gd` | Complete authoring definition → exact v2 bytes → accepted candidate | Current compiler is conventional, single tractor electric, finite battery and gearless; imported source provenance needs an explicit record extension |
| `trial.gd`, root/Main trial route | Frozen source/configuration and reference-backend test flight | AC-09/11 start receipt, logging, replay and restart coverage remain open |
| `store.gd` and process lock | Immutable blobs, drafts, revisions and publication pointer | AC-13 platform/export qualification, AC-18 Home resolver and AC-19 portable closure remain open |
| Strict aircraft contract and `FlightSession` | Capability, geometry, inventory, inertia, preparation and start validation | Stock support for a law does not mean Creator can author or launch it |

**Blocking flight dependency:** the existing [AC-12 campaign](../research/aircraft-creator/AC-12-numerical-campaign.md) did not pass its registered numerical gate. Preview/parser work can proceed. Any player-facing flight milestone must close that gate for its stated domain, or qualify an independently specified configuration/domain through the owning physics process. Preserve the failed campaign and preregister any revised metric; successful trim is insufficient.

Creator trials currently pin `gdscript_reference`. Keep that policy; imported aircraft do not inherit stock native-backend qualification. Do not modify the float64 kernel or add ClearView/aircraft-ID branches to it. Keep the pinned `aircraft_data.gd` source unchanged unless a separately scoped physics change is necessary.

## 3. Compatibility scope

The inspected corpus contains 26 model roots from seven ZIPs: 20 `verNumber 5.0` and six `6.0`. All 121 `.ac` files have the `AC3Db` header. This establishes an initial corpus, not compatibility with every download on the site. See the [machine-readable inventory](../research/aircraft-creator/clearview-source-inventory-2026-11-15.json).

| Wave | Supported outcome | Conditions and boundaries |
| --- | --- | --- |
| A | Local v5/v6 ZIP detection, model picker, static preview and original paint | AC3Db subset; declared render model; JPEG/BMP/PNG textures; bounded PNG output. Unsupported essential image/geometry features block complete preview |
| B | One conventional electric aircraft, articulated controls/propeller, Airborne/Hand-launch, saved revision and Home launch | Actual topology and installation fit a qualified Creator domain. Select the fixture from the corpus after inspection; do not assume that a familiar aircraft name fits |
| C | Fixed tricycle/taildragger gear, Runway starts and supported gasoline/glow installations | Depends on AC-21/23, GP contact laws and NITRO/FUEL authoring. Calmato is a valuable candidate, not a ready-made first electric fixture |
| D | Elevons, pushers, gliders, flaps and additional installations, individually qualified | Reuse supported shared laws; add Creator compilers, records, bindings and tests where missing. A named commercial airframe does not select a law |
| E | Biplanes, repeated propulsion, jets, variable geometry, V-tail/canard and retractable gear | Separate capability/law and authoring projects where unsupported. Preserve multiple physical surfaces/installations. AC-25 keeps retractable gear last |

Helicopters, multirotors, landscapes and the V-22 transition model do not become fixed-wing aircraft by import. A V-22 may have a visual preview; operational tiltrotor support requires its own vehicle-model and validation project through the shared kernel. Never collapse a multi-engine model into one equivalent motor without an explicitly authored, differently identified experimental configuration.

## 4. Architecture and trust boundaries

```text
local ZIP → bounded archive reader → model inventory + selected dependency closure
          → v5/v6 parameter AST + AC3Db scene/marker IR + attributed observations
          → visual normalization → self-contained GLB + binding candidates
          → existing Creator SourceImporter.inspect_bytes → preview

observations + confirmed definition + qualified OpenRC package
          → existing/extended Creator compiler → RecordLoader → AcceptedCandidate
          → exact-context trial → immutable Creator revision → AC-18 Home resolver
```

### 4.1 Archive admission

Capture and hash the selected ZIP once. Enumerate models by a model-root `params.txt` plus its declared dependencies; do not interpret every nested `params.txt` as another aircraft. The V-22 sample contains a duplicate under `wavdata/`. Packs have per-model outcomes and are not one all-or-nothing flight transaction.

Read entries into bounded buffers, not arbitrary filesystem extraction. Reject absolute, drive-qualified, UNC, traversal and symlink paths, encrypted/unsupported compression, overlapping entries, duplicate canonical names, inconsistent local/central metadata, invalid CRCs and truncated/overlong streams. Limit actual expanded output as well as advertised sizes, entry counts, nesting and allocation arithmetic. Inspect names for Unicode and case collisions before resolution.

Resolve exact paths first. Permit a recorded case-insensitive match only when it is unique within that model's dependency root; refuse ambiguity. Never search the host filesystem, fetch a URL from a model, or guess a missing asset from another aircraft. Five sampled model references and one texture reference require this case handling.

The existing Creator inflater handles zlib/PNG, which is not proof of bounded ZIP raw-DEFLATE support. AC-CV-01 must establish a bounded stored/DEFLATE implementation with exact consumption, output count and CRC checks on the pinned engine. Evaluate existing Godot ZIP facilities and the current inflater before adding code; do not call an allocating decoder on an unverified member. If the required guarantees are unavailable, ship only the developer conversion spike until a separately reviewed reader is ready.

Initial policy proposal, to freeze after corpus and resource measurements: 64 MiB compressed archive, 256 MiB aggregate expanded data, 4,096 entries, 64 detected models, one model conversion at a time and 32 MiB selected render-source output. These are policy ceilings, not hardware qualification. Reuse Creator's stricter downstream triangle, node, material, image and store ceilings. Test every boundary and refusal; do not increase limits merely to make a sample pass.

### 4.2 Legacy syntax and scene representation

Use a typed, bounded AC3Db intermediate representation with object hierarchy, local transforms, original qualified names, materials, per-reference UVs, surface flags and separate point/line markers. Handle comments, CRLF variants, scientific numbers and quoted names. Validate complete numeric tokens, finite values, counts, indices, hierarchy depth and byte-counted `data` fields before allocation. Unknown geometry-affecting tokens or newer AC3D versions require a diagnostic, not an optimistic parse.

Parse v5 flat parameters and v6 typed `#begin`/`#end` sections separately, selected by the actual `verNumber`. Preserve ordered repeated directives such as `breakPart`. Identical repeated scalar values can be recorded; conflicting scalar definitions require resolution. Recognize documented trailing annotations without allowing partial numeric parsing. Keep unknown fields in the import report; do not interpret them as supported physics.

Read the configured `modelName`; do not assume `body.ac`. Read `fmodel.ac`, `colbody.ac` and a configured v5 `paramModelName` in distinct roles. Do not render all `.ac` files together: doing so would display collision models, aerodynamic rectangles, markers and smoke geometry as aircraft parts.

### 4.3 Visual conversion and tool choice

Recommended product direction: a small GDScript AC3Db adapter into the existing Creator representation, using the pinned Godot image and mesh facilities. It avoids requiring players to install Blender, AC3D, Python or a native converter. Treat this choice as conditional on AC-CV-02's fidelity, resource and security evidence.

Before implementing a geometry converter, compare a reusable [Assimp AC importer](https://github.com/assimp/assimp/blob/master/code/AssetLib/AC/ACLoader.cpp) and an available Blender import route on synthetic known-answer fixtures and the local corpus. Preserve upstream notices for any reused code; pin the exact version/commit before adoption. Use them as independent comparators where useful. Do not add a three-platform native dependency solely because AC3D is supported in a library. If reuse demonstrably reduces total code and meets the same trust boundary, record that decision in AC-CV-02 and use it.

The converter must preserve transforms, crease/smoothing, normals, double-sided flags, material opacity, texture scale/offset and UV seams. Triangulate concave polygons correctly; refuse self-intersecting/unsupported polygons rather than using an incorrect triangle fan. Point/line reference objects become metadata. Keep deterministic source-object → output-node mappings even when names repeat. Do not flatten articulated nodes or merge across hinges.

Decode JPEG/BMP/PNG only after format-specific structure, dimension, size and aggregate pixel checks, then normalize to embedded PNG. Dimension checks and post-decode output checks do not bound a native decoder's workspace or CPU. AC-CV-02 must specify the admitted JPEG/BMP subset and establish malformed-input, parser-differential, allocation/CPU and cancellation evidence on the pinned exported engine; use strict Creator PNG validation for PNG. If that boundary cannot be established, refuse the affected image subtype or use a separately reviewed resource-limited decode process. Do not widen Creator's direct source-image admission to accommodate the adapter. Verify actual decoder output and re-admit the resulting GLB through `SourceImporter.inspect_bytes`; conversion never bypasses preflight. GIF is not a current Creator source-image format: ignore a confirmed optional legacy smoke effect with a visible report, or block a required texture with conversion guidance. Never silently lose body artwork. WAV files and legacy scripts/settings are not executed or automatically installed; use the existing OpenRC audio path until a separately licensed and validated audio import exists.

### 4.4 Frames, scale and moving parts

Require confirmation of nose/up, the resulting right direction, real span and wing leading-edge datum. The legacy manual itself gives an example where about two AC3D units represent a 730 mm aircraft; a universal one-unit/one-metre assumption is invalid. Store one explicit source-to-structural transform into OpenRC's `[x_aft, y_right, z_up]` LE frame. Apply it consistently to visuals, marker positions, hinge axes and candidate observations. Retain double precision for physical coordinates; rendering converts at its existing boundary. Test rotation, translation, uniform scale, handedness, winding and normal signs with asymmetric fixtures.

Creator placement currently derives a right-handed frame from nose/up, and GLB preflight refuses mirrored/sheared nodes. Normalize any required reflection into the converted vertex/normal/winding data and marker coordinates before GLB admission, leaving supported right-handed rigid transforms and positive scale for placement. An unrepresentable shear, singular transform or unverified reflection must be refused explicitly. Do not serialize an arbitrary transform and assume the existing Placement/GLB contracts admit it.

For v5, recover `XYZGroup`/`OCoord`/`ZCoord` hinge candidates. For v6, follow `XYZObject`, servo controlled-part/axis references and render-group associations. Keep parent transforms and multiple instances. A name match proposes a binding; it does not confirm control direction or aerodynamic authority. The player verifies full-left/right/up/down, neutral and propeller rotation using Creator's parts UI. Physical control signs must use `ControlSurfaces`; copying source servo signs is insufficient. Preserve stable OpenRC `airplane`, `propeller` and hinge conventions through the adapter.

Creator's current `visual_parts.gd` binds mesh-carrying nodes, rotates around the selected node origin on a local x/y/z axis, and allows at most two nodes per role. Extracted arbitrary hinge lines and group nodes do not fit that contract directly. For representable rigid assemblies, the converter must re-pivot geometry, align the local axis and preserve the complete rest transform; bake or combine only geometry sharing that same rigid motion. Test parented/offset/oblique axes and neutral-pose equality independently. Refuse unrepresentable nested/grouped articulation and role counts with a report, or extend/version AC-17 bindings and all trial/store readers before offering those controls. Never discard an additional aileron to satisfy the limit.

## 5. Physical authoring and evidence mapping

Maintain an import report per selected model. Each observation contains source ZIP/member hashes, source dialect, section/key or qualified object, raw value/unit, conversion/assumption, target field if any, disposition and reason. Unknown is distinct from zero. No solver-specific coefficient becomes an OpenRC coefficient by sharing a similar name.

| Legacy information | Proposed disposition |
| --- | --- |
| Title, authors, readme and original file names | Preserve as provenance; do not substitute author credits for a license |
| Render dimensions and aerodynamic rectangles | Propose dimension/planform landmarks after confirmed scale and frame; retain them as source geometry observations, never measured aerodynamic truth |
| `modelMass`, CG coordinates | Prefill only with established units/frame and explicit confirmation; v2 values remain borrowed or estimated source information, not aircraft measurements |
| `propDiamInch`, `propPitchInch`, RPM and watts fields | Convert explicit units exactly, e.g. inches × 0.0254; retain ambiguous curve axes and installation meaning as unresolved. Drawn propeller size is not physical propeller diameter |
| Named airfoil | Preserve identity/reference; require actual polar provenance, Reynolds/domain and the OpenRC coefficient convention before use |
| Servo links, channels, mixing and `XYZObject` | Propose part relationships. Establish real throw, timing, signs and supported mixer independently |
| Wheel/collision markers | Propose contact/hull locations. Require wheel radius, tire/suspension, support geometry and crash policy from supported authoring contracts |
| `liftCoef`, wash/damping/CG/stall adjustments, `xRotMass`, `maxThrust` | Retain in source report; no direct coefficient/inertia/thrust-law mapping without a documented derivation and independent known-answer checks |
| Gravity, camera, global input shaping, smoke and startup settings | Do not import into simulation settings. OpenRC owns environment, devices, starts and optional presentation |

The compiler must produce a complete inventory with total mass, CG and full inertia derived once; no invisible ballast or duplicate motor/battery mass. Provide the supported aerodynamic law, controls, propulsion/energy, hull and gear policy, physical IDs and `{value, unit, kind, source}` quantities. `borrowed` and `derived` already belong to v2's evidence vocabulary, but Creator's current definition/compiler accepts a narrower set: extend and version that authoring path, its store, UI and round-trip tests before importing such evidence. Preserve the original source reference through compilation rather than relabelling a copied value as player-measured or generic manual input.

Offer two explicit workflows: **review a detected installation** when sufficient compatible evidence exists, or **author a new estimated OpenRC installation** on the imported airframe. The second has its own configuration identity and visible differences from the source. It is never an automatic electric substitution for an unknown, combustion or multi-motor source. Select a qualified package only within its domain. Otherwise keep the draft and explain the missing law/data.

## 6. Persistence, replay and user experience

Extend Creator's existing immutable records with a versioned import receipt referencing the captured original package, selected model/member hashes, importer and limits versions, normalized GLB, placement, bindings, physical definition and dependency/provenance report. The current Store has one source blob constrained to 32 MiB; it cannot store a proposed 64 MiB ZIP plus a normalized GLB in that slot. Add a distinct, versioned, bounded original-package blob/reference and archive-receipt closure, keeping the existing source slot for the admitted GLB. Extend every write/read/hash/quota/export/resolver check and migration test; do not merely raise `MODEL_SOURCE_BYTES` or route the ZIP through a permissive raw-record slot. If that extension is deferred, keep the archive external with its hash and no self-contained-original/portable-source claim. Separate original, visual, physical and full-trial hashes. Painting changes visual identity without rewriting physical bytes. A compiler/conversion update creates a new revision; it never silently alters an existing saved flight configuration.

Reuse the Store's writer lock, CAS and root-pointer publication. Enforce its quota before capturing large archives; capture each original ZIP once and share it between imported pack members. Reference-count/quota policy must account for original bytes and conversion scratch even though Store is append-only. Interrupted conversion leaves the previous publication untouched. Archive/hide a revision through existing semantics; do not invent unsafe deletion or bypass the store to write into `res://`.

Use the AC-18 source resolver for Home and preference restoration; do not add user entries to the static stock catalog or generate runtime scripts. One saved selection must resolve the exact source revision after restart and revalidate flight availability. Missing or corrupted dependencies show an unavailable card with recovery guidance, never a substituted stock aircraft. AC-19 must include the entire permitted source closure for portability. A flight log's visual-source hash is not the visual bytes: test both exact physics replay and visual reconstruction, including a clean machine with the source absent. Do not embed restricted source assets into an export by default.

Player flow: **Workshop → Import ClearView ZIP → choose model → inspect conversion report → confirm orientation/size/datum → review physical configuration → verify moving parts → test flight → save aircraft → select in Home.** Keep advanced source keys in an expandable report. Show practical reasons such as “Two motors detected; this compiler supports one” or “Confirm the real wingspan”; avoid presenting parser internals as the main flow. Include cancel/progress, retry, keyboard/radio-safe navigation and the existing dirty/recovery guards.

## 7. Work packages and acceptance

AC-CV-01 has a bounded reader implementation and synthetic/corpus evidence. AC-CV-02/03 have an experimental conversion and Creator integration slice; their fidelity, resource and exported-target gates remain open. AC-CV-04 has four-point render-frame recognition, exact provenance, conservative v6 visual hinge proposals and manual group bindings. V5 hinge/propeller semantics, independent animation comparison and exported evidence remain open. AC-CV-05 has a versioned read-only source report; parameter adoption remains open. AC-CV-00 is partial, and AC-CV-06…14 remain open. The [implementation evidence](../research/aircraft-creator/clearview-2026-11-15.md#7-implementation-evidence) distinguishes implemented behavior from qualification. No whole step is marked complete by these slices.

| ID | Work | Acceptance evidence / dependency |
| --- | --- | --- |
| AC-CV-00 | Freeze supported corpus, rights ledger, compatibility matrix and resource policy | Re-download/hash receipts; one outcome per model; fixture permissions; select an actually compatible first-flight specimen |
| AC-CV-01 | Bounded ZIP inventory, safe dependency resolver and v5/v6 parser | Generated hostile and known-answer cases; CRC/truncation/overrun; unique case handling; pack picker; no filesystem/network escape |
| AC-CV-02 | AC3Db/texture conversion spike and tool decision | Asymmetric synthetic reference; transform/UV/material/pivot comparisons; defined JPEG/BMP subset, decoder malformed/peak campaign; re-admitted Creator GLB; measured peaks and exported-engine probe; no runtime dependency assumed |
| AC-CV-03 | Production preview adapter and actionable report | Corpus conversion matrix; no visible fmodel/colbody/markers; paint retained; cancellation and malformed-input isolation at 1080p |
| AC-CV-04 | Moving-part proposals and confirmed bindings | v5/v6 parented/oblique hinge fixtures; mesh re-pivoting/axis alignment and exact rest pose; role-limit/group refusal or versioned AC-17 extension; neutral/full-deflection/prop tests; independent instances |
| AC-CV-05 | Versioned source observations and Creator provenance extension | Closed-schema round trip through definition/compiler/store/UI; exact units and source hashes; ambiguous data never auto-admitted |
| AC-CV-06 | First conventional electric candidate | AC-12 numerical/domain gate; complete v2 inventory, laws and IDs; exact source/config/environment/backend/start identity; no source-installation substitution |
| AC-CV-07 | Save, Home, restart and portable dependency closure | AC-13/18/19; separate original-ZIP blob/receipt schema and admitted-GLB source; clean-profile import→save→restart→Home→fly; missing/corrupt/conflicting revision tests; quota and interruption matrix |
| AC-CV-08 | Flight lifecycle, recorder and regression coverage | AC-09/11 exact-context receipt; reset/crash/return/log/checkpoint/replay on exact candidate; original stock behavior unchanged |
| AC-CV-09 | Exported desktop and resource qualification | Windows/Linux/macOS packaged builds, read-only app install, no editor/tool prerequisite; native renderer/actual 1080p evidence; memory and cancellation checks |
| AC-CV-10 | Fixed-gear conventional aircraft | AC-21 and GP; tricycle/taildragger, Runway, support geometry, steering, touchdown/reset/replay; test Calmato if its evidence fits |
| AC-CV-11 | Gasoline/glow and additional energy installations | AC-23 plus NITRO/FUEL/EL/BAT; authoring, depletion/mass/CG, audio identity and lifecycle per supported family |
| AC-CV-12 | Elevon/pusher/glider/flap imports | Owning AS/AC capabilities; actual distinct compilers and start/control tests; no fake aft tail or powered glider substitution |
| AC-CV-13 | Expanded layouts and installation research | Explicit separate proposals for biplanes, repeated propulsion, jets, variable geometry, canard/V-tail and retractable gear; no blanket compatibility claim |
| AC-CV-14 | Player guide, support matrix and permitted release | Published tested archive/model identities, known omissions, licenses/credits and export evidence; no redistribution without the applicable rights |

### Verification strategy

Reuse focused `test_creator_import`, `test_creator_glb`, `test_creator_visual`, `test_creator_compiler`, `test_creator_trial`, `test_creator_flight`, `test_creator_store` and `test_creator_flow` coverage as affected. Add tests at the new archive, syntax, mapping and publication boundaries; generate synthetic assets with independently calculated expected coordinates, signs, unit conversions and CRCs. Keep third-party downloads out of the repository/required CI unless their fixture rights are established. A network-optional local corpus campaign records refusal reasons as well as successes.

Follow the [tool index](../tools/README.md), [focused verification scope](../tools/shared.md#verification-scope) and test admission policy. Use checked headless jobs for compatible independent tests; rendered/export/platform evidence has separate gates. For physics changes preserve an `.orfl` baseline, verify exact replay, compare the same input tape, and retain `complete`, `solver_changed`, configuration and backend identities through the [flight-log workflow](../FLIGHT-LOGGING.md). Do not re-record stock goldens to absorb importer work.

Measure import wall time, main-thread stall, cancellation latency, peak process RAM, decoded texture bytes, resulting triangles/draw calls, VRAM and steady/peak 1080p frame time on named target hardware. Freeze measurable thresholds in AC-CV-00/02 after baseline collection, before the production campaign. Keep conversion out of the active flight tick; parse in bounded jobs and create/free GPU resources through the proper rendering path. Apply existing quality settings to presentation without changing physics. Qualify above-1080p afterward; 720p evidence cannot replace 1080p acceptance.

## 8. Ownership, risk and delivery sizing

Proposed owned code: `app/workshop/creator/clearview/`, its schemas under `app/data/creator/`, and `app/tests/test_creator_clearview_*.gd`. Keep offline corpus commands under `research/aircraft-creator/clearview/` if implementation needs them; retain only small textual receipts in `docs/research/aircraft-creator/`. Extend shared Creator files with AC; Home/root/preferences with UI; v2/presentation with AS; sessions/replay with physics/FL; contact with GP/CR; energy with EL/BAT/NITRO/FUEL. No helper owns final architectural or integration acceptance.

| Risk | Mitigation / stop condition |
| --- | --- |
| ZIP and native image decoder resource abuse | Bounded preflight, actual expansion/pixel counters, synthetic hostile campaign and exported-engine testing before release |
| Unsupported geometry or ambiguous references | Deterministic refusal or explicitly limited preview; preserve the source and correction report |
| Attractive visuals conceal false physics | Separate availability levels, complete evidence-bearing authoring, supported domains, numerical and physical gates |
| Existing Creator qualification and Home work grow the scope | Track AC dependencies explicitly; release preview separately; do not call test flight a finished import feature |
| Mixed asset provenance and unclear rights | Per-asset ledger; distribute importer code separately; include only assets with the needed documented permissions |
| Re-import, upgrade or missing visual source changes replay | Immutable revisions and full closure/resolver tests; never regenerate a saved version in place |

Planning ranges, not commitments: **2–3 engineer-weeks** for bounded format/conversion spikes and preview; **3–5 additional engineer-weeks** for source-aware authoring, articulation and one qualified flight configuration; **2–4 additional engineer-weeks** for persistent Home/export/lifecycle integration if the relevant Creator foundations can be completed in that period. Work packages can overlap with clear ownership, but failed numerical qualification, new laws, permission acquisition and target-device access are external to those ranges. Re-estimate after AC-CV-02. Do not promise a date for every aircraft on the website; AC-CV-10…13 are separate capability increments.

The first completion milestone is one identified, permitted and supported aircraft completing **ZIP → original appearance → confirmed controls → qualified OpenRC physics → test flight → saved revision → Home → restart → flight**, on each advertised packaged desktop target, with all unavailable cases still handled safely and clearly.
