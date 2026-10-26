# P0 M5-W05b-R1: preserve the legacy wind law while introducing world-space queries.
extends SceneTree

const WindConfig := preload("res://physics/wind_config.gd")
const WindField := preload("res://physics/wind_field.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const PhysicsAtmosphere := preload("res://physics/atmosphere.gd")

class SyntheticWorldWind extends "res://physics/wind_field.gd":
	var linear := false
	var world_sample_calls := 0
	var override_enabled := false
	var override_value := PackedFloat64Array()

	func sample(time_s: float) -> PackedFloat64Array:
		# Poison the legacy path so the Environment test proves it dispatches sample_world.
		return PackedFloat64Array([900.0, 800.0, 700.0])

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		world_sample_calls += 1
		if override_enabled:
			return override_value.duplicate()
		if not linear:
			return PackedFloat64Array([1.25, -3.5, 0.75])
		return PackedFloat64Array([
			1.0 + 0.5 * position_ned[0] + 2.0 * time_s,
			-2.0 + 0.25 * position_ned[1] - time_s,
			3.0 - position_ned[2] + 0.5 * time_s,
		])


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _finite3(values: PackedFloat64Array) -> bool:
	return values.size() == 3 and is_finite(values[0]) and is_finite(values[1]) and is_finite(values[2])


func _same_bytes(actual: PackedFloat64Array, expected: PackedFloat64Array) -> bool:
	return actual.to_byte_array() == expected.to_byte_array()


func _check_legacy_compatibility() -> void:
	var formats := {}
	var points: Array[PackedFloat64Array] = [
		PackedFloat64Array([1234.5, -87.25, -12.0]),
		PackedFloat64Array([-930.125, 441.75, 3.5]),
		PackedFloat64Array([0.0625, 2700.0, 89.25]),
	]
	var times: Array[float] = [0.0, 3.25, 19.75, 128.5]
	for preset: Dictionary in WindConfig.presets():
		var config: Dictionary = preset.config
		formats[str(config.format)] = true
		var built: Dictionary = WindField.build(config)
		_check("preset %s builds" % str(preset.id), built.ok, str(built.errors))
		if not built.ok:
			continue
		var environment: Variant = SimEnvironment.new()
		environment.weather = built.field
		# A deterministic owner-sampled turbulence value exercises the legacy addition path for every schema version.
		environment.turbulence = func(time_s: float) -> PackedFloat64Array:
			return PackedFloat64Array([0.125 + time_s * 0.03125, -0.375, 0.0625 - time_s * 0.0078125])
		for point: PackedFloat64Array in points:
			for time_s: float in times:
				var legacy: PackedFloat64Array = environment.wind(time_s)
				var spatial: PackedFloat64Array = environment.wind_world(point, time_s)
				_check("%s exact legacy bytes at %s, t=%s" % [str(preset.id), str(point), str(time_s)],
					_same_bytes(spatial, legacy), "%s != %s" % [str(spatial), str(legacy)])
	_check("v1, v2, v3 and v4 presets are covered", formats.size() == 4, str(formats.keys()))

	var detached_field: Variant = WindField.build(WindConfig.preset("gusty")).field
	var detached_position := PackedFloat64Array([-31.25, 240.5, -2.75])
	var first: PackedFloat64Array = detached_field.sample_world(detached_position, 4.125)
	var first_bytes: PackedByteArray = first.to_byte_array()
	first[0] = 999.0
	_check("WindField world samples are detached", detached_field.sample_world(detached_position, 4.125).to_byte_array() == first_bytes)
	var detached_environment: Variant = SimEnvironment.new()
	detached_environment.weather = detached_field
	var world_first: PackedFloat64Array = detached_environment.wind_world(detached_position, 4.125)
	var world_bytes: PackedByteArray = world_first.to_byte_array()
	world_first[1] = -999.0
	_check("Environment world wind is detached", detached_environment.wind_world(detached_position, 4.125).to_byte_array() == world_bytes)


func _check_world_dispatch_and_repeatability() -> void:
	var constant_field := SyntheticWorldWind.new()
	var constant_environment: Variant = SimEnvironment.new()
	constant_environment.weather = constant_field
	var constant_a: PackedFloat64Array = constant_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
	var constant_b: PackedFloat64Array = constant_environment.wind_world(PackedFloat64Array([500.0, -20.0, 100.0]), 93.5)
	var constant_expected := PackedFloat64Array([1.25, -3.5, 0.75])
	_check("constant synthetic field has known NED value", _same_bytes(constant_a, constant_expected), str(constant_a))
	_check("constant synthetic field ignores position and time", _same_bytes(constant_b, constant_expected))
	_check("Environment dispatched once for each constant sample", constant_field.world_sample_calls == 2,
		str(constant_field.world_sample_calls))

	var linear_field := SyntheticWorldWind.new()
	linear_field.linear = true
	var environment: Variant = SimEnvironment.new()
	environment.weather = linear_field
	var position := PackedFloat64Array([10.0, 4.0, -2.0])
	var original_position := position.duplicate()
	var first: PackedFloat64Array = environment.wind_world(position, 3.0)
	var first_bytes: PackedByteArray = first.to_byte_array()
	var expected := PackedFloat64Array([12.0, -4.0, 6.5])
	_check("linear synthetic field returns known NED value", _same_bytes(first, expected), str(first))
	environment.wind_world(PackedFloat64Array([-7.0, 2.0, 9.0]), 8.25)
	environment.wind_world(PackedFloat64Array([1.0, 6.0, 0.0]), 0.125)
	var repeated: PackedFloat64Array = environment.wind_world(original_position, 3.0)
	_check("same point and time are unchanged by query order", repeated.to_byte_array() == first_bytes, str(repeated))
	first[0] = -500.0
	var after_mutation: PackedFloat64Array = environment.wind_world(original_position, 3.0)
	_check("a returned spatial sample cannot mutate later samples", after_mutation.to_byte_array() == first_bytes)
	_check("world sample dispatch occurs exactly once per query", linear_field.world_sample_calls == 5,
		str(linear_field.world_sample_calls))

	var noise_calls := {"count": 0}
	var noisy_environment: Variant = SimEnvironment.new()
	noisy_environment.weather = constant_field
	noisy_environment.turbulence = func(_time_s: float) -> PackedFloat64Array:
		noise_calls.count += 1
		return PackedFloat64Array([0.25, -0.5, 1.5])
	var noisy: PackedFloat64Array = noisy_environment.wind_world(PackedFloat64Array([8.0, 4.0, 2.0]), 7.0)
	_check("legacy turbulence is added once after spatial sampling",
		_same_bytes(noisy, PackedFloat64Array([1.5, -4.0, 2.25])) and noise_calls.count == 1,
		"wind=%s turbulence_calls=%d" % [str(noisy), noise_calls.count])

	var empty_noise_environment: Variant = SimEnvironment.new()
	var empty_noise_field: Variant = WindField.build(WindConfig.preset("gusty")).field
	empty_noise_environment.weather = empty_noise_field
	empty_noise_environment.turbulence = func(_time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array()
	var raw_profile: PackedFloat64Array = empty_noise_field.sample(4.125)
	var empty_noise_world: PackedFloat64Array = empty_noise_environment.wind_world(PackedFloat64Array([52.0, -8.0, 3.0]), 4.125)
	_check("empty owner turbulence preserves exact provider bytes", _same_bytes(empty_noise_world, raw_profile))


func _check_fail_closed_inputs() -> void:
	var field: Variant = WindField.new()
	var malformed_positions: Array[PackedFloat64Array] = [
		PackedFloat64Array(),
		PackedFloat64Array([1.0, 2.0]),
		PackedFloat64Array([1.0, NAN, 3.0]),
		PackedFloat64Array([1.0, INF, 3.0]),
	]
	for position: PackedFloat64Array in malformed_positions:
		_check("WindField rejects malformed position %s" % str(position), not _finite3(field.sample_world(position, 1.0)))
	for bad_time: float in [NAN, INF, -0.25]:
		_check("WindField rejects invalid time %s" % str(bad_time), not _finite3(field.sample_world(PackedFloat64Array([0.0, 0.0, 0.0]), bad_time)))

	var environment: Variant = SimEnvironment.new()
	var negative_time_field := SyntheticWorldWind.new()
	environment.weather = negative_time_field
	for position: PackedFloat64Array in malformed_positions:
		_check("Environment rejects malformed world position %s" % str(position),
			not _finite3(environment.wind_world(position, 1.0)))
	_check("Environment rejects nonfinite world-query time",
		not _finite3(environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), NAN)))
	_check("Environment rejects negative time before a permissive provider is dispatched",
		not _finite3(environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), -0.25))
			and negative_time_field.world_sample_calls == 0, str(negative_time_field.world_sample_calls))

	for bad_output: PackedFloat64Array in [
		PackedFloat64Array([1.0, 2.0]), PackedFloat64Array([1.0, NAN, 3.0]),
	]:
		var bad_field := SyntheticWorldWind.new()
		bad_field.override_enabled = true
		bad_field.override_value = bad_output
		var bad_provider_environment: Variant = SimEnvironment.new()
		bad_provider_environment.weather = bad_field
		_check("Environment fails closed on malformed provider wind %s" % str(bad_output),
			not _finite3(bad_provider_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1.0)))

	var wrong_size_environment: Variant = SimEnvironment.new()
	wrong_size_environment.weather = SyntheticWorldWind.new()
	wrong_size_environment.turbulence = func(_time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.5, -0.25])
	_check("Environment fails closed on malformed turbulence length",
		not _finite3(wrong_size_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1.0)))

	var nonfinite_noise_environment: Variant = SimEnvironment.new()
	nonfinite_noise_environment.weather = SyntheticWorldWind.new()
	nonfinite_noise_environment.turbulence = func(_time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([0.5, NAN, -0.25])
	_check("Environment fails closed on nonfinite turbulence",
		not _finite3(nonfinite_noise_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1.0)))

	var wrong_type_environment: Variant = SimEnvironment.new()
	wrong_type_environment.weather = SyntheticWorldWind.new()
	wrong_type_environment.turbulence = func(_time_s: float) -> Variant:
		return [0.5, -0.25, 0.125]
	_check("Environment fails closed on non-packed turbulence output",
		not _finite3(wrong_type_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1.0)))

	var overflow_field := SyntheticWorldWind.new()
	overflow_field.override_enabled = true
	overflow_field.override_value = PackedFloat64Array([1.0e308, 0.0, 0.0])
	var overflow_environment: Variant = SimEnvironment.new()
	overflow_environment.weather = overflow_field
	overflow_environment.turbulence = func(_time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([1.0e308, 0.0, 0.0])
	_check("Environment fails closed when finite wind and noise overflow on addition",
		not _finite3(overflow_environment.wind_world(PackedFloat64Array([0.0, 0.0, 0.0]), 1.0)))


func _check_air_world() -> void:
	var config: Dictionary = WindConfig.upgrade_column(WindConfig.defaults(), {
		atmosphere_mode = "standard_column",
		field_elevation_m = 1000.0,
		temperature_c = 15.0,
		qnh_hpa = 1013.25,
		relative_humidity_pct = 0.0,
	})
	var built: Dictionary = WindField.build(config)
	_check("standard-column field fixture builds", built.ok, str(built.errors))
	if not built.ok:
		return
	var environment: Variant = SimEnvironment.new()
	environment.weather = built.field
	var position := PackedFloat64Array([250.0, -75.0, 200.0])
	var actual: Dictionary = environment.air_world(position)
	var expected: Dictionary = PhysicsAtmosphere.standard_column(800.0)
	_check("air_world uses field elevation minus NED down for geometric altitude",
		actual == expected and actual != PhysicsAtmosphere.standard_column(-200.0), str(actual))
	var detached_expected: Dictionary = expected.duplicate(true)
	actual.rho_kgm3 = -1.0
	_check("air_world atmosphere result is detached", environment.air_world(position) == detached_expected)

	for invalid_position: PackedFloat64Array in [
		PackedFloat64Array(), PackedFloat64Array([0.0, 0.0]),
		PackedFloat64Array([NAN, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, INF]),
	]:
		var invalid_air: Dictionary = environment.air_world(invalid_position)
		_check("air_world rejects malformed position %s" % str(invalid_position),
			invalid_air.has("ok") and not bool(invalid_air.ok), str(invalid_air))
	var outside_column: Dictionary = environment.air_world(PackedFloat64Array([0.0, 0.0, -10000.001]))
	_check("air_world propagates out-of-column failure", outside_column.has("ok") and not bool(outside_column.ok), str(outside_column))


func _initialize() -> void:
	_check_legacy_compatibility()
	_check_world_dispatch_and_repeatability()
	_check_fail_closed_inputs()
	_check_air_world()
	print("spatial wind contract: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
