extends Node3D
class_name AircraftLightingRig3D
## Render-owned facade over the single existing NightKit. This node never owns or frees the aircraft root.

const Profile := preload("res://render/lighting/lighting_profile.gd")
const AircraftLights := preload("res://render/world/aircraft_lights.gd")
const Patterns := preload("res://render/lighting/lighting_patterns.gd")
const LightingVfx := preload("res://render/lighting/lighting_vfx.gd")
const RGB_STRIP_SHADER := preload("res://render/lighting/rgb_strip.gdshader")
const RGB_LAMP_SHADER := preload("res://render/lighting/rgb_lamp.gdshader")

const MAX_FRAME_PARAMETER_WRITES := 48
const STRIP_NAMES := ["strip_left", "strip_right", "strip_top_left", "strip_top_right", "strip_belly"]
const MODE_IDS := ["all", "nav", "off"]

var root: Node3D
var kit: Node3D
var _profile: Dictionary = {}
var _zones: Dictionary = {}
var _materials: Array[Dictionary] = []
var _mode := "all"
var _previous_mode := "all"
var _gain := 1.0
var _profile_brightness := 1.0
var _disabled := false
var _active := false
var _last_seconds := -1.0
var _last_frame_writes := 0
var _vfx: RefCounted
var _emission_bindings: Dictionary = {}
var _previous_emission_mode := "all"
var _previous_emission_gain := 1.0
var _warnings: Array[String] = []


## Validates and stages one accepted profile. Inherit is deliberately lazy and does not attach a NightKit.
func configure(aircraft_root: Node3D, raw_profile: Dictionary) -> Dictionary:
	if aircraft_root == null or not is_instance_valid(aircraft_root):
		return {"ok": false, "errors": ["aircraft root is unavailable"], "warnings": []}
	var checked: Dictionary = Profile.validate(raw_profile)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "errors": checked.get("errors", ["invalid lighting profile"]), "warnings": []}

	var candidate: Dictionary = checked.profile
	var selection := str(candidate.get("selection", "inherit"))
	var existing := aircraft_root.get_node_or_null("NightKit") as Node3D
	var requested_mode := str(existing.get_meta("mode", "all")) if existing != null else "all"
	var baseline_mode := requested_mode
	var baseline_emission_mode := requested_mode
	var baseline_emission_gain := 1.0
	if _active and root == aircraft_root:
		requested_mode = _mode
		baseline_mode = _previous_mode
		baseline_emission_mode = _previous_emission_mode
		baseline_emission_gain = _previous_emission_gain
	dispose()

	root = aircraft_root
	_profile = candidate.duplicate(true)
	_profile_brightness = float(candidate.get("brightness", 1.0))
	_disabled = selection == "disabled"
	_zones = _zone_map(candidate.get("zones", []))
	_warnings.append_array(checked.get("warnings", []))
	_previous_mode = baseline_mode if baseline_mode in MODE_IDS else "all"
	_previous_emission_mode = baseline_emission_mode if baseline_emission_mode in MODE_IDS else _previous_mode
	_previous_emission_gain = clampf(baseline_emission_gain, 0.0, 2.0)
	_mode = requested_mode if requested_mode in MODE_IDS else "all"
	_gain = 1.0
	_last_seconds = -1.0

	if selection == "inherit":
		_active = false
		_disabled = false
		return {"ok": true, "errors": [], "warnings": _warnings.duplicate()}

	_active = true
	if selection == "disabled":
		kit = existing
		_emission_bindings = AircraftLights.prepare_emission(root)
		_capture_emission_baseline(requested_mode)
		_mode = "off"
		AircraftLights.set_emission_mode(_emission_bindings, "off", 0.0)
		if is_instance_valid(kit):
			AircraftLights.set_mode(kit, "off")
		return {"ok": true, "errors": [], "warnings": _warnings.duplicate()}

	kit = AircraftLights.attach(aircraft_root)
	if kit == null or not is_instance_valid(kit):
		dispose()
		return {"ok": false, "errors": ["existing aircraft light kit could not be attached"], "warnings": []}
	_previous_mode = baseline_mode if baseline_mode in MODE_IDS else str(kit.get_meta("mode", "all"))
	_emission_bindings = AircraftLights.prepare_emission(root)
	_capture_emission_baseline(requested_mode)
	_apply_profile_materials()

	_vfx = LightingVfx.new()
	var vfx_result: Dictionary = _vfx.configure(root, kit, _profile)
	_warnings.append_array(vfx_result.get("warnings", []))
	var vfx_errors: Array = vfx_result.get("errors", [])
	if not vfx_errors.is_empty():
		var failure := {"ok": false, "errors": vfx_errors.duplicate(), "warnings": _warnings.duplicate()}
		dispose()
		return failure
	set_mode(_mode, 1.0)
	return {"ok": true, "errors": [], "warnings": _warnings.duplicate()}


## Applies the legacy ALL / NAV / OFF policy and a bounded brightness gain.
func set_mode(mode: String, gain := 1.0) -> void:
	if mode not in MODE_IDS or not is_finite(gain):
		return
	var next_mode := "off" if _disabled else mode
	var next_gain := clampf(gain, 0.0, 2.0)
	_mode = next_mode
	_gain = next_gain
	if not _active:
		return
	if is_instance_valid(kit):
		AircraftLights.set_mode(kit, _mode)
	_apply_emission_mode()
	_reapply_profile_visibility()
	var supported_groups := _supported_light_groups()
	for binding: Dictionary in _materials:
		var node: Node3D = binding.get("node")
		if not is_instance_valid(node):
			continue
		var group := str(binding.get("group", "orientation"))
		var group_on := group in supported_groups and (_mode == "all" or (_mode == "nav" and group in ["navigation", "strobe"]))
		var gate_open := bool(node.get_meta("gate_open", true))
		var show_binding := bool(binding.get("original_visible", true)) and bool(binding.get("enabled", true)) and gate_open and group_on
		node.visible = show_binding
		if str(binding.get("kind", "")) == "spot":
			var light := node as Light3D
			if is_instance_valid(light):
				var light_zone: Dictionary = binding.get("zone", {})
				light.light_color = Patterns.sample(light_zone.get("pattern", {}), 0.0, 0.5, _profile.get("sequence", []), str(binding.get("zone_id", "")))
				light.light_energy = float(binding.get("base_energy", 0.0)) * _zone_gain(str(binding.get("zone_id", ""))) if show_binding else 0.0
			continue
		var material: ShaderMaterial = binding.get("material")
		if not is_instance_valid(material):
			continue
		if str(binding.get("kind", "")) == "strip":
			_set_param(material, binding, "effect_gain", _zone_gain(str(binding.get("zone_id", ""))))
		else:
			_set_param(material, binding, "radiance", float(binding.get("base_radiance", 1.0)))
			_set_param(material, binding, "effect_gain", _zone_gain(str(binding.get("zone_id", ""))))
	if _vfx != null:
		_vfx.set_mode(_mode, _gain)


## Advances all visual clocks from the already displayed pose; no simulation object is read here.
func advance(presentation_seconds: float, telemetry: Dictionary = {}) -> void:
	_last_frame_writes = 0
	if not _active or _disabled or not is_instance_valid(kit) or not is_finite(presentation_seconds):
		return
	_reapply_profile_visibility()
	var seconds := maxf(0.0, presentation_seconds)
	if _last_seconds >= 0.0 and seconds < _last_seconds:
		reset()
	var exposure := _number_or(telemetry.get("exposure", 1.0), 1.0, 0.0001, 1000000.0)
	for binding: Dictionary in _materials:
		var bound_node: Node3D = binding.get("node")
		if not is_instance_valid(bound_node):
			continue
		if str(binding.get("kind", "")) == "spot":
			var light := bound_node as Light3D
			if not is_instance_valid(light):
				continue
			var spot_zone: Dictionary = binding.get("zone", {})
			light.light_color = Patterns.sample(spot_zone.get("pattern", {}), seconds, 0.5, _profile.get("sequence", []), str(binding.get("zone_id", "")))
			var spot_reaction := Patterns.reactive_multiplier(spot_zone.get("reactive", {}), telemetry)
			var spot_group := str(binding.get("group", ""))
			var spot_show := bool(binding.get("enabled", false)) and spot_group in _supported_light_groups() \
				and (_mode == "all" or (_mode == "nav" and spot_group in ["navigation", "strobe"])) \
				and bool(light.get_meta("gate_open", true)) and bool(binding.get("original_visible", true))
			light.visible = spot_show
			light.light_energy = float(binding.get("base_energy", 0.0)) * _zone_gain(str(binding.get("zone_id", ""))) * float(spot_reaction.get("multiplier", 1.0)) if spot_show else 0.0
			continue
		if not is_instance_valid(binding.get("material")):
			continue
		var material: ShaderMaterial = binding.material
		if str(binding.get("kind", "")) == "steady":
			_set_param(material, binding, "local_clock", seconds)
			_set_param(material, binding, "local_exposure", exposure)
			var steady_zone: Dictionary = binding.get("zone", {})
			var steady_zone_id := str(binding.get("zone_id", ""))
			var steady_pattern: Dictionary = steady_zone.get("pattern", {})
			if not steady_pattern.is_empty():
				var steady_color := Patterns.sample(steady_pattern, seconds, 0.5, _profile.get("sequence", []), steady_zone_id)
				_set_param(material, binding, "light_color", steady_color)
				if str(steady_pattern.get("id", "steady")) != "steady":
					_set_param(material, binding, "flash", Vector4(1.0, 0.0, 0.0, 0.0))
			var steady_reaction := Patterns.reactive_multiplier(steady_zone.get("reactive", {}), telemetry)
			if not bool(steady_reaction.get("available", true)):
				var steady_source := str((steady_zone.get("reactive", {}) as Dictionary).get("source", "none"))
				var steady_warning := "reactive source '%s' is unavailable; base pattern remains active" % steady_source
				if steady_source != "none" and not _warnings.has(steady_warning):
					_warnings.append(steady_warning)
			var steady_scale := _zone_gain(steady_zone_id) * float(steady_reaction.get("multiplier", 1.0))
			_set_param(material, binding, "radiance", float(binding.get("base_radiance", 1.0)))
			_set_param(material, binding, "effect_gain", steady_scale)
			continue
		if str(binding.get("kind", "")) != "strip" or not bool(binding.get("enabled", false)):
			continue
		var zone_id := str(binding.get("zone_id", ""))
		var zone: Dictionary = binding.get("zone", {})
		var resolved := Patterns.resolve(binding.get("pattern", {}), seconds, _profile.get("sequence", []), zone_id)
		var active_pattern: Dictionary = resolved.get("pattern", {})
		var signature := JSON.stringify(active_pattern)
		if signature != str(binding.get("pattern_signature", "")):
			var shader_state := Patterns.uniforms(active_pattern)
			_set_param(material, binding, "pattern_settings", shader_state.pattern_settings)
			_set_param(material, binding, "pattern_extras", shader_state.pattern_extras)
			_set_param(material, binding, "palette", shader_state.palette)
			binding["pattern_signature"] = signature
		_set_param(material, binding, "pattern_phase", float(resolved.get("phase", 0.0)))
		_set_param(material, binding, "local_exposure", exposure)
		var reaction := Patterns.reactive_multiplier(zone.get("reactive", {}), telemetry)
		if not bool(reaction.get("available", true)):
			var reactive: Dictionary = zone.get("reactive", {})
			var source := str(reactive.get("source", "none"))
			var warning := "reactive source '%s' is unavailable; base pattern remains active" % source
			if source != "none" and not _warnings.has(warning):
				_warnings.append(warning)
		var scale := _zone_gain(zone_id) * float(reaction.get("multiplier", 1.0))
		_set_param(material, binding, "effect_gain", scale)
	_apply_profile_emission(seconds, telemetry)
	if _vfx != null:
		_vfx.advance(seconds, telemetry)
	_last_seconds = seconds
	if _last_frame_writes > MAX_FRAME_PARAMETER_WRITES:
		var warning := "frame parameter update limit exceeded; later updates were skipped"
		if not _warnings.has(warning):
			_warnings.append(warning)


func reset() -> void:
	_last_seconds = -1.0
	_last_frame_writes = 0
	for binding: Dictionary in _materials:
		var material: ShaderMaterial = binding.get("material")
		if not is_instance_valid(material):
			continue
		material.set_shader_parameter("pattern_phase", 0.0)
		var cache: Dictionary = binding.get("cache", {})
		cache.erase("pattern_phase")
		if str(binding.get("kind", "")) == "steady":
			material.set_shader_parameter("local_clock", 0.0)
			cache.erase("local_clock")
		binding["cache"] = cache
		binding["pattern_signature"] = ""
	if _vfx != null:
		_vfx.reset()


## Restores only resources and overrides owned by this facade; it never frees the aircraft root or kit.
func dispose() -> void:
	_restore_materials()
	if _vfx != null:
		_vfx.dispose()
		_vfx = null
	if _active and is_instance_valid(kit):
		AircraftLights.set_mode(kit, _previous_mode if _previous_mode in MODE_IDS else "all")
	if not _emission_bindings.is_empty():
		_restore_emission_colors()
		_emission_bindings["mode"] = ""
		AircraftLights.set_emission_mode(_emission_bindings, _previous_emission_mode if _previous_emission_mode in MODE_IDS else "all", _previous_emission_gain)
	_materials.clear()
	_zones.clear()
	_profile.clear()
	root = null
	kit = null
	_emission_bindings = {}
	_active = false
	_disabled = false
	_last_seconds = -1.0
	_last_frame_writes = 0
	_warnings.clear()


func budget_info() -> Dictionary:
	var vfx_info: Dictionary = _vfx.budget_info() if _vfx != null else {
		"effects_allocated": 0,
		"sparks_allocated": 0,
		"trails_allocated": 0,
		"spill_lights_allocated": 0,
	}
	return {
		"active": _active,
		"selection": str(_profile.get("selection", "inherit")),
		"zones_requested": _zones.size(),
		"zones_resolved": _materials.filter(func(item: Dictionary) -> bool: return str(item.get("kind", "")) == "strip" and bool(item.get("enabled", false))).size(),
		"frame_parameter_writes": _last_frame_writes,
		"frame_parameter_limit": MAX_FRAME_PARAMETER_WRITES,
		"warnings": _warnings.duplicate(),
		"vfx": vfx_info,
	}


func get_kit() -> Node3D:
	if is_instance_valid(kit):
		return kit
	if is_instance_valid(root):
		return root.get_node_or_null("NightKit") as Node3D
	return null


func luminous_nodes() -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	var target := get_kit()
	if not is_instance_valid(target):
		return result
	for child: Node in target.get_children():
		if child is MeshInstance3D:
			result.append(child as VisualInstance3D)
	return result


func _apply_profile_materials() -> void:
	if not is_instance_valid(kit):
		return
	var seen_zones: Dictionary = {}
	for node: Node in kit.get_children():
		if node is Light3D:
			var light_node := node as Light3D
			var light_zone_id := _canonical_zone_id(str(light_node.name))
			var light_zone: Dictionary = _zones.get(light_zone_id, {})
			if light_zone_id != "landing_lamp" or light_zone.is_empty():
				continue
			seen_zones[light_zone_id] = true
			_materials.append({
				"node": light_node,
				"kind": "spot",
				"zone_id": light_zone_id,
				"zone": light_zone,
				"enabled": bool(light_zone.get("enabled", true)),
				"group": "landing",
				"original_visible": _profile_node_author_visible(light_node, "landing"),
				"base_energy": light_node.light_energy,
				"base_color": light_node.light_color,
			})
			continue
		if not node is MeshInstance3D:
			continue
		var mesh_node := node as MeshInstance3D
		var node_zone_id := str(mesh_node.name)
		var zone_id := _canonical_zone_id(node_zone_id)
		var zone: Dictionary = _zones.get(zone_id, {})
		var enabled := bool(zone.get("enabled", true))
		var original_visible := _profile_node_author_visible(mesh_node, "orientation" if STRIP_NAMES.has(node_zone_id) else _group_for(zone_id))
		var prior := mesh_node.get_surface_override_material(0)
		var source := mesh_node.get_active_material(0) as ShaderMaterial
		if STRIP_NAMES.has(node_zone_id):
			seen_zones[zone_id] = true
			if zone.is_empty():
				_materials.append({
					"node": mesh_node,
					"surface": 0,
					"prior": prior,
					"material": source,
					"kind": "strip",
					"zone_id": zone_id,
					"zone": {},
					"pattern": {},
					"pattern_signature": "",
					"enabled": false,
					"group": "orientation",
					"original_visible": original_visible,
					"base_radiance": 0.0,
					"cache": {},
				})
				continue
			if mesh_node.mesh == null or mesh_node.mesh.get_surface_count() == 0:
				_warnings.append("strip zone '%s' has no render surface; it was skipped" % zone_id)
				continue
			if source == null:
				_warnings.append("strip zone '%s' has no compatible source material; it was skipped" % zone_id)
				continue
			var material := ShaderMaterial.new()
			material.shader = RGB_STRIP_SHADER
			var original_color := _color(_shader_value(source, "light_color", Color.WHITE), Color.WHITE)
			var pattern: Dictionary = zone.get("pattern", _default_pattern(original_color))
			var initial := Patterns.uniforms(pattern)
			material.set_shader_parameter("pattern_settings", initial.pattern_settings)
			material.set_shader_parameter("pattern_extras", initial.pattern_extras)
			material.set_shader_parameter("palette", initial.palette)
			material.set_shader_parameter("pattern_phase", 0.0)
			material.set_shader_parameter("effect_gain", _zone_gain(zone_id))
			material.set_shader_parameter("local_exposure", 1.0)
			material.set_shader_parameter("face_dir", _shader_value(source, "face_dir", Vector3.DOWN))
			material.set_shader_parameter("radiance", _number_or(_shader_value(source, "radiance", 0.25), 0.25, 0.0, 20.0))
			material.set_shader_parameter("width_m", _number_or(_shader_value(source, "width_m", 0.015), 0.015, 0.001, 0.25))
			material.set_shader_parameter("min_px", _number_or(_shader_value(source, "min_px", 2.0), 2.0, 0.0, 8.0))
			material.set_shader_parameter("display_cap", _number_or(_shader_value(source, "display_cap", 2.0), 2.0, 0.1, 20.0))
			var axis := _axis_for(zone_id)
			material.set_shader_parameter("axis_dir", axis)
			material.set_shader_parameter("axis_range", _axis_range(mesh_node.mesh, axis))
			mesh_node.set_surface_override_material(0, material)
			_materials.append({
				"node": mesh_node,
				"surface": 0,
				"prior": prior,
				"material": material,
				"kind": "strip",
				"zone_id": zone_id,
				"zone": zone,
				"pattern": pattern,
				"pattern_signature": JSON.stringify(pattern),
				"enabled": enabled,
				"group": "orientation",
				"original_visible": original_visible,
				"base_radiance": _number_or(_shader_value(source, "radiance", 0.25), 0.25, 0.0, 20.0),
				"cache": {},
			})
			continue
		if source == null or source.shader == null:
			continue
		var lamp := ShaderMaterial.new()
		lamp.shader = RGB_LAMP_SHADER
		lamp.set_shader_parameter("vfx_mode", 0.0)
		lamp.set_shader_parameter("light_color", _profile_color(zone, source))
		lamp.set_shader_parameter("radiance", _number_or(_shader_value(source, "radiance", 2.5), 2.5, 0.0, 100.0))
		lamp.set_shader_parameter("effect_gain", _zone_gain(zone_id))
		lamp.set_shader_parameter("size_m", _number_or(_shader_value(source, "size_m", 0.025), 0.025, 0.001, 1.0))
		lamp.set_shader_parameter("min_px", _number_or(_shader_value(source, "min_px", 4.0), 4.0, 0.0, 32.0))
		lamp.set_shader_parameter("flash", _shader_value(source, "flash", Vector4(1.0, 0.0, 0.0, 0.0)))
		lamp.set_shader_parameter("display_cap", _number_or(_shader_value(source, "display_cap", 2.5), 2.5, 0.1, 100.0))
		lamp.set_shader_parameter("local_exposure", 1.0)
		lamp.set_shader_parameter("local_clock", 0.0)
		var lamp_zone := _is_lamp_zone(node_zone_id)
		if lamp_zone and not zone.is_empty():
			seen_zones[zone_id] = true
		mesh_node.set_surface_override_material(0, lamp)
		_materials.append({
			"node": mesh_node,
			"surface": 0,
			"prior": prior,
			"material": lamp,
			"kind": "steady",
			"zone_id": zone_id,
			"zone": zone,
			"enabled": enabled,
			"group": _group_for(zone_id),
			"original_visible": original_visible,
			"base_radiance": _number_or(_shader_value(source, "radiance", 2.5), 2.5, 0.0, 100.0),
			"cache": {},
		})
	for zone_id: String in _zones:
		if seen_zones.has(zone_id):
			continue
		if STRIP_NAMES.has(zone_id):
			_warnings.append("strip zone '%s' has no fitted NightKit geometry; it was skipped" % zone_id)
		elif kit.get_node_or_null(zone_id) == null:
			_warnings.append("lighting zone '%s' has no fitted NightKit anchor; legacy hardware remains unchanged" % zone_id)


func _restore_materials() -> void:
	for binding: Dictionary in _materials:
		var node: Node3D = binding.get("node")
		if is_instance_valid(node):
			if str(binding.get("kind", "")) == "spot":
				var light := node as Light3D
				if is_instance_valid(light):
					light.light_energy = float(binding.get("base_energy", light.light_energy))
					light.light_color = binding.get("base_color", light.light_color)
			elif node is MeshInstance3D:
				(node as MeshInstance3D).set_surface_override_material(int(binding.get("surface", 0)), binding.get("prior"))
			node.visible = bool(binding.get("original_visible", true))
	_materials.clear()


func _set_param(material: ShaderMaterial, binding: Dictionary, key: StringName, value: Variant) -> void:
	var cache: Dictionary = binding.get("cache", {})
	if cache.has(key) and cache[key] == value:
		return
	if _last_frame_writes >= MAX_FRAME_PARAMETER_WRITES:
		return
	material.set_shader_parameter(key, value)
	cache[key] = value
	binding["cache"] = cache
	_last_frame_writes += 1


func _zone_gain(zone_id: String) -> float:
	var zone: Dictionary = _zones.get(zone_id, {})
	var brightness := _number_or(zone.get("brightness", 1.0), 1.0, 0.0, 2.0)
	return _profile_brightness * brightness * _gain


func _zone_map(entries: Variant) -> Dictionary:
	var result: Dictionary = {}
	if entries is Array:
		for item: Variant in entries:
			if item is Dictionary:
				result[_canonical_zone_id(str(item.get("id", "")))] = item
	return result


func _capture_emission_baseline(fallback_mode: String) -> void:
	if _emission_bindings.is_empty():
		_previous_emission_mode = fallback_mode if fallback_mode in MODE_IDS else "all"
		_previous_emission_gain = 1.0
		return
	var mode := str(_emission_bindings.get("mode", ""))
	_previous_emission_mode = mode if mode in MODE_IDS else (fallback_mode if fallback_mode in MODE_IDS else "all")
	var gain := _number_or(_emission_bindings.get("gain", -1.0), -1.0, -1.0, 2.0)
	_previous_emission_gain = gain if gain >= 0.0 else 1.0
	for binding: Dictionary in _emission_bindings.get("materials", []):
		var material: BaseMaterial3D = binding.get("material")
		if is_instance_valid(material) and not binding.has("profile_original_emission"):
			binding["profile_original_emission"] = material.emission


func _apply_emission_mode() -> void:
	if _emission_bindings.is_empty():
		return
	var applied_gain := 0.0 if _mode == "off" else _profile_brightness * _gain
	AircraftLights.set_emission_mode(_emission_bindings, _mode, applied_gain)
	_apply_profile_emission(0.0, {})


func _apply_profile_emission(seconds: float, telemetry: Dictionary) -> void:
	if _emission_bindings.is_empty():
		return
	for binding: Dictionary in _emission_bindings.get("materials", []):
		var material: BaseMaterial3D = binding.get("material")
		if not is_instance_valid(material):
			continue
		var group := str(binding.get("group", ""))
		var zone_id := _emission_zone_id(binding)
		if not zone_id.is_empty() and _zones.has(zone_id):
			var zone: Dictionary = _zones[zone_id]
			var pattern: Dictionary = zone.get("pattern", {})
			material.emission = Patterns.sample(pattern, seconds, 0.5, _profile.get("sequence", []), zone_id)
			var reaction := Patterns.reactive_multiplier(zone.get("reactive", {}), telemetry)
			var enabled := bool(zone.get("enabled", true)) and _profile_group_on(group)
			material.emission_enabled = enabled
			material.emission_energy_multiplier = float(binding.get("energy", 0.0)) * _zone_gain(zone_id) * float(reaction.get("multiplier", 1.0)) if enabled else 0.0
			continue
		if zone_id.is_empty() and _all_group_zones_disabled(group):
			material.emission_enabled = false
			material.emission_energy_multiplier = 0.0
		if zone_id.is_empty() and _group_has_zones(group):
			var warning := "imported emission material '%s' follows the %s group because no individual zone mapping is available" % [material.resource_name, group]
			if not _warnings.has(warning):
				_warnings.append(warning)


func _restore_emission_colors() -> void:
	for binding: Dictionary in _emission_bindings.get("materials", []):
		var material: BaseMaterial3D = binding.get("material")
		if is_instance_valid(material) and binding.has("profile_original_emission"):
			material.emission = binding.profile_original_emission


func _emission_zone_id(binding: Dictionary) -> String:
	if str(binding.get("group", "")) != "navigation":
		return ""
	var material: BaseMaterial3D = binding.get("material")
	if not is_instance_valid(material):
		return ""
	match str(material.resource_name):
		"light_red": return "nav_left"
		"light_green": return "nav_right"
	return ""


func _all_group_zones_disabled(group: String) -> bool:
	var found := false
	for zone_id: String in _zones:
		if _group_for(zone_id) != group:
			continue
		found = true
		if bool((_zones[zone_id] as Dictionary).get("enabled", true)):
			return false
	return found


func _group_has_zones(group: String) -> bool:
	for zone_id: String in _zones:
		if _group_for(zone_id) == group:
			return true
	return false


func _profile_group_on(group: String) -> bool:
	if group not in _supported_light_groups():
		return false
	return _mode == "all" or (_mode == "nav" and group in ["navigation", "strobe"])


func _supported_light_groups() -> Array:
	if is_instance_valid(kit):
		var supported: Variant = kit.get_meta("supported_light_groups", AircraftLights.GROUPS)
		if supported is Array:
			return supported
	return AircraftLights.GROUPS


func _reapply_profile_visibility() -> void:
	var supported := _supported_light_groups()
	for binding: Dictionary in _materials:
		var node: Node3D = binding.get("node")
		if not is_instance_valid(node):
			continue
		var group := str(binding.get("group", "orientation"))
		var group_on := group in supported and (_mode == "all" or (_mode == "nav" and group in ["navigation", "strobe"]))
		node.visible = bool(binding.get("original_visible", true)) and bool(binding.get("enabled", true)) \
			and bool(node.get_meta("gate_open", true)) and group_on
		if str(binding.get("kind", "")) == "spot":
			var light := node as Light3D
			if is_instance_valid(light):
				light.light_energy = float(binding.get("base_energy", 0.0)) * _zone_gain(str(binding.get("zone_id", ""))) if node.visible else 0.0


func _profile_node_author_visible(node: Node3D, group: String) -> bool:
	if is_instance_valid(kit):
		var groups: Dictionary = kit.get_meta("light_bindings", {})
		var members: Variant = groups.get(group, [])
		if members is Array and node in members:
			return true # A bound node's live visibility is mode/gate state, not its authored visibility.
	return node.visible


func _profile_color(zone: Dictionary, source: ShaderMaterial) -> Color:
	var original := _color(_shader_value(source, "light_color", Color.WHITE), Color.WHITE)
	var pattern: Variant = zone.get("pattern", {})
	if pattern is Dictionary and not pattern.is_empty():
		return Patterns.sample(pattern, 0.0, 0.5, _profile.get("sequence", []), str(zone.get("id", "")))
	return original


func _group_for(zone_id: String) -> String:
	if zone_id.begins_with("nav_"):
		return "navigation"
	if zone_id.begins_with("strobe_"):
		return "strobe"
	if zone_id.begins_with("landing_lamp"):
		return "landing"
	return "orientation"


func _canonical_zone_id(zone_id: String) -> String:
	if zone_id in ["landing_lamp_right", "landing_light", "landing_light_right"]:
		return "landing_lamp"
	return zone_id


func _is_lamp_zone(zone_id: String) -> bool:
	return _canonical_zone_id(zone_id) in ["nav_left", "nav_right", "nav_tail", "strobe_left", "strobe_right", "strobe_dorsal", "strobe_ventral", "landing_lamp"]


func _default_pattern(color: Color) -> Dictionary:
	return {"id": "steady", "palette": [color], "period_ticks": 240, "phase_turns": 0.0, "floor": 1.0, "duty": 0.5, "reverse": false, "segments": 1}


func _axis_for(zone_id: String) -> Vector3:
	if zone_id == "strip_belly":
		return Vector3.BACK
	return Vector3.LEFT if zone_id.ends_with("left") else Vector3.RIGHT


func _axis_range(mesh: Mesh, axis: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	if mesh != null and mesh.get_surface_count() > 0:
		var arrays: Array = mesh.surface_get_arrays(0)
		if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var projected := vertex.dot(axis)
				if is_finite(projected):
					lo = minf(lo, projected)
					hi = maxf(hi, projected)
	if not is_finite(lo) or not is_finite(hi) or hi - lo < 0.00001:
		return Vector2(0.0, 1.0)
	return Vector2(lo, hi - lo)


func _shader_value(material: ShaderMaterial, key: StringName, fallback: Variant) -> Variant:
	if material == null or material.shader == null:
		return fallback
	var value: Variant = material.get_shader_parameter(key)
	return fallback if value == null else value


func _color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(value, fallback)
	return fallback


func _number_or(value: Variant, fallback: float, low: float, high: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)
