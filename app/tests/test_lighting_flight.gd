extends SceneTree

const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const TimeConfig := preload("res://environment/time_of_day_config.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")

class TestFlight extends "res://main.gd":
	func _user_args() -> Dictionary:
		return {"soundscape": "off", "crash-effects": "off", "smoke": "off"}

class CountingRig extends "res://render/lighting/aircraft_lighting_rig_3d.gd":
	var mode_calls := 0
	func set_mode(mode: String, gain := 1.0) -> void:
		mode_calls += 1
		super.set_mode(mode, gain)

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
	profile.lighting = Presentation.LightingProfile.preset("festival")
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
		# First sampling a show cue during pause must not create a new burst.
		flight.session.sim.tick = roundi(8.0 / flight.session.sim.dt()) # Festival burst cue
		rig.reset()
		flight._process(0.01)
		var effects := flight.find_children("*", "MultiMeshInstance3D", true, false)
		var show_particles := 0
		var show_pools := 0
		for effect: Node in effects:
			if effect.get_parent().name == "AircraftLightingWorldVfx":
				show_pools += 1
				show_particles += (effect as MultiMeshInstance3D).multimesh.visible_instance_count
		_check("paused first cue sample does not emit a burst", show_pools == 2 and show_particles == 0)
		flight._on_resetting()
		_check("session reset resumes AUTO and retains preset", flight._aircraft_lights.selection == "auto" and rig.budget_info().selection == "preset")
		_verify_mode_dispatch(flight)
	flight.free()
	await process_frame
	_finish()


func _verify_mode_dispatch(flight: TestFlight) -> void:
	# Replace the flight's rig with a real instrumented rig and an imported lens.
	var original: Node = flight._rgb_lighting
	original.dispose()
	original.free()
	var aircraft: Node3D = flight._airplane.root
	aircraft.remove_meta("aircraft_light_emission")
	var lens := MeshInstance3D.new()
	lens.mesh = BoxMesh.new()
	var source := StandardMaterial3D.new()
	source.resource_name = "light_red"
	source.emission_enabled = true
	source.emission_energy_multiplier = 2.0
	lens.material_override = source
	aircraft.add_child(lens)
	var profile: Dictionary = Presentation.LightingProfile.preset("classic_rc")
	for zone: Dictionary in profile.zones:
		if zone.id == "nav_left":
			zone.reactive = {"source": "throttle", "gain": 1.0}
	var rig := CountingRig.new()
	flight.add_child(rig)
	var configured := rig.configure(aircraft, profile)
	_check("instrumented flight rig configures", configured.ok, str(configured.get("errors", [])))
	if not configured.ok:
		rig.free()
		flight._rgb_lighting = null
		return
	flight._rgb_lighting = rig
	flight._aircraft_lights.set_mode("all")
	var before := rig.mode_calls
	flight._update_aircraft_lights(0.5, false)
	_check("replacement rig receives the current flight mode", rig.mode_calls == before + 1)
	var kit := rig.get_kit()
	var material := lens.get_active_material(0) as BaseMaterial3D
	var telemetry := {"throttle": 1.0, "exposure": 1.0, "effects_allowed": true}
	rig.advance(0.5, telemetry)
	var energized := material.emission_energy_multiplier
	before = rig.mode_calls
	for i in 30:
		flight._update_aircraft_lights(0.5, false)
	print("lighting mode dispatch: unchanged_updates=30 set_mode_calls=%d" % (rig.mode_calls - before))
	_check("unchanged frame updates skip mode and preserve reactive emission",
		rig.mode_calls == before and is_equal_approx(energized, 4.0) \
		and is_equal_approx(material.emission_energy_multiplier, energized))
	rig.advance(0.5, {"throttle": 0.0, "exposure": 1.0, "effects_allowed": true})
	_check("telemetry still advances while the mode is unchanged", is_equal_approx(material.emission_energy_multiplier, 2.0))
	rig.advance(0.5, telemetry)
	_check("reactive emission returns with throttle", is_equal_approx(material.emission_energy_multiplier, 4.0))
	before = rig.mode_calls
	for i in 5:
		flight._process(0.01)
	_check("flight frame loop skips an unchanged mode", rig.mode_calls == before)
	# Explicit rig calls remain forced reconciliation operations.
	rig.set_mode("all", 1.0)
	_check("direct set_mode retains synchronous reconciliation", is_equal_approx(material.emission_energy_multiplier, 2.0))
	rig.advance(0.5, telemetry)

	before = rig.mode_calls
	flight.set_aircraft_lights("off")
	var off := not kit.visible
	flight.set_aircraft_lights("nav")
	var nav := kit.visible and (kit.get_node("nav_left") as Node3D).visible \
		and not (kit.get_node("landing_lamp") as Node3D).visible
	flight.set_aircraft_lights("all")
	_check("explicit OFF, NAV and ALL remain synchronous", off and nav and kit.visible and rig.mode_calls == before + 3)

	before = rig.mode_calls
	flight._on_resetting()
	_check("reset forces reconciliation even when AUTO remains ALL",
		flight._aircraft_lights.selection == "auto" and kit.visible and rig.mode_calls == before + 1)

	# Keep a high sun so this exercises the civil 17:30 threshold itself.
	var saved_seconds: float = flight.lighting_config.local_seconds
	var saved_elevation: float = flight._lighting.solar.elevation_deg
	flight._lighting.solar.elevation_deg = 30.0
	flight.lighting_config.local_seconds = 62999.0
	before = rig.mode_calls
	flight._process(0.01)
	var day_off := not kit.visible and flight._aircraft_lights.gain == 0.0 and rig.mode_calls == before + 1
	flight._process(0.01)
	flight.lighting_config.local_seconds = 63000.0
	flight._process(0.01)
	var evening_on := kit.visible and flight._aircraft_lights.gain == 1.0 and rig.mode_calls == before + 2
	flight._process(0.01)
	_check("AUTO frame path changes once at the evening threshold", day_off and evening_on and rig.mode_calls == before + 2)
	flight.lighting_config.local_seconds = saved_seconds
	flight._lighting.solar.elevation_deg = saved_elevation

	rig.set_mode("off", 0.0)
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5)
	_check("explicit update reconciles an external rig mode change", rig.mode_calls == before + 1 and kit.visible)
	kit.visible = false
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5)
	_check("explicit update reconciles an externally hidden kit", rig.mode_calls == before + 1 and kit.visible)
	before = rig.mode_calls
	aircraft.visible = false
	flight._update_aircraft_lights(0.5, false)
	aircraft.visible = true
	flight._update_aircraft_lights(0.5, false)
	_check("hiding and revealing the aircraft preserves kit mode without extra mode work", kit.visible and rig.mode_calls == before)

	var lamp := kit.get_node("landing_lamp") as Node3D
	lamp.set_meta("gear_gated", true)
	kit.set_meta("dynamic", true)
	AircraftLights.update_dynamic(kit, aircraft, 0.0)
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5, false)
	rig.advance(0.5, telemetry)
	var gated := not lamp.visible
	AircraftLights.update_dynamic(kit, aircraft, 1.0)
	flight._update_aircraft_lights(0.5, false)
	rig.advance(0.5, telemetry)
	_check("gear gates still reconcile on advance", gated and lamp.visible and rig.mode_calls == before)

	flight.set_aircraft_lights("nav")
	var added := MeshInstance3D.new()
	kit.add_child(added)
	var groups: Dictionary = kit.get_meta("light_bindings")
	(groups.orientation as Array).append(added)
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5)
	_check("explicit update reconciles an added bound kit child in NAV", rig.mode_calls == before + 1 and not added.visible)
	(groups.orientation as Array).erase(added)
	kit.remove_child(added)
	added.free()
	flight.set_aircraft_lights("all")

	var changed_profile := profile.duplicate(true)
	for zone: Dictionary in changed_profile.zones:
		if zone.id == "nav_left": zone.brightness = 0.5
	configured = rig.configure(aircraft, changed_profile)
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5)
	rig.advance(0.5, telemetry)
	_check("explicit update reconciles a reconfigured profile on the same rig", configured.ok \
		and rig.mode_calls == before + 1 and is_equal_approx(material.emission_energy_multiplier, 2.0))

	var disabled := Presentation.LightingProfile.defaults()
	disabled.selection = "disabled"
	configured = rig.configure(aircraft, disabled)
	before = rig.mode_calls
	flight._update_aircraft_lights(0.5)
	flight._update_aircraft_lights(0.5, false)
	_check("disabled profile applies once even when flight mode is ALL", configured.ok \
		and rig.mode_calls == before + 1 and not kit.visible)

	var replacement := StandardMaterial3D.new()
	lens.material_override = replacement
	flight._update_aircraft_lights(0.5, false)
	_check("external material replacement remains untouched", lens.material_override == replacement)


func _check(label: String, success: bool, detail: String = "") -> void:
	_checks += 1
	if not success:
		_failures += 1
		printerr("FAIL ", label, " ", detail)

func _finish() -> void:
	print("Lighting flight: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
