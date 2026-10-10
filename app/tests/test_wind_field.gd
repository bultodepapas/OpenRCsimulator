# M5 wind foundation: validated configs and known-answer uniform/gust field samples.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Config := preload("res://physics/wind_config.gd")
const WeatherSampler := preload("res://physics/wind_field.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 1e-12) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not is_finite(actual[i]) or absf(actual[i] - expected[i]) > tolerance:
			return false
	return true


func _field(changes: Dictionary = {}) -> Variant:
	var raw: Dictionary = Config.defaults()
	for key: Variant in changes:
		raw[key] = changes[key]
	var result: Dictionary = WeatherSampler.build(raw)
	if not result.ok:
		printerr("wind field fixture rejected: ", result.errors)
		return null
	return result.field


func _validate_configs() -> void:
	var defaults: Dictionary = Config.defaults()
	var validated: Dictionary = Config.validate(defaults)
	_check("defaults validate", validated.ok and validated.config == defaults, str(validated.errors))
	var wrapped: Dictionary = defaults.duplicate(true)
	wrapped.from_deg = 360.0
	validated = Config.validate(wrapped)
	_check("360 degrees canonicalizes to 0 without rounding other fields", validated.ok and validated.config.from_deg == 0.0)
	var precise: Dictionary = defaults.duplicate(true)
	precise.speed_mps = 1.2345678901234567
	validated = Config.validate(precise)
	_check("valid float64 setting is not rounded", validated.ok and validated.config.speed_mps == precise.speed_mps)

	for mutation: Dictionary in [
		{ key = "speed_mps", value = true },
		{ key = "speed_mps", value = NAN },
		{ key = "speed_mps", value = INF },
		{ key = "speed_mps", value = -0.01 },
		{ key = "speed_mps", value = 15.01 },
		{ key = "from_deg", value = 360.01 },
		{ key = "gust_mps", value = -0.01 },
		{ key = "gust_up_mps", value = 8.01 },
		{ key = "gust_duration_s", value = 0.49 },
		{ key = "gust_period_s", value = 120.01 },
		{ key = "gust_delay_s", value = -0.01 },
	]:
		var bad: Dictionary = defaults.duplicate(true)
		bad[mutation.key] = mutation.value
		_check("reject invalid %s=%s" % [mutation.key, mutation.value], not Config.validate(bad).ok)
	var boolean_period: Dictionary = defaults.duplicate(true)
	boolean_period.gust_period_s = true
	_check("boolean period is not numeric", not Config.validate(boolean_period).ok)
	var reversed: Dictionary = defaults.duplicate(true)
	reversed.gust_duration_s = 5.0
	reversed.gust_period_s = 4.0
	_check("period shorter than duration is rejected", not Config.validate(reversed).ok)
	var missing: Dictionary = defaults.duplicate(true)
	missing.erase("gust_delay_s")
	_check("required field cannot be omitted", not Config.validate(missing).ok)
	var unknown: Dictionary = defaults.duplicate(true)
	unknown.extra = 1.0
	_check("unknown fields are rejected", not Config.validate(unknown).ok)
	_check("non-object is rejected", not Config.validate(PackedFloat64Array([1.0])).ok)

	var preset_ids := PackedStringArray()
	for entry: Dictionary in Config.presets():
		preset_ids.append(str(entry.id))
		_check("preset %s validates" % str(entry.id), Config.validate(entry.config).ok)
	_check("required preset set", preset_ids == PackedStringArray(["calm", "steady", "crosswind", "gusty", "updraft", "turbulent", "hot-high", "cool-dense"]))
	_check("unknown preset is empty", Config.preset("missing").is_empty())
	var steady: Dictionary = Config.preset("steady")
	var crosswind: Dictionary = Config.preset("crosswind")
	var gusty: Dictionary = Config.preset("gusty")
	var updraft: Dictionary = Config.preset("updraft")
	_check("steady preset has specified values", steady.speed_mps == 3.0 and steady.from_deg == 270.0)
	_check("crosswind preset has specified values", crosswind.speed_mps == 5.0 and crosswind.from_deg == 0.0)
	_check("gusty preset has specified values", gusty.speed_mps == 3.0 and gusty.from_deg == 270.0
		and gusty.gust_mps == 3.0 and gusty.gust_up_mps == 1.5)
	_check("updraft preset has specified values", updraft.gust_up_mps == 2.0 and updraft.gust_period_s == 10.0)
	_check("summary is English calm", Config.summary(Config.preset("calm")) == "Calm")


func _check_cardinals() -> void:
	var cases: Array[Dictionary] = [
		{ from_deg = 0.0, expected = M.v3(-5.0, 0.0, 0.0) },
		{ from_deg = 90.0, expected = M.v3(0.0, -5.0, 0.0) },
		{ from_deg = 180.0, expected = M.v3(5.0, 0.0, 0.0) },
		{ from_deg = 270.0, expected = M.v3(0.0, 5.0, 0.0) },
	]
	for entry: Dictionary in cases:
		var field: Variant = _field({ "speed_mps": 5.0, "from_deg": entry.from_deg })
		var sample: PackedFloat64Array = field.sample(0.0)
		_check("wind from %d points downwind exactly" % int(entry.from_deg), _near(sample, entry.expected, 0.0), str(sample))
	var up: Variant = _field({ "gust_up_mps": 2.0 })
	_check("positive vertical gust is upward in NED", _near(up.sample(4.0), M.v3(0.0, 0.0, -2.0), 1e-12))
	var canonical_360: Dictionary = Config.defaults()
	canonical_360.speed_mps = 5.0
	canonical_360.from_deg = 360.0
	var wrapped_field: Dictionary = WeatherSampler.build(canonical_360)
	_check("360 degree wind has exact north-from vector", wrapped_field.ok
		and _near(wrapped_field.field.sample(0.0), M.v3(-5.0, 0.0, 0.0), 0.0))

	var calm: Variant = _field()
	_check("calm field fast-paths to exact zero", calm.is_calm() and calm.sample(8.0) == M.v3(0.0, 0.0, 0.0))
	var state: PackedFloat64Array = RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(15.0, 0.0, 0.0),
		M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var northward_air: Variant = _field({ "speed_mps": 15.0, "from_deg": 180.0 })
	var air: Dictionary = Air.compute(state, northward_air.sample(0.0))
	_check("matching ground velocity and wind gives finite zero airspeed",
		air.V == 0.0 and air.alpha == 0.0 and air.beta == 0.0 and air.qbar == 0.0)


func _check_gust() -> void:
	var field: Variant = _field({
		"gust_mps": 3.0, "gust_up_mps": 1.5,
		"gust_duration_s": 4.0, "gust_period_s": 12.0, "gust_delay_s": 2.0,
	})
	var mean := M.v3(0.0, 0.0, 0.0)
	_check("gust starts at exact mean", _near(field.sample(2.0), mean, 0.0))
	_check("halfway reaches component peaks", _near(field.sample(4.0), M.v3(-3.0, 0.0, -1.5), 1e-12))
	_check("gust ends at exact mean", _near(field.sample(6.0), mean, 0.0))
	_check("gap remains exactly mean", _near(field.sample(8.0), mean, 0.0))
	_check("next event starts at exact mean", _near(field.sample(14.0), mean, 0.0))
	_check("repeated event reaches the same peak", _near(field.sample(16.0), M.v3(-3.0, 0.0, -1.5), 1e-12))

	# Composite trapezoidal integration over the complete cosine pulse: integral = amplitude × duration / 2.
	const N := 1024
	var north_integral := 0.0
	var down_integral := 0.0
	var step := 4.0 / N
	for i in range(N + 1):
		var sample: PackedFloat64Array = field.sample(2.0 + i * step)
		var weight := 0.5 if i == 0 or i == N else 1.0
		north_integral += weight * sample[0]
		down_integral += weight * sample[2]
	north_integral *= step
	down_integral *= step
	_check("horizontal gust area is A·T/2", absf(north_integral - (-3.0 * 4.0 / 2.0)) < 1e-10, str(north_integral))
	_check("vertical gust area is A·T/2 with NED sign", absf(down_integral - (-1.5 * 4.0 / 2.0)) < 1e-10, str(down_integral))

	_check("time above shader wrap uses simulation time", _near(field.sample(1027.0), mean, 0.0))
	var first: PackedFloat64Array = field.sample(4.0)
	field.sample(100.0)
	field.sample(3.25)
	_check("query order does not alter repeated samples", field.sample(4.0).to_byte_array() == first.to_byte_array())
	_check("negative time is rejected with nonfinite sample", not is_finite(field.sample(-1.0)[0]))
	_check("nonfinite time is rejected", not is_finite(field.sample(NAN)[1]))


func _check_no_aliasing() -> void:
	var raw: Dictionary = Config.preset("gusty")
	var built: Dictionary = WeatherSampler.build(raw)
	_check("gusty config builds", built.ok)
	var field: Variant = built.field
	var before: PackedFloat64Array = field.sample(4.0)
	raw.speed_mps = 10.0
	var exposed: Dictionary = field.configuration()
	exposed.speed_mps = 12.0
	var returned: PackedFloat64Array = field.sample(4.0)
	returned[0] = 999.0
	_check("input, config result and sampled vectors cannot mutate field internals",
		field.sample(4.0).to_byte_array() == before.to_byte_array())
	var invalid: Dictionary = WeatherSampler.build({ format = Config.FORMAT })
	_check("build failure returns null field and diagnostics", not invalid.ok and invalid.field == null and not invalid.errors.is_empty())


func _initialize() -> void:
	_validate_configs()
	_check_cardinals()
	_check_gust()
	_check_no_aliasing()
	print("wind field: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
