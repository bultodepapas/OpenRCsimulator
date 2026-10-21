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
const CollisionWorld := preload("res://scenery/collision_world.gd")
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


func _quantity(value: Variant, unit: String) -> Dictionary:
	return {"value": value, "unit": unit, "kind": "estimated", "source": "focused compatibility test"}


func _initialize() -> void:
	var loaded := FieldLights.load_from()
	_check("committed lights file validates", loaded.ok, "; ".join(loaded.errors))
	var refused := {
		"wrong format": func(r: Dictionary) -> void: r.format = "openrc-field-lights v0",
		"unknown type": func(r: Dictionary) -> void: r.emitters[0].type = "laser",
		"missing source": func(r: Dictionary) -> void: r.emitters[0].intensity.erase("source"),
		"wrong unit": func(r: Dictionary) -> void: r.emitters[0].intensity.unit = "lm",
		"negative intensity": func(r: Dictionary) -> void: r.emitters[0].intensity.value = -5,
		"numeric string": func(r: Dictionary) -> void: r.emitters[0].aim_north.value = "9",
		"unknown key": func(r: Dictionary) -> void: r.emitters[0].colour = {value = 1, unit = "x", kind = "estimated", source = "x"},
		"duplicate id": func(r: Dictionary) -> void: r.emitters[1].id = r.emitters[0].id,
		"bad points": func(r: Dictionary) -> void: r.fixtures[0].points.value = [[1, 2, 3]],
		"empty points": func(r: Dictionary) -> void: r.fixtures[0].points.value = [],
		"bad colour": func(r: Dictionary) -> void: r.fixtures[1].color.value = "greenish",
		"too wide beam": func(r: Dictionary) -> void: r.emitters[0].beam_half_angle.value = 85,
		"unlinked installation": func(r: Dictionary) -> void: r.emitters[0].installation_id = "missing",
		"too many floods": func(r: Dictionary) -> void:
			for i in 3:
				var copy: Dictionary = r.emitters[0].duplicate(true)
				copy.id = "extra_%d" % i
				r.emitters.append(copy),
	}
	for name: String in refused:
		var result := _mutant(refused[name])
		_check("refused: " + name, not result.ok, "accepted")

	var legacy := FieldLights.validate({
		"format": "openrc-field-lights v1", "conversion": _quantity(100000, "lux per scene unit"),
		"fixtures": [{"id":"flood_west", "type":"flood", "north":_quantity(-8,"m"), "east":_quantity(-22,"m"),
			"height":_quantity(8,"m"), "aim_north":_quantity(18,"m"), "aim_east":_quantity(-12,"m"),
			"intensity":_quantity(12000,"cd"), "beam_half_angle":_quantity(30,"deg"), "range":_quantity(90,"m"),
			"color_temperature":_quantity(5000,"K")},
			{"id":"old_stakes", "type":"stake_row", "points":_quantity([[9,-50]],"m"), "height":_quantity(0.35,"m"),
			"intensity":_quantity(5,"cd"), "size":_quantity(0.05,"m"), "color_temperature":_quantity(3000,"K")} ]})
	_check("v1 historical lights still normalize", legacy.ok and legacy.lights.fixtures[0].role == "runway_flood"
		and legacy.lights.fixtures[0].distance_attenuation == 1.0, "; ".join(legacy.errors))
	var legacy_nodes := FieldLights.build(legacy.lights)
	_check("v1 historical renderer retains its flood pole", legacy_nodes.get_node_or_null("flood_west_pole") != null)
	legacy_nodes.free()

	var lights := FieldLights.build(loaded.lights)
	var spots := lights.find_children("*", "SpotLight3D", true, false)
	_check("four runway sectors and one windsock spot, no shadows", spots.size() == 5 and lights.get_meta("spots") == 5
		and spots.all(func(s: SpotLight3D) -> bool: return not s.shadow_enabled))
	_check("four independently named runway lamp quads", ["flood_west", "flood_inner_west", "flood_inner_east", "flood_east"].all(
		func(id: String) -> bool: return lights.get_node_or_null(id + "_lamp") is MeshInstance3D))
	_check("v2 uses one shared mast visual and a low windsock mount",
		lights.get_node_or_null("field_mast_pole") != null and lights.get_node_or_null("flood_west_pole") == null
		and lights.get_node_or_null("windsock_mount_pole") != null)
	var west: SpotLight3D = lights.get_node("flood_west")
	_check("flood energy = 8,000 cd / 1e5 lux", is_equal_approx(west.light_energy, 0.08), str(west.light_energy))
	_check("radial decay follows inverse-square exponent", is_equal_approx(west.spot_attenuation, 2.0)
		and is_equal_approx(west.spot_angle_attenuation, 1.0))
	var aim := (Frames.ned_to_render([9.0, -38.0, 0.0]) - west.position).normalized()
	_check("flood aimed at its target", (-west.transform.basis.z).normalized().distance_to(aim) < 1e-4, str(-west.transform.basis.z))
	var horizon_safe := true
	for fixture: Dictionary in loaded.lights.fixtures:
		if fixture.type != "flood" or fixture.role != "runway_flood":
			continue
		var horizontal := Vector2(fixture.aim_north - fixture.north, fixture.aim_east - fixture.east).length()
		var depression := rad_to_deg(atan2(fixture.height - fixture.aim_height, horizontal))
		horizon_safe = horizon_safe and fixture.beam_half_angle <= depression - 1.99
	_check("all runway spot cones stay at least 2 degrees below the horizon", horizon_safe)
	_check("4,000 K is warm neutral", west.light_color.r == 1.0 and west.light_color.b > 0.65 and west.light_color.b < 0.9, str(west.light_color))
	_check("stake rows are one MultiMesh each", (lights.get_node("runway_edge_stakes") as MultiMeshInstance3D).multimesh.instance_count == 12)
	_check("lamp radiance: 5 cd from 5 cm ≈ 0.08", absf(FieldLights.lamp_radiance(5.0, 0.05, 100000.0) - 0.08) < 1e-9)
	_check("engine radial edge reaches zero at range", FieldLights.radial_transport(75.0, 75.0, 2.0) == 0.0)
	_check("smooth cone has no transport at half-angle boundary", FieldLights.angular_transport(cos(deg_to_rad(13.0)), 13.0, 1.0) == 0.0)
	var collidable := CollisionWorld.build({"pilot":{"north":0.0,"east":0.0,"down":0.0}, "objects":[], "flight_cues":[]},
		{"groups":[]}, loaded.lights)
	var mast_poles: Array[Dictionary] = []
	var campfire_proxies: Array[Dictionary] = []
	if collidable.ok:
		for proxy: Dictionary in collidable.world.proxies:
			if str(proxy.part) == "flood_pole" and str(proxy.id).contains("field_mast"):
				mast_poles.append(proxy)
			if str(proxy.part) == "campfire_base": campfire_proxies.append(proxy)
	_check("four spots create one physical mast collider", collidable.ok and mast_poles.size() == 1)
	_check("permanent campfire base collision proxy matches v2 footprint", campfire_proxies.size() == 1
		and campfire_proxies[0].shape == "box" and is_equal_approx(campfire_proxies[0].half_x, 0.5)
		and is_equal_approx(campfire_proxies[0].half_down, 0.2) and campfire_proxies[0].damage_profile == "wood")
	var runway_irradiance: Array[float] = []
	for north: int in range(9, 22):
		for east: int in range(-50, 51):
			var point := Frames.ned_to_render([float(north), float(east), 0.0])
			var value := FieldLights.illuminance_surface(loaded.lights, point, Vector3.UP)
			if value > 0.0:
				runway_irradiance.append(value)
	runway_irradiance.sort()
	var runway_p05 := runway_irradiance[int(float(runway_irradiance.size() - 1) * 0.05)] if not runway_irradiance.is_empty() else 0.0
	var runway_p50 := runway_irradiance[int(runway_irradiance.size() / 2)] if not runway_irradiance.is_empty() else 0.0
	var runway_p95 := runway_irradiance[int(float(runway_irradiance.size() - 1) * 0.95)] if not runway_irradiance.is_empty() else 0.0
	_check("four horizon-safe sectors cover every 1 m runway sample", runway_irradiance.size() == 1313)
	_check("runway surface irradiance reports nonzero p05/p50/p95", runway_p05 > 0.0 and runway_p50 > runway_p05 and runway_p95 > runway_p50,
		"p05 %.8f p50 %.8f p95 %.8f; p95/p05 %.2f" % [runway_p05, runway_p50, runway_p95, runway_p95 / maxf(runway_p05, 1e-20)])
	print("night field grid received scene irradiance: p05=%.8f p50=%.8f p95=%.8f p95/p05=%.2f; nonzero=%d/1313" %
		[runway_p05, runway_p50, runway_p95, runway_p95 / maxf(runway_p05, 1e-20), runway_irradiance.size()])
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
	_test_geometry_arrays()
	_test_underwing_face_selection()
	_test_wing_station_ranges()
	for id: String in [AirplaneBuilder.STIK_ID, AirplaneBuilder.EXTRA_ID, AirplaneBuilder.AVANTI_ID, AirplaneBuilder.P51_ID, AirplaneBuilder.TIMBER_ID]:
		var plane: Dictionary = AirplaneBuilder.build(id)
		var pts := AircraftLights.vertices(plane.root)
		var half := AircraftLights.span_half(pts)
		var tris := AircraftLights.triangles(plane.root)
		var lines := AircraftLights.underwing_lines(tris, half)
		var top_lines := AircraftLights.underwing_lines(tris, half, true)
		var ok := true
		var detail := ""
		var top_ok := true
		var top_detail := ""
		for key: String in ["left", "right"]:
			var line: PackedVector3Array = lines[key]
			var top_line: PackedVector3Array = top_lines[key]
			if line.size() != AircraftLights.STRIP_STATIONS:
				ok = false
				detail = "%s %s: %d stations" % [id, key, line.size()]
			if top_line.size() != AircraftLights.STRIP_STATIONS:
				top_ok = false
				top_detail = "%s %s: %d stations" % [id, key, top_line.size()]
			for k in range(1, line.size()):
				if absf(line[k].y - line[k - 1].y) > 0.06 or absf(line[k].z - line[k - 1].z) > 0.15:
					ok = false
					detail = "%s %s: jump %s -> %s" % [id, key, line[k - 1], line[k]]
			for k in range(1, top_line.size()):
				if absf(top_line[k].y - top_line[k - 1].y) > 0.06 or absf(top_line[k].z - top_line[k - 1].z) > 0.15:
					top_ok = false
					top_detail = "%s %s: jump %s -> %s" % [id, key, top_line[k - 1], top_line[k]]
		var dressed := AircraftLights.attach(plane.root)
		ok = ok and dressed.get_node_or_null("strip_left") != null and dressed.get_node_or_null("strip_right") != null
		_check("%s: smooth under-wing strips on both sides, every station" % id, ok, detail)
		_check("%s: smooth wing-top strips on both sides, every station" % id, top_ok, top_detail)
		var nav_left := dressed.get_node("nav_left") as Node3D
		var nav_right := dressed.get_node("nav_right") as Node3D
		var tip_ok: bool = nav_right.position.x > half and nav_left.position.x < -half
		var anchors: Dictionary = plane.root.get_meta("light_anchors", {})
		if anchors.has("nav_left") and anchors.has("nav_right"):
			var left_anchor: Dictionary = anchors.nav_left
			var right_anchor: Dictionary = anchors.nav_right
			var lens_margin := maxf(0.03, 0.04 * half)
			tip_ok = tip_ok or (left_anchor.get("position") is Vector3 and right_anchor.get("position") is Vector3
				and nav_left.position.distance_to(left_anchor.position) < 0.0001
				and nav_right.position.distance_to(right_anchor.position) < 0.0001
				and absf(absf(nav_left.position.x) - half) <= lens_margin
				and absf(absf(nav_right.position.x) - half) <= lens_margin)
		_check("%s: nav lights at the modeled tips or authored lenses (span %.2f m)" % [id, 2.0 * half], tip_ok,
			"left=%.4f right=%.4f half=%.4f" % [nav_left.position.x, nav_right.position.x, half])
		plane.root.free()

	# Light on a point: the point helper follows the pinned GLES3 radial and smooth cone functions.
	var lights_data: Dictionary = loaded.lights
	var flood: Dictionary = lights_data.fixtures[0]
	var head := Frames.ned_to_render([flood.north, flood.east, -flood.height])
	var aim_point := Frames.ned_to_render([flood.aim_north, flood.aim_east, -flood.aim_height])
	var on_axis := head + (aim_point - head).normalized() * 20.0
	var isolated := lights_data.duplicate(true)
	isolated.fixtures = [flood]
	var expected := float(flood.intensity) / float(lights_data.conversion) * FieldLights.radial_transport(20.0,
		float(flood.range), float(flood.distance_attenuation)) * FieldLights.angular_transport(1.0,
		float(flood.beam_half_angle), float(flood.angular_attenuation))
	_check("flood light on its axis at 20 m", absf(FieldLights.illuminance_point(isolated, on_axis) - expected) < expected * 1e-4,
		"%f vs %f" % [FieldLights.illuminance_point(isolated, on_axis), expected])
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
	# Zero-gain daylight must ignore target/ground lighting, then resume it immediately at dusk.
	# Retain the night adaptation state here to make any leaked artificial term observable.
	var saved_sun_elevation: float = Atmosphere.state.sun_elevation_deg
	var saved_profile: String = World._night_profile
	var legacy_lit_exposure := World.view_exposure(lit, 1.0)
	World._night_profile = "off"
	var unlit_exposure := World.view_exposure(lit, 1.0)
	World._night_profile = saved_profile
	for elevation: float in [3.0, 3.001, 45.0]:
		Atmosphere.state.sun_elevation_deg = elevation
		var expected_day: float = unlit_exposure if LandscapeOptions.enabled() else legacy_lit_exposure
		_check("daylight exposure at %.3f degrees preserves the lighting route" % elevation,
			World.view_exposure(lit, 1.0) == expected_day)
	Atmosphere.state.sun_elevation_deg = -4.0
	_check("artificial adaptation resumes after crossing from day to night",
		World.view_exposure(lit, 1.0) < unlit_exposure)
	World._night_profile = "off"
	_check("disabled night lights do not affect exposure", World.view_exposure(lit, 1.0) == unlit_exposure)
	World._night_profile = saved_profile
	Atmosphere.state.sun_elevation_deg = saved_sun_elevation
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


func _test_underwing_face_selection() -> void:
	# The horizontal skin defines y=0 and y=0.02 m; a vertical fence and a collapsed low triangle overlap its chord.
	# The known skin coordinates must win without depending on triangle selection order.
	var flat_with_fence := _synthetic_wing(0.0, true, true)
	var lower: PackedVector3Array = AircraftLights.underwing_lines(flat_with_fence, 1.0).right
	var upper: PackedVector3Array = AircraftLights.underwing_lines(flat_with_fence, 1.0, true).right
	var flat_ok := lower.size() == AircraftLights.STRIP_STATIONS and upper.size() == AircraftLights.STRIP_STATIONS
	for point in lower:
		flat_ok = flat_ok and absf(point.y + AircraftLights.STRIP_GAP_M) < 1e-6 and absf(point.z - 0.5) < 1e-6
	for point in upper:
		flat_ok = flat_ok and absf(point.y - (0.02 + AircraftLights.STRIP_GAP_M)) < 1e-6 and absf(point.z - 0.5) < 1e-6
	_check("under-wing selectors ignore a lower fence and collapsed face, retaining both known skins", flat_ok,
		"lower=%s upper=%s" % [str(lower), str(upper)])

	var skins := AircraftLights.wing_skin_lines(flat_with_fence, 1.0)
	_check("batched wing skins preserve independent single-skin results",
		var_to_bytes(skins.lower) == var_to_bytes(AircraftLights.underwing_lines(flat_with_fence, 1.0))
		and var_to_bytes(skins.upper) == var_to_bytes(AircraftLights.underwing_lines(flat_with_fence, 1.0, true)))
	var sections := AircraftLights._wing_sections(flat_with_fence, 1.0)
	var saved_sections := var_to_bytes(sections)
	var upper_first := AircraftLights._wing_lines_from_sections(sections, true)
	var lower_second := AircraftLights._wing_lines_from_sections(sections, false)
	_check("wing selectors leave shared cuts unchanged and ignore selection order",
		saved_sections == var_to_bytes(sections) and var_to_bytes(upper_first) == var_to_bytes(skins.upper)
		and var_to_bytes(lower_second) == var_to_bytes(skins.lower))
	var saved_upper := var_to_bytes(skins.upper)
	var changed: PackedVector3Array = skins.lower.right
	changed[0] = Vector3(99, 99, 99)
	skins.lower.right = changed
	_check("editing a lower strip cannot change the upper strip or later builds",
		saved_upper == var_to_bytes(skins.upper)
		and var_to_bytes(lower_second) == var_to_bytes(AircraftLights.wing_skin_lines(flat_with_fence, 1.0).lower))

	# A 0.5 m/m spanwise slope is a real tilted skin (normal still vertical-dominant), not a flat-plane-only special case.
	var slope := 0.5
	var sloped: PackedVector3Array = AircraftLights.underwing_lines(_synthetic_wing(slope, false, false), 1.0).right
	var slope_ok := sloped.size() == AircraftLights.STRIP_STATIONS
	for point in sloped:
		slope_ok = slope_ok and (
			absf(point.y - (slope * point.x - AircraftLights.STRIP_GAP_M)) < 1e-6
			and absf(point.z - 0.5) < 1e-6)
	_check("under-wing selector retains a 26.6-degree spanwise wing slope", slope_ok, str(sloped))

	var degenerate := PackedVector3Array([
		Vector3(0.48, -0.2, 0.4), Vector3(0.68, -0.2, 0.4), Vector3(0.58, -0.2, 0.4)])
	var no_skin: Dictionary = AircraftLights.underwing_lines(degenerate, 1.0)
	_check("zero-area triangles alone create no under-wing stations", no_skin.left.is_empty() and no_skin.right.is_empty(), str(no_skin))


func _synthetic_wing(slope: float, include_fence: bool, include_degenerate: bool) -> PackedVector3Array:
	var triangles := PackedVector3Array()
	for offset: float in [0.0, 0.02]:
		var a := Vector3(-1.0, -slope + offset, 0.0)
		var b := Vector3(1.0, slope + offset, 0.0)
		var c := Vector3(1.0, slope + offset, 1.0)
		var d := Vector3(-1.0, -slope + offset, 1.0)
		triangles.append_array(PackedVector3Array([a, b, c, a, c, d]))
	if include_fence:
		var x0 := 0.48
		var x1 := 0.68
		var z := 0.5
		var f0 := Vector3(x0, slope * x0 - 0.1, z)
		var f1 := Vector3(x1, slope * x1 - 0.1, z)
		var f2 := Vector3(x1, slope * x1 + 0.12, z)
		var f3 := Vector3(x0, slope * x0 + 0.12, z)
		triangles.append_array(PackedVector3Array([f0, f1, f2, f0, f2, f3]))
	if include_degenerate:
		triangles.append_array(PackedVector3Array([
			Vector3(0.48, slope * 0.48 - 0.2, 0.4),
			Vector3(0.68, slope * 0.68 - 0.2, 0.4),
			Vector3(0.58, slope * 0.58 - 0.2, 0.4)]))
	return triangles


func _test_wing_station_ranges() -> void:
	# At half-span 20, the tip stations are exactly +/-19. Each touches one
	# triangle's limiting edge: lower bound on the left, upper bound on the right.
	var edge_triangles := PackedVector3Array([Vector3(-19, 0, -1), Vector3(-18, 0, 0), Vector3(-19, 0, 1),
		Vector3(19, 0, -1), Vector3(18, 0, 0), Vector3(19, 0, 1)])
	var sections := AircraftLights._wing_sections(edge_triangles, 20.0)
	var endpoints_ok := true
	var touched := 0
	for j in sections.xs.size():
		var segments: Array = sections.segments[j]
		if absf(sections.xs[j]) == 19.0:
			touched += 1
			endpoints_ok = endpoints_ok and segments == [[-1.0, 1.0, 0.0, 0.0]]
		else:
			endpoints_ok = endpoints_ok and segments.is_empty()
	_check("wing stations include both limiting triangle edges without extra cuts", endpoints_ok and touched == 2)

	var flat := _synthetic_wing(0.0, false, false)
	var coincident := AircraftLights._wing_sections(flat, 0.0)
	var duplicates_ok: bool = coincident.segments.size() == 2 * AircraftLights.STRIP_STATIONS
	for j in coincident.xs.size():
		duplicates_ok = duplicates_ok and coincident.xs[j] == 0.0 and coincident.segments[j].size() == 4
	_check("coincident wing stations each retain all four skin triangles", duplicates_ok)
	_check("reversed semispan preserves left/right geometry and root-to-tip order",
		var_to_bytes(AircraftLights.wing_skin_lines(flat, -1.0)) == var_to_bytes(AircraftLights.wing_skin_lines(flat, 1.0)))


func _test_geometry_arrays() -> void:
	var model := Node3D.new()
	model.position = Vector3(100, 100, 100) # collector outputs the root's local frame
	var parent := Node3D.new()
	parent.position = Vector3(1, 2, 3)
	model.add_child(parent)
	var item := MeshInstance3D.new()
	item.position = Vector3(.5, 0, 0)
	parent.add_child(item)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 1, 0), Vector3(0, 0, 1), Vector3(4, 7, 9)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([2, 0, 1, 1, 0, 2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0)])
	arrays[Mesh.ARRAY_INDEX] = null
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	item.mesh = mesh
	var saved_mesh := var_to_bytes(mesh.surface_get_arrays(0))
	var geometry := AircraftLights._geometry_arrays(model)
	var expected_points := PackedVector3Array([Vector3(.5, 2, 3), Vector3(2.5, 3, 3), Vector3(1.5, 2, 4),
		Vector3(5.5, 9, 12), Vector3(1.5, 2, 3), Vector3(3.5, 2, 3)])
	var expected_faces := PackedVector3Array([Vector3(1.5, 2, 4), Vector3(.5, 2, 3), Vector3(2.5, 3, 3),
		Vector3(2.5, 3, 3), Vector3(.5, 2, 3), Vector3(1.5, 2, 4)])
	_check("shared geometry retains unused/line vertices in root-local order", geometry.points == expected_points)
	_check("shared geometry preserves triangle winding and excludes line surfaces", geometry.triangles == expected_faces)
	geometry.points[0] = Vector3(99, 99, 99)
	var fresh := AircraftLights._geometry_arrays(model)
	_check("shared geometry results cannot mutate faces, source meshes or later reads",
		geometry.triangles == expected_faces and fresh.points == expected_points and fresh.triangles == expected_faces
		and var_to_bytes(mesh.surface_get_arrays(0)) == saved_mesh)
	model.free()
