## FW-35c: shared policy, real flight routes, threshold crossings and lifecycle.
extends SceneTree

const State = preload("res://render/world/aircraft_light_state.gd")
const World = preload("res://render/world/world.gd")
const Config = preload("res://environment/time_of_day_config.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Home = preload("res://ui/home_scene.gd")
const Helicopter = preload("res://helicopter_main.gd")

class TestFlight extends "res://main.gd":
	func _user_args() -> Dictionary:
		return {"soundscape": "off", "crash-effects": "off", "smoke": "off"}

var checks := 0
var failures := 0
var captures := ""

func check(label: String, valid: bool) -> void:
	checks += 1
	if not valid:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	_run.call_deferred()

func _config(seconds: int) -> Dictionary:
	var config := Config.defaults()
	config.mode = "astronomical"
	config.date = "2026-06-21"
	config.latitude_deg = 40.0
	config.longitude_deg = 0.0
	config.local_seconds = seconds
	return config

func _policy() -> void:
	var state := State.new()
	state.update(62999.99, 0.0)
	check("before 17:30 stays off with a high sun", state.active_mode == "off")
	check("17:30 changes output", state.update(63000.0, 0.0) and state.active_mode == "all")
	check("unchanged time/output needs no writes", not state.update(63001.0, 0.0))
	state.set_mode("off")
	state.update(72000.0, 1.0)
	check("explicit OFF beats evening and darkness", state.active_mode == "off" and state.gain == 0.0)
	state.set_mode("all")
	state.update(43200.0, 0.0)
	check("explicit ON survives daylight", state.active_mode == "all" and state.gain == 1.0)
	state.set_mode("nav")
	state.update(80000.0, 1.0)
	check("NAV also persists", state.active_mode == "nav")
	check("invalid selection is atomic", not state.set_mode("bad") and state.selection == "nav")
	state.reset()
	state.update(18000.0, 1.0)
	check("reset resumes existing dawn ON", state.selection == "auto" and state.active_mode == "all")
	state.update(36000.0, 0.0)
	check("morning returns to existing daylight OFF", state.active_mode == "off")
	state.update(20000.0, 0.5)
	check("helicopter dawn fade is preserved", state.gain == 0.5)
	state.update(86400.0 + 63000.0, 0.0)
	check("civil day rollover is normalized", state.active_mode == "all")
	state.update(NAN, NAN)
	check("legacy/invalid time never invents an evening", state.active_mode == "off")
	check("configurable activation accepts 18:00", state.configure_evening(64800))
	state.update(63000.0, 0.0)
	check("custom activation waits", state.active_mode == "off")
	state.update(64800.0, 0.0)
	check("custom activation switches exactly", state.active_mode == "all")
	check("invalid threshold preserves accepted config", not state.configure_evening(86400) and state.evening_on_seconds == 64800)
	var begin := Time.get_ticks_usec()
	for i in 10000: state.update(63000.0, 0.0)
	print("FW-35c unchanged policy sample mean us: %.3f" % ((Time.get_ticks_usec() - begin) / 10000.0))
	var host := Node3D.new()
	var kit := Node3D.new()
	host.add_child(kit)
	var lamp := SpotLight3D.new()
	var glow := MeshInstance3D.new()
	kit.add_child(lamp)
	kit.add_child(glow)
	check("authored light and glow references bind", World.AircraftLights.bind_groups(kit, {landing = [lamp, glow]}, ["landing"]))
	World.AircraftLights.set_mode(kit, "all")
	check("lamp and glow switch together", lamp.visible and glow.visible)
	World.AircraftLights.set_mode(kit, "off")
	check("OFF hides both node contributions", not lamp.visible and not glow.visible)
	check("duplicate bindings are rejected", not World.AircraftLights.bind_groups(kit, {landing = [lamp, lamp]}))
	check("unsupported groups are accepted as dark", World.AircraftLights.bind_groups(kit, {landing = [lamp, glow]}, ["navigation"]))
	World.AircraftLights.set_mode(kit, "all")
	check("unsupported equipment stays off", not lamp.visible and not glow.visible)
	host.free()
	var model := Node3D.new()
	var lens := MeshInstance3D.new()
	var source := StandardMaterial3D.new()
	source.resource_name = "light_red"
	source.emission_enabled = true
	source.emission_energy_multiplier = 2.7
	var mesh := BoxMesh.new()
	mesh.material = source
	lens.mesh = mesh
	model.add_child(lens)
	var emission := World.AircraftLights.prepare_emission(model)
	World.AircraftLights.set_emission_mode(emission, "off")
	var private_material := lens.get_active_material(0) as BaseMaterial3D
	check("native emission OFF preserves reflective lens and source", lens.visible and private_material != source and not private_material.emission_enabled and source.emission_enabled)
	World.AircraftLights.set_emission_mode(emission, "nav")
	check("NAV restores the native lens emission energy", private_material.emission_enabled and is_equal_approx(private_material.emission_energy_multiplier, 2.7))
	check("native emission preparation is stable", World.AircraftLights.prepare_emission(model).materials[0].material == private_material)
	model.free()

func _flight(id: String, config: Dictionary) -> TestFlight:
	var flight := TestFlight.new()
	flight.interactive_start = true
	flight.aircraft_id = id
	flight.lighting_config = config
	root.add_child(flight)
	flight.set_process(false)
	flight.session.physics_enabled = false
	flight.session.input_enabled = false
	flight.session.sim.set_paused(true)
	check(id + " starts without an error", flight.startup_error.is_empty())
	return flight

func _edit(flight: TestFlight, seconds: int) -> void:
	check("paused clock edit accepted", flight.apply_lighting_config(_config(seconds)).ok)

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-aircraft-lights="):
			captures = arg.trim_prefix("--capture-aircraft-lights=")
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	_policy()
	for id: String in Catalog.airplane_visual_families():
		var flight := _flight(id, _config(62999))
		check(id + " daytime has no light kit", flight._night_kit == null)
		var emission: Dictionary = World.AircraftLights.prepare_emission(flight._airplane.root)
		check(id + " native daytime emission is OFF", emission.materials.all(func(binding: Dictionary) -> bool: return not binding.material.emission_enabled))
		_edit(flight, 63000)
		var kit: Node3D = flight._night_kit
		check(id + " starts lights at 17:30 despite a high sun", kit != null and kit.visible and World.aircraft_sun_elevation(flight._lighting) > 6.0)
		check(id + " native evening emission is ON", emission.materials.all(func(binding: Dictionary) -> bool: return binding.material.emission_enabled))
		if id == "turbo-lumber-evolution": check("Timber binds both imported navigation materials", emission.materials.size() == 2)
		check(id + " kit is attached only once", World.AircraftLights.attach(flight._airplane.root) == kit)
		flight.controller_action("lights_cycle")
		check(id + " controller selects NAV", flight._aircraft_lights.selection == "nav" and not kit.get_node("landing_light").visible)
		var event := InputEventKey.new()
		event.physical_keycode = KEY_L
		event.pressed = true
		flight._unhandled_input(event)
		check(id + " keyboard selects OFF", flight._aircraft_lights.selection == "off" and not kit.visible)
		check(id + " native emission follows manual OFF", emission.materials.all(func(binding: Dictionary) -> bool: return not binding.material.emission_enabled))
		event.echo = true
		flight._unhandled_input(event)
		check(id + " keyboard repeat does not cycle", flight._aircraft_lights.selection == "off")
		flight._update_hud(false, false)
		check(id + " minimal HUD reflects manual OFF", flight._hud.text.contains("Night lights: off"))
		_edit(flight, 75600)
		check(id + " manual OFF survives later night", not kit.visible)
		flight.set_aircraft_lights("all")
		_edit(flight, 43200)
		check(id + " manual ON survives noon", kit.visible and flight._aircraft_lights.selection == "all")
		var children := kit.get_child_count()
		for i in 30: flight._update_aircraft_lights()
		check(id + " repeated updates keep one bounded kit", kit.get_child_count() == children)
		flight.session.reset()
		check(id + " reset resumes daylight automatic OFF", flight._aircraft_lights.selection == "auto" and not kit.visible)
		flight.session.sim.set_paused(true)
		_edit(flight, 63000)
		flight.set_aircraft_lights("off")
		flight.session.reset()
		check(id + " reset after threshold resumes automatic ON", flight._aircraft_lights.selection == "auto" and kit.visible)
		flight._update_hud(false, false)
		check(id + " minimal HUD reflects automatic reset", flight._hud.text.contains("Night lights: all") and flight._hud.text.contains("Night lights: auto"))
		flight.session.sim.set_paused(true)
		_edit(flight, 63000)
		await _capture(flight, id + "-on")
		flight.set_aircraft_lights("off")
		await _capture(flight, id + "-off")
		flight.free()
	# A fresh scene starts after the threshold with no leaked manual selection.
	var fresh := _flight(Catalog.DEFAULT_ID, _config(63000))
	check("fresh flight after 17:30 initializes ON", fresh._night_kit != null and fresh._night_kit.visible and fresh._aircraft_lights.selection == "auto")
	fresh.set_aircraft_lights("off")
	check("successful aircraft data reload", fresh.session.reload().begins_with("aircraft reloaded:"))
	check("data reload resets manual selection with the session", fresh._aircraft_lights.selection == "auto" and fresh._night_kit.visible)
	fresh.free()
	await _helicopter()
	await _flow()
	var home := Home.new(Catalog.DEFAULT_ID, "res://data/fields/default.json", _config(63000))
	root.add_child(home)
	check("Home uses fixed civil-time default", home.airplane.root.get_node_or_null("NightKit") != null)
	home.show_aircraft("gp-extra-300s-60")
	check("aircraft change inherits automatic evening", home.airplane.root.get_node_or_null("NightKit") != null)
	home.free()
	await process_frame
	await process_frame
	if not captures.is_empty():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	print("FW-35c aircraft light control: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _helicopter() -> void:
	var flight := Helicopter.new()
	flight.interactive_start = true
	flight.lighting_config = _config(63000)
	flight._injected_user_args = PackedStringArray()
	root.add_child(flight)
	flight.set_process(false)
	flight.session.physics_enabled = false
	flight.session.sim.set_paused(true)
	flight._present(0.0)
	var kit: Node3D = flight._night_kit
	check("helicopter after 17:30 initializes ON with a high sun", flight.startup_error.is_empty() and kit.visible and kit.active_mode == "all")
	flight._cycle_night_lights() # AUTO -> ALL
	flight._cycle_night_lights() # ALL -> NAV
	flight._cycle_night_lights() # NAV -> OFF
	flight._present(0.0)
	check("helicopter OFF hides body, rotor and lamps", not kit.visible and not kit._landing.visible and not kit._frame_fill.visible)
	flight.session.reset()
	flight._present(0.0)
	check("helicopter reset clears override", kit.mode == "auto" and kit.active_mode == "all")
	if not captures.is_empty():
		flight._rig.set_view("closeup")
		flight._present(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		check("capture helicopter", root.get_texture().get_image().save_png(captures.path_join("helicopter-on.png")) == OK)
	flight.free()

func _flow() -> void:
	var values := {"OPENRC_TIME": "17:29", "OPENRC_TIME_SCALE": "20", "OPENRC_LAT": "40", "OPENRC_LON": "0", "OPENRC_UTC_OFFSET": "0", "OPENRC_DATE": "2026-06-21"}
	var saved := {}
	for key: String in values:
		saved[key] = [OS.has_environment(key), OS.get_environment(key)]
		OS.set_environment(key, values[key])
	var flight := _flight(Catalog.DEFAULT_ID, Config.defaults())
	flight.session.sim.set_paused(false)
	for i in 719: flight.session.sim.step()
	flight._process(0.0)
	check("flow before 17:30 stays OFF", flight._night_kit == null and World.aircraft_local_seconds({}, flight.session.sim.time()) < 63000.0)
	if not captures.is_empty(): await RenderingServer.frame_post_draw
	flight.session.sim.step()
	flight._process(0.0)
	check("flow crossing 17:30 turns ON", flight._night_kit != null and flight._night_kit.visible)
	if not captures.is_empty(): await RenderingServer.frame_post_draw
	flight.set_aircraft_lights("off")
	for i in 240: flight.session.sim.step()
	flight._process(0.0)
	check("flow preserves manual OFF", not flight._night_kit.visible)
	if not captures.is_empty(): await RenderingServer.frame_post_draw
	flight.session.reset()
	flight.set_aircraft_lights("off")
	for i in 720: flight.session.sim.step()
	flight._process(0.0)
	check("manual OFF before crossing remains OFF after it", not flight._night_kit.visible)
	if not captures.is_empty(): await RenderingServer.frame_post_draw
	flight.session.reset()
	flight.set_aircraft_lights("all")
	for i in 720: flight.session.sim.step()
	flight._process(0.0)
	check("manual ON before crossing remains ON after it", flight._night_kit.visible and flight._aircraft_lights.selection == "all")
	if not captures.is_empty(): await RenderingServer.frame_post_draw
	flight.free()
	for key: String in saved:
		if saved[key][0]: OS.set_environment(key, saved[key][1])
		else: OS.unset_environment(key)

func _capture(flight: TestFlight, label: String) -> void:
	if captures.is_empty(): return
	flight._rig.set_view("closeup")
	flight._process(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	check("capture " + label, root.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK)
