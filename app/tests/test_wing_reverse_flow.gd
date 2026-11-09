## D8b-R2d-R1: stock strip seams under rotation, held wake, refinement and GE.
## Numerical continuity and consumer agreement; not aircraft physical validation.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Polar := preload("res://physics/wing_polar.gd")
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
var evaluator: GDScript = Aero
var checks := 0
var failures := 0
var max_force_jump_n := 0.0
var max_moment_jump_nm := 0.0


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	# Deliberate negative control can load a frozen historical evaluator outside app/.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reference-aero="):
			evaluator = load(argument.trim_prefix("--reference-aero="))
	var loaded := AD.load_file("res://data/aircraft/gp_extra_300s_60.json")
	check("stock Extra loads", loaded.ok)
	if loaded.ok:
		for rates in [M.v3(1, 0, 0), M.v3(1, 0.3, -0.2)]:
			for ground_up in [NAN, 299.0]:
				_strip_seams(loaded.model, rates, ground_up)
	_polar_continuation()
	_late_detachment()
	print("Refined seam maxima: force_N=", max_force_jump_n, " moment_Nm=", max_moment_jump_nm)
	print("D8b-R2d-R1 reverse flow: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _state(w: float, rates: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, -300), M.v3(-20, 0, w), M.q_identity(), rates)


func _strip_angle(w: float, rates: PackedFloat64Array, model: Dictionary, index: int) -> float:
	var state := _state(w, rates)
	return evaluator._wing_flow(state, Air.compute(state, M.v3(0, 0, 0)), ZERO, model).angles[index]


func _strip_seams(model: Dictionary, rates: PackedFloat64Array, ground_up: float) -> void:
	for index in model.envelope.station_ys.size():
		# Find the actual production wrap branch, including Godot's approximate endpoint
		# snap, independently for every strip instead of crossing all strips together.
		var low := -5.0
		var high := 5.0
		var low_positive := _strip_angle(low, rates, model, index) > 0.0
		check("strip %d bracketed %s GE=%s" % [index, rates, ground_up],
			low_positive != (_strip_angle(high, rates, model, index) > 0.0))
		for iteration in 60:
			var middle := (low+high)*0.5
			if (_strip_angle(middle, rates, model, index) > 0.0) == low_positive:
				low = middle
			else:
				high = middle
		var boundary := (low+high)*0.5
		var first_jump := 0.0
		var last_jump := 0.0
		var wake_agrees := true
		for epsilon in [1e-4, 1e-6, 1e-8, 1e-10]:
			var loads: Array = []
			for side in [-1.0, 1.0]:
				var state := _state(boundary+side*epsilon, rates)
				var air := Air.compute(state, M.v3(0, 0, 0))
				# Hold the incoming wake fixed: neighboring forces must not be masked by
				# a simultaneous wake change. Separately verify the generated source.
				loads.append(evaluator.loads(state, air, ZERO, model, 1.225, 0.0, ground_up))
				var mean_wake := 0.0
				var rows: Array = evaluator.wing_strip_loads(state, air, ZERO, model, 1.225, 0.0, ground_up)
				for row in rows:
					mean_wake += float(row.plane_speed_mps)*float(row.cl)/rows.size()
				wake_agrees = wake_agrees and absf(mean_wake-evaluator.wing_wake_velocity(state, air, ZERO, model, ground_up)) < 1e-12
			var jump := 0.0
			for component in 6:
				jump = maxf(jump, absf(loads[1][component]-loads[0][component]))
			if epsilon == 1e-4:
				first_jump = jump
			last_jump = jump
			if epsilon == 1e-10:
				for component in 3:
					max_force_jump_n = maxf(max_force_jump_n, absf(loads[1][component]-loads[0][component]))
					max_moment_jump_nm = maxf(max_moment_jump_nm, absf(loads[1][component+3]-loads[0][component+3]))
		# Godot wrapf has a small endpoint snap. This bound allows that independently
		# observed residual, but rejects the original finite 3.60/5.29 N strip jumps.
		check("strip %d held-wake seam bounded %s GE=%s jump=%s" % [index, rates, ground_up, last_jump], last_jump < 0.003)
		check("strip %d refinement has no finite multi-newton limit" % index, last_jump < first_jump*1.1)
		check("strip %d wake source matches force law" % index, wake_agrees)


func _polar_continuation() -> void:
	for close_endpoint in [false, true]:
		var raw := Fixture.raw()
		if close_endpoint:
			for name in ["positive", "negative"]:
				raw.aero.wing_polar[name].value[20] = 89.9
		var loaded := AD.validate_and_derive(raw)
		check("synthetic polar accepted near endpoint=%s" % close_endpoint, loaded.ok)
		if not loaded.ok:
			continue
		var polar: Dictionary = loaded.model.envelope.wing_polar
		for factor in [0.01, 0.5, 0.964182, 1.0, 1.024268, 6.0]:
			var bounded := true
			var physical := true
			var forward := true
			for degrees in range(-1800, 1801, 5):
				var alpha := deg_to_rad(degrees/10.0)
				var value := Polar.evaluate(alpha, 0.3, polar, factor)
				for item in value:
					bounded = bounded and is_finite(item)
				bounded = bounded and value[1] >= 0.0 and value[2] >= 0.0 and value[2] <= 1.0
				if absf(alpha) >= PI/2.0:
					physical = physical and value == Polar.evaluate(alpha, 0.3, polar)
				if absf(alpha) <= PI/4.0:
					forward = forward and value == Polar.evaluate(alpha*factor, 0.3, polar)
			check("factor %s finite, passive profile drag, bounded attachment" % factor, bounded)
			check("factor %s physical reverse polar" % factor, physical)
			check("factor %s forward stall unchanged" % factor, forward)
			for join in [-PI/2.0, -PI/4.0, PI/4.0, PI/2.0]:
				var epsilon := 1e-9
				var center := Polar.evaluate(join, 0.3, polar, factor)
				var left := Polar.evaluate(join-epsilon, 0.3, polar, factor)
				var right := Polar.evaluate(join+epsilon, 0.3, polar, factor)
				var c1 := true
				for component in 3:
					c1 = c1 and absf((center[component]-left[component])/epsilon-(right[component]-center[component])/epsilon) < 0.01
				check("factor %s C1 continuation at %s" % [factor, join], c1)
		var continuous_factor := true
		for degrees in [-88.0, -67.5, -46.0, 46.0, 67.5, 88.0]:
			var alpha := deg_to_rad(degrees)
			var shared := Polar.evaluate(alpha, 0.3, polar)
			for factor in [1.0-1e-10, 1.0+1e-10]:
				var value := Polar.evaluate(alpha, 0.3, polar, factor)
				for component in 3:
					continuous_factor = continuous_factor and absf(value[component]-shared[component]) < 1e-7
		check("continuity through progression factor one", continuous_factor)


## Valid authored tables may retain attachment above 45 degrees. Fading progression
## must never reattach a strip, or give the coupled base a different retention.
func _late_detachment() -> void:
	var raw := Fixture.raw()
	var first: Array = raw.aero.wing_polar.positive.value.slice(0, 4)
	var cd0: float = first[2]
	var cd90: float = raw.aero.wing_polar.positive.value[-2]-cd0
	for name in ["positive", "negative"]:
		var start: Array = raw.aero.wing_polar[name].value.slice(0, 4)
		start.append_array([45.0, 2.5, cd0+0.3, 1.0, 50.0, 2.4, cd0+0.5, 1.0,
			50.1, 2.3, cd0+0.51, 0.0, 70.0, 0.4, cd0+0.9, 0.0,
			90.0, 0.0, cd0+cd90, 0.0])
		raw.aero.wing_polar[name].value = start
	var loaded := AD.validate_and_derive(raw)
	check("late-detachment authored table admitted", loaded.ok)
	if not loaded.ok:
		printerr(loaded.errors)
		return
	var polar: Dictionary = loaded.model.envelope.wing_polar
	for factor in [0.01, 0.5, 0.964182, 1.0-1e-10, 1.0, 1.0+1e-10, 1.024268, 6.0]:
		for side in [-1.0, 1.0]:
			var previous := 1.0
			var monotone := true
			var coupled := true
			for step in range(1801):
				var alpha: float = side*deg_to_rad(step/10.0)
				var at_zero := Polar.evaluate(alpha, 0.0, polar, factor)
				var at_one := Polar.evaluate(alpha, 1.0, polar, factor)
				monotone = monotone and at_zero[2] <= previous+1e-14
				previous = at_zero[2]
				coupled = coupled and absf((at_one[0]-at_zero[0])-at_zero[2]) < 1e-12
			check("late-detachment retention monotone factor=%s side=%s" % [factor, side], monotone)
			check("coupled-base derivative equals retention factor=%s side=%s" % [factor, side], coupled)
