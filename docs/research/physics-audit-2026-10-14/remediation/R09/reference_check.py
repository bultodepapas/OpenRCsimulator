"""Independent dry ISA reference calculation for R09; imports no application code."""
import json

P0_PA = 101325.0
T0_K = 288.15
G0_MPS2 = 9.80665
RD_J_KG_K = 287.05287
LAPSE_K_PER_M = 0.0065
EARTH_RADIUS_M = 6356766.0
ALTITUDES_GEOMETRIC_M = [-500.0, 0.0, 50.0, 500.0, 1000.0, 11000.0]

rows = []
for z_m in ALTITUDES_GEOMETRIC_M:
    h_m = EARTH_RADIUS_M * z_m / (EARTH_RADIUS_M + z_m)
    temp_k = T0_K - LAPSE_K_PER_M * h_m
    pressure_pa = P0_PA * (temp_k / T0_K) ** (G0_MPS2 / (RD_J_KG_K * LAPSE_K_PER_M))
    rho_kgm3 = pressure_pa / (RD_J_KG_K * temp_k)
    rows.append({
        "geometric_altitude_m": z_m,
        "geopotential_altitude_m": h_m,
        "temperature_k": temp_k,
        "pressure_pa": pressure_pa,
        "dry_density_kgm3": rho_kgm3,
        "sigma_against_legacy_1_225": rho_kgm3 / 1.225,
    })

result = {
    "method": "independent standard-atmosphere equations; no app imports",
    "constants": {
        "sea_level_pressure_pa": P0_PA,
        "sea_level_temperature_k": T0_K,
        "standard_gravity_mps2": G0_MPS2,
        "dry_air_gas_constant_j_kg_k": RD_J_KG_K,
        "troposphere_lapse_k_per_m": LAPSE_K_PER_M,
        "effective_earth_radius_m": EARTH_RADIUS_M,
    },
    "rows": rows,
    "sea_level_density_minus_legacy_literal_kgm3": rows[1]["dry_density_kgm3"] - 1.225,
}
print(json.dumps(result, indent=2, sort_keys=True))
