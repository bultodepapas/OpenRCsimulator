extends SceneTree
const Lights := preload("res://render/world/aircraft_lights.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Airplane := preload("res://render/airplane.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _fixture() -> Dictionary:
	return {"version": 1, "anchors": [{"id": "nav_left", "node_path": "Mount", "position_m": [-0.2, 0.05, 0.0], "gear_gated": false}],
		"strips": [{"id": "strip_left", "node_path": "Mount", "points_m": [[-0.5, 0.04, 0.0], [-0.2, 0.04, 0.0]], "face": [0, 1, 0], "width_m": 0.012}]}

func _run() -> void:
	var layout := _fixture()
	check("closed layout validates including JSON numeric roundtrip", Lights.validate_authored_layout(layout).ok
		and Lights.validate_authored_layout(JSON.parse_string(JSON.stringify(layout))).ok)
	for path: String in ["../Mount", "/root/Mount", "res://anything", "Mount:position", "Mount//Child", "x".repeat(161)]:
		var bad := layout.duplicate(true)
		bad.anchors[0].node_path = path
		check("unsafe host path rejected: " + path.left(25), not Lights.validate_authored_layout(bad).ok)
	for value: Variant in [true, INF, NAN, 5.01]:
		var bad := layout.duplicate(true)
		bad.anchors[0].position_m[0] = value
		check("invalid coordinate rejected", not Lights.validate_authored_layout(bad).ok)
	var bad := layout.duplicate(true)
	bad.anchors.append(bad.anchors[0].duplicate(true))
	check("duplicate semantic mounts rejected", not Lights.validate_authored_layout(bad).ok)
	bad = layout.duplicate(true)
	bad.strips[0].points_m[1] = bad.strips[0].points_m[0].duplicate()
	check("collapsed strip segments rejected", not Lights.validate_authored_layout(bad).ok)
	bad = layout.duplicate(true)
	bad.strips[0].face = [1, 0, 0]
	check("strip face parallel to its path rejected", not Lights.validate_authored_layout(bad).ok)
	bad = layout.duplicate(true)
	bad.strips[0].points_m.resize(33)
	check("strip station count bounded", not Lights.validate_authored_layout(bad).ok)
	bad = layout.duplicate(true)
	bad.anchors[0].gear_gated = true
	check("navigation cannot be gear gated", not Lights.validate_authored_layout(bad).ok)
	var aircraft := Node3D.new()
	root.add_child(aircraft)
	var wing := MeshInstance3D.new()
	wing.mesh = BoxMesh.new()
	wing.mesh.size = Vector3(2.0, 0.08, 0.3)
	aircraft.add_child(wing)
	var mount := Node3D.new()
	mount.name = "Mount"
	mount.position = Vector3(-0.3, 0.1, 0.2)
	mount.rotation = Vector3(0.1, 0.2, 0.3)
	mount.scale = Vector3(1.3, 0.8, 1.1)
	aircraft.add_child(mount)
	var fitted := Lights.prepare_layout(aircraft)
	var baseline := Lights.attach(aircraft, fitted)
	var baseline_position: Vector3 = baseline.get_node("nav_left").position
	aircraft.remove_child(baseline)
	baseline.free()
	aircraft.set_meta("lighting_layout", layout.duplicate(true))
	var kit := Lights.attach(aircraft, fitted)
	var lamp := kit.get_node("nav_left") as Node3D
	var strip := kit.get_node("strip_left") as MeshInstance3D
	check("authored point uses host translation rotation and scale", lamp.position.is_equal_approx(mount.transform * Vector3(-0.2, 0.05, 0)))
	check("authored strip remains node-local and follows full transform", strip.transform.is_equal_approx(mount.transform))
	check("authored width and face reach the material", is_equal_approx(float(strip.mesh.surface_get_material(0).get_shader_parameter("width_m")), 0.012)
		and strip.mesh.surface_get_material(0).get_shader_parameter("face_dir") == Vector3.UP)
	check("cached fitted layout is reused without authored instance data", is_same(kit.get_meta("geometry_layout"), fitted) and not fitted.has("anchors"))
	mount.position += Vector3(0.1, 0.2, 0.3)
	mount.rotate_z(0.4)
	Lights.update_dynamic(kit, aircraft, 1.0)
	check("point and strip track moving mounts", lamp.position.is_equal_approx(mount.transform * Vector3(-0.2, 0.05, 0)) and strip.transform.is_equal_approx(mount.transform))
	check("one existing kit is retained", Lights.attach(aircraft) == kit)
	aircraft.remove_child(kit)
	kit.free()
	aircraft.set_meta("light_anchors", {"nav_left": {"position": baseline_position}})
	kit = Lights.attach(aircraft, fitted)
	check("builder-owned point wins with a diagnostic", kit.get_node("nav_left").position == baseline_position and not kit.get_meta("layout_warnings").is_empty())
	aircraft.remove_child(kit)
	kit.free()
	aircraft.remove_meta("light_anchors")
	var missing := layout.duplicate(true)
	missing.anchors[0].node_path = "Missing"
	missing.strips[0].node_path = "Missing"
	aircraft.set_meta("lighting_layout", missing)
	kit = Lights.attach(aircraft, fitted)
	check("missing authored hosts retain fitted equipment", kit.get_node("nav_left").position == baseline_position
		and not kit.get_node("strip_left").has_meta("follow_transform") and kit.get_meta("layout_warnings").size() == 2)
	aircraft.free()
	var empty := Node3D.new()
	root.add_child(empty)
	kit = Lights.attach(empty)
	check("missing geometry produces an empty diagnosed kit", kit.get_child_count() == 0 and not kit.get_meta("layout_warnings").is_empty())
	empty.free()
	var built := Airplane.build("jensen-das-ugly-stik-60")
	check("normal aircraft build projects the generated layout", not built.is_empty() and built.root.get_meta("lighting_layout") == built.customization_bindings.lighting_layout)
	if not built.is_empty():
		var bindings: Dictionary = built.customization_bindings.duplicate(true)
		bindings.lighting_layout = layout
		bindings.slots_sha256 = Presentation.bindings_sha256(bindings)
		check("companion and profile readers both validate v4 layouts", Customization.validate_bindings(bindings).ok and Presentation.validate(Presentation.defaults(bindings), bindings).ok)
		bindings.lighting_layout.strips[0].width_m = true
		bindings.slots_sha256 = Presentation.bindings_sha256(bindings)
		check("both readers reject malformed authored layouts even with matching hash", not Customization.validate_bindings(bindings).ok and not Presentation.validate(Presentation.defaults(), bindings).ok)
		built.root.free()
	await process_frame
	print("Lighting layouts: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if ok: print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label)
