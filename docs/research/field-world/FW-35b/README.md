# FW-35b · night kit v2: orientation strips, belly strip, landing light, modes

2026-10-13, at the owner's request ("mejora los leds y su funcionamiento"). Code: `app/render/world/aircraft_lights.gd`, `led_strip.gdshader`, `app/main.gd` ([L]), `app/render/crash/wreck.gd` (followers).

## Changes

- **Orientation strips:** warm-white strips run on both wing tops, traced on the model's own triangles like the FW-62 underside strips and seen only from above (`face_dir`). With the cyan undersides this gives the RC night convention of white for the top and cyan for the belly. A cyan belly strip follows the fuselage in its symmetry plane, completing the FW-35 item. It starts at the station nearest the wing and continues fore and aft only within a 3 cm step, so gear legs, the tail skid and the propeller zone never take it.
- **Landing light:** the light moves from the centre of the leading edge, where it lit the propeller disc and engine as a large white halo, to the left wing's leading edge at 36 % of the semispan, under the skin. Its 16° beam clears the Stik's propeller disc by 35 mm, and a small lamp sprite marks the light.
- **Modes:** [L] cycles ALL → NAV (navigation and strobes only) → OFF. In daylight the first press fits the kit, which shows as faint dots at its physical brightness. The help row reads "[V] [L] Ground shadow · night lights"; the shorter text keeps Help within 600 px in both languages.
- **Crash:** each light records the part it is mounted on (`crash_follow`, the smallest mesh box holding it) and `crash_no_bounds`. The wreck twin mounts it on that part, so wing strips fly with their wing half, and the 1 m light quads no longer inflate the wreck's collision boxes — before this change the airframe box grew at night.

## Evidence

- Left: before; right: after, closeup camera at t = 1.5 s. [Night](night-closeup-ab.png): the halo is gone and the white top strips draw the wing at night. [Blue hour](blue-hour-closeup-ab.png). [Hashes](SHA256SUMS).
- `app/tests/test_night_kit.gd` 26/0:
  - fleet top strips above the undersides;
  - the Stik belly strip on the fuselage underside and 0.88 m long;
  - landing light position and beam clearance;
  - the three modes;
  - host and no-bounds metadata;
  - the wreck's airframe box unchanged by the kit;
  - the wreck's left strip riding on the left wing.
- Also passing:
  - `test_world_field_lights` 49/0;
  - the GPU `capture_aircraft_lights.gd`, with no failures;
  - `test_ui_help`;
  - the crash suites.

## Open

- Assigning the light mode to a radio AUX switch, using the smoke AUX assignment pattern, needs an owner decision on the channel.
- Owner night-flight review on the target monitor.
