#!/usr/bin/env python3
"""Independent numeric checks for M5-ATM-1; uses published equations, not app code."""

import json
import math

P0_PA = 101325.0
T0_K = 288.15
RHO0_KGM3 = 1.2250
G0_MPS2 = 9.80665
LAPSE_KPM = 0.0065
EARTH_RADIUS_M = 6356766.0
RD_STANDARD = P0_PA / (RHO0_KGM3 * T0_K)
RD_RUNTIME = 287.05287
R_UNIVERSAL_CIPM = 8.314472
M_DRY_CIPM_KG_MOL = 0.02896546
M_WATER_KG_MOL = 0.01801528
RV_RUNTIME = R_UNIVERSAL_CIPM / M_WATER_KG_MOL


def isa_at_geometric_altitude(z_m: float) -> dict[str, float]:
    geopotential_m = EARTH_RADIUS_M * z_m / (EARTH_RADIUS_M + z_m)
    temperature_k = T0_K - LAPSE_KPM * geopotential_m
    pressure_pa = P0_PA * (temperature_k / T0_K) ** (
        G0_MPS2 / (RD_STANDARD * LAPSE_KPM)
    )
    density_kgm3 = pressure_pa / (RD_STANDARD * temperature_k)
    return {
        "geometric_altitude_m": z_m,
        "geopotential_altitude_m": geopotential_m,
        "temperature_k": temperature_k,
        "pressure_pa": pressure_pa,
        "density_kgm3": density_kgm3,
    }


def buck_saturation_pa(temp_c: float) -> float:
    exponent = (18.678 - temp_c / 234.5) * temp_c / (257.14 + temp_c)
    return 611.21 * math.exp(exponent)


def cipm_2007_density(p_pa: float, temp_c: float, rh: float) -> float:
    """CIPM-2007 equations (NIST Metrologia 45 (2008), Appendix A)."""
    temperature_k = temp_c + 273.15
    p_sat = math.exp(
        1.2378847e-5 * temperature_k**2
        - 1.9121316e-2 * temperature_k
        + 33.93711047
        - 6.3431645e3 / temperature_k
    )
    enhancement = 1.00062 + 3.14e-8 * p_pa + 5.6e-7 * temp_c**2
    x_v = rh * enhancement * p_sat / p_pa
    z = 1.0 - p_pa / temperature_k * (
        1.58123e-6
        - 2.9331e-8 * temp_c
        + 1.1043e-10 * temp_c**2
        + (5.707e-6 - 2.051e-8 * temp_c) * x_v
        + (1.9898e-4 - 2.376e-6 * temp_c) * x_v**2
    ) + p_pa**2 / temperature_k**2 * (1.83e-11 - 0.765e-8 * x_v**2)
    return (
        M_DRY_CIPM_KG_MOL
        * p_pa
        / (z * R_UNIVERSAL_CIPM * temperature_k)
        * (1.0 - x_v * (1.0 - M_WATER_KG_MOL / M_DRY_CIPM_KG_MOL))
    )


def simple_moist_density(p_pa: float, temp_c: float, rh: float) -> dict[str, float]:
    temperature_k = temp_c + 273.15
    vapor_pressure_pa = rh * buck_saturation_pa(temp_c)
    dry = (p_pa - vapor_pressure_pa) / (RD_RUNTIME * temperature_k)
    vapor = vapor_pressure_pa / (RV_RUNTIME * temperature_k)
    return {
        "vapor_pressure_pa": vapor_pressure_pa,
        "dry_air_density_kgm3": dry,
        "rho_kgm3": dry + vapor,
        "engine_charge_ratio": dry / RHO0_KGM3,
    }


def main() -> None:
    z1000 = isa_at_geometric_altitude(1000.0)
    sea_level = simple_moist_density(101325.0, 20.0, 0.5)
    cipm = cipm_2007_density(101325.0, 20.0, 0.5)
    sea_level["cipm_2007_rho_kgm3"] = cipm
    sea_level["relative_error_vs_cipm_percent"] = (
        sea_level["rho_kgm3"] / cipm - 1.0
    ) * 100.0
    results = {
        "scope": "equation cross-checks; not physical weather validation",
        "dry_gas_constant_standard_exact_ratio": RD_STANDARD,
        "dry_gas_constant_runtime_rounded": RD_RUNTIME,
        "water_vapor_gas_constant_from_cipm_R_and_Mv": RV_RUNTIME,
        "buck_liquid_water_saturation_minus20c_pa": buck_saturation_pa(-20.0),
        "isa_1000m_geometric": z1000,
        "sea_level_20C_50pct_rh": sea_level,
    }
    print(json.dumps(results, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
