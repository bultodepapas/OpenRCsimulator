# R09 regression and vertical-atmosphere acceptance checks; run with --path app.
extends SceneTree

const Atmosphere := preload("res://physics/atmosphere.gd")
const Config := preload("res://physics/wind_config.gd")
const WindField := preload("res://physics/wind_field.gd")

var _checks := 0
var _failures := 0

func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])

func _near(actual: float, expected: float, tolerance: float) -> bool:
	return is_finite(actual) and absf(actual - expected) <= tolerance

func _column_config(field_elevation_m: float = 0.0, changes: Dictionary = {}) -> Dictionary:
	var selected: Dictionary = {
		"atmosphere_mode": "standard_column",
		"field_elevation_m": field_elevation_m,
		"temperature_c": 15.0,
		"qnh_hpa": 1013.25,
		"relative_humidity_pct": 0.0,
	}
	selected.merge(changes, true)
	return Config.upgrade_column(Config.defaults(), selected)

func _build_column(field_elevation_m: float = 0.0, changes: Dictionary = {}) -> Variant:
	var built: Dictionary = WindField.build(_column_config(field_elevation_m, changes))
	if not built.ok:
		printerr("column field fixture rejected: ", built.errors)
		return null
	return built.field

func _initialize() -> void:
	_check_known_answers()
	_check_ranges_and_legacy()
	_check_weather_versions()
	_check_field_sampling()
	print("R09 atmosphere column: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)

func _check_known_answers() -> void:
	# Independent dry-ISA references: h=Re*z/(Re+z), T=T0-L*h,
	# p=p0*(T/T0)^(g0/(Rd*L)), rho=p/(Rd*T).
	var cases: Array[Dictionary] = [
		{z = -500.0, t = 291.400255653240, p = 107478.006754987393, rho = 1.28489542200680},
		{z = 0.0, t = 288.150000000000, p = 101325.000000000000, rho = 1.22500001812429},
		{z = 50.0, t = 287.825002556311, p = 100725.787237186509, rho = 1.21913067767820},
		{z = 500.0, t = 284.900255613026, p = 95461.285491468429, rho = 1.16727328495126},
		{z = 1000.0, t = 281.651022371695, p = 89876.277602342365, rho = 1.11165967369969},
		{z = 11000.0, t = 216.773512704456, p = 22699.936837004112, rho = 0.36480143683538},
	]
	for row: Dictionary in cases:
		var air: Dictionary = Atmosphere.standard_column(row.z)
		_check("column accepts altitude %.1f m" % row.z, air.ok, str(air))
		if not air.ok:
			continue
		_check("independent temperature at %.1f m" % row.z, _near(air.temperature_k, row.t, 2e-10), str(air.temperature_k))
		_check("independent pressure at %.1f m" % row.z, _near(air.pressure_pa, row.p, 2e-7), str(air.pressure_pa))
		_check("independent dry density at %.1f m" % row.z, _near(air.rho_kgm3, row.rho, 2e-12), str(air.rho_kgm3))
		_check("dry result fields at %.1f m" % row.z, air.vapor_pressure_pa == 0.0
			and air.dry_air_density_kgm3 == air.rho_kgm3 and air.engine_charge_ratio == air.sigma)
		_check("density altitude recovers %.1f m" % row.z, _near(air.density_altitude_m, row.z, 3e-9), str(air.density_altitude_m))
		_check("pure repeated query at %.1f m" % row.z, JSON.stringify(air) == JSON.stringify(Atmosphere.standard_column(row.z)))
		var nearby_z: float = row.z + (1e-6 if row.z < 11000.0 else -1e-6)
		var nearby: Dictionary = Atmosphere.standard_column(nearby_z)
		_check("continuous near altitude %.1f m" % row.z, nearby.ok
			and absf(nearby.temperature_k - air.temperature_k) < 1e-8
			and absf(nearby.pressure_pa - air.pressure_pa) < 3e-5
			and absf(nearby.rho_kgm3 - air.rho_kgm3) < 3e-10)

func _check_ranges_and_legacy() -> void:
	for invalid: Variant in [-500.000001, 11000.000001, NAN, INF, true, "500"]:
		_check("reject invalid geometric altitude %s" % str(invalid), not Atmosphere.standard_column(invalid).ok)
	_check("both geometric bounds are supported", Atmosphere.standard_column(-500.0).ok and Atmosphere.standard_column(11000.0).ok)
	var literal: Dictionary = Atmosphere.standard()
	_check("literal reference remains byte-valued legacy state", literal.rho_kgm3 == 1.225 and literal.sigma == 1.0 and literal.engine_charge_ratio == 1.0)
	_check("v3 rejects v4-only column mode", not Config.validate(Config.upgrade_atmosphere(Config.defaults(), {atmosphere_mode = "standard_column"})).ok)

func _check_weather_versions() -> void:
	var v1: Dictionary = Config.defaults()
	var checked_v1: Dictionary = Config.validate(v1)
	_check("v1 canonical configuration unchanged", checked_v1.ok and checked_v1.config == v1, str(checked_v1.errors))
	var v2: Dictionary = Config.GENTLE_PRACTICE.duplicate(true)
	var checked_v2: Dictionary = Config.validate(v2)
	_check("v2 canonical configuration unchanged", checked_v2.ok and checked_v2.config == v2, str(checked_v2.errors))
	var v3: Dictionary = Config.upgrade_atmosphere(Config.defaults(), {temperature_c = 15.0})
	var checked_v3: Dictionary = Config.validate(v3)
	_check("v3 canonical configuration unchanged", checked_v3.ok and checked_v3.config == v3, str(checked_v3.errors))
	var v3_custom: Dictionary = Config.upgrade_atmosphere(Config.defaults(), {atmosphere_mode = "custom", field_elevation_m = 500.0,
		temperature_c = 22.0, qnh_hpa = 1001.0, relative_humidity_pct = 40.0})
	var v4_custom: Dictionary = Config.upgrade_column(v3_custom)
	var validated_v4: Dictionary = Config.validate(v4_custom)
	_check("v4 preserves all five atmosphere fields and custom mode", validated_v4.ok
		and validated_v4.config.format == Config.COLUMN_FORMAT and validated_v4.config.atmosphere_mode == "custom"
		and validated_v4.config.field_elevation_m == 500.0 and validated_v4.config.temperature_c == 22.0
		and validated_v4.config.qnh_hpa == 1001.0 and validated_v4.config.relative_humidity_pct == 40.0)
	_check("v4 upgrade is not downgraded by atmosphere upgrade", Config.upgrade_atmosphere(v4_custom).format == Config.COLUMN_FORMAT)
	_check("v4 custom kernel output is identical to v3 custom", Config.atmosphere(v3_custom) == Config.atmosphere(v4_custom))
	var v4_reference: Dictionary = Config.upgrade_column(Config.upgrade_atmosphere(Config.defaults()))
	_check("v4 reference remains the literal reference state", Config.atmosphere(v4_reference) == Atmosphere.standard()
		and not Config.has_atmosphere(v4_reference) and not Config.has_vertical_atmosphere(v4_reference))
	_check("column preset exists and validates", Config.validate(Config.preset("standard-column")).ok
		and Config.preset("standard-column").format == Config.COLUMN_FORMAT
		and Config.preset("standard-column").atmosphere_mode == "standard_column")
	var standard_v4: Dictionary = Config.validate(_column_config()).config
	_check("v4 accepts column mode", standard_v4.format == Config.COLUMN_FORMAT and Config.has_vertical_atmosphere(standard_v4)
		and Config.has_atmosphere(standard_v4))
	_check("v4 preserves validated inert draft values", standard_v4.temperature_c == 15.0
		and standard_v4.qnh_hpa == 1013.25 and standard_v4.relative_humidity_pct == 0.0)
	_check("column retains the field-elevation datum bounds", Config.validate(_column_config(4000.0)).ok
		and not Config.validate(_column_config(4000.000001)).ok)
	_check("custom mode remains custom-atmosphere capability", Config.has_atmosphere(v3_custom) and Config.has_atmosphere(v4_custom)
		and not Config.has_vertical_atmosphere(v3_custom))
	var invalid_v3_mode: Dictionary = Config.upgrade_atmosphere(Config.defaults(), {atmosphere_mode = "standard_column"})
	var invalid_v3_result: Dictionary = Config.validate(invalid_v3_mode)
	_check("v3 invalid mode preserves its historical diagnostic", not invalid_v3_result.ok
		and invalid_v3_result.errors.has("atmosphere_mode must be reference or custom"))

func _check_field_sampling() -> void:
	var field: Variant = _build_column(500.0)
	_check("column weather field builds", field != null)
	if field == null:
		return
	_check("column is active atmosphere and reports its vertical subtype", field.has_atmosphere() and field.has_vertical_atmosphere())
	_check("column law is exposed", field.atmosphere_law() == Atmosphere.STANDARD_COLUMN_LAW)
	var sample_500: Dictionary = field.atmosphere(0.0)
	var same_z_field: Variant = _build_column(1000.0)
	var sample_same_z: Dictionary = same_z_field.atmosphere(500.0)
	_check("field offset and NED down map to identical geometric altitude", sample_500 == sample_same_z)
	_check("density and charge query use the same altitude", field.air_density(0.0) == sample_500.rho_kgm3
		and field.engine_charge_ratio(0.0) == sample_500.engine_charge_ratio)
	_check("field sample is repeatable", field.atmosphere(123.25) == field.atmosphere(123.25))
	var with_drafts: Variant = _build_column(500.0, {temperature_c = 38.0, qnh_hpa = 870.0, relative_humidity_pct = 100.0})
	_check("draft temperature/QNH/RH stay inert in column law", with_drafts.atmosphere(0.0) == sample_500)
	_check("exact supported aircraft altitude limits sample", field.atmosphere(-10500.0).ok and field.atmosphere(1000.0).ok)
	_check("out-of-range column atmosphere fails closed", not field.atmosphere(-10500.000001).ok
		and not is_finite(field.air_density(-10500.000001)) and not is_finite(field.engine_charge_ratio(-10500.000001)))
	_check("lower out-of-range altitude fails closed", not field.atmosphere(1000.000001).ok
		and not is_finite(field.air_density(1000.000001)) and not is_finite(field.engine_charge_ratio(1000.000001)))
	var v3_reference: Variant = WindField.build(Config.upgrade_atmosphere(Config.defaults())).field
	_check("uniform weather keeps old law identifier and constant no-argument outputs",
		v3_reference.atmosphere_law() == "uniform-field-qnh-isa-buck-liquid-v1"
		and v3_reference.air_density() == 1.225 and v3_reference.air_density(1200.0) == 1.225
		and v3_reference.engine_charge_ratio() == 1.0)
	var v3_custom_field: Variant = WindField.build(v3_custom_config()).field
	var v4_custom_field: Variant = WindField.build(Config.upgrade_column(v3_custom_config())).field
	_check("v4 custom uniform field keeps v3 density and charge", v3_custom_field.air_density() == v4_custom_field.air_density()
		and v3_custom_field.engine_charge_ratio() == v4_custom_field.engine_charge_ratio()
		and v4_custom_field.has_atmosphere() and not v4_custom_field.has_vertical_atmosphere())
	_check("reference and custom weather are not vertical profiles",
		not v3_reference.has_vertical_atmosphere() and WindField.build(v3_custom_config()).field.has_atmosphere())

func v3_custom_config() -> Dictionary:
	return Config.upgrade_atmosphere(Config.defaults(), {atmosphere_mode = "custom", field_elevation_m = 500.0,
		temperature_c = 22.0, qnh_hpa = 1001.0, relative_humidity_pct = 40.0})
