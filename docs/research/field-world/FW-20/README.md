# FW-20 — Ephemeris (sun, moon, sidereal time)

**Status:** engineering-verified 2026-10-10. Code: [ephemeris.gd](../../../../app/render/world/ephemeris.gd). Test: [test_world_ephemeris.gd](../../../../app/tests/test_world_ephemeris.gd) (28 checks).

## What was done

Float64 GDScript (no `Vector3`/`Basis`): Julian Day, Greenwich sidereal time (Meeus eq. 12.4), apparent sun (NOAA solar-calculator formulas after Meeus ch. 25), moon (P. Schlyter's elements with 12 + 5 + 2 perturbation terms), topocentric lunar parallax, Bennett/Saemundsson refraction, phase from the sun–moon elongation.

## Results (`--verbose`, offset from the reference)

| Check | Reference | Offset |
| --- | --- | --- |
| JD, GMST (Meeus 7.a, 12.a, 12.b) | published | 0.000000 |
| Sun RA / dec 1992-10-13 (Meeus 25.a) | 198.38083° / −7.78507° | −0.000005° / 0.000000° |
| Sun dec at the 2024 March equinox / June solstice | 0° / 23.436° | +0.0005° / +0.0026° |
| Moon RA / dec 1992-04-12 (Meeus 47.a) | 134.688470° / 13.768368° | −0.023° / −0.004° |
| Moon ecliptic longitude / latitude / distance | 47.a | −0.015° / −0.010° / −0.05 Earth radii |
| Moon illuminated fraction (Meeus 48.a) | 0.6786 | −0.0013 |
| 2024-04-08 total eclipse from Dallas, mid-totality | sun and moon overlap | separation < 0.25° (passes; checks sidereal time, horizontal frame and parallax together) |
| Solstice noon at 40° N | 73.44°, due south | +0.003°, +0.24° azimuth |

## What it does not prove

ΔT (TT − UT, ~1 min) is ignored: < 0.01° for the sun, ~0.5′ for the moon. Precession of the star catalogue is handled in FW-24, not here. Positions are visual inputs; nothing in `sim/`/`physics/` reads them.

## Reproduce

`$(app/get-godot.sh) --headless --path app --script res://tests/test_world_ephemeris.gd -- --verbose`
