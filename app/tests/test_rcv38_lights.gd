extends SceneTree

const Model := preload("res://vehicles/ground/monster_car_2_model.gd")
const Effects := preload("res://vehicles/ground/ground_effects.gd")
const Lights := preload("res://vehicles/ground/monster_car_2_lights.gd")
const Activity := preload("res://vehicles/ground/ground_scene.gd")

const LENS_NAMES := [
	"Faros", "Faros_Diurna", "Faros_Direccional", "Marcadores_Ambar",
	"LED_Frontal", "LED_Techo",
	"Focos_Antivuelco_LED", "Antiniebla_Lente", "Calaveras",
	"Neon_Lateral", "Neon_Frente_Cola", "Aleron_Gurney",
	"Carroceria_Casco", "Carroceria_Cabina", "Capo_Bulto", "Aleron_Aletas",
]
const EMISSIVE_GROUPS := {
	"head": ["Faros"],
	"running": ["Faros_Diurna", "Faros_Direccional", "Marcadores_Ambar"],
	"aux": ["LED_Frontal", "LED_Techo", "Focos_Antivuelco_LED", "Antiniebla_Lente"],
	"neon": ["Neon_Lateral", "Neon_Frente_Cola", "Aleron_Gurney",
		"Carroceria_Casco", "Carroceria_Cabina", "Capo_Bulto", "Aleron_Aletas"],
	"stop": ["Calaveras"],
}

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var visual_a: Dictionary = Model.build()
	var visual_b: Dictionary = Model.build()
	check(bool(visual_a.get("ok", false)) and bool(visual_b.get("ok", false)),
		"two independent authored Monster Car 2 visuals build")
	if not visual_a.get("ok", false) or not visual_b.get("ok", false):
		printerr(str(visual_a.get("error", "")) + " " + str(visual_b.get("error", "")))
		quit(1)
		return
	world.add_child(visual_a.root)
	world.add_child(visual_b.root)
	await process_frame

	var mesh_a := _lens_meshes(visual_a)
	var mesh_b := _lens_meshes(visual_b)
	check(mesh_a.size() == LENS_NAMES.size() and mesh_b.size() == LENS_NAMES.size(),
		"all authored head, auxiliary, tail and neon lens meshes are addressable")
	if mesh_a.size() != LENS_NAMES.size() or mesh_b.size() != LENS_NAMES.size():
		printerr("visual mesh bindings missing: " + str(_missing_lens_names(mesh_a))
			+ " / " + str(_missing_lens_names(mesh_b)))
		quit(1)
		return
	var source_a := _capture_mesh_sources(mesh_a)
	var source_b := _capture_mesh_sources(mesh_b)

	var effects_a := Effects.new()
	var effects_b := Effects.new()
	world.add_child(effects_a)
	world.add_child(effects_b)
	check(effects_a.prepare(visual_a, world), "first effects instance prepares authored lights")
	check(effects_b.prepare(visual_b, world), "second effects instance prepares authored lights")
	var component_a: Node = effects_a.get("_nitro_lights") as Node
	var component_b: Node = effects_b.get("_nitro_lights") as Node
	check(component_a is Lights and component_b is Lights,
		"each GroundEffects instance owns its own Monster Car 2 lighting component")
	if not component_a is Lights or not component_b is Lights:
		quit(1)
		return

	var nitro_lights_a := component_a as Lights
	var nitro_lights_b := component_b as Lights
	var spots_a := _spotlights(visual_a.root, nitro_lights_a)
	var spots_b := _spotlights(visual_b.root, nitro_lights_b)
	check(spots_a.size() <= 5 and spots_b.size() <= 5,
		"each vehicle uses at most five bounded SpotLights")
	var initial_lights: Dictionary = nitro_lights_a.diagnostic_snapshot()
	check(initial_lights.get("light_node_count", -1) == 5 and initial_lights.get("light_budget", -1) == 5,
		"diagnostics report the five-light budget exactly")
	check(initial_lights.get("shadow_light_count", -1) == 0,
		"diagnostics confirm that no bounded light casts shadows")
	check(int(initial_lights.get("active_lights", 99)) <= 5,
		"active light diagnostics remain within the authored light budget")
	check(_count_role(spots_a, "head") == 2 and _count_role(spots_b, "head") == 2,
		"two forward headlight spots are mounted per vehicle")
	check(_count_role(spots_a, "aux") == 1 and _count_role(spots_a, "neon") == 1
		and _count_role(spots_a, "stop") == 1,
		"the remaining spots are one auxiliary, one down-neon and one rear-stop light")

	for light: SpotLight3D in spots_a:
		check(not light.shadow_enabled, str(light.name) + " never casts shadows")
		check(light.distance_fade_enabled and is_finite(light.distance_fade_begin)
			and is_finite(light.distance_fade_length) and light.distance_fade_length > 0.0,
			str(light.name) + " has finite distance fade")
		check(is_finite(light.light_energy) and light.light_energy >= 0.0,
			str(light.name) + " starts with finite nonnegative energy")
	check(_role_points(spots_a, "head", Vector3.FORWARD), "headlights point forward")
	check(_role_points(spots_a, "aux", Vector3.FORWARD), "auxiliary spot points forward")
	check(_role_points(spots_a, "neon", Vector3.DOWN), "neon spot points down")
	check(_role_points(spots_a, "stop", Vector3.BACK, 0.7), "stop spot points rearward with downward spill")

	# The component must clone only its per-vehicle emissive material state. It may
	# use material overlays or surface overrides, but the GLB mesh and source slots
	# remain immutable and each vehicle receives separate runtime materials.
	for lens_name: String in LENS_NAMES:
		var lens_a := mesh_a.get(lens_name) as MeshInstance3D
		var lens_b := mesh_b.get(lens_name) as MeshInstance3D
		check(_source_unchanged(lens_a, source_a[lens_name]), lens_name + " keeps source mesh/material slots")
		check(_source_unchanged(lens_b, source_b[lens_name]), lens_name + " keeps second source mesh/material slots")
	for role: String in EMISSIVE_GROUPS:
		var runtime_a := _group_runtime_materials(role, mesh_a, source_a)
		var runtime_b := _group_runtime_materials(role, mesh_b, source_b)
		check(not runtime_a.is_empty() and not runtime_b.is_empty()
			and not _shares_material(runtime_a, runtime_b),
			role + " emissive materials are cloned and isolated per vehicle")

	# Head and auxiliary output follow independent switches and fade to zero in daylight.
	nitro_lights_a.observe({}, 1.0, false, false, false)
	var head_material_off := _group_emission_level("head", mesh_a, source_a)
	nitro_lights_a.observe({}, 0.0, true, false, false)
	var head_day := _role_energy(spots_a, "head")
	check(head_day > 0.0 and head_day < 2.1, "headlights dim to their low daylight level")
	nitro_lights_a.observe({}, 1.0, true, false, false)
	var head_on := _role_energy(spots_a, "head")
	check(head_on > head_day, "headlight toggle and night weight increase forward brightness")
	check(_group_emission_level("head", mesh_a, source_a) > head_material_off,
		"head lamp lens emission brightens when headlights switch on")
	check(_group_emission_level("running", mesh_a, source_a) > 0.0,
		"authored daytime and amber running lenses follow the head switch")
	nitro_lights_a.observe({}, 1.0, false, true, false)
	check(_role_energy(spots_a, "head") <= 0.000001
		and _role_energy(spots_a, "aux") > 0.0,
		"auxiliary lighting remains independent of the headlight switch")
	check(_group_emission_level("aux", mesh_a, source_a) > 0.0,
		"authored auxiliary lens emission follows its independent switch")
	check(_group_emission_level("running", mesh_a, source_a) <= 0.000001,
		"head switch also clears the running-light lens group")
	nitro_lights_a.observe({}, 1.0, false, false, true)
	check(_role_energy(spots_a, "neon") > 0.0
		and _role_energy(spots_a, "head") <= 0.000001
		and _role_energy(spots_a, "aux") <= 0.000001,
		"neon toggle is independent of headlight and auxiliary switches")
	check(_group_emission_level("neon", mesh_a, source_a) > 0.0,
		"authored underbody neon emission follows its switch")
	nitro_lights_a.observe({}, 1.0, false, false, false)
	check(_role_energy(spots_a, "neon") <= 0.000001,
		"neon switch clears its downward beam")

	# Brake lamps are red stop output only. A raw Nitro reverse request must not
	# activate a white reverse lamp or beam; UI reverse is mapped to braking above.
	nitro_lights_a.observe({"brake": 0.0, "reverse": true}, 1.0, false, false, false)
	check(_total_energy(spots_a) <= 0.000001,
		"raw reverse request produces no white reverse light")
	nitro_lights_a.observe({"brake": 1.0}, 1.0, false, false, false)
	check(_role_energy(spots_a, "stop") > 0.0
		and _role_energy(spots_a, "head") <= 0.000001,
		"braking turns on rear stop light with headlights off")
	check(_group_emission_level("stop", mesh_a, source_a) > 0.0,
		"authored rear stop lens brightens under braking")
	nitro_lights_a.observe({"brake": 0.0}, 1.0, false, false, false)
	check(_role_energy(spots_a, "stop") <= 0.000001,
		"rear stop light clears as soon as braking is released")
	check(_group_emission_level("stop", mesh_a, source_a) <= 0.000001,
		"rear stop lens emission clears as soon as braking is released")

	# Cached identical observations should not reapply node/material setters.
	var stable_controls := {"brake": 0.25, "throttle": 0.4, "steer": -0.2}
	nitro_lights_a.observe(stable_controls, 0.7, true, false, true)
	var before_repeat: Dictionary = nitro_lights_a.diagnostic_snapshot()
	nitro_lights_a.observe(stable_controls, 0.7, true, false, true)
	var after_repeat: Dictionary = nitro_lights_a.diagnostic_snapshot()
	var update_before := int(before_repeat.get("update_count", -1))
	var update_after := int(after_repeat.get("update_count", -2))
	check(update_before >= 0 and update_after == update_before,
		"identical accepted inputs are cached without material or light setter updates")

	# Invalid control values cannot contaminate render-side values or node properties.
	nitro_lights_a.observe({"brake": INF, "throttle": NAN, "steer": -INF, "reverse": true},
		NAN, true, true, true)
	var malformed_snapshot: Dictionary = nitro_lights_a.diagnostic_snapshot()
	check(_all_finite(malformed_snapshot), "malformed and non-finite controls produce finite diagnostics")
	for light: SpotLight3D in spots_a:
		check(is_finite(light.light_energy) and light.light_energy >= 0.0,
			str(light.name) + " remains finite after malformed controls")

	# A hidden body root must hide its lights too, preventing floating beams.
	visual_a.root.visible = false
	nitro_lights_a.observe({}, 1.0, true, true, true)
	for light: SpotLight3D in spots_a:
		check(not light.is_visible_in_tree() and light.light_energy <= 0.000001,
			str(light.name) + " cannot create a detached beam when its body is hidden")
	visual_a.root.visible = true

	# GroundEffects reset clears transient light states but retains user toggles.
	effects_a.headlights_enabled = false
	effects_a.auxiliary_enabled = true
	effects_a.neon_enabled = false
	effects_a.reset()
	check(not effects_a.headlights_enabled and effects_a.auxiliary_enabled and not effects_a.neon_enabled,
		"vehicle reset preserves the user's three lighting toggles")

	var controls_snapshot := stable_controls.duplicate(true)
	var accepted_state := PackedFloat64Array([0.1, -0.2, 1.4, 0.0, 0.0, 0.0, 1.0])
	var state_snapshot := accepted_state.duplicate()
	var accepted_telemetry := {"state": accepted_state, "nitro": {"engine_rpm": 7300.0, "fuel_kg": 0.18}}
	var telemetry_snapshot := accepted_telemetry.duplicate(true)
	effects_a.update_render(0.0, accepted_telemetry, stable_controls,
		Callable(self, "_sample_road"), false, 0.6)
	check(stable_controls == controls_snapshot and accepted_telemetry == telemetry_snapshot
		and accepted_state == state_snapshot,
		"lighting observation leaves accepted controls, telemetry and float64 physics state unchanged")

	await _activity_ui_test()

	print("RCV-38 lights: %d checks, %d failures" % [checks, failures])
	world.free()
	await process_frame
	quit(1 if failures else 0)


func _lens_meshes(visual: Dictionary) -> Dictionary:
	var result := {}
	var nodes: Dictionary = visual.get("_mesh_nodes", {})
	for lens_name: String in LENS_NAMES:
		var mesh: Variant = nodes.get(lens_name)
		if mesh is MeshInstance3D:
			result[lens_name] = mesh
	return result


func _missing_lens_names(meshes: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for lens_name: String in LENS_NAMES:
		if not meshes.has(lens_name):
			result.append(lens_name)
	return result


func _capture_mesh_sources(meshes: Dictionary) -> Dictionary:
	var result := {}
	for lens_name: String in meshes:
		var mesh := meshes[lens_name] as MeshInstance3D
		var surface_materials: Array[Material] = []
		var surface_overrides: Array[Material] = []
		var surface_material_states: Array[Dictionary] = []
		var surface_override_states: Array[Dictionary] = []
		if mesh.mesh != null:
			for surface in mesh.mesh.get_surface_count():
				var source_material := mesh.mesh.surface_get_material(surface)
				var override_material := mesh.get_surface_override_material(surface)
				surface_materials.append(source_material)
				surface_overrides.append(override_material)
				surface_material_states.append(_material_state(source_material))
				surface_override_states.append(_material_state(override_material))
		result[lens_name] = {
			"mesh": mesh.mesh,
			"override": mesh.material_override,
			"override_state": _material_state(mesh.material_override),
			"overlay": mesh.material_overlay,
			"surfaces": surface_materials,
			"surface_overrides": surface_overrides,
			"surface_states": surface_material_states,
			"surface_override_states": surface_override_states,
		}
	return result


func _source_unchanged(mesh: MeshInstance3D, saved: Dictionary) -> bool:
	if mesh == null or mesh.mesh != saved.get("mesh") or mesh.material_override != saved.get("override"):
		return false
	if _material_state(mesh.material_override) != saved.get("override_state", {}):
		return false
	var source_materials: Array = saved.get("surfaces", [])
	var surface_overrides: Array = saved.get("surface_overrides", [])
	var source_states: Array = saved.get("surface_states", [])
	var override_states: Array = saved.get("surface_override_states", [])
	if mesh.mesh == null or mesh.mesh.get_surface_count() != source_materials.size():
		return false
	for surface in source_materials.size():
		if mesh.mesh.surface_get_material(surface) != source_materials[surface] \
				or _material_state(mesh.mesh.surface_get_material(surface)) != source_states[surface] \
			or _material_state(surface_overrides[surface]) != override_states[surface]:
			return false
	return true


func _runtime_materials(mesh: MeshInstance3D, saved: Dictionary) -> Array[Material]:
	var result: Array[Material] = []
	var surface_overrides: Array = saved.get("surface_overrides", [])
	if mesh.material_overlay != null and mesh.material_overlay != saved.get("overlay"):
		result.append(mesh.material_overlay)
	if mesh.material_override != null and mesh.material_override != saved.get("override"):
		result.append(mesh.material_override)
	if mesh.mesh != null:
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface)
			if material != null and material != surface_overrides[surface] and not result.has(material):
				result.append(material)
	return result


func _group_runtime_materials(role: String, meshes: Dictionary, sources: Dictionary) -> Array[Material]:
	var result: Array[Material] = []
	for lens_name: String in EMISSIVE_GROUPS.get(role, []):
		var mesh := meshes.get(lens_name) as MeshInstance3D
		if mesh == null:
			continue
		for material in _runtime_materials(mesh, sources[lens_name]):
			if not result.has(material):
				result.append(material)
	return result


func _group_emission_level(role: String, meshes: Dictionary, sources: Dictionary) -> float:
	var total := 0.0
	for material in _group_runtime_materials(role, meshes, sources):
		if material is BaseMaterial3D:
			var base := material as BaseMaterial3D
			if base.emission_enabled:
				total += (base.emission.r + base.emission.g + base.emission.b) * base.emission_energy_multiplier
	return total


func _material_state(material: Material) -> Dictionary:
	if material == null:
		return {"class": "null"}
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		return {
			"class": "BaseMaterial3D",
			"albedo": base.albedo_color,
			"emission_enabled": base.emission_enabled,
			"emission": base.emission,
			"emission_energy": base.emission_energy_multiplier,
		}
	if material is ShaderMaterial:
		var shader_material := material as ShaderMaterial
		return {"class": "ShaderMaterial", "shader": shader_material.shader}
	return {"class": material.get_class(), "path": material.resource_path}


func _shares_material(first: Array[Material], second: Array[Material]) -> bool:
	for material in first:
		if second.has(material):
			return true
	return false


func _spotlights(visual_root: Node, component: Node) -> Array[SpotLight3D]:
	var result: Array[SpotLight3D] = []
	_collect_spotlights(visual_root, result)
	if component != null and component != visual_root:
		_collect_spotlights(component, result)
	return result


func _collect_spotlights(node: Node, result: Array[SpotLight3D]) -> void:
	if node is SpotLight3D and not result.has(node):
		result.append(node as SpotLight3D)
	for child in node.get_children():
		_collect_spotlights(child, result)


func _count_role(lights: Array[SpotLight3D], token: String) -> int:
	var count := 0
	for light in lights:
		if str(light.name).to_lower().contains(token):
			count += 1
	return count


func _role_points(lights: Array[SpotLight3D], role: String, direction: Vector3, minimum_dot: float = 0.9) -> bool:
	var found := 0
	for light in lights:
		if not str(light.name).to_lower().contains(role):
			continue
		found += 1
		var emitted_direction := (light.global_transform.basis * Vector3.FORWARD).normalized()
		if emitted_direction.dot(direction) < minimum_dot:
			return false
	return found > 0


func _role_energy(lights: Array[SpotLight3D], role: String) -> float:
	var total := 0.0
	for light in lights:
		if str(light.name).to_lower().contains(role):
			total += light.light_energy
	return total


func _total_energy(lights: Array[SpotLight3D]) -> float:
	var total := 0.0
	for light in lights:
		total += light.light_energy
	return total


func _all_finite(value: Variant) -> bool:
	if value is float or value is int:
		return is_finite(float(value))
	if value is Vector3:
		return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
	if value is Dictionary:
		for key in value:
			if not _all_finite(value[key]):
				return false
		return true
	if value is Array or value is PackedFloat64Array or value is PackedFloat32Array:
		for item in value:
			if not _all_finite(item):
				return false
	return true


func _sample_road(_north: float, _east: float) -> Dictionary:
	return {"surface_id": "asphalt", "height_m": 0.0, "water_depth_m": 0.0, "water_height_m": 0.0}


func _activity_ui_test() -> void:
	var previous_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	var english: Variant = _new_test_activity("monster-car-2")
	root.add_child(english)
	await process_frame
	await process_frame
	english.set_process(false)
	english.set_physics_process(false)
	check(english.startup_error.is_empty() and english.session.tick == 0,
		"nitro Activity prepares with audio/course visuals disabled and no physics ticks")
	check(english._environment != null and english._environment.glow_enabled,
		"Nitro Activity enables local Environment glow for its authored emissive lamps")
	check(english._nitro_sound == null and english._sound == null,
		"lighting Activity test does not create engine audio")
	check(english._effects.headlights_enabled and not english._effects.auxiliary_enabled
		and english._effects.neon_enabled,
		"English Activity starts with headlights and neon on and auxiliary lights off")
	english.dashboard.update_lights(english._effects.headlights_enabled,
		english._effects.auxiliary_enabled, english._effects.neon_enabled)
	check(english.dashboard.headlights_button.text == "Headlights on · L"
		and english.dashboard.auxiliary_button.text == "Auxiliary lights off · K"
		and english.dashboard.neon_button.text == "Neon on · N",
		"English dashboard shows all three default light labels")
	english.handle_action("aux_lights")
	english.handle_action("neon")
	check(english._effects.auxiliary_enabled and not english._effects.neon_enabled
		and english.dashboard.auxiliary_button.text == "Auxiliary lights on · K"
		and english.dashboard.neon_button.text == "Neon off · N",
		"auxiliary and neon actions route through English dashboard toggles")
	english.queue_free()
	await process_frame

	TranslationServer.set_locale("es")
	var spanish: Variant = _new_test_activity("monster-car-2")
	root.add_child(spanish)
	await process_frame
	await process_frame
	spanish.set_process(false)
	spanish.set_physics_process(false)
	check(spanish.startup_error.is_empty() and spanish.session.tick == 0,
		"Spanish nitro Activity also prepares without advancing physics")
	spanish.dashboard.update_lights(spanish._effects.headlights_enabled,
		spanish._effects.auxiliary_enabled, spanish._effects.neon_enabled)
	check(spanish.dashboard.headlights_button.text == "Faros encendidos · L"
		and spanish.dashboard.auxiliary_button.text == "Exploradoras apagadas · K"
		and spanish.dashboard.neon_button.text == "Neón encendido · N",
		"Spanish dashboard shows localized default light labels")
	spanish.handle_action("aux_lights")
	spanish.handle_action("neon")
	check(spanish._effects.auxiliary_enabled and not spanish._effects.neon_enabled
		and spanish.dashboard.auxiliary_button.text == "Exploradoras encendidas · K"
		and spanish.dashboard.neon_button.text == "Neón apagado · N",
		"auxiliary and neon actions route through Spanish dashboard toggles")
	spanish.queue_free()
	await process_frame

	TranslationServer.set_locale("en")
	var bisonte: Variant = _new_test_activity("mt8-bisonte")
	root.add_child(bisonte)
	await process_frame
	await process_frame
	bisonte.set_process(false)
	bisonte.set_physics_process(false)
	check(bisonte.startup_error.is_empty() and bisonte._environment != null
		and not bisonte._environment.glow_enabled,
		"Bisonte Activity keeps Environment glow disabled")
	check(bisonte.dashboard.auxiliary_button == null and bisonte.dashboard.neon_button == null,
		"Bisonte dashboard does not expose Nitro-only light actions")
	var aux_before: bool = bisonte._effects.auxiliary_enabled
	var neon_before: bool = bisonte._effects.neon_enabled
	bisonte.handle_action("aux_lights")
	bisonte.handle_action("neon")
	check(bisonte._effects.auxiliary_enabled == aux_before and bisonte._effects.neon_enabled == neon_before,
		"Nitro-only light action routes leave Bisonte settings untouched")
	bisonte.queue_free()
	await process_frame
	TranslationServer.set_locale(previous_locale)


func _new_test_activity(id: String) -> Variant:
	var activity = Activity.new()
	activity.vehicle_id = id
	activity.enable_audio = false
	activity.enable_course_visual = false
	activity.use_practice_fixture = true
	activity.checkpoint_path = "user://rcv/rcv38-lights-%s.json" % id
	activity.set_process(false)
	activity.set_physics_process(false)
	return activity


