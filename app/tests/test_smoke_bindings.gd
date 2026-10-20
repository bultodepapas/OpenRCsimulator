extends SceneTree
const Customization := preload("res://render/aircraft_customization.gd")
const Profile := preload("res://workshop/presentation.gd")
const Sources := preload("res://render/presentation_sources.gd")
var _failures := 0
var _checks := 0

func _initialize() -> void:
	var root := Node3D.new()
	var outlet_node := Node3D.new()
	root.add_child(outlet_node)
	var first := _slot("left_exit", "engine_a", "left")
	var second := _slot("right_exit", "engine_a", "right")
	var third := _slot("second_engine", "engine_b", "exit")
	var slots: Array = [first, second, third]
	var bindings := _bindings(slots)
	for malformed_version: Variant in [[], {}, true, "2", 0, 3]:
		var invalid_binding := bindings.duplicate(true)
		invalid_binding.source_proof_version = malformed_version
		invalid_binding.slots_sha256 = Profile.bindings_sha256(invalid_binding)
		_check("malformed proof version fails structurally without runtime error " + str(malformed_version),
			not Customization.validate_bindings(invalid_binding).get("ok", false)
			and not Profile.validate(Profile.defaults(), invalid_binding).get("ok", false))
	var airplane: Dictionary = {"root": root, "customization_bindings": bindings,
		"visual_family": "fixture", "model_manifest_sha256": "a".repeat(64),
		"smoke_sources": {
			"engine_a": {"kind": "glow_prop", "anchors": {
				"left": {"position": Vector3(-0.2, 0.1, 0.3), "direction": Vector3.LEFT},
				"right": {"position": Vector3(0.2, 0.1, 0.3), "direction": Vector3.RIGHT, "node": outlet_node}}},
			"engine_b": {"kind": "glow_prop", "anchors": {
				"exit": {"position": Vector3(0.0, 0.1, 0.3), "direction": Vector3.BACK}}}}}
	var resolved := Customization.resolve_smoke_bindings(airplane)
	_check("two outlets share one stable engine and another engine resolves", resolved.get("ok", false)
		and resolved.handles.sources.left_exit == resolved.handles.sources.right_exit
		and resolved.handles.sources.second_engine != resolved.handles.sources.left_exit, str(resolved.get("errors", [])))
	for scale_value: float in [0.1, 1.0, 5.0]:
		root.transform = Transform3D(Basis.from_euler(Vector3(0.41, -0.67, PI)).scaled(Vector3.ONE * scale_value), Vector3(3.2, -1.4, 6.0))
		var transforms := Customization.update_smoke_transforms(resolved.handles)
		_check("all transformed outlets retained at scale " + str(scale_value), transforms.size() == 3)
		var expected: Vector3 = root.transform * Vector3(-0.2, 0.1, 0.3)
		_check("position scale CG and inversion at " + str(scale_value), transforms.left_exit.origin.distance_to(expected) < 0.00001)
		var direction: Vector3 = (root.transform.basis * Vector3.LEFT).normalized()
		_check("direction scale CG and inversion at " + str(scale_value), (-transforms.left_exit.basis.z).normalized().dot(direction) > 0.99999)
		_check("authored bore retains uniform scale at " + str(scale_value),
			absf(transforms.left_exit.basis.x.length() * float(first.radius_m) - scale_value * float(first.radius_m)) < 0.000001)
	outlet_node.position = Vector3(0.0, 0.25, 0.0)
	var moved := Customization.update_smoke_transforms(resolved.handles)
	_check("cached articulated handles update", moved.right_exit.origin.distance_to(root.transform * Vector3(0.2, 0.35, 0.3)) < 0.00001)
	root.basis = Basis(Vector3(1, 0, 0), Vector3(0.2, 1, 0), Vector3(0, 0, 1))
	_check("sheared root safely unavailable", Customization.update_smoke_transforms(resolved.handles).is_empty())
	root.transform = Transform3D.IDENTITY
	airplane.smoke_sources.engine_a.anchors.erase("left")
	var missing := Customization.resolve_smoke_bindings(airplane)
	_check("missing stable anchor reports no origin fallback", not missing.ok
		and not Customization.update_smoke_transforms(missing.handles).has("left_exit"))
	airplane.smoke_sources.engine_b.kind = "turbine"
	var wrong := Customization.resolve_smoke_bindings(airplane)
	_check("mismatched source kind cannot emit", not wrong.ok
		and not Customization.update_smoke_transforms(wrong.handles).has("second_engine"))
	var malformed := first.duplicate(true)
	malformed["source_anchor_ref"] = "exhausts[0]"
	_check("v3 rejects legacy positional selector", not Customization.validate_smoke_slot(malformed).ok)
	malformed = first.duplicate(true)
	malformed.radius_m = true
	_check("v3 rejects boolean bore radius", not Customization.validate_smoke_slot(malformed).ok)
	var eight: Array = []
	var modern := Profile.defaults(bindings)
	for index in range(8):
		var slot := _slot("outlet_%d" % index, "engine_a", "right")
		eight.append(slot)
		modern.smoke.append(_entry(str(slot.id), index < 4))
	bindings = _bindings(eight)
	modern = Profile.defaults(bindings)
	for index in range(8):
		modern.smoke.append(_entry("outlet_%d" % index, index < 4))
	_check("eight authored selections with four active accepted", Profile.validate(modern, bindings).get("ok", false))
	modern.smoke[4].enabled = true
	_check("fifth active outlet refused", not Profile.validate(modern, bindings).get("ok", false))
	root.free()
	_check("deleted cached root returns empty", Customization.update_smoke_transforms(resolved.handles).is_empty())
	print("Smoke stable bindings: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _slot(id: String, source: String, anchor: String) -> Dictionary:
	return {"id": id, "label": "Source outlet", "kind": "source", "role": "exhaust", "pair": "",
		"source_id": source, "source_kind": "glow_prop", "anchor_id": anchor,
		"radius_m": 0.003, "emissions_preset": "glow_two_stroke", "activation_policy": "source_running", "provenance": "estimated"}

func _bindings(slots: Array) -> Dictionary:
	var result := {"format": Profile.BINDINGS_FORMAT, "version": 3, "source_proof_version": 2,
		"visual_family": "fixture", "model_manifest_sha256": "a".repeat(64), "paint_slots": [], "marking_slots": [],
		"smoke_slots": slots, "presentation_engine_version": "4.7.2", "presentation_sources": Sources.current_records(2), "slots_sha256": ""}
	result.slots_sha256 = Profile.bindings_sha256(result)
	return result

func _entry(slot: String, enabled: bool) -> Dictionary:
	return {"slot": slot, "enabled": enabled, "color": "#FFFFFFFF", "amount": 1.0,
		"width_m": 0.2, "lifetime_s": 2.0, "shape": "ribbon", "mode": "hold",
		"burst_s": 0.0, "pulse_period_s": 0.0, "pulse_duty": 0.0, "palette": [], "step_s": 0.0}

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
