extends SceneTree

const Profile := preload("res://physics/glow/profile.gd")
const Vibration := preload("res://physics/glow/vibration.gd")

var checks := 0
var failures := 0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		print("FAIL: " + label)


func _initialize() -> void:
	var two_loaded: Dictionary = Profile.load_file("res://data/glow/os_max_55ax_candidate.json")
	var four_loaded: Dictionary = Profile.load_file("res://data/glow/os_fs_64v_candidate.json")
	check("both generated geometry profiles load", two_loaded.ok and four_loaded.ok)
	if not two_loaded.ok or not four_loaded.ok:
		quit(1)
		return
	var two_model: Dictionary = two_loaded.model
	var four_model: Dictionary = four_loaded.model
	var two_before: Dictionary = two_model.duplicate(true)
	var two_prepared: Dictionary = Vibration.prepare(two_model)
	var four_prepared: Dictionary = Vibration.prepare(four_model)
	check("two-stroke geometry prepares", two_prepared.ok)
	check("four-stroke geometry prepares", four_prepared.ok)
	if not two_prepared.ok or not four_prepared.ok:
		quit(1)
		return
	var two_geometry: Dictionary = two_prepared.prepared
	var mass: float = two_geometry.reciprocating_mass_kg
	var radius: float = two_geometry.crank_radius_m
	var rod: float = two_geometry.connecting_rod_m
	var phase: float = 0.73
	var omega: float = 700.0
	var alpha: float = 250.0
	var h: float = 0.0001
	var position_plus: float = _position(phase + h, radius, rod)
	var position_center: float = _position(phase, radius, rod)
	var position_minus: float = _position(phase - h, radius, rod)
	var first_fd: float = (position_plus - position_minus) / (2.0 * h)
	var second_fd: float = (position_plus - 2.0 * position_center + position_minus) / (h * h)
	var forced: Dictionary = Vibration.evaluate(two_prepared, phase, omega, alpha)
	var expected_force: float = -mass * (second_fd * omega * omega + first_fd * alpha)
	check("exact source force includes angular acceleration term", forced.ok and absf(forced.source_force_n - expected_force) <= maxf(0.0001, absf(expected_force) * 0.00001))
	check("variable-speed result is not labeled constant-speed", forced.ok and not forced.constant_speed_assumption)
	var alpha_only: Dictionary = Vibration.evaluate(two_prepared, phase, 0.0, alpha)
	check("variable-RPM acceleration excites the source at zero instantaneous speed", alpha_only.ok and absf(alpha_only.source_force_n + mass * first_fd * alpha) < 0.0001)
	var negative_alpha: Dictionary = Vibration.evaluate(two_prepared, phase, omega, -alpha)
	check("order peak supports positive and negative acceleration", negative_alpha.ok and absf(negative_alpha.order_1x_force_peak_n - forced.order_1x_force_peak_n) < 1e-10 and absf(negative_alpha.order_2x_force_peak_n - forced.order_2x_force_peak_n) < 1e-10)
	_check_orders(two_prepared, omega, 0.0)
	_check_orders(two_prepared, omega, 110.0)
	_check_family_invariance(two_model, two_prepared)
	_check_domains(two_model, two_prepared)
	_check_mass_sensitivity(two_model, two_prepared, phase, omega)
	check("observer leaves loaded profile data unchanged", two_model == two_before)
	var prepared_before: Dictionary = two_prepared.duplicate(true)
	Vibration.evaluate(two_prepared, phase, omega, alpha, 0.6)
	check("observer leaves prepared geometry unchanged", two_prepared == prepared_before)
	check("prepared geometry and evaluation results are read-only", two_prepared.is_read_only() and two_geometry.is_read_only() and forced.is_read_only())
	print("NITRO vibration source observer: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check_orders(prepared: Dictionary, omega: float, alpha: float) -> void:
	var count: int = 1024
	var cos_1 := 0.0
	var sin_1 := 0.0
	var cos_2 := 0.0
	var sin_2 := 0.0
	var valid := true
	for index: int in count:
		var theta: float = TAU * float(index) / float(count)
		var value: Dictionary = Vibration.evaluate(prepared, theta, omega, alpha)
		valid = valid and value.ok
		cos_1 += value.source_force_n * cos(theta)
		sin_1 += value.source_force_n * sin(theta)
		cos_2 += value.source_force_n * cos(2.0 * theta)
		sin_2 += value.source_force_n * sin(2.0 * theta)
	var projected_1: float = 2.0 * sqrt(cos_1*cos_1 + sin_1*sin_1) / float(count)
	var projected_2: float = 2.0 * sqrt(cos_2*cos_2 + sin_2*sin_2) / float(count)
	var reference: Dictionary = Vibration.evaluate(prepared, 0.4, omega, alpha)
	check("order spectrum includes omega-squared and omega-dot terms at 1X", valid and absf(projected_1 - reference.order_1x_force_peak_n) <= reference.order_1x_force_peak_n * 0.00001)
	check("order spectrum includes omega-squared and omega-dot terms at 2X", valid and absf(projected_2 - reference.order_2x_force_peak_n) <= reference.order_2x_force_peak_n * 0.00001)
	check("zero-angular-acceleration result is explicitly labeled constant-speed", reference.ok and reference.constant_speed_assumption == (alpha == 0.0))


func _check_family_invariance(two_model: Dictionary, two_prepared: Dictionary) -> void:
	var four_same_mechanics: Dictionary = two_model.duplicate(true)
	four_same_mechanics.family = "glow_4t"
	four_same_mechanics.identity.cycle_revolutions = 2
	var four_prepared: Dictionary = Vibration.prepare(four_same_mechanics)
	check("same slider-crank geometry prepares for either family", four_prepared.ok)
	if not four_prepared.ok:
		return
	var a: Dictionary = Vibration.evaluate(two_prepared, 1.2, 800.0, -125.0, 0.4)
	var b: Dictionary = Vibration.evaluate(four_prepared, 1.2, 800.0, -125.0, 0.4)
	check("identical mechanics produce identical source force across engine family", a.ok and b.ok and a.source_force_n == b.source_force_n)
	check("identical mechanics produce identical inertia orders across engine family", a.order_1x_force_peak_n == b.order_1x_force_peak_n and a.order_2x_force_peak_n == b.order_2x_force_peak_n)
	check("firing cadence follows 360/720-degree profile cycle", a.firing_order == 1.0 and b.firing_order == 0.5 and a.opportunity_frequency_hz == 2.0 * b.opportunity_frequency_hz)
	check("expected successful-fire rate uses observed fraction", absf(a.mean_successful_fire_rate_hz - a.opportunity_frequency_hz * 0.4) < 1e-12)


func _check_domains(two_model: Dictionary, two_prepared: Dictionary) -> void:
	var bad_ratio: Dictionary = two_model.duplicate(true)
	bad_ratio.parameters.rod_to_crank_radius_ratio = 1.99
	check("rod/crank ratio below real-valued solver domain is rejected", not Vibration.prepare(bad_ratio).ok)
	var bad_volume: Dictionary = two_model.duplicate(true)
	bad_volume.parameters.displacement_m3 *= 1.01
	check("bore/stroke volume mismatch is rejected", not Vibration.prepare(bad_volume).ok)
	check("negative angular speed is rejected", not Vibration.evaluate(two_prepared, 0.2, -1.0, 0.0).ok)
	check("nonfinite phase is rejected", not Vibration.evaluate(two_prepared, INF, 1.0, 0.0).ok)
	check("nonfinite angular acceleration is rejected", not Vibration.evaluate(two_prepared, 0.2, 1.0, INF).ok)
	check("firing fraction outside zero-to-one is rejected", not Vibration.evaluate(two_prepared, 0.2, 1.0, 0.0, 1.01).ok)
	var malformed: Dictionary = Vibration.prepare({family = "glow_2t", parameters = {}})
	check("missing mechanical inputs are rejected", not malformed.ok)
	var forged_geometry: Dictionary = two_prepared.prepared.duplicate(true)
	forged_geometry.erase("cosine_1x_displacement_m")
	var forged: Dictionary = {ok = true, prepared = forged_geometry}
	check("malformed prepared dictionaries fail safely", not Vibration.evaluate(forged, 0.2, 1.0, 0.0).ok)
	check("empty prepared geometry fails safely", not Vibration.evaluate({ok = true, prepared = {}}, 0.2, 1.0, 0.0).ok)


func _check_mass_sensitivity(two_model: Dictionary, two_prepared: Dictionary, phase: float, omega: float) -> void:
	var low_model: Dictionary = two_model.duplicate(true)
	var high_model: Dictionary = two_model.duplicate(true)
	low_model.parameters.reciprocating_mass_kg *= 0.01 / 0.025
	high_model.parameters.reciprocating_mass_kg *= 0.05 / 0.025
	var low: Dictionary = Vibration.prepare(low_model)
	var high: Dictionary = Vibration.prepare(high_model)
	var low_value: Dictionary = Vibration.evaluate(low, phase, omega, 0.0)
	var nominal_value: Dictionary = Vibration.evaluate(two_prepared, phase, omega, 0.0)
	var high_value: Dictionary = Vibration.evaluate(high, phase, omega, 0.0)
	check("one-to-five-percent dry-mass sensitivity is explicit and linear", low.ok and high.ok and absf(nominal_value.source_force_n / low_value.source_force_n - 2.5) < 1e-12 and absf(high_value.source_force_n / low_value.source_force_n - 5.0) < 1e-12)


func _position(theta: float, radius: float, rod: float) -> float:
	var sine: float = sin(theta)
	return radius * (1.0 - cos(theta)) + rod - sqrt(rod * rod - radius * radius * sine * sine)
