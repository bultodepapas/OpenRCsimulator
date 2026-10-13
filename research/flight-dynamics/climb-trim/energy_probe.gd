# Independent mechanical-energy audit; trapezoidal work is a numerical diagnostic, not flight validation.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const FIXTURE := "res://../research/flight-dynamics/climb-trim/ugly-loop-inputs.json"
var raw := {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
func _initialize() -> void:
	call_deferred("run")
func _energy(model: Dictionary, state: PackedFloat64Array, g: float) -> float:
	var v := M.v3(state[RB.VEL], state[RB.VEL+1], state[RB.VEL+2])
	var w := M.v3(state[RB.RATE], state[RB.RATE+1], state[RB.RATE+2])
	return 0.5*float(model.mass_kg)*M.dot(v,v) + 0.5*M.dot(w,RB.inertia_mul(model.inertia,w)) - float(model.mass_kg)*g*state[RB.POS+2]
func _dot_load(loads: PackedFloat64Array, force_v: PackedFloat64Array, rates: PackedFloat64Array) -> float:
	return loads[0]*force_v[0]+loads[1]*force_v[1]+loads[2]*force_v[2]+loads[3]*rates[0]+loads[4]*rates[1]+loads[5]*rates[2]
func _eval(session, state: PackedFloat64Array, t: float) -> Dictionary:
	var model: Dictionary = session.aircraft.model
	var d: Dictionary = session._deflections(session.sim.aux)
	var rpm: float = session.sim.aux[0]
	var lag: int = session.downwash_index()
	var lag_cl: float = session.sim.aux[lag] if lag >= 0 and lag < session.sim.aux.size() else NAN
	return Dynamics.evaluate(state,model,d,rpm,session.air_density(),session.wind_at(t),session.sim.gravity,PackedFloat64Array(),lag_cl)
func run() -> void:
	var calm := "--calm" in OS.get_cmdline_user_args()
	var multiplier := 2 if "--480" in OS.get_cmdline_user_args() else 1
	Engine.physics_ticks_per_second = 240 * multiplier
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var samples := {}
	for row: Dictionary in source.samples: samples[int(row.tick)] = row
	var session = Session.new()
	assert(session.setup_weather(Weather.defaults() if calm else Weather.GENTLE_PRACTICE))
	session.setup("res://data/aircraft/jensen_ugly_stik_60.json","jensen-das-ugly-stik-60")
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	session.read_raw = func() -> Dictionary: return raw.duplicate()
	session.rate_profile = "normal"
	var max_error := 0.0
	var max_step_closure := 0.0
	var cumulative_closure := 0.0
	var cumulative_abs_closure := 0.0
	var interval_start_energy := _energy(session.aircraft.model,session.sim.state,session.sim.gravity)
	var interval_work := 0.0
	var interval_aero_work := 0.0
	var dt: float = session.sim.dt()
	var row_records: Array = []
	var max_ticks: int = min(int(source.last_tick),3600) * multiplier
	for tick in range(1,max_ticks+1):
		var source_tick: int = floori(float(tick - 1) / multiplier) + 1
		if samples.has(source_tick): raw=samples[source_tick].raw
		session._physics_process(dt)
		var old_state: PackedFloat64Array = session.sim.state.duplicate()
		var old_time: float = session.sim.time()
		session.sim.step()
		if session.sim.paused: break
		var new_state: PackedFloat64Array = session.sim.state
		var e0 := _energy(session.aircraft.model,old_state,session.sim.gravity)
		var e1 := _energy(session.aircraft.model,new_state,session.sim.gravity)
		var r0 := _eval(session,old_state,old_time)
		var r1 := _eval(session,new_state,session.sim.time())
		var w0 := M.v3(old_state[RB.VEL],old_state[RB.VEL+1],old_state[RB.VEL+2])
		var w1 := M.v3(new_state[RB.VEL],new_state[RB.VEL+1],new_state[RB.VEL+2])
		var omega0 := M.v3(old_state[RB.RATE],old_state[RB.RATE+1],old_state[RB.RATE+2])
		var omega1 := M.v3(new_state[RB.RATE],new_state[RB.RATE+1],new_state[RB.RATE+2])
		var step_work := 0.5*dt*(_dot_load(r0.loads,w0,omega0)+_dot_load(r1.loads,w1,omega1))
		var aero_work := 0.5*dt*(_dot_load(r0.aero_loads,r0.air.v_air,omega0)+_dot_load(r1.aero_loads,r1.air.v_air,omega1))
		var step_closure := (e1-e0)-step_work
		max_step_closure=maxf(max_step_closure,absf(step_closure))
		cumulative_closure+=step_closure
		cumulative_abs_closure+=absf(step_closure)
		interval_work+=step_work
		interval_aero_work+=aero_work
		if not calm and multiplier == 1 and samples.has(tick) and samples[tick].has("state"):
			var expected: Array=samples[tick].state
			for i in new_state.size(): max_error=maxf(max_error,absf(new_state[i]-float(expected[i])))
		if tick % (240 * multiplier) == 0:
			var result: Dictionary=_eval(session,new_state,session.sim.time())
			var air: Dictionary=result.air
			var d: Dictionary=session._deflections(session.sim.aux)
			var row={t=session.sim.time(),speed=air.V,alpha_deg=rad_to_deg(air.alpha),pitch_deg=rad_to_deg(M.q_to_euler(RB._att(new_state))[1]),q=new_state[RB.RATE+1],elevator=d.elevator,throttle=session.commands.throttle,blend=preload("res://physics/aero.gd").local_flow_weight(new_state,air,d,session.aircraft.model),energy_delta=_energy(session.aircraft.model,new_state,session.sim.gravity)-interval_start_energy,body_work=interval_work,aero_work=interval_aero_work,energy_closure=(_energy(session.aircraft.model,new_state,session.sim.gravity)-interval_start_energy)-interval_work,aero_power=_dot_load(result.aero_loads,air.v_air,M.v3(new_state[RB.RATE],new_state[RB.RATE+1],new_state[RB.RATE+2])),body_power=_dot_load(result.loads,M.v3(new_state[RB.VEL],new_state[RB.VEL+1],new_state[RB.VEL+2]),M.v3(new_state[RB.RATE],new_state[RB.RATE+1],new_state[RB.RATE+2])),max_step_closure=max_step_closure,state=Array(new_state)}
			row_records.append(row)
			interval_start_energy=_energy(session.aircraft.model,new_state,session.sim.gravity)
			interval_work=0.0
			interval_aero_work=0.0
			max_step_closure=0.0
	print("ENERGY_AUDIT ",JSON.stringify({case="calm" if calm else "actual-gentle-practice",hz=240*multiplier,fixture_compared=not calm and multiplier==1,duration=session.sim.time(),sample_max_state_error=max_error,cumulative_body_energy_closure=cumulative_closure,abs_step_closure_sum=cumulative_abs_closure,rows=row_records}))
	session.free()
	quit()
