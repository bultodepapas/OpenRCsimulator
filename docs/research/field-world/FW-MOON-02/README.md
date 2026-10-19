# FW-MOON-02: Lunar state and reference fixtures

**Status:** engineering-verified 2026-10-19. Not yet wired to rendering, so captures and traces are unchanged.

- Code: [lunar.gd](../../../../app/render/world/lunar.gd), plus `distance_au` in [ephemeris.gd](../../../../app/render/world/ephemeris.gd) `sun()`.
- Test: [test_world_moon_lunar.gd](../../../../app/tests/test_world_moon_lunar.gd), 1102 checks.
- Fixture: [moon_reference_v1.json](../../../../app/tests/fixtures/moon_reference_v1.json) from [moon_fixtures.py](../../../../tools/world/moon_fixtures.py).
- Plan: [moon plan](../../../plans/moon.md).

## What `Lunar` provides

`Lunar.state(when)` and `Lunar.at_jd(jd, lat, lon, geocentric)` return, in float64:

- **Position:** apparent azimuth and elevation, plus whether the upper limb is above the horizon. The parallax is a rigorous vector calculation for an observer on a spherical Earth, and refraction is the same as `Ephemeris.sky()`.
- **Size and phase:** topocentric distance and angular radius; exact phase angle (Sun–Moon–observer); illuminated fraction and waxing.
- **Angles:** bright-limb angle χ, parallactic angle q, axis position angle of date.
- **Libration:** the sub-observer and sub-solar points.
- **Orientation matrices:**
  - `body_to_ned`: Moon-fixed to local north/east/down. Built from the IAU WGCCRE 2009 pole and prime meridian and IAU 1976 precession.
  - `sun_ned`: the direction from the Moon to the Sun, for the terminator.
- **Brightness:**
  - Kasten–Young airmass.
  - KS91 phase flux with inverse-square distance.
  - Earthshine: Earth geometric albedo 0.434 × Lambert phase × (R⊕/d)².
- **Eclipse geometry:** the geocentric umbra and penumbra (Earth radius 6371 + 88 km); umbral and penumbral magnitude; and the shadow axis and offset in moon radii, which the shader will use per pixel.

`Lunar.events(when)` finds rise and set (refracted upper limb) and transit for a local day. `Lunar.next_event(when, kind)` finds the next one, searching up to three days ahead. `Lunar.calendar(jd)` converts a JD back to a date.

## Results

Run: `"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_world_moon_lunar.gd`. Result: 1102/1102 checks passed.

| Reference | Quantity | Worst error | Tolerance |
| --- | --- | --- | --- |
| `Ephemeris.sky()` | direction (vector vs elevation-only parallax) | 0.008° | 0.01° |
| NASA SVS 5587, 120 rows of 2026 | illuminated fraction | 0.0004 | 0.001 |
| | diameter | 0.23 % | 0.4 % |
| | sub-Earth point (libration) | 0.090° | 0.15° |
| | sub-solar point | 0.022° | 0.05° |
| JPL Horizons, Madrid / Buenos Aires / Tromsø, 34 epochs including 2–4° elevation | position | 4.0′ | 5′ |
| | illuminated fraction | 0.0005 | 0.002 |
| | phase angle | 0.061° | 0.2° |
| | diameter, distance | 0.17 % | 0.4 % |
| | sub-observer point | 0.051° | 0.1° |
| | north-pole position angle | 0.022° | 0.1° |
| Horizons rise/transit/set, Madrid and Buenos Aires, 17 events | time | 1.23 min | 2.5 min (Horizons prints whole minutes) |
| | transit elevation | 0.014° | 0.08° |
| Espenak, 6 eclipses 2026–2028 | umbral magnitude | 0.031 | 0.05 |
| | time of greatest eclipse | 3.75 min | 6 min |

**Other checks:**
- KS91 at quarter: 0.09099.
- Perigee/apogee brightness: 1.246.
- Airmass: 1.000 at the zenith, 37.92 at the horizon.
- Earthshine at new moon lies inside the observed 3.6·10⁻⁶…3.6·10⁻⁴ band and fades toward full moon.
- `body_to_ned` is orthonormal with determinant +1.
- Lunar north points up from Madrid at transit and down from Buenos Aires (the southern-hemisphere view is "upside down").
- AstroPixels full and new moons give illuminated fraction > 0.998 and < 0.002, and the waxing flag flips at full moon.
- Calendar round trips work, including 29 Feb 2028 and the turn of the year.
- `next_event` crosses days and the turn of the year.

**Cost:** 125 µs per `at_jd` call on this VM (llvmpipe host, CPU only). That is fine at the 30 s flow step, but it should not be called every frame.

## Findings

1. **Decision M-D9 is resolved: no Meeus ch. 47 upgrade.** With Schlyter's series, eclipses land within 0.031 magnitude and 3.75 min of Espenak, well inside the plan's ±15 min need.
2. **The orientation model is right.** Libration, sub-solar point and axis angle agree with NASA and JPL within 0.1°. The 4′ position error is invisible on a 31′ disc.
3. **Exact phase.** The Sun–Moon–observer phase angle replaces the elongation approximation, cutting the error in illuminated fraction from 0.17 to 0.04 percentage points against SVS.
4. **Audit corrections** (in the [FW-MOON-00 record](../FW-MOON-00/README.md)):
   - Night clouds already follow the moon: in field-world mode the sky shader's `sun_dir` is the active light.
   - Moonlight ramps in smoothly through the sky table's direct beam from −0.5° to 0°; it does not pop at −1°.

## Limits

- The Earth is a sphere: observer height and the ellipsoid are ignored, which is below 0.1′ of parallax difference.
- Nutation and TT−UT are ignored.
- Eclipse limb darkening and the Danjon colour belong to FW-MOON-10.
- Re-running the fixture generator queries JPL again; the retrieval date is recorded.
