# Aircraft Workshop

The Workbench feature is named **Aircraft Workshop** in the application (**Taller de aviones** in Spanish). It creates experimental local variants without changing shipped aircraft data. Open it from Home or Pause.

| Need | Authoritative home |
| --- | --- |
| Use the editor; understand supported adjustments, scaling and saved variants | This guide, checked against source on 2026-10-19 |
| Develop the feature; find pending steps and acceptance gates | [Consolidated AE plan](plans/aircraft-editor.md) |
| Explore current customization and the remaining Workbench backlog | [Workbench backlog](plans/aircraft-editor.md#5-planned-player-facing-work) |
| Implement the next slice; find dependencies, contracts and tests | [Ordered work packages](plans/aircraft-editor.md#56-implementation-packages-and-order) and [required test matrix](plans/aircraft-editor.md#57-required-test-matrix) |
| Design the menus, editing flow and model inspection | [Interface contract and remaining gates](plans/aircraft-editor.md#59-menus-workflow-and-visual-design) |
| Author physical data, stable IDs and model manifests | [Aircraft contract](AIRCRAFT_CONTRACT.md#workshop-authoring-standard) |
| Generate descriptors, run checks or capture the editor | [Workshop commands](TOOLS.md#aircraft-workshop) |
| Inspect dated results and limitations | [Verification and evidence](#verification) |

## Using the Workshop

1. Open **Library**, browse stock aircraft or search saved builds, and use **Favorites only** or the favorite toggle to find saved variants. Favorites are metadata separate from immutable build revisions. Unavailable favorites stay removable under **Favorites only**, so missing files cannot permanently fill the 256-item limit. Browsing leaves the current draft unchanged; opening remains explicit.
2. Use **Appearance** for registered solid-color regions and short aircraft markings, and **Smoke** for supported show/source endpoints and presets. **More options** exposes color steps and emission timing. Both pages participate in the same Undo/Redo history as physical edits. Apply or cancel pending color/inscription text before changing its target.
3. Use **Flight setup** for presets, size, mass, tank capacity, power and control travel. Sliders and numeric fields share the accepted bounds. Invalid text remains visible, blocks Save/Test fly, and can be corrected or cancelled with Back. **Review issues** focuses the blocking field.
4. Use **Compare** for changed values in Original / Draft / Difference columns; **All values** and **Technical details** add context. These are static estimates, not measured flight performance.
5. Choose **Save build** and provide a name, or **Save a copy** in Library. Repeated saves create immutable revisions. Loading restores exact saved inputs. Delete captures the selected UUID/revision; **Undo delete** restores that exact trash generation during this editor visit. Deleting the loaded record preserves its draft as a new unsaved build.
6. Choose **Test fly** without requiring Save. Review the inherited field, wind, lighting, full-fuel, normal-rate and current-controller summary, then choose a start that the frozen aircraft, field and weather qualify; supported starts include Airborne and some runway configurations. Pause offers **Resume trial** and one direct **Return to Workshop** action. Return restores the same draft, history, page, camera, scroll and focused action. A retained original flight stays paused. Preparation failure preserves it; restored audio buses restart continuous sound with a fade.

When copying an appearance/smoke profile, review the compatible and skipped settings by name before applying. Copying requires matching registered material kinds and smoke endpoint identities/roles, enforces each marking's fixed glyph limit, preserves target settings the source does not touch, and adds one Undo entry without changing the physical recipe. Cancel leaves the draft unchanged. A stale pinned profile is refused for review rather than silently rebased.

The independent preview offers Inspect auto-fit, Compare size with a shared world scale, original/draft switching, Front/Side/Top, orbit, zoom and Reset. The aircraft stays stationary during appearance/smoke playback; an isolated 240 Hz smoke clock and wind drive Play, Pause and Restart without advancing a flight or carrying preview conditions into Test fly. Source preview is labeled illustrative. There is no moving maneuver pass, scrubber or smoke-specific auto-framing yet. The grid spacing is 0.5 m. It requests redraws only after changes. The editor uses one scrolling inspector and an on-demand, scrolling library. Compact layouts provide a page selector and View/Edit; inspection expands the model area while keeping Edit and Save/Test fly reachable. A very short preview reports its inspection limit and exposes camera actions in a menu. English/Spanish and shared text scaling are supported; the [native evidence](research/aircraft-editor/AE-08b-09/README.md) states the physical inspection scope, and [AE-24 evidence](research/aircraft-editor/AE-24/README.md) records the appearance/smoke captures and lifecycle probe.

Back first cancels the active dialog or uncommitted number, then leaves compact inspection. Abandoning a changed draft offers **Save and continue**, **Discard changes**, or **Cancel**, with Cancel focused. The comparison includes exact source and dependency pins as well as recipe/name; camera/page changes do not mark a build dirty. Source changes, close, quit and window close use the same guard, including the detached editor during a trial. Window close first dismisses an active editor popup; it cannot stack an exit prompt over it. Save failure retains the draft and captured destination.

The normal Home/Pause application keeps one recovery snapshot after 750 ms without an edit. It preserves the accepted recipe/profile separately from pending numeric, color and inscription text, plus name/page/camera; it never creates a library revision. Reopening offers **Restore as a new build**, **Later**, or **Discard recovered draft**. Later preserves the old snapshot and pauses automatic replacement until that recovery is resolved; reopen it from Library. Restore detaches saved ancestry and revalidates the draft; invalid fields still block Save/Test fly. Stale pins and unavailable selections remain readable and cannot silently rebind or replace the snapshot. Each session pins the exact recovery bytes it reviewed or wrote; a concurrent change refuses save, restore or discard and requires renewed review. A completed named save or explicit draft discard clears recovery only if that identity still matches. The last debounce interval, unsent fields inside the measurement dialog and prior Undo history are not recovered. Tests/tools must opt in with isolated roots.

Selecting a saved build in Library requests a separate static thumbnail. Its temporary world cannot change the active preview, camera or build. The copied-pixel LRU retains at most 16 images / 4 MiB; selection changes and closing Library cancel pending renders and clear the old image. A missing thumbnail leaves the build's normal actions available. These cache limits do not measure total GPU memory; see [thumbnail evidence](research/aircraft-editor/AE-24d-1/README.md).

If saving a manual trace fails during Return/Quit, recording has stopped. **Stay**, **Retry save**, and **Discard trace and continue** are explicit choices; a second exit request cannot imply discard. Trial and retained-flight outcomes are tracked separately. This recovery does not change streaming `.orfl` completeness rules.

**Reset this page**, Undo and Redo cover physical recipe, appearance and smoke profile edits in one history; history retains up to 32 entries. One slider drag or preset is one edit; a new edit clears Redo. Loading or replacing the source starts a new history. Undo marks the draft clean only when its full saved payload matches the baseline.

## Supported adjustments

| Parameter | Current range or choices | Meaning |
| --- | --- | --- |
| Size | 50%, 75%, 100%, 125%, 150%, 200% | Uniform physical and visual scale |
| Mass scaling | Constant wing loading; geometric | Scale dry inventory mass with area or volume, before applying the weight multiplier |
| Weight | 0.50–2.00× | Multiplies dry inventory mass; declared tank liquid follows tank scaling |
| Tank capacity | 0.50–2.00× | Compiler sizing proposal for validated tanks; trial mass/fill integration remains under verification |
| Power | 0.50–2.00× | Virtual prescribed-RPM propeller static-power multiplier after size/mass scaling |
| Control travel | 0.50–1.50× | Surface throw limits; does not change transmitter expo or servo speed |
| Measured component mass | 0.001–5 kg per eligible existing inventory ID; at most 32 entries | Original stations and geometry; measurement source required; complete aircraft validation still applies |

The six size choices are shortcuts. Loaded recipes may contain intermediate sizes within 50–200%; the editor adds their exact size to the selector and preserves their numeric multipliers instead of rounding them to the nearest shortcut or slider step. Invalid recipe inputs are refused before replacing the current draft.

Presets are Mini, Giant, Light, Heavy, More power, More travel and Light / low power. They apply only supported adjustments. Their names describe changes rather than measured flight performance. Valid slider values can still form an invalid combination: normal aircraft, trim and timestep checks remain authoritative.

The catalog has eight airplane configurations; the Workshop filters out the separate rotorcraft entry. Size, dry-weight and virtual-power transforms require the simple prescribed-RPM capability, currently provided by the baseline Stik. Extra now uses a finite-glow installation, so it keeps those transforms disabled like the three finite-glow Stiks. Tank capacity is a separate operation for classified aircraft with validated tanks; conventional control travel follows the registered surface capability. Runway availability is qualified from the frozen candidate through the real session with the selected field and weather; it does not use an aircraft-ID allowlist. The compiler contains no aircraft-ID transformation branches.

Runway qualification currently succeeds for all eight default fixed-wing configurations. The Stik at 150% and 200% is refused for runway starts while remaining available airborne. These are software start-qualification results, not physical-flight acceptance; half-power airborne starts are not currently available in the Workshop.

Presentation bindings cover five authored visual families. Solid paint regions and source/show smoke endpoints are model-authored; short EN/ES registration text is registered for the Stik, Extra 300S and Timber. The current paint controls are solid fills; no broad whole-model repaint is inferred from a family name. The v2 customization companion pins its seven presentation source files and Godot 4.7.2 through a separate presentation proof package, leaving physical model-manifest identity independent of cosmetic source changes. Smoke profiles support up to eight palette colors, up to eight seconds for relevant duration/lifetime controls, and a total 768-particle profile-renderer allocation; these are implementation bounds, not measured performance guarantees.

The current generated visual coverage is exact and intentionally limited:

| Visual family | Solid paint regions | Registration | Smoke endpoints |
| --- | --- | --- | --- |
| `jensen-das-ugly-stik-60` | body, wing, wing_tip, tail | Yes | paired show wing tips, show tail, physical source exhaust |
| `gp-extra-300s-60` | body, wing, wing_tip, tail | Yes | paired show wing tips, show tail |
| `p51d-mustang-120` | body, wing, wing_tip, tail | No | paired show wing tips, show tail, physical source exhaust |
| `sebart-avanti-s-a200-p100rx` | body, wing, tail | No | paired show wing tips, show tail |
| `turbo-lumber-evolution` | body, wing, wing_tip, tail | Yes | paired show wing tips, show tail |

These are visual-family bindings, not a claim that all eight fixed-wing catalog configurations have separate authored families. Slots absent from a family's generated companion are unavailable.

Descriptor freshness is a separate launch gate. The [interface verification](research/aircraft-editor/AE-08b-09/README.md) reruns the generators and focused suites against the current fixtures. Earlier compiler/legacy-trial failures remain in their dated diagnostic report; passing software checks do not establish fleet acceptance. Fuel software and physical acceptance stay with the [fuel-mass plan](plans/fuel-mass-balance.md).

These changes retain estimated aerodynamic coefficients and do not model Reynolds-number changes or certify a real miniature/giant aircraft. Component moves/ballast mounts, editable hardware packages, wider validated ranges, full-fleet conformance and physical aircraft acceptance remain planned. Bounded offline experiments and strict data-only variant bundles now have software paths, but neither establishes measured aircraft performance or full cross-platform package acceptance.

### Measured mass and CG

**Flight setup → Measured components** records a measured mass and its source for an eligible existing component. Add/update measurements, inspect the complete candidate, then **Apply to a new build**. This is one Undo edit. Applying measured edits to a saved build creates a new draft and preserves the saved original. Keep scale, weight and tank-capacity multipliers at 1.0. Source-marked virtual reference masses and fuel/line liquid are unavailable. No mount envelope is authored yet, so positions, new ballast and hardware replacements cannot be edited.

The comparison uses the source-declared weighing state, including empty tanks where declared, and CG coordinates in metres from the LE datum: x aft, y right, z up. It reports total-mass and three-axis CG residuals. The one-component fixed-station solve is a **derived proposal only**; it cannot be applied as a component measurement. Impossible/negative solutions and changes outside authored balance tolerances reject. The loader recomputes full inertia; O-relative thrust/intake offsets are re-referenced so their structural points stay fixed. Authored plan CG, fuel state and geometry stay unchanged. Reference chord remains distinct from MAC. [AE-12/13 evidence](research/aircraft-editor/AE-12-13/README.md) records the arithmetic, compiler/persistence and UI scope.

The Workshop reads each catalog entry's main `data` source. Timber trials therefore use its fixed-voltage configuration; ordinary flights default to the separate finite 4S pack. The Workshop has no battery-mode selector. Physical editing transforms and module coverage remain incomplete. Portable bundles carry strict JSON data, exact base bytes and pins; the CLI read-only launch does not load bundle-selected resource paths or replay arbitrary external dependencies.

The bounded experiment evaluator supports static reports, fixed-tick input-tape runs and offline sweeps/discovery. Sweep evaluation is limited to four axes, eight values per axis and 32 candidates; fixed-tape runs are bounded to 28,800 ticks (120 seconds at 240 Hz). These are deterministic software-simulation tools, not measurements of a real airplane. The source-only analysis CLI is available; see the [Workshop commands](TOOLS.md#aircraft-workshop) for its read-only input and new-output rules.

## Common implementation and authoring interface

| Source | Responsibility |
| --- | --- |
| `app/workshop/parameters.gd` | Closed recipe keys, bounds and defaults |
| `app/workshop/compiler.gd` | Detached, capability-gated transforms, validator and before/after summary |
| `app/workshop/descriptor.gd` | Generated descriptor validation and source/binding checks |
| `app/workshop/dependencies.gd` | Wheel/glow dependency discovery and exact-byte hash verification |
| `app/workshop/store.gd` | UUID library, immutable revisions, atomic index replacement/recovery and trash |
| `app/workshop/draft_store.gd` | Bounded detached recovery snapshot, raw editor buffers, locked temp/readback/backup and explicit discard |
| `app/workshop/mass_edit.gd`, `app/ui/workshop_mass.gd` | Stable-ID measured mass editing, source-state mass/CG checks and proposal-only inverse solve |
| `app/workshop/thumbnail_cache.gd`, `app/ui/workshop_thumbnail.gd` | Copied-pixel LRU and cancellable isolated still renderer |
| `app/workshop/presentation.gd`, `app/render/aircraft_customization.gd` | Versioned presentation profile, authored paint/marking/smoke bindings and per-instance application |
| `app/render/presentation_sources.gd` | Separate proof package for pinned presentation source files and engine version |
| `app/workshop/trial.gd` | Canonical physical identity and frozen accepted trial inputs |
| `app/workshop/start_qualification.gd` | Runway/airborne availability from the actual frozen candidate, field and weather |
| `app/workshop/bundle.gd`, `launch.gd` | Strict data-only bundle validation and read-only `--aircraft-variant` launch |
| `app/workshop/experiments.gd` | Bounded deterministic offline experiment and sweep evaluation |
| `app/ui/workshop.gd`, `workshop_preview.gd`, `workshop_customization.gd` | Common editor, isolated playback preview and appearance/smoke pages |
| `research/aircraft-editor/run_experiment.gd` | Source-only local-file CLI for a catalog aircraft or bundle with optional recipe/sweep input and a new report file |
| `research/aircraft-editor/build_descriptors.py` | Catalog-discovered descriptor generator |

After adding or regenerating an aircraft through its owning pipeline, follow the [descriptor generation and verification sequence](TOOLS.md#aircraft-workshop). Resolve unsupported module classifications before generation; do not edit the generated descriptor to bypass a refusal.

Include the generated `app/data/workshop/<catalog-id>.json` with its source change. Identified sources use v3 ID bindings; historical descriptors retain explicit versioned readers. Exact source and model-manifest pins require regeneration after input changes, even when component IDs survive. The [Workshop authoring contract](AIRCRAFT_CONTRACT.md#workshop-authoring-standard) owns those schema/binding rules; the [model contract](AIRCRAFT_CONTRACT.md#model-and-package-contract) owns presentation manifests. Saved records are not automatically rebased.

The v1 descriptor reader remains explicit for saved variants. Structural validation never resolves current model dependencies, so an unavailable/changed model cannot hide a saved record. Trial preparation verifies the current dependencies and passes its accepted model hash to the renderer; a replacement between freezing and building is rejected. The library record stays unchanged.

Adding an aircraft with existing supported capabilities requires catalog/data/assets, a generated descriptor and conformance evidence. It does not require a new Workshop screen or transformation branch. A new propulsion law requires a shared capability implementation and its tests. Descriptor generation does not automatically qualify that law for editing.

### Scale policy

For size `s`, weight multiplier `w`, and tank-capacity multiplier `c`, the compiler uses dry-mass ratio `r_dry = s²w` under constant wing loading or `s³w` under geometric scaling. Its tank transform multiplies declared liquid mass, capacity, unusable volume and reserve by `s³c` and box dimensions by `s·c^(1/3)`, intending to preserve density and fill. The latest compiler suite still rejects a finite-glow capacity-only estimate on dry-carrier mass properties; these equations describe the compiler policy, not a qualified transform envelope.

Other positions scale by `s`. Proposed total mass ratio is `r_total = (M_dry·r_dry + M_liquid·s³c)/(M_dry + M_liquid)`. The compiler re-derives inertia from inventory and the loader rechecks CG at the declared fuel state; mixed dry/tank scaling can shift CG or invalidate a candidate. Declared start speed uses `sqrt(r_total)/s`; suspension uses `r_total`. The real session must still accept trim, timestep and start checks.

The virtual legacy propeller uses the dry ratio: diameter scales by `s`, rotating inertia by `r_dry s²`, maximum RPM by `sqrt(r_dry)/s² × power^(1/3)`, and idle RPM by `sqrt(r_dry)/s²`. The static coefficient-law result therefore scales thrust by `r_dry × power^(2/3)` and power by `r_dry^(3/2)/s × power`. This is a virtual propeller policy, not a substituted physical engine specification.

Virtual suspension uses `a=max(s,1)`: spring stiffness scales by `r_total/a`, damping by `r_total/sqrt(a)`, and travel by `a`. This preserves the small-model suspension timescale instead of shrinking travel with geometry. Contact positions, hull, wheel radius and wheel mass/inertia parameters follow their own transforms. Inherited wheel profiles retain their applied status so variant IDs do not disable wheel dynamics. Runway qualification remains AE-11.

Without declared tank liquid, `r_total=r_dry`: CG/reference-chord ratio stays fixed and the full inertia tensor scales by `r_dry s²`. These are project similarity assumptions. The original policy rationale cites [NASA similarity parameters](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/similarity-parameters/) and [UIUC propeller coefficient conventions](https://m-selig.ae.illinois.edu/props/propDB.html) (accessed 2026-10-13); neither validates resized aircraft or hardware. Normal trim and solver checks still apply to each candidate.

### Persistence and identity

Variants live under Godot's `user://aircraft_variants/`. New records use `format: openrc-aircraft-variant` and `version: 2`; they store exact base bytes, physical recipe, presentation profile v1, descriptor, dependency hashes, compiler version, UUID, display name and revision. The explicit v1 reader supplies legacy presentation defaults without rewriting old records. The original resource bytes are never overwritten. Saves normalize numeric values to their JSON round-trip representation before hashing; caller dictionaries and existing revisions remain unchanged.

Trials normalize omitted recipe defaults and numeric representation (`1` and `1.0` have the same identity), validate metadata before hashing, and exclude cosmetic names from physical identity. Presentation has a separate canonical identity bound to the visual family, physical model-manifest hash, customization companion hash, presentation dependencies, seed and schedule policy. Conflicting recipe/record ancestry is refused. The editor keeps physical recipe values separate from the saved record name and ID, including when loading historical records that duplicate them inside the recipe. The physical fingerprint binds source, physical recipe, descriptor, resolved visual family/model-manifest hash, physical dependencies and compiler, including when a legacy descriptor supplies the visual binding. Trace metadata also records the ancestor variant/revision and exact resolved-input/model hashes. Saved ancestry requires an explicit descriptor, dependency and compiler pin plus a positive integer revision. Flight restart/reload uses the frozen in-memory result, not a newly read catalog source.

Updating an existing variant requires `Store.save_variant`'s `expected_revision` argument; a stale editor must reload or save a copy. First saves build and validate a complete `_staging` directory before publishing the UUID with one directory rename; interrupted staging is ignored by the library and is not silently promoted. Saves, deletes and restores exclusively reserve the variant ID using an atomic directory operation. Each operation releases its reservation on ordinary success/failure, and temporary files have unique names. Deletion rechecks the captured revision under that reservation. New trash generations use UUID tokens, so restore does not depend on wall-clock order. This prevents competing writers from overwriting an immutable revision or redirecting a confirmed delete.

Recipes without measured edits retain `openrc-aircraft-workshop-v1-generic-compiler-2`. Nonempty `mass_edits` selects `openrc-aircraft-workshop-v1-measured-mass-1`; the optional extension is absent from normalized legacy recipes. Nested masses normalize to float, measurement sources trim outer whitespace, and independent edits sort by stable ID before hashing. Direct measured saves and imports compile before publication; exact readback must return the new revision. Saved compiler pins remain immutable, so changing evaluators requires a new build. Recovery lives separately at `user://workshop_recovery/_workshop_recovery/` with fixed primary/backup/temp files and a fail-closed `write.lock`; never reclaim a lock merely because it is old. Readback/interruption tests do not establish power-loss durability.

If the current manifest or its referenced revision is corrupt/incomplete, loading may recover an earlier valid revision through the manifest backup. The editor identifies the recovered revision; saving creates a new revision beyond existing files and preserves the usable backup. A saved record never silently acquires a missing historical descriptor pin.

An abrupt process termination can leave an empty `user://aircraft_variants/_locks/<uuid>/` reservation. Loading and **Save a copy** remain available; automatic lock stealing is disabled. Only remove an orphan reservation after verifying that no simulator instance is writing that variant. The store provides local filesystem protection, not distributed synchronization.

The named-library save matrix exercises 35 boundaries across first publication, updates, backup rotation and updates after backup recovery. Injected prefixes and abrupt native Windows writer termination preserve complete physical/presentation records, immutable revisions and explicit retry behavior. Temporary files, staged directories and orphan revision files are never silently promoted. This establishes the recorded process-boundary behavior; partial filesystem writes, staging cleanup and power-loss durability remain unqualified. See [AE-03a evidence](research/aircraft-editor/AE-03a/README.md).

Bundles use strict JSON with byte, depth and node limits. The read-only `--aircraft-variant=<local-json-path>` path validates the exact base snapshot, recipe, descriptor, dependency pins and presentation profile, freezes a trial, and does not import into the library or change preferences. A separate import operation can create a local copy only after current compiler, profile and dependency compatibility checks. Changed wheel/glow/model dependencies or an incompatible compiler prevent a saved variant from starting; the library record remains intact. Removing the catalog visual family prevents a saved variant from flying; its record remains readable. Full fleet migration, broad cross-platform fresh-package qualification and physical module support remain open in AE-19 and later steps.

## Verification

Use the [focused commands](TOOLS.md#aircraft-workshop) before the full `app/test.sh` suite. Focused suites now cover presentation profiles, customization bindings/instance isolation, smoke scheduling, bundles, bounded experiments and start qualification alongside the physical Workshop paths. A passing focused suite does not close native rendering/performance, full fleet, physical or user acceptance. A blocked generator is a failed integration gate, even if individual runtime suites pass.

| Dated evidence | Scope |
| --- | --- |
| [AE-03a library save boundaries, 2026-10-19](research/aircraft-editor/AE-03a/README.md) | 35 injected and native Windows abrupt-writer cases; complete records, immutable retries, backup recovery and orphan-lock/Save a copy behavior |
| [AE-03c recovery, 2026-10-19](research/aircraft-editor/AE-03c/README.md) | Bounded snapshots, interruption/lock/collision matrix, invalid-field restore and native recovery dialog |
| [AE-12/13 measured mass, 2026-10-19](research/aircraft-editor/AE-12-13/README.md) | Independent first-moment/full-tensor checks, fixed hubs/intakes, compiler identity, immutable records and constrained measurement UI |
| [AE-24d.1 thumbnails, 2026-10-19](research/aircraft-editor/AE-24d-1/README.md) | Copied-pixel LRU, two native families, twenty active-render cancellation cycles and active-preview isolation |
| [AE-24 presentation and bounded-analysis baseline, 2026-10-19](research/aircraft-editor/AE-24/README.md) | Appearance/smoke pages, Library search/favorites, compatible profile copy and nine native captures; 30/60/144 GPU lifecycle checks, strict portable bundles and source-only experiment CLI. This baseline predates AE-24d.1 thumbnails; broader rendering, hardware and physical acceptance remain open |
| [AE-08b/09 interface delivery, 2026-10-19](research/aircraft-editor/AE-08b-09/README.md) | Inspection, compact menus, draft/trace guards, numeric validation, storage publication and native interface checks; remaining acceptance is explicit |
| [AE-00 investigation, 2026-10-19](research/aircraft-editor/AE-00/README.md) | Current source seams, official Godot references, diagnostic suites and isolated birth-color probe with unresolved pause/reset assertions |
| [AE-01–10, 2026-10-13](research/aircraft-editor/AE-01-10/README.md) | Initial compiler/store/trial/UI/integration checks, scaling fixtures, captures and persistence audit findings |
| [AS-08 identity migration](research/aircraft-standardization/AS-08-identity/README.md) | Authored physical IDs and Workshop v3 bindings; historical readers remain explicit |
| [AS-09/10 imported models](research/aircraft-standardization/AS-09-10-import/README.md) | Generated model-manifest and shared imported-presentation bindings |
| [UI-29-R3, 2026-10-16](research/menu-investigations/UI-29-R3/README.md) | Native navigation, EN/ES and responsive shell captures; it predates the appearance/smoke pages and does not qualify their layout or rendering |
| [FUEL-00-R1, 2026-10-19](research/fuel-systems/FUEL-00-R1/README.md) | Fuel integration audit and Workshop classification gap |

The initial six-size flight matrix covers constant wing loading and default weight/power for 240 ticks, using the then-current Stik and legacy Extra. It does not qualify today's finite-glow Extra. Algebra checks and twenty synthetic IDs do not establish a full combination envelope, sustained flight, twenty distinct airframes or physical accuracy. The [plan](plans/aircraft-editor.md) owns remaining acceptance; historical logs retain their original scope.
