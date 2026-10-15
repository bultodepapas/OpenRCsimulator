# DR-04a…06a (foundation slice): the multirotor plant on the shared kernel. Known answers and sign contracts from
# the drone plan (§4.2, §4.6, §4.11): hover from the closed form holds altitude and level attitude; raising the right
# rotors rolls left, the front rotors pitch up, the counter-clockwise pair yaws clockwise; rotor acceleration yaws the
# body inertially before any aerodynamic torque difference; rotor drag never does positive in-plane work; a uniform
# wind through the environment contract is Galilean; replay is exact. Research-grade estimated data, no validation.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const WeatherField := preload("res://physics/wind_field.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const Plant := preload("res://physics/multirotor/plant.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")
const LP := preload("res://tests/law_properties.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _hover_state() -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -1.5), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))


## A kernel with the plant installed and reset at hover; returns {sim, plant}.
func _hovering(environment: RefCounted = null) -> Dictionary:
	var plant: RefCounted = Plant.new()
	plant.data = Plant.research_quad()
	plant.environment = environment
	var sim: Node = Sim.new()
	root.add_child(sim)
	var ok: bool = sim.set_model(plant.build())
	sim.mass = float(plant.data.mass_kg)
	sim.inertia = plant.data.inertia_kg_m2.duplicate()
	var hover: Dictionary = plant.hover()
	sim.inputs = PackedFloat64Array([hover.duty, hover.duty, hover.duty, hover.duty])
	sim.aux = sim.inputs.duplicate()
	sim.continuous = PackedFloat64Array([hover.omega, hover.omega, hover.omega, hover.omega])
	plant.duties = sim.aux.duplicate()
	var reset_ok: bool = sim.reset(_hover_state())
	return { sim = sim, plant = plant, ok = ok and reset_ok, hover = hover }


func _run_ticks(sim: Node, ticks: int) -> bool:
	for _i in ticks:
		sim.step()
		if not sim.fault_reason.is_empty():
			return false
	return true


func _run() -> void:
	_contract_and_hover()
	_sign_contracts()
	_inertial_yaw()
	_rotor_drag_passivity()
	_galilean_wind()
	_replay()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _contract_and_hover() -> void:
	var h: Dictionary = _hovering()
	var sim: Node = h.sim
	_check("the plant installs on the kernel and resets at hover", h.ok, sim.fault_reason)
	_check("layout: four inputs, four sampled duties, four rotor speeds, no discrete modes", sim.model.input_size == 4
		and sim.model.aux_size == 4 and sim.model.continuous_size == 4 and sim.model.modes_size == 0 and sim.model.events.is_empty())
	_check("hover closed form: four thrusts carry the weight", absf(4.0 * float(h.plant.data.rotor.thrust_coefficient_n_s2) * h.hover.omega * h.hover.omega - float(h.plant.data.mass_kg) * 9.80665) < 1e-9)
	_check("one second of hover holds altitude within 1 mm and stays level",
		_run_ticks(sim, 240) and absf(sim.state[RB.POS + 2] + 1.5) < 1e-3 and absf(sim.state[RB.RATE]) < 1e-9 and absf(sim.state[RB.RATE + 1]) < 1e-9 and absf(sim.state[RB.RATE + 2]) < 1e-9,
		"z %.6f p %s q %s r %s" % [sim.state[RB.POS + 2], LP.sci(sim.state[RB.RATE]), LP.sci(sim.state[RB.RATE + 1]), LP.sci(sim.state[RB.RATE + 2])])
	_check("rotor speeds stay at the hover speed under the lag law", absf(sim.continuous[0] - h.hover.omega) < 1e-9)
	_check("the spinning momentum of matched pairs cancels", absf(sim.model.stage.call(sim.state, sim.continuous, 0.0).rotor_momentum[2]) < 1e-12)
	sim.free()


func _step_pair(indices: Array, delta: float, ticks: int) -> PackedFloat64Array:
	var h: Dictionary = _hovering()
	var sim: Node = h.sim
	var inputs: PackedFloat64Array = sim.inputs.duplicate()
	for i in indices:
		inputs[i] = clampf(inputs[i] + delta, 0.0, 1.0)
	sim.inputs = inputs
	_run_ticks(sim, ticks)
	var rates := M.v3(sim.state[RB.RATE], sim.state[RB.RATE + 1], sim.state[RB.RATE + 2])
	sim.free()
	return rates


func _sign_contracts() -> void:
	var right: PackedFloat64Array = _step_pair([0, 1], 0.05, 24) # rotors 1 and 2 are on the right
	_check("raising the right rotors rolls left (negative p), no pitch", right[0] < -1e-3 and absf(right[1]) < 1e-9, str(right))
	var front: PackedFloat64Array = _step_pair([1, 3], 0.05, 24) # rotors 2 and 4 are in front
	_check("raising the front rotors pitches up (positive q), no roll", front[1] > 1e-3 and absf(front[0]) < 1e-9, str(front))
	var ccw: PackedFloat64Array = _step_pair([1, 2], 0.05, 24) # rotors 2 and 3 turn counter-clockwise
	_check("speeding the counter-clockwise pair yaws clockwise (positive r) with no roll or pitch", ccw[2] > 1e-4 and absf(ccw[0]) < 1e-9 and absf(ccw[1]) < 1e-9, str(ccw))


func _inertial_yaw() -> void:
	# The same command with and without rotor inertia: the inertial reaction of the accelerating counter-clockwise
	# pair adds clockwise yaw in the first tick, before the aerodynamic torque difference has built up.
	var with_inertia: PackedFloat64Array = _step_pair([1, 2], 0.05, 1)
	var h: Dictionary = _hovering()
	h.plant.data.rotor.inertia_kg_m2 = 0.0
	var sim: Node = h.sim
	var inputs: PackedFloat64Array = sim.inputs.duplicate()
	inputs[1] = clampf(inputs[1] + 0.05, 0.0, 1.0)
	inputs[2] = clampf(inputs[2] + 0.05, 0.0, 1.0)
	sim.inputs = inputs
	_run_ticks(sim, 1)
	var without: float = sim.state[RB.RATE + 2]
	sim.free()
	_check("rotor acceleration yaws the body inertially: more clockwise yaw after one tick with rotor inertia than without",
		with_inertia[2] > without and without > 0.0, "with %s without %s" % [LP.sci(with_inertia[2]), LP.sci(without)])


func _rotor_drag_passivity() -> void:
	var data: Dictionary = Plant.research_quad()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var worst := -INF
	for _i in 200:
		var v := M.v3(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-10.0, 10.0))
		var omega := rng.randf_range(0.0, 3000.0)
		var loads: Dictionary = Rotor.loads(omega, 1.0, M.v3(0.0, 0.0, 0.0), v, M.v3(0.0, 0.0, 0.0), 0.0, data.rotor)
		worst = maxf(worst, loads.force[0] * v[0] + loads.force[1] * v[1])
	_check("rotor drag never does positive in-plane work (200 random states)", worst <= 0.0, String.num_scientific(worst))


func _galilean_wind() -> void:
	var env := SimEnvironment.new()
	var config: Dictionary = WeatherConfig.defaults()
	config.speed_mps = 4.0
	config.from_deg = 270.0
	var built: Dictionary = WeatherField.build(config)
	_check("a steady wind builds", built.ok, str(built.errors))
	env.weather = built.field
	var calm: Dictionary = _hovering()
	var windy: Dictionary = _hovering(env)
	var wind: PackedFloat64Array = env.wind(0.0)
	var moving: PackedFloat64Array = calm.sim.state.duplicate()
	for i in 3:
		moving[RB.VEL + i] += wind[i] # identity attitude: body axes coincide with NED
	var still_loads: PackedFloat64Array = calm.sim.model.stage.call(calm.sim.state, calm.sim.continuous, 0.0).loads
	var wind_loads: PackedFloat64Array = windy.sim.model.stage.call(moving, windy.sim.continuous, 0.0).loads
	var worst := 0.0
	for i in 6:
		worst = maxf(worst, absf(still_loads[i] - wind_loads[i]))
	_check("flying with the wind through the environment contract gives the still-air loads (Galilean, 1e-9)", worst < 1e-9, String.num_scientific(worst))
	calm.sim.free()
	windy.sim.free()


func _replay() -> void:
	var a: Dictionary = _hovering()
	var b: Dictionary = _hovering()
	for tick in 240:
		var inputs: PackedFloat64Array = a.sim.inputs.duplicate()
		if tick >= 60 and tick < 120:
			inputs[0] = clampf(inputs[0] + 0.03, 0.0, 1.0)
			inputs[1] = clampf(inputs[1] + 0.03, 0.0, 1.0)
		a.sim.inputs = inputs
		b.sim.inputs = inputs.duplicate()
		a.sim.step()
		b.sim.step()
	_check("two kernels replay the same bytes", a.sim.state.to_byte_array() == b.sim.state.to_byte_array()
		and a.sim.continuous.to_byte_array() == b.sim.continuous.to_byte_array() and a.sim.fault_reason.is_empty())
	var snapshot: Dictionary = a.sim.checkpoint()
	_check("the plant's kernel checkpoints and restores", not snapshot.is_empty() and b.sim.restore_checkpoint(snapshot))
	a.sim.free()
	b.sim.free()
