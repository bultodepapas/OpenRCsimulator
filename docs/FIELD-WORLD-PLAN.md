# Field world: current composition and open work

2026-10-12 · Revision 4 · Step prefix: **FW** · Gates: **FW-U** and **FW-N**

**Status:** FW-01/02 deliver the shared world composer and byte-stable parity. The conditions resolver, Home time choice, dusk flow, night sky and field lights are present in the app. Remaining work is field/data consolidation, night refinements, target-hardware cost and owner flight acceptance. Both gates remain open.

**Owns:** app/render/world, sky data, field-light data, world tools and world tests listed in the [track registry](README.md#step-id-namespaces). It coordinates shared shader, field, scenery, UI and aircraft-light hooks with their owners.

## Try the current time controls

Home saves a time choice. The Evening choice starts at golden hour and advances the world at 20× simulation time; Day selects the calibrated fixed-sun scene. Technical launch arguments take precedence over environment values and Home preferences.

    $(app/get-godot.sh) --path app -- --quick-flight --time_of_day=golden_hour
    $(app/get-godot.sh) --path app -- --quick-flight --time_of_day=golden_hour --time_scale=20
    $(app/get-godot.sh) --path app -- --quick-flight --time=18:30 --date=2026-06-21 --lat=40 --lon=-3.7 --utc_offset=2

Available named presets include dawn, sunrise, morning, noon, afternoon, golden_hour, sunset, blue_hour, night and night_dark. Without a resolved time, direct technical launches preserve the calibrated 225° azimuth / 45° fixed sun for parity. That fixed reference is not described as astronomical noon.

## Current implementation

- FW-01/02 use the same World.build/update path for flight, Home, scenery views and the runway scenario. The parity tool covers 89 views plus trace content; two runs match. See [FW-02 evidence](research/field-world/FW-02/README.md).
- FW-20–24 provide float64 sun/moon ephemeris, an offline sky table, shared sky/ground/grass haze, time-dependent light and exposure, and geometry-based stars. See [FW-20](research/field-world/FW-20/README.md), [FW-23](research/field-world/FW-23/README.md) and [FW-24](research/field-world/FW-24/README.md).
- FW-27's saved Home choice is implemented. FW-61's named Evening flow is implemented in the world and has a focused deterministic test; its full clock/checkpoint lifecycle remains under TOD-09c2.
- FW-31/33/34 provide validated field-light data, lamp sprites, club floods and a lit windsock. Aircraft navigation lights, strobes and landing lights are in the first slice. Wing underside strips are now derived from model triangles (FW-62); a fuselage belly strip still needs model anchors. [FW-35 evidence](research/field-world/FW-35/README.md).
- FW-62-R1 fixes dark wing blocks in zoomed dusk flights. Strip and point-light sizes use the current projection and viewport; strips add light without opaque coverage and fade out from above. The rendered regression covers the fleet, zoom, resolution and foreground occlusion; [diagnosis and proof](research/field-world/FW-35/README.md#2026-10-13--fw-62-r1-distant-wing-blocks).
- No chosen-time request keeps the fixed legacy sky. Explicit time changes are visual state and do not alter flight physics.

## Remaining work

| ID | Work remaining | Status |
| --- | --- | --- |
| FW-03 | Fold visibility, scenery selection and other world conditions into one resolver. | Partial: time/date/place and presets resolve; flags and data layer remain outside it. |
| FW-04–09 | Consolidate field layers, shader/hash utilities, contact-shadow and palette decisions, and scenery quality controls. | Open; keep existing field layouts and byte-parity contracts while each owning track is coordinated. |
| FW-25/26 | Finish cloud behavior below the horizon and evaluate credible dark adaptation without harming lit objects. | Partial; night cloud shadows and per-pixel scotopic response remain incomplete. |
| FW-30 | Measure local-light cost on the supported target GPU. | Open; llvmpipe proves repeatability, not hardware performance. |
| FW-35 | Complete and review the aircraft night kit. | Partial; wing underside strips under FW-62; FW-35b (2026-10-13) adds white top strips, the fuselage belly strip, a landing light clear of the propeller, [L] ALL/NAV/OFF modes and crash-wreck mounting ([evidence](research/field-world/FW-35b/README.md)); radio AUX switch and owner night-flight review remain. |
| FW-36 | Blinded readability review at dusk, moonlight and dark night, with and without the kit. | Open; Gate FW-N evidence. |
| FW-61 | Complete the evening time-flow step record and lifecycle review. | Runtime flow and focused test exist; the full anchored TOD-09c2 contract remains open. |

FW-32 light pools were not needed for the first slice. Additional village, traffic, wind-turbine and club lighting is parked behind Gate FW-N; it is not required to review the current night kit.

## Acceptance and research

Gate FW-U asks whether one field can be composed without changing existing visuals or traces. Gate FW-N asks whether a pilot can fly a complete dusk/night session and read the aircraft. Engineering captures do not close either owner decision.

The principal retained evidence is [FW-02 parity](research/field-world/FW-02/README.md), [ephemeris](research/field-world/FW-20/README.md), [night rendering](research/field-world/FW-23/README.md), [stars](research/field-world/FW-24/README.md), [field lights/night kit](research/field-world/FW-35/README.md), and the [2026-10-10 source research](research/field-world/web-research-2026-10-10.md). Current implementation is in app/render/world and app/tests/test_world_*.
