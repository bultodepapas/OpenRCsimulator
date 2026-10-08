# L10c flightline barrier data contract

Status: implementation contract, 2026-10-08. Step: L10c.

`openrc-field v1` keeps `flight_cues` optional. When present, it accepts zero to three cues, with at most one windsock, one pilot station, and one flightline barrier. Existing fields without the key retain their legacy normalized shape; a present empty array remains present and empty. Cue order is preserved.

A `flightline_barrier` cue has exactly `id`, `type`, `collides`, `north`, `east`, `width`, `height`, and `gap_width`. It requires `type: "flightline_barrier"` and `collides: false`. The five numeric fields are finite metre quantities with exact `{value, unit, kind, source}` metadata, known evidence kinds, and nonempty provenance. Coordinates remain limited to ±1,000,000 m. IDs share the field-wide uniqueness check, must be valid Godot node names, and cannot use generated field-child names including `NearGrass`, `Scenery`, and `FlightCueShadows`. Invalid cues reject the whole field.

Estimated visual bounds are width 10–80 m, height 0.5–0.9 m, and gap width 2–12 m; the opening must be at least 4 m narrower than the full width. These are implementation bounds, not surveyed dimensions or a safety standard. The default uses north 4.5 m, east 0 m, width 48 m, height 0.65 m, and gap width 6 m. The estimates are informed by [RC field layout research](../../scenery-investigations/03-rc-field-layout-references.md), which records club examples without establishing a standard.

The barrier row is level, fixed east–west, centered exactly on `pilot.east`, and at least 2 m north of the pilot. Its full-span conservative footprint is `width / 2 + 0.1 m` east–west and `0.14 m` north–south. The footprint must fit inside a flat rough surface, avoid runway and mown rectangles, and stay clear of the full windsock envelope. Only the exact 40 km square horizon rough surface applies the existing 1,500 m radial limit, checked at all footprint corners; custom rough rectangles remain flat without that limit. The row must also stay at least 1 m behind the referenced runway's near edge and clear a maximum-depth pilot station by at least 2 m plus margin.

Barrier height preserves a straight sightline from the pilot eye to ground at the referenced runway's near edge. On the flat field datum, the allowed top height is `eye_height × (runway_near_north − (barrier_north + 0.04 m)) / (runway_near_north − pilot_north)`. The estimated barrier top must remain at least 0.05 m below that line; the denominator must be positive. A field with a lower pilot eye or closer runway edge can therefore require a lower barrier or a different placement.

The visual is one opaque merged mesh with four open horizontal slats per bay, a central opening, small posts and fittings, no floor, collision, physics, process, or engine shadows. Slats begin at least 0.2 m above ground. Geometry stays within the nominal width, height, and 0.08 m face thickness, uses 1,320 triangles in the default field (fewer than 3,000 at the maximum custom width), and is rendered as one draw. `FlightlineBarrier.post_positions(cue)` supplies the same ordered local post centers to both geometry and contact-shadow generation.

Validation: `test_flightline_barrier_data.gd` 144 checks; `test_flightline_barrier.gd` 48; `test_windsock_data.gd` 121; `test_pilot_station_data.gd` 163. All passed headlessly on Godot 4.7.2.
