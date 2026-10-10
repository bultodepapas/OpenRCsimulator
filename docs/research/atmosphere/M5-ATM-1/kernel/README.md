# M5-ATM-1 kernel

**Status:** implemented and checked 2026-10-09. **Step:** M5-ATM-1. **Code:** [`atmosphere.gd`](../../../../../app/physics/atmosphere.gd); standalone checks: [`test_air_density.gd`](../../../../../app/tests/test_air_density.gd).

`Atmosphere.evaluate(elevation_m, temp_c, qnh_hpa, rh_percent)` evaluates one uniform field-level atmosphere. Inputs accept finite integers or floats only. It returns `ok`, `errors`, station pressure, absolute temperature, vapor pressure, total moist density, dry-air density, `sigma`, dry-air `engine_charge_ratio`, and density altitude. Invalid types, non-finite numbers, or values outside the declared ranges fail without returning partial physics data.

| Input | Accepted range | Meaning |
| --- | ---: | --- |
| Geometric field elevation | −500 to 4000 m | Height above mean sea level |
| Field temperature | −20 to 45 °C | Ambient temperature at the field |
| QNH | 870 to 1085 hPa | Sea-level-reduced altimeter setting |
| Relative humidity | 0 to 100% | RH relative to liquid water, including supercooled water below 0 °C |

These bounds define the simulator input envelope. They are not claims about the validity limits of the standard atmosphere or saturation-pressure equations. The RH convention is part of the interface: a provider reporting RH over ice below freezing must convert it before calling this kernel. The Buck liquid-water curve is used through the subzero range; measurements of supercooled water are limited, so winter humidity derived this way has less physical certainty than the equation's smooth output suggests.

The pressure estimate converts geometric elevation to geopotential height, then reduces QNH through the ISA tropospheric profile:

```text
h = Re·z/(Re+z)
T_ISA = T0 − L·h
p = QNH·100·(T_ISA/T0)^(g0/(Rd·L))
```

This is a standard-atmosphere reduction from QNH to estimated field pressure. The supplied field temperature changes density; it does not alter that pressure reduction. It is not a claim that real weather follows an ISA temperature profile or hydrostatic column.

Buck's updated liquid-water saturation pressure is `es = 611.21·exp((18.678 − t/234.5)·t/(257.14+t))` Pa. With RH expressed as a fraction, `e = RH·es`; for the percentage input, this is `e = (RH_percent/100)·es`. The ideal partial-pressure mixture is `rho = (p−e)/(Rd·T) + e/(Rv·T)`. Runtime uses `Rd = 287.05287 J/(kg·K)` and `Rv = 461.523329 J/(kg·K)`; NASA's adopted standard values imply `p0/(rho0·T0) = 287.052874247 J/(kg·K)`, so the runtime constant is rounded. `dry_air_density_kgm3 = (p−e)/(Rd·T)` feeds the first-order combustion-engine charge proxy; `engine_charge_ratio = dry_air_density_kgm3/1.225`. Total moist density is used for aerodynamic density, with `sigma = rho/1.225`.

`density_altitude_m` is the geometric altitude whose ISA tropospheric density equals the calculated moist density. The inversion is analytic, uses the same ideal dry-air standard-atmosphere constants as the pressure profile, and is converted from geopotential back to geometric altitude. It is a display and pilot-intuition quantity; the flight model consumes density.

`Atmosphere.standard()` keeps the existing standard flight state literal: 101325 Pa, 288.15 K, zero vapor pressure, total and dry density 1.225 kg/m³, sigma and charge ratio 1, and density altitude zero. The literal density is about 15 parts per billion below recomputing `p/(Rd·T)` with the rounded runtime constant; this preserves the existing baseline exactly.

The runtime is a simple ideal-mixture model. It omits the saturation enhancement factor, real-gas compressibility, changing CO₂ composition, vertical temperature structure, and in-flight changes of pressure or density with altitude. It does not establish an aircraft engine's exact power map. The charge ratio is a physically motivated first-order input for a naturally aspirated combustion model; per-engine friction and manufacturer data remain necessary for an accurate torque curve. Do not apply it unchanged to electric motors or turbines.

## Evidence

Run the focused Godot check with the pinned engine:

```sh
./.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script res://tests/test_air_density.gd
```

The check covers the literal reference, Buck liquid-water vapor pressure at 20 °C and −20 °C, an in-range CIPM-2007 moist-air comparison, a standard-atmosphere field-height inversion, inclusive bounds, invalid input controls, and pressure/temperature/humidity monotonicity. Its independent equation calculations are reproduced by [`reference_check.py`](reference_check.py); the captured output is [`reference_results.json`](reference_results.json). This focused check does not run the full application suite.

Sources and their scope are recorded in [`../sources/README.md`](../sources/README.md).
