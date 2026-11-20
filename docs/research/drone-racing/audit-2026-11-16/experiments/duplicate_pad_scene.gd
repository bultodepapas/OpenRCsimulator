# Observation probe for baseline 35c20367 / production cfb5acd5.
# Real controller service, registry, quad scene and adapter, but synthetic
# device records, input and focused-pad verifier. The checked result cannot
# qualify actual SDL hotplug timing, physical radios or in-air reachability.
# Passing assertions describe a suspected baseline behavior, not desired behavior.
extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DEVICE := 7
const DT := 1.0 / 240.0

var keys := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "arm": false, "mode": false}
var observations: Array = []
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		failures += 1

func device(id: int, guid: String, serial: String) -> Dictionary:
	return {"id": id, "name": "Synthetic gamepad", "raw_name": "Synthetic gamepad", "guid": guid,
		"vendor_id": 123, "product_id": 456, "serial_number": serial, "known": true, "kind": "gamepad"}

func _run() -> void:
	var original := device(DEVICE, "pad-family", "pad-a")
	var different := device(9, "different-family", "pad-c")
	var duplicate := device(8, "pad-family", "pad-b")
	observations = [original]
	var service := Service.new()
	var prefix := "user://quad_duplicate_audit_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	service.store = Service.Store.new(prefix + ".profiles", prefix + ".legacy")
	service.enumerate_devices = func() -> Array: return observations.duplicate(true)
	service.allow_automatic_selection = func() -> bool: return false # Same ownership policy as an active Home-launched activity.
	root.add_child(service)
	service.set_process(false)
	var registry = service.registry
	check("real service observes original pad and permits explicit selection", registry.device_for_id(DEVICE).get("connected", false) \
		and registry.select_device("flight", DEVICE))
	check("real service resolves an explicit healthy default", not service.profile_for_device(DEVICE).is_empty())
	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = registry
	activity.controller_profile_for = Callable(service, "profile_for_device")
	# Models the service's selected-id/generation checks, while standing in for
	# OS focus and the real SDL pad checks unavailable to a synthetic fixture.
	activity.controller_confirmation = func(id: int, expected_id: int, generation: int) -> bool:
		return id == expected_id and registry.selected_device_id("flight") == id \
			and registry.connection_generation(id) == generation and bool(registry.device_for_id(id).get("connected", false))
	activity.input.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	activity.input.read_button = func(_id: int, _button: int) -> bool: return false
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	root.add_child(activity)
	activity.set_physics_process(false)
	var started: bool = activity.startup_error.is_empty() and activity.session != null and activity.session.prepared
	check("real scene adopts selected pad", started and activity.input.radio.connected \
		and activity.input.radio.is_gamepad() and activity.input.radio.device_id == DEVICE)
	if not started:
		root.remove_child(activity)
		activity.free()
		service.free()
		quit(1)
		return
	activity.handle_action("resume")
	activity._physics_process(DT)
	keys.arm = true
	activity._physics_process(DT)
	keys.arm = false
	activity._physics_process(DT)
	check("confirmed pad is ready and real session motor arms", not activity.session.paused and activity._last_input.ready \
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and activity.input.radio.can_confirm_gamepad_poll())
	var source_generation: int = activity.input.source_generation
	var registry_generation: int = registry.connection_generation(DEVICE)

	# Positive control: a different fingerprint must not break the original pad.
	observations = [original, different]
	service._connection_changed(9, true)
	check("different device arrival leaves selected generation unchanged", \
		registry.selected_device_id("flight") == DEVICE \
		and registry.connection_generation(DEVICE) == registry_generation)
	activity._joy_connection_changed(9, true)
	await process_frame
	await process_frame
	activity._physics_process(DT)
	check("different device leaves selected pad ready and armed", not activity.session.paused and activity._last_input.ready \
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and activity.input.source_generation == source_generation)
	observations = [original]
	service._connection_changed(9, false)
	activity._joy_connection_changed(9, false)
	await process_frame
	await process_frame

	# Same family, new serial: the selected original remains connected and selected;
	# registry ambiguity changes its generation without emitting selection loss.
	observations = [original, duplicate]
	service._connection_changed(8, true)
	check("matching family marks ambiguity but retains original selection", \
		registry.selected_device_id("flight") == DEVICE \
		and registry.device_for_id(DEVICE).connected and registry.device_for_id(DEVICE).ambiguous \
		and registry.connection_generation(DEVICE) > registry_generation)
	activity._joy_connection_changed(8, true)
	await process_frame
	await process_frame
	check("id-only sync leaves old source generation and stale verifier", not activity.session.paused \
		and activity.input.source_generation == source_generation and not activity.input.radio.can_confirm_gamepad_poll() \
		and not service._confirmed_gamepad_connection(DEVICE, DEVICE, registry_generation))
	var tick_before: int = activity.session.sim.tick
	activity._physics_process(DT)
	check("next scene tick accepts an unready source and disarms", activity.session.sim.tick == tick_before + 1 \
		and not activity._last_input.ready and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED \
		and activity.session.fault_reason.is_empty())
	check("the scene remains running without opening the menu", not activity.session.paused and not activity.hud.menu_visible)

	# Removing the duplicate increments the original's generation again; id-only
	# sync still cannot make its old generation-bound verifier current.
	observations = [original]
	service._connection_changed(8, false)
	check("removing duplicate restores uniqueness and original role", registry.selected_device_id("flight") == DEVICE and not registry.device_for_id(DEVICE).ambiguous)
	activity._joy_connection_changed(8, false)
	await process_frame
	await process_frame
	check("the original verifier remains stale after duplicate removal", activity.input.source_generation == source_generation \
		and not activity.input.radio.can_confirm_gamepad_poll())
	root.remove_child(activity)
	activity.free()
	service.free()
	print("duplicate pad scene repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
