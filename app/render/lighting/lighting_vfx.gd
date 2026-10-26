extends RefCounted
## Bounded render-only aircraft sparks, ribbon trails and nearby light spill.
## All motion is analytic from the caller's displayed-pose clock; this class never reads simulation state.

const RGB_LAMP_SHADER := preload("res://render/lighting/rgb_lamp.gdshader")
const Patterns := preload("res://render/lighting/lighting_patterns.gd")
const LightingPolicy := preload("res://render/lighting/lighting_policy.gd")
const SceneBudget := preload("res://render/lighting/lighting_scene_budget.gd")
const MAX_EFFECTS := 2
const SPARK_POOL_CAPACITY := 32
const SPARKS_PER_EVENT := 20
const BURST_SPARKS_PER_EVENT := 32
const MAX_TRAIL_SEGMENTS := 63
const MAX_TRAIL_SAMPLES := MAX_TRAIL_SEGMENTS + 1
const TRAIL_SAMPLE_INTERVAL := 1.0 / 30.0
const MANEUVER_TRIGGER := 0.72
const TRAIL_MANEUVER_THRESHOLD := 0.35
const SPARK_COOLDOWN_S := 0.45
const SPILL_RANGE_M := 2.7
const SPILL_ENERGY := 0.08
const SPILL_LIMIT := 2
const SPILL_MAX_EXPOSED_ENERGY := 0.05
const SPILL_FULL_DISTANCE_M := 20.0
const SPILL_OFF_DISTANCE_M := 40.0
const VFX_FULL_DISTANCE_M := 60.0
const VFX_OFF_DISTANCE_M := 120.0
const EFFECT_BOUNDS_PADDING_M := 0.01
const LOD_NEAR_ENTER_PX := 198.0
const LOD_NEAR_EXIT_PX := 162.0
const LOD_MEDIUM_ENTER_PX := 66.0
const LOD_MEDIUM_EXIT_PX := 54.0
const LOD_FAR_ENTER_PX := 13.2
const LOD_FAR_EXIT_PX := 10.8
const LOD_NEAR := "near"
const LOD_MEDIUM := "medium"
const LOD_FAR := "far"
const LOD_TINY := "tiny"
const TIP_ANCHORS := {"vfx_tip_left": "nav_left", "vfx_tip_right": "nav_right"}
const GOLD := Color("#FFD17A")
const EFFECT_QUAD_LOCAL_AABB := AABB(Vector3(-0.5, -0.5, 0.0), Vector3(1.0, 1.0, 0.0))

var _root: Node3D
var _kit: Node3D
var _world_host: Node3D
var _world_root: Node3D
var _profile: Dictionary = {}
var _effects: Array[Dictionary] = []
var _spills: Array[Dictionary] = []
var _warnings: Array[String] = []
var _mode := "off"
var _gain := 1.0
var _last_seconds := -1.0
var _last_maneuver := false
var _last_cue_key := ""
var _event_serial := 0
var _spill_fade := 1.0
var _distance_fade := 1.0
var _scene_budget: RefCounted
var _scene_grant := {"spill_lights": 0, "vfx_anchors": 0}
var _budget_distance := 1000000.0
var _budget_priority := 0
var _aircraft_bounds_local := AABB()
var _has_aircraft_bounds := false
var _lod_camera_id := 0
var _lod_tier := LOD_NEAR
var _lod_birth_density := 1.0
var _lod_projected_span_px := 0.0
var _aircraft_in_view := true


func configure(aircraft_root: Node3D, kit: Node3D, profile: Dictionary) -> Dictionary:
	dispose()
	if aircraft_root == null or not is_instance_valid(aircraft_root) or kit == null or not is_instance_valid(kit):
		return {"ok": false, "errors": ["lighting VFX requires a live aircraft root and NightKit"], "warnings": []}
	_root = aircraft_root
	_kit = kit
	_profile = profile.duplicate(true)
	_cache_aircraft_bounds()
	var entries: Array = []
	var errors: Array[String] = []
	var effects: Variant = profile.get("effects", [])
	if effects is Array:
		for effect: Variant in effects:
			if not effect is Dictionary or not bool(effect.get("enabled", false)):
				continue
			var anchor_id := str(effect.get("anchor_id", ""))
			var kit_name := str(TIP_ANCHORS.get(anchor_id, ""))
			var anchor := kit.get_node_or_null(NodePath(kit_name)) as Node3D if not kit_name.is_empty() else null
			if anchor == null:
				var message := "effect anchor '%s' is unavailable; effect was skipped" % anchor_id
				if bool(effect.get("required", true)):
					errors.append(message)
				else:
					_warnings.append(message)
				continue
			entries.append({"effect": effect, "anchor": anchor})
	if not errors.is_empty():
		var failure_warnings := _warnings.duplicate()
		dispose()
		return {"ok": false, "errors": errors, "warnings": failure_warnings}
	if entries.size() > MAX_EFFECTS:
		var overflow := "lighting VFX exceeds the two-effect runtime budget"
		dispose()
		return {"ok": false, "errors": [overflow], "warnings": []}
	_create_spill_lights(profile)
	if not entries.is_empty():
		_create_world_root()
		for entry: Dictionary in entries:
			_create_effect_pool(entry.effect, entry.anchor)
	if _root.is_inside_tree():
		_scene_budget = SceneBudget.for_world(_root.get_world_3d())
		if _scene_budget != null:
			var identity := "aircraft:" + str(_root.get_path()).sha256_text().substr(0, 32)
			if not _scene_budget.register_owner(self, identity):
				_warnings.append("scene lighting budget unavailable; decorative effects remain hidden")
	return {"ok": true, "errors": [], "warnings": _warnings.duplicate()}


func set_mode(mode: String, gain := 1.0) -> void:
	if mode not in ["all", "nav", "off"] or not is_finite(gain):
		return
	_mode = mode
	_gain = clampf(gain, 0.0, 2.0)
	var show_all := _mode == "all" and _gain > 0.0 and is_instance_valid(_kit) and _kit.visible
	for binding: Dictionary in _spills:
		var spill: OmniLight3D = binding.get("light")
		if is_instance_valid(spill):
			binding["wants_visible"] = show_all and LightingPolicy.quality != "low" and _spill_fade > 0.0 and bool(spill.get_meta("gate_open", true))
	for pool: Dictionary in _effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance):
			pool["wants_visible"] = show_all and LightingPolicy.effects_allowed()
	if not show_all:
		_clear_transients()
	_refresh_scene_budget()


func advance(presentation_seconds: float, telemetry: Dictionary = {}) -> void:
	if not is_finite(presentation_seconds) or not is_instance_valid(_root) or not is_instance_valid(_kit):
		return
	var seconds := maxf(0.0, presentation_seconds)
	if _last_seconds >= 0.0 and seconds < _last_seconds:
		reset()
	var exposure := _number_or(telemetry.get("exposure", 1.0), 1.0, 0.0001, 1000000.0)
	var distance := _number_or(telemetry.get("distance_m", 0.0), 0.0, 0.0, 1000000.0)
	_budget_distance = distance
	_budget_priority = clampi(int(telemetry.get("lighting_priority", 0)), -1000, 1000)
	_update_projected_lod()
	_spill_fade = 1.0 - _smoothstep(SPILL_FULL_DISTANCE_M, SPILL_OFF_DISTANCE_M, distance)
	if LightingPolicy.quality == "low": _spill_fade = 0.0
	_distance_fade = 1.0 - _smoothstep(VFX_FULL_DISTANCE_M, VFX_OFF_DISTANCE_M, distance)
	var maneuver := _number_or(telemetry.get("maneuver", 0.0), 0.0, 0.0, 1.0)
	var maneuver_high := maneuver >= MANEUVER_TRIGGER
	var maneuver_rising := maneuver_high and not _last_maneuver
	_last_maneuver = maneuver_high
	var effects_allowed := bool(telemetry.get("effects_allowed", false))
	var show_all := _mode == "all" and _gain > 0.0 and _kit.visible
	var active := show_all and effects_allowed and LightingPolicy.effects_allowed()
	if not LightingPolicy.effects_allowed(): _clear_transients()
	for pool: Dictionary in _effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if is_instance_valid(instance): pool["wants_visible"] = show_all and LightingPolicy.effects_allowed()
	var cue_state := _sequence_state(seconds)
	var cue := cue_state.get("cue", {}) as Dictionary
	var cue_key := "%d:%d" % [int(cue_state.get("sequence_cycle", 0)), int(cue_state.get("cue_index", -1))]
	var cue_changed := cue_key != _last_cue_key
	_last_cue_key = cue_key
	var cue_anchors: Array = cue.get("effect_anchor_ids", []) if cue_changed else []
	var cue_active_anchors: Array = cue.get("effect_anchor_ids", [])
	var cue_start := float(cue_state.get("cue_start_seconds", -1.0))
	for pool: Dictionary in _effects:
		var anchor: Node3D = pool.get("anchor")
		if not is_instance_valid(anchor):
			continue
		var kind := str(pool.get("kind", "spark"))
		var cue_trigger := str(pool.get("anchor_id", "")) in cue_anchors
		var cue_active := str(pool.get("anchor_id", "")) in cue_active_anchors
		if active and _distance_fade > 0.0 and cue_trigger and kind in ["spark", "burst"] and cue_start >= 0.0:
			_trigger_sparks(pool, cue_start, seconds, true, _distance_fade)
		elif active and _distance_fade > 0.0 and maneuver_rising and kind in ["spark", "burst"]:
			_trigger_sparks(pool, seconds, seconds, false, _distance_fade)
		if kind == "trail":
			var trail_active := active and _lod_birth_density > 0.0 and _distance_fade > 0.0 \
				and (cue_active or maneuver >= TRAIL_MANEUVER_THRESHOLD)
			if trail_active:
				pool["trail_until"] = seconds + float(pool.get("lifetime_s", 0.6))
				_sample_trail(pool, seconds, anchor.global_position)
			_update_trail(pool, seconds, exposure, _distance_fade)
		else:
			_update_sparks(pool, seconds, exposure, _distance_fade)
	_update_spills(seconds, telemetry, exposure)
	_refresh_scene_budget()
	_last_seconds = seconds


func reset() -> void:
	_last_seconds = -1.0
	_last_maneuver = false
	_last_cue_key = ""
	_event_serial = 0
	_spill_fade = 1.0
	_distance_fade = 1.0
	for pool: Dictionary in _effects:
		pool["last_event_time"] = -INF
		pool["last_sample_time"] = -INF
		pool["trail_until"] = -INF
		pool["samples"] = []
		pool["particles"] = []
		_clear_pool_visuals(pool)
	_refresh_scene_budget()


func dispose() -> void:
	if _scene_budget != null:
		_scene_budget.unregister_owner(self)
	_scene_budget = null
	_scene_grant = {"spill_lights": 0, "vfx_anchors": 0}
	for binding: Dictionary in _spills:
		var spill: OmniLight3D = binding.get("light")
		if is_instance_valid(spill):
			spill.free()
	_spills.clear()
	if is_instance_valid(_world_root):
		_world_root.free()
	_world_root = null
	_world_host = null
	_effects.clear()
	_profile.clear()
	_warnings.clear()
	_root = null
	_kit = null
	_mode = "off"
	_gain = 1.0
	_last_seconds = -1.0
	_last_maneuver = false
	_last_cue_key = ""
	_event_serial = 0
	_spill_fade = 1.0
	_distance_fade = 1.0
	_aircraft_bounds_local = AABB()
	_has_aircraft_bounds = false
	_lod_camera_id = 0
	_lod_tier = LOD_NEAR
	_lod_birth_density = 1.0
	_lod_projected_span_px = 0.0
	_aircraft_in_view = true


func budget_info() -> Dictionary:
	var spark_particles := 0
	var trail_samples := 0
	var spark_gpu_capacity := 0
	var trail_gpu_capacity := 0
	var gpu_anchors := 0
	var gpu_instance_writes := 0
	for pool: Dictionary in _effects:
		var kind := str(pool.get("kind", ""))
		var particle_state: Variant = pool.get("particles", [])
		var sample_state: Variant = pool.get("samples", [])
		if kind == "trail":
			if sample_state is Array:
				trail_samples += sample_state.size()
		else:
			if particle_state is Array:
				spark_particles += particle_state.size()
		gpu_instance_writes += int(pool.get("gpu_instance_writes", 0))
		var instance: MultiMeshInstance3D = pool.get("instance")
		if not is_instance_valid(instance) or instance.multimesh == null:
			continue
		var allocated_instances := instance.multimesh.instance_count
		if allocated_instances <= 0:
			continue
		gpu_anchors += 1
		if kind == "trail":
			trail_gpu_capacity += allocated_instances
		else:
			spark_gpu_capacity += allocated_instances
	return {
		"effects_allocated": _effects.size(), # CPU effect-pool records, independent of GPU grants.
		"effects_cpu_allocated": _effects.size(),
		"effects_gpu_allocated": gpu_anchors,
		"sparks_allocated": spark_gpu_capacity,
		"trails_allocated": trail_gpu_capacity,
		"sparks_cpu_live": spark_particles,
		"trails_cpu_live": trail_samples,
		"sparks_gpu_instance_capacity": spark_gpu_capacity,
		"trails_gpu_instance_capacity": trail_gpu_capacity,
		"gpu_anchors_allocated": gpu_anchors,
		"gpu_instance_capacity_allocated": spark_gpu_capacity + trail_gpu_capacity,
		"gpu_instance_writes": gpu_instance_writes,
		"spill_lights_allocated": _spills.size(),
		"spark_limit": MAX_EFFECTS * SPARK_POOL_CAPACITY,
		"trail_sample_limit": MAX_EFFECTS * MAX_TRAIL_SAMPLES,
		"spill_light_limit": SPILL_LIMIT,
		"projected_vfx_tier": _lod_tier,
		"projected_aircraft_span_px": _lod_projected_span_px,
		"projected_vfx_birth_density": _lod_birth_density,
		"projected_aircraft_in_view": _aircraft_in_view,
		"warnings": _warnings.duplicate(),
		"scene_grant": _scene_grant.duplicate(),
		"scene_budget": _scene_budget.receipt() if _scene_budget != null else {},
	}


## The shared World3D coordinator revokes all old grants before enabling new owners.
func apply_scene_budget(grant: Dictionary) -> void:
	_scene_grant = grant.duplicate()
	var spill_left := int(grant.get("spill_lights", 0))
	for binding: Dictionary in _spills:
		var light: OmniLight3D = binding.get("light")
		if not is_instance_valid(light): continue
		light.visible = bool(binding.get("wants_visible", false)) and spill_left > 0
		if light.visible: spill_left -= 1
	var desired_pool_ids: Dictionary = {}
	var effects_left := mini(MAX_EFFECTS, maxi(0, int(grant.get("vfx_anchors", 0))))
	for pool: Dictionary in _effects:
		if effects_left <= 0:
			break
		if bool(pool.get("wants_visible", false)) and int(pool.get("live_visual_count", 0)) > 0:
			desired_pool_ids[int(pool.get("pool_id", -1))] = true
			effects_left -= 1

	# Drop every revoked buffer before allocating any newly granted buffer on this rig.
	for pool: Dictionary in _effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if not is_instance_valid(instance) or instance.multimesh == null:
			continue
		if not desired_pool_ids.has(int(pool.get("pool_id", -1))):
			_release_effect_buffer(instance)

	# Grant callbacks allocate capacity only. The next advance repopulates it from CPU state.
	for pool: Dictionary in _effects:
		var instance: MultiMeshInstance3D = pool.get("instance")
		if not is_instance_valid(instance) or instance.multimesh == null:
			continue
		var desired := desired_pool_ids.has(int(pool.get("pool_id", -1)))
		if desired and instance.multimesh.instance_count == 0:
			_allocate_effect_buffer(instance, pool)
		instance.visible = desired and bool(pool.get("wants_visible", false)) \
			and instance.multimesh.instance_count > 0 and instance.multimesh.visible_instance_count > 0


func _refresh_scene_budget() -> void:
	var spill_count := 0
	for binding: Dictionary in _spills:
		if bool(binding.get("wants_visible", false)): spill_count += 1
	var effects_count := 0
	for pool: Dictionary in _effects:
		if bool(pool.get("wants_visible", false)) and int(pool.get("live_visual_count", 0)) > 0:
			effects_count += 1
	if _scene_budget == null:
		apply_scene_budget({"spill_lights": 0, "vfx_anchors": 0})
		return
	_scene_budget.set_quality(LightingPolicy.quality)
	var grant: Dictionary = _scene_budget.submit(self, {"priority": _budget_priority, "distance_m": _budget_distance,
		"spill_lights": spill_count, "vfx_anchors": effects_count})
	# A numerically unchanged grant still needs to apply new per-pool eligibility.
	apply_scene_budget(grant)


func warnings() -> Array[String]:
	return _warnings.duplicate()


func _create_world_root() -> void:
	var host: Node3D = null
	var cursor: Node = _root.get_parent() if is_instance_valid(_root) else null
	while cursor != null and host == null:
		host = cursor as Node3D
		cursor = cursor.get_parent()
	if host == null:
		host = _root
	_world_host = host
	_world_root = Node3D.new()
	_world_root.name = "AircraftLightingWorldVfx"
	_world_root.top_level = true
	_world_host.add_child(_world_root)
	_world_root.global_transform = Transform3D.IDENTITY


func _create_effect_pool(effect: Dictionary, anchor: Node3D) -> void:
	var kind := str(effect.get("kind", "spark"))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.instance_count = 0
	multi.visible_instance_count = 0
	multi.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = RGB_LAMP_SHADER
	material.set_shader_parameter("vfx_mode", 1.0)
	material.set_shader_parameter("radial_shape", 0.0 if kind == "trail" else 1.0)
	material.set_shader_parameter("radiance", 1.8 if kind == "trail" else 2.4)
	var instance := MultiMeshInstance3D.new()
	instance.name = "show_%s" % str(effect.get("anchor_id", "tip"))
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	_world_root.add_child(instance)
	var lifetime := float(maxi(12, int(effect.get("lifetime_ticks", 96)))) / 240.0
	_effects.append({
		"pool_id": _effects.size(),
		"anchor_id": str(effect.get("anchor_id", "")),
		"anchor": anchor,
		"kind": kind,
		"intensity": clampf(_number_or(effect.get("intensity", 0.5), 0.5, 0.0, 1.0), 0.0, 1.0),
		"lifetime_s": lifetime,
		"seed": int(_profile.get("visual_seed", 0)),
		"event_count": 0,
		"last_event_time": -INF,
		"last_sample_time": -INF,
		"trail_until": -INF,
		"samples": [],
		"particles": [],
		"visual_transforms": [],
		"visual_colors": [],
		"visual_bounds": AABB(),
		"live_visual_count": 0,
		"gpu_instance_writes": 0,
		"instance": instance,
		"material": material,
	})


func _create_spill_lights(profile: Dictionary) -> void:
	var zones: Variant = profile.get("zones", [])
	var strip_zones: Dictionary = {}
	if zones is Array:
		for zone: Variant in zones:
			if zone is Dictionary and str(zone.get("id", "")).begins_with("strip_") and bool(zone.get("enabled", true)):
				strip_zones[str(zone.get("id", ""))] = zone
	if strip_zones.is_empty() or not is_instance_valid(_kit):
		return
	var supported: Array = _kit.get_meta("supported_light_groups", ["navigation", "strobe", "landing", "orientation"])
	if not supported.has("orientation"):
		return # Authored aircraft that do not support orientation strips cannot receive decorative spill.
	var brightness := clampf(_number_or(profile.get("brightness", 1.0), 1.0, 0.0, 2.0), 0.0, 2.0)
	for side in ["left", "right"]:
		if _spills.size() >= SPILL_LIMIT:
			break
		var zone_id := ""
		var zone: Dictionary = {}
		for candidate_id in ["strip_%s" % side, "strip_top_%s" % side]:
			var candidate_zone: Dictionary = strip_zones.get(candidate_id, {})
			var candidate_node := _kit.get_node_or_null(candidate_id) as MeshInstance3D
			if not candidate_zone.is_empty() and candidate_node != null and candidate_node.mesh != null and candidate_node.mesh.get_surface_count() > 0:
				zone_id = candidate_id
				zone = candidate_zone
				break
		if zone.is_empty():
			continue
		var anchor_name := "nav_%s" % side
		var anchor := _kit.get_node_or_null(anchor_name) as Node3D
		if anchor == null:
			_warnings.append("spill anchor '%s' is unavailable; local spill was skipped" % anchor_name)
			continue
		var pattern: Dictionary = zone.get("pattern", {})
		var color := LightingPolicy.sample(pattern, 0.0, 0.5, profile.get("sequence", []), zone_id)
		var zone_brightness := clampf(_number_or(zone.get("brightness", 1.0), 1.0, 0.0, 2.0), 0.0, 2.0)
		var light := OmniLight3D.new()
		light.name = "strip_spill_%s" % side
		light.light_color = color
		light.light_energy = 0.0 # Wait for the displayed exposure sample before enabling local spill.
		light.omni_range = SPILL_RANGE_M
		light.omni_attenuation = 2.0
		light.shadow_enabled = false
		light.light_specular = 0.0
		light.position = anchor.position
		light.visible = false
		if anchor.has_meta("follow"):
			light.set_meta("follow", anchor.get_meta("follow"))
			light.set_meta("follow_offset", anchor.get_meta("follow_offset", Vector3.ZERO))
		if anchor.has_meta("gear_gated"):
			light.set_meta("gear_gated", true)
		_kit.add_child(light)
		_spills.append({"light": light, "zone": zone, "zone_id": zone_id, "base_energy": SPILL_ENERGY * brightness * zone_brightness})


func _trigger_sparks(pool: Dictionary, birth_seconds: float, current_seconds: float, burst: bool, distance_fade: float) -> void:
	var lifetime := maxf(0.001, float(pool.get("lifetime_s", 0.5)))
	var age_at_birth := current_seconds - birth_seconds
	if age_at_birth < 0.0 or age_at_birth >= lifetime:
		return
	if birth_seconds - float(pool.get("last_event_time", -INF)) < SPARK_COOLDOWN_S:
		return
	var base_count := BURST_SPARKS_PER_EVENT if burst else SPARKS_PER_EVENT
	var count := clampi(roundi(float(base_count) * distance_fade * LightingPolicy.effect_density()
		* _lod_birth_density), 0, SPARK_POOL_CAPACITY)
	if count <= 0:
		return
	pool["last_event_time"] = birth_seconds
	var anchor: Node3D = pool.get("anchor")
	if not is_instance_valid(anchor):
		return
	var particles: Array = []
	var rng := RandomNumberGenerator.new()
	_event_serial += 1
	var serial := int(pool.get("event_count", 0)) + _event_serial
	pool["event_count"] = serial
	rng.seed = posmod(int(pool.get("seed", 0)) + serial * 104729 + str(pool.get("anchor_id", "")).hash(), 2147483647)
	var x_axis := _safe_axis(_root.global_transform.basis.x, Vector3.RIGHT)
	var y_axis := _safe_axis(_root.global_transform.basis.y, Vector3.UP)
	var z_axis := _safe_axis(_root.global_transform.basis.z, Vector3.BACK)
	for _index in count:
		var direction := (x_axis * rng.randf_range(-1.0, 1.0) + y_axis * rng.randf_range(0.0, 1.0) + z_axis * rng.randf_range(-1.0, 1.0)).normalized()
		if direction.length_squared() < 0.5:
			direction = y_axis
		particles.append({
			"origin": anchor.global_position,
			"velocity": direction * rng.randf_range(0.7, 2.1),
			"size": rng.randf_range(0.018, 0.045) * (1.25 if burst else 1.0),
			"start": birth_seconds,
			"life": lifetime,
			"color": GOLD,
		})
	pool["particles"] = particles


func _update_sparks(pool: Dictionary, seconds: float, exposure: float, distance_fade: float) -> void:
	var material: ShaderMaterial = pool.get("material")
	_set_exposure(material, pool, exposure)
	var particles: Array = pool.get("particles", [])
	var retained_particles: Array = []
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var live_bounds := AABB()
	var has_live_bounds := false
	var camera_basis := _camera_basis()
	for particle_value: Variant in particles:
		if not particle_value is Dictionary:
			continue
		var particle: Dictionary = particle_value
		var age := maxf(0.0, seconds - float(particle.get("start", seconds)))
		var life := maxf(0.001, float(particle.get("life", 0.5)))
		if age >= life:
			continue
		retained_particles.append(particle)
		var origin: Vector3 = particle.get("origin", Vector3.ZERO)
		var velocity: Vector3 = particle.get("velocity", Vector3.ZERO)
		var point := origin + velocity * age + Vector3.DOWN * (0.5 * 1.4 * age * age)
		var fade := clampf(1.0 - age / life, 0.0, 1.0) * float(pool.get("intensity", 0.5)) * _gain * distance_fade
		if fade <= 0.0:
			continue
		var size := float(particle.get("size", 0.025)) * (0.7 + 0.3 * fade)
		var basis := Basis(camera_basis.x * size, camera_basis.y * size, camera_basis.z * size)
		var local_transform := _local_transform(Transform3D(basis, point))
		if not local_transform.is_finite():
			continue
		var particle_bounds := local_transform * EFFECT_QUAD_LOCAL_AABB
		if not particle_bounds.is_finite():
			continue
		transforms.append(local_transform)
		live_bounds = particle_bounds if not has_live_bounds else live_bounds.merge(particle_bounds)
		has_live_bounds = true
		var color: Color = particle.get("color", GOLD)
		colors.append(Color(color.r, color.g, color.b, fade))
	pool["particles"] = retained_particles
	pool["visual_transforms"] = transforms
	pool["visual_colors"] = colors
	pool["visual_bounds"] = live_bounds if has_live_bounds else AABB()
	pool["live_visual_count"] = transforms.size()
	_write_pool_visuals(pool)


func _sample_trail(pool: Dictionary, seconds: float, point: Vector3) -> void:
	var last_sample_time := float(pool.get("last_sample_time", -INF))
	var sample_interval := TRAIL_SAMPLE_INTERVAL / maxf(LightingPolicy.effect_density() * _lod_birth_density, 0.01)
	if seconds - last_sample_time < sample_interval:
		return
	var samples: Array = pool.get("samples", [])
	if not samples.is_empty():
		var previous: Dictionary = samples[-1]
		var previous_point: Vector3 = previous.get("position", point)
		if previous_point.distance_to(point) > 5.0:
			samples.clear() # A camera/aircraft teleport never draws a bridge across the world.
		elif seconds - float(previous.get("time", seconds)) < TRAIL_SAMPLE_INTERVAL * 0.5:
			return
	samples.append({"time": seconds, "position": point})
	while samples.size() > MAX_TRAIL_SAMPLES:
		samples.pop_front()
	pool["samples"] = samples
	pool["last_sample_time"] = seconds


func _update_trail(pool: Dictionary, seconds: float, exposure: float, distance_fade: float) -> void:
	var material: ShaderMaterial = pool.get("material")
	_set_exposure(material, pool, exposure)
	var samples: Array = pool.get("samples", [])
	var life := maxf(0.001, float(pool.get("lifetime_s", 0.6)))
	while not samples.is_empty() and seconds - float(samples[0].get("time", seconds)) > life:
		samples.pop_front()
	pool["samples"] = samples
	var camera_position := _camera_position()
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var live_bounds := AABB()
	var has_live_bounds := false
	for index in MAX_TRAIL_SEGMENTS:
		if index + 1 >= samples.size():
			break
		var before: Dictionary = samples[index]
		var after: Dictionary = samples[index + 1]
		var from: Vector3 = before.get("position", Vector3.ZERO)
		var to: Vector3 = after.get("position", Vector3.ZERO)
		var delta := to - from
		var length := delta.length()
		if length < 0.001 or length > 5.0:
			continue
		var tangent := delta / length
		var midpoint := (from + to) * 0.5
		var side := (camera_position - midpoint).cross(tangent)
		if side.length_squared() < 1e-8:
			side = Vector3.UP.cross(tangent)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT.cross(tangent)
		side = side.normalized()
		var normal := tangent.cross(side).normalized()
		var fade := clampf(1.0 - maxf(0.0, seconds - float(after.get("time", seconds))) / life, 0.0, 1.0)
		fade *= float(pool.get("intensity", 0.5)) * _gain * distance_fade
		if fade <= 0.0:
			continue
		var basis := Basis(tangent * length, side * 0.035, normal)
		var local_transform := _local_transform(Transform3D(basis, midpoint))
		if not local_transform.is_finite():
			continue
		var segment_bounds := local_transform * EFFECT_QUAD_LOCAL_AABB
		if not segment_bounds.is_finite():
			continue
		transforms.append(local_transform)
		live_bounds = segment_bounds if not has_live_bounds else live_bounds.merge(segment_bounds)
		has_live_bounds = true
		colors.append(Color(GOLD.r, GOLD.g, GOLD.b, fade))
	pool["visual_transforms"] = transforms
	pool["visual_colors"] = colors
	pool["visual_bounds"] = live_bounds if has_live_bounds else AABB()
	pool["live_visual_count"] = transforms.size()
	_write_pool_visuals(pool)


func _update_spills(seconds: float, telemetry: Dictionary, exposure: float) -> void:
	for binding: Dictionary in _spills:
		var light: OmniLight3D = binding.get("light")
		if not is_instance_valid(light):
			continue
		var zone: Dictionary = binding.get("zone", {})
		var zone_id := str(binding.get("zone_id", ""))
		var pattern: Dictionary = zone.get("pattern", {})
		light.light_color = LightingPolicy.sample(pattern, seconds, 0.5, _profile.get("sequence", []), zone_id)
		var reaction := LightingPolicy.reaction(zone.get("reactive", {}), telemetry)
		var modulation := float(binding.get("base_energy", SPILL_ENERGY)) / SPILL_ENERGY * _gain * _spill_fade * float(reaction.get("multiplier", 1.0))
		# Preserve user brightness and telemetry response after adapting to night exposure.
		light.light_energy = minf(SPILL_ENERGY, SPILL_MAX_EXPOSED_ENERGY / maxf(exposure, 0.0001)) * modulation
		binding["wants_visible"] = _mode == "all" and _gain > 0.0 and _spill_fade > 0.0 and _kit.visible and bool(light.get_meta("gate_open", true))


func _sequence_state(seconds: float) -> Dictionary:
	var sequence: Variant = _profile.get("sequence", [])
	if not sequence is Array or sequence.is_empty():
		return {"cue_index": -1, "sequence_cycle": 0, "cue_start_seconds": -1.0, "cue": {}}
	return Patterns.sequence_state(sequence, seconds)


func _set_exposure(material: ShaderMaterial, pool: Dictionary, exposure: float) -> void:
	if not is_instance_valid(material):
		return
	if absf(float(pool.get("last_exposure", -1.0)) - exposure) <= 0.0001:
		return
	material.set_shader_parameter("local_exposure", exposure)
	pool["last_exposure"] = exposure


func _active_camera() -> Camera3D:
	if not is_instance_valid(_world_root):
		return null
	var viewport := _world_root.get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


func _camera_basis() -> Basis:
	var camera := _active_camera()
	return camera.global_transform.basis.orthonormalized() if camera != null else Basis.IDENTITY


func _camera_position() -> Vector3:
	var camera := _active_camera()
	return camera.global_position if camera != null else Vector3.ZERO


func _cache_aircraft_bounds() -> void:
	_aircraft_bounds_local = AABB()
	_has_aircraft_bounds = false
	if not is_instance_valid(_kit):
		return
	var layout: Variant = _kit.get_meta("geometry_layout", {})
	if not layout is Dictionary:
		return
	var raw_bounds: Variant = layout.get("bounds")
	if typeof(raw_bounds) != TYPE_AABB:
		return
	var bounds: AABB = raw_bounds
	if not bounds.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return
	_aircraft_bounds_local = bounds
	_has_aircraft_bounds = true


func _measure_projected_view() -> Dictionary:
	if not _has_aircraft_bounds or not is_instance_valid(_root):
		return {"ok": false}
	var camera := _active_camera()
	if camera == null:
		return {"ok": false}
	var viewport := camera.get_viewport()
	if viewport == null:
		return {"ok": false}
	var viewport_size := viewport.get_visible_rect().size
	if not is_finite(viewport_size.x) or not is_finite(viewport_size.y) \
			or viewport_size.x < 1.0 or viewport_size.y < 1.0:
		return {"ok": false}
	var world_bounds: AABB = _root.global_transform * _aircraft_bounds_local
	if not world_bounds.is_finite():
		return {"ok": false}
	var camera_inverse := camera.global_transform.affine_inverse()
	var center_camera := camera_inverse * world_bounds.get_center()
	var center_depth := -center_camera.z
	var radius := world_bounds.size.length() * 0.5
	if not is_finite(center_depth) or not is_finite(radius) or radius <= 0.0:
		return {"ok": false}
	var camera_id := camera.get_instance_id()
	if center_depth + radius < camera.near or center_depth - radius > camera.far:
		return {"ok": true, "camera_id": camera_id, "span_px": 0.0, "visible": false}
	# Bounds touching the near plane conservatively occupy the view. This avoids
	# unstable divisions while zooming through the aircraft or orbiting inside it.
	if center_depth - radius <= camera.near:
		return {"ok": true, "camera_id": camera_id,
			"span_px": maxf(viewport_size.x, viewport_size.y), "visible": true}

	var projection: Projection = camera.get_camera_projection()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for x_index in 2:
		for y_index in 2:
			for z_index in 2:
				var corner := world_bounds.position + Vector3(
					world_bounds.size.x if x_index > 0 else 0.0,
					world_bounds.size.y if y_index > 0 else 0.0,
					world_bounds.size.z if z_index > 0 else 0.0)
				var camera_point := camera_inverse * corner
				var depth := -camera_point.z
				if not is_finite(depth) or depth < camera.near:
					return {"ok": true, "camera_id": camera_id,
						"span_px": maxf(viewport_size.x, viewport_size.y), "visible": true}
				var clip: Vector4 = projection * Vector4(camera_point.x, camera_point.y, camera_point.z, 1.0)
				if not is_finite(clip.x) or not is_finite(clip.y) or not is_finite(clip.w) or clip.w <= 0.000001:
					return {"ok": false}
				var ndc := Vector2(clip.x / clip.w, clip.y / clip.w)
				var screen := Vector2((ndc.x * 0.5 + 0.5) * viewport_size.x,
					(0.5 - ndc.y * 0.5) * viewport_size.y)
				if not is_finite(screen.x) or not is_finite(screen.y):
					return {"ok": false}
				minimum.x = minf(minimum.x, screen.x)
				minimum.y = minf(minimum.y, screen.y)
				maximum.x = maxf(maximum.x, screen.x)
				maximum.y = maxf(maximum.y, screen.y)
	var span_px := maxf(maximum.x - minimum.x, maximum.y - minimum.y)
	if not is_finite(span_px):
		return {"ok": false}
	var visible := maximum.x >= 0.0 and minimum.x <= viewport_size.x \
		and maximum.y >= 0.0 and minimum.y <= viewport_size.y
	return {"ok": true, "camera_id": camera_id, "span_px": maxf(0.0, span_px), "visible": visible}


func _update_projected_lod() -> void:
	var measured := _measure_projected_view()
	if not bool(measured.get("ok", false)):
		# Editor previews and headless fixtures without a camera keep the previous near behavior.
		_lod_camera_id = 0
		_lod_tier = LOD_NEAR
		_lod_birth_density = 1.0
		_lod_projected_span_px = 0.0
		_aircraft_in_view = true
		return
	var span_px := maxf(0.0, float(measured.get("span_px", 0.0)))
	var camera_id := int(measured.get("camera_id", 0))
	if not is_finite(span_px) or camera_id == 0:
		_lod_camera_id = 0
		_lod_tier = LOD_NEAR
		_lod_birth_density = 1.0
		_lod_projected_span_px = 0.0
		_aircraft_in_view = true
		return
	_apply_projected_view(span_px, bool(measured.get("visible", false)), camera_id)


func _apply_projected_view(span_px: float, visible: bool, camera_id: int) -> void:
	if not is_finite(span_px) or span_px < 0.0 or camera_id == 0:
		_lod_camera_id = 0
		_lod_tier = LOD_NEAR
		_lod_birth_density = 1.0
		_lod_projected_span_px = 0.0
		_aircraft_in_view = true
		return
	if camera_id != _lod_camera_id:
		_lod_tier = _tier_for_projected_span(span_px)
	else:
		_lod_tier = _tier_with_hysteresis(_lod_tier, span_px)
	_lod_camera_id = camera_id
	_lod_projected_span_px = span_px
	_aircraft_in_view = visible
	_lod_birth_density = _density_for_lod_tier(_lod_tier) if _aircraft_in_view else 0.0


func _tier_for_projected_span(span_px: float) -> String:
	if span_px > 180.0:
		return LOD_NEAR
	if span_px >= 60.0:
		return LOD_MEDIUM
	if span_px >= 12.0:
		return LOD_FAR
	return LOD_TINY


func _tier_with_hysteresis(current: String, span_px: float) -> String:
	match current:
		LOD_NEAR:
			return LOD_MEDIUM if span_px < LOD_NEAR_EXIT_PX else LOD_NEAR
		LOD_MEDIUM:
			if span_px > LOD_NEAR_ENTER_PX:
				return LOD_NEAR
			if span_px < LOD_MEDIUM_EXIT_PX:
				return LOD_FAR
			return LOD_MEDIUM
		LOD_FAR:
			if span_px > LOD_MEDIUM_ENTER_PX:
				return LOD_MEDIUM
			if span_px < LOD_FAR_EXIT_PX:
				return LOD_TINY
			return LOD_FAR
		LOD_TINY:
			return LOD_FAR if span_px > LOD_FAR_ENTER_PX else LOD_TINY
	return LOD_NEAR


func _density_for_lod_tier(tier: String) -> float:
	match tier:
		LOD_NEAR: return 1.0
		LOD_MEDIUM: return 0.5
		LOD_FAR: return 0.25
		LOD_TINY: return 0.0
	return 1.0


func _set_live_effect_bounds(instance: MultiMeshInstance3D, multi: MultiMesh, bounds: AABB, has_bounds: bool) -> void:
	var live_bounds := bounds.grow(EFFECT_BOUNDS_PADDING_M) if has_bounds and bounds.is_finite() else AABB()
	if not live_bounds.is_finite():
		live_bounds = AABB()
	multi.custom_aabb = live_bounds
	instance.custom_aabb = live_bounds


func _local_transform(world_transform: Transform3D) -> Transform3D:
	if not is_instance_valid(_world_root):
		return world_transform
	return _world_root.global_transform.affine_inverse() * world_transform


func _clear_transients() -> void:
	for pool: Dictionary in _effects:
		pool["particles"] = []
		pool["samples"] = []
		pool["last_sample_time"] = -INF
		pool["trail_until"] = -INF
		_clear_pool_visuals(pool)


func _clear_pool_visuals(pool: Dictionary) -> void:
	pool["visual_transforms"] = []
	pool["visual_colors"] = []
	pool["visual_bounds"] = AABB()
	pool["live_visual_count"] = 0


func _write_pool_visuals(pool: Dictionary) -> void:
	var instance: MultiMeshInstance3D = pool.get("instance")
	if not is_instance_valid(instance) or instance.multimesh == null:
		return
	var multi := instance.multimesh
	if multi.instance_count <= 0:
		return
	var transforms: Array = pool.get("visual_transforms", [])
	var colors: Array = pool.get("visual_colors", [])
	var write_count := mini(multi.instance_count, mini(transforms.size(), colors.size()))
	for index in write_count:
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colors[index])
		pool["gpu_instance_writes"] = int(pool.get("gpu_instance_writes", 0)) + 2
	multi.visible_instance_count = write_count
	var bounds: AABB = pool.get("visual_bounds", AABB())
	_set_live_effect_bounds(instance, multi, bounds, write_count > 0)


func _allocate_effect_buffer(instance: MultiMeshInstance3D, pool: Dictionary) -> void:
	var multi := instance.multimesh
	if multi == null or multi.instance_count > 0:
		return
	instance.visible = false
	multi.visible_instance_count = 0
	_set_live_effect_bounds(instance, multi, AABB(), false)
	multi.instance_count = MAX_TRAIL_SEGMENTS if str(pool.get("kind", "")) == "trail" else SPARK_POOL_CAPACITY


func _release_effect_buffer(instance: MultiMeshInstance3D) -> void:
	var multi := instance.multimesh
	if multi == null:
		instance.visible = false
		return
	instance.visible = false
	multi.visible_instance_count = 0
	multi.instance_count = 0
	_set_live_effect_bounds(instance, multi, AABB(), false)


func _safe_axis(axis: Vector3, fallback: Vector3) -> Vector3:
	return axis.normalized() if axis.is_finite() and axis.length_squared() > 1e-8 else fallback


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / maxf(edge1 - edge0, 0.00001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _number_or(value: Variant, fallback: float, low: float, high: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), low, high)
