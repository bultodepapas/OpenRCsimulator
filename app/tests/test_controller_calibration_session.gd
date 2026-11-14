extends SceneTree

const Profile := preload("res://input/controller_profile.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const Flight := preload("res://sim/flight_session.gd")
const Helicopter := preload("res://sim/helicopter_flight_session.gd")
const Simulation := preload("res://sim/simulation.gd")

var checks := 0
var failures := 0


class CompletedCalibration extends RefCounted:
	var profile: Dictionary
	var aux_warning := "Existing gear control needs reassignment. Existing smoke control needs reassignment."
	func _init(measured: Dictionary) -> void: profile = measured.duplicate(true)
	func advance(_axes: PackedFloat64Array) -> bool: return true


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	for kind in ["airplane", "helicopter"]:
		var session: Node = Flight.new() if kind == "airplane" else Helicopter.new()
		if kind == "airplane": session.sim = Simulation.new()
		var simulation: Node = session.sim
		session.external_controller_selection = true
		var info := {"name": "Calibration fixture", "guid": "fixture-radio", "known": false}
		var original := Profile.defaults("radio", "radio_custom")
		session.radio.connect_device(7, info, original)
		check(kind + " rejects managed calibration without a generation lease", not session.start_calibration())
		var lease := {"value": 12, "calls": 0}
		session.controller_connection_generation = func(_id: int) -> int: return lease.value
		session.persist_controller_profile = func(_profile: Dictionary) -> Dictionary:
			lease.calls += 1
			return {"ok": false, "error": "Action camera_cycle uses primary flight axis 5"}
		check(kind + " captures a positive connection generation", session.start_calibration())
		var measured: Dictionary = Calibration.new().profile
		measured.roll = {"axis": 5, "min": -1.0, "center": 0.0, "max": 1.0, "invert": false}
		var old_profile: Dictionary = session.radio.profile.duplicate(true)
		session.calibration = CompletedCalibration.new(measured)
		session.advance_calibration()
		var pending: Dictionary = session.pending_controller_calibration
		check(kind + " retains measured work and complete source lease after refusal", session.calibration == null \
			and pending.get("profile", {}) == measured and pending.get("device_id", -1) == 7 \
			and pending.get("device_key", "") == session.radio.device_key and pending.get("generation", -1) == 12)
		check(kind + " reports action and all AUX conflicts while old profile remains active", session.radio.profile == old_profile \
			and "camera_cycle" in session.pause_reason and "gear" in session.pause_reason and "smoke" in session.pause_reason)
		check(kind + " starts another calibration explicitly", session.start_calibration())
		session.calibration = CompletedCalibration.new(measured)
		lease.value = 13
		session.advance_calibration()
		check(kind + " refuses a changed generation before persistence", session.calibration == null \
			and session.pending_controller_calibration.is_empty() and lease.calls == 1 and "changed" in session.pause_reason)
		lease.value = 13
		check(kind + " can start again after change", session.start_calibration())
		session.calibration = CompletedCalibration.new(measured)
		session.advance_calibration()
		session.controller_disconnected()
		check(kind + " disconnect discards pending measurements", session.pending_controller_calibration.is_empty())
		simulation.free()
		session.free()
	print("Controller calibration session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
