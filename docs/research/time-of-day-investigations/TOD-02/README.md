# TOD-02: fixed-time configuration and solar kernel

2026-10-10 · **Status: implementation integrated; focused tests pass; all post-integration app-check blocks pass across split execution.**

Step prefix: TOD. Owning plan: [TIME-OF-DAY-PLAN](../../../TIME-OF-DAY-PLAN.md). This report covers TOD-02a (validated configuration and fixed local time) and TOD-02b (float64 solar position and event presets).

## Configuration contract

`TimeOfDayConfig.DEFAULTS` and `defaults()` provide the complete legacy configuration:

```json
{
  "format": "openrc-lighting v1",
  "mode": "legacy",
  "date": "2026-03-20",
  "local_seconds": 43200,
  "utc_offset_minutes": 0,
  "latitude_deg": 0.0,
  "longitude_deg": 0.0,
  "location_name": "Reference field (synthetic)"
}
```

The coordinates and UTC offset are pinned hypothetical reference values, not a claim about a real field or the owner's club. All fields remain present in legacy mode. The offset is a fixed scenario value; daylight-saving and historical time-zone rules are outside v1. `defaults()` returns a deep copy.

`validate(raw)` rejects missing or unknown fields, wrong string/bool types, invalid Gregorian dates, non-finite coordinates, and values outside years 2000–2100, latitude ±90°, longitude ±180°, clock seconds 0–86399, and offset −720…+840 minutes. JSON has one numeric type, and Godot 4.7 parses even integer literals as floats. Therefore finite, exactly integral JSON numbers are normalized to integers; fractional values, booleans, non-finite values and out-of-range values remain errors. The normalized result does not alias its input.

`parse_time` accepts `HH:MM` or `HH:MM:SS`; invalid input returns −1. `format_time` omits seconds when they are zero and returns an empty string outside the day. `from_args` defaults to legacy; `--time-of-day` and/or `--date` imply astronomical mode, while `--lighting=legacy|astronomical` selects it explicitly. Explicit legacy mode cannot be combined with clock/date overrides. A full JSON `--lighting-config` cannot be combined with individual lighting flags. Config-file errors return validation errors and never write files. Relative file paths resolve from the Godot project root.

`preset(config, id)` returns the same `{ok, config, errors}` result shape. Dawn is the first rising crossing of geometric solar-center elevation −6°. Sunset is the descending crossing of −0.8333° (a conventional apparent-horizon event). Noon is the upper transit (hour angle zero), including at a pole where elevation can remain constant. Night chooses the minimum geometric elevation on that local date and fails unless it is below −18°. Missing polar crossings and astronomical darkness are reported; no event is manufactured.

## Solar method and limits

`SolarPosition.evaluate(config)` converts the fixed local date/time and offset to a UTC Julian date, then evaluates the [USNO approximate solar coordinates](https://aa.usno.navy.mil/faq/sun_approx) and the USNO true-north altitude/azimuth convention. It returns geometric center elevation, azimuth clockwise from true north, signed hour angle, UTC Julian date, and a unit north/east/down direction array. At the zenith, where azimuth is undefined, it returns zero by convention. The kernel uses scalar float64 GDScript math; it has no rendering vectors, colors, physics state, network calls, or new dependency. No atmospheric-refraction correction is applied to geometric elevation; only the sunset preset uses the conventional −0.8333° reference.

The USNO approximate method is intended for this bounded 2000–2100 product range. The sampled table comparisons below passed their stated rounded-value tolerances, but they are not a full-domain accuracy bound, a photometric test, or physical field validation. NOAA solar-noon rows add an independent event-time check. The NOAA comparison coordinates are used only to reproduce that published table and are not the simulator's reference field.

## Independent fixtures and checks

[`solar-oracles.json`](solar-oracles.json) records source URL, date, coordinates, offset, expected output, and tolerance for each published comparison. The USNO [one-day altitude/azimuth table](https://aa.usno.navy.mil/data/AltAz) reports these rounded 2024-03-10 samples at 0° latitude, 45° east longitude, UTC:

| UTC | USNO altitude | USNO azimuth | Use |
| --- | ---: | ---: | --- |
| 06:00 | 42.3° | 95.3° | Morning/eastward NED check |
| 09:10 | 86.2° | 179.4° | Near-zenith direction check; azimuth is ill-conditioned |
| 12:00 | 47.4° | 264.4° | Afternoon/westward NED check |

USNO values are rounded to 0.1°. Tests compare the full direction against a 0.09° angular tolerance and elevation against the rounding interval; they avoid treating near-zenith azimuth as a stable direction measure. The fixtures also verify UTC/JD conversion, identical instants expressed with different offsets, date rollover, finite unit directions, east/west sign, hemispheric seasons, zenith behavior, and polar geometry.

The [NOAA/GML 2024 solar-noon table](https://gml.noaa.gov/grad/solcalc/table.php?lat=-33.425&lon=-70.567&year=2024) lists 12:44:08 local standard time for 2024-06-21 and 13:40:26 local daylight time for 2024-12-21 at latitude −33.425°, longitude −70.567°. The event tests allow 45 seconds for each rounded table time and independently check that the selected instant has hour angle within 0.003°. NOAA's table is a computational comparison, not an observation or physical measurement.

[`lighting-config.json`](lighting-config.json) exercises full-config file loading with a non-default site, offset, and time. The test checks direct `validate(JSON.parse_string(...))`, strict fractional/bool rejection, the CLI conflict rules, missing-file errors, and that reading the fixture does not modify it.

Focused checks run with `$(app/get-godot.sh) --headless --path app --script res://tests/<test>.gd`: config passed 75 checks, solar passed 42, and the actual-Main session test passed 9 checks for copied selection, fixed light through simulation/pause/restart, and frozen visual context after the T-record seam. The session test reports the aircraft data loader's existing inertia warning; there are no engine errors. The pre-change baseline `app/test.sh` passed before TOD integration; all post-integration blocks pass across split execution ([integration record](../TOD-07/verification.md)). These checks are software-only; there is no rendered, target-hardware, pilot, or physical validation in TOD-02.

## Sources

- [USNO approximate solar coordinates](https://aa.usno.navy.mil/faq/sun_approx) — formula and stated domain/accuracy.
- [USNO altitude and azimuth](https://aa.usno.navy.mil/faq/alt_az) — true-north azimuth convention.
- [USNO rise, set, and twilight definitions](https://aa.usno.navy.mil/faq/RST_defs) — −6° civil twilight and conventional −0.8333° rise/set reference.
- [USNO one-day altitude/azimuth service](https://aa.usno.navy.mil/data/AltAz) — tabulated direction oracle, values rounded to 0.1°.
- [NOAA/GML solar calculator tables](https://gml.noaa.gov/grad/solcalc/table.php?lat=-33.425&lon=-70.567&year=2024) — independent solar-noon comparison times.

No source code, image, or other third-party asset was copied. The kernel adds no dependency and does not call an online API at runtime.
