# M5-ATM-2/3: one environment through trim, stage loads, shaft charge, wake, trace and exact replay.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Config = preload("res://physics/wind_config.gd")
const Air = preload("res://physics/air_data.gd")
const Dynamics = preload("res://physics/dynamics.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const Turbine = preload("res://physics/turbine.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const Recorder = preload("res://sim/recorder.gd")
const Trace = preload("res://sim/trace.gd")
const Golden = preload("res://tests/golden_flights.gd")
const PATHS = ["res://data/aircraft/jensen_ugly_stik_60.json","res://data/aircraft/gp_extra_300s_60.json","res://data/aircraft/p51d_mustang_120.json","res://data/aircraft/sebart_avanti_s_a200.json"]
var failures := 0
var checks := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func flight(path: String, config: Dictionary) -> Session:
	var s: Session = Session.new()
	s.input_enabled = false
	check("weather accepted",s.setup_weather(config))
	s.setup(path)
	check("initial condition valid "+path,s.is_flyable())
	return s

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var config: Dictionary = Config.preset("hot-high")
	for path: String in PATHS:
		var baseline: Session = flight(path,Config.defaults())
		var reference: Session = flight(path,Config.upgrade_atmosphere(Config.defaults(),{field_elevation_m=3200.0,temperature_c=40.0,relative_humidity_pct=90.0}))
		check("reference ignores stored custom parameters and keeps literal density",reference.air_density()==1.225 and reference.engine_charge_ratio()==1.0)
		check("reference reset bytes unchanged "+path,var_to_bytes(baseline.checkpoint())==var_to_bytes(reference.checkpoint()))
		for tick: int in 240:
			baseline.sim.step()
			reference.sim.step()
		check("reference flight/state/checkpoint bytes unchanged "+path,var_to_bytes(baseline.checkpoint())==var_to_bytes(reference.checkpoint()))
		baseline.free()
		reference.free()
		var s: Session = flight(path,config)
		var original: Dictionary = s.checkpoint()
		check("custom density+charge are physical and distinct", s.air_density()<1.225 and s.engine_charge_ratio()<s.atmosphere_configuration().sigma)
		check("custom atmosphere trim preserves catalog TAS", absf(s.air_data(s.sim.state).V-s.start.V)<1e-10)
		check("dynamic pressure uses custom density", absf(s.air_data(s.sim.state).qbar-0.5*s.air_density()*s.start.V*s.start.V)<1e-10)
		var loads: PackedFloat64Array = s.sim.last_loads
		var derivative: PackedFloat64Array = RB.derivative(s.sim.state,s.sim.mass,s.sim.inertia,RB.inertia_inverse(s.sim.inertia),
			M.v3(loads[0],loads[1],loads[2]),M.v3(loads[3],loads[4],loads[5]),s.sim.gravity,s.rotor_momentum(s.sim.aux))
		var equilibrium := true
		for index: int in [RB.VEL,RB.VEL+1,RB.VEL+2,RB.RATE,RB.RATE+1,RB.RATE+2]:
			equilibrium = equilibrium and is_finite(derivative[index]) and absf(derivative[index])<1e-8
		check("custom-air reset solves all six equilibrium accelerations", equilibrium)
		var r: Recorder = Recorder.new(s.sim)
		r.start(s.trace_meta())
		for tick: int in 240:
			s.sim.step()
		check("hot/high 1s level hold "+path, s.sim.tick==240 and s.is_flyable() and absf(s.sim.state[RB.POS+2]+30.0)<1e-6 and absf(s.air_data(s.sim.state).V-s.start.V)<1e-6)
		check("v6 constant field density and EAS",r.trace.to_csv().begins_with("# format: openrc-trace v6\n") and r.trace.value(240,"rho_kgm3")==s.air_density() and absf(r.trace.value(240,"equivalent_airspeed_mps")-s.air_data(s.sim.state).V*M.sqrt_(s.air_density()/1.225))<1e-12)
		check("golden v1 refuses changed atmosphere",Golden.record(s,"roll_15").is_empty() and not Golden.replay(s,{}).ok)
		r.detach()
		var saved: Dictionary = s.checkpoint()
		check("atmosphere checkpoint v3",saved.format=="openrc-flight-checkpoint v3" and saved.weather_config==config)
		for tick: int in 100:
			s.sim.step()
		var final: PackedByteArray = var_to_bytes(s.checkpoint())
		var destination: Session = flight(path,Config.defaults())
		check("reference session adopts custom field checkpoint",destination.restore_checkpoint(saved))
		for tick: int in 100:
			destination.sim.step()
		check("custom replay exactly reproduces state/aux/modes/wake/loads",final==var_to_bytes(destination.checkpoint()))
		var untouched: PackedByteArray = var_to_bytes(destination.checkpoint())
		for defect: String in ["temperature","humidity","version","hash"]:
			var bad: Dictionary = saved.duplicate(true)
			match defect:
				"temperature": bad.weather_config.temperature_c = INF
				"humidity": bad.weather_config.relative_humidity_pct = 101.0
				"version": bad.format = "openrc-flight-checkpoint v2"
				"hash": bad.weather_config.temperature_c += 1.0
			check("invalid environment restore remains atomic "+defect,not destination.restore_checkpoint(bad) and untouched==var_to_bytes(destination.checkpoint()))
		destination.free()
		s.reset()
		check("restart repeats custom-density start",var_to_bytes(original)==var_to_bytes(s.checkpoint()))
		s.free()
	_shaft_and_propulsor_checks(config)
	_transition_checks(config)
	_failure_recovery(config)
	_mixed_replay(config)
	_runway(config)
	print("M5-ATM flight: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)

func _shaft_and_propulsor_checks(config: Dictionary) -> void:
	var s: Session = flight(PATHS[2],config)
	var prop: Dictionary = s.aircraft.model.propulsion
	var rpm := 4200.0
	var throttle := 0.65
	var friction: float = prop.shaft.friction[0]+prop.shaft.friction[1]*rpm/1000.0
	var reference: float = Propulsion.engine_torque(rpm,throttle,prop)
	var expected: float = (reference+friction)*s.engine_charge_ratio()-friction
	check("dry charge scales indicated torque while friction stays fixed",absf(Propulsion.engine_torque(rpm,throttle,prop,s.engine_charge_ratio())-expected)<1e-12)
	check("humidity correction differs from moist total density scaling",s.engine_charge_ratio()<s.air_density()/1.225 and absf(Propulsion.engine_torque(rpm,throttle,prop,s.engine_charge_ratio())-Propulsion.engine_torque(rpm,throttle,prop,s.air_density()/1.225))>1e-3)
	var u: float = M.dot(s.air_data(s.sim.state).v_air,Propulsion.axis(prop))
	var predicted: float = Propulsion.shaft_step(s.sim.aux[0],s.sim.inputs[3],u,s.sim.dt(),prop,s.air_density(),s.engine_charge_ratio())
	s.sim.step()
	check("session shaft pre-step uses density and dry charge",s.sim.aux[0]==predicted)
	var thin: PackedFloat64Array = Propulsion.thrust_torque(M.v3(10,0,0),rpm,prop,s.air_density())
	var dense: PackedFloat64Array = Propulsion.thrust_torque(M.v3(10,0,0),rpm,prop,1.225)
	check("fixed-rpm prop thrust and load scale with total density",absf(thin[0]/dense[0]-s.air_density()/1.225)<1e-12 and absf(thin[1]/dense[1]-s.air_density()/1.225)<1e-12)
	s.free()
	var jet: Session = flight(PATHS[3],config)
	var a: PackedFloat64Array = Turbine.loads(M.v3(29,2,-1),jet.sim.aux[0],jet.aircraft.model.propulsion,jet.air_density())
	var b: PackedFloat64Array = Turbine.loads(M.v3(29,2,-1),jet.sim.aux[0],jet.aircraft.model.propulsion,1.225)
	var matched := true
	for axis: int in 6:
		matched = matched and absf(a[axis]-b[axis]*jet.air_density()/1.225)<1e-9
	check("turbine retains its own density-scaled thrust/ram law",matched)
	jet.free()

func _transition_checks(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0],Config.defaults())
	check("tick-zero weather change accepted",s.setup_weather(config))
	check("new atmosphere requires reset before checkpoint",s.sim.paused and not s.is_flyable() and s.checkpoint().is_empty())
	s.reset()
	check("density reset re-solves custom trim",s.is_flyable() and absf(s.air_data(s.sim.state).V-s.start.V)<1e-10)
	for tick: int in 240:
		s.sim.step()
	check("re-solved start stays level",absf(s.sim.state[RB.POS+2]+30.0)<1e-6)
	var bytes: PackedByteArray = var_to_bytes(s.checkpoint())
	check("live atmosphere change refused atomically",not s.setup_weather(Config.preset("cool-dense")) and bytes==var_to_bytes(s.checkpoint()))
	s.free()

func _mixed_replay(config: Dictionary) -> void:
	var c: Dictionary = Config.upgrade_atmosphere(Config.preset("turbulent"),config)
	# Retain the turbulence preset's axes while combining atmosphere fields.
	c.turbulence_rms_mps = [0.6,0.6,0.4]
	var s: Session = flight(PATHS[2],c)
	for tick: int in 120:
		s.sim.step()
	var saved: Dictionary = s.checkpoint()
	for tick: int in 120:
		s.sim.step()
	var exact: PackedByteArray = var_to_bytes(s.checkpoint())
	var fresh: Session = flight(PATHS[2],Config.defaults())
	check("mixed OU/environment checkpoint restores fresh reference",fresh.restore_checkpoint(saved))
	for tick: int in 120:
		fresh.sim.step()
	check("mixed OU/density exact continuation",exact==var_to_bytes(fresh.checkpoint()))
	fresh.free()
	s.free()

func _runway(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0],config)
	var field: Dictionary = FieldLoader.load_from()
	check("runway field accepted",field.ok and s.set_field(field.field))
	s.start_choice = Session.START_RUNWAY
	s.reset()
	check("custom-air static runway solve valid",s.is_flyable() and s.sim.tick==0 and s.start_error.is_empty())
	var snapshot: PackedByteArray = var_to_bytes(s.checkpoint())
	for tick: int in 120:
		s.sim.step()
	check("custom-density runway remains finite",s.is_flyable() and s.sim.tick==120)
	s.reset()
	check("runway restart preserves custom-air static state",snapshot==var_to_bytes(s.checkpoint()))
	s.free()


func _failure_recovery(config: Dictionary) -> void:
	var s: Session = flight(PATHS[0],Config.defaults())
	var extreme: Dictionary = Config.upgrade_atmosphere(config,{field_elevation_m=4000.0,temperature_c=45.0,qnh_hpa=870.0,relative_humidity_pct=100.0})
	check("valid extreme field accepted at launch boundary",s.setup_weather(extreme))
	s.reset()
	check("unflyable atmosphere refuses old sea-level trim",not s.is_flyable() and not s.can_resume() and s.sim.paused and not s.start_error.is_empty())
	check("reset remains parked and cannot produce misleading checkpoint",s.sim.tick==0 and s.checkpoint().is_empty())
	check("reference settings can recover a failed atmospheric start",s.setup_weather(Config.defaults()))
	s.reset()
	check("failed trim recovers to a valid reference flight",s.is_flyable() and s.air_density()==1.225 and absf(s.air_data(s.sim.state).V-15.0)<1e-10)
	s.free()
