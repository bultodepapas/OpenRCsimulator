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
	_check("flood energy = 30,000 cd / 1e5 lux", is_equal_approx(west.light_energy, 0.3), str(west.light_energy))
	var aim := (Frames.ned_to_render([18.0, -12.0, 0.0]) - west.position).normalized()
	_check("flood aimed at its target", (-west.transform.basis.z).normalized().distance_to(aim) < 1e-4, str(-west.transform.basis.z))
	_check("5,000 K is near-white, slightly warm of D65", west.light_color.r == 1.0 and west.light_color.b > 0.75 and west.light_color.b < 0.9, str(west.light_color))
	_check("stake rows are one MultiMesh each", (lights.get_node("runway_edge_stakes") as MultiMeshInstance3D).multimesh.instance_count == 12)
	_check("lamp radiance: 5 cd from 5 cm ≈ 0.08", absf(FieldLights.lamp_radiance(5.0, 0.05, 100000.0) - 0.08) < 1e-9)
	lights.free()

	# Night kit on the Stik: red at −x (left), green at +x (right), landing light forward.
	var airplane: Dictionary = AirplaneBuilder.build()
	var b := AircraftLights.bounds(airplane.root) # before the kit: its sprite quads would widen the bounds
	var kit := AircraftLights.attach(airplane.root)
	var left: Node3D = kit.get_node("nav_left")
	var right: Node3D = kit.get_node("nav_right")
	_check("nav lights at the wing tips", left.position.x < b.wing.position.x and right.position.x > b.wing.end.x
		and absf(right.position.x - b.wing.end.x) < 0.05)
	_check("left red, right green", ((left as MeshInstance3D).mesh.material as ShaderMaterial).get_shader_parameter("light_color").r > 0.9
		and ((right as MeshInstance3D).mesh.material as ShaderMaterial).get_shader_parameter("light_color").g > 0.9)
	var landing: SpotLight3D = kit.get_node("landing_light")
	_check("landing light points forward (−z) and a little down", (-landing.transform.basis.z).z < -0.9 and (-landing.transform.basis.z).y < 0.0)
	_check("kit names never collide with the model's hinges", kit.find_children("*_hinge", "", true, false).is_empty())
	airplane.root.free()

	# World: legacy builds no lights; night builds stars, lights; noon builds none.
	var field: Dictionary = FieldLoader.load_from().field
	for case: Array in [[{time_of_day = false}, false], [Conditions.resolve(PackedStringArray(["--time_of_day=noon"])), false],
			[Conditions.resolve(PackedStringArray(["--time_of_day=night"])), true]]:
		var holder := Node3D.new()
		World.build(holder, field, Callable(), case[0])
		var has_lights := holder.get_node_or_null("FieldLights") != null
		var has_stars := holder.get_node_or_null("Stars") != null
		_check("world %s: field lights %s, stars %s" % [case[0].get("preset", "legacy"), case[1], case[1]], has_lights == case[1] and has_stars == case[1])
		holder.free()
	Atmosphere.state = {}
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
