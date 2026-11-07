extends SceneTree
const Session := preload("res://sim/helicopter_flight_session.gd")
const Recorder := preload("res://sim/rotorcraft_recorder.gd")
const Field := preload("res://data/field_loader.gd")
const M := preload("res://physics/math3d.gd")
const OUTPUT := "C:/DEVELOPMENT/OpenRCsimulator/tmp/audit2-20261107-heli-candidate"

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var report := {format = "helicopter heading candidate v1", engine = Engine.get_version_info().string,
		session_sha256 = FileAccess.get_sha256("res://sim/helicopter_flight_session.gd"),
		electronics_sha256 = FileAccess.get_sha256("res://physics/rotorcraft/electronics.gd"), cases = {}}
	var all_ok := true
	for sign_value: float in [1.0, -1.0]:
		var name := "positive" if sign_value > 0.0 else "negative"
		var session := Session.new()
		session.input_enabled = false
		session.physics_enabled = false
		root.add_child(session)
		var ready: bool = session.setup() and session.set_field(Field.load_from().field) and session.set_start_choice("ground") and session.reset()
		if not ready:
			all_ok = false
			session.free()
			continue
		var recorder := Recorder.new(session.sim, session.trace_controls)
		recorder.start(session.trace_meta())
		var initial: Dictionary = session.checkpoint()
		var midpoint: Dictionary = {}
		var inputs: Array = []
		var hashes: Array = []
		var complete := true
		for index in 780:
			var yaw := sign_value if index < 720 else 0.0
			var sample := PackedFloat64Array([0.0, 0.0, yaw, session.startup_collective])
			inputs.append(sample)
			_apply(session, sample)
			if session.sim.tick != index + 1 or not session.sim.fault_reason.is_empty() or not session.crash.is_empty():
				complete = false
				break
			hashes.append(_digest(session))
			if index == 359: midpoint = session.checkpoint()
		var telemetry: Dictionary = session.telemetry()
		var heading: float = M.q_to_euler(session.sim.state.slice(6, 10))[0]
		var error: float = float(telemetry.controls.heading_error_rad)
		var target: float = float(telemetry.controls.target_yaw_rate_rad_s)
		var csv_path := OUTPUT.path_join(name + ".csv")
		var saved: bool = recorder.stop(csv_path) == OK
		recorder.detach()
		var replay_ok: bool = not midpoint.is_empty() and session.restore_checkpoint(midpoint).get("ok", false)
		if replay_ok:
			for index in range(360, inputs.size()):
				_apply(session, inputs[index])
				if _digest(session) != hashes[index]:
					replay_ok = false
					break
		var tape_path := OUTPUT.path_join(name + ".tape")
		var file := FileAccess.open(tape_path, FileAccess.WRITE)
		file.store_var({format = "helicopter deterministic input tape v1", initial = initial,
			midpoint = midpoint, inputs = inputs, hashes = hashes})
		file.close()
		report.cases[name] = {ticks = inputs.size(), complete = complete, csv_saved = saved,
			exact_replay = replay_ok, heading_rad = heading, heading_reference_rad = session.sim.continuous[4],
			error_rad = error, target_rad_s = target, csv_sha256 = FileAccess.get_sha256(csv_path),
			tape_sha256 = FileAccess.get_sha256(tape_path)}
		print("HELI H01 ", name, " complete=", complete, " replay=", replay_ok, " heading_error=", error, " target=", target)
		all_ok = all_ok and complete and saved and replay_ok and absf(error) < 1e-9 and absf(target) < 1e-9
		session.free()
	report.ok = all_ok
	var result := FileAccess.open(OUTPUT.path_join("witness.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(report, "\t", true, true))
	result.close()
	print("HELI H01 CANDIDATE: ", all_ok)
	quit(0 if all_ok else 1)

func _apply(session: Node, inputs: PackedFloat64Array) -> void:
	for index in 4: session.commands[["roll", "pitch", "yaw", "throttle"][index]] = inputs[index]
	session.sim.inputs = inputs.duplicate()
	session.sim.step()

func _digest(session: Node) -> String:
	return var_to_bytes([session.sim.tick, session.sim.state, session.sim.previous, session.sim.continuous,
		session.sim.aux, session.sim.inputs, session.sim.last_loads, session.shaft_phase]).hex_encode().sha256_text()
