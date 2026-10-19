# Optional polar integration: replay identity, transactional reload, reflected loads and flown recovery evidence.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Fixture := preload("res://tests/wing_polar_fixture.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const ZERO := {elevator = 0.0, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
var failures := 0
var count := 0

func check(label: String, ok: bool) -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func write(path: String, raw: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()

func _initialize() -> void:
	var path := "user://pullup-polar-test-%s.json" % Time.get_ticks_usec()
	var raw := Fixture.raw()
	write(path,raw)
	var session := Session.new()
	session.setup(path)
	root.add_child(session)
	session.input_enabled = false
	session.set_start_altitude(300)
	session.reset()
	check("candidate session ready",session.is_flyable())
	check("trace explicitly names experimental polar", "tabulated-wing-v1" in session.trace_meta().wing_polar_model)
	var inputs: PackedFloat64Array = session.sim.inputs.duplicate()
	inputs[1] = 1.0
	session.sim.inputs = inputs
	for i in 300: session.sim.step()
	var cp := session.checkpoint()
	for i in 200: session.sim.step()
	var expected: PackedByteArray = session.sim.state.to_byte_array()+session.sim.aux.to_byte_array()
	var restored := session.restore_checkpoint(cp)
	session.sim.set_paused(false)
	session.sim.inputs = inputs
	for i in 200: session.sim.step()
	check("mid-pull replay preserves body and lag bytes",restored and expected == session.sim.state.to_byte_array()+session.sim.aux.to_byte_array())
	var configuration := session._checkpoint_configuration()
	var original_lift: float = session.aircraft.model.envelope.wing_polar.positive.values[9]
	session.aircraft.model.envelope.wing_polar.positive.values[9] = original_lift * 0.95
	check("polar change invalidates checkpoint identity",session._checkpoint_configuration() != configuration and not session.restore_checkpoint(cp))
	session.aircraft.model.envelope.wing_polar.positive.values[9] = original_lift
	# Invalid input must preserve the currently flying model/state; no silent fallback.
	var before: PackedByteArray = session.sim.state.to_byte_array()+session.sim.aux.to_byte_array()
	configuration = session._checkpoint_configuration()
	raw.aero.wing_polar.positive.source = ""
	write(path,raw)
	var note := session.reload()
	check("malformed polar reload is transactional", "wing_polar" in note and configuration == session._checkpoint_configuration()
		and before == session.sim.state.to_byte_array()+session.sim.aux.to_byte_array())
	var mirrored := true
	for k in range(-170,171,5):
		var a := deg_to_rad(float(k))
		var s := RB.make_state(M.v3(0,0,-300),M.v3(25*cos(a),1.3,25*sin(a)),M.q_identity(),M.v3(0.2,-0.3,0.4))
		var other := s.duplicate()
		other[RB.VEL+1] *= -1.0
		other[RB.RATE] *= -1.0
		other[RB.RATE+2] *= -1.0
		var left := Aero.loads(s,Air.compute(s,M.v3(0,0,0)),ZERO,session.aircraft.model,1.225)
		var right := Aero.loads(other,Air.compute(other,M.v3(0,0,0)),ZERO,session.aircraft.model,1.225)
		for j in 6:
			mirrored = mirrored and absf(left[j]-( -right[j] if j in [1,3,5] else right[j])) < 1e-10
	check("reflected local flows give reflected forces and moments",mirrored)
	# Exercise spin/recovery inputs without inventing a physical rate envelope for synthetic data.
	var trace: RefCounted = Maneuvers.fly(session,Maneuvers.all().spin_right)
	var finite: bool = trace.row_count() == 1921 and session.sim.fault_reason.is_empty()
	for row in trace.row_count():
		for name in ["p_radps","q_radps","r_radps","alt_m"]:
			finite = finite and is_finite(float(trace.value(row,name)))
	check("complete finite cross-controlled stall/recovery sequence",finite)
	# D10-R2: judged phase-independently. After the recovery input a decaying yaw oscillation remains; a 1 rad/s bound on
	# every sample from 6 s read one swing of it (base 5.92 s, D10-R2 6.01 s). Autorotation is sustained same-sign rotation:
	# the mean yaw rate over 6–8 s stays below 0.3 rad/s (≈ 0.06–0.08 recovered, ≈ 2.3 with pro-spin held) and the
	# envelope has decayed below 1 rad/s by 7 s (≈ 0.3 recovered, ≈ 5.5–6.9 with pro-spin held).
	var yaw_sum := 0.0
	var late_peak := 0.0
	for row in range(1440,1921):
		yaw_sum += float(trace.value(row,"r_radps"))
		if row >= 1680:
			late_peak = maxf(late_peak, maxf(absf(float(trace.value(row,"p_radps"))), absf(float(trace.value(row,"r_radps")))))
	var recovered := absf(yaw_sum / 481.0) < 0.3 and late_peak < 1.0
	check("synthetic fixture retains autorotation, then stops with the existing recovery input",float(trace.value(960,"r_radps")) > 1.0 and recovered)
	print("Synthetic spin: p/r at 4 s = %s/%s, at 8 s = %s/%s (not physical acceptance)" % [trace.value(960,"p_radps"),trace.value(960,"r_radps"),trace.value(1920,"p_radps"),trace.value(1920,"r_radps")])
	session.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("D8b-R2 session: %d checks, %d failed" % [count,failures])
	quit(1 if failures else 0)
