# M5-ATM-1: atmosphere known answers, physical invariants, limits and failure controls.
# Run: .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script res://tests/test_air_density.gd
extends SceneTree

const Atmosphere := preload("res://physics/atmosphere.gd")

var _failures: int = 0
var _count: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _close(actual: float, expected: float, tolerance: float) -> bool:
	return is_finite(actual) and absf(actual - expected) <= tolerance


func _initialize() -> void:
	var reference: Dictionary = Atmosphere.standard()
	_check("reference succeeds", reference.get("ok") == true)
	_check("reference has no errors", reference.get("errors") == [])
	_check("reference total density stays literal", reference.get("rho_kgm3") == 1.225)
	_check("reference dry density stays literal", reference.get("dry_air_density_kgm3") == 1.225)
	_check("reference pressure and temperature", reference.get("pressure_pa") == 101325.0
		and reference.get("temperature_k") == 288.15)
	_check("reference vapor, sigma, charge and altitude", reference.get("vapor_pressure_pa") == 0.0
		and reference.get("sigma") == 1.0 and reference.get("engine_charge_ratio") == 1.0
		and reference.get("density_altitude_m") == 0.0)

	# Independent NIST CIPM-2007 check is in-range at 101325 Pa, 20 C, 50% RH.
	var sea_level: Dictionary = Atmosphere.evaluate(0.0, 20.0, 1013.25, 50.0)
	_check("sea-level inputs succeed", sea_level.get("ok") == true, str(sea_level.get("errors", [])))
	_check("sea-level pressure and absolute temperature",
		_close(float(sea_level.get("pressure_pa", NAN)), 101325.0, 1e-10)
		and _close(float(sea_level.get("temperature_k", NAN)), 293.15, 1e-12))
	_check("Buck liquid-water vapor pressure at 20 C, 50% RH",
		_close(float(sea_level.get("vapor_pressure_pa", NAN)), 1169.1699892250094, 1e-10))
	var supercooled_liquid: Dictionary = Atmosphere.evaluate(0.0, -20.0, 1013.25, 100.0)
	_check("subzero RH uses the Buck liquid-water curve",
		_close(float(supercooled_liquid.get("vapor_pressure_pa", NAN)), 125.58408951511785, 1e-10))
	_check("moist density agrees with independent CIPM-2007 reference within 0.05%",
		absf(float(sea_level.get("rho_kgm3", NAN)) / 1.1993138954744933 - 1.0) <= 0.0005,
		"runtime=%.12f CIPM=1.199313895474" % float(sea_level.get("rho_kgm3", NAN)))
	_check("density and dry charge use separate partial pressures",
		float(sea_level.get("rho_kgm3", NAN)) > float(sea_level.get("dry_air_density_kgm3", NAN))
		and _close(float(sea_level.get("engine_charge_ratio", NAN)),
			float(sea_level.get("dry_air_density_kgm3", NAN)) / 1.225, 1e-14))

	# NASA NDARC's ISA equations; a 1000 m geometric field maps to 999.8427 m geopotential.
	var field_geopotential_m: float = 6356766.0 * 1000.0 / (6356766.0 + 1000.0)
	var isa_field_c: float = 288.15 - 0.0065 * field_geopotential_m - 273.15
	var isa_field: Dictionary = Atmosphere.evaluate(1000.0, isa_field_c, 1013.25, 0.0)
	_check("1000 m geometric field standard pressure",
		_close(float(isa_field.get("pressure_pa", NAN)), 89876.2776, 0.03),
		str(isa_field.get("pressure_pa", NAN)))
	_check("standard density at field maps back to 1000 m geometric density altitude",
		_close(float(isa_field.get("density_altitude_m", NAN)), 1000.0, 1e-7),
		str(isa_field.get("density_altitude_m", NAN)))
	_check("NASA sea-level standard dry density is the expected rounded value",
		_close(float(Atmosphere.evaluate(0, 15, 1013.25, 0).get("rho_kgm3", NAN)),
			1.2250000181, 1e-9))

	# Boundary values are accepted; each input is checked independently outside its domain.
	_check("inclusive lower domain limits succeed",
		Atmosphere.evaluate(-500, -20, 870, 0).get("ok") == true)
	_check("inclusive upper domain limits succeed",
		Atmosphere.evaluate(4000, 45, 1085, 100).get("ok") == true)
	_check("reject elevation below domain", not Atmosphere.evaluate(-500.01, 15, 1013.25, 50).get("ok"))
	_check("reject temperature above domain", not Atmosphere.evaluate(0, 45.01, 1013.25, 50).get("ok"))
	_check("reject QNH below domain", not Atmosphere.evaluate(0, 15, 869.99, 50).get("ok"))
	_check("reject RH above domain", not Atmosphere.evaluate(0, 15, 1013.25, 100.01).get("ok"))
	_check("reject booleans instead of numbers", not Atmosphere.evaluate(true, 15, 1013.25, 50).get("ok"))
	_check("reject strings instead of numbers", not Atmosphere.evaluate(0, "15", 1013.25, 50).get("ok"))
	_check("reject NaN", not Atmosphere.evaluate(0, NAN, 1013.25, 50).get("ok"))
	_check("reject infinity", not Atmosphere.evaluate(0, 15, INF, 50).get("ok"))

	# Independent-direction checks catch sign mistakes without depending on exact coefficients.
	var colder: Dictionary = Atmosphere.evaluate(0, 10, 1013.25, 50)
	var hotter: Dictionary = Atmosphere.evaluate(0, 30, 1013.25, 50)
	var lower_pressure: Dictionary = Atmosphere.evaluate(0, 20, 990.0, 50)
	var humid: Dictionary = Atmosphere.evaluate(0, 20, 1013.25, 90)
	var dry: Dictionary = Atmosphere.evaluate(0, 20, 1013.25, 0)
	_check("density falls as temperature rises", float(hotter.get("rho_kgm3", INF)) < float(colder.get("rho_kgm3", -INF)))
	_check("density falls as QNH falls at fixed temperature and humidity",
		float(lower_pressure.get("rho_kgm3", INF)) < float(sea_level.get("rho_kgm3", -INF)))
	_check("moist air density and dry engine charge both fall with RH at fixed p and T",
		float(humid.get("rho_kgm3", INF)) < float(dry.get("rho_kgm3", -INF))
		and float(humid.get("engine_charge_ratio", INF)) < float(dry.get("engine_charge_ratio", -INF)))
	_check("all successful representative outputs are finite and positive",
		_is_finite_success(sea_level) and _is_finite_success(isa_field)
		and _is_finite_success(Atmosphere.evaluate(-500, -20, 870, 0))
		and _is_finite_success(Atmosphere.evaluate(4000, 45, 1085, 100)))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _is_finite_success(result: Dictionary) -> bool:
	if result.get("ok") != true:
		return false
	for key: String in ["pressure_pa", "temperature_k", "vapor_pressure_pa", "rho_kgm3",
			"dry_air_density_kgm3", "sigma", "engine_charge_ratio", "density_altitude_m"]:
		var value: Variant = result.get(key, NAN)
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
			return false
	return float(result.get("pressure_pa", 0.0)) > 0.0 \
		and float(result.get("temperature_k", 0.0)) > 0.0 \
		and float(result.get("rho_kgm3", 0.0)) > 0.0 \
		and float(result.get("dry_air_density_kgm3", 0.0)) > 0.0
