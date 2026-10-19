# Landscape contributor guide

Landscapes are selectable field presentations backed by validated `openrc-field v1` data. The catalog owns the
stable selection IDs; field data owns the pilot, contact surfaces and field objects. Start with the short
[landscape selection plan](plans/landscape-selection.md) and the [field contract](LANDSCAPE-PLAN.md).

## Catalog and adapters

`app/landscapes/catalog.gd` explicitly registers bundled landscapes. Adding files alone does not register them.
Its public API is:

```gdscript
const DEFAULT_ID := "club_field"
static func ids() -> Array[String]
static func has(id: String) -> bool
static func entry(id: String) -> Dictionary # {id, name, field_path}
static func build(id: String, field: Dictionary, lighting: Dictionary = {}) -> Node3D
static func collision_world(id: String, field: Dictionary) -> Dictionary # {ok, world, errors}
```

Each adapter lives in its landscape folder as `landscape.gd` and declares `ID`, `DISPLAY_NAME` and `FIELD_PATH`,
with `build(field, lighting = {}) -> Node3D` and `collision_world(field) -> Dictionary` methods. For new fields,
the folder name, adapter ID and `field.id` use the same unique snake_case ID. The `club_field` adapter is the
intentional exception: it keeps the existing `res://data/fields/default.json` path and legacy field ID `default`.
Do not move or rewrite the existing field, lighting, scenery or collision sources.

Use this layout; Green paradise is the minimal working example:

```text
app/landscapes/
  catalog.gd
  green_paradise/
    landscape.gd       # required: identity, renderer, obstacle adapter
    field.json         # required for a new field: openrc-field v1
    assets/            # optional: meshes/textures, licenses and provenance
```

The default adapter delegates to the current `FieldBuilder` and `SceneryCollisionSetup` paths. A new adapter
should reuse those shared systems where they fit. Add one `preload("res://landscapes/<id>/landscape.gd")` to
`Catalog.ADAPTERS`. Include `landscapes/*/*.json` (and any new asset file types) in all export presets. Store the
selected ID in preferences; resolve the ID through the catalog instead of persisting a path. Missing or stale
preference IDs recover to `club_field`; an invalid explicit `--landscape=<id>` is an error.

## Field data and the green landscape

Put field definitions beside their adapter. Validate them with `FieldLoader.load_from`; keep coordinates in local
NED metres and every authored quantity in `{value, unit, kind, source}` form. `app/data/fields/grass.json` is
`openrc-grass v1` placement data, not a field definition.

`green_paradise` uses one 40 km flat grass plane with the existing `Ground` grass material. Its field has no
objects, flight cues, rotorcraft pad or scenery collision proxies. It has no lake or water contact. Keep the
existing contact model's sub-centimetre grass microrelief; the visible mesh remains flat. Field v1 requires a
runway reference to a surface of type `runway`, so Green paradise keeps an unpainted logical runway rectangle.
The current friction table treats `runway` as grass (`grass_rwy`, friction factor 0.8 and rolling factor 2.5),
not pavement. Do not add runway paint or pavement to its renderer.

The validated field surfaces still drive `GroundSurfaces` and `FlightSession.set_field`; they are the ground
contact contract. `collision_world` supplies static scenery obstacle proxies only. It must not replace field
surface contact data or introduce render-mesh collision into simulation. Green paradise returns a valid empty
obstacle world. Keep the club adapter on the existing collision setup so its scenery, lights and identities stay
intact. The lake is tied to the exact default field identity; do not attach it to Green paradise.

## Rendering and selection

An adapter renderer returns a scene-local `Node3D` named `Field`. Preserve the existing field root and object
paths. Where lighting transactions apply, expose `lighting_materials` metadata as `Array[ShaderMaterial]` and
`lighting_snapshot` metadata. A supported lake renderer may also expose `lake_context`; Green paradise does not.
Pass lighting through to shared materials, and keep renderer state out of `app/sim/` and `app/physics/`.

The direct fixed-wing route accepts `--landscape=green_paradise`. Home's Landscape button cycles registered
choices, remembers the selected ID, and updates both the still backdrop and the next flight's field. Change the
selection on Home after ending a flight; do not switch the field of a live session. Green paradise starts fixed
wing aircraft airborne and the helicopter at a hover. Do not offer a helicopter pad start without a pad. Ground
vehicle courses remain independent of aircraft landscape selection.
Natural Random currently requires Club field; Green disables it with an explanation.

Do not recreate an asset that is already freely available. Reuse suitable assets only when redistribution is
allowed; retain their license, source and processing provenance with the asset. Never download assets at runtime.

## Verification

Run the pinned Godot import and verification commands in [TOOLS](TOOLS.md#developer-setup). Check
`test_landscapes.gd`, `test_field_integration.gd`, `test_ui_runway.gd` and `test_world_flow.gd`. For example:

```sh
<godot> --headless --path app --audio-driver Dummy --script res://tests/test_landscapes.gd
<godot> --path app --audio-driver Dummy --script res://tests/test_landscapes.gd -- --capture-landscapes=<absolute-dir>
```

Inspect both Home and flight captures. Verify Club → Green → Club, restart, saved selection, no leftover objects,
and nighttime lighting. Run the normal export smoke: `check_field_pack.gd` validates every registered field from
an empty project root, so missing exported JSON cannot fall back to source files.
[L21–L24 verification and captures](research/landscape-upgrade/L21-24/README.md) record the current results and limits.
