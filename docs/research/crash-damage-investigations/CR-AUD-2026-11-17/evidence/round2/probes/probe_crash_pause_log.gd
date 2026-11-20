# Draft only: root runs this through the checked runner after import.
# Requires --out=<fresh absolute directory>; the real flight logger writes one .orfl there.
# The collision uses test_scenery_damage_session.gd's synthetic wire proxy and single-CG-probe,
# zero-gravity, 100 m/s fixture. Ordinary coupled propulsion/aerodynamic stage loads remain.
# Its initial north coordinate is -1 m so one accepted no-contact tick precedes the real
# swept terminal contact. Production bin construction covers both sides of East=0.
# No claim of a stock flight or calibrated high-speed response.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const RB := preload("res://physics/rigid_body.gd")

var checks: Array[Dictionary] = []
var failures := 0
var observations: Dictionary = {}
var output_dir := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
	_run.call_deferred()


func _check(name: String, passed: bool) -> void:
	checks.append({"name": name, "passed": passed})
	if not passed:
		failures += 1


func _finish() -> void:
	print("ROUND2_CRASH_PAUSE_LOG_COMPLETE " + JSON.stringify({
		"checks": checks, "check_count": checks.size(), "failures": failures,
		"observations": observations,
	}))
	quit(1 if failures > 0 else 0)


func _world() -> Dictionary:
	var proxy := {
		"id": "wire:probe", "kind": "fence", "part": "rail", "shape": "box",
		"response_class": "hard_terminal", "damage_id": "wire:probe", "damage_profile": "wire",
		"north": 0.2, "east": 0.0, "down": -10.0,
		"half_x": 1.0, "half_down": 5.0, "half_z": 0.1,
		"sin_heading": 0.0, "cos_heading": 1.0,
		"bounds_north_min": 0.1, "bounds_north_max": 0.3,
		"bounds_east_min": -1.0, "bounds_east_max": 1.0,
		"bounds_down_min": -15.0, "bounds_down_max": -5.0,
	}
	var proxies: Array[Dictionary] = [proxy]
	return {"format": CollisionWorld.FORMAT, "identity": "round2-crash-pause-wire",
		"cell_size_m": CollisionWorld.CELL_SIZE_M,
		"proxies": proxies, "bins": CollisionWorld._build_bins(proxies)}


func _run() -> void:
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		_check("fresh absolute --out directory supplied", false)
		_finish()
		return
	var log_path: String = output_dir.path_join("fixedwing-crash-pause.orfl")
	if FileAccess.file_exists(log_path):
		_check("output log does not already exist", false)
		_finish()
		return

	var flight: Node = Flight.new()
	flight.input_enabled = false
	flight.crash_auto_restart = false
	root.add_child(flight)
	flight.set_physics_process(false)
	var world_installed: bool = flight.set_collision_world(_world())
	flight.setup()
	_check("synthetic wire world and fixed-wing session prepared", world_installed and flight.is_flyable())
	if not world_installed or not flight.is_flyable():
		observations["setup_error"] = str(flight.start.get("message", ""))
		flight.free()
		_finish()
		return
	flight.sim.process_mode = Node.PROCESS_MODE_DISABLED
	flight.aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	flight.sim.gravity = 0.0
	var initial := PackedFloat64Array()
	initial.resize(RB.SIZE)
	initial[RB.POS] = -1.0
	initial[RB.POS + 2] = -10.0
	initial[RB.VEL] = 100.0
	initial[RB.ATT] = 1.0
	var reset_ok: bool = flight.sim.reset(initial)
	_check("disclosed synthetic start accepted", reset_ok)
	if not reset_ok:
		observations["reset_error"] = str(flight.sim.fault_reason)
		flight.free()
		_finish()
		return
	flight.resume()
	_check("fixture starts unpaused", not flight.sim.paused and flight.pause_reason.is_empty())

	var pauses: Array[Dictionary] = []
	flight.sim.paused_changed.connect(func(paused: bool) -> void:
		if not paused:
			return
		var contacts: Dictionary = flight.contact_events()
		pauses.append({"tick": int(flight.sim.tick), "reason": str(flight.pause_reason),
			"crashed": not flight.crash.is_empty(), "scenery_damage_count": flight.scenery_damage().size(),
			"contact_event_count": contacts.get("events", []).size()}))
	var writer: RefCounted = FlightLog.new(flight)
	var start_error: Error = writer.start(log_path)
	_check("real flight logger starts", start_error == OK)
	if start_error != OK:
		observations["logger_start_error"] = str(writer.failure)
		flight.free()
		_finish()
		return

	# Positive control: an explicitly staged reason before an ordinary user pause is observed and logged.
	flight.pause_reason = "manual pause control"
	flight.sim.set_paused(true)
	flight.resume()
	_check("ordinary pause/resume leaves the fixture running", not flight.sim.paused and flight.pause_reason.is_empty())
	flight.sim.step()
	_check("first accepted tick is clear of the wire", int(flight.sim.tick) == 1 and flight.crash.is_empty() \
		and not flight.sim.paused and flight.sim.fault_reason.is_empty())
	for _i: int in 4:
		if not flight.crash.is_empty() or not flight.sim.fault_reason.is_empty():
			break
		flight.sim.step()
	var final_reason: String = str(flight.pause_reason)
	var final_tick: int = int(flight.sim.tick)
	var final_damage: Dictionary = flight.scenery_damage()
	var final_contacts: Dictionary = flight.contact_events()
	_check("real swept wire strike reaches a terminal accepted tick", not flight.crash.is_empty() \
		and final_reason.begins_with("CRASH at ") and flight.sim.paused and flight.sim.fault_reason.is_empty())
	_check("terminal hit commits wire damage and a contact event", final_damage.has("wire:probe") \
		and not final_contacts.get("events", []).is_empty())

	var callback_crash: Dictionary = {}
	var callback_manual: Dictionary = {}
	for pause_event: Dictionary in pauses:
		if bool(pause_event.crashed):
			callback_crash = pause_event
		elif str(pause_event.reason) == "manual pause control":
			callback_manual = pause_event
	_check("ordinary pause callback receives its staged reason", not callback_manual.is_empty())
	_check("crash pause callback sees final crash reason", not callback_crash.is_empty() \
		and str(callback_crash.get("reason", "")) == final_reason)
	_check("crash pause callback sees committed contact and scenery damage", not callback_crash.is_empty() \
		and int(callback_crash.get("scenery_damage_count", -1)) == final_damage.size() \
		and int(callback_crash.get("contact_event_count", -1)) == final_contacts.get("events", []).size())

	var stop_error: Error = writer.stop("round2 probe complete")
	_check("real flight logger closes without error", stop_error == OK and not writer.recording)
	var read: Dictionary = Reader.inspect(log_path)
	_check("flight log is complete and readable", bool(read.get("ok", false)) and bool(read.get("complete", false)))
	var logged_manual := ""
	var logged_crash := ""
	var logged_crash_found := false
	if read.get("ok", false):
		for item: Variant in read.events:
			if not item is Dictionary or str(item.get("kind", "")) != "pause":
				continue
			if int(item.get("tick", -1)) == 0:
				logged_manual = str(item.get("detail", ""))
			if int(item.get("tick", -1)) == final_tick:
				logged_crash = str(item.get("detail", ""))
				logged_crash_found = true
	_check("saved ordinary pause reason matches", logged_manual == "manual pause control")
	_check("saved crash pause reason matches the final crash reason", logged_crash_found and logged_crash == final_reason)
	observations["fixture"] = {"synthetic_cg_probe": true, "zero_gravity": true, "ordinary_coupled_stage_loads": true,
		"initial_north_m": -1.0, "initial_down_m": -10.0, "initial_forward_mps": 100.0,
		"world": "single hard-terminal wire proxy"}
	observations["crash"] = {"tick": final_tick, "final_reason": final_reason,
		"final_damage_count": final_damage.size(), "final_contact_event_count": final_contacts.get("events", []).size(),
		"callback": callback_crash, "manual_callback": callback_manual,
		"log_ok": bool(read.get("ok", false)), "log_error": str(read.get("error", "")),
		"logged_manual_reason": logged_manual, "logged_crash_found": logged_crash_found,
		"logged_crash_reason": logged_crash, "log_path": log_path}
	flight.free()
	_finish()
