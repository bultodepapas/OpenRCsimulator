# E5b: rigid-limit nose-over oracle and synthetic resistance-patch verification.
# Test fixtures only: no aircraft, field or production force changes.
extends SceneTree

const M: Script = preload("res://physics/math3d.gd")
const RB: Script = preload("res://physics/rigid_body.gd")
const Sim: Script = preload("res://sim/simulation.gd")
const Ground: Script = preload("res://physics/ground_contact.gd")
const AD: Script = preload("res://physics/aircraft_data.gd")
const G: float = 9.80665
const DATA: Array[String] = ["gp_extra_300s_60", "p51d_mustang_120"]

var count: int = 0
var failures: int = 0
var report: Dictionary = {}
var scope: String = "full"


func check(label: String, ok: bool, detail: String = "") -> void:
	count += 1
	print(("ok " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func attitude(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.quat(s[6], s[7], s[8], s[9])


func pitch_of(s: PackedFloat64Array) -> float:
	return M.q_to_euler(attitude(s))[1]


func geometric_pitch(gear: Dictionary) -> float:
	var a: PackedFloat64Array = gear.contacts[0].position
	var b: PackedFloat64Array = gear.contacts[2].position
	return atan2(a[2] - b[2], a[0] - b[0])


func oracle(gear: Dictionary, pitch: float) -> Dictionary:
	# Hand rigid-gear lever arms, independent of evaluated contact loads.
	var r: PackedFloat64Array = gear.contacts[0].position
	var d: float = cos(pitch) * r[0] + sin(pitch) * r[2]
	var h: float = -sin(pitch) * r[0] + cos(pitch) * r[2]
	return {d_m = d, h_m = h, ratio = d / h, pitch_deg = rad_to_deg(pitch)}


func pose(gear: Dictionary, pitch: float, sag: float, speed: float) -> PackedFloat64Array:
	var o: Dictionary = oracle(gear, pitch)
	return RB.make_state(M.v3(0, 0, -o.h_m + sag),
		M.v3(speed * cos(pitch), 0, speed * sin(pitch)), M.q_from_euler(0, pitch, 0), M.v3(0, 0, 0))


func ground_load(s: PackedFloat64Array, gear: Dictionary, surfaces: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	var load: PackedFloat64Array = Ground.loads(s, gear, 0.0, surfaces)
	return load if load.size() == 6 else PackedFloat64Array([0, 0, 0, 0, 0, 0])


func normal(s: PackedFloat64Array, gear: Dictionary, index: int) -> float:
	var single: Dictionary = gear.duplicate()
	single.contacts = [gear.contacts[index]]
	var loads: PackedFloat64Array = ground_load(s, single)
	var world: PackedFloat64Array = M.q_rotate(attitude(s), M.v3(loads[0], loads[1], loads[2]))
	return -world[2]


func static_checks(model: Dictionary) -> Dictionary:
	var gear: Dictionary = model.landing_gear.duplicate(true)
	var o: Dictionary = oracle(gear, 0.0)
	var sag: float = model.mass_kg * G / (gear.contacts[0].stiffness + gear.contacts[1].stiffness)
	var s: PackedFloat64Array = pose(gear, 0.0, sag, 3.0)
	var comp: PackedFloat64Array = Ground.compressions(s, gear)
	check("tail-up fixture has loaded mains and clear tail", comp[0] > 0 and comp[1] > 0 and comp[2] < 0, str(comp))
	var ratios: Array = []
	for fraction in [0.98, 1.0, 1.02]:
		var mu: float = fraction * o.ratio
		gear.rolling_resistance = mu
		var loads: PackedFloat64Array = ground_load(s, gear)
		var n: float = -loads[2]
		var expected: float = n * (o.d_m - mu * o.h_m)
		check("main-only pitch moment follows N(d - mu*h)", absf(loads[4] - expected) < 1e-10 * model.mass_kg * G,
			str([mu, loads[4], expected]))
		check("main-only drag and normal force agree with oracle", absf(n - model.mass_kg * G) < 1e-9 * model.mass_kg * G
			and absf(loads[0] + mu * n) < 1e-9 * n)
		if fraction != 1.0:
			check("pitch sign changes across 2 percent threshold bracket", loads[4] * (1.0 - fraction) > 0)
		ratios.append({mu = mu, pitch_moment_nm = loads[4], normal_n = n})
	# Locate the evaluator's zero without giving the bisection the oracle threshold.
	var low: float = 0.0
	var high: float = 0.79
	for iteration in range(35):
		var middle: float = (low + high) / 2.0
		gear.rolling_resistance = middle
		if ground_load(s, gear)[4] > 0:
			low = middle
		else:
			high = middle
	check("evaluated pitch-zero threshold agrees with d/h within 2 percent", absf((low + high) / 2.0 / o.ratio - 1.0) < 0.02)
	# Friction circle must prevent a high requested resistance from creating unbounded overturning load.
	gear.side_friction = 0.5 * o.ratio
	gear.rolling_resistance = 1.0
	var capped: PackedFloat64Array = ground_load(s, gear)
	check("friction cap below threshold prevents nose-down moment", capped[4] > 0
		and absf(capped[0] / capped[2] - gear.side_friction) < 1e-10)
	return {oracle = o, samples = ratios, pitch_zero_bracket = [low, high], tail_compression_m = comp[2]}


func stiff_gear(model: Dictionary, scale: float) -> Dictionary:
	var gear: Dictionary = model.landing_gear.duplicate(true)
	for c in gear.contacts:
		c.stiffness *= scale
		c.damping *= sqrt(scale)
		c.damping_onset /= scale
	gear.static_sag /= scale
	return gear


func ramp(model: Dictionary, hz: int, scale: float, ramp_rate: float) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var gear: Dictionary = stiff_gear(model, scale)
	var angle: float = geometric_pitch(gear)
	var o: Dictionary = oracle(gear, angle)
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
		gear.rolling_resistance = maxf(0.0, t - 1.5) * ramp_rate
		var load: PackedFloat64Array = ground_load(s, gear)
		var world: PackedFloat64Array = M.q_rotate(attitude(s), M.v3(load[0], load[1], load[2]))
		# Horizontal tow through CG cancels ground drag; no added torque. Keeps rolling speed resolved
		# while approaching the quasi-static moment limit. This is NOT an unpowered field coast-down.
		var tow: PackedFloat64Array = M.q_rotate(M.q_conj(attitude(s)), M.v3(-world[0], -world[1], 0))
		for axis in range(3):
			load[axis] += tow[axis]
		return load
	var reset_ok: bool = sim.reset(pose(gear, angle, gear.static_sag, 3.0))
	var previous_mu: float = 0.0
	var separation: Dictionary = {}
	var unloading_mu: float = -1.0
	var rows: Array = []
	var initialized: bool = false
	var sampled_initial: bool = false
	for tick in range(roundi((1.5 + 0.79 / ramp_rate) * hz)):
		sim.step()
		if not sim.fault_reason.is_empty():
			break
		var mu: float = maxf(0.0, sim.time() - 1.5) * ramp_rate
		var comp: PackedFloat64Array = Ground.compressions(sim.state, gear)
		var tail_n: float = normal(sim.state, gear, 2)
		if sim.time() >= 1.5:
			if not sampled_initial:
				initialized = comp[2] > 0.0 and tail_n > 0.0
				sampled_initial = true
			if unloading_mu < 0 and tail_n <= 0:
				unloading_mu = mu
			if comp[2] <= 0:
				separation = {mu = mu, bracket = [previous_mu, mu], time_s = sim.time(),
					pitch_deg = rad_to_deg(pitch_of(sim.state)), pitch_rate_rad_s = sim.state[11],
					main_compression_m = comp[0], tail_compression_m = comp[2]}
				break
		if tick % maxi(1, roundi(float(hz) / 10.0)) == 0:
			rows.append([sim.time(), mu, tail_n, comp[2], rad_to_deg(pitch_of(sim.state))])
		previous_mu = mu
	var result: Dictionary = {hz = hz, stiffness_scale = scale, ramp_rate_per_s = ramp_rate,
		oracle = o, reset_ok = reset_ok, initialized_loaded_tail = initialized,
		fault = sim.fault_reason, separation = separation, first_zero_tail_force_mu = unloading_mu, rows = rows}
	sim.free()
	return result


func patch_trial(model: Dictionary, hz: int, fraction: float) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var gear: Dictionary = model.landing_gear.duplicate(true)
	var o: Dictionary = oracle(gear, 0.0)
	var factor: float = fraction * o.ratio / gear.rolling_resistance
	check("synthetic patch factor is within supported surface bounds", factor >= 0.5 and factor <= 20.0)
	var surfaces: PackedFloat64Array = PackedFloat64Array([
		0, 10, -10, 10, 1, factor, -INF, INF, -INF, INF, 1, 1])
	var sag: float = model.mass_kg * G / (gear.contacts[0].stiffness + gear.contacts[1].stiffness)
	var initial: PackedFloat64Array = pose(gear, 0.0, sag, 3.0)
	initial[0] = -o.d_m - 0.06 # Mains start 60 mm before the patch, tail already clear.
	var outside: PackedFloat64Array = ground_load(initial, gear, surfaces)
	var inside: PackedFloat64Array = initial.duplicate()
	inside[0] += 0.12
	var on_patch: PackedFloat64Array = ground_load(inside, gear, surfaces)
	check("patch lookup scales longitudinal drag at wheel location", absf(on_patch[0] / outside[0] - factor) < 1e-10)
	check("patch moment has expected threshold sign", on_patch[4] * (1.0 - fraction) > 0)
	var sim: Node = Sim.new()
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return ground_load(s, gear, surfaces)
	var reset_ok: bool = sim.reset(initial)
	var rows: Array = []
	var entered: bool = false
	var clear_tail: bool = true
	var collapse: bool = false
	var peak_pitch: float = 0.0
	for tick in range(roundi(0.15 * hz)):
		sim.step()
		if not sim.fault_reason.is_empty():
			break
		var r: PackedFloat64Array = M.q_rotate(attitude(sim.state), gear.contacts[0].position)
		entered = entered or sim.state[0] + r[0] > 0
		clear_tail = clear_tail and Ground.compressions(sim.state, gear)[2] < 0
		collapse = collapse or Ground.collapsed(sim.state, gear)
		peak_pitch = maxf(peak_pitch, pitch_of(sim.state))
		rows.append([sim.time(), sim.state[0] + r[0], rad_to_deg(pitch_of(sim.state)), sim.state[11]])
	var result: Dictionary = {hz = hz, fraction = fraction, rolling_factor = factor,
		effective_crr = fraction * o.ratio, reset_ok = reset_ok, entered = entered,
		fault = sim.fault_reason, tail_clear = clear_tail, collapsed = collapse,
		pitch_rad = pitch_of(sim.state), peak_pitch_rad = peak_pitch, pitch_rate_rad_s = sim.state[11], rows = rows}
	sim.free()
	check("patch coast enters with clear tail and no collapse or fault", reset_ok and entered and clear_tail
		and not collapse and result.fault.is_empty())
	check("patch coast pitch rate has predicted direction", result.pitch_rate_rad_s * (1 - fraction) > 0,
		str([fraction, result.pitch_rad, result.pitch_rate_rad_s]))
	if fraction > 1:
		check("high-resistance patch reverses initial nose-up motion", peak_pitch > result.pitch_rad)
	return result


func _initialize() -> void:
	var saved: int = Engine.physics_ticks_per_second
	if "--quick" in OS.get_cmdline_user_args():
		scope = "static-and-patch"
	for aircraft in DATA:
		Engine.physics_ticks_per_second = 240
		var loaded: Dictionary = AD.load_file("res://data/aircraft/" + aircraft + ".json")
		check(aircraft + " loads", loaded.ok, str(loaded.errors))
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var statics: Dictionary = static_checks(model)
		var trials: Array = []
		var patches: Array = []
		for hz in [240, 480, 960]:
			for fraction in [0.8, 1.3]:
				patches.append(patch_trial(model, hz, fraction))
		for i in range(2):
			var coarse: float = absf(patches[i].pitch_rad - patches[i + 2].pitch_rad)
			var fine: float = absf(patches[i + 2].pitch_rad - patches[i + 4].pitch_rad)
			check("patch pitch agrees across adjacent rates within 0.1 degree", coarse < deg_to_rad(0.1) and fine < deg_to_rad(0.1), str([coarse, fine]))
		var settings_list: Array = [] if scope != "full" else [[1920, 64.0, 0.05], [3840, 64.0, 0.05],
			[3840, 256.0, 0.05], [3840, 256.0, 0.025]]
		for settings in settings_list:
			var r: Dictionary = ramp(model, settings[0], settings[1], settings[2])
			check("rigid ramp begins with loaded tail and completes without fault", r.reset_ok and r.initialized_loaded_tail
				and r.fault.is_empty() and not r.separation.is_empty(), str(r.get("separation", {})))
			if not r.separation.is_empty():
				check("tail separation agrees with rigid d/h within 2 percent", absf(r.separation.mu / r.oracle.ratio - 1) < 0.02,
					str([r.separation.mu, r.oracle.ratio]))
				check("tail normal force is zero by geometric separation", r.first_zero_tail_force_mu >= 0
					and r.first_zero_tail_force_mu <= r.separation.mu and r.separation.bracket[0] < r.separation.bracket[1])
			trials.append(r)
		if trials.size() == 4 and trials.all(func(r: Dictionary) -> bool: return not r.separation.is_empty()):
			var rigid: float = trials[0].oracle.ratio
			check("doubling ramp tick rate changes threshold by less than 0.1 percent", absf(trials[0].separation.mu - trials[1].separation.mu) / rigid < 0.001)
			check("stiffer gear approaches rigid threshold", absf(trials[2].separation.mu - rigid) < absf(trials[1].separation.mu - rigid))
			check("halving ramp rate changes threshold by less than 0.1 percent", absf(trials[2].separation.mu - trials[3].separation.mu) / rigid < 0.001)
		report[aircraft] = {statics = statics, ramps = trials, patches = patches}
	Engine.physics_ticks_per_second = saved
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			var file: FileAccess = FileAccess.open(argument.trim_prefix("--out="), FileAccess.WRITE)
			check("report opened", file != null)
			if file != null:
				file.store_string(JSON.stringify({scope = scope, checks = count, failures = failures, results = report}, "\t") + "\n")
	print("%d checks, %d failed" % [count, failures])
	quit(1 if failures > 0 else 0)
