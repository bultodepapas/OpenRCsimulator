# HELI-20 research probe: full accepted helicopter-session physics-step cost.
extends SceneTree

const Session = preload("res://sim/helicopter_flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const TICK_RATE_HZ: int = 240
const DEFAULT_STEADY_TICKS: int = 2400
const DEFAULT_SOFT_SPOOL_TICKS: int = 12 * TICK_RATE_HZ
const DEFAULT_WARMUP_TICKS: int = 120
const RESULT_MARKER: String = "HELI_PROFILE_RESULT_JSON:"
const ERROR_MARKER: String = "HELI_PROFILE_ERROR_JSON:"

var settings: Dictionary = {
	"steady_ticks": DEFAULT_STEADY_TICKS,
	"soft_spool_ticks": DEFAULT_SOFT_SPOOL_TICKS,
	"warmup_ticks": DEFAULT_WARMUP_TICKS,
}
var _failure: String = ""


func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--parse-only"):
		print("HELI_PROFILE_PARSE_OK")
		quit(0)
		return
	_read_settings()
	call_deferred("_run")


func _read_settings() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.split("=", false, 1)
		if pair.size() != 2:
			continue
		var value: int = int(pair[1])
		if pair[0] == "--steady-ticks":
			settings.steady_ticks = value
		elif pair[0] == "--soft-spool-ticks":
			settings.soft_spool_ticks = value
		elif pair[0] == "--warmup-ticks":
			settings.warmup_ticks = value
	if int(settings.steady_ticks) <= 0 or int(settings.soft_spool_ticks) <= 0 \
			or int(settings.warmup_ticks) < 0:
		_failure = "profile tick counts must be positive (warmup may be zero)"


func _run() -> void:
	if not _failure.is_empty():
		_emit_error(_failure)
		return
	if Engine.physics_ticks_per_second != TICK_RATE_HZ:
		_emit_error("project fixed tick rate is not 240 Hz")
		return
	var specs: Array[Dictionary] = [
		{"name": "stoppedground", "start": "ground", "mode": "stopped"},
		{"name": "12ssoftspool", "start": "ground", "mode": "soft_spool"},
		{"name": "governedground", "start": "ground", "mode": "governed"},
		{"name": "legacyairbornehover", "start": "airborne", "mode": "airborne"},
	]
	var scenarios: Array[Dictionary] = []
	for spec: Dictionary in specs:
		var result: Dictionary = _run_scenario(spec)
		if not result.get("ok", false):
			_emit_error(str(result.get("error", "scenario failed: " + str(spec.name))))
			return
		scenarios.append(result)
	var report: Dictionary = {
		"format": "openrc-heli-session-profile-samples-v1",
		"step_call": "session.sim.step()",
		"tick_rate_hz": TICK_RATE_HZ,
		"tick_duration_s": 1.0 / float(TICK_RATE_HZ),
		"timing_clock": "Time.get_ticks_usec() surrounding each complete Simulation.step() call",
		"control_trace_recording": false,
		"accepted_tick_observer": "Session._on_stepped (existing session observer); each tick acceptance is checked by tick increment",
		"sample_timing_includes_signal_observers": true,
		"settings": settings.duplicate(),
		"scenarios": scenarios,
	}
	print(RESULT_MARKER + JSON.stringify(report))
	quit(0)


func _run_scenario(spec: Dictionary) -> Dictionary:
	var session: Node = Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	root.add_child(session)
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
	if not field.get("ok", false) or not session.setup() \
			or not session.set_field(field.field) or not session.set_start_choice(str(spec.start)) \
			or not session.reset() or not session.is_flyable():
		var reason: String = str(session.start_error)
		if reason.is_empty():
			reason = str(session.pause_reason)
		if reason.is_empty():
			reason = "; ".join(field.get("errors", []))
		session.free()
		return {"ok": false, "error": "scenario setup refused: " + reason}
	if str(spec.start) == "ground" and session.sim.continuous.size() != 14:
		session.free()
		return {"ok": false, "error": "ground profile did not use the 14-state skids/bristles layout"}
	if session.sim.dt() != 1.0 / float(TICK_RATE_HZ):
		session.free()
		return {"ok": false, "error": "session fixed timestep is not exactly 1/240 s"}
	if str(spec.mode) in ["soft_spool", "governed"]:
		if not session.toggle_motor_arm() or not session.power.armed \
				or not session.set_drive_hold(false):
			session.free()
			return {"ok": false, "error": "explicit ground arm/release sequence refused"}
	var warmup_ticks: int = int(settings.warmup_ticks)
	var unmeasured_preroll_ticks: int = 0
	if str(spec.mode) == "governed":
		unmeasured_preroll_ticks = int(settings.soft_spool_ticks)
		if not _advance_unmeasured(session, unmeasured_preroll_ticks):
			var fault: String = str(session.pause_reason)
			session.free()
			return {"ok": false, "error": "ground spool pre-roll failed: " + fault}
		if session.power_phase() != "GOVERNED":
			session.free()
			return {"ok": false, "error": "ground pre-roll did not reach governed RPM"}
	elif str(spec.mode) == "airborne":
		if session.power_phase() not in ["GOVERNED", "RUNNING"]:
			session.free()
			return {"ok": false, "error": "legacy airborne reset did not initialize at governed RPM"}
	if warmup_ticks > 0 and not _advance_unmeasured(session, warmup_ticks):
		var fault: String = str(session.pause_reason)
		session.free()
		return {"ok": false, "error": "scenario warmup failed: " + fault}
	var measurement_ticks: int = int(settings.soft_spool_ticks) \
		if str(spec.mode) == "soft_spool" else int(settings.steady_ticks)
	var start_tick: int = session.sim.tick
	var start_time_s: float = session.sim.time()
	var start_omega: float = float(session.sim.continuous[0])
	var start_power_phase: String = session.power_phase()
	var samples: Array[Dictionary] = []
	samples.resize(measurement_ticks)
	for index: int in range(measurement_ticks):
		var previous_tick: int = session.sim.tick
		var clock_start: int = Time.get_ticks_usec()
		session.sim.step()
		var elapsed_usec: int = Time.get_ticks_usec() - clock_start
		if session.sim.tick != previous_tick + 1 or not session.is_flyable():
			var fault: String = str(session.sim.fault_reason)
			if fault.is_empty():
				fault = str(session.pause_reason)
			session.free()
			return {"ok": false, "error": "measured tick rejected in " + str(spec.name) + ": " + fault}
		var omega: float = float(session.sim.continuous[0])
		samples[index] = {
			"sample_index": index,
			"tick": session.sim.tick,
			"sim_time_s": session.sim.time(),
			"elapsed_usec": elapsed_usec,
			"omega_rad_s": omega,
			"rpm": omega * 60.0 / (2.0 * PI),
		}
	var summary: Dictionary = {
		"ok": true,
		"name": str(spec.name),
		"start_choice": str(spec.start),
		"mode": str(spec.mode),
		"measurement_ticks": measurement_ticks,
		"accepted_ticks": measurement_ticks,
		"warmup_ticks": warmup_ticks,
		"unmeasured_preroll_ticks": unmeasured_preroll_ticks,
		"start_tick": start_tick,
		"end_tick": session.sim.tick,
		"start_sim_time_s": start_time_s,
		"start_omega_rad_s": start_omega,
		"start_power_phase": start_power_phase,
		"end_omega_rad_s": float(session.sim.continuous[0]),
		"end_rpm": float(session.sim.continuous[0]) * 60.0 / (2.0 * PI),
		"end_power_phase": session.power_phase(),
		"continuous_state_count": session.sim.continuous.size(),
		"samples": samples,
	}
	session.free()
	return summary


func _advance_unmeasured(session: Node, count: int) -> bool:
	for _index: int in range(count):
		var previous_tick: int = session.sim.tick
		session.sim.step()
		if session.sim.tick != previous_tick + 1 or not session.is_flyable():
			return false
	return true


func _emit_error(message: String) -> void:
	print(ERROR_MARKER + JSON.stringify({"ok": false, "error": message}))
	quit(1)
