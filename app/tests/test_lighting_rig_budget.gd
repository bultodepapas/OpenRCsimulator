extends SceneTree

const Rig := preload("res://render/lighting/aircraft_lighting_rig_3d.gd")
const Profile := preload("res://render/lighting/lighting_profile.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const Patterns := preload("res://render/lighting/lighting_patterns.gd")

const STRIPS := ["strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"]
const EXPECTED_LAMP_MATERIALS := 9
const EXPECTED_STRIP_MATERIALS := 5

var _checks := 0
var _failures := 0
var _sequence_zone_ids: Array[String] = [
	"nav_left", "nav_right", "nav_tail",
	"strobe_left", "strobe_right", "strobe_dorsal", "strobe_ventral", "landing_lamp",
	"strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "LightingRigBudgetTestStage"
	root.add_child(stage)
	await process_frame

	var aircraft := _make_aircraft(stage)
	var kit := AircraftLights.attach(aircraft)
	_add_missing_strips(kit)
	var decoration := MeshInstance3D.new()
	decoration.name = "unrelated_decoration"
	decoration.mesh = BoxMesh.new()
	var decoration_material := StandardMaterial3D.new()
	decoration_material.emission_enabled = true
	decoration.material_override = decoration_material
	kit.add_child(decoration)

	var profile: Dictionary = Profile.preset("custom")
	var sequence_pattern := {
		"id": "sequence",
		"palette": ["#FFFFFF"],
		"period_ticks": 240,
		"phase_turns": 0.0,
		"floor": 1.0,
		"duty": 0.5,
		"reverse": false,
		"segments": 1,
	}
	var cue_a := {
		"id": "cue_a",
		"duration_ticks": 240,
		"pattern": {"id": "steady", "palette": ["#FF241C"], "period_ticks": 240, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1},
		"zone_ids": _sequence_zone_ids.duplicate(),
		"effect_anchor_ids": [],
	}
	var cue_b := {
		"id": "cue_b",
		"duration_ticks": 240,
		"pattern": {"id": "steady", "palette": ["#224EFF"], "period_ticks": 240, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1},
		"zone_ids": _sequence_zone_ids.duplicate(),
		"effect_anchor_ids": [],
	}
	profile["sequence"] = [cue_a, cue_b]
	for zone: Dictionary in profile.get("zones", []):
		zone["enabled"] = true
		zone["brightness"] = 1.0
		zone["pattern"] = sequence_pattern.duplicate(true)
	var checked: Dictionary = Profile.validate(profile)
	_check("maximum supported profile validates", bool(checked.get("ok", false)))

	var rig := Rig.new()
	var configured: Dictionary = rig.configure(aircraft, profile)
	_check("full semantic NightKit configures", bool(configured.get("ok", false)))
	_check("profile exposes all thirteen semantic zones to the two cues", int(rig.budget_info().get("zones_requested", -1)) == 13 and cue_a.zone_ids.size() == 13 and cue_b.zone_ids.size() == 13)
	_check("unrelated NightKit mesh is excluded and preserved", decoration.get_surface_override_material(0) == null and decoration.get_active_material(0) == decoration_material)
	_check("unrelated mesh gets an explicit skipped-binding warning", _contains_warning(rig.budget_info().get("warnings", []), "outside the supported semantic bindings"))

	var lamp_count := 0
	var strip_count := 0
	for binding: Dictionary in rig._materials:
		match str(binding.get("kind", "")):
			"steady": lamp_count += 1
			"strip": strip_count += 1
	_check("semantic material set is closed at nine lamps and five strips", lamp_count == EXPECTED_LAMP_MATERIALS and strip_count == EXPECTED_STRIP_MATERIALS)

	rig.advance(0.5, {"exposure": 10000.0})
	_check("public advance resolves the first sequence cue across strips and lamps", _all_strip_uniforms_match(rig, 0.5) and _all_steady_lamps_updated(rig, 0.5, 10000.0))

	# Force every known parameter to be considered dirty, including the three
	# pattern uniforms at the actual public cue transition. This exercises the exact bound.
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) in ["steady", "strip"]:
			binding["cache"] = {}
			if str(binding.get("kind", "")) == "strip":
				binding["pattern_signature"] = "previous-cue"
	rig.advance(1.5, {"exposure": 10000.0})
	var budget: Dictionary = rig.budget_info()
	_check("worst-case frame updates fit the closed material budget", int(budget.get("frame_parameter_writes", -1)) == int(budget.get("frame_parameter_limit", 0)))
	_check("valid maximum rig never drops a shader update", not _contains_warning(budget.get("warnings", []), "write budget was exceeded"))
	_check("all strip cue signatures commit after their uniforms", _all_strip_signatures_committed(rig, 1.5))
	_check("all strip pattern uniforms match the second cue", _all_strip_uniforms_match(rig, 1.5))
	_check("all steady lamps receive the second cue, displayed clock and exposure", _all_steady_lamps_updated(rig, 1.5, 10000.0))

	# A mode change follows a fully-budgeted advance. It gets a separate bounded
	# operation allowance and must update every material synchronously.
	rig.set_mode("all", 0.25)
	budget = rig.budget_info()
	_check("mode update has its own bounded allowance", int(budget.get("mode_parameter_writes", -1)) <= int(budget.get("mode_parameter_limit", 0)))
	_check("mode gain is fresh on every bound material after a full advance", _all_material_gains_match(rig))
	_check("mode update preserves the completed advance accounting", int(budget.get("frame_parameter_writes", -1)) == int(budget.get("frame_parameter_limit", 0)))

	# Simulate a final-cue boundary with an exhausted guard. The cue signature
	# must remain pending until all three pattern uniforms can be written.
	var strip_binding: Dictionary = _first_strip_binding(rig)
	var strip_material := strip_binding.get("material") as ShaderMaterial
	var next_pattern := {"id": "wave", "palette": ["#F68B24", "#FFFFFF"], "period_ticks": 480, "phase_turns": 0.0, "floor": 0.2, "duty": 0.5, "reverse": false, "segments": 1}
	strip_binding["pattern_signature"] = "terminal-cue"
	rig._last_frame_writes = 0
	var partial := rig._apply_pattern_uniforms(strip_material, strip_binding, next_pattern, "steady-after-terminal-cue", 0)
	_check("exhausted guard does not commit a partial cue signature", not partial and str(strip_binding.get("pattern_signature", "")) == "terminal-cue")
	rig._last_frame_writes = 0
	var retried := rig._apply_pattern_uniforms(strip_material, strip_binding, next_pattern, "steady-after-terminal-cue")
	var expected_pattern_state := Patterns.uniforms(next_pattern)
	_check("next update retries and commits every terminal-cue uniform", retried and str(strip_binding.get("pattern_signature", "")) == "steady-after-terminal-cue" and strip_material.get_shader_parameter("pattern_settings") == expected_pattern_state.pattern_settings and strip_material.get_shader_parameter("pattern_extras") == expected_pattern_state.pattern_extras and strip_material.get_shader_parameter("palette") == expected_pattern_state.palette)

	rig.dispose()
	rig.free()
	_check_alias_mesh_is_skipped(stage)
	stage.free()
	print("lighting rig budget: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_aircraft(parent: Node3D) -> Node3D:
	var aircraft := Node3D.new()
	aircraft.name = "LightingRigBudgetAircraft"
	aircraft.set_meta("light_anchors", {
		"landing": {"position": Vector3(-0.08, -0.02, -0.2)},
		"landing_right": {"position": Vector3(0.08, -0.02, -0.2)},
		"strobe_dorsal": {"position": Vector3(0.0, 0.07, 0.0)},
		"strobe_ventral": {"position": Vector3(0.0, -0.07, 0.0)},
	})
	parent.add_child(aircraft)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.12, 0.9)
	body.mesh = box
	aircraft.add_child(body)
	return aircraft


func _add_missing_strips(kit: Node3D) -> void:
	var bindings: Dictionary = kit.get_meta("light_bindings", {})
	var orientation: Array = bindings.get("orientation", [])
	for name: String in STRIPS:
		if kit.get_node_or_null(name) != null:
			continue
		var line := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(0.2, 0.01, 0.1), Vector3(0.4, 0.0, 0.0)])
		var strip: MeshInstance3D = AircraftLights.strip(name, line)
		kit.add_child(strip)
		orientation.append(strip)
	bindings["orientation"] = orientation
	AircraftLights.bind_groups(kit, bindings, ["navigation", "strobe", "landing", "orientation"])


func _first_strip_binding(rig: Node) -> Dictionary:
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) == "strip":
			return binding
	return {}


func _all_strip_signatures_committed(rig: Node, seconds: float) -> bool:
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) != "strip":
			continue
		var resolved := Patterns.resolve(binding.get("pattern", {}), seconds, rig._profile.get("sequence", []), str(binding.get("zone_id", "")))
		if str(binding.get("pattern_signature", "")) != JSON.stringify(resolved.pattern):
			return false
	return true


func _all_strip_uniforms_match(rig: Node, seconds: float) -> bool:
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) != "strip":
			continue
		var material := binding.get("material") as ShaderMaterial
		var resolved := Patterns.resolve(binding.get("pattern", {}), seconds, rig._profile.get("sequence", []), str(binding.get("zone_id", "")))
		var expected := Patterns.uniforms(resolved.pattern)
		if material.get_shader_parameter("pattern_settings") != expected.pattern_settings:
			return false
		if material.get_shader_parameter("pattern_extras") != expected.pattern_extras:
			return false
		if material.get_shader_parameter("palette") != expected.palette:
			return false
	return true


func _all_steady_lamps_updated(rig: Node, seconds: float, exposure: float) -> bool:
	for binding: Dictionary in rig._materials:
		if str(binding.get("kind", "")) != "steady":
			continue
		var material := binding.get("material") as ShaderMaterial
		if not is_equal_approx(float(material.get_shader_parameter("local_clock")), seconds):
			return false
		if not is_equal_approx(float(material.get_shader_parameter("local_exposure")), exposure):
			return false
		var expected_color: Color = Patterns.sample(binding.get("zone", {}).get("pattern", {}), seconds, 0.5, rig._profile.get("sequence", []), str(binding.get("zone_id", "")))
		if material.get_shader_parameter("light_color") != expected_color:
			return false
	return true


func _all_material_gains_match(rig: Node) -> bool:
	for binding: Dictionary in rig._materials:
		var kind := str(binding.get("kind", ""))
		if kind not in ["steady", "strip"]:
			continue
		var material := binding.get("material") as ShaderMaterial
		var expected_gain: float = float(rig._zone_gain(str(binding.get("zone_id", ""))))
		if not is_equal_approx(float(material.get_shader_parameter("effect_gain")), expected_gain):
			return false
	return true


func _contains_warning(warnings: Variant, fragment: String) -> bool:
	if warnings is Array:
		for item: Variant in warnings:
			if str(item).contains(fragment):
				return true
	return false


func _check_alias_mesh_is_skipped(parent: Node3D) -> void:
	var aircraft := Node3D.new()
	aircraft.name = "LightingAliasMeshAircraft"
	parent.add_child(aircraft)
	var kit := Node3D.new()
	kit.name = "NightKit"
	kit.set_meta("light_groups", ["navigation", "strobe", "landing", "orientation"])
	aircraft.add_child(kit)
	var alias_mesh := MeshInstance3D.new()
	alias_mesh.name = "landing_light"
	alias_mesh.mesh = QuadMesh.new()
	var original_material := StandardMaterial3D.new()
	original_material.emission_enabled = true
	alias_mesh.material_override = original_material
	kit.add_child(alias_mesh)
	var alias_rig := Rig.new()
	var alias_result: Dictionary = alias_rig.configure(aircraft, Profile.preset("classic_rc"))
	_check("landing-light alias mesh without a spot is excluded and preserved", bool(alias_result.get("ok", false)) and alias_mesh.get_surface_override_material(0) == null and alias_mesh.get_active_material(0) == original_material and _contains_warning(alias_result.get("warnings", []), "outside the supported semantic bindings"))
	alias_rig.dispose()
	alias_rig.free()


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
