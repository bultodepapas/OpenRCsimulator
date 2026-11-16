# Observation probe for baseline 35c20367 / production cfb5acd5.
# Narrow synthetic ordering: same-handle identity replacement and explicit
# reselection happen synchronously before the quad's deferred selection callback.
# The registry and quad activity are real; devices, profile resolver and input are
# synthetic. This does not prove that an ordinary human/UI can produce the ordering.
# Assertions describe the suspected current behavior, not desired acceptance.
extends SceneTree

const Registry := preload("res://input/controller_registry.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Profile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DEVICE := 8
const DT := 1.0 / 240.0

var axes := {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
var keys := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "arm": false, "mode": false}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if ok else "FAIL", label])
	if not ok:
		failures += 1

func device(serial: String) -> Dictionary:
	return {"id": DEVICE, "name": "Synthetic radio", "raw_name": "Synthetic radio", "guid": "synthetic-guid",
		"vendor_id": 123, "product_id": 456, "serial_number": serial, "known": false, "kind": "radio"}

func _run() -> void:
	var registry := Registry.new()
	var profile_a := Profile.defaults("radio", "radio_custom")
	var profile_b := Profile.defaults("radio", "radio_custom")
	profile_b.roll.invert = true
	check("two distinct radio mappings validate", Profile.validate(profile_a).ok and Profile.validate(profile_b).ok \
		and profile_a.profile_id != profile_b.profile_id and not profile_a.roll.invert and profile_b.roll.invert)
	check("original observed and selected", registry.update_devices([device("receiver-a")]).ok \
		and registry.select_device("flight", DEVICE))
	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = registry
	activity.controller_profile_for = func(id: int) -> Dictionary:
		var serial := str(registry.device_for_id(id).get("serial_number", ""))
		return profile_a.duplicate(true) if serial == "receiver-a" else (profile_b.duplicate(true) if serial == "receiver-b" else {})
	activity.input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	activity.input.read_button = func(_id: int, _button: int) -> bool: return false
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	root.add_child(activity)
	activity.set_physics_process(false)
	var started: bool = activity.startup_error.is_empty() and activity.session != null and activity.session.prepared
	check("real scene adopts receiver A's profile", started and activity.input.radio.profile.get("profile_id", "") == profile_a.profile_id)
	if not started:
		root.remove_child(activity)
		activity.free()
		quit(1)
		return
	activity.input.radio.on_motion(DEVICE, 2, -1.0)
	activity.handle_action("resume")
	activity._physics_process(DT)
	keys.arm = true
	activity._physics_process(DT)
	keys.arm = false
	activity._physics_process(DT)
	check("receiver A is ready and motor armed", not activity.session.paused and activity._last_input.ready \
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	var old_registry_generation: int = registry.connection_generation(DEVICE)
	var old_source_generation: int = activity.input.source_generation

	# Real registry clears the selection for changed serial, but the scene handles
	# its selection callbacks deferred. Explicitly reselect B before they run.
	check("identity replacement clears selection and advances registry generation", \
		registry.update_devices([device("receiver-b")]).ok and registry.selected_device_id("flight") == -1 \
		and registry.connection_generation(DEVICE) > old_registry_generation)
	check("same numeric handle is explicitly reselected in this synthetic ordering", registry.select_device("flight", DEVICE))
	check("resolver now supplies receiver B's inverted profile", \
		str(activity.controller_profile_for.call(DEVICE).get("profile_id", "")) == str(profile_b.profile_id))
	activity._sync_selected_controller() # Same id equality guard as the queued callbacks.
	check("id-only sync keeps receiver A profile and old source generation", \
		str(activity.input.radio.profile.get("profile_id", "")) == str(profile_a.profile_id) \
		and activity.input.source_generation == old_source_generation and not activity.session.paused)
	axes[0] = 0.7
	activity.input.radio.on_motion(DEVICE, 0, 0.7)
	var tick_before: int = activity.session.sim.tick
	activity._physics_process(DT)
	check("scene accepts ready, armed input with old roll mapping", activity.session.sim.tick == tick_before + 1 \
		and activity._last_input.ready and activity._last_input.pilot[FC.IN_ROLL] > 0.6 \
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and activity.session.fault_reason.is_empty())
	await process_frame
	await process_frame
	check("queued id-only callbacks still retain the old mapping", not activity.session.paused \
		and str(activity.input.radio.profile.get("profile_id", "")) == str(profile_a.profile_id) \
		and activity.input.source_generation == old_source_generation)
	root.remove_child(activity)
	activity.free()
	print("same-handle reselection scene repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
