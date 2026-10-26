extends SceneTree
## AE-24a: authored paint targets, registration mounts, manifest pins and exact smoke mounts.

const Airplane := preload("res://render/airplane.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const PresentationSources := preload("res://render/presentation_sources.gd")

const AIRCRAFT := [
	"jensen-das-ugly-stik-60",
	"gp-extra-300s-60",
	"p51d-mustang-120",
	"sebart-avanti-s-a200-p100rx",
	"turbo-lumber-evolution",
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_fleet_bindings_and_mounts()
	_test_material_isolation_and_reset("jensen-das-ugly-stik-60")
	_test_material_isolation_and_reset("gp-extra-300s-60")
	_test_invalid_profile_is_atomic()
	print("Aircraft customization: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_fleet_bindings_and_mounts() -> void:
	for id: String in AIRCRAFT:
		var airplane: Dictionary = Airplane.build(id)
		_check(id + " builds with customization", not airplane.is_empty())
		if airplane.is_empty():
			continue
		var bindings: Dictionary = airplane.get("customization_bindings", {})
		var checked: Dictionary = Customization.validate_bindings(bindings,
			str(airplane.get("visual_family", "")), str(airplane.get("model_manifest_sha256", "")))
		_check(id + " bindings validate", checked.get("ok", false), str(checked.get("errors", [])))
		_check(id + " binds the v3 presentation source closure",
			int(bindings.get("version", 0)) == 4 and int(bindings.get("source_proof_version", 0)) == 3
			and str(bindings.get("presentation_engine_version", "")) == PresentationSources.ENGINE_VERSION_PIN
			and bindings.get("presentation_sources", []) == PresentationSources.current_records())
		_check(id + " exposes body, wing and tail paint", _slot_ids(bindings.get("paint_slots", [])) == ["body", "tail", "wing"]
			or _slot_ids(bindings.get("paint_slots", [])) == ["body", "tail", "wing", "wing_tip"])
		var paint: Array = []
		for slot: Dictionary in bindings.get("paint_slots", []):
			paint.append({"slot": slot.id, "color": "#A13BCCFF", "pattern": "solid", "accent": "none"})
		var markings: Array = []
		if not bindings.get("marking_slots", []).is_empty():
			markings.append({"slot": "registration", "text": "NÑ-24", "color": "#00BEEFFF"})
		var applied: Dictionary = Customization.apply(airplane, {"paint": paint, "markings": markings})
		_check(id + " authored paint targets resolve", applied.get("ok", false), str(applied.get("errors", [])))
		if not markings.is_empty():
			_test_registration_mounts(id, airplane, "NÑ-24", Color("#00BEEFFF"))
		var restored: Dictionary = Customization.apply(airplane, {})
		_check(id + " legacy empty paint restores stock", restored.get("ok", false), str(restored.get("errors", [])))
		_check(id + " legacy empty profile removes only owned registration nodes",
			_aircraft_marking_nodes(airplane).is_empty())

		var show_ids := []
		for endpoint: Dictionary in bindings.get("smoke_slots", []):
			if endpoint.kind == "show":
				show_ids.append(str(endpoint.id))
		var expected_show_ids := ["show_tail", "show_wing_tip_left", "show_wing_tip_right"]
		if id in ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t", "stik-glow-55ax-2t", "stik-glow-fs64v-4t", "p51d-mustang-120"]:
			expected_show_ids.push_front("show_exhaust")
		if id == "sebart-avanti-s-a200-p100rx": expected_show_ids.insert(1, "show_tailpipe")
		_check(id + " declares authored show mounts", show_ids == expected_show_ids)
		var transforms: Dictionary = Customization.smoke_transforms(airplane)
		var expected_count: int = bindings.get("smoke_slots", []).size()
		_check(id + " resolves only authored smoke endpoints", transforms.size() == expected_count, str(transforms.keys()))
		airplane.root.transform = Transform3D(Basis(Vector3.UP, 0.31), Vector3(2.0, 1.0, -3.0))
		transforms = Customization.smoke_transforms(airplane)
		for endpoint: Dictionary in bindings.get("smoke_slots", []):
			if endpoint.kind == "show" and not endpoint.has("anchor_id"):
				var expected_position: Vector3 = airplane.root.transform * _vector(endpoint.position_m)
				var expected_direction: Vector3 = (airplane.root.transform.basis * _vector(endpoint.direction)).normalized()
				var actual: Transform3D = transforms.get(str(endpoint.id), Transform3D.IDENTITY)
				_check(id + " " + str(endpoint.id) + " origin follows authored pose", actual.origin.is_equal_approx(expected_position))
				_check(id + " " + str(endpoint.id) + " local -Z follows authored direction",
					(actual.basis * Vector3.FORWARD).normalized().dot(expected_direction) > 0.999)
			else:
				var anchor: Dictionary = airplane.exhausts[0]
				var expected_position: Vector3 = airplane.root.transform * anchor.position
				var expected_direction: Vector3 = (airplane.root.transform.basis * anchor.direction).normalized()
				var actual: Transform3D = transforms.get(str(endpoint.id), Transform3D.IDENTITY)
				_check(id + " physical exhaust origin follows matching source", actual.origin.is_equal_approx(expected_position))
				_check(id + " physical exhaust direction is preserved",
					(actual.basis * Vector3.FORWARD).normalized().dot(expected_direction) > 0.999)
		airplane.root.free()


func _test_material_isolation_and_reset(id: String) -> void:
	var first: Dictionary = Airplane.build(id)
	var second: Dictionary = Airplane.build(id)
	_check(id + " builds two independent instances", not first.is_empty() and not second.is_empty())
	if first.is_empty() or second.is_empty():
		return
	var body: Dictionary = _find_slot(first.customization_bindings.paint_slots, "body")
	var target: Dictionary = body.targets[0]
	var first_mesh := first.root.get_node(NodePath(target.node_path)) as MeshInstance3D
	var second_mesh := second.root.get_node(NodePath(target.node_path)) as MeshInstance3D
	var source: Material = first_mesh.get_active_material(int(target.surface))
	var second_source: Material = second_mesh.get_active_material(int(target.surface))
	var source_color := _material_color(source, target)
	var red := {"paint": [{"slot": "body", "color": "#D32F2FFF", "pattern": "solid", "accent": "none"}], "markings": []}
	var applied: Dictionary = Customization.apply(first, red)
	_check(id + " paint applies", applied.get("ok", false), str(applied.get("errors", [])))
	var first_copy: Material = first_mesh.get_active_material(int(target.surface))
	var second_stays_source: Material = second_mesh.get_active_material(int(target.surface))
	_check(id + " paint uses a new per-instance material", first_copy != source and first_copy != second_source)
	_check(id + " other instance and cached source stay stock",
		second_stays_source == second_source and _material_color(second_stays_source, target).is_equal_approx(source_color)
		and _material_color(source, target).is_equal_approx(source_color))
	_check(id + " selected color is visible", _material_color(first_copy, target).is_equal_approx(Color("#D32F2FFF")))
	if id == "jensen-das-ugly-stik-60":
		var registered: Dictionary = Customization.apply(first,
			{"paint": [], "markings": [{"slot": "registration", "text": "NÑ-24", "color": "#FFFFFFFF"}]})
		_check("registration mounts on one instance", registered.get("ok", false)
			and _aircraft_marking_nodes(first).size() == 2 and _aircraft_marking_nodes(second).is_empty())
		_check("other aircraft instance receives no registration text", _aircraft_marking_nodes(second).is_empty())
	var reset: Dictionary = Customization.apply(first, {})
	_check(id + " empty paint resets the per-instance copy", reset.get("ok", false)
		and _material_color(first_mesh.get_active_material(int(target.surface)), target).is_equal_approx(source_color))
	if id == "jensen-das-ugly-stik-60":
		_check("registration reset removes the owned nodes", _aircraft_marking_nodes(first).is_empty())
	first.root.free()
	second.root.free()


func _test_invalid_profile_is_atomic() -> void:
	var airplane: Dictionary = Airplane.build("gp-extra-300s-60")
	if airplane.is_empty():
		_check("invalid-profile airplane builds", false)
		return
	var valid := {"paint": [{"slot": "body", "color": "#ED8B00FF", "pattern": "solid", "accent": "none"}],
		"markings": [{"slot": "registration", "text": "NÑ-24", "color": "#314159FF"}]}
	_check("atomicity fixture applies", Customization.apply(airplane, valid).get("ok", false))
	var labels_before := _aircraft_marking_nodes(airplane)
	var slot: Dictionary = _find_slot(airplane.customization_bindings.paint_slots, "body")
	var target: Dictionary = slot.targets[0]
	var mesh := airplane.root.get_node(NodePath(target.node_path)) as MeshInstance3D
	var before: Material = mesh.get_active_material(int(target.surface))
	var bad := {"paint": [{"slot": "unregistered", "color": "#FFFFFFFF", "pattern": "solid", "accent": "none"}], "markings": []}
	var rejected: Dictionary = Customization.apply(airplane, bad)
	_check("unknown paint slot is rejected without mutation", not rejected.get("ok", false)
		and mesh.get_active_material(int(target.surface)) == before
		and _material_color(before, target).is_equal_approx(Color("#ED8B00FF")))
	var invalid_markings := [
		{"slot": "registration", "text": "TOO-LONG-REG-1", "color": "#FFFFFFFF"},
		{"slot": "registration", "text": "NÑ-☃", "color": "#FFFFFFFF"},
		{"slot": "missing", "text": "NÑ-24", "color": "#FFFFFFFF"},
	]
	for item: Dictionary in invalid_markings:
		var bad_marking: Dictionary = Customization.apply(airplane, {"paint": [], "markings": [item]})
		_check("invalid marking is rejected without replacing existing labels",
			not bad_marking.get("ok", false) and _same_node_references(_aircraft_marking_nodes(airplane), labels_before))
	var unsupported_airplane: Dictionary = Airplane.build("p51d-mustang-120")
	var unsupported: Dictionary = Customization.apply(unsupported_airplane,
		{"paint": [], "markings": [{"slot": "registration", "text": "NÑ-24", "color": "#FFFFFFFF"}]})
	_check("unsupported family registration slot fails closed", not unsupported.get("ok", false))
	if not unsupported_airplane.is_empty():
		unsupported_airplane.root.free()
	airplane.root.free()
	for node: Label3D in labels_before:
		_check("owned registration node is freed with its airplane", not is_instance_valid(node))


func _test_registration_mounts(id: String, airplane: Dictionary, text: String, color: Color) -> void:
	var slot: Dictionary = _find_slot(airplane.customization_bindings.marking_slots, "registration")
	var labels := _aircraft_marking_nodes(airplane)
	_check(id + " creates both authored registration labels", labels.size() == 2)
	if labels.size() != 2:
		return
	var expected_font: Font = ThemeDB.fallback_font
	for index in 2:
		var target: Dictionary = slot.targets[index]
		var label: Label3D = labels[index]
		var parent := airplane.root.get_node_or_null(NodePath(str(target.node_path))) as MeshInstance3D
		_check(id + " label has exact mesh parent", label.get_parent() == parent)
		_check(id + " label uses exact authored local mount", label.position.is_equal_approx(_vector(target.position_m)))
		_check(id + " label faces authored fuselage side",
			label.basis.z.normalized().dot(_vector(target.direction).normalized()) > 0.999)
		_check(id + " label up follows authored mount", label.basis.y.normalized().dot(_vector(target.up).normalized()) > 0.999)
		_check(id + " label uses fallback font and preserves Spanish glyph", label.font == expected_font and label.text == text)
		_check(id + " label color matches selected swatch", label.modulate.is_equal_approx(color))
		_check(id + " label is single-sided, depth-tested and not billboarded",
			not label.double_sided and not label.no_depth_test and label.billboard == BaseMaterial3D.BILLBOARD_DISABLED)
		var line_size := label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.font_size)
		var font_height := label.font.get_height(label.font_size)
		_check(id + " label fits its bounded authored panel",
			line_size.x * label.pixel_size <= float(target.width_m) and font_height * label.pixel_size <= float(target.height_m))


func _aircraft_marking_nodes(airplane: Dictionary) -> Array[Label3D]:
	var result: Array[Label3D] = []
	for item: Variant in airplane.get("_customization_marking_nodes", []):
		if item is Label3D and is_instance_valid(item):
			result.append(item)
	return result


func _same_node_references(left: Array[Label3D], right: Array[Label3D]) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _find_slot(slots: Array, id: String) -> Dictionary:
	for slot: Dictionary in slots:
		if str(slot.get("id", "")) == id:
			return slot
	return {}


func _slot_ids(slots: Array) -> Array:
	var ids := []
	for slot: Dictionary in slots:
		ids.append(str(slot.get("id", "")))
	return ids


func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _material_color(material: Material, target: Dictionary) -> Color:
	if target.kind == "standard_albedo":
		return (material as StandardMaterial3D).albedo_color
	return (material as ShaderMaterial).get_shader_parameter(str(target.parameter))


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label + (" — " + detail if not detail.is_empty() else ""))
