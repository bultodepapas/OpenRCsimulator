# Aircraft skin toolkit

The registry at `app/assets/skin-kit/models.json` covers nine visual families:
Ugly Stick (basic and three glow configurations), electric 6S, Extra 300S, P-51D, Corsair, Vantage Jet,
Turbo Lumber, MoonRunner X99 and HX-700/X-Cell. Kits use the same paint bindings as the runtime.
See [the skin contract and player flow](../../docs/AIRCRAFT-SKINS.md).

## Generate

Run `python tools/skins/build_guide.py` and `--check` first. The guide includes
all nine simulator languages, image and Blender prompts, and community submissions.

The procedural families and Turbo Lumber need a prepared scene. Run the
checked Godot exporter for each of `jensen-das-ugly-stik-60`, `stik-electric-6s`, `gp-extra-300s-60`,
`p51d-mustang-120`, and `turbo-lumber-evolution`:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta2_win64_console.exe').Path
python tools/godot/run_checked.py --timeout 180 -- $GodotWindows --headless --path app --audio-driver Dummy --script ../tools/skins/export_procedural.gd -- <family> <absolute-output-directory>/<family>.glb
```

Create the output directory first. The exporter validates the stock model before
copying it, applies the same paint mapping as the runtime and reports its identity.
The neutral six-view starters for Extra, P-51 and Timber are not stock-paint bakes;
unchanged packaging yields neutral paint. Projection overlaps and seams are
intentional limitations documented in the guide. Both Ugly Stick families retain the
existing covering atlas; electric 6S has its own model and package identity.
Hidden maintenance/fracture subtrees are omitted from the editable
kit copy where required for glTF import; runtime nodes remain intact.

Then use Blender 5.2.2:

```sh
blender --background --factory-startup --python-exit-code 1   --python tools/skins/build_skin_kits.py -- --prepared-dir <absolute-output-directory>
```

Optional trailing family IDs rebuild only those kits; `--output-dir` builds into
scratch. The generator checks imported GLB hashes or prepared-scene hashes against
the registry, and writes each ZIP atomically. Source deliveries and stock GLBs
are unchanged. `.blend` output need not be byte-identical across rebuilds.

Each kit contains `Aircraft.blend`, `Export OpenRC Skin.py`, `pack_image.py`,
`kit.json`, numbered `Paint-NN.png` / `UV-NN.png` pairs, `README.txt` and `guide.html`.
The guide is stamped with its aircraft family. `kit.json` records material groups,
base-color factors, source dimensions, template kind and stock compatibility hash.
The HX boom is proportionally reduced from 8192 × 880 to 4096 × 440.
The Turbo Lumber and MoonRunner kits also include the original asset attribution
and beta-specific distribution notice. Their technical paint-editing workflow
does not itself establish permission to modify or redistribute the asset.

## Stock vehicle paints (HX-700 and RC cars)

The built-in paint schemes of the HX-700 and the two RC cars are separate from the
player kits above. `app/data/vehicle_paints.json` lists them per vehicle: an
always-on `base` (the HX-700 carbon fibre, which the Blender export left as a
white unbaked procedural) and named skins chosen in Home's paint gallery.
`app/render/vehicle_paint.gd` applies them as per-instance `StandardMaterial3D`
copies matched by glTF material name, before lights, rotor blur and damage copy
the materials. Saved choices: `[liveries]` for the helicopter, `[vehicle_skins]`
for the cars. The agent workflow is the `openrc-skins` skill.

Helper tools (Python from `.tools/visual-venv`, Godot windowed for renders):

```sh
python tools/skins/glb_inspect.py <model.glb> [--material <name>]   # materials, nodes, bounds, UV traps
python tools/skins/paint_audit.py <model.glb> <mat>[,<mat>] <W>x<H>  # texel density, stretch, conflicts
<godot> --path app --audio-driver Dummy --windowed --resolution 320x200 \
  --script ../tools/skins/paint_preview.gd -- --vehicle=<id> --skin=<id> --out=<abs dir> [--views=...] [--zoom=1]
```

`paint_preview.gd` builds the vehicle through the game's builders (aircraft ids,
`xcell-60-research` for the HX-700, or an RC car id). It saves 1600×1000 studio
views. Prefix `OPENRC_SCENE_DETAIL=low` to check the Low preset.

Bindings may set albedo/emission colours and maps, metallic, roughness,
clearcoat, and object-space triplanar detail: the shared CC0 twill-carbon,
brushed-metal and rubber maps in `app/assets/vehicle-paints/shared/`
(ambientCG, see its `LICENSES.txt`). With a `roughness_texture`, `roughness`
is its multiplier. Normal and roughness maps are skipped at Low scene detail.
Keep albedos out of pure black (charcoal plastic and rubber sit near sRGB
`#19`–`#20`) and keep `Pala_Carbono` dark: the rotor blur samples its colour.

Per-part rules use the same mesh-node globs. `base_nodes` always applies (part
finishes such as TiN shock shafts, powder-coated springs, glass-filled nylon
arms or red urethane bump stops); give it finishes, not colours a skin changes.
`default_nodes` applies with the delivered paint, and a skin's `nodes` with that
skin, for parts that carry a scheme's own colours, for example the MT8's
machined shock bodies and anodised caps.

A fixed-wing skin from this registry appears in Home's paint gallery after the
delivered liveries and repaints the default asset (no livery GLB of its own). The
Avanti jet's "Verde Neón Carbono" is designed in the jet's scene space (all node
transforms applied) and baked through the stock UVs. Those UVs need three
precautions, all in the builder:
- They repeat outside 0..1, and the bake wraps them as the sampler does.
- Left and right parts share mirrored UVs, so the bake folds about X = 0.
- Cove and edge faces share texels with the skin, so the face that best faces the
  skin direction owns each texel.

The stock wing doors reuse the wing image over the wing's leading edge, so the
skin gives them their own texture.

Fixed-wing families may have entries too. `AirplaneBuilder.build` applies a
family's base right after model validation, before lighting, customization or
paint kits copy materials. The procedural Ugly Stik materials are named
`profile:colour` (`aluminum:858d91ff`) and are shared across parts (wheel hubs
and engine case), so the Ugly Stik landing-gear finishes bind by node:
rubber-grain tyres, brushed hubs, the brushed 2024-T3 strap, piano-wire nose leg
and black-oxide collars. `stik-electric-6s` reuses them with `same_as`.

A vehicle may also define `layers`, applied only on request
(`VehiclePaint.apply(root, id, skin, ["inspection"])`). A layer binds by material
name or, under `nodes`, by mesh-node glob with `"*"` for all of a node's
materials. The HX-700 `inspection` layer is the colour key of the advanced
mechanics view (`app/tools/inspect_hx700.gd`). Orange is servo input, red the
fixed swashplate and blue rotating parts. Violet is the swashplate driver, yellow
the pitch links and green tail control. Steel, nylon, screws and carbon keep
their real finish. Painting is authoritative for its own copies, so a layer
switched off returns those surfaces to their base finish. Do not bind the
articulated landing gear's `Plastico_Grafito`. A duplicate of that imported
material on its surface logs a dummy-renderer error when the model is freed. The
mechanics view's fresh technical gear materials do not.

Every texture there imports with mipmaps and high-quality VRAM compression;
normal maps also set `compress/normal_map=1`. Godot only detects 3D use in the
editor, so set these in the `.import` files of new textures, then reimport.

Generated textures (canopy and boom liveries, re-tinted Monster Car 2 livery and
emission maps) come only from assets already in the repository. Canopy designs,
including the mirrored "HX-700" lettering (Noto Sans, SIL OFL), are evaluated in
the canopy's model space and baked through its plan-projected UVs:

```powershell
.tools/visual-venv/Scripts/python.exe tools/skins/build_vehicle_paints.py
.tools/visual-venv/Scripts/python.exe tools/skins/build_vehicle_paints.py --check
```

`--check` is byte-exact with the visual venv's Pillow 12.3.0 and NumPy 2.5.3;
another Pillow/FreeType build may anti-alias the lettering differently.
Import new outputs once with Godot `--headless --path app --import`. A colour-only
skin (all MT8 schemes) needs no texture: edit the JSON only.

### Ugly Stik: NEON RONIN (US-V19)

`build_stik_cyberpunk.py` authors the cyberpunk covering for the basic Stik, its
three glow configurations and electric 6S. Run it with the visual venv; `--check`
compares the three 2048-square PNGs byte for byte. It reuses the shared CC0 carbon
weave and the bundled OFL Noto font. The registry binds albedo, selective emission
and roughness to instance-owned film materials, retaining the stock film normals.
The stock material adds its emission colour to the map: black emission colour
keeps the carbon dark while the map alone supplies the luminous traces.
Low scene detail skips the roughness map and uses its recorded mean instead.

The stock atlas and custom-kit identity stay unchanged. Both wing faces share UVs;
the acid-yellow belly keel and striped stabiliser underside provide the underside
markings. Fin lettering shares UVs and mirrors on the opposite face. Rebuild the
paint from this source, never edit the generated PNGs. Review Home and flight at
1920 × 1080 and run `test_vehicle_paint.gd` plus the Stik skin-fleet checks.

### Ugly Stik: SILVER ACE (US-V20)

`build_stik_silver_ace.py` generates a fictional early-USAF natural-metal scheme
for the basic, glow and electric Stiks. Run it with the visual venv; `--check`
verifies four 2048-square PNGs, source hashes and the recorded roughness mean.
The public-domain USAF roundel, OFL stencil font and their provenance are in
`sources/silver-ace/`; the brushed roughness reuses the shared CC0 Metal009 map.

Albedo supplies alloy tones, markings and wear. Independent metallic and roughness
maps separate bare, polished and oxidised panels from dielectric paint and grip
strips; an OpenGL normal map supplies flush rivets and recessed panel joints.
These are artistic finish estimates. The skin adds no mesh geometry or emission.
At Low, metal/paint boundaries remain while normal and roughness detail are omitted;
the recorded roughness mean keeps the overall sheen. Returning to factory or
NEON RONIN restores its own material finish.

The stock wing and fin UV sharing still applies. Fin insignia are symmetric;
readable serials are on the two unwrapped fuselage flanks. Stabiliser tops and
some end caps sample a constant metal patch, so they cannot show separate rivet
detail. Dorsal/hatch/underside overlaps are retained. Validate with
`test_vehicle_paint.gd`, the two Stik families in `test_skin_fleet.gd` and native
1920 × 1080 review of the metal under changing view angles.

### Ugly Stik: BLACKBIRD (US-V21)

`build_stik_blackbird.py` generates an SR-71/A-12-inspired charcoal tribute for
all five Stiks. Four 2048-square maps describe dark thermal panels, flush rivets,
subtle titanium scuffs and sparse muted-red safety marks. The black coating is
dielectric; only exposed scuffs have metallic response. No emission or clearcoat.
Panel roughness varies; Low substitutes the recorded mean and omits normals.

Run with the pinned visual venv; `--check` verifies PNG bytes, authoring source
hashes, roughness mean and a coarse atlas red-area limit. The visual review must
still inspect visible red coverage. It reuses `MetalAtlas` authoring utilities,
the shared CC0 Metal009 roughness and bundled OFL Noto font. The inherited USAF
source is verified but no insignia is painted on BLACKBIRD.

Keep text on the separately mapped fuselage flanks. Wing and fin UVs are shared
and use geometric marks; stabiliser tops and some edges retain uniform charcoal
patches. Clearing height before an overlapping region is repainted keeps its
normal map consistent. Validate with `test_vehicle_paint.gd` and native
1920 × 1080 review of both sides and Low detail.

## Export and check

From an extracted kit, edit the paint images and run standard-library Python 3:

```sh
python pack_image.py --output my-design.orskin --label "My design"
```

A single-image kit also accepts an explicit PNG argument. The legacy X8 packer
calling convention remains supported. For Blender painting, run the embedded
exporter or use:

```sh
blender --background --factory-startup Aircraft.blend --python-exit-code 1   --python "Export OpenRC Skin.py" -- --output my-design.orskin --label "My design"
```

The exporter rejects geometry, UV, material-slot and unsupported-shader changes.
It emits only paint materials and PNGs, deduplicating shared textures. The image
packer checks bounded PNG decoding, dimensions, checksums, aggregate pixels and
atomic failure. The runtime independently validates the archive and exact stock
identity; it applies instance-owned materials to the verified model.

From the repository root:

```sh
python tools/skins/build_guide.py --check
python tools/skins/test_pack_image.py
python tools/skins/test_skin_kits.py
```

Use the [checked Godot runner](../godot/README.md) for:

- `res://tests/test_custom_skin.gd`: malformed archives, compatibility, isolation
  and existing X8 imports.
- `res://tests/test_skin_fleet.gd`: every catalog ID, import/selection, texture
  assignment, stock geometry and wrong-family rejection.
- `res://tests/test_procedural_skin.gd`: projected geometry, LODs, preserved shader
  coordinates and material properties. Re-encoding a copied Godot mesh can change
  normals/tangents by less than 0.0002; triangle positions remain unchanged.
- `res://tests/test_skin_tools.gd`, `test_livery_picker.gd`,
  `test_aircraft_liveries.gd` and `test_ui_preview_requests.gd`: dialog, selection
  and preview regressions.

The adapter compatibility hash binds the verified model manifest and adapter
source; Timber additionally binds the visual-detail layer used before mapping.
Exported applications carry those source proofs and the kit JSON. A changed
mapping requires regenerating identities, prepared scenes and kits together.

The [TT-21-R1 LOD repair](../../docs/research/timber-integration/TT-21/lods/README.md)
keeps the distributed Timber paint identity through one exact, reviewed old-kit/new
runtime-identity pair. Base geometry/paint mapping and existing kit bytes are unchanged;
unrelated identities and future source drift remain rejected. Its `source_sha256`
generation fingerprint is separately updated to the repeated pinned-engine export.

The Stik and Extra retain their distributed paint identities through separate
exact old-kit/current-model pairs. A same-engine comparison of the historical
assemblies found identical target paths, transforms, mesh arrays, UVs and materials
on all 19 Stik and 14 Extra paint surfaces. The Stik engine loading change leaves
its paint unchanged; the Extra propeller correction changes non-paintable geometry,
so its starter was regenerated to show the current propeller. Source fingerprints
were refreshed from repeated beta2 exports. The electric kit uses its own verified
overlay and adapter identity, and does not accept basic Stik packages.

## Evidence

US-V19, 2026-11-14: NEON RONIN was selected through the Spanish Home paint gallery
and reviewed in Home and flight at 1920 × 1080 on Windows, Godot 4.8-beta2,
GL Compatibility and an RTX 3090. Top, underside, opposite side and night views
confirmed atlas placement, the cyan ventral fin and emission confined to traces.
The visual session's final skin records match the workspace and frozen test input;
captures are outside Git at `D:/OpenRCsimulator-evidence/neon-ronin/`. The session
reported no error-level engine records; loading/catch-up hitches were present.
The checked `test_vehicle_paint.gd` run passed 1,621 assertions with zero engine
errors or warnings. The generator's three maps passed byte-exact `--check`.
These are visual checks, not a sustained performance qualification.

The original X8-only integration was checked on Windows on 2026-10-28 with Godot
4.8-beta1 and Blender 5.2.2. It passed 36 importer, 114 dialog, 285 picker, 179
stock-livery and 25 preview checks. The supplied shark image was subsequently
packaged without resizing and inspected at 1920 × 1080 in Home and a short flight;
it was usable with visible panel discontinuities and asymmetric markings.
See the [dated prompt findings](../../docs/research/aircraft-skin-prompts-2026-10-28.md).

Fleet evidence is retained under ignored `tmp/skin-standard-*` and checked-runner
reports under `tmp/godot-checks/`. ZIP tests exercise real image packing for every
family; Blender checks reopen all eight starters and export them. Review captures
stay outside Git. These checks establish source-workflow behavior, not published
desktop-package acceptance, image-generator reliability or flight-model validation.
A full `app/test.sh` run has not been claimed for this changing shared checkout.

Fleet integration on Windows, 2026-10-28: the checked runner passed 552 fleet,
3,458 mapping/LOD, 147 dialog (nine locales and all eleven kit selections),
36 importer, 285 picker, 179 stock-livery and 25 preview assertions. All eight
translation catalogs covered 2,573 source messages. The guide, seven PNG-packer
tests and two fleet ZIP/round-trip tests passed. The fleet comparison destroys
children before parents because simultaneous detailed Timber trees expose a
material-lifetime error during whole-subtree teardown in the dummy renderer;
engine diagnostics remain enabled.

Actual 1920 × 1080 debug-bridge runs loaded the helicopter skin through Home and
into its flight route, retained selection after restart, and rendered diagnostic
atlases on Extra, P-51 and Timber. Timber retained its custom paint in a short
flight and returned to stock paint afterward. Both owned rendered sessions ended
with no engine error records, crashes or leaked objects. Export-plugin parsing
passed; an exported application was not produced or qualified by these checks.

Release repair on Windows, 2026-11-09 (`755eb8813`): the checked fleet passed 628
assertions, packaged source proofs passed 339, and an isolated host loaded the
final PCK with 54 paint/resource assertions. Blender 5.2.2 reopened and exported
the regenerated electric and Extra starters; decompressed archive scans found no
local paths. Both exported paints were inspected in Home and the flight route at
1920×1080 using GL Compatibility on an RTX 3090, including moving controls.
The owned session stopped with no reported crash, leaked objects or error-level
records; hitches and experimental-aircraft warnings remain recorded. Evidence is
outside Git under `D:/OpenRCsimulator-evidence/release-skins/`. This does not
qualify a distributable executable, sustained performance or physical behavior.
