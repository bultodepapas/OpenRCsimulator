# L10b field cue data contract

Status: implementation contract, 2026-10-08. Step: L10b.

openrc-field v1 keeps flight_cues optional. When present, the array accepts zero to two cues: at most one windsock and at most one pilot_station. Fields without this key retain their legacy normalized shape; a present empty array remains present and empty. Cue order is preserved.

Each cue has an exact schema selected by its type. Windsocks keep the L10a keys and behavior in the [L10a data contract](../L10a/data-contract.md). A pilot_station has exactly id, type, collides, north, east, width, depth, and height. It requires type: "pilot_station" and collides: false; its dimensions and coordinates use {value, unit, kind, source} quantities in metres. All quantities are checked for exact metadata, known evidence kind, finite numeric values, and nonempty provenance. A cue cannot include keys belonging only to the other cue type.

Cue IDs share the field-wide uniqueness check, must be valid Godot node names, and cannot use the generated NearGrass or Scenery child names. Coordinates are limited to ±1,000,000 m. Invalid cues fail the whole field; no partial normalized field is returned.

The station is centered exactly on the pilot's north/east coordinates, with pilot.down == 0 m. Its fixed world orientation has the front/barrier facing north and the open rear facing south. width spans east-west and depth spans north-south. The full outer width/depth include the small frame fittings and pad. The station top must remain at least 0.4 m below pilot.eye_height.

Policy dimension bounds are estimated for a compact visual station: width 1.2–2.4 m, depth 1.0–2.0 m, and height 0.6–0.9 m. The layout references are recorded in [RC field layout research](../../scenery-investigations/03-rc-field-layout-references.md); none of these dimensions is claimed from a current standard. These are layout bounds, not measurements or structural ratings.

For ground placement, the conservative horizontal envelope radius is hypot(width / 2, depth / 2) + 0.1 m. The added 0.1 m is conservative clearance around that footprint; all fittings are already included in it. This envelope must fit inside a rough surface and avoid runway and mown rectangles. On the exact 40 km square rough surface, its center plus envelope must remain within 1,500 m of the rough center, matching the existing relief limit. Custom rough surfaces remain flat and do not use that relief limit.

This schema adds visual field data only. It does not enable collisions or physics.
