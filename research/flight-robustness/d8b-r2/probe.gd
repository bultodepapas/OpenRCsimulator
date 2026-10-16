# D8b-R2 diagnostic only. Run from repository root with --path app --script <absolute path>.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Aero = preload("res://physics/aero.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var results: Array = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for speed in [15.0, 20.0, 25.0, 30.0]:
		for variant in ["baseline", "no_gyro", "glide", "half_pull", "keyboard"]:
			trial(speed, variant, 240)
	for hz in [480, 960]:
		trial(25.0, "baseline", hz)
		trial(25.0, "keyboard", hz)
	for variant in ["glide_symmetric", "glide_seed_positive", "glide_seed_negative", "no_inertia_cross"]:
		trial(25.0, variant, 240)
	static_sweep()
	var file := FileAccess.open("res://../docs/research/flight-robustness/D8b-R2/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t", true, true) + "\n")
	quit()

func trial(speed: float, variant: String, hz: int) -> void:
	Engine.physics_ticks_per_second = hz
	var session = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	var trim: Dictionary = session.trim_at(speed, "glide" if variant.begins_with("glide") else "level")
	if not trim.ok:
		results.append({speed = speed, variant = variant, hz = hz, error = trim.message})
		session.free()
		return
	session.set_start_altitude(300.0)
	session.reset()
	if variant in ["glide_symmetric", "glide_seed_positive", "glide_seed_negative", "no_inertia_cross"]:
		var inertia: PackedFloat64Array = session.aircraft.model.inertia.duplicate()
		inertia[3] = 0.0 # Jxy: reflection symmetry; retain Jxz (pitch-plane symmetry allows it).
		inertia[5] = 0.0 # Jyz.
		session.aircraft.model.inertia = inertia
		session.sim.inertia = inertia
		if variant.begins_with("glide"):
			session.trims.roll = 0.0
			session.trims.yaw = 0.0
			session.reset()
			var exact: PackedFloat64Array = session.sim.state.duplicate()
			exact[4] = 0.0
			exact[10] = 0.0001 if variant == "glide_seed_positive" else (-0.0001 if variant == "glide_seed_negative" else 0.0)
			exact[12] = 0.0
			session.sim.reset(exact)
	if variant == "no_gyro":
		session.sim.model.rotor_momentum = func(_a: PackedFloat64Array) -> PackedFloat64Array: return M.v3(0, 0, 0)
	if variant == "keyboard":
		session.input_enabled = true
		session.radio.connected = false
		session.read_raw = func() -> Dictionary:
			var t: float = session.sim.time()
			return {roll = 0.0, pitch = 1.0 if t >= 0.25 and t < 2.25 else 0.0, yaw = 0.0, throttle = 0.0}
	var start: PackedFloat64Array = session.sim.state.duplicate()
	var heading := M.q_rotate(RB._att(start), M.v3(1,0,0))
	var normal := M.v3(-heading[1], heading[0], 0)
	normal = M.scale(normal, 1.0 / M.sqrt_(M.dot(normal, normal)))
	var rows: Array = []
	var peak_p := 0.0
	var peak_r := 0.0
	var peak_beta := 0.0
	var peak_alpha := 0.0
	var peak_cross := 0.0
	for i in range(4 * hz + 1):
		var s: PackedFloat64Array = session.sim.state
		var air: Dictionary = session.air_data(s)
		var d: Dictionary = session._deflections(session.sim.aux)
		var cross_track := M.dot(M.sub(RB._slice3(s,0),RB._slice3(start,0)), normal)
		peak_p = maxf(peak_p, absf(s[10]))
		peak_r = maxf(peak_r, absf(s[12]))
		peak_beta = maxf(peak_beta, absf(air.beta))
		peak_alpha = maxf(peak_alpha, absf(air.alpha))
		peak_cross = maxf(peak_cross, absf(cross_track))
		if i % (hz / 20) == 0:
			rows.append({t = session.sim.time(), V = air.V, alpha_deg = rad_to_deg(air.alpha), beta_deg = rad_to_deg(air.beta),
				p = s[10], q = s[11], r = s[12], blend = Aero.local_flow_weight(s, air, d, session.aircraft.model),
				elevator_deg = rad_to_deg(d.elevator), cross_m = cross_track, rpm = session.sim.aux[0], state = Array(s)})
		if i == 4 * hz: break
		var time: float = session.sim.time()
		if variant == "keyboard":
			session._physics_process(session.sim.dt())
		else:
			session.commands = {roll = 0.0, pitch = (0.5 if variant == "half_pull" else 1.0) if time >= 0.25 and time < 2.25 else 0.0, yaw = 0.0, throttle = session.start.throttle}
			session.sim.inputs = session._inputs()
		session.sim.step()
		if not session.sim.fault_reason.is_empty(): break
	var out := {speed = speed, variant = variant, hz = hz, trims = session.trims, throttle = session.start.throttle,
		inertia = Array(session.aircraft.model.inertia), cg = Array(session.aircraft.model.cg_le),
		peak_p = peak_p, peak_r = peak_r, peak_beta_deg = rad_to_deg(peak_beta), peak_alpha_deg = rad_to_deg(peak_alpha), peak_cross_m = peak_cross,
		fault = session.sim.fault_reason, tick = session.sim.tick, rows = rows}
	results.append(out)
	out = out.duplicate()
	out.erase("rows")
	print(JSON.stringify(out))
	session.free()

func static_sweep() -> void:
	var session = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	var model: Dictionary = session.aircraft.model
	var rows: Array = []
	var d := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	for tenth in range(80, 181, 5):
		var alpha := deg_to_rad(tenth / 10.0)
		var s := RB.make_state(M.v3(0,0,-300), M.v3(25*cos(alpha),0,25*sin(alpha)), M.q_from_euler(0,0,0), M.v3(0,0,0))
		var air: Dictionary = session.air_data(s)
		var base := Aero.loads(s,air,d,model,1.225)
		var minus := s.duplicate()
		var plus := s.duplicate()
		minus[10] = -0.00001
		plus[10] = 0.00001
		var derivative := (Aero.loads(plus,air,d,model,1.225)[3] - Aero.loads(minus,air,d,model,1.225)[3]) / 0.00002
		rows.append({alpha_deg = tenth/10.0, roll_nm_per_radps = derivative, approximate_p_growth_per_s = derivative/model.inertia[0], loads = Array(base), cl = Aero.wing_lift_coefficient(s,air,d,model), blend = Aero.local_flow_weight(s,air,d,model)})
	results.append({variant = "static_sweep", rows = rows, envelope = model.envelope, inertia = Array(model.inertia)})
	session.free()
