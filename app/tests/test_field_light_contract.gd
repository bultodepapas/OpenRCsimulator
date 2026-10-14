extends SceneTree

const FieldLights := preload("res://render/world/field_lights.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Frames := preload("res://render/frames.gd")

var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _q(value: Variant, unit: String) -> Dictionary:
	return {"value": value, "unit": unit, "kind": "estimated", "source": "focused compatibility test"}


func _initialize() -> void:
	var loaded := FieldLights.load_from()
	_check("committed v2 lights validate", loaded.ok, "; ".join(loaded.errors))
	if not loaded.ok:
		quit(1)
		return
	var fixtures: Array = loaded.lights.fixtures
	_check("five explicit v2 emitters have installation IDs and consumer roles",
		fixtures.size() == 8 and fixtures.slice(0, 5).all(func(f: Dictionary) -> bool:
			return f.type == "flood" and not str(f.installation_id).is_empty() and not str(f.role).is_empty()))
	_check("legacy flood IDs survive v2 migration", fixtures[0].id == "flood_west" and fixtures[4].id == "windsock_flood")

	var invalid_numeric: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLights.DEFAULT_PATH))
	invalid_numeric.emitters[0].intensity.value = "8000"
	_check("numeric strings are rejected", not FieldLights.validate(invalid_numeric).ok)
	var invalid_role: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLights.DEFAULT_PATH))
	invalid_role.emitters[0].role = "unconsumed"
	_check("unknown consumer roles are rejected", not FieldLights.validate(invalid_role).ok)
	var invalid_link: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLights.DEFAULT_PATH))
	invalid_link.emitters[0].installation_id = "missing"
	_check("dangling installation references are rejected", not FieldLights.validate(invalid_link).ok)

	var v1 := FieldLights.validate({"format":"openrc-field-lights v1", "conversion":_q(100000,"lux per scene unit"), "fixtures":[
		{"id":"flood_west", "type":"flood", "north":_q(-8,"m"), "east":_q(-22,"m"), "height":_q(8,"m"),
			"aim_north":_q(18,"m"), "aim_east":_q(-12,"m"), "intensity":_q(12000,"cd"),
			"beam_half_angle":_q(30,"deg"), "range":_q(90,"m"), "color_temperature":_q(5000,"K")} ]})
	_check("v1 files keep historical decay and do not claim v2 installations", v1.ok
		and v1.lights.fixtures[0].distance_attenuation == 1.0
		and str(v1.lights.fixtures[0].get("installation_id", "")).is_empty() and v1.lights.installations.is_empty(),
		"; ".join(v1.errors))
	var v1_nodes := FieldLights.build(v1.lights)
	_check("v1 build retains its original per-flood pole node", v1_nodes.get_node_or_null("flood_west_pole") != null
		and v1_nodes.find_children("*", "SpotLight3D", true, false).size() == 1)
	v1_nodes.free()

	var node := FieldLights.build(loaded.lights)
	var spots := node.find_children("*", "SpotLight3D", true, false)
	_check("four runway spots and one windsock spot build without shadows", spots.size() == 5
		and spots.all(func(value: SpotLight3D) -> bool: return not value.shadow_enabled))
	_check("one mast shaft serves four independently named lamps", node.get_node_or_null("field_mast_pole") != null
		and node.get_node_or_null("flood_west_pole") == null
		and ["flood_west", "flood_inner_west", "flood_inner_east", "flood_east"].all(
			func(id: String) -> bool: return node.get_node_or_null(id + "_lamp") is MeshInstance3D))
	var position_set := {}
	for id: String in ["flood_west", "flood_inner_west", "flood_inner_east", "flood_east"]:
		position_set[(node.get_node(id) as SpotLight3D).position.x] = true
	_check("each mast head has a distinct reachable position", position_set.size() == 4)
	var west := node.get_node("flood_west") as SpotLight3D
	_check("v2 radial law uses inverse square and smooth cone law", is_equal_approx(west.spot_attenuation, 2.0)
		and is_equal_approx(west.spot_angle_attenuation, 1.0))
	_check("radial window and angular boundary follow pinned GLES3", FieldLights.radial_transport(75.0, 75.0, 2.0) == 0.0
		and FieldLights.angular_transport(cos(deg_to_rad(13.0)), 13.0, 1.0) == 0.0)

	var samples: Array[float] = []
	for north: int in range(9, 22):
		for east: int in range(-50, 51):
			var point := Frames.ned_to_render([float(north), float(east), 0.0])
			var illuminance := FieldLights.illuminance_surface(loaded.lights, point, Vector3.UP)
			if illuminance > 0.0: samples.append(illuminance)
	samples.sort()
	var p05 := samples[int(float(samples.size() - 1) * 0.05)] if not samples.is_empty() else 0.0
	var p50 := samples[int(samples.size() / 2)] if not samples.is_empty() else 0.0
	var p95 := samples[int(float(samples.size() - 1) * 0.95)] if not samples.is_empty() else 0.0
	_check("all 1 m runway surface samples receive light", samples.size() == 1313)
	_check("runway intensity distribution is measured", p05 > 0.0 and p50 > p05 and p95 > p50,
		"p05 %.8f p50 %.8f p95 %.8f p95/p05 %.2f" % [p05, p50, p95, p95 / maxf(p05, 1e-20)])
	print("night runway scene irradiance: p05=%.8f p50=%.8f p95=%.8f p95/p05=%.2f; nonzero=%d/1313" %
		[p05, p50, p95, p95 / maxf(p05, 1e-20), samples.size()])

	var collision := CollisionWorld.build({"pilot":{"north":0.0,"east":0.0,"down":0.0}, "objects":[], "flight_cues":[]},
		{"groups":[]}, loaded.lights)
	var mast_count := 0
	var fire_count := 0
	var good_fire_proxy := false
	if collision.ok:
		for proxy: Dictionary in collision.world.proxies:
			if proxy.part == "flood_pole" and str(proxy.id).contains("field_mast"): mast_count += 1
			if proxy.part == "campfire_base":
				fire_count += 1
				good_fire_proxy = proxy.shape == "box" and is_equal_approx(proxy.half_x, 0.5) \
					and is_equal_approx(proxy.half_down, 0.2) and proxy.damage_profile == "wood"
	_check("collision world has one mast collider for the four spots", collision.ok and mast_count == 1)
	_check("campfire base is a permanent wood proxy at 1 m by 0.4 m", fire_count == 1 and good_fire_proxy)

	node.free()
	print("%d failures" % _failures)
	quit(1 if _failures > 0 else 0)
