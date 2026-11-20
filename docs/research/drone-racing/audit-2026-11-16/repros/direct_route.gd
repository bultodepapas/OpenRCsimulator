# Audit observation probe for pinned cfb5acd5; see the README and checked-run evidence.
# Passing checks reproduce structural baseline behavior. Synthetic ID is an InputMap fixture, not a real pad.
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Store := preload("res://input/controller_profile_store.gd")

var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	print("%s %s" % ["ok  " if condition else "FAIL", label])
	if not condition: failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	UiInput.set_gamepad(7) # Installs the device-scoped native menu mappings without requiring a physical device.
	check("fixture starts with gamepad UI mappings", not UiInput.joypad_ui_events().is_empty())
	var app := AppRoot.new()
	app.user_args = PackedStringArray(["--multirotor=openrc-fpv5-x1"])
	root.add_child(app)
	await process_frame
	check("direct quad activity was created", app.ground_vehicle != null)
	check("direct route did not create the controller service", app.controllers == null)
	check("direct launch removed the gamepad UI mappings without restoring them", UiInput.joypad_ui_events().is_empty())
	if app.ground_vehicle != null:
		var activity: Node = app.ground_vehicle
		check("direct quad has no service profile resolver", not activity.controller_profile_for.is_valid())
		check("fallback points to legacy, not V2 controller storage", activity.input.profiles_path == Store.LEGACY_PATH \
			and activity.input.profiles_path != Store.DEFAULT_PATH)
	root.remove_child(app)
	app.free()
	UiInput.isolate_joypads()
	print("quad direct route probe: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
