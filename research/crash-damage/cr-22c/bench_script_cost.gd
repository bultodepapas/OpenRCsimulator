## CR-22c: script cost of the crash-realism hot paths (CPU only; headless, no rendering). Run from the repo root:
##   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --audio-driver Dummy --script ../research/crash-damage/cr-22c/bench_script_cost.gd
## Prints median and p95 microseconds per call over repeated batches. Host numbers, not target-hardware acceptance.
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const CrashCause := preload("res://render/crash/cause.gd")
const Effects := preload("res://render/crash/effects.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const BATCHES := 40
const CALLS := 250


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var prepared: Dictionary = session._hull_contact
	var air := RB.make_state(M.v3(0, 0, -30), M.v3(15, 0, 0), M.q_from_euler(0, 0, 0), M.v3(0, 0, 0))
	var near := RB.make_state(M.v3(0, 0, -0.5), M.v3(15, 0, 0.5), M.q_from_euler(0, 0, deg_to_rad(40)), M.v3(0, 0, 0))
	var touching := near.duplicate()
	touching[RB.POS + 2] = -0.40
	_report("HullContact.loads, high above the ground (per RK stage)", func() -> void: HullContact.loads(air, prepared))
	_report("HullContact.loads, within reach, no contact", func() -> void: HullContact.loads(near, prepared))
	_report("HullContact.loads, touching", func() -> void: HullContact.loads(touching, prepared))
	_report("HullContact.terminal + contacts, high above the ground (per tick)", func() -> void:
		HullContact.terminal(air, air, prepared)
		HullContact.contacts(air, air, prepared))
	_report("HullContact.terminal + contacts, within reach, no contact (per tick)", func() -> void:
		HullContact.terminal(near, near, prepared)
		HullContact.contacts(near, near, prepared))
	_report("HullContact.terminal + contacts, touching (per tick)", func() -> void:
		HullContact.terminal(near, touching, prepared)
		HullContact.contacts(near, touching, prepared))
	var history: Array = []
	for i in int(CrashCause.HISTORY_S / CrashCause.SAMPLE_INTERVAL_S):
		history.append({t = i * 0.05, airspeed = 12.0, ground_speed = 12.0, alpha_deg = 9.0 + i * 0.05, pitch_deg = 5.0, bank_deg = 10.0,
			roll_rate_dps = 20.0, yaw_rate_dps = 5.0, height_agl = 5.0, vertical_speed = -2.0, throttle = 0.2, engine_running = true})
	_report("CrashCause.classify, full 5 s history (once per crash)", func() -> void:
		CrashCause.classify(history, {trigger = "hull_contact"}, {stall_alpha_deg = 14.0, start_speed = 15.0}))
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	await process_frame
	fx.start(Vector3.ZERO, Vector3(15, -8, 0), {"class": 4, "severity": 1.0, "surface": "grass"}, 1.28, true, Vector3.ZERO)
	fx.apply_energy(Effects.energy_outcome({lipo = 0.3}, {"class": 4, "severity": 1.0, "component_group": "fuselage"}, true, false))
	_report("Effects.update, C4 with %d chips and venting (per frame)" % fx.stats().splinters, func() -> void: fx.update(1.0 / 60.0, false))
	fx.free()
	session.free()
	quit(0)


func _report(label: String, call: Callable) -> void:
	var per_call: Array[float] = []
	for b in BATCHES:
		var start := Time.get_ticks_usec()
		for i in CALLS:
			call.call()
		per_call.append(float(Time.get_ticks_usec() - start) / CALLS)
	per_call.sort()
	print("| %s | %.2f | %.2f |" % [label, per_call[BATCHES / 2], per_call[int(BATCHES * 0.95)]])
