# Deterministic passivity fuzz for the flight-repair surface model.
# Run from the repo root:
#   FLIGHT_REPAIR_FUZZ_OUT="$PWD/docs/research/flight-robustness/repair-fuzz-results.json" \
#     $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/flight-robustness/repair-fuzz.gd"
# Fast CI-sized subset:
#   $(app/get-godot.sh) --headless --path app --script "$PWD/docs/research/flight-robustness/repair-fuzz.gd" -- --quick
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const AD := preload("res://physics/aircraft_data.gd")

const RNG_SEED := 0x4f50454e
const FULL_RANDOM_CASES := 100000
const QUICK_RANDOM_CASES := 5000
const POSITIVE_EPS_W := 1.0e-7

var rng := RandomNumberGenerator.new()
var model: Dictionary
var quick := false
var total_cases := 0
var positive_cases := 0
var positive_global := 0
var positive_blend := 0
var positive_local := 0
var global_cases := 0
var blend_cases := 0
var local_cases := 0
var zero_com_cases := 0
var zero_com_positive := 0
var zero_com_nonzero_loads := 0
var zero_com_peak_load_norm := 0.0
var zero_com_peak: Dictionary = {}
var transition_weight_bins := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var max_power := -INF
var max_case: Dictionary = {}
var top_positive: Array[Dictionary] = []


func _initialize() -> void:
	quick = OS.get_cmdline_user_args().has("--quick")
	rng.seed = RNG_SEED
	var loaded := AD.load_file("res://data/aircraft/jensen_ugly_stik_60.json")
	if not loaded.ok:
		printerr("Could not load aircraft: %s" % loaded.errors)
		quit(2)
		return
	model = loaded.model

	_run_com_zero_rate_cases()
	_run_transition_grid()
	_run_transition_focus_grid()
	_run_random_cases(QUICK_RANDOM_CASES if quick else FULL_RANDOM_CASES)
	var report := _report()
	print(JSON.stringify(report, "\t", true, true))
	var out_path := OS.get_environment("FLIGHT_REPAIR_FUZZ_OUT")
	if not out_path.is_empty():
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			printerr("Could not write %s (error %d)" % [out_path, FileAccess.get_open_error()])
			quit(3)
			return
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	quit(1 if positive_cases > 0 else 0)


func _report() -> Dictionary:
	return {
		"format": "openrc-aero-passivity-fuzz v1",
		"seed": RNG_SEED,
		"rng": "Godot RandomNumberGenerator; uniform angle/rate/speed, discrete full/neutral surface endpoints",
		"godot": Engine.get_version_info(),
		"aircraft": model.id,
		"aircraft_json_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://data/aircraft/jensen_ugly_stik_60.json")),
		"aero_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://physics/aero.gd")),
		"aircraft_data_script_sha256": FileAccess.get_sha256(ProjectSettings.globalize_path("res://physics/aircraft_data.gd")),
		"mode": "quick" if quick else "full",
		"random_cases": QUICK_RANDOM_CASES if quick else FULL_RANDOM_CASES,
		"positive_power_threshold_W": POSITIVE_EPS_W,
		"power_definition": "F_aero · v_air_at_CG + M_aero_CG · omega; no propulsion, gravity or moving-surface work",
		"coverage": {
			"total_cases": total_cases,
			"global_weight_cases": global_cases,
			"transition_weight_cases": blend_cases,
			"local_weight_cases": local_cases,
			"transition_weight_bins_0_to_1_by_tenth": Array(transition_weight_bins),
			"com_velocity_zero_cases": zero_com_cases,
			"com_velocity_zero_nonzero_load_cases": zero_com_nonzero_loads,
			"com_velocity_zero_positive_power_cases": zero_com_positive,
		},
		"positive_power_cases": {
			"total": positive_cases,
			"global": positive_global,
			"transition": positive_blend,
			"local": positive_local,
		},
		"maximum_sampled_power_W": max_power,
		"maximum_power_case": max_case,
		"maximum_com_zero_load_norm_case": zero_com_peak,
		"top_positive_cases": top_positive,
	}


func _run_com_zero_rate_cases() -> void:
	# A zero COM velocity does not imply zero local flow: every surface sees omega × arm.
	var rates: Array[float] = [-20.0, -5.0, -1.0, 0.0, 1.0, 5.0, 20.0]
	var commands: Array[float] = [-1.0, 0.0, 1.0]
	if quick:
		rates = [-10.0, 0.0, 10.0]
	for p in rates:
		for q in rates:
			for r in rates:
				for e in commands:
					for aileron_right in commands:
						for aileron_left in commands:
							for rudder in commands:
								_evaluate(0.0, 0.0, 0.0, [p, q, r], {
									elevator = e, aileron_right = aileron_right,
									aileron_left = aileron_left, rudder = rudder,
								}, true)


func _run_transition_grid() -> void:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var alpha_values: Array[float] = [
		deg_to_rad(-180.0), deg_to_rad(-90.0), deg_to_rad(-30.0), -env.n2, -env.n1,
		-surfaces.attached_limit, 0.0, surfaces.attached_limit, env.a1,
		env.a1 + (env.a2-env.a1)*0.25, env.a1 + (env.a2-env.a1)*0.5,
		env.a2, deg_to_rad(30.0), deg_to_rad(90.0), deg_to_rad(180.0),
	]
	var beta_values: Array[float] = [deg_to_rad(-90.0), deg_to_rad(-25.0), -env.b2, -env.b1, 0.0, env.b1, env.b2, deg_to_rad(25.0), deg_to_rad(90.0)]
	var speeds: Array[float] = [0.0, 0.001, 0.05, 0.5, 1.0, 3.0, 8.0, 15.0, 30.0, 40.0]
	var rates: Array[Array] = [
		[0.0, 0.0, 0.0], [5.0, 0.0, 0.0], [-5.0, 0.0, 0.0],
		[0.0, 5.0, 0.0], [0.0, -5.0, 0.0], [0.0, 0.0, 5.0], [0.0, 0.0, -5.0],
		[10.0, 10.0, 10.0], [-10.0, -10.0, -10.0], [10.0, 0.0, -10.0], [-10.0, 0.0, 10.0],
		[20.0, -20.0, 20.0], [-20.0, 20.0, -20.0], [100.0, -100.0, 100.0], [-100.0, 100.0, -100.0],
	]
	var controls: Array[Dictionary] = [
		{elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0},
		{elevator = 1.0, aileron_right = 1.0, aileron_left = 1.0, rudder = 1.0},
		{elevator = -1.0, aileron_right = -1.0, aileron_left = -1.0, rudder = -1.0},
		{elevator = 1.0, aileron_right = 1.0, aileron_left = -1.0, rudder = 1.0},
		{elevator = -1.0, aileron_right = -1.0, aileron_left = 1.0, rudder = -1.0},
	]
	if quick:
		alpha_values = [-PI, -env.n2, -surfaces.attached_limit, 0.0, surfaces.attached_limit, env.a1, env.a2, PI]
		beta_values = [-PI/2.0, -env.b2, -env.b1, 0.0, env.b1, env.b2, PI/2.0]
		speeds = [0.0, 0.001, 15.0, 40.0]
		rates = [[0.0,0.0,0.0], [10.0,10.0,10.0], [-10.0,0.0,10.0]]
	for alpha in alpha_values:
		for beta in beta_values:
			for speed in speeds:
				for rate in rates:
					for command in controls:
						_evaluate(alpha, beta, speed, rate, command, false)


func _run_transition_focus_grid() -> void:
	# Densely cover the blend ramps with rates at zero so one extreme panel does not mask them.
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var speeds: Array[float] = [0.001, 15.0, 40.0]
	var controls: Array[Dictionary] = [
		{elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0},
		{elevator = 1.0, aileron_right = 1.0, aileron_left = -1.0, rudder = 1.0},
		{elevator = -1.0, aileron_right = -1.0, aileron_left = 1.0, rudder = -1.0},
	]
	var steps := 8 if quick else 24
	for i in range(steps + 1):
		var fraction := float(i) / float(steps)
		var positive_alpha := lerpf(surfaces.attached_limit, env.a1, fraction)
		var negative_alpha := -lerpf(surfaces.attached_limit, env.n1, fraction)
		var beta := lerpf(surfaces.attached_limit, env.b2, fraction)
		for speed in speeds:
			for command in controls:
				for angle in [positive_alpha, negative_alpha]:
					_evaluate(angle, 0.0, speed, [0.0, 0.0, 0.0], command, false)
				for side in [-1.0, 1.0]:
					_evaluate(0.0, side * beta, speed, [0.0, 0.0, 0.0], command, false)


func _run_random_cases(count: int) -> void:
	for i in count:
		var speed := 40.0 * rng.randf()
		var alpha := rng.randf_range(-PI, PI)
		var beta := asin(rng.randf_range(-1.0, 1.0))
		var p := rng.randf_range(-100.0, 100.0)
		var q := rng.randf_range(-100.0, 100.0)
		var r := rng.randf_range(-100.0, 100.0)
		var controls := {
			elevator = _pick_surface(),
			aileron_right = _pick_surface(),
			aileron_left = _pick_surface(),
			rudder = _pick_surface(),
		}
		_evaluate(alpha, beta, speed, [p, q, r], controls, false)


func _pick_surface() -> float:
	match rng.randi_range(0, 2):
		0: return -1.0
		1: return 0.0
		_: return 1.0


func _evaluate(alpha: float, beta: float, speed: float, rate: Array, controls: Dictionary, count_zero_com: bool) -> void:
	var vel := M.v3(
		speed * cos(beta) * cos(alpha),
		speed * sin(beta),
		speed * cos(beta) * sin(alpha))
	var rates := M.v3(rate[0], rate[1], rate[2])
	var state := RB.make_state(M.v3(0.0, 0.0, -20.0), vel, M.q_identity(), rates)
	var air := Air.compute(state, M.v3(0.0, 0.0, 0.0))
	var throws: Dictionary = model.controls.throw_deg
	var right_fraction: float = controls.get("aileron_right", controls.get("aileron", 0.0))
	var left_fraction: float = controls.get("aileron_left", -controls.get("aileron", 0.0))
	var d := Aero.deflections_from_surfaces({
		elevator = controls.elevator * throws.elevator,
		aileron_right = right_fraction * throws.aileron,
		aileron_left = left_fraction * throws.aileron,
		rudder = controls.rudder * throws.rudder,
	})
	var loads: PackedFloat64Array = Aero.loads(state, air, d, model, Air.RHO_SEA_LEVEL)
	var power := loads[0]*vel[0] + loads[1]*vel[1] + loads[2]*vel[2] + loads[3]*rates[0] + loads[4]*rates[1] + loads[5]*rates[2]
	var blend := Aero.local_flow_weight(state, air, d, model)
	total_cases += 1
	if blend == 0.0:
		global_cases += 1
	elif blend == 1.0:
		local_cases += 1
	else:
		blend_cases += 1
		var bin := clampi(int(floor(blend * 10.0)), 0, 9)
		transition_weight_bins[bin] += 1
	if power > max_power:
		max_power = power
		max_case = _case_record(power, blend, speed, air, rate, controls, loads, vel, true)
	if count_zero_com:
		zero_com_cases += 1
		var load_norm := _loads_norm(loads)
		if load_norm > 1.0e-9:
			zero_com_nonzero_loads += 1
		if load_norm > zero_com_peak_load_norm:
			zero_com_peak_load_norm = load_norm
			zero_com_peak = _case_record(power, blend, speed, air, rate, controls, loads, vel, true)
	if power > POSITIVE_EPS_W:
		positive_cases += 1
		if blend <= 0.0:
			positive_global += 1
		elif blend >= 1.0:
			positive_local += 1
		else:
			positive_blend += 1
		if count_zero_com:
			zero_com_positive += 1
		var entry := _case_record(power, blend, speed, air, rate, controls, loads, vel, true)
		top_positive.append(entry)
		top_positive.sort_custom(func(lhs: Dictionary, rhs: Dictionary) -> bool: return lhs.power_W > rhs.power_W)
		if top_positive.size() > 12:
			top_positive.resize(12)


func _case_record(power: float, blend: float, speed: float, air: Dictionary, rate: Array,
		controls: Dictionary, loads: PackedFloat64Array, vel: PackedFloat64Array, include_flows: bool) -> Dictionary:
	var out := {
		power_W = power, local_flow_weight = blend, V_com_mps = speed,
		alpha_deg = rad_to_deg(air.alpha), beta_deg = rad_to_deg(air.beta),
		omega_rad_s = rate, surface_fractions = controls,
		loads_N_Nm = Array(loads), v_air_body = Array(vel),
	}
	if include_flows:
		out.local_tail_flows_body_mps = _tail_flows(vel, M.v3(rate[0], rate[1], rate[2]))
	return out


func _loads_norm(loads: PackedFloat64Array) -> float:
	var total := 0.0
	for x in loads:
		total += x*x
	return sqrt(total)


func _tail_flows(vel: PackedFloat64Array, rates: PackedFloat64Array) -> Dictionary:
	var surfaces: Dictionary = model.surfaces
	var horizontal: Dictionary = surfaces.horizontal
	var vertical: Dictionary = surfaces.vertical
	var h_arm := Aero._arm(horizontal.position, model.cg_le)
	var v_arm := Aero._arm(vertical.position, model.cg_le)
	return {
		horizontal = Array(M.add(vel, M.cross(rates, h_arm))),
		vertical = Array(M.add(vel, M.cross(rates, v_arm))),
	}
