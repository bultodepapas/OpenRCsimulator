extends SceneTree

const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const TimeConfig := preload("res://environment/time_of_day_config.gd")

class TestFlight extends "res://main.gd":
	func _user_args() -> Dictionary:
		return {"soundscape": "off", "crash-effects": "off", "smoke": "off"}

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var described := Customization.describe(Catalog.DEFAULT_ID)
	_check("lighting flight companion resolves", described.get("ok", false), str(described.get("errors", [])))
	if not described.get("ok", false):
		_finish()
		return
	var profile := Presentation.defaults(described.bindings)
	profile.lighting = Presentation.LightingProfile.preset("neon_rgb")
	var frozen := Trial.freeze({"base_id": Catalog.DEFAULT_ID,
		"base_bytes": FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data),
		"recipe": {}, "presentation_profile": profile})
	_check("lighting profile freezes for real flight", frozen.get("ok", false), str(frozen.get("errors", [])))
	if not frozen.get("ok", false):
		_finish()
		return
	var flight := TestFlight.new()
	flight.interactive_start = true
	flight.aircraft_id = Catalog.DEFAULT_ID
	flight.workshop_trial = frozen
	var config := TimeConfig.defaults()
	config.mode = "astronomical"
	config.local_seconds = 72000
	flight.lighting_config = config
	root.add_child(flight)
	flight.set_process(false)
	_check("real RGB flight starts", flight.startup_error.is_empty(), flight.startup_error)
	if not flight.startup_error.is_empty():
		flight.free()
		_finish()
		return
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.session.sim.set_paused(true)
	var rig: Node = flight.get("_rgb_lighting")
	_check("flight installs one owned RGB facade", is_instance_valid(rig))
	if is_instance_valid(rig):
		var kit: Node3D = rig.get_kit()
		_check("flight reuses the one NightKit", is_instance_valid(kit) and kit == flight._airplane.root.get_node_or_null("NightKit"))
		flight.set_aircraft_lights("all")
		flight._process(0.01)
		var strip := kit.get_node("strip_left") as MeshInstance3D
		var material := strip.get_active_material(0) as ShaderMaterial
		var phase: Variant = material.get_shader_parameter("pattern_phase")
		flight._process(0.2)
		_check("paused flight freezes phase despite render delta", phase == material.get_shader_parameter("pattern_phase"))
		flight.set_aircraft_lights("off")
		_check("existing OFF control hides RGB strip", not strip.visible)
		flight.set_aircraft_lights("nav")
		_check("NAV keeps navigation and suppresses RGB strip", not strip.visible and kit.get_node("nav_left").visible)
		flight.set_aircraft_lights("all")
		_check("ALL restores the selected RGB preset", strip.visible)
		flight._on_resetting()
		_check("session reset resumes AUTO and retains preset", flight._aircraft_lights.selection == "auto" and rig.budget_info().selection == "preset")
	flight.free()
	await process_frame
	_finish()

func _check(label: String, success: bool, detail: String = "") -> void:
	_checks += 1
	if not success:
		_failures += 1
		printerr("FAIL ", label, " ", detail)

func _finish() -> void:
	print("Lighting flight: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
