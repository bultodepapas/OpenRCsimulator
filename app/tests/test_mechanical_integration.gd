extends SceneTree

const MainScene: PackedScene = preload("res://main.tscn")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")

const COMBUSTION_ID := "p51d-mustang-120"
const ELECTRIC_ID := "turbo-lumber-evolution"
const MECHANICAL_CONFIG := {"servo_type": "high_torque", "servo_level": 0.35, "retract_type": "pneumatic"}
const DT: float = 1.0 / 240.0

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.audio_listener_enable_3d = true
	await _test_workshop_flight_integration()
	await _test_electric_rpm_masking()
	print("Mechanical integration: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _frozen_trial(aircraft_id: String) -> Dictionary:
	var described: Dictionary = Customization.describe(aircraft_id)
	_check(aircraft_id + " has current Workshop bindings", bool(described.get("ok", false)), str(described.get("errors", [])))
	if not bool(described.get("ok", false)):
		return {}
	var profile: Dictionary = Presentation.defaults(described.bindings)
	profile["mechanical_audio"] = MECHANICAL_CONFIG.duplicate(true)
	var entry: Dictionary = Catalog.entry(aircraft_id)
	var result: Dictionary = Trial.freeze({
		"base_id": aircraft_id,
		"base_bytes": FileAccess.get_file_as_bytes(str(entry.get("data", ""))),
		"recipe": {},
		"presentation_profile": profile,
	})
	_check(aircraft_id + " freezes an exact v4 Workshop audio profile",
		bool(result.get("ok", false))
		and int(result.get("presentation_profile", {}).get("version", 0)) == 4
		and result.get("presentation_profile", {}).get("mechanical_audio", {}) == MECHANICAL_CONFIG,
		str(result.get("errors", [])))
	return result if bool(result.get("ok", false)) else {}


func _start_flight(aircraft_id: String) -> Node:
	var frozen: Dictionary = _frozen_trial(aircraft_id)
	if frozen.is_empty():
		return null
	var flight: Node = MainScene.instantiate()
	flight.set_user_args(PackedStringArray(["--scenery=off", "--birds=off", "--crash-effects=off"]))
	flight.set("workshop_trial", frozen)
	flight.set("aircraft_id", aircraft_id)
	flight.set("interactive_start", true)
	flight.set("start_choice", "airborne")
	flight.set("crash_effects_enabled", false)
	root.add_child(flight)
	for _frame: int in 120:
		if bool(flight.get("startup_complete")):
			break
		await process_frame
	var session: Node = flight.get("session") as Node
	var adapter: Node = flight.get("_soundscape_audio") as Node
	if session != null:
		session.set_physics_process(false)
		(session.get("sim") as Node).set_physics_process(false)
		(session.get("sim") as Node).set_process(false)
	flight.set_process(false)
	flight.set_process_unhandled_input(false)
	if adapter != null:
		adapter.set_process(false)
	_check(aircraft_id + " starts a production flight with mechanical audio",
		bool(flight.get("startup_complete")) and str(flight.get("startup_error")).is_empty()
		and session != null and adapter != null,
		"startup=%s error=%s" % [str(flight.get("startup_complete")), str(flight.get("startup_error"))])
	return flight


func _test_workshop_flight_integration() -> void:
	var flight: Node = await _start_flight(COMBUSTION_ID)
	if flight == null or flight.get("_soundscape_audio") == null:
		await _close_flight(flight)
		return
	var session: Node = flight.get("session") as Node
	var sim: Node = session.get("sim") as Node
	var adapter: Node = flight.get("_soundscape_audio") as Node
	var mechanical: Node = adapter.get("mechanical_audio") as Node
	var configured: Dictionary = mechanical.get("_config") as Dictionary
	_check("v4 Workshop config reaches the flight MechanicalAudio node", configured == MECHANICAL_CONFIG, str(configured))
	var soundscape: Node = adapter.get("soundscape") as Node
	var voice_profile: Dictionary = soundscape.get("voice_profile") as Dictionary
	_check("production aircraft audio identifies the combustion family",
		str(voice_profile.get("family", "")) == "gasoline", str(voice_profile))

	var camera: Camera3D = flight.get("_camera") as Camera3D
	var listener := AudioListener3D.new()
	listener.position = Vector3(0.0, 0.5, 0.0)
	(flight.get("_airplane").get("root") as Node3D).add_child(listener)
	listener.make_current()
	_check("FlightAudio follows the active viewport AudioListener3D",
		adapter.call("listener_position").is_equal_approx(listener.get_listener_transform().origin))
	listener.clear_current()
	_check("FlightAudio falls back to the flight camera when no listener is active",
		adapter.call("listener_position").is_equal_approx(camera.global_position),
		"listener=%s camera=%s" % [str(adapter.call("listener_position")), str(camera.global_position)])
	listener.make_current()

	_test_mask_from_accepted_rpm(session, adapter, "gasoline")
	session.call("reset")
	adapter.call("_process", DT)
	var initial_snapshot: Dictionary = adapter.get("_mechanical_snapshot") as Dictionary
	var initial_channels: Array = initial_snapshot.get("channels", [])
	var initial_angles: Dictionary = session.call("surface_angles_deg")
	var initial_gear: Dictionary = session.call("gear_state")
	_check("P-51 production flight exposes accepted retracts and flaps",
		bool(initial_gear.get("available", false)) and bool(session.call("flaps_available"))
		and initial_channels.size() == 4 and str(initial_channels[3].get("id", "")) == "flap",
		"gear=%s channels=%s" % [str(initial_gear), str(initial_channels)])

	var session_before_command: Dictionary = session.call("checkpoint")
	var command_profile: Dictionary = session.get("commands") as Dictionary
	command_profile["roll"] = 0.75
	command_profile["pitch"] = 0.12
	command_profile["throttle"] = 0.3
	session.set("commands", command_profile)
	var gear_command_accepted: bool = bool(session.call("set_gear_down", true))
	var flap_command_accepted: bool = bool(session.call("set_flaps", 1.0))
	_check("production retract and flap requests are accepted", gear_command_accepted and flap_command_accepted)
	adapter.call("_process", DT)
	var command_only: Dictionary = adapter.get("_mechanical_snapshot") as Dictionary
	_check("pilot and mechanism requests alone do not create actuator travel audio",
		var_to_bytes(session.call("checkpoint")) == var_to_bytes(session_before_command)
		and is_equal_approx(float(command_only.gear.get("extension", -1.0)), float(initial_gear.extension))
		and float(command_only.channels[0].get("angle_deg", NAN)) == float(initial_channels[0].angle_deg)
		and int(mechanical.call("diagnostics").get("events_played", 0)) == 0,
		str(mechanical.call("diagnostics")))

	var inputs: PackedFloat64Array
	for _tick: int in 200:
		inputs = session.call("_inputs") as PackedFloat64Array
		sim.set("inputs", inputs)
		sim.call("step")
		adapter.call("_process", DT)
	var accepted_angles: Dictionary = session.call("surface_angles_deg") as Dictionary
	var accepted_flaps: Dictionary = session.call("flap_state") as Dictionary
	var accepted_gear: Dictionary = session.call("gear_state") as Dictionary
	var moved_snapshot: Dictionary = adapter.get("_mechanical_snapshot") as Dictionary
	var moved_channels: Array = moved_snapshot.get("channels", [])
	var expected_flap_angle: float = float(session.get("sim").get("aux")[session.call("flap_aux_index")]) \
		* float(session.get("aircraft").get("model").get("flaps").get("max_angle_deg"))
	_check("accepted flight ticks move the real control servo, flap actuator and retracts",
		accepted_angles.get("aileron_right", 0.0) != initial_angles.get("aileron_right", 0.0)
		and float(accepted_flaps.get("actual", 0.0)) > 0.0
		and float(accepted_gear.get("extension", 0.0)) > 0.0,
		"angles=%s flaps=%s gear=%s" % [str(accepted_angles), str(accepted_flaps), str(accepted_gear)])
	_check("mechanical adapter reports accepted channel angles, flap fraction and gear extension",
		is_equal_approx(float(moved_channels[0].get("angle_deg", NAN)), float(accepted_angles.aileron_right))
		and is_equal_approx(float(moved_channels[3].get("angle_deg", NAN)), expected_flap_angle)
		and is_equal_approx(float(moved_snapshot.gear.get("extension", NAN)), float(accepted_gear.extension)),
		"snapshot=%s" % str(moved_snapshot))
	_check("accepted motion reaches the configured real mechanical voices",
		int(mechanical.call("diagnostics").get("events_played", 0)) > 0
		and int(mechanical.call("diagnostics").get("motion_voice_count", 0)) > 0,
		str(mechanical.call("diagnostics")))

	var diagnostics_before_reset: Dictionary = mechanical.call("diagnostics")
	session.call("reset")
	var diagnostics_after_reset: Dictionary = mechanical.call("diagnostics")
	_check("FlightSession reset clears the audio motion observer and voices",
		int(diagnostics_after_reset.get("reset_count", 0)) == int(diagnostics_before_reset.get("reset_count", 0)) + 1
		and int(diagnostics_after_reset.get("active_motion_voices", 0)) == 0
		and int(diagnostics_after_reset.get("playing_event_voices", 0)) == 0
		and int(diagnostics_after_reset.get("pending_event_count", 0)) == 0
		and int(adapter.get("_last_tick")) == -1,
		str(diagnostics_after_reset))
	await _close_flight(flight)


func _test_mask_from_accepted_rpm(session: Node, adapter: Node, family: String) -> void:
	var sim: Node = session.get("sim") as Node
	var commands: Dictionary = session.get("commands") as Dictionary
	commands["roll"] = 0.0
	commands["pitch"] = 0.0
	commands["yaw"] = 0.0
	commands["throttle"] = 0.0
	session.set("commands", commands)
	var inputs: PackedFloat64Array
	for _tick: int in 80:
		inputs = session.call("_inputs") as PackedFloat64Array
		sim.set("inputs", inputs)
		sim.call("step")
	var low_sound: Dictionary = adapter.call("snapshot") as Dictionary
	for _sample: int in 40:
		adapter.call("mechanical_snapshot", low_sound, 0.1)
	var low_mask: float = float(adapter.get("_mechanical_mask"))
	commands = session.get("commands") as Dictionary
	commands["throttle"] = 1.0
	session.set("commands", commands)
	for _tick: int in 180:
		inputs = session.call("_inputs") as PackedFloat64Array
		sim.set("inputs", inputs)
		sim.call("step")
	var high_sound: Dictionary = adapter.call("snapshot") as Dictionary
	for _sample: int in 40:
		adapter.call("mechanical_snapshot", high_sound, 0.1)
	var high_mask: float = float(adapter.get("_mechanical_mask"))
	_check(family + " mask samples the accepted FlightSession RPM and running state",
		float(high_sound.get("rpm", -1.0)) == float(sim.get("aux")[0]) and bool(high_sound.get("running", false)),
		"sound=%s rpm=%s" % [str(high_sound), str(sim.get("aux")[0])])
	_check(family + " accepted higher shaft speed increases engine masking",
		float(high_sound.get("rpm", 0.0)) > float(low_sound.get("rpm", -1.0))
		and high_mask < low_mask,
		"low=%.1f/%.4f high=%.1f/%.4f" % [float(low_sound.get("rpm", 0.0)), low_mask,
		float(high_sound.get("rpm", 0.0)), high_mask])


func _test_electric_rpm_masking() -> void:
	var flight: Node = await _start_flight(ELECTRIC_ID)
	if flight == null or flight.get("_soundscape_audio") == null:
		await _close_flight(flight)
		return
	var adapter: Node = flight.get("_soundscape_audio") as Node
	var session: Node = flight.get("session") as Node
	var soundscape: Node = adapter.get("soundscape") as Node
	var voice_profile: Dictionary = soundscape.get("voice_profile") as Dictionary
	_check("production electric flight selects the electric voice bank",
		str(voice_profile.get("family", "")) == "electric", str(voice_profile))
	_test_mask_from_accepted_rpm(session, adapter, "electric")
	await _close_flight(flight)


func _close_flight(flight: Node) -> void:
	if not is_instance_valid(flight):
		return
	var adapter: Node = flight.get("_soundscape_audio") as Node
	if adapter == null:
		flight.queue_free()
		await process_frame
		return
	var audio_weak: WeakRef = weakref(adapter)
	var soundscape: Node = adapter.get("soundscape") as Node
	var bus_names: Array = soundscape.get("_bus_names") as Array
	flight.queue_free()
	await process_frame
	await process_frame
	_check("scene cleanup frees its production FlightAudio node", audio_weak.get_ref() == null)
	var buses_removed := true
	for bus_value: Variant in bus_names:
		buses_removed = buses_removed and AudioServer.get_bus_index(StringName(str(bus_value))) == -1
	_check("scene cleanup releases every soundscape bus", buses_removed, str(bus_names))
