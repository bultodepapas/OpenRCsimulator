---
name: openrc-skins
description: Create or improve stock paint schemes (skins, liveries, decals, sponsor logos, material finishes) for OpenRC vehicles — aircraft, the HX-700 helicopter and RC cars — through data/vehicle_paints.json, render/vehicle_paint.gd and the texture builder tools/skins/build_vehicle_paints.py. Covers GLB inspection, 3D-designed liveries baked through stock UVs, lettering and decals, PBR material tuning, import settings, previews, audits and verification. Use for any skin, livery, decal, logo, paint, texture-colour or material-finish task on a vehicle; player paint kits (.orskin) are a different system (tools/skins/README.md, docs/AIRCRAFT-SKINS.md).
---

# Vehicle skins in OpenRC

Authoritative reference: [tools/skins/README.md](../../../tools/skins/README.md) ("Stock vehicle paints"). Skins are render-only:
never edit GLBs, generated geometry or `app/physics`/`app/sim`. Runtime: per-instance `StandardMaterial3D` copies
matched by glTF material name and, optionally, mesh-node glob, applied by each builder before lights, rotor blur,
damage, grime or paint kits copy materials. Home's paint gallery lists the skins automatically.

## Workflow

1. **Inspect** the model: `.tools/visual-venv/Scripts/python.exe tools/skins/glb_inspect.py <glb>` — materials,
   textures, mesh nodes, scene-space bounds and warnings (UVs outside 0..1, mirrored left/right UVs, images shared
   by several materials, emission textures). Procedural models (Ugly Stik) have no GLB: list nodes and `profile:colour`
   material names from a built instance.
2. **Choose the cheapest layer that works:** colour/finish bindings in JSON (`base`, a skin's `materials`), per-part
   rules by node glob (`base_nodes` always, `default_nodes`/skin `nodes` per scheme, `layers` on request), shared CC0
   detail maps (twill carbon, brushed metal, rubber in `assets/vehicle-paints/shared/`), and only then baked textures.
3. **Design baked liveries in 3D scene space** (all node transforms applied) in the builder and bake through the stock
   UVs. Measure first: `tools/skins/paint_audit.py <glb> <materials> <WxH>` (texel density, stretch, conflicts).
4. **Preview** through the real builders, both sides and the Low preset:
   `.tools/Godot_v4.8-beta2_win64_console.exe --path app --audio-driver Dummy --windowed --resolution 320x200 --script ../tools/skins/paint_preview.gd -- --vehicle=<id> --skin=<id> --out=<abs dir>`
   (prefix `OPENRC_SCENE_DETAIL=low`). Look at every image; audit orientation, resolution, logic and aesthetics,
   ideally with an independent reviewer given only the renders.
5. **Verify:** `build_vehicle_paints.py --check` (byte-exact), `app/tests/test_vehicle_paint.gd` plus
   `test_aircraft_liveries`, `test_livery_picker`, `test_custom_skin` and the vehicle's own suites; add checks for new skins.

## Baking rules learned the hard way

- Stock UVs **repeat** outside 0..1: wrap texel indices like the sampler, never clip.
- Left/right parts often **share mirrored UVs**: fold about X = 0 (`symmetric`), keep lettering and asymmetric marks
  (nav-light colours, "NO STEP") off them; put text on separately mapped surfaces (fuselage sides, fin).
- Hidden cove/edge faces share texels with the skin: let the face that best faces the skin axis own the texel
  (`skin_axis`, winner takes all), and keep white keylines off gap faces.
- Parts reusing another material's image over its UVs (Avanti wing doors) get their own texture; force underside
  design on parts whose inner faces point up.
- Replace emission maps with the design (the old pattern keeps glowing); add a gloss map + `detail_map_means` entry.
- Chord-based designs: smooth the leading/trailing-edge table and interpolate between span bins.
- Lettering/decals: choose the side from the normal, sample bilinearly, letters ≥ 20 px tall (bake a larger atlas —
  UVs are normalised), keep them inside one surface and clear of creases, wing roots and control-surface hinges.

## Materials

- No pure black: charcoal plastic/rubber ≈ sRGB `#19`–`#20`. Lacquer and carbon resin get clearcoat; with a
  `roughness_texture`, `roughness` is a multiplier (Low preset uses multiplier × map mean).
- Compatibility renderer: everything but subsurface scattering works; `compress/high_quality` is ignored.
- Every new texture: `compress/mode=2`, `mipmaps/generate=true`, normal maps `compress/normal_map=1`, set in the
  `.import` (Godot detects 3D use only in the editor), then `--headless --path app --import`; restore unrelated sidecars.
- Do not bind the articulated HX-700 gear's `Plastico_Grafito` (dummy-renderer teardown error).

## Assets and provenance

Reuse before inventing: ambientCG CC0 via its API, bundled Noto fonts (OFL). Record sources in `SOURCE.txt`/`LICENSES.txt`.
Trademarked sponsor logos need the owner's confirmation of permission: keep originals unchanged in a `.gdignore`d
folder with a SOURCE note and bake them in. Another session may edit `vehicle_paints.json`: read-modify-write, never
overwrite blindly. Python patches with `'''` break bash heredocs — write them to a file first.
