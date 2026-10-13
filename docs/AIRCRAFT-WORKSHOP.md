# Aircraft Workshop

The Workshop creates experimental local variants without changing shipped aircraft data. Open **Aircraft Workshop** from Home or Pause; in Spanish the entry is **Laboratorio de aviones**. The [AE plan](plans/aircraft-editor.md) owns remaining development; [implementation evidence](research/aircraft-editor/AE-01-10/README.md) records the initial supported slice.

## Using the Workshop

1. Choose a catalog aircraft. Its supported adjustments are enabled automatically.
2. Select a preset or edit size, weight, power and control travel. Inspect the original/proposed mass, span, area, wing loading, RPM, static thrust/power and reference-chord CG.
3. Optionally name and **Save build**. Saving again creates an immutable revision of that variant; **Save a copy** creates a separate variant. Load restores the original source snapshot and saved recipe. Delete moves a variant to local trash; **Undo delete** restores the most recent deletion during this editor visit.
4. Choose **Test fly**. Trials start in the air. Pause and return to Workshop to continue the same draft. If opened over an existing flight, that flight remains paused at its previous state. An invalid candidate leaves it untouched. Restoring a detached flight rebuilds its audio buses and restarts its continuous sound with a fade; the simulation state is preserved.

The preview is a separate still scene with a scale grid. Keyboard focus stays in the menu and follows the scroll area. The title and action footer remain visible at 720p and 1080p. English and Spanish labels are included. Reset restores defaults; Undo/Redo retain up to 32 recipe edits. One slider drag is one edit; a new edit clears the redo branch. Loading a variant or switching aircraft starts a separate history. A trial round trip preserves the draft and history, but unsaved drafts are not recovered after closing the editor or restarting the application.

## Supported adjustments

| Parameter | Current range or choices | Meaning |
| --- | --- | --- |
| Size | 50%, 75%, 100%, 125%, 150%, 200% | Uniform physical and visual scale |
| Mass scaling | Constant wing loading; geometric | Scale mass with area or volume, before applying the weight multiplier |
| Weight | 0.50–2.00× | Uniform inventory mass change; derived inertia follows the changed mass |
| Power | 0.50–2.00× | Virtual prescribed-RPM propeller static-power multiplier after size/mass scaling |
| Control travel | 0.50–1.50× | Surface throw limits; does not change transmitter expo or servo speed |

The six size choices are shortcuts. Loaded recipes may contain intermediate sizes within 50–200%; the editor adds their exact size to the selector and preserves their numeric multipliers instead of rounding them to the nearest shortcut or slider step. Invalid recipe inputs are refused before replacing the current draft.

Presets are Mini, Giant, Light, Heavy, More power, More travel and Light / low power. They apply only supported adjustments. Their names describe changes rather than measured flight performance. Valid slider values can still form an invalid combination: normal aircraft, trim and timestep checks remain authoritative.

All seven current catalog configurations have generated descriptors and use the same screen, library, compiler and launch path. Conventional control travel is supported across this catalog. Uniform size/weight and virtual power changes currently require the simple prescribed-RPM propeller capability without shaft, finite-glow installation or propeller normal-force coupling. The Stik and Extra satisfy that capability gate. The P-51, electric Timber, two finite-glow Stiks and turbine jet keep these adjustments disabled until their reusable family transforms are implemented. There are no aircraft-ID switches in the Workshop transformation rules.

These changes retain estimated aerodynamic coefficients and do not model Reynolds-number changes or certify a real miniature/giant aircraft. Runway trials, component/CG editing, editable hardware packages, measured performance experiments, portable import/export and wider ranges remain planned.

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

After adding or regenerating an aircraft through its owning pipeline, run:

```powershell
python research/aircraft-standardization/build_models.py
python research/aircraft-editor/build_descriptors.py
python research/aircraft-editor/build_descriptors.py --check
python research/aircraft-editor/test_descriptor_checkout.py
```

Commit the generated `app/data/workshop/<catalog-id>.json` with its source change. The current closed `openrc-aircraft-workshop v2` descriptor binds exact aircraft bytes, snapshot-local inventory index/name hashes, shared module assertions, visual family, model-manifest hash and stable root. It contains no copied physical constants. Renaming/reordering an inventory requires regeneration; these inventory keys do not supply cross-version component migration. Model manifests and their generator are defined in the [aircraft contract](../AIRCRAFT_CONTRACT.md#model-and-package-contract).

The v1 descriptor reader remains explicit for saved variants. Structural validation never resolves current model dependencies, so an unavailable/changed model cannot hide a saved record. Trial preparation verifies the current dependencies and passes its accepted model hash to the renderer; a replacement between freezing and building is rejected. The library record stays unchanged.

Adding an aircraft with existing supported capabilities requires catalog/data/assets, a generated descriptor and conformance evidence. It does not require a new Workshop screen or transformation branch. A new propulsion law requires a shared capability implementation and its tests. Descriptor generation does not automatically qualify that law for editing.

### Scale policy

For size `s` and weight multiplier `w`, mass ratio `r` is `s²w` under constant wing loading or `s³w` under geometric scaling. Lengths/positions scale by `s`, areas by `s²`, and the inventory-derived inertia by `r s²`. CG/reference-chord ratio is unchanged by uniform scaling. Declared start speed scales by `sqrt(r)/s`; the session still requires an accepted trim.

The virtual legacy propeller diameter scales by `s`, rotating inertia by `r s²`, maximum RPM by `sqrt(r)/s² × power^(1/3)`, and idle RPM by `sqrt(r)/s²`. The static coefficient-law result therefore scales thrust by `r × power^(2/3)` and power by `r^(3/2)/s × power`. It is a virtual propeller policy, not a substituted physical engine specification.

Virtual suspension uses `a=max(s,1)`: spring stiffness scales by `r/a`, damping by `r/sqrt(a)`, and travel by `a`. This deliberately preserves the small-model suspension timescale instead of shrinking travel with geometry. Contact positions, hull, wheel radius and wheel mass/inertia parameters are transformed separately. Inherited wheel profiles retain their applied status so variant IDs do not disable wheel dynamics. Runway qualification remains AE-11.

### Persistence and identity

Variants live under Godot's `user://aircraft_variants/`. The record uses `format: openrc-aircraft-variant` and `version: 1`; it stores exact base bytes, recipe, descriptor, dependency hashes, compiler version, UUID, display name and revision. The original resource bytes are never overwritten.

Trials normalize omitted recipe defaults and exclude cosmetic names from physical identity. Their fingerprint binds source, physical recipe, descriptor, resolved visual family/model-manifest hash, dependencies and compiler, including when a legacy descriptor supplies the visual binding. Trace metadata also records the ancestor variant/revision and exact resolved-input/model hashes. Saved ancestry requires an explicit descriptor, dependency and compiler pin plus a positive integer revision. Flight restart/reload uses the frozen in-memory result, not a newly read catalog source.

Updating an existing variant requires its expected revision (`Store.save_variant`'s final argument); a stale editor must reload or save a copy. Saves, deletes and restores exclusively reserve the variant ID using an atomic directory operation. Each operation releases its reservation on ordinary success/failure, and temporary files have unique names. This prevents competing writers from overwriting a supposedly immutable revision.

If the current manifest or its referenced revision is corrupt/incomplete, loading may recover an earlier valid revision through the manifest backup. The editor identifies the recovered revision; saving creates a new revision beyond existing files and preserves the usable backup. A saved record never silently acquires a missing historical descriptor pin.

An abrupt process termination can leave an empty `user://aircraft_variants/_locks/<uuid>/` reservation. Loading and **Save a copy** remain available; automatic lock stealing is disabled. Only remove an orphan reservation after verifying that no simulator instance is writing that variant. The store provides local filesystem protection, not distributed synchronization.

External dependencies are **hash-pinned, not embedded and replayed from a bundle**. Changed wheel/glow/model dependencies or an incompatible compiler prevent a saved variant from starting; the library record remains intact. A new copy from current catalog data is the current manual migration path. Removing the catalog visual family prevents a saved variant from flying; its record remains readable. Portable frozen dependency loading and explicit migrations remain AE-16/19.

## Verification

`app/test.sh` discovers the six `test_workshop_*.gd` suites and checks generated descriptors plus fresh checkouts with both Git line-ending modes. See [AE evidence](research/aircraft-editor/AE-01-10/README.md) for the native Godot results, UI captures and remaining acceptance scope. Passing these checks establishes software behavior, not measured flight accuracy.
