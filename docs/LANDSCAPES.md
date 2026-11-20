# Add a landscape

Landscapes are bundled field presentations backed by validated `openrc-field v1` data.
Use [Green paradise](../app/landscapes/green_paradise/) as the minimal working example.
The separate [implementation plan](plans/landscape-selection.md) describes integration and release gates.

## Import Phoenix scenery

Open **Home → Flight → Import scenery** beneath the landscape selector. Choose a Phoenix installation,
site folder, `.pxf` descriptor or ZIP, including ZIP64. Large ZIPs are indexed without extracting
their contents. Select a result to load its six faces. Drag to look
around if the seams match, or use the numbered buttons to inspect the individual faces. Choose
**Install preview** to keep the scenery in the local library. Installed previews reopen even if the
source folder is disconnected. Removal asks for confirmation. Preview conversion uses up to
1024 pixels per face and rejects source panels that exceed the decoder's size limits.

For the calibrated revisions of Airfield, Aircraft Carrier X98, Frönäs, Farmland and Aero Club
Dolores, install the preview and choose **Fly calibrated runway**. The importer verifies the site's
revision and six images. It starts the selected runway-capable airplane in the calibrated direction
using a fixed pilot eye and calm practice conditions. The calibration uses estimated geometry and
contact properties. It covers the launch strip and leaves source terrain, obstacles, water and
landing fidelity unqualified. Other revisions remain available to preview, including recognizable
InfinityScape titles. The built-in landscape selector still controls ordinary Home flights.
[Compatibility and remaining work](plans/phoenix-scenery-import.md)

## Files and registration

```text
app/landscapes/
  catalog.gd
  green_paradise/
    landscape.gd       # required adapter
    field.json         # required definition for a new field
    assets/            # optional meshes/textures, licenses and provenance
```

Use a unique snake_case ID for the folder, adapter `ID` and `field.id`; use a readable
`DISPLAY_NAME` such as “Green paradise”. Club field deliberately retains its legacy
field ID `default` and `res://data/fields/default.json`. Keep its assets and sources in place.

Add one `preload("res://landscapes/<id>/landscape.gd")` to `ADAPTERS` in
[catalog.gd](../app/landscapes/catalog.gd). Registry order is selector order; Club stays first/default.
Folders are not discovered automatically. Preferences store the ID; stale IDs recover to Club,
while an unknown explicit `--landscape=<id>` is refused.

Field JSON contains `format`, `id`, `runway`, `pilot`, `surfaces` and `objects`.
Coordinates are local NED metres; quantities use `{value, unit, kind, source}`.
Use `FieldLoader.load_from(path)` to validate and normalize them. Optional objects/cues/pads
must satisfy that loader's contract. `data/fields/grass.json` is grass-placement data, not a field definition.

## Adapter interface

```gdscript
extends RefCounted
const ID := "green_paradise"
const DISPLAY_NAME := "Green paradise"
const FIELD_PATH := "res://landscapes/green_paradise/field.json"

static func build(field: Dictionary, lighting: Dictionary = {}) -> Node3D:
    var root := Node3D.new()
    root.name = "Field"
    # Add scene-local meshes and lighting metadata; see the working example.
    return root
static func collision_world(field: Dictionary) -> Dictionary:
    return {ok = true, world = {}, errors = PackedStringArray()}
```

Follow the working adapter's method bodies. Reuse existing builders and materials where suitable.
Preserve field/object node names. For shared lighting updates, expose `lighting_materials`
as `Array[ShaderMaterial]` and `lighting_snapshot` metadata; pass the supplied lighting to materials.
A lake renderer also supplies matching `lake_context`. Obstacle proxies must agree with visible objects.
Validated field surfaces separately feed ground contact; rendering must not change simulation state.

Green builds one 40 km flat grass plane with the existing Ground material. It has no objects,
cues, near-grass geometry, pad, lake or obstacle proxies. Field v1 requires a logical runway
rectangle; Green leaves it unpainted. Its `runway` contact is maintained grass, not pavement.
The existing sub-centimetre grass contact microrelief remains; the visible mesh is flat.

Reuse suitable freely available assets with redistribution rights; retain source, license and
processing provenance. Include `landscapes/*/*.json` and any new asset file types in every export preset.

## Use and validation

Home's Landscape button updates the backdrop and remembers the next flight's landscape.
Switch through Pause → End flight → Home. Direct launch: `--landscape=green_paradise`.
Green supports airplane airborne starts and helicopter hover; Natural Random requires Club.
Truck courses remain separate.

Use the [pinned engine and import workflow](TOOLS.md#developer-setup), then run:

```sh
<godot> --headless --path app --audio-driver Dummy --script res://tests/test_landscapes.gd
<godot> --path app --audio-driver Dummy --script res://tests/test_landscapes.gd -- --capture-landscapes=<absolute-dir>
```

Inspect both Home and flight captures. Check Club → Green → Club, restart, saved relaunch,
lighting, resources and absence of leftover contacts. Also run `test_field_integration.gd`,
`test_ui_runway.gd` and `test_world_flow.gd`. The normal export smoke's `check_field_pack.gd`
validates all registered fields from an empty project root.
[Verification, captures and current limits](research/landscape-upgrade/L21-24/README.md).
