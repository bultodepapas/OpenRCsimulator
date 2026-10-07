# H8a: nonautonomous RK4 through the real Simulation, with the autonomous API retained.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const Sim := preload("res://sim/simulation.gd")
var _checks := 0
var _failures := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s %s" % ["ok" if ok else "FAIL", label])


func _initial() -> PackedFloat64Array:
	return RB.make_state(M.v3(0, 0, 0), M.v3(0, 0, 0), M.q_identity(), M.v3(0, 0, 0))


func _zero() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(RB.SIZE)
	return result


func _kernel() -> void:
	var seen: Array[float] = []
	var f := func(_s: PackedFloat64Array, t: float) -> PackedFloat64Array:
		seen.append(t)
		return _zero()
	var s := _initial()
	RK.rk4_step_at(s, 2.0, 0.25, f)
	_check("uncached kernel stage times", seen == [2.0, 2.125, 2.125, 2.25])
	seen.clear()
	RK.rk4_step_at(s, 2.0, 0.25, f, _zero())
	_check("cached k1 avoids duplicate evaluation", seen == [2.125, 2.125, 2.25])
	var autonomous := func(state: PackedFloat64Array) -> PackedFloat64Array:
		var d := _zero()
		d[RB.POS] = state[RB.VEL]
		d[RB.VEL] = -state[RB.POS]
		return d
	var timed := func(state: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		return autonomous.call(state)
	s[RB.POS] = 1.0
	s[RB.VEL] = 0.5
	_check("autonomous kernel retains exact arithmetic", RK.rk4_step(s, 0.125, autonomous).to_byte_array() == RK.rk4_step_at(s, 7.0, 0.125, timed).to_byte_array())


func _sampling_and_faults() -> void:
	for bad_stage in [-1, 2, 3, 4]:
		var sim := Sim.new()
		sim.gravity = 0.0
		sim.reset(_initial())
		sim.step() # nonzero start time catches a stage-offset-only implementation
		var t: float = sim.time()
		var h: float = sim.dt()
		var seen: Array[float] = []
		var sampled: Array[float] = []
		var input_samples: Array[float] = []
		sim.pre_step = func(a: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array:
			a[0] += 1.0
			return a
		sim.loads = func(_s: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
			seen.append(stage_t)
			sampled.append(sim.aux[0])
			input_samples.append(sim.inputs[0])
			return PackedFloat64Array([NAN if seen.size() == bad_stage else stage_t, 0, 0, 0, 0, 0])
		var state_before: PackedFloat64Array = sim.state.duplicate()
		var previous_before: PackedFloat64Array = sim.previous.duplicate()
		var loads_before: PackedFloat64Array = sim.last_loads.duplicate()
		var inputs_before: PackedFloat64Array = sim.inputs.duplicate()
		sim.inputs[0] = 0.25 # new tick sample; failure must restore the last committed sample
		var emissions := [0]
		sim.stepped.connect(func(_tick, _time, _state, _loads, _inputs, _aux): emissions[0] += 1)
		sim.step()
		if bad_stage < 0:
			_check("simulation uses absolute stage times", seen == [t, t + h / 2.0, t + h / 2.0, t + h])
			_check("aux advances once and stays frozen", sampled == [1.0, 1.0, 1.0, 1.0] and sim.aux[0] == 1.0)
			_check("sampled inputs stay fixed across stages", input_samples == [0.25, 0.25, 0.25, 0.25])
			_check("trace loads retain k1 timing", sim.last_loads[0] == t and emissions[0] == 1 and sim.tick == 2)
		else:
			_check("stage %d fault rolls back body, aux, inputs and trace loads" % bad_stage,
				sim.state == state_before and sim.previous == previous_before and sim.aux[0] == 0.0
				and sim.last_loads == loads_before and sim.inputs == inputs_before and sim.tick == 1)
			_check("stage %d fault pauses without emitting a completed tick" % bad_stage,
				sim.paused and not sim.fault_reason.is_empty() and emissions[0] == 0)
			sim.step()
			_check("stage %d fault remains sticky" % bad_stage, sim.tick == 1 and emissions[0] == 0)
		sim.free()


func _coupled_error(hz: int) -> float:
	Engine.physics_ticks_per_second = hz
	var sim := Sim.new()
	sim.gravity = 0.0
	# Unit-mass x'' = x + t; x(0)=v(0)=0. Exact x=sinh(t)-t, v=cosh(t)-1.
	sim.loads = func(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
		return PackedFloat64Array([s[RB.POS] + t, 0, 0, 0, 0, 0])
	sim.reset(_initial())
	for tick in hz:
		sim.step()
	var x_exact := 0.5 * (exp(1.0) - exp(-1.0)) - 1.0
	var v_exact := 0.5 * (exp(1.0) + exp(-1.0)) - 1.0
	var error := maxf(absf(sim.state[RB.POS] - x_exact), absf(sim.state[RB.VEL] - v_exact))
	_check("coupled solve at %d Hz completes" % hz, sim.tick == hz and sim.fault_reason.is_empty())
	sim.free()
	return error


func _initialize() -> void:
	var original_hz := Engine.physics_ticks_per_second
	_kernel()
	_sampling_and_faults()
	var errors := [_coupled_error(4), _coupled_error(8), _coupled_error(16)]
	var ratio1: float = errors[0] / errors[1]
	var ratio2: float = errors[1] / errors[2]
	_check("coupled nonautonomous solution converges at fourth order", ratio1 > 14.0 and ratio1 < 18.0 and ratio2 > 14.0 and ratio2 < 18.0)
	var production_error := _coupled_error(240)
	_check("240 Hz coupled solution error below 1e-10", production_error < 1e-10)
	print("H8a errors=%s ratios=%s,%s error_240hz=%s" % [str(errors), str(ratio1), str(ratio2), String.num_scientific(production_error)])
	Engine.physics_ticks_per_second = original_hz
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
