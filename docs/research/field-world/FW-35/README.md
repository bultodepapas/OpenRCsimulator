# FW-31…35 — Field lights and the aircraft night kit (first slice)

**Status:** engineering-verified 2026-10-10; owner's night flight pending (Gate FW-N). Code: [field_lights.gd](../../../../app/render/world/field_lights.gd), [lights.json](../../../../app/data/fields/lights.json), [aircraft_lights.gd](../../../../app/render/world/aircraft_lights.gd), [light_sprite.gdshader](../../../../app/render/world/light_sprite.gdshader). Test: [test_world_field_lights.gd](../../../../app/tests/test_world_field_lights.gd) (25 checks).

## What was done

- **Data (FW-31):** `openrc-field-lights v1`, every value `{value, unit, kind, source}`. Two 8 m LED floods (30,000 cd, 60°, 5,000 K) behind the pilot line aimed at the runway, a floodlit windsock (after FAA L-807), solar stakes along both runway edges every 20 m, green stakes across both ends (artistic borrowing), and a red lamp on the pilot station (red keeps dark adaptation). The loader refuses 11 kinds of malformed files, including more than four floods.
- **Floods (FW-34):** shadowless `SpotLight3D`s (energy = cd / 10⁵ lux), poles and glowing heads. Compatibility lights at most 8 spots per mesh and the ground is one mesh: floods (3) plus the landing light stay inside it, so the analytic light pools (FW-32) were not needed yet.
- **Points (FW-33):** one sprite shader for every lamp: physical core size and radiance, a minimum on-screen size with flux conservation (a light vanishes by day and blazes at night, as real ones do), a display cap that keeps saturated hues from clipping to white, flashing on `sim_clock`, and output encoded for the engine's ALBEDO linearisation.
- **Night kit (FW-35):** fitted from dusk to any catalog aircraft from its own bounds (no model file or node touched): red left / green right tip lights, white tail light, white tip strobes double-flashing each second, and a forward landing light. Belly strips were tried and dropped: the bounds include wheels and propeller, so a strip floated below the gear. They need per-model anchors (D-8).
- **When:** field lights and stars from a sun below 3° and 2°, the kit below 6°, only in time-of-day mode.

## Results

- Captures: floods light the runway and windsock; the exposure adapts to 8 % of the lit field's illuminance (moonless night 90,000 → 12,893), so the lit area reads while stars and the moonlit sky stay visible. The ground directly under the floods still clips in the close-up (tuning for Gate FW-N).
- The kit's tip lights read as red and green points from the pilot's eye at 30 m once held at 4 px; before the display cap and encoding fix they were white or invisible.
- `World.build` builds none of this in the legacy mode or at noon (tested).

## What it does not prove

Light counts and per-pixel cost on the owner's GPU (FW-30 still open). Whether the kit is enough to judge attitude at 150 m at night: that is Gate FW-N's question, and the belly strips are expected to matter.

## Reproduce

`$(app/get-godot.sh) --headless --path app --script res://tests/test_world_field_lights.gd`; `tools/world/capture_times.sh <out> night night_dark` (pilot and close-up views).
