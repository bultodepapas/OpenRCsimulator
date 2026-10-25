extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const RGB_STRIP_SHADER := preload("res://render/lighting/rgb_strip.gdshader")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "LightingRigTestStage"
	root.add_child(stage)
	await process_frame
	var aircraft := _make_aircraft(stage, "LightingRigAircraft")
	var inherited := Rig.new()
	var inherit_result: Dictionary = inherited.configure(aircraft, Profile.defaults())
	_check("inherit stays lazy", bool(inherit_result.get("ok", false)) and aircraft.get_node_or_null("NightKit") == null and inherited.get_kit() == null)
	inherited.dispose()

	var kit := AircraftLights.attach(aircraft)
	_add_test_strip(kit, "strip_left")
	_add_test_strip(kit, "strip_right")
	var festival: Dictionary = Profile.preset("festival")
	var checked_profile: Dictionary = Profile.validate(festival)
	_check("Festival keeps optional effects optional", bool(checked_profile.get("ok", false)) and not bool(festival.effects[0].get("required", true)))

	var rig := Rig.new()
	var configured: Dictionary = rig.configure(aircraft, festival)
	_check("explicit profile configures one existing NightKit", bool(configured.get("ok", false)) and rig.get_kit() == kit)
	var budget: Dictionary = rig.budget_info()
	var vfx_budget: Dictionary = budget.get("vfx", {})
	_check("bounded effects and two actual spill lights allocate", int(vfx_budget.get("effects_allocated", -1)) == 2 and int(vfx_budget.get("spill_lights_allocated", -1)) == 2 and _count_children(kit, "OmniLight3D") == 2)

	var telemetry := {"effects_allowed": true, "distance_m": 0.0, "exposure": 10000.0, "maneuver": 0.0, "throttle": 0.6}
	rig.advance(8.02, telemetry)
	var fx_root := stage.get_node_or_null("AircraftLightingWorldVfx") as Node3D
	var spark_nodes := _children_of_type(fx_root, "MultiMeshInstance3D")
	_check("sequence burst uses a bounded 32 point pool per tip", spark_nodes.size() == 2 and spark_nodes.all(func(node: Node) -> bool: return (node as MultiMeshInstance3D).multimesh.visible_instance_count == 32))
	var strip_material := (kit.get_node("strip_left") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	_check("actual exposure reaches the strip cap unchanged", strip_material != null and is_equal_approx(float(strip_material.get_shader_parameter("local_exposure")), 10000.0))

	var strobe := kit.get_node("strobe_left") as MeshInstance3D
	var strobe_material := strobe.get_surface_override_material(0) as ShaderMaterial
	var clock_before := float(strobe_material.get_shader_parameter("local_clock"))
	rig.advance(NAN, telemetry)
	_check("nonfinite clock is ignored safely", is_equal_approx(float(strobe_material.get_shader_parameter("local_clock")), clock_before))
	rig.advance(8.02, telemetry)
	_check("paused clock holds the sequence burst", spark_nodes.all(func(node: Node) -> bool: return (node as MultiMeshInstance3D).multimesh.visible_instance_count == 32))
	rig.advance(0.0, telemetry)
	_check("backward clock resets sprite phase and transient pools", is_zero_approx(float(strobe_material.get_shader_parameter("local_clock"))) and spark_nodes.all(func(node: Node) -> bool: return (node as MultiMeshInstance3D).multimesh.visible_instance_count == 0))

	for cycle in 3:
		var again: Dictionary = rig.configure(aircraft, festival)
		var stage_vfx := _children_named(stage, "AircraftLightingWorldVfx")
		_check("reconfigure cycle %d reuses one kit and one VFX root" % cycle, bool(again.get("ok", false)) and rig.get_kit() == kit and stage_vfx.size() == 1 and _count_children(kit, "OmniLight3D") == 2)
	rig.dispose()
	_check("dispose releases spill and scene VFX resources but preserves aircraft", is_instance_valid(aircraft) and aircraft.get_node_or_null("NightKit") == kit and _count_children(kit, "OmniLight3D") == 0 and _children_named(stage, "AircraftLightingWorldVfx").is_empty())
	_check("dispose restores source strip overrides", (kit.get_node("strip_left") as MeshInstance3D).get_surface_override_material(0) == null)

	var strip_nodes: Array[MeshInstance3D] = []
	for child: Node in kit.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("strip_"):
			strip_nodes.append(child as MeshInstance3D)
	var strip_ids: Dictionary = {}
	for strip_node: MeshInstance3D in strip_nodes:
		strip_ids[strip_node.get_instance_id()] = true
	var groups: Dictionary = kit.get_meta("light_bindings", {})
	for group: String in groups:
		var remaining: Array = []
		for candidate: Variant in groups[group]:
			var is_removed_strip := candidate is MeshInstance3D and strip_ids.has(candidate.get_instance_id())
			if is_instance_valid(candidate) and not is_removed_strip:
				remaining.append(candidate)
		groups[group] = remaining
	kit.set_meta("light_bindings", groups)
	for strip_node: MeshInstance3D in strip_nodes:
		kit.remove_child(strip_node)
		strip_node.free()
	var missing_geometry: Dictionary = rig.configure(aircraft, festival)
	_check("missing optional strip geometry reports diagnostics", bool(missing_geometry.get("ok", false)) and _contains_warning(missing_geometry.get("warnings", []), "has no fitted NightKit geometry"))
	rig.dispose()

	var nav_left := kit.get_node("nav_left")
	var light_bindings: Dictionary = kit.get_meta("light_bindings", {})
	for group: String in light_bindings:
		var remaining: Array = []
		for candidate: Variant in light_bindings[group]:
			if candidate != nav_left and is_instance_valid(candidate):
				remaining.append(candidate)
		light_bindings[group] = remaining
	kit.set_meta("light_bindings", light_bindings)
	kit.remove_child(nav_left)
	nav_left.free()
	var optional: Dictionary = rig.configure(aircraft, festival)
	var optional_budget: Dictionary = rig.budget_info().get("vfx", {})
	_check("missing required=false anchor skips with a warning", bool(optional.get("ok", false)) and int(optional_budget.get("effects_allocated", -1)) == 1 and _contains_warning(optional.get("warnings", []), "effect anchor 'vfx_tip_left' is unavailable"))
	rig.dispose()
	var required_profile: Dictionary = festival.duplicate(true)
	for effect: Dictionary in required_profile.effects:
		if str(effect.get("anchor_id", "")) == "vfx_tip_left":
			effect["required"] = true
	var required: Dictionary = rig.configure(aircraft, required_profile)
	_check("missing required anchor fails configuration cleanly", not bool(required.get("ok", true)) and not required.get("errors", []).is_empty() and _children_named(stage, "AircraftLightingWorldVfx").is_empty())
	rig.dispose()

	var disabled_aircraft := _make_aircraft(stage, "DisabledLightingAircraft")
	var body := disabled_aircraft.get_node("Body") as MeshInstance3D
	var imported := StandardMaterial3D.new()
	imported.resource_name = "light_red"
	imported.emission_enabled = true
	imported.emission = Color("#FF241C")
	imported.emission_energy_multiplier = 1.5
	body.material_override = imported
	var disabled_profile := Profile.defaults()
	disabled_profile["selection"] = "disabled"
	var disabled_rig := Rig.new()
	var disabled_result: Dictionary = disabled_rig.configure(disabled_aircraft, disabled_profile)
	var private_material := body.get_active_material(0) as BaseMaterial3D
	_check("disabled selection shuts off private imported emission", bool(disabled_result.get("ok", false)) and private_material != imported and not private_material.emission_enabled and imported.emission_enabled and disabled_aircraft.get_node_or_null("NightKit") == null)
	disabled_rig.dispose()
	_check("disabled dispose restores emission without mutating source", private_material.emission_enabled and imported.emission_enabled and body.material_override == private_material)
	disabled_rig.dispose()
	inherited.free()
	rig.free()
	disabled_rig.free()
	stage.free()

	print("lighting rig: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_aircraft(parent: Node3D, node_name: String) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = node_name
	parent.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	return aircraft


func _add_test_strip(kit: Node3D, node_name: String) -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://render/world/led_strip.gdshader")
	material.set_shader_parameter("light_color", Color("#20B8FF"))
	material.set_shader_parameter("radiance", 0.25)
	material.set_shader_parameter("face_dir", Vector3.DOWN)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.02)
	quad.material = material
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = quad
	mesh.position = Vector3(-0.15 if node_name.ends_with("left") else 0.15, -0.08, 0.0)
	kit.add_child(mesh)


func _count_children(parent: Node, type_name: String) -> int:
	if parent == null:
		return 0
	var count := 0
	for child: Node in parent.get_children():
		if child.is_class(type_name):
			count += 1
	return count


func _children_of_type(parent: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if parent == null:
		return result
	for child: Node in parent.get_children():
		if child.is_class(type_name):
			result.append(child)
	return result


func _children_named(parent: Node, node_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if parent == null:
		return result
	for child: Node in parent.get_children():
		if child.name == node_name:
			result.append(child)
	return result


func _contains_warning(warnings: Variant, fragment: String) -> bool:
	if warnings is Array:
		for item: Variant in warnings:
			if str(item).contains(fragment):
				return true
	return false


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
