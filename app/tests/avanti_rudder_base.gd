## AV-17-R3: real gamepad yaw pulse/release, fixed initial trim throttle.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
var hz := 240
var data_path := "res://data/aircraft/sebart_avanti_s_a200.json"

func run_case(speed: float, yaw: float, hold: float = 1.0) -> Dictionary:
	var f := Flight.new()
	f.rate_profile = "normal"
	f.setup(data_path, "sebart-avanti-s-a200-p100rx")
	root.add_child(f)
	f.set_physics_process(false)
	f.sim.set_physics_process(false)
	assert(f.trim_at(speed).ok)
	f.set_start_altitude(500)
	f.reset()
	f.crash_auto_restart = false
	f.radio.connect_device(15, {known=true, name="Synthetic Xbox"}, Profile.defaults())
	f.radio.confirmed_gamepad_connection = func(id:int)->bool: return id==15
	f.read_axis = func(_id:int, axis:int)->float:
		return yaw if axis==0 and f.sim.time()>=0.5 and f.sim.time()<0.5+hold else 0.0
	f.read_button = func(_id:int, _button:int)->bool: return false
	for i in hz/4: f.radio.poll(f.read_axis, f.sim.dt(), f.read_button, false)
	assert(f.radio.armed)
	assert(f.radio.set_rate_throttle_for_start(f.start.throttle))
	var r: Dictionary = {speed=speed, yaw=yaw, hold_s=hold, peak_yaw_rate=0.0, return_yaw_rate=0.0,
		peak_beta=0.0, late_beta=0.0, peak_roll_rate=0.0, command_opposite=0.0, rudder_opposite=0.0,
		unwanted_command=0.0, finite=true, samples=[]}
	for i in 7*hz:
		f._physics_process(f.sim.dt())
		f.sim.step()
		var s: PackedFloat64Array = f.sim.state
		var air := Air.compute(s, M.v3(0,0,0), f.air_density())
		var q := M.quat(s[6],s[7],s[8],s[9])
		var forward := M.q_rotate(q,M.v3(1,0,0))
		var velocity := M.q_rotate(q,M.v3(s[3],s[4],s[5]))
		var heading := rad_to_deg(atan2(forward[1],forward[0]))
		var track := rad_to_deg(atan2(velocity[1],velocity[0]))
		var yaw_rate := rad_to_deg(s[12])
		var rudder: float = f.surface_angles_deg().rudder
		r.peak_yaw_rate = maxf(r.peak_yaw_rate, signf(yaw)*yaw_rate)
		if f.sim.time()>0.5+hold: r.return_yaw_rate = minf(r.return_yaw_rate, signf(yaw)*yaw_rate)
		r.peak_beta = maxf(r.peak_beta, absf(rad_to_deg(air.beta)))
		if f.sim.time()>5.0: r.late_beta = maxf(r.late_beta, absf(rad_to_deg(air.beta)))
		r.peak_roll_rate = maxf(r.peak_roll_rate, absf(rad_to_deg(s[10])))
		r.command_opposite = maxf(r.command_opposite, -signf(yaw)*f.commands.yaw)
		r.rudder_opposite = maxf(r.rudder_opposite, -signf(yaw)*rudder)
		r.unwanted_command = maxf(r.unwanted_command, maxf(absf(f.commands.pitch), absf(f.commands.roll)))
		for value in s: r.finite = r.finite and is_finite(value)
		for value in f.sim.aux: r.finite = r.finite and is_finite(value)
		if i%(hz/40)==0:
			r.samples.append([f.sim.time(),air.V,rad_to_deg(air.alpha),rad_to_deg(air.beta),rad_to_deg(s[10]),
				yaw_rate,heading,track,f.raw.yaw,f.commands.yaw,rudder,f.commands.throttle])
		if f.sim.paused or not f.sim.fault_reason.is_empty() or not f.crash.is_empty() or not r.finite: break
	r.completed = f.sim.tick==7*hz and f.sim.fault_reason.is_empty() and f.crash.is_empty() and r.finite
	var brief := r.duplicate()
	brief.erase("samples")
	print(JSON.stringify(brief))
	f.free()
	return r
