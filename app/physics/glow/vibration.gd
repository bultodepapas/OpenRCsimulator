extends RefCounted

## Read-only slider-crank source excitation observer.
## Positive cylinder axis is defined from TDC toward BDC; source force is the
## equal-and-opposite reaction to the reciprocating equivalent mass.

const TWO_STROKE := "glow_2t"
const FOUR_STROKE := "glow_4t"
const MIN_ROD_TO_CRANK_RATIO := 2.0
const DISPLACEMENT_RELATIVE_TOLERANCE := 0.005
const FOURIER_SAMPLE_COUNT := 256
const M := preload("res://physics/math3d.gd")
const PREPARED_KEYS := ["family", "cycle_revolutions", "bore_m", "stroke_m", "displacement_m3", "crank_radius_m", "connecting_rod_m", "reciprocating_mass_kg", "cosine_1x_displacement_m", "cosine_2x_displacement_m"]


static func prepare(profile_model: Variant) -> Dictionary:
	if not profile_model is Dictionary:
		return _fail("Profile model must be a dictionary")
	var family: Variant = profile_model.get("family", "")
	if family != TWO_STROKE and family != FOUR_STROKE:
		return _fail("Unsupported glow engine family")
	var parameters: Variant = profile_model.get("parameters", null)
	if not parameters is Dictionary:
		return _fail("Profile model has no parameter dictionary")
	for key: String in ["displacement_m3", "bore_m", "stroke_m", "rod_to_crank_radius_ratio", "reciprocating_mass_kg"]:
		if not parameters.has(key):
			return _fail("Profile is missing vibration parameter: " + key)
	for key: String in ["displacement_m3", "bore_m", "stroke_m", "reciprocating_mass_kg"]:
		if not _positive_finite(parameters[key]):
			return _fail("Vibration parameter must be a finite positive value: " + key)
	var ratio_value: Variant = parameters.rod_to_crank_radius_ratio
	if typeof(ratio_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(ratio_value)) or float(ratio_value) < MIN_ROD_TO_CRANK_RATIO:
		return _fail("Rod-to-crank ratio must be finite and at least %.1f" % MIN_ROD_TO_CRANK_RATIO)
	var bore_m: float = float(parameters.bore_m)
	var stroke_m: float = float(parameters.stroke_m)
	var displacement_m3: float = float(parameters.displacement_m3)
	var geometric_displacement_m3: float = PI * bore_m * bore_m * stroke_m * 0.25
	if not is_finite(geometric_displacement_m3) or absf(geometric_displacement_m3 - displacement_m3) > displacement_m3 * DISPLACEMENT_RELATIVE_TOLERANCE:
		return _fail("Bore and stroke do not reconstruct declared swept displacement within 0.5%")
	if profile_model.has("identity") and profile_model.identity is Dictionary:
		var expected_revolutions: int = 1 if family == TWO_STROKE else 2
		if int(profile_model.identity.get("cycle_revolutions", expected_revolutions)) != expected_revolutions:
			return _fail("Profile cycle identity does not match its engine family")
	var crank_radius_m: float = stroke_m * 0.5
	var connecting_rod_m: float = float(ratio_value) * crank_radius_m
	var radius_squared: float = crank_radius_m * crank_radius_m
	var rod_squared: float = connecting_rod_m * connecting_rod_m
	if not _positive_finite(crank_radius_m) or not _positive_finite(connecting_rod_m) \
			or not _positive_finite(radius_squared) or not _positive_finite(rod_squared):
		return _fail("Derived slider-crank lengths are outside the finite numerical domain")
	var coefficient_1x: float = 0.0
	var coefficient_2x: float = 0.0
	for sample_index: int in FOURIER_SAMPLE_COUNT:
		var theta: float = TAU * float(sample_index) / float(FOURIER_SAMPLE_COUNT)
		var position_m: float = _piston_position(theta, crank_radius_m, connecting_rod_m)
		if not is_finite(position_m):
			return _fail("Slider-crank position is outside the finite numerical domain")
		coefficient_1x += position_m * M.cos_(theta)
		coefficient_2x += position_m * M.cos_(2.0 * theta)
	coefficient_1x *= 2.0 / float(FOURIER_SAMPLE_COUNT)
	coefficient_2x *= 2.0 / float(FOURIER_SAMPLE_COUNT)
	if not is_finite(coefficient_1x) or not is_finite(coefficient_2x):
		return _fail("Slider-crank order coefficients are outside the finite numerical domain")
	var geometry: Dictionary = {
		family = family,
		cycle_revolutions = 1 if family == TWO_STROKE else 2,
		bore_m = bore_m,
		stroke_m = stroke_m,
		displacement_m3 = displacement_m3,
		crank_radius_m = crank_radius_m,
		connecting_rod_m = connecting_rod_m,
		reciprocating_mass_kg = float(parameters.reciprocating_mass_kg),
		cosine_1x_displacement_m = coefficient_1x,
		cosine_2x_displacement_m = coefficient_2x,
	}
	geometry.make_read_only()
	var result: Dictionary = {
		ok = true,
		errors = PackedStringArray(),
		prepared = geometry,
	}
	result.make_read_only()
	return result


static func evaluate(prepared: Dictionary, crank_phase_rad: float, omega_rad_s: float, alpha_rad_s2: float, firing_fraction: float = 1.0) -> Dictionary:
	if not prepared.get("ok", false):
		return _fail("Prepared vibration geometry is invalid")
	var geometry_value: Variant = prepared.get("prepared", null)
	if not geometry_value is Dictionary or not _valid_prepared(geometry_value):
		return _fail("Prepared vibration geometry is malformed")
	if not is_finite(crank_phase_rad) or not is_finite(omega_rad_s) or not is_finite(alpha_rad_s2) or not is_finite(firing_fraction):
		return _fail("Vibration input contains a nonfinite value")
	if omega_rad_s < 0.0 or firing_fraction < 0.0 or firing_fraction > 1.0:
		return _fail("RPM and firing fraction are outside the observer domain")
	var engine: Dictionary = geometry_value
	var phase: float = fposmod(crank_phase_rad, TAU)
	if not is_finite(phase):
		return _fail("Crank phase cannot be reduced to a finite revolution")
	var radius: float = float(engine.crank_radius_m)
	var rod: float = float(engine.connecting_rod_m)
	var mass: float = float(engine.reciprocating_mass_kg)
	var sine: float = M.sin_(phase)
	var cosine: float = M.cos_(phase)
	var root_argument: float = rod * rod - radius * radius * sine * sine
	if not is_finite(root_argument) or root_argument <= 0.0:
		return _fail("Slider-crank geometry is outside its real-valued domain")
	var root: float = sqrt(root_argument)
	var position_derivative: float = radius * sine + radius * radius * sine * cosine / root
	var position_second_derivative: float = radius * cosine + radius * radius * ((cosine * cosine - sine * sine) / root + radius * radius * sine * sine * cosine * cosine / (root * root * root))
	var piston_acceleration: float = position_second_derivative * omega_rad_s * omega_rad_s + position_derivative * alpha_rad_s2
	var source_force_n: float = -mass * piston_acceleration
	var coefficient_1x: float = float(engine.cosine_1x_displacement_m)
	var coefficient_2x: float = float(engine.cosine_2x_displacement_m)
	var order_1x_force_cosine_n: float = mass * coefficient_1x * omega_rad_s * omega_rad_s
	var order_1x_force_sine_n: float = mass * coefficient_1x * alpha_rad_s2
	var order_2x_force_cosine_n: float = mass * 4.0 * coefficient_2x * omega_rad_s * omega_rad_s
	var order_2x_force_sine_n: float = mass * 2.0 * coefficient_2x * alpha_rad_s2
	var order_1x: float = sqrt(order_1x_force_cosine_n * order_1x_force_cosine_n + order_1x_force_sine_n * order_1x_force_sine_n)
	var order_2x: float = sqrt(order_2x_force_cosine_n * order_2x_force_cosine_n + order_2x_force_sine_n * order_2x_force_sine_n)
	var cycle_revolutions: int = int(engine.cycle_revolutions)
	var crank_revolutions_per_second: float = omega_rad_s / TAU
	var opportunity_hz: float = crank_revolutions_per_second / float(cycle_revolutions)
	var outputs: Array[float] = [source_force_n, order_1x, order_2x, order_1x_force_cosine_n, order_1x_force_sine_n,
		order_2x_force_cosine_n, order_2x_force_sine_n, opportunity_hz, opportunity_hz * firing_fraction]
	for value: float in outputs:
		if not is_finite(value):
			return _fail("Vibration output is nonfinite")
	var result: Dictionary = {
		ok = true,
		errors = PackedStringArray(),
		family = engine.family,
		cycle_revolutions = cycle_revolutions,
		firing_order = 1.0 / float(cycle_revolutions),
		phase_rad = phase,
		omega_rad_s = omega_rad_s,
		alpha_rad_s2 = alpha_rad_s2,
		constant_speed_assumption = alpha_rad_s2 == 0.0,
		source_force_n = source_force_n,
		order_1x_force_cosine_n = order_1x_force_cosine_n,
		order_1x_force_sine_n = order_1x_force_sine_n,
		order_2x_force_cosine_n = order_2x_force_cosine_n,
		order_2x_force_sine_n = order_2x_force_sine_n,
		order_1x_force_peak_n = order_1x,
		order_2x_force_peak_n = order_2x,
		opportunity_frequency_hz = opportunity_hz,
		mean_successful_fire_rate_hz = opportunity_hz * firing_fraction,
	}
	result.make_read_only()
	return result


static func _piston_position(theta: float, crank_radius: float, connecting_rod: float) -> float:
	var sine: float = M.sin_(theta)
	return crank_radius * (1.0 - M.cos_(theta)) + connecting_rod - sqrt(connecting_rod * connecting_rod - crank_radius * crank_radius * sine * sine)


static func _valid_prepared(engine: Dictionary) -> bool:
	if engine.size() != PREPARED_KEYS.size():
		return false
	for key: String in PREPARED_KEYS:
		if not engine.has(key):
			return false
	var family: Variant = engine.family
	if family != TWO_STROKE and family != FOUR_STROKE:
		return false
	var expected_revolutions: int = 1 if family == TWO_STROKE else 2
	if typeof(engine.cycle_revolutions) not in [TYPE_INT, TYPE_FLOAT] or int(engine.cycle_revolutions) != expected_revolutions:
		return false
	for key: String in ["bore_m", "stroke_m", "displacement_m3", "crank_radius_m", "connecting_rod_m", "reciprocating_mass_kg"]:
		if not _positive_finite(engine[key]):
			return false
	for key: String in ["cosine_1x_displacement_m", "cosine_2x_displacement_m"]:
		if typeof(engine[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(engine[key])):
			return false
	if absf(float(engine.crank_radius_m) - float(engine.stroke_m) * 0.5) > float(engine.stroke_m) * 1e-12:
		return false
	if float(engine.connecting_rod_m) / float(engine.crank_radius_m) < MIN_ROD_TO_CRANK_RATIO:
		return false
	var geometric_volume: float = PI * float(engine.bore_m) * float(engine.bore_m) * float(engine.stroke_m) * 0.25
	return is_finite(geometric_volume) and absf(geometric_volume - float(engine.displacement_m3)) <= float(engine.displacement_m3) * DISPLACEMENT_RELATIVE_TOLERANCE


static func _positive_finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) > 0.0


static func _fail(message: String) -> Dictionary:
	var empty: Dictionary = {}
	empty.make_read_only()
	var result: Dictionary = {ok = false, errors = PackedStringArray([message]), prepared = empty}
	result.make_read_only()
	return result
