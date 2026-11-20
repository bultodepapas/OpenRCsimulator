# Observation probe for baseline 35c20367 / production cfb5acd5; results in the follow-up evidence.
# Passing assertions reproduce A03; they are not desired-behavior acceptance tests.
# Real activity, session, production data and menu handlers; simulated selected radio
# and a supported research/test air start. No hardware or normal-flight claim.
extends SceneTree

const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const Profile := preload("res://input/controller_profile.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DT := 1.0 / 240.0
const DEVICE := 8
const ARM_BUTTON := 20

class Registry extends RefCounted:
	signal selection_changed(role: String, id: int)
	func selected_device_id(role: String) -> int:
		return 8 if role == "flight" else -1
	func device_for_id(id: int) -> Dictionary:
		return {"id": id, "connected": true, "name": "Synthetic radio", "guid": "audit-radio",
			"known": false, "kind": "radio"} if id == 8 else {}
	func connection_generation(_id: int) -> int:
		return 1

var axes := {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0}
var buttons := {ARM_BUTTON: false}
var keys := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0, "throttle": 0.0, "arm": false, "mode": false}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition:
		failures += 1

func _run() -> void:
	var profile := Profile.defaults("radio", "radio_custom")
	profile.aux = {"arm": {"type": "button", "button": ARM_BUTTON, "mode": "level"}}
	check("synthetic Arm AUX profile validates", Profile.validate(profile).ok)
	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = Registry.new()
	activity.controller_profile_for = func(_id: int) -> Dictionary: return profile.duplicate(true)
	activity.input.read_axis = func(_id: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	activity.input.read_button = func(_id: int, button: int) -> bool: return bool(buttons.get(button, false))
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	root.add_child(activity)
	activity.set_physics_process(false) # Deterministic manual calls through the real scene method.
	var started: bool = activity.startup_error.is_empty() and activity.session != null and activity.session.prepared
	check("real activity prepared with selected radio", started and activity.input.radio.connected \
		and activity.input.radio.device_id == DEVICE and activity.input.arm_aux() == "arm")
	if not started:
		root.remove_child(activity)
		activity.free()
		print("scene pause repro: %d checks, %d failed" % [checks, failures])
		quit(1)
		return

	# Use the session's admitted air-start contract, not a hand-edited controller or motor state.
	var options: Dictionary = activity._session_options()
	options.start = "air"
	options.altitude_m = 20.0
	check("research air start prepares", activity.session.prepare(activity.field, options))
	if not activity.session.prepared or str(activity.session.options.start) != "air":
		root.remove_child(activity)
		activity.free()
		print("scene pause repro: %d checks, %d failed" % [checks, failures])
		quit(1)
		return
	var body: PackedFloat64Array = activity.session.plant_frame().body
	var ground: PackedFloat64Array = activity.session.environment.ground(body[0], body[1])
	check("air-start altitude is 20 m AGL", absf(-body[2] - ground[0] - 20.0) < 1.0e-6)

	# Resume first: paused samples intentionally disable AUX. Give fresh throttle LOW,
	# then, on integrating ticks, the same release/press evidence as the plant repro.
	activity.input.radio.on_motion(DEVICE, 2, -1.0)
	activity.handle_action("resume")
	check("ready radio resumes initial menu", not activity.session.paused)
	activity._physics_process(DT)
	activity.input.radio.on_button(DEVICE, ARM_BUTTON, false)
	activity._physics_process(DT)
	buttons[ARM_BUTTON] = true
	activity.input.radio.on_button(DEVICE, ARM_BUTTON, true)
	activity._physics_process(DT)
	check("fresh OFF then ON arms the real activity session", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED \
		and bool(activity._last_input.ready) and activity.session.fault_reason.is_empty())
	var tick_before: int = activity.session.sim.tick
	var generation_before: int = activity.input.source_generation

	# This is the exact menu/Continue handler path called by the activity's P/Escape.
	activity._open_menu("Flight paused")
	activity._physics_process(DT)
	check("ordinary menu holds an armed flight without a source change", activity.session.paused \
		and activity.hud.menu_visible and activity.session.sim.tick == tick_before \
		and activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED \
		and activity.input.source_generation == generation_before)
	check("menu offers ordinary Resume flight", not activity.hud.resume_button.disabled \
		and activity.hud.resume_button.text == "Resume flight")
	activity.handle_action("resume")
	check("Continue unpauses while the physical Arm switch stays ON", not activity.session.paused \
		and bool(buttons[ARM_BUTTON]))
	activity._physics_process(DT)
	var resumed: Dictionary = activity._last_input
	check("first resumed scene sample is ready but substitutes OFF", resumed.ready \
		and resumed.pilot[FC.IN_ARM] == 0.0 and activity.session.sim.tick == tick_before + 1)
	check("first accepted resumed scene tick disarms", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED \
		and activity.session.fault_reason.is_empty())
	var tape: PackedFloat64Array = activity.session.tape()
	check("accepted tape records the substituted OFF frame", tape.size() >= FC.INPUT_SIZE \
		and tape[tape.size() - FC.INPUT_SIZE + FC.IN_ARM] == 0.0)
	root.remove_child(activity)
	activity.free()
	print("scene pause repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
