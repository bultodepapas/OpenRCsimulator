# RCV airfield track: siting and design research

Date: 2026-10-14  
Status: placement review and design estimates; no implementation or physical validation.

## Siting

The default field data puts the runway at N=15 m, E=0, with a 100 m east-west length and 12 m north-south width. Its rectangle is therefore N=9–21 and E=−50–50. These source values are marked estimated in the field file, so the derived site clearances are estimates too ([field data](../../../../app/data/fields/default.json)).

The proposed capsule box, N=36.2–53.8 and E=−20.8–20.8, leaves 15.2 m north of the runway edge. A dirt approach at E=−10 from N=21 to 39 begins at the runway’s north edge, stays clear of the runway rectangle, and can meet a gate on the south straight. The explicit placements in [default scenery](../../../../app/data/scenery/default.json) do not enter either box or approach: the nearby pavilion is at N=−22 and pit shelters at N=−18.5. The [lake bank data](../../../../app/data/fields/lake.json) has an N/E bounding box starting at N=76, E=74; its conservative diagonal gap from the capsule box is about 58 m. No fixed scenery or lake conflict was found. Procedural ground cover still needs a clear-area check in the rendered field.

The scenery profile places this site inside its flight-box region and caps props there at an estimated 1.5 m ([scenery data](../../../../app/data/scenery/default.json)). Keep walls, berms and dressing low; that cap is a project estimate, not an aviation standard.

One footprint detail: the capsule dimensions above are 41.6 × 17.6 m, which is more elongated than the requested roughly 35 × 28 m. It fits the field. If the original footprint is important, a rounded rectangle with outer bounds E=±17.5, N=31–59, 6 m corner radii, a 3.2 m lane and 1.2 m shoulders fits 35 × 28 m and keeps a 10 m runway gap.

## Vehicle-scale guidance

The values below are estimates for this simulator’s truck and stated maximum speed of about 4 m/s; they are not published RC track standards.

- A 6 m bend radius at 4 m/s gives about 2.7 m/s² lateral acceleration. A simple steady-turn calculation gives a roughly 15° balancing bank angle. Start around 12–18° and blend each bank smoothly into the straights; tire grip and suspension will change the actual limit.
- The proposed 3.2 m lane and 1.2 m shoulders leave room for steering error and recovery. Use one continuous outer wall with an entry gate, and keep the wall profile rounded and low.
- The pair of 0.22 m and 0.32 m tabletops are plausible small-play features. Keep their takeoffs smooth, leave several metres for landing before the next turn, and avoid placing a jump in a banked curve. Traxxas’s T-Maxx manual advises keeping the nose up and landing level on all four wheels; its shock guide explains how suspension absorbs a jump landing and settles afterward.
- Three rollers around 0.12 m high, spaced at least 3 m apart, give a controllable rhythm section. Velosolutions specifies a 3 m minimum roller spacing and a 4 m standard corner radius for human pump tracks, and says turn radius should grow with entry speed. Those are useful shape references only; the 0.12 m roller height and RC layout are estimates.
- Keep the infield slalom as a deliberate shortcut/practice branch with clear merge points. Avoid an uncontrolled crossing or bridge: the current road representation samples a single ground surface.

The [Velosolutions pump-track standards](https://velosolutions.com/velosolutions-pump-track-standards/) supply the roller-spacing and speed/radius references. Traxxas primary sources are the [T-Maxx owner’s manual](https://traxxas.com/media/productattach/C-49077-3/2/kc2892-r01-49077-3-t-maxx-tqi-owners.pdf) and [shock tuning guide](https://traxxas.com/news/suspension-tuning-guide-part2).

## Reuse and asset scope

Use the project’s existing gravel shader and ground/path materials ([gravel shader](../../../../app/scenery/gravel.gdshader), [ground materials](../../../../app/render/ground.gd)). The rideable rollers, tabletops, berms and walls should be represented by the same course/terrain data that drives contact; a decorative mesh that disagrees with that surface would mislead the driver.

Do not model new cones or barrier props. If the course needs those decorations, [OpenGameArt’s Traffic Road Assets](https://opengameart.org/content/traffic-road-assets) is a low-poly CC0 pack that includes cones, crush barriers and roadblocks. [Kenney Road Textures](https://kenney.nl/assets/road-textures) is another CC0 source for simple surface details; Kenney confirms its asset pages use CC0 on its [license FAQ](https://kenney.nl/support). Reuse only the needed files and retain their license/source record.
