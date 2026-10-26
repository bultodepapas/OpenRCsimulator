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
	var zones_off_profile: Dictionary = festival.duplicate(true)
	for zone: Dictionary in zones_off_profile.get("zones", []):
		if str(zone.get("id", "")).begins_with("strip_"):
			zone["enabled"] = false
	var zones_off_result: Dictionary = rig.configure(aircraft, zones_off_profile)
	var zones_off_vfx: Dictionary = rig.budget_info().get("vfx", {})
	_check("disabled strip zones allocate no spill", bool(zones_off_result.get("ok", false)) and int(zones_off_vfx.get("spill_lights_allocated", -1)) == 0)
	rig.dispose()

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

	var limited_aircraft := _make_aircraft(stage, "TimberCapabilityLightingAircraft")
	limited_aircraft.set_meta("light_groups", ["navigation", "strobe", "landing"])
	limited_aircraft.set_meta("light_anchors", {
		"landing": {"position": Vector3(-0.08, -0.02, -0.2), "gear_gated": true},
		"landing_right": {"position": Vector3(0.08, -0.02, -0.2), "gear_gated": true},
	})
	var limited_kit := AircraftLights.attach(limited_aircraft)
	var limited_left_beam := limited_kit.get_node("landing_light") as SpotLight3D
	var limited_right_beam := limited_kit.get_node("landing_light_right") as SpotLight3D
	var left_beam_energy := limited_left_beam.light_energy
	var right_beam_energy := limited_right_beam.light_energy
	for strip_name: String in ["strip_left", "strip_right"]:
		if limited_kit.get_node_or_null(strip_name) == null:
			_add_test_strip(limited_kit, strip_name)
	var limited_bindings: Dictionary = limited_kit.get_meta("light_bindings", {})
	var orientation_bindings: Array = limited_bindings.get("orientation", [])
	for child: Node in limited_kit.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("strip_") and child not in orientation_bindings:
			orientation_bindings.append(child)
	limited_bindings["orientation"] = orientation_bindings
	AircraftLights.bind_groups(limited_kit, limited_bindings, ["navigation", "strobe", "landing"])
	var timber_profile: Dictionary = Profile.preset("neon_rgb")
	var classic_profile: Dictionary = Profile.preset("classic_rc")
	for zone: Dictionary in classic_profile.get("zones", []):
		if str(zone.get("id", "")) == "landing_lamp":
			var disabled_landing: Dictionary = zone.duplicate(true)
			disabled_landing["enabled"] = false
			timber_profile["zones"].append(disabled_landing)
	var limited_rig := Rig.new()
	var limited_result: Dictionary = limited_rig.configure(limited_aircraft, timber_profile)
	limited_rig.set_mode("all")
	_check("unsupported orientation capability suppresses strips and spill", bool(limited_result.get("ok", false)) and not (limited_kit.get_node("strip_left") as MeshInstance3D).visible and not (limited_kit.get_node("strip_right") as MeshInstance3D).visible and int(limited_rig.budget_info().get("vfx", {}).get("spill_lights_allocated", -1)) == 0)
	var landing_nodes: Array[Node3D] = [
		limited_kit.get_node("landing_lamp") as Node3D,
		limited_kit.get_node("landing_lamp_right") as Node3D,
		limited_left_beam,
		limited_right_beam,
	]
	for landing_node: Node3D in landing_nodes:
		landing_node.set_meta("gate_open", false)
	AircraftLights.update_dynamic(limited_kit, limited_aircraft, 1.0)
	_check("gear update exposes the disabled landing group before profile reconciliation", landing_nodes.all(func(node: Node3D) -> bool: return node.visible))
	limited_rig.advance(0.0)
	_check("same-frame profile reconciliation keeps disabled landing lamps and beams dark", landing_nodes.all(func(node: Node3D) -> bool: return not node.visible) and is_zero_approx(limited_left_beam.light_energy) and is_zero_approx(limited_right_beam.light_energy))
	var enabled_landing_profile: Dictionary = timber_profile.duplicate(true)
	enabled_landing_profile["brightness"] = 1.0
	for zone: Dictionary in enabled_landing_profile.get("zones", []):
		if str(zone.get("id", "")) == "landing_lamp":
			zone["enabled"] = true
			zone["brightness"] = 0.25
	var enabled_landing_result: Dictionary = limited_rig.configure(limited_aircraft, enabled_landing_profile)
	limited_rig.set_mode("all")
	_check("canonical landing zone brightness controls both paired beams", bool(enabled_landing_result.get("ok", false)) and limited_left_beam.visible and limited_right_beam.visible and is_equal_approx(limited_left_beam.light_energy, left_beam_energy * 0.25) and is_equal_approx(limited_right_beam.light_energy, right_beam_energy * 0.25) and (limited_kit.get_node("landing_lamp_right") as MeshInstance3D).visible)
	limited_rig.dispose()
	limited_rig.free()

	var pattern_aircraft := _make_aircraft(stage, "LightingPatternAircraft")
	pattern_aircraft.set_meta("light_material_groups", {"light_red": "navigation", "light_green": "navigation", "light_custom": "navigation"})
	var red_lens := _add_emission_lens(pattern_aircraft, "ImportedRedLens", "light_red")
	var green_lens := _add_emission_lens(pattern_aircraft, "ImportedGreenLens", "light_green")
	var custom_lens := _add_emission_lens(pattern_aircraft, "ImportedCustomLens", "light_custom")
	var pattern_kit := AircraftLights.attach(pattern_aircraft)
	AircraftLights.set_mode(pattern_kit, "off")
	var pattern_profile: Dictionary = Profile.preset("classic_rc")
	for zone: Dictionary in pattern_profile.get("zones", []):
		match str(zone.get("id", "")):
			"nav_left": zone["enabled"] = false
			"nav_right": zone["brightness"] = 0.25
			"nav_tail":
				zone["pattern"] = {"id": "wave", "palette": ["#FF241C", "#224EFF"], "period_ticks": 240, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1}
	var pattern_rig := Rig.new()
	var pattern_result: Dictionary = pattern_rig.configure(pattern_aircraft, pattern_profile)
	pattern_rig.set_mode("all")
	var nav_tail_material := (pattern_kit.get_node("nav_tail") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	var nav_right_material := (pattern_kit.get_node("nav_right") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	var pattern_strobe_material := (pattern_kit.get_node("strobe_left") as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
	var red_emission := red_lens.get_active_material(0) as BaseMaterial3D
	var green_emission := green_lens.get_active_material(0) as BaseMaterial3D
	var custom_emission := custom_lens.get_active_material(0) as BaseMaterial3D
	pattern_rig.advance(0.0)
	var nav_tail_phase_zero: Color = nav_tail_material.get_shader_parameter("light_color")
	pattern_rig.advance(0.25)
	var nav_tail_phase_quarter: Color = nav_tail_material.get_shader_parameter("light_color")
	var nav_tail_flash: Vector4 = nav_tail_material.get_shader_parameter("flash")
	var classic_strobe_flash: Vector4 = pattern_strobe_material.get_shader_parameter("flash")
	_check("reused OFF kit opens profile-enabled lamps", bool(pattern_result.get("ok", false)) and (pattern_kit.get_node("nav_right") as MeshInstance3D).visible)
	_check("animated lamp samples the selected pattern and disables its legacy flash", nav_tail_phase_zero != nav_tail_phase_quarter and is_zero_approx(nav_tail_flash.w))
	_check("steady classic strobe preserves its legacy flash", classic_strobe_flash.w > 0.5)
	_check("known imported lenses follow their zone enabled and brightness values", not red_emission.emission_enabled and green_emission.emission_enabled and is_equal_approx(green_emission.emission_energy_multiplier, 0.5) and green_emission.emission == Color("#22E85B"))
	_check("unknown imported material reports group-only zone control", custom_emission.emission_enabled and _contains_warning(pattern_rig.budget_info().get("warnings", []), "no individual zone mapping"))
	var all_navigation_off: Dictionary = Profile.preset("classic_rc")
	for zone: Dictionary in all_navigation_off.get("zones", []):
		if str(zone.get("id", "")).begins_with("nav_"):
			zone["enabled"] = false
	var group_off_result: Dictionary = pattern_rig.configure(pattern_aircraft, all_navigation_off)
	pattern_rig.set_mode("all")
	_check("disabling every navigation zone disables unmapped imported emissions", bool(group_off_result.get("ok", false)) and not custom_emission.emission_enabled)
	pattern_rig.dispose()
	pattern_rig.free()

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


func _add_emission_lens(parent: Node3D, node_name: String, material_name: String) -> MeshInstance3D:
	var lens := MeshInstance3D.new()
	lens.name = node_name
	lens.mesh = SphereMesh.new()
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 2.0
	lens.material_override = material
	parent.add_child(lens)
	return lens


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
