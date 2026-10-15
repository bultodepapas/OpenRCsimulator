# R09 — Explicit standard atmosphere column

**Status:** implemented; focused deterministic checks pass 2026-10-14. **Scope:** the new `standard_column` weather mode is an explicit, dry lower-atmosphere reference profile. It is not a sounding, a local forecast, or a claim about observed field conditions.

## Model and bounds

The kernel uses the same standard-atmosphere constants and geopotential conversion already recorded in [M5-ATM-1 source evidence](../../../atmosphere/M5-ATM-1/sources/README.md) and the [M5-ATM-1 kernel notes](../../../atmosphere/M5-ATM-1/kernel/README.md):

```text
h = Re·z/(Re+z)
T = T0 − L·h
p = p0·(T/T0)^(g0/(Rd·L))
rho = p/(Rd·T)
```

Here `z` is geometric altitude and `h` geopotential altitude. The constants are `p0=101325 Pa`, `T0=288.15 K`, `L=0.0065 K/m`, `g0=9.80665 m/s²`, `Rd=287.05287 J/(kg·K)`, and `Re=6356766 m`. The standard-atmosphere references define the lower layer in geopotential altitude; the supported geometric top of 11000 m maps to about 10981 m geopotential, inside that tropospheric layer. The application domain is explicitly `−500 ≤ z ≤ 11000 m`; a query outside it fails rather than clamps.

The profile is dry: vapor pressure is zero, total density equals dry-air density, and both density ratio and first-order engine charge ratio use the existing rounded literal reference `1.225 kg/m³` as denominator. Recomputing sea-level density from the gas equation gives `1.225000018124288 kg/m³`, about `1.81×10⁻⁸ kg/m³` above the preserved literal. The literal reference and every v1/v2/v3 uniform path stay unchanged.

Weather `openrc-weather v4` has the same wind, gust, turbulence, and five atmosphere fields as v3. It is the only weather version that accepts `atmosphere_mode="standard_column"`; v3 keeps its historical `reference` and `custom` modes and diagnostic text. In the column mode, all five fields remain validated and serialized, but only `field_elevation_m` affects the physical profile. Temperature, QNH, and RH are inert draft settings in this mode. The field datum retains the existing −500 to 4000 m bound. At a body state, geometric altitude is `field_elevation_m − down_m` (NED down is positive).

`WindField.atmosphere(down_m)`, `air_density(down_m)`, and `engine_charge_ratio(down_m)` evaluate the same pure column sample. A failed atmospheric query returns an error dictionary; its scalar density and charge accessors return `NAN` so flight integration can fail closed. `has_atmosphere()` denotes an active non-reference atmosphere, including the column; `has_vertical_atmosphere()` selects specifically v4 `standard_column`. The law identifier is `standard-column-dry-isa-troposphere-v1`; uniform fields keep `uniform-field-qnh-isa-buck-liquid-v1`.

## Independent values

[`reference_check.py`](reference_check.py) independently evaluates the equations without importing app code. [`reference_results.json`](reference_results.json) contains its constants and full precision outputs. The integrated GDScript test checks these values, both closed bounds, invalid/out-of-domain inputs, local continuity, field-elevation/down-offset equivalence, inert draft values, and v1/v2/v3 compatibility. Captured Godot output is in [`test_atmosphere_column.log`](test_atmosphere_column.log).

| Geometric altitude (m) | Temperature (K) | Pressure (Pa) | Dry density (kg/m³) |
| ---: | ---: | ---: | ---: |
| −500 | 291.400255653240 | 107478.006754987 | 1.28489542200680 |
| 0 | 288.150000000000 | 101325.000000000 | 1.22500001812429 |
| 50 | 287.825002556311 | 100725.787237187 | 1.21913067767820 |
| 500 | 284.900255613026 | 95461.285491468 | 1.16727328495126 |
| 1000 | 281.651022371695 | 89876.277602342 | 1.11165967369969 |
| 11000 | 216.773512704456 | 22699.936837004 | 0.364801436835383 |

## Verification

Focused command:

```powershell
& ./.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script res://tests/test_atmosphere_column.gd
```

Result: **83 checks, 0 failed**. This checks the column kernel and weather/field behavior; it does not establish physical validation against a measured atmosphere or aircraft response.

Primary references are the [NOAA/NASA/USAF U.S. Standard Atmosphere, 1976](https://ntrs.nasa.gov/api/citations/19770009539/downloads/19770009539.pdf) and NASA's [NDARC Theory Manual](https://rotorcraft.arc.nasa.gov/Publications/files/NDARCTheory_v1_6_938.pdf). Their role in the pre-existing M5 model and the scope of the constants are summarized in the linked M5-ATM-1 source evidence. The profile's use here is bounded to the lower troposphere and a controlled baseline, not local atmospheric prediction.
