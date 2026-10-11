# Uniform, field-level atmosphere inputs for one flight. Physics values stay float64.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const SEA_LEVEL_PRESSURE_PA: float = 101325.0
const SEA_LEVEL_TEMPERATURE_K: float = 288.15
const SEA_LEVEL_DENSITY_KGM3: float = 1.225
const STANDARD_GRAVITY_MPS2: float = 9.80665
const TROPOSPHERE_LAPSE_KPM: float = 0.0065
const DRY_AIR_GAS_CONSTANT_J_KG_K: float = 287.05287
const WATER_VAPOR_GAS_CONSTANT_J_KG_K: float = 461.523329
const EARTH_EFFECTIVE_RADIUS_M: float = 6356766.0

const MIN_FIELD_ELEVATION_M: float = -500.0
const MAX_FIELD_ELEVATION_M: float = 4000.0
const MIN_TEMPERATURE_C: float = -20.0
const MAX_TEMPERATURE_C: float = 45.0
const MIN_QNH_HPA: float = 870.0
const MAX_QNH_HPA: float = 1085.0
const MIN_RELATIVE_HUMIDITY_PERCENT: float = 0.0
const MAX_RELATIVE_HUMIDITY_PERCENT: float = 100.0


## Literal reference state retained for existing flight behavior and goldens.
static func standard() -> Dictionary:
	return {
		"ok": true,
		"errors": [],
		"pressure_pa": SEA_LEVEL_PRESSURE_PA,
		"temperature_k": SEA_LEVEL_TEMPERATURE_K,
		"vapor_pressure_pa": 0.0,
		"rho_kgm3": SEA_LEVEL_DENSITY_KGM3,
		"dry_air_density_kgm3": SEA_LEVEL_DENSITY_KGM3,
		"sigma": 1.0,
		"engine_charge_ratio": 1.0,
		"density_altitude_m": 0.0,
	}


## Evaluates one uniform field-level atmosphere from geometric elevation and weather.
## Relative humidity is referenced to liquid water, including supercooled liquid below 0 C.
static func evaluate(field_elevation_m: Variant, temp_c: Variant, qnh_hpa: Variant,
		relative_humidity_percent: Variant) -> Dictionary:
	var errors: Array[String] = []
	var elevation: float = _read_number(field_elevation_m, "field_elevation_m",
		MIN_FIELD_ELEVATION_M, MAX_FIELD_ELEVATION_M, errors)
	var ambient_c: float = _read_number(temp_c, "temp_c", MIN_TEMPERATURE_C, MAX_TEMPERATURE_C, errors)
	var qnh: float = _read_number(qnh_hpa, "qnh_hpa", MIN_QNH_HPA, MAX_QNH_HPA, errors)
	var humidity_percent: float = _read_number(relative_humidity_percent, "relative_humidity_percent",
		MIN_RELATIVE_HUMIDITY_PERCENT, MAX_RELATIVE_HUMIDITY_PERCENT, errors)
	if not errors.is_empty():
		return _failure(errors)

	var geopotential_elevation: float = _to_geopotential_m(elevation)
	var pressure_base: float = 1.0 - TROPOSPHERE_LAPSE_KPM * geopotential_elevation / SEA_LEVEL_TEMPERATURE_K
	if not is_finite(pressure_base) or pressure_base <= 0.0:
		return _failure(["field_elevation_m produces an invalid ISA pressure base."])
	var pressure_exponent: float = STANDARD_GRAVITY_MPS2 / (DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM)
	var pressure_pa: float = qnh * 100.0 * M.pow_(pressure_base, pressure_exponent)
	var temperature_k: float = ambient_c + 273.15
	var saturation_vapor_pressure_pa: float = _buck_saturation_vapor_pressure_pa(ambient_c)
	var vapor_pressure_pa: float = humidity_percent / 100.0 * saturation_vapor_pressure_pa
	if not is_finite(pressure_pa) or not is_finite(temperature_k) \
			or not is_finite(vapor_pressure_pa) or pressure_pa <= vapor_pressure_pa:
		return _failure(["Derived pressure, temperature, or vapor pressure is physically invalid."])

	var dry_air_density_kgm3: float = (pressure_pa - vapor_pressure_pa) \
		/ (DRY_AIR_GAS_CONSTANT_J_KG_K * temperature_k)
	var vapor_density_kgm3: float = vapor_pressure_pa \
		/ (WATER_VAPOR_GAS_CONSTANT_J_KG_K * temperature_k)
	var density_kgm3: float = dry_air_density_kgm3 + vapor_density_kgm3
	var sigma: float = density_kgm3 / SEA_LEVEL_DENSITY_KGM3
	var engine_charge_ratio: float = dry_air_density_kgm3 / SEA_LEVEL_DENSITY_KGM3
	var density_altitude_m: float = _density_altitude_geometric_m(density_kgm3)
	if not is_finite(dry_air_density_kgm3) or not is_finite(density_kgm3) \
			or not is_finite(sigma) or not is_finite(engine_charge_ratio) \
			or not is_finite(density_altitude_m) or density_kgm3 <= 0.0:
		return _failure(["Derived atmosphere values are not finite and positive."])

	return {
		"ok": true,
		"errors": [],
		"pressure_pa": pressure_pa,
		"temperature_k": temperature_k,
		"vapor_pressure_pa": vapor_pressure_pa,
		"rho_kgm3": density_kgm3,
		"dry_air_density_kgm3": dry_air_density_kgm3,
		"sigma": sigma,
		"engine_charge_ratio": engine_charge_ratio,
		"density_altitude_m": density_altitude_m,
	}


static func _read_number(value: Variant, key: String, minimum: float, maximum: float,
		errors: Array[String]) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		errors.append("%s must be an integer or float, not %s." % [key, type_string(typeof(value))])
		return 0.0
	var number: float = float(value)
	if not is_finite(number):
		errors.append("%s must be finite." % key)
		return 0.0
	if number < minimum or number > maximum:
		errors.append("%s must be in [%s, %s]." % [key, str(minimum), str(maximum)])
	return number


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors}


static func _to_geopotential_m(geometric_m: float) -> float:
	return EARTH_EFFECTIVE_RADIUS_M * geometric_m / (EARTH_EFFECTIVE_RADIUS_M + geometric_m)


static func _buck_saturation_vapor_pressure_pa(temp_c: float) -> float:
	var exponent: float = (18.678 - temp_c / 234.5) * temp_c / (257.14 + temp_c)
	return 611.21 * M.exp_(exponent)


static func _density_altitude_geometric_m(density_kgm3: float) -> float:
	var sea_level_dry_density: float = SEA_LEVEL_PRESSURE_PA \
		/ (DRY_AIR_GAS_CONSTANT_J_KG_K * SEA_LEVEL_TEMPERATURE_K)
	var density_exponent: float = STANDARD_GRAVITY_MPS2 \
		/ (DRY_AIR_GAS_CONSTANT_J_KG_K * TROPOSPHERE_LAPSE_KPM) - 1.0
	var density_ratio: float = density_kgm3 / sea_level_dry_density
	if density_ratio <= 0.0 or density_exponent <= 0.0:
		return NAN
	var geopotential_m: float = SEA_LEVEL_TEMPERATURE_K / TROPOSPHERE_LAPSE_KPM \
		* (1.0 - M.pow_(density_ratio, 1.0 / density_exponent))
	return EARTH_EFFECTIVE_RADIUS_M * geopotential_m / (EARTH_EFFECTIVE_RADIUS_M - geopotential_m)
