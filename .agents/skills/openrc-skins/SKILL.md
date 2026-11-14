---
name: openrc-skins
description: Author and verify stock skins, liveries, decals and material finishes for OpenRC aircraft, helicopters and RC cars through the paint registry and source texture generators. Use for vehicle appearance work; player-created .orskin packages have a separate pipeline.
---

# Vehicle skins in OpenRC

[tools/skins/README.md](../../../tools/skins/README.md) owns the stock-paint workflow.
Keep skins render-only: preserve generated geometry, UVs, node/hinge names and physics.
Runtime bindings make per-instance `StandardMaterial3D` copies before lights, blur,
damage and custom paint kits. Home lists stock skins from the registry.

## Authoring workflow

1. **Inspect existing schemes and the actual asset.** Check the registry and source
   generators for suitable work to reuse, preserving requests for a distinct design.
   Use `tools/skins/glb_inspect.py` for GLBs and
   `paint_audit.py` for UV density, stretch and conflicts. For procedural aircraft,
   inspect a built instance and its UV source. Material names can be shared by
   unrelated parts; use node bindings when a finish belongs only to one part.
2. **Choose the cheapest sufficient layer.** Start with registry colours/finishes,
   node rules and shared CC0 maps. Bake a new atlas when the design needs unique
   panels, lettering or wear. A new Stik skin can reuse its stock atlas directly;
   a Blender export is unnecessary for a paint-only task.
3. **Generate reproducibly.** Use the pinned visual venv and the owning generator,
   not hand-edited PNGs. Record sources, licences and hashes. Read-modify-write
   `app/data/vehicle_paints.json` to preserve parallel work. Regenerate the recorded
   roughness mean whenever its map changes; run the actual generator's `--check`.
4. **Review the production builders.** Inspect Home and flight at 1920x1080 first,
   both flanks, top and underside, then Low scene detail. Studio/atlas previews
   support authoring; their default dimensions do not establish native 1080p review.
   Record the actual viewport dimensions and renderer from the running app.
   Check lettering at its actual screen size, reflections at multiple angles and
   small accents on the visible aircraft. Atlas-area percentages alone cannot
   establish visible coverage when UVs repeat. Independent render review is useful.
5. **Verify new skin bindings and affected behavior.** New registry/material
   bindings merit the targeted paint test even when loader code is unchanged. Run
   the checked
   `app/tests/test_vehicle_paint.gd` and relevant livery, picker, custom-skin and
   vehicle tests. Cover variant registration, repainting and Low when affected.
   Colour-only edits do not justify broad physics suites or new tests that repeat
   the implementation. Read engine errors/warnings and completion markers as well
   as assertion counts. Keep captures in ignored evidence, not tracked image folders.

## UV and raster rules

- UVs may repeat outside 0..1: wrap texels as the runtime sampler does.
- Shared/mirrored faces cannot carry independently readable lettering. Use symmetric
  marks there and put text on separately unwrapped faces; a fin is not automatically
  safe. For the Stik, read the [atlas rules](../../../tools/skins/README.md#procedural-stik-atlas)
  before placing any artwork. Do not change its stock/custom-kit identity to fix a decal.
- In scene-space bakes, apply all node transforms. Let the face best aligned with
  the paint direction own shared edge/cove texels (`skin_axis`); keep bright keylines
  off hidden gaps. Avanti wing doors need their own texture over the reused UVs.
- Keep letters at least 20 actual atlas pixels tall, bilinearly sampled and clear of
  folds, wing roots and hinges. Smooth/interpolate chord-based boundary tables.
- Compensate unequal U/V texel density so logos retain their aspect on the mesh,
  not only in the PNG. Keep complete emblems clear of articulated hinge cuts unless
  a split is intentional, and review them with the control surface deflected.
- Repainting an overlapping atlas region must replace its albedo, roughness,
  metallic mask and height/normal information together. A flat hatch must not keep
  a buried seam from the previous grid. Pillow drawing can include the far edge
  while a crop excludes it; cover the complete stroke to prevent bright mip bleed.

## Material decisions

- Use charcoal rather than pure black for coated surfaces. Black paint is mostly
  dielectric; do not make every black panel metallic. Exposed scuffs may reveal
  metal. Bare aluminium needs alloy-colour, roughness and metal/paint boundaries,
  not a flat silver fill. Treat these as art-directed estimates, not measured BRDFs.
- Compatibility flight and Home disable sky reflections (`render/atmosphere.gd`):
  fully metallic paint keeps only sun highlights and reads near-black. Give bare
  metal a partial metallic share (about 0.45-0.7) and compare `paint_preview.gd`
  `--env=flight` (default) with `--env=sky`; `--focus=x,y,z --zoom=N` frames decals.
- `"albedo_texture": null` / `"emission_texture": null` remove a stock map.
- Metal skins reuse `build_metal_skin` (scene-space bake, height-to-normal, chunked per-texel
  layers). Run one heavy bake at a time: with a full system disk the page file cannot grow and
  a parallel bake or render fails with MemoryError, which is not a byte mismatch.
- `roughness_texture` multiplies `roughness`; Low uses multiplier times the recorded
  map mean. A `metallic_texture` also needs the intended multiplier (usually 1.0)
  and grayscale channel. Its paint/metal boundaries remain at Low.
- Replacement normal maps must not expose the source film normals when Low skips
  detail. Skins that do not replace normals can retain their original finish.
- Emission's additive colour can wash out an otherwise sparse map. Use black
  emission colour when only the map should glow; repainting must remove stale
  emission. Match clearcoat to a coating/resin, not automatically to every metal.
- Repainting starts from the immutable source, stays one copy deep and preserves
  mesh resources. Test neon -> nonemissive -> factory when those finishes interact.
- New textures need `compress/mode=2`, mipmaps and normal-map mode 1 where applicable.
  Import with the pinned engine through admitted tooling; retain only intended
  sidecar changes. Compatibility does not support subsurface scattering and ignores
  the high-quality compression flag. Avoid the HX-700 gear's `Plastico_Grafito`
  binding because its copied surface has a dummy-renderer teardown error.

## Shared-host verification

Read [testqueue](../../../tools/testqueue/README.md) and
[debug bridge](../../../tools/debug/README.md) before engine work. Use admitted
sessions and their owning handles; a port alone is not ownership. When the host is
busy, leave the work queued, check its state patiently and advance generators,
provenance, visual/source review or documentation. Preserve other sessions; do not
ask the user to close them by default merely to accelerate a skin task.

Budget disk space for frozen inputs, materialized copies and imports before
launching. Reuse a complete, source-compatible import cache when appropriate.
Allow the job deadline to cover import plus the actual check. For a known job,
use infrequent status requests with only one in flight; slow status is not a reason
to submit it again. If a submission acknowledgment is lost after registration,
recover once from its durable receipt with `testctl.py resubmit <receipt>` before
creating another request. Do not confuse infrastructure failure with a failed skin
assertion. Retain logs and restore owned temporary storage changes before handoff.

## Sources and permissions

Reuse suitable ambientCG CC0 maps, bundled OFL fonts and public-domain artwork.
Record exact source URLs, licences, hashes and transformations in the existing
SOURCE/LICENSE files. Keep downloaded originals separate from generated textures.
Trademarked sponsor artwork requires the owner's confirmation of permission; keep
its original bytes and provenance. Do not turn a paint task into a geometry,
lighting, simulation or host-configuration change.
