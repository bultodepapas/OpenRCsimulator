# Audit observation probe for pinned cfb5acd5; see the README and checked-run evidence.
# Passing checks reproduce the baseline refusal-to-default mismatch; they are not a desired regression test.
extends SceneTree

const Service := preload("res://input/controller_service.gd")
const Activity := preload("res://vehicles/multirotor/multirotor_scene.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const DT := 1.0 / 240.0

var checks := 0
var failures := 0
var keys := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, arm = false, mode = false}


func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition: failures += 1


func _initialize() -> void:
	_run.call_deferred()


func observed_pad() -> Dictionary:
	return {"id": 7, "guid": "audit-synthetic-pad", "name": "Synthetic pad", "raw_name": "Synthetic pad",
		"known": true, "kind": "gamepad", "vendor_id": 700, "product_id": 7, "serial_number": "audit-pad-serial"}


func new_service(path: String) -> Service:
	var service := Service.new()
	service.store = Service.Store.new(path, path + ".legacy")
	service.enumerate_devices = func() -> Array: return [observed_pad()]
	service.refresh() # Same registry/default-selection and profile-resolver paths as Home.
	return service


func _run() -> void:
	# Unique files only; do not replace the player's actual controller store.
	var prefix := "user://quad_audit_corrupt_%d_%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	var cfg := ConfigFile.new()
	cfg.set_value(Service.Store.STORAGE_SECTION, "schema_version", 999)
	cfg.set_value(Service.Store.STORAGE_SECTION, "profiles", [])
	check("isolated unsupported store fixture writes", cfg.save(prefix) == OK)
	var service := new_service(prefix)
	check("store rejects unsupported version", not service.store.load_all().ok)
	check("known gamepad is nevertheless selected for flight", service.registry.selected_device_id("flight") == 7)
	check("service correctly refuses to resolve profile", service.profile_for_device(7).is_empty())

	# Create the real quad scene with its documented resolver/confirmation seams. The confirmation below
	# stands in for a current, focused selected SDL gamepad; it does not qualify physical hardware.
	var activity := Activity.new()
	activity.enable_world = false
	activity.enable_audio = false
	activity.departure_managed = true
	activity.race_track = ""
	activity.controller_registry = service.registry
	activity.controller_profile_for = Callable(service, "profile_for_device")
	activity.controller_confirmation = func(id: int, expected_id: int, generation: int) -> bool:
		return id == expected_id and generation == service.registry.connection_generation(id) \
			and service.registry.selected_device_id("flight") == id
	activity.input.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	activity.input.read_button = func(_id: int, _button: int) -> bool: return false
	activity.input.read_keys = func() -> Dictionary: return keys.duplicate()
	root.add_child(activity)
	activity.set_physics_process(false)
	check("quad scene prepared", activity.session != null and activity.session.prepared)
	if activity.session != null and activity.session.prepared:
		check("quad replaced refusal with built-in gamepad profile", activity.input.radio.connected \
			and activity.input.radio.profile_source == "gamepad" and activity.input.radio.is_gamepad())
		var sample: Dictionary = activity.input.sample(DT, false)
		check("quad treats fallback as ready under verified poll", sample.ready)
		activity.handle_action("resume")
		check("scene resumes with refused profile", not activity.session.paused)
		activity._physics_process(DT) # ready OFF
		keys.arm = true
		activity._physics_process(DT) # ON at low throttle
		check("fallback mapping can arm controlled session", activity.session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED)
	root.remove_child(activity)
	activity.free()
	service.free()

	var healthy := new_service(prefix + ".healthy")
	var healthy_profile: Dictionary = healthy.profile_for_device(7)
	check("healthy genuinely empty store resolves an explicit default", not healthy_profile.is_empty() \
		and healthy_profile.get("kind", "") == "gamepad" and healthy_profile.get("preset", "") == "mode2")
	healthy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix))
	print("quad store-refusal repro: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
