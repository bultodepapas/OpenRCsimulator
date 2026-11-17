# Phoenix aircraft import

Status: proposed Creator/Workshop subtrack. Dated evidence and a local package-inspection probe are delivered; no Phoenix runtime importer, decoded aircraft mesh, exported application support or flight qualification is delivered by this plan. This file owns `AC-PX-00` through `AC-PX-09` status and acceptance.

## 1. Goal and decision

Let a user select a Phoenix aircraft package or an installed model folder inside OpenRC, review the aircraft and its available paint schemes, and create an honest Creator draft. Preserve source-authored geometry, appearance and articulated controls where a tested conversion supports them. Offer flight only after the actual configuration passes its applicable numerical and capability gates.

Phoenix deserves a dedicated feasibility track. Direct creator uploads from November 2026 contain readable aircraft definitions and separable geometry/images; the community is still producing models. The remaining critical discovery is a reliable `.geo` decoder and its correspondence with the authored object tree. Container decompression alone does not satisfy that discovery. The [dated research](../research/aircraft-creator/phoenix-2026-11-17.md) and [specimen inventory](../research/aircraft-creator/phoenix-source-inventory-2026-11-17.json) distinguish measured facts from hypotheses.

The intended product flow is automatic. Blender and Phoenix Builder may help developers produce owned reference fixtures, but they are not mandatory end-user dependencies. An author-provided OBJ/MTL export is a separately labeled recovery route for that aircraft; it must not be advertised as general Phoenix package support.

## 2. Baselines and ownership

The current implementation audit is pinned to OpenRC `main` at [`3c91936ab8f9064daa798311b5fb3e89e28d3754`](https://github.com/bultodepapas/OpenRCsimulator/tree/3c91936ab8f9064daa798311b5fb3e89e28d3754). This proposed plan is added to the existing research branch whose preceding head was `59a6da558d2f3b68233ba56b3e5ee50b33a772c6`. That branch does not necessarily contain the audited current-main runtime. Re-audit the then-merged implementation before coding.

[Aircraft Creator](aircraft-creator.md) owns admission, authoring and its numerical gate; [Aircraft Workshop](aircraft-editor.md) owns the host, trial and Store; [the aircraft contract](../AIRCRAFT_CONTRACT.md) and physics owners retain physical capabilities. Coordinate shared work with [ClearView](clearview-aircraft-import.md) and [Flight Simulator](flight-simulator-aircraft-import.md), especially observations, source closure, overrides and lifecycle. Phoenix must not create a parallel authoring system or introduce source-simulator branches into the simulation kernel.

Proposed format-specific code belongs under `app/workshop/creator/phoenix/`; focused runtime tests would use `app/tests/test_creator_phoenix_*.gd`. Research probes belong under `research/aircraft-creator/phoenix/`. Changes to shared schemas, UI, Store, `VehicleModel`, propulsion, gear, energy and replay require their existing owners. No proposal below reassigns those owners or marks their milestones complete.

## 3. Support is recorded by stage

Record support against a content fingerprint, parsed structure and exact specimen, not the `.pkg` extension or a marketing version. At minimum preserve these distinct identifiers: archive wrapper, observed PKG framing profile, PKG header numeric string, model `revision`, `.mod` `formatVersion`, `.mod` `minProgramVersion`, Builder version when evidenced, and source simulator version when actually tested. In the inspected readable examples the PKG numeric string matches model revision; it is not proven to be a container-format version and does not establish Phoenix 7.

| Input or result | Research status | Product acceptance requirement |
| --- | --- | --- |
| ZIP containing one or several PKGs | Recent creator ZIPs inspected locally | Bounded ZIP admission; discover candidates without executing or installing anything; do not import images/sites as aircraft |
| PKG framing and file tree | Seven selected packages decoded by the research probe | A reviewed runtime profile with path, size, count, compression, padding and cancellation rules; no universal compatibility claim |
| Readable `.mod` | Six selected definitions inspected | Non-evaluating grammar, exact spans and validated object/dependency references; unresolved semantics stay observations |
| Binary `.geo` | Extractable members; full mesh decoding unproven | Independently checked vertices, indices, UVs, transforms, object identity and materials before a visual-support claim |
| PNG/BMP/JPEG/TGA and `#` scheme files | Mixed types and scheme associations observed | Content inspection, explicit decoder profiles, per-image and total budgets; retain alpha and scheme dependencies |
| Installed model directory | Author catalog offers folders; package paths show model roots | User-selected scope, bounded capture, symlink/path rules, deterministic dependency resolution and immutable snapshots |
| Standalone `.phx`, `.var`, `.pxm`, `.fly`, `.sim` | One PHX decompressed but not indexed; one public VAR refers to a base model; other forms unqualified | Separate specimens and versioned readers; do not infer the PKG grammar from a suffix or treat a variant as a full aircraft |
| Original `.obj` / `.mtl` / textures | OBJ import and separately linked textures documented; MTL is a prospective author-export dependency, not established Builder support | Authorized complete closure and its own geometry import profile; retain missing physics/pivot status |
| OpenRC preview / draft | Proposed | Converted GLB passes Creator admission; clear capability and omission report |
| Experimental flight / calibrated aircraft | Not established | Exact candidate passes current numerical/capability gates; physical calibration uses independent evidence |

Every unsupported or malformed input returns a concrete diagnostic and retains the user's source unchanged. The compatibility matrix must not silently promote an inspected package to visual support or a visual preview to flyable status.

## 4. Proposed pipeline and contracts

### 4.1 Capture and package closure

Capture selected bytes once, hash them and inspect the captured copy. Never reopen a mutable source after approval and assume it is the same input. Directory import needs a bounded, explicit root and a receipt identifying every captured member, any changed/missing member and the chosen resolution policy.

An outer ZIP and an inner PKG are distinct layers. Reuse the existing checked ZIP primitives only after extracting/versioning their generic policy with the ClearView owner. Phoenix PKGs observed in this research use framed zlib blocks and a separate file-tree serialization; they are not ZIP archives. Implement that reader in the Phoenix provider, with little-endian reads, checked arithmetic, bounded recursion and exact input consumption. Treat observed zero padding as a narrowly defined profile rule, not permission to ignore arbitrary trailing bytes.

The source tree contains install paths and author-local source strings. Preserve the original strings as evidence, but never use them as output paths. Resolve allowed relative member identities inside a virtual package root; reject traversal, absolute/drive/UNC names, NUL, path collisions, ambiguous case/Unicode aliases and escapes. Do not strip directories until two different files become indistinguishable. Author-local source strings are not dependencies and must not be followed or included unredacted in public reports by default.

A discovery result distinguishes a complete model, a definition-only variant, an alternate paint scheme, an image preview, a sound reference and a flying site. A candidate binds the selected definition and geometry, requested scheme and actual dependency closure. The matching Wasps' PNG hashes are an opportunity for byte deduplication, not grounds to merge their different aircraft/configurations.

Proposed first-profile ceilings can start from reviewed existing admission limits: 64 MiB captured archive, 256 MiB aggregate expansion, 32 MiB per member, 4,096 entries and 512-character normalized names. These are proposed limits, not measured Phoenix performance. Bound all nested layers against one total budget; separately bound native decoder workspace, tree depth, compression ratio policy, strings, tokens, output bytes and elapsed work. A larger source needs a diagnosed limit result or a later measured profile, never a silent policy increase.

### 4.2 Static definition parser

Readable `.mod` files resemble Lua assignments such as `modelTypes.<identifier> = { ... }`, including symbol references such as `physics.airplane`. Parse a deliberately restricted data grammar; do not call Lua, `eval`, load libraries or execute package code. Recognize only evidenced literals, tables, comments and allowlisted symbolic values. Preserve key spelling, ordering, source spans and original numeric lexemes; reject duplicate/conflicting keys, unbounded nesting, non-finite values and unsupported expressions with a useful location.

Create a format-specific source representation before any OpenRC mapping. It should retain header identities; physical declarations; airfoils and their separate aerodynamic geometry; surface hinges, inputs, sides and travel; propulsion declarations; gear/wheels; collision descriptors; widgets; tuning, mixes and external names. Geometry lists are exact object references. `ELEBATOR_LEFT...` in one sample demonstrates why guessed English names are not reliable identities.

Do not infer that the `Engine` label is a physical engine specification: the tutorial uses that field to choose an engine sound. Do not import Phoenix `Inertia`, tuning percentages, stall knobs or a NACA label as an OpenRC inertia tensor or aerodynamic polar. Keep unsupported values available in the report. Missing airfoil/sound libraries are explicit dependencies with separate necessity: a missing sound can be optional for a static preview; missing geometry cannot.

### 4.3 Geometry: the feasibility gate

First establish a bounded `.geo` reader on independently known source/export pairs. A publishable fixture should be owned or explicitly licensed: a triangle with known winding/normal/UV, an asymmetric three-axis object, two differently textured objects, a nested/nonidentity transform and one rigid hinged control. Obtain exports from the specific Builder generation under a legitimate developer setup and retain the source, settings and expected measurements. A second author/version is needed before generalizing beyond one workflow.

The decoder must consume validated record boundaries. A string scan, recognizable object name, plausible float array or package-level success is insufficient. Compare exact topology or documented exporter changes, bounds, orientation, material slots, UV seams, transform composition and object references against independent known answers. Unknown record classes, non-finite coordinates, bad indices, cycles or ambiguous objects must fail the affected stage.

Emit only Creator's supported self-contained GLB subset and pass generated bytes back through `source_importer.gd.inspect_bytes`. Preserve source-to-output object IDs in a versioned conversion receipt. Treat conversion identity and qualification identity separately. `.geo` decoding remains the first technical stop condition: until it passes, ship research or a package inspection report, not an operational aircraft-import claim.

### 4.4 Scale, frames and dimensions

The author tutorial uses a 100-unit visual span and a separate Builder size control. Actual definitions mix position/pivot values near 50 with wing lengths/chords around one or less. These observations do not justify applying a single unit multiplier to every numeric field. Build a typed field map with candidate categories for normalized visual coordinates, dimensional quantities, angles, ratios and tuning factors; retain unresolved units until each interpretation is established.

The observed author workflow suggests a Builder frame with +X left, +Y up and +Z forward. That remains an example-derived hypothesis until the known-answer fixtures establish the binary/export frame. Do not apply Blender's exporter settings twice to already exported geometry. Record source frame, visual GLB frame and aircraft body frame separately, including handedness, winding/normal treatment and all pivot transforms.

The possible `Size / 100` relationship for normalized visual coordinates must be tested rather than adopted by name. Verify total span, root/tip distances, prop diameter, CG and control pivots on the same source configuration. Geometry, aerodynamic surfaces and collisions may have different semantics. Current Creator placement edits and user corrections need their own provenance and invalidate dependent qualification where appropriate.

### 4.5 Images, schemes and materials

Use the actual file signature and decoder result, not its extension. An official BMP-named member in the comparison sample does not contain an admitted standard BMP. An image prefix search inside a geometry file is not an embedded-image parser.

Inspect alpha, color interpretation, UV orientation, wrap modes, materials and references. The Extra contains both `#` scheme images and corresponding thumbnails; a thumbnail is not the aircraft's diffuse map. Preserve base aircraft plus scheme selection rather than counting each paint as a new full aircraft. Support PNG first if the geometry proof permits it, then expand bounded BMP/JPEG/TGA profiles using representative fixtures. Creator's current image code does not supply TGA or DDS support automatically. Do not fetch missing dependencies from arbitrary package URLs.

### 4.6 Articulation and controls

Use source-defined `root_pivot`, `tip_pivot`, inputs, side membership, travel, neutral transforms and mirroring. A hinge axis is derived from two endpoints only after their common frame and units are established. Validate finite nonzero axes, neutral/end poses, sign, handedness, duplicate references and shared/overlapping geometry. Do not assume the signs or endpoint meanings of two positive min/max values; establish source behavior with independent endpoint fixtures.

Creator binding v1 currently supports conventional ailerons, elevator, rudder and one propeller with cardinal local axes and limited part counts. Source hinges can be arbitrary. A future adapter may create a validated parent frame that aligns the binding axis and preserves geometry/neutral pose; alternatively a versioned binding extension may be needed. Neither is delivered here. Rig construction must not flatten or silently discard source structure to fit the old schema.

Flaps, retracts, doors, multiple propellers, mixing and moving nozzles require their actual source semantics and their owning presentation/physical capabilities. A static visual fallback is acceptable when labeled. A moving rendered nozzle does not establish a physical thrust vector; one logical elevator animating two parts does not establish two independent servo/force laws.

### 4.7 Observations, provenance and user edits

Create a closed, versioned Phoenix observation provider. Do not put Phoenix data into `openrc_clearview` or relax its existing v1 validators. Each observation binds source package and member hashes, selected candidate/scheme, source key and byte/line location, original value/unit, interpreted value/unit if established, conversion profile, evidence class, conflicts and any user override. Distinguish captured member integrity from an unverified externally declared association. A hash identifies bytes; it proves neither authorship nor physical truth.

Initial observations are read-only. Adopting a source value into an editable aircraft requires coordinated Definition, Compiler, UI, source installation, Store and resolver changes preserving field-level evidence. Keep the current `{value, unit, kind, source}` quantity contract closed; do not append undocumented properties. Separate source-authored, inferred, independently estimated, user-entered and measured facts. Unknown source data must not be promoted to measured or calibrated status.

### 4.8 Trial guards and lifecycle

A provider-specific source/config association and flight guard must exist before exposing the route. Cover trial creation, verification, publication and saved-source resolution. Current ClearView guards recognize their namespace; a Phoenix label does not inherit them. Exact visual, source/report and configuration identities must be checked again on reopen. Do not enable flight by stripping provider metadata or silently substituting an independently estimated trainer.

Also prove the semantic relationship between saved authoring and physical data. Regenerate the stored physical bytes using the pinned compiler, packages and conversion profile, or provide an equivalently strong reviewed proof. Independently valid hashes or a forgeable compile-binding association do not prove that a definition produced its paired physical record. Refuse a mixed definition-A/physical-record-B pair even when an attacker recomputes their association hashes. Compiler/profile changes require explicit migration and renewed acceptance where needed; reuse the same shared requirement as AC-FS rather than adding a weaker Phoenix-only shortcut.

Current Store holds one source model of at most 32 MiB per draft/revision. It does not retain a complete Phoenix archive plus extracted files and derived GLB. Coordinate content-addressed source closure with AC-CV-07, AC-FS-02/10 and AC-13/18/19. Store original closure and normalized visual as separate immutable identities, enforce quota/garbage-collection rules, preserve rights metadata and support missing/corrupt-source recovery. Until then, say that originals remain external; a saved visual draft is not a source backup.

Reopen/replay/export acceptance must identify the exact aircraft revision, overrides, converter profile and source closure. Store's current recovery promise concerns interrupted processes, not power loss. Platform locking, export and clean-profile behavior require their existing qualification gates.

## 5. Flight scope and the SU-35

The initial source corpus should include a simple conventional electric aircraft that fits Creator's actual compile domain, plus examples deliberately outside it. The Extra is labeled `Gasser` and has gear declarations; the Queen Wasp has biplane/flap declarations and an amphibious version. Their availability does not make them eligible for the current conventional aft-tail, single tractor-electric, finite-battery, gearless Creator compiler. They are valuable visual/diagnostic cases. Do not change their identity by dropping features and call the result faithful.

The author's released Freewing SU-35 v23 was obtained and inspected. Its `.mod` has two entries named `EDF LEFT` / `EDF RIGHT` with Phoenix `type = "turbine"`, control-surface declarations and retractable nose/main gear, nose linkage and doors. That source type is not a validated mapping to OpenRC's single centerline turbine physics. Thrust vectoring and runtime behavior were not established. The release is connected through the author's original/moved build log, but its earlier date does not prove every later screenshot change is present. The separate Su-37 remains an independent fixture. These OpenRC boundaries apply:

- The audited physical contract supports single tractor/pusher propeller or single centerline turbine installations; multiple propulsion units and EDF duct/fan momentum are outside active v2. Multi-EDF work needs propulsion/energy owners and an explicit validated physical model, not a single-turbine substitution.
- Dynamic thrust vectoring needs nozzle axes/travel/rates, actuator/mixer behavior, force direction and moment arms, visual coupling, state/reset/checkpoint/log/replay support and suitable tests. Existing fixed thrust angles do not establish that capability.
- The broader runtime already has retractable gear laws and an F4U visual rig. Creator authoring/import binding and this aircraft's own gear/contact configuration still need AC-21/25 and owner validation. Do not describe retracts as wholly absent from OpenRC.
- Surface arrangements, mixing, channels and source-assigned features must be read from the actual file. Model appearance alone does not prove they are configured or physically effective.

Numerical acceptance is still owned by G05/AC-12 or an explicitly reviewed separate domain. Preserve failed campaign results; a revised scope requires its own preregistered criteria and evidence. A valid v2 compile or trim solution is not a passed campaign. Matching Phoenix is a separately specified comparison; calibrated RC fidelity requires independent measurements and held-out validation.

## 6. User flow

1. **Choose files.** Accept one package/ZIP or an explicitly selected installed folder. Capture and show aircraft candidates, source author/version when evidenced, completeness and supported stages.
2. **Review appearance.** After geometry admission, show the aircraft and available schemes at 1080p-first quality, with optional scalable rendering. Unsupported/missing geometry produces a concrete report instead of a misleading preview.
3. **Review moving parts.** Display source-based proposals and omissions. Users can inspect neutral/end poses and correct bindings without editing a text file.
4. **Review aircraft data.** Show established units and provenance alongside unresolved values and unsupported capabilities. Ask only questions that materially resolve a missing field; retain previous answers and permit later edits.
5. **Save or continue to qualification.** Save a truthful visual/editable draft. Offer a numerical-ready experimental candidate only when its actual domain and all relevant guards permit it. A qualified aircraft is a separate state, never a side effect of importing successfully.

Keep technical offsets and parse diagnostics in a detailed report. The normal UI should explain what was imported, what still needs input and which actions are available. Preserve the selected aircraft and edits across recoverable errors; cancellation must leave no partially published record.

## 7. Work packages and acceptance

| Step | Owner / dependencies | Deliverable and decisive acceptance | Status |
| --- | --- | --- | --- |
| AC-PX-00 — Evidence corpus | AC; rights/source owners | Pinned sources, stage matrix, original fixture plan and rights ledger; at least two creator workflows and an unsupported case; correct revision semantics | Initial research recorded; corpus/permission qualification open |
| AC-PX-01 — Capture and container | AC; generic archive owner | Safe captured input, bounded ZIP/PKG/tree profile, complete member receipts, deterministic candidate selection; adversarial/truncation/cancellation cases | Proposed/open; research probe only |
| AC-PX-02 — Definition observations | AC; AC-CV-05 / AC-FS observations | Restricted non-executing `.mod` parser, exact references/locations and schema-versioned read-only observations; unknown expressions and missing libraries diagnosed | Proposed/open |
| AC-PX-03 — Geometry feasibility | AC; geometry owners | Owned known-answer exports decoded; independently verified object/topology/frame/material mapping; admitted generated GLB and exact scope | Proposed/open; critical feasibility gate |
| AC-PX-04 — Appearance and schemes | AC; image/skin owners; PX-03 | Bounded image/material profiles, correct scheme selection/alpha/UVs, missing/opaque image handling; no thumbnails used as diffuse maps | Proposed/open |
| AC-PX-05 — Articulation | AC-17 / presentation; PX-02/03 | Neutral/endpoint/sign/mirror proof; stable source-to-output IDs; arbitrary pivots handled by an approved binding strategy; explicit unsupported roles | Proposed/open |
| AC-PX-06 — Creator integration | AC/AE/UI; PX-01…05 | Automatic in-app route, source/config receipts, proven definition-to-physical compilation, field-level overrides, all trial/verify/publish/resolver guards, truthful states and recovery | Proposed/open |
| AC-PX-07 — Flight eligibility | Physics/AS/energy/GP; Creator gates | Exact supported candidate and backend pass the applicable numerical/capability gates; separate owner plans for additional source configurations | Proposed/open; no Phoenix flight qualification |
| AC-PX-08 — Source retention | AE/AC-CV-07 / AC-FS-02/10; AC-13/18/19 | Immutable original closure plus derived visual, quota/recovery, exact saved revision, semantic-pair revalidation and missing-source behavior; rights-aware export | Proposed/open |
| AC-PX-09 — Desktop release | AC/AE/UI/platform owners; preceding gates | Clean exported Windows/Linux/macOS profiles, reopen and supported flight lifecycle, bounded CPU/RAM/VRAM/time/cancel latency, 1080p-first evidence and accurate support matrix | Proposed/open |

Do not schedule broad UI/flight work on the assumption that PX-03 is solved. PX-01/02 can produce useful inspection output while geometry research proceeds. Once geometry succeeds, finish one narrow visual path and its guard/storage behavior before expanding source versions or aircraft classes. Additional mechanisms enter existing capability tracks, not a growing importer-specific flight engine.

## 8. Verification and stop conditions

Parser qualification needs owned adversarial fixtures: count/length overflow, truncated zlib streams, declared-size mismatch, unused compressed bytes, tree-depth overflow, path aliases/traversal, duplicate model roots, malformed text/expressions, missing references and opaque protected-looking members. Test aggregate limits across nested wrappers. The delivered research probe is read-only and bounded but is not this production security/cancellation qualification.

Visual qualification needs an independent source/export oracle for geometry, transforms, object IDs, material references, UVs and selected schemes. Motion checks compare neutral and both endpoints, including asymmetric travel and mirrored parts. Physics checks belong to the exact authored configuration and must distinguish source agreement, numerical stability and measured physical validity. Resource checks must use actual exported runtimes; a small package size does not predict decoded geometry/image memory.

Stop the relevant stage on unknown encoding, ambiguous identity, missing mandatory dependencies, unsupported expression, inconsistent units/frame or failed numerical gate. Retain a useful report and already admissible draft stages. Public availability and vendor discontinuation do not establish rights to redistribute models, derivative assets or included third-party components. Keep inspected third-party binaries out of this repository until permission is evidenced; public test fixtures should be original or expressly licensed.

Before implementation, verify the then-current main interfaces, ownership registry and prerequisite gates. Before release, prove every advertised stage on its listed specimen/profile and update this status table with exact evidence. Do not claim support for thousands of aircraft from a handful of samples, forum page counts or a collection of paint schemes.
