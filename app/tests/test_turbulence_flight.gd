# M5-W04a: exact weather owner state, transactional replay and independent RK-stage forcing.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Config = preload("res://physics/wind_config.gd")
const Field = preload("res://physics/wind_field.gd")
const Kernel = preload("res://physics/wind_turbulence.gd")
const Trace = preload("res://sim/trace.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Golden = preload("res://tests/golden_flights.gd")
const Recorder = preload("res://sim/recorder.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const PATHS = ["res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json", "res://data/aircraft/p51d_mustang_120.json", "res://data/aircraft/sebart_avanti_s_a200.json"]
var checks := 0
var failures := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)

func flight(path: String, config: Dictionary) -> Session:
	var s: Session = Session.new()
	s.input_enabled = false
	check("configuration accepted", s.setup_weather(config))
	s.setup(path)
	check("start flyable " + path, s.is_flyable())
	return s

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var config: Dictionary = Config.preset("turbulent")
	check("v2 config validates JSON round-trip", Config.validate(JSON.parse_string(JSON.stringify(config, "", true, true))).config == config)
	for defect: String in ["sigma", "tau", "seed_fraction", "seed_negative", "seed_big", "seed_bool", "missing", "extra"]:
		var bad: Dictionary = config.duplicate(true)
		match defect:
			"sigma": bad.turbulence_rms_mps = [0.0, NAN, 0.0]
			"tau": bad.turbulence_tau_s = 0.0
			"seed_fraction": bad.turbulence_seed = 1.5
			"seed_negative": bad.turbulence_seed = -1
			"seed_big": bad.turbulence_seed = 4294967296
			"seed_bool": bad.turbulence_seed = true
			"missing": bad.erase("turbulence_seed")
			"extra": bad.sigma = 1.0
		check("invalid v2 refused " + defect, not Config.validate(bad).ok)
	var zero: Dictionary = config.duplicate(true)
	zero.turbulence_rms_mps = [0.0, 0.0, 0.0]
	zero.speed_mps = 0.0
	check("zero turbulence reports calm", Field.build(zero).field.is_calm())
	for path: String in PATHS:
		var calm: Session = flight(path, Config.defaults())
		var disabled: Session = flight(path, zero)
		check("disabled v2 preserves calm reset bytes " + path, var_to_bytes(calm.sim.checkpoint()) == var_to_bytes(disabled.sim.checkpoint()))
		for tick: int in 80:
			calm.sim.step()
			disabled.sim.step()
		check("disabled v2 preserves calm flight/checkpoint bytes " + path, var_to_bytes(calm.checkpoint()) == var_to_bytes(disabled.checkpoint()))
		calm.free()
		disabled.free()
		var s: Session = flight(path, config)
		var original: Dictionary = s.checkpoint()
		var noise: Dictionary = Kernel.initial(PackedFloat64Array(config.turbulence_rms_mps), config.turbulence_seed)
		check("reset has stationary exact noise and raw RNG " + path, s.sim.aux.slice(s.turbulence_index(), s.turbulence_index()+3) == noise.values and s.sim.modes[1] == noise.rng_state)
		check("airborne reset preserves trimmed TAS " + path, absf(s.air_data(s.sim.state).V - s.start.V) < 1e-10)
		var immutable: PackedByteArray = var_to_bytes(s.checkpoint())
		check("legacy golden requires calm without touching flight", Golden.record(s,"roll_15").is_empty() and not Golden.replay(s,{}).ok and immutable == var_to_bytes(s.checkpoint()))
		for query: int in 50:
			s.wind_at(query * s.sim.dt()/50.0)
			s.air_data(s.sim.state)
		check("queries do not draw or advance " + path, immutable == var_to_bytes(s.checkpoint()))
		var next: Dictionary = Kernel.step(noise.values, PackedFloat64Array(config.turbulence_rms_mps), config.turbulence_tau_s, s.sim.dt(), config.turbulence_seed, noise.rng_state)
		s.sim.step()
		var index: int = s.turbulence_index()
		check("one tick advances OU exactly " + path, s.sim.aux.slice(index+3,index+6) == next.values and s.sim.modes[1] == next.rng_state)
		var background: PackedFloat64Array = Field.build(config).field.sample(s.sim.dt()/2.0)
		var middle: PackedFloat64Array = s.wind_at(s.sim.dt()/2.0)
		var midpoint_ok := true
		for axis: int in 3:
			midpoint_ok = midpoint_ok and absf(middle[axis] - (background[axis]+0.5*(noise.values[axis]+next.values[axis]))) < 1e-12
		check("RK midpoint samples interval interpolation " + path, midpoint_ok)
		for tick: int in 100:
			s.sim.step()
		check("all finite, full fleet remains flyable " + path, s.is_flyable() and s.sim.tick == 101)
		var saved: Dictionary = s.checkpoint()
		for tick: int in 80:
			s.sim.step()
		var final: PackedByteArray = var_to_bytes(s.checkpoint())
		var destination: Session = flight(path, Config.defaults())
		check("fresh calm adopts OU checkpoint " + path, destination.restore_checkpoint(saved))
		for tick: int in 80:
			destination.sim.step()
		check("cross-session continuation exact body/aux/RNG/wash " + path, final == var_to_bytes(destination.checkpoint()))
		var unchanged: PackedByteArray = var_to_bytes(destination.checkpoint())
		for defect: String in ["anchor", "interval", "rng_layout", "aux_layout", "config"]:
			if defect == "anchor" and s.anchor_count() == 0:
				continue
			var bad: Dictionary = saved.duplicate(true)
			match defect:
				"anchor": bad.simulation.aux[Session.AUX_ANCHORS+2] = 0.5
				"interval": bad.simulation.aux[index+6] += s.sim.dt()
				"rng_layout": bad.simulation.modes = PackedInt64Array([1])
				"aux_layout": bad.simulation.aux.resize(index+6)
				"config": bad.weather_config.turbulence_seed += 1
			check("checkpoint mutation refused atomically %s %s" % [path,defect], not destination.restore_checkpoint(bad) and unchanged == var_to_bytes(destination.checkpoint()))
		destination.free()
		var pre_fault: Dictionary = s.checkpoint()
		var loads: Callable = s.sim.continuous_loads
		var body_loads: Callable = s.sim.loads
		s.sim.loads = func(_state: PackedFloat64Array, _time: float) -> PackedFloat64Array: return PackedFloat64Array([NAN,0,0,0,0,0])
		s.sim.continuous_loads = func(_state: PackedFloat64Array, _wash: PackedFloat64Array, _time: float) -> PackedFloat64Array: return PackedFloat64Array([NAN,0,0,0,0,0])
		s.sim.step()
		check("failed step rolls back OU interval/RNG and body " + path, s.sim.tick == pre_fault.simulation.tick and s.sim.state == pre_fault.simulation.state and s.sim.aux == pre_fault.simulation.aux and s.sim.modes == pre_fault.simulation.modes)
		s.sim.continuous_loads = loads
		s.sim.loads = body_loads
		check("exact recovery after fault " + path, s.restore_checkpoint(pre_fault))
		s.hold("test")
		var before_hold: PackedByteArray = var_to_bytes(s.checkpoint())
		s.sim._physics_process(s.sim.dt())
		s._physics_process(s.sim.dt())
		check("pause freezes turbulence/RNG " + path, before_hold == var_to_bytes(s.checkpoint()))
		s.release("test")
		s.reset()
		check("restart repeats original seeded start " + path, var_to_bytes(original) == var_to_bytes(s.checkpoint()))
		s.free()
	_runway_weather(config)
	_pending_boundary(config)
	_manufactured_forcing(config)
	_trace_checks(config)
	print("M5-W04a turbulence flight: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _trace_checks(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0], config)
	var r: Recorder = Recorder.new(s.sim)
	r.start(s.trace_meta())
	for tick: int in 40:
		s.sim.step()
	check("turbulence trace v5 explicit columns", r.trace.to_csv().begins_with("# format: openrc-trace v5\n") and r.trace.columns() == Trace.COLUMNS + Trace.WEATHER_COLUMNS + Trace.TURBULENCE_COLUMNS)
	check("trace actual state/load TAS", r.trace.value(40,"tas_mps") == s.air_data(s.sim.state).V and r.trace.value(40,"loads_tas_mps") == s.air_data(s.sim.previous, 39*s.sim.dt()).V)
	for axis: int in 3:
		check("trace state wind %d" % axis, r.trace.value(40,["wind_north_mps","wind_east_mps","wind_down_mps"][axis]) == s.wind_at(s.sim.time())[axis])
		check("trace load wind %d" % axis, r.trace.value(40,["loads_wind_north_mps","loads_wind_east_mps","loads_wind_down_mps"][axis]) == s.wind_at(39*s.sim.dt())[axis])
	r.recording = false
	r.start(s.trace_meta())
	check("midflight first row has preceding OU and body", r.trace.value(0,"loads_tas_mps") == s.air_data(s.sim.previous, 39*s.sim.dt()).V)
	for tick: int in 8:
		s.sim.step()
	check("midflight trace continuation saves", r.trace.save("/tmp/openrc-turbulence-midflight.csv") == OK)
	for defect: String in ["index", "interval", "size", "nonfinite", "missing_rng", "rng_overflow", "origin"]:
		var trace: Trace = Trace.new()
		trace.meta = s.trace_meta()
		var aux: PackedFloat64Array = s.sim.aux.duplicate()
		match defect:
			"index": trace.meta.turbulence_aux_index = 0
			"interval": aux[aux.size()-1] += 1.0
			"size": aux.resize(aux.size()-1)
			"nonfinite": aux[aux.size()-2] = NAN
			"missing_rng": trace.meta.erase("recording_start_rng_state")
			"rng_overflow": trace.meta.recording_start_rng_state = "9223372036854775808"
			"origin": trace.meta.recording_start_turbulence = "[0,0,0,0,0,0,0]"
		trace.record(s.sim.tick,s.sim.time(),s.sim.state,s.sim.last_loads,s.sim.inputs,aux)
		check("malformed OU trace refuses saving "+defect, trace.to_csv().is_empty() and trace.save("/tmp/invalid-ou.csv") == ERR_INVALID_DATA)
	r.recording = false
	var late: Dictionary = s.checkpoint()
	late.simulation.tick = 100000000 # exercise late recording without simulating days of flight
	late.simulation.aux[-1] = (late.simulation.tick - 1) * late.simulation.dt
	check("late-clock checkpoint restores", s.restore_checkpoint(late))
	r.start(s.trace_meta())
	for tick: int in 8:
		s.sim.step()
	check("late-clock trace preserves weather timestep", r.trace.save("/tmp/openrc-turbulence-long-clock.csv") == OK)
	r.detach()
	s.free()


func _manufactured_forcing(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0], config)
	s.sim.gravity = 0.0
	s.sim.mass = 2.0
	s.sim.loads = func(_state: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		return PackedFloat64Array([s.wind_at(time_s)[0],0.0,0.0,0.0,0.0,0.0])
	check("manufactured forcing reset", s.sim.reset(PackedFloat64Array([0,0,-100,0,0,0,1,0,0,0,0,0,0])))
	var h: float = s.sim.dt()
	var w0: float = s.wind_at(0.0)[0]
	s.sim.step()
	var w1: float = s.wind_at(h)[0]
	var velocity: float = h*(w0+w1)/(2.0*s.sim.mass)
	var position: float = h*h*(w0/2.0+(w1-w0)/6.0)/s.sim.mass
	check("RK integrates linear stochastic-window force exactly", absf(s.sim.state[RB.VEL]-velocity) < 1e-15 and absf(s.sim.state[RB.POS]-position) < 1e-15)
	s.free()


func _pending_boundary(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0], Config.defaults())
	var previous: PackedFloat64Array = s.sim.state.duplicate()
	check("tick-zero setup creates stopped reset boundary", s.setup_weather(config) and s.sim.paused and not s.can_resume() and s.checkpoint().is_empty())
	s.sim.step()
	check("raw step cannot index old layout or advance clock", s.sim.tick == 0 and s.sim.state == previous and not s.sim.fault_reason.is_empty())
	s.reset()
	check("reset completes environment boundary safely", s.is_flyable() and s.sim.modes.size() == 2 and not s.sim.paused)
	var changed: Dictionary = config.duplicate(true)
	changed.turbulence_seed += 1
	check("tick-zero turbulent config also requires reset", s.setup_weather(changed) and not s.is_flyable() and not is_finite(s.wind_at(0.0)[0]))
	s.reset()
	check("changed seed has new stationary reset", s.is_flyable() and s.sim.modes[1] == Kernel.initial(PackedFloat64Array(changed.turbulence_rms_mps), changed.turbulence_seed).rng_state)
	s.free()


func _runway_weather(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0], config)
	var loaded: Dictionary = FieldLoader.load_from()
	check("runway field loaded", loaded.ok and s.set_field(loaded.field))
	for tick: int in 80:
		s.sim.step()
	s.start_choice = Session.START_RUNWAY
	s.reset()
	var initial: Dictionary = Kernel.initial(PackedFloat64Array(config.turbulence_rms_mps), config.turbulence_seed)
	check("runway starts at deterministic stationary weather clock", s.is_flyable() and s.sim.tick == 0 and s.sim.modes[1] == initial.rng_state and s.sim.aux.slice(s.turbulence_index(),s.turbulence_index()+3) == initial.values)
	var initial_checkpoint: PackedByteArray = var_to_bytes(s.checkpoint())
	for tick: int in 80:
		s.sim.step()
	check("runway turbulence advances without fault", s.is_flyable() and s.sim.tick == 80)
	s.reset()
	check("runway restart repeats static pose/noise/anchors", initial_checkpoint == var_to_bytes(s.checkpoint()))
	s.free()
