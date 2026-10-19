# Aircraft Workshop

The Workbench feature is named **Aircraft Workshop** in the application (**Taller de aviones** in Spanish). It creates experimental local variants without changing shipped aircraft data. Open it from Home or Pause.

| Need | Authoritative home |
| --- | --- |
| Use the editor; understand supported adjustments, scaling and saved variants | This guide, checked against source on 2026-10-19 |
| Develop the feature; find pending steps and acceptance gates | [Consolidated AE plan](plans/aircraft-editor.md) |
| Explore proposed customization, smoke presets and easy experiment ideas | [Future Workbench backlog](plans/aircraft-editor.md#5-planned-player-facing-work) |
| Implement the next slice; find dependencies, contracts and tests | [Ordered work packages](plans/aircraft-editor.md#56-implementation-packages-and-order) and [required test matrix](plans/aircraft-editor.md#57-required-test-matrix) |
| Author physical data, stable IDs and model manifests | [Aircraft contract](AIRCRAFT_CONTRACT.md#workshop-authoring-standard) |
| Generate descriptors, run checks or capture the editor | [Workshop commands](TOOLS.md#aircraft-workshop) |
| Inspect dated results and limitations | [Verification and evidence](#verification) |

## Using the Workshop

1. Choose a catalog airplane. Its supported adjustments are enabled automatically.
2. Select a preset or edit size, weight, tank capacity, power and control travel. Inspect the original/proposed mass, span, area, wing loading, tank capacity, RPM, static thrust/power and reference-chord CG where available.
3. Optionally name and **Save build**. Saving again creates an immutable revision of that variant; **Save a copy** creates a separate variant. Load restores the original source snapshot and saved recipe. Delete moves a variant to local trash; **Undo delete** restores the most recent deletion during this editor visit.
4. Choose **Test fly**. Trials start in the air. Pause and return to Workshop to continue the same draft. If opened over an existing flight, that flight remains paused at its previous state. An invalid candidate leaves it untouched. Restoring a detached flight rebuilds its audio buses and restarts its continuous sound with a fade; the simulation state is preserved.

The preview is a separate still scene with a scale grid. Keyboard focus stays in the menu and follows the scroll area. The title and action footer remain visible at 720p and 1080p. English and Spanish labels are included. Reset restores defaults; Undo/Redo retain up to 32 recipe edits. One slider drag is one edit; a new edit clears the redo branch. Loading a variant or switching aircraft starts a separate history. A trial round trip preserves the draft and history, but unsaved drafts are not recovered after closing the editor or restarting the application.

## Supported adjustments

| Parameter | Current range or choices | Meaning |
| --- | --- | --- |
| Size | 50%, 75%, 100%, 125%, 150%, 200% | Uniform physical and visual scale |
| Mass scaling | Constant wing loading; geometric | Scale dry inventory mass with area or volume, before applying the weight multiplier |
| Weight | 0.50–2.00× | Multiplies dry inventory mass; declared tank liquid follows tank scaling |
| Tank capacity | 0.50–2.00× | Compiler sizing proposal for validated tanks; trial mass/fill integration remains under verification |
| Power | 0.50–2.00× | Virtual prescribed-RPM propeller static-power multiplier after size/mass scaling |
| Control travel | 0.50–1.50× | Surface throw limits; does not change transmitter expo or servo speed |

The six size choices are shortcuts. Loaded recipes may contain intermediate sizes within 50–200%; the editor adds their exact size to the selector and preserves their numeric multipliers instead of rounding them to the nearest shortcut or slider step. Invalid recipe inputs are refused before replacing the current draft.

Presets are Mini, Giant, Light, Heavy, More power, More travel and Light / low power. They apply only supported adjustments. Their names describe changes rather than measured flight performance. Valid slider values can still form an invalid combination: normal aircraft, trim and timestep checks remain authoritative.

The catalog has eight airplane configurations; the Workshop filters out the separate rotorcraft entry. Size, dry-weight and virtual-power transforms require the simple prescribed-RPM capability, currently provided by the baseline Stik. Extra now uses a finite-glow installation, so it keeps those transforms disabled like the three finite-glow Stiks. Tank capacity is a separate operation for classified aircraft with validated tanks; conventional control travel follows the registered surface capability. The compiler contains no aircraft-ID transformation branches.

Descriptor freshness is a separate launch gate. The [latest diagnostic checks](research/aircraft-editor/AE-00/README.md#diagnostic-checks) pass all eight descriptors and the store/UI/integration suites; compiler and legacy-trial failures remain. These moving-tree results do not establish fleet acceptance. Fuel software and physical acceptance stay with the [fuel-mass plan](plans/fuel-mass-balance.md).

These changes retain estimated aerodynamic coefficients and do not model Reynolds-number changes or certify a real miniature/giant aircraft. Runway trials, component/CG editing, editable hardware packages, measured performance experiments, portable import/export and wider ranges remain planned.

The Workshop reads each catalog entry's main `data` source. Timber trials therefore use its fixed-voltage configuration; ordinary flights default to the separate finite 4S pack. The Workshop has no battery-mode selector. Missing family transforms and portable resource loading remain in the AE plan.

## Common implementation and authoring interface

| Source | Responsibility |
| --- | --- |
| `app/workshop/parameters.gd` | Closed recipe keys, bounds and defaults |
| `app/workshop/compiler.gd` | Detached, capability-gated transforms, validator and before/after summary |
| `app/workshop/descriptor.gd` | Generated descriptor validation and source/binding checks |
| `app/workshop/dependencies.gd` | Wheel/glow dependency discovery and exact-byte hash verification |
| `app/workshop/store.gd` | UUID library, immutable revisions, atomic index replacement/recovery and trash |
| `app/workshop/trial.gd` | Canonical physical identity and frozen accepted trial inputs |
| `app/ui/workshop.gd`, `workshop_preview.gd` | Common editor and isolated still preview |
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

Variants live under Godot's `user://aircraft_variants/`. The record uses `format: openrc-aircraft-variant` and `version: 1`; it stores exact base bytes, recipe, descriptor, dependency hashes, compiler version, UUID, display name and revision. The original resource bytes are never overwritten. Saves normalize numeric recipe values to their JSON round-trip representation before hashing; caller dictionaries and existing revisions remain unchanged.

Trials normalize omitted recipe defaults and numeric representation (`1` and `1.0` have the same identity), validate metadata before hashing, and exclude cosmetic names from physical identity. Conflicting recipe/record ancestry is refused. The editor keeps physical recipe values separate from the saved record name and ID, including when loading historical records that duplicate them inside the recipe. Their fingerprint binds source, physical recipe, descriptor, resolved visual family/model-manifest hash, dependencies and compiler, including when a legacy descriptor supplies the visual binding. Trace metadata also records the ancestor variant/revision and exact resolved-input/model hashes. Saved ancestry requires an explicit descriptor, dependency and compiler pin plus a positive integer revision. Flight restart/reload uses the frozen in-memory result, not a newly read catalog source.

Updating an existing variant requires its expected revision (`Store.save_variant`'s final argument); a stale editor must reload or save a copy. Saves, deletes and restores exclusively reserve the variant ID using an atomic directory operation. Each operation releases its reservation on ordinary success/failure, and temporary files have unique names. This prevents competing writers from overwriting a supposedly immutable revision.

If the current manifest or its referenced revision is corrupt/incomplete, loading may recover an earlier valid revision through the manifest backup. The editor identifies the recovered revision; saving creates a new revision beyond existing files and preserves the usable backup. A saved record never silently acquires a missing historical descriptor pin.

An abrupt process termination can leave an empty `user://aircraft_variants/_locks/<uuid>/` reservation. Loading and **Save a copy** remain available; automatic lock stealing is disabled. Only remove an orphan reservation after verifying that no simulator instance is writing that variant. The store provides local filesystem protection, not distributed synchronization.

External dependencies are **hash-pinned, not embedded and replayed from a bundle**. Changed wheel/glow/model dependencies or an incompatible compiler prevent a saved variant from starting; the library record remains intact. A new copy from current catalog data is the current manual migration path. Removing the catalog visual family prevents a saved variant from flying; its record remains readable. Portable frozen dependency loading and explicit migrations remain AE-16/19.

## Verification

Use the [focused commands](TOOLS.md#aircraft-workshop) before the full `app/test.sh` suite. The full runner discovers six `test_workshop_*.gd` suites and includes descriptor generation and checkout checks. A blocked generator is a failed integration gate, even if individual runtime suites pass.

| Dated evidence | Scope |
| --- | --- |
| [AE-00 investigation, 2026-10-19](research/aircraft-editor/AE-00/README.md) | Current source seams, official Godot references, diagnostic suites and isolated birth-color probe with unresolved pause/reset assertions |
| [AE-01–10, 2026-10-13](research/aircraft-editor/AE-01-10/README.md) | Initial compiler/store/trial/UI/integration checks, scaling fixtures, captures and persistence audit findings |
| [AS-08 identity migration](research/aircraft-standardization/AS-08-identity/README.md) | Authored physical IDs and Workshop v3 bindings; historical readers remain explicit |
| [AS-09/10 imported models](research/aircraft-standardization/AS-09-10-import/README.md) | Generated model-manifest and shared imported-presentation bindings |
| [UI-29-R3, 2026-10-16](research/menu-investigations/UI-29-R3/README.md) | Native navigation, EN/ES and responsive shell captures; preview inspection remains limited |
| [FUEL-00-R1, 2026-10-19](research/fuel-systems/FUEL-00-R1/README.md) | Fuel integration audit and Workshop classification gap |

The initial six-size flight matrix covers constant wing loading and default weight/power for 240 ticks, using the then-current Stik and legacy Extra. It does not qualify today's finite-glow Extra. Algebra checks and twenty synthetic IDs do not establish a full combination envelope, sustained flight, twenty distinct airframes or physical accuracy. The [plan](plans/aircraft-editor.md) owns remaining acceptance; historical logs retain their original scope.
