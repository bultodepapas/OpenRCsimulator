# Aircraft skin toolkit

The registry at `app/assets/skin-kit/models.json` covers eight visual families:
Ugly Stick (four engine configurations), Extra 300S, P-51D, Corsair, Vantage Jet,
Turbo Lumber, X8 and HX-700/X-Cell. Kits use the same paint bindings as the runtime.
See [the skin contract and player flow](../../docs/AIRCRAFT-SKINS.md).

## Generate

Run `python tools/skins/build_guide.py` and `--check` first. The guide includes
all nine simulator languages, image and Blender prompts, and community submissions.

The three procedural families and Turbo Lumber need a prepared scene. Run the
checked Godot exporter for each of `jensen-das-ugly-stik-60`, `gp-extra-300s-60`,
`p51d-mustang-120`, and `turbo-lumber-evolution`:

```powershell
$GodotWindows = (Resolve-Path '.tools/Godot_v4.8-beta1_win64_console.exe').Path
python tools/godot/run_checked.py --timeout 180 -- $GodotWindows --headless --path app --audio-driver Dummy --script ../tools/skins/export_procedural.gd -- <family> <absolute-output-directory>/<family>.glb
```

Create the output directory first. The exporter validates the stock model before
copying it, applies the same paint mapping as the runtime and reports its identity.
The neutral six-view starters for Extra, P-51 and Timber are not stock-paint bakes;
unchanged packaging yields neutral paint. Projection overlaps and seams are
intentional limitations documented in the guide. Ugly Stick retains its existing
covering atlas. Hidden maintenance/fracture subtrees are omitted from the editable
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

## Evidence

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
