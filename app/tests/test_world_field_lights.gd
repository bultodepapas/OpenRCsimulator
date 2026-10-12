# FW-31…34 and FW-35: field lights and the aircraft night kit. The committed lights file validates; malformed files
# are refused; floods become shadowless SpotLight3Ds aimed at their targets with energy = cd / conversion; the kit
# puts red left / green right at the wing tips; nothing is built by day; legacy (no time) builds none of it.
# Run: godot --headless --path . --script res://tests/test_world_field_lights.gd
extends SceneTree

const FieldLights := preload("res://render/world/field_lights.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Frames := preload("res://render/frames.gd")
const Exposure := preload("res://render/world/exposure.gd")
const LandscapeOptions := preload("res://render/landscape_upgrade/options.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _mutant(change: Callable) -> Dictionary:
	var f := FileAccess.open(FieldLights.DEFAULT_PATH, FileAccess.READ)
	var root: Dictionary = JSON.parse_string(f.get_as_text())
	change.call(root)
	return FieldLights.validate(root)


func _initialize() -> void:
	var loaded := FieldLights.load_from()
	_check("committed lights file validates", loaded.ok, "; ".join(loaded.errors))
	var refused := {
		"wrong format": func(r: Dictionary) -> void: r.format = "openrc-field-lights v0",
		"unknown type": func(r: Dictionary) -> void: r.fixtures[0].type = "laser",
		"missing source": func(r: Dictionary) -> void: r.fixtures[0].intensity.erase("source"),
		"wrong unit": func(r: Dictionary) -> void: r.fixtures[0].intensity.unit = "lm",
		"negative intensity": func(r: Dictionary) -> void: r.fixtures[0].intensity.value = -5,
		"unknown key": func(r: Dictionary) -> void: r.fixtures[0].colour = {value = 1, unit = "x", kind = "estimated", source = "x"},
		"duplicate id": func(r: Dictionary) -> void: r.fixtures[1].id = r.fixtures[0].id,
		"bad points": func(r: Dictionary) -> void: r.fixtures[3].points.value = [[1, 2, 3]],
		"bad colour": func(r: Dictionary) -> void: r.fixtures[4].color.value = "greenish",
		"too wide beam": func(r: Dictionary) -> void: r.fixtures[0].beam_half_angle.value = 85,
		"too many floods": func(r: Dictionary) -> void:
			for i in 3:
				var copy: Dictionary = r.fixtures[0].duplicate(true)
				copy.id = "extra_%d" % i
				r.fixtures.append(copy),
	}
	for name: String in refused:
		var result := _mutant(refused[name])
		_check("refused: " + name, not result.ok, "accepted")

	var lights := FieldLights.build(loaded.lights)
	var spots := lights.find_children("*", "SpotLight3D", true, false)
	_check("three floods, no shadows", spots.size() == 3 and lights.get_meta("spots") == 3 and spots.all(func(s: SpotLight3D) -> bool: return not s.shadow_enabled))
	var west: SpotLight3D = lights.get_node("flood_west")
	_check("flood energy = 12,000 cd / 1e5 lux", is_equal_approx(west.light_energy, 0.12), str(west.light_energy))
	var aim := (Frames.ned_to_render([18.0, -12.0, 0.0]) - west.position).normalized()
	_check("flood aimed at its target", (-west.transform.basis.z).normalized().distance_to(aim) < 1e-4, str(-west.transform.basis.z))
	_check("5,000 K is near-white, slightly warm of D65", west.light_color.r == 1.0 and west.light_color.b > 0.75 and west.light_color.b < 0.9, str(west.light_color))
	_check("stake rows are one MultiMesh each", (lights.get_node("runway_edge_stakes") as MultiMeshInstance3D).multimesh.instance_count == 12)
	_check("lamp radiance: 5 cd from 5 cm ≈ 0.08", absf(FieldLights.lamp_radiance(5.0, 0.05, 100000.0) - 0.08) < 1e-9)
	lights.free()

	# Night kit on the Stik: red at −x (left), green at +x (right), landing light forward.
	var airplane: Dictionary = AirplaneBuilder.build()
	var stik_half := AircraftLights.span_half(AircraftLights.vertices(airplane.root)) # before the kit exists
	var kit := AircraftLights.attach(airplane.root)
	var left: Node3D = kit.get_node("nav_left")
	var right: Node3D = kit.get_node("nav_right")
	_check("nav lights at the wing tips", left.position.x < -stik_half and right.position.x > stik_half
		and absf(right.position.x - stik_half) < 0.05)
	_check("left red, right green", ((left as MeshInstance3D).mesh.material as ShaderMaterial).get_shader_parameter("light_color").r > 0.9
		and ((right as MeshInstance3D).mesh.material as ShaderMaterial).get_shader_parameter("light_color").g > 0.9)
	var landing: SpotLight3D = kit.get_node("landing_light")
	_check("landing light points forward (−z) and a little down", (-landing.transform.basis.z).z < -0.9 and (-landing.transform.basis.z).y < 0.0)
	_check("kit names never collide with the model's hinges", kit.find_children("*_hinge", "", true, false).is_empty())
	airplane.root.free()

	# FW-62: under-wing strips on every catalog aircraft, traced on its own lowest vertices.
	for id: String in [AirplaneBuilder.STIK_ID, AirplaneBuilder.EXTRA_ID, AirplaneBuilder.AVANTI_ID, AirplaneBuilder.P51_ID]:
		var plane: Dictionary = AirplaneBuilder.build(id)
		var pts := AircraftLights.vertices(plane.root)
		var half := AircraftLights.span_half(pts)
		var lines := AircraftLights.underwing_lines(AircraftLights.triangles(plane.root), half)
		var ok := true
		var detail := ""
		for key: String in ["left", "right"]:
			var line: PackedVector3Array = lines[key]
			if line.size() != AircraftLights.STRIP_STATIONS:
				ok = false
				detail = "%s %s: %d stations" % [id, key, line.size()]
			for k in range(1, line.size()):
				if absf(line[k].y - line[k - 1].y) > 0.06 or absf(line[k].z - line[k - 1].z) > 0.15:
					ok = false
					detail = "%s %s: jump %s -> %s" % [id, key, line[k - 1], line[k]]
		var dressed := AircraftLights.attach(plane.root)
		ok = ok and dressed.get_node_or_null("strip_left") != null and dressed.get_node_or_null("strip_right") != null
		_check("%s: smooth under-wing strips on both sides, every station" % id, ok, detail)
		var tip_ok: bool = (dressed.get_node("nav_right") as Node3D).position.x > half and (dressed.get_node("nav_left") as Node3D).position.x < -half
		_check("%s: nav lights at the real wing tips (span %.2f m)" % [id, 2.0 * half], tip_ok)
		plane.root.free()

	# Light on a point (FW-23 adaptation): on the flood's aim line it is I / conversion / d² × window; nothing outside.
	var lights_data: Dictionary = loaded.lights
	var flood: Dictionary = lights_data.fixtures[0]
	var head := Frames.ned_to_render([flood.north, flood.east, -flood.height])
	var aim_point := Frames.ned_to_render([flood.aim_north, flood.aim_east, 0.0])
	var on_axis := head + (aim_point - head).normalized() * 20.0
	var expected := float(flood.intensity) / float(lights_data.conversion) / 400.0 * pow(1.0 - pow(20.0 / float(flood.range), 4.0), 2.0)
	_check("flood light on its axis at 20 m", absf(FieldLights.illuminance_point(lights_data, on_axis) - expected) < expected * 1e-4,
		"%f vs %f" % [FieldLights.illuminance_point(lights_data, on_axis), expected])
	_check("no flood light 200 m up", FieldLights.illuminance_point(lights_data, Vector3(0.0, 200.0, 0.0)) == 0.0)

	# Eye adaptation: snaps on the first call, falls fast toward light, rises slowly toward dark, holds while paused.
	var field_data: Dictionary = FieldLoader.load_from().field
	var adapt_holder := Node3D.new()
	var built := World.build(adapt_holder, field_data, Callable(), Conditions.resolve(PackedStringArray(["--time_of_day=night"])))
	var env: Environment = built.environment
	var dark := Vector3(0.0, 120.0, -300.0)
	var lit := on_axis
	_check("a lit target needs less exposure than a dark one", World.view_exposure(lit) < World.view_exposure(dark) * 0.5,
		"%f vs %f" % [World.view_exposure(lit), World.view_exposure(dark)])
	var first := World.adapt(env, dark, 10.0)
	_check("first call snaps to the dark goal", is_equal_approx(first, World.view_exposure(dark)))
	var held := World.adapt(env, dark, 10.0)
	_check("paused clock holds the exposure", is_equal_approx(held, first))
	var after_light := World.adapt(env, lit, 10.5)
	var light_goal := World.view_exposure(lit)
	var k_light := exp(-World.ADAPT_TO_LIGHT_PER_S * 0.5)
	_check("toward light: log-exponential at ADAPT_TO_LIGHT_PER_S",
		absf(log(after_light) - (log(light_goal) + (log(first) - log(light_goal)) * k_light)) < 0.021, "%f" % after_light)
	World.adapt(env, lit, 30.0) # > MAX_STEP: snaps to the lit goal
	var back := World.adapt(env, dark, 31.0)
	var k_dark := exp(-World.ADAPT_TO_DARK_PER_S * 1.0)
	_check("toward dark: slower, at ADAPT_TO_DARK_PER_S",
		absf(log(back) - (log(World.view_exposure(dark)) + (log(light_goal) - log(World.view_exposure(dark))) * k_dark)) < 0.021, "%f" % back)
	_check("the light shaders see the exposure in use", is_equal_approx(Exposure.last, env.tonemap_exposure))
	_check("looking down at the lit field lowers the exposure", World.view_exposure(dark, 1.0) < World.view_exposure(dark, 0.0) * 0.5)
	var cam := Camera3D.new()
	cam.fov = 50.0
	adapt_holder.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2, 0), Vector3(0, 2 + tan(deg_to_rad(40.0)) * 10.0, -10.0), Vector3.UP)
	var up_share := World.ground_share(cam)
	cam.look_at_from_position(Vector3(0, 2, 0), Vector3(0, 2 - tan(deg_to_rad(40.0)) * 10.0, -10.0), Vector3.UP)
	var down_share := World.ground_share(cam)
	cam.look_at_from_position(Vector3(0, 2, 0), Vector3(0, 2, -10.0), Vector3.UP)
	_check("ground share: none 40° up, all 40° down, half level", up_share == 0.0 and down_share == 1.0 and absf(World.ground_share(cam) - 0.5) < 1e-4,
		"%f %f %f" % [up_share, down_share, World.ground_share(cam)])
	adapt_holder.free()
	Atmosphere.state = {}
	var legacy_env := Atmosphere.environment() # the calibrated fixed sun
	World.update(legacy_env, 1.0, Vector3.ZERO, lit)
	_check("fixed sun: no adaptation", is_equal_approx(legacy_env.tonemap_exposure, 0.6), "%f, state %s" % [legacy_env.tonemap_exposure, str(Atmosphere.state.keys())])

	# LU-03: fixture hardware persists by day with zero energy; stars retain the FW night contract.
	var field: Dictionary = FieldLoader.load_from().field
	for case: Array in [[{time_of_day = false}, false], [Conditions.resolve(PackedStringArray(["--time_of_day=noon"])), false],
			[Conditions.resolve(PackedStringArray(["--time_of_day=night"])), true]]:
		var holder := Node3D.new()
		World.build(holder, field, Callable(), case[0])
		var has_lights := holder.get_node_or_null("FieldLights") != null
		var has_stars := holder.get_node_or_null("Stars") != null
		_check("world %s: hardware and stars" % case[0].get("preset", "legacy"), has_lights == (LandscapeOptions.enabled() or case[1]) and has_stars == case[1])
		if has_lights:
			_check("field emission follows time", ((holder.get_node("FieldLights/flood_west") as SpotLight3D).light_energy > 0.0) == bool(case[1]))
		holder.free()
	Atmosphere.state = {}
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
