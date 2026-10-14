## FW-84 presentation consumer: one event schedule, cloud overlay, bolt mesh and transient light.
extends Node3D

const StormEvents = preload("res://environment/storm_events.gd")
const StormAudio = preload("res://audio/storm_audio.gd")
const CLOUD_FLASH_SHADER: Shader = preload("res://render/weather/cloud_flash.gdshader")
const LIGHTNING_BOLT_SHADER: Shader = preload("res://render/weather/lightning_bolt.gdshader")
const EVENT_LOOKBACK_S: float = 0.12
const LIGHTNING_DISPLAY_CAP: float = 2.0
const MIN_SOUND_SPEED_MPS: float = 300.0
const CLOUD_PLANE_SIZE_M: float = 180000.0
const DEFAULT_CLOUD_ALTITUDE_M: float = 3900.0
const DEFAULT_CLOUD_SCALE_M: float = 6000.0
const CLOUD_FLASH_RADIUS_M: float = 4200.0
const MAX_PATH_SEGMENTS: int = 28
const BOLT_HALO_HALF_WIDTH_M: float = 140.0
const BOLT_CORE_HALF_WIDTH_M: float = 50.0

enum FlashMode { FULL, REDUCED, OFF }

var _events: StormEvents = StormEvents.new()
var _audio: StormAudio = null
var _active: bool = false
var _flash_mode: int = FlashMode.FULL
var _sound_speed_mps: float = 343.0
var _audio_allowed: bool = true
var _audio_rebuild_pending: bool = false
var _last_time_s: float = -1.0
var _last_tick: int = -1
var _cloud_altitude_m: float = DEFAULT_CLOUD_ALTITUDE_M
var _cloud_scale_m: float = DEFAULT_CLOUD_SCALE_M
var _cloud_offset: Vector2 = Vector2.ZERO
var _cloud_seed: int = 1
var _cloud_coverage: float = 0.94
var _cloud_density_scale: float = 0.97
var _cluster_strength: float = 0.65
var _cloud_state_valid: bool = false
var _current_event_id: String = ""
var _world_light: DirectionalLight3D = null
var _cloud_deck: MeshInstance3D = null
var _cloud_material: ShaderMaterial = null
var _bolt_halo: MeshInstance3D = null
var _bolt_core: MeshInstance3D = null
var _halo_material: ShaderMaterial = null
var _core_material: ShaderMaterial = null
var _bolt_event_id: String = ""
var _bank_ref: WeakRef
var _cell_transport: Dictionary = {}
var _presented_event: Dictionary = {}
var _presented_level := 0.0
var _event_placement: Dictionary = {}


func configure(config: Dictionary) -> void:
	reset()
	_active = str(config.get("preset", "classic")) == "electrical_storm"
	_events.configure(config)
	if _cloud_state_valid:
		_events.set_cloud_altitude(_cloud_altitude_m - 300.0)
	var mode: String = str(config.get("flashes", "full")).to_lower()
	match mode:
		"reduced":
			_flash_mode = FlashMode.REDUCED
		"off":
			_flash_mode = FlashMode.OFF
		_:
			_flash_mode = FlashMode.FULL
	if not _active:
		set_process(false)
		return
	set_process(true)
	_ensure_visuals()
	_ensure_audio()
	_audio.set_audio_enabled(_audio_allowed)
	_audio.configure(config)
	_audio.set_sound_speed(_sound_speed_mps)
	_audio_rebuild_pending = _audio_allowed
	_clear_visuals()


func update_at(sim_time_s: float, listener_position: Vector3, paused: bool,
		exposure: float = 1.0) -> void:
	if not _active:
		return
	var bank := _bank()
	if bank != null and bank.visible:
		bank.select_view_copy(listener_position)
	_events.set_cell_context(bank.cell_spec() if bank != null and bank.visible else {},
		_cell_transport, listener_position)
	var now_s: float = maxf(sim_time_s, 0.0)
	var now_tick: int = _events.tick_for_time(now_s)
	if paused:
		_clear_visuals()
		var paused_events: Array[Dictionary] = _restore_audio_events(now_s, now_tick)
		_audio.update_at(now_s, listener_position, true, _sound_speed_mps, paused_events)
		_last_time_s = now_s
		_last_tick = now_tick
		return
	if _last_time_s >= 0.0 and now_s < _last_time_s:
		# A restored time invalidates old playback; the next update rebuilds only still-travelling thunder.
		_audio.reset()
		_audio_rebuild_pending = _audio_allowed
		_last_time_s = now_s
		_last_tick = now_tick
		_clear_visuals()
		_event_placement.clear()
		_bolt_event_id = ""
		return
	var discontinuity: bool = _last_time_s >= 0.0 and now_s - _last_time_s > 0.5
	if discontinuity:
		_audio.reset()
		_audio_rebuild_pending = _audio_allowed
		_event_placement.clear()
		_bolt_event_id = ""
	var from_s: float = now_s - (1.0 / float(_events.tick_rate_hz())) if _last_time_s < 0.0 else _last_time_s
	# A large seek/hitch should not flash historical pulses or queue a backlog of old cracks.
	from_s = maxf(from_s, now_s - EVENT_LOOKBACK_S)
	var from_tick: int = maxi(0, _events.tick_for_time(from_s))
	var events: Array[Dictionary] = _events.events_for_window(from_tick, now_tick)
	var selected: Dictionary = {}
	var selected_level: float = 0.0
	for event: Dictionary in events:
		var level: float = _pulse_peak_in_interval(event, from_s, now_s)
		if level > selected_level:
			selected = event
			selected_level = level
	if _flash_mode == FlashMode.OFF:
		selected_level = 0.0
	var safe_exposure: float = maxf(exposure, 0.001)
	_apply_event(selected, selected_level, listener_position, safe_exposure)
	var new_audio_events: Array[Dictionary] = _restore_audio_events(now_s, now_tick)
	if not _audio_rebuild_pending and _audio_allowed and not discontinuity \
			and _last_tick >= 0 and now_s - _last_time_s <= 0.5:
		new_audio_events = _events.events_started_between(_last_tick, now_tick)
	_audio.update_at(now_s, listener_position, false, _sound_speed_mps, new_audio_events)
	_last_time_s = now_s
	_last_tick = now_tick


func bind_storm_bank(bank: Node3D) -> void:
	if bank == _bank():
		return
	var previous := _bank()
	if previous != null:
		previous.apply_flash({}, 0.0, 1.0)
	_bank_ref = weakref(bank) if bank != null else null
	_bolt_event_id = ""
	_event_placement.clear()


func set_cell_transport(transport: Dictionary) -> void:
	if transport != _cell_transport:
		_cell_transport = transport.duplicate(true)


func _bank() -> Node3D:
	return _bank_ref.get_ref() as Node3D if _bank_ref != null else null


func _exit_tree() -> void:
	# A retained World may outlive the presentation consumer (Workshop/scene replacement).
	reset()


func snapshot() -> Dictionary:
	return {event_id = _current_event_id, level = _presented_level,
		source_world = _presented_event.get("source_world", PackedFloat64Array()).duplicate(),
		mode = _flash_mode, bank_bound = _bank() != null,
		light_energy = _world_light.light_energy if _world_light != null else 0.0,
		pending_thunder = _audio._pending.size() if _audio != null else 0,
		node_count = get_child_count()}


func _restore_audio_events(now_s: float, now_tick: int) -> Array[Dictionary]:
	if not _audio_allowed or not _audio_rebuild_pending:
		return []
	# AudioStreamPlayer3D is inaudible beyond its range. Reconstruct at most the sound's
	# maximum travel time, then let StormAudio discard arrivals that have already passed.
	var delay_limit_s: float = StormAudio.MAX_AUDIBLE_DISTANCE_M / MIN_SOUND_SPEED_MPS + 0.25
	var from_tick: int = _events.tick_for_time(maxf(0.0, now_s - delay_limit_s))
	_audio_rebuild_pending = false
	return _events.events_started_in_window(from_tick, now_tick)


func set_cloud_state(snapshot: Dictionary) -> void:
	var layers_value: Variant = snapshot.get("cloud_layers", [])
	if not layers_value is Array:
		_cloud_state_valid = false
		return
	var layers: Array = layers_value
	# The profile-wide adjustments are separate from each layer's raw values in
	# Atmosphere.cloud_state_snapshot(). Apply them here once so the local deck
	# samples the same effective mask/opacity as sky.gdshader.
	var profile_cover: float = clampf(float(snapshot.get("cloud_cover", 0.5)), 0.0, 1.0)
	var profile_density: float = clampf(float(snapshot.get("cloud_density", 1.0)), 0.0, 1.0)
	var chosen: Dictionary = {}
	var best_density: float = -1.0
	for value: Variant in layers:
		if not value is Dictionary:
			continue
		var layer: Dictionary = value
		var type_name: String = str(layer.get("type", "")).to_lower()
		var density: float = clampf(float(layer.get("density", 0.0)), 0.0, 1.0)
		var storm_layer: bool = type_name.contains("cumulonimbus") or type_name.contains("storm")
		var chosen_storm: bool = str(chosen.get("type", "")).to_lower().contains("cumulonimbus") \
			or str(chosen.get("type", "")).to_lower().contains("storm")
		if (storm_layer and not chosen_storm) or (storm_layer == chosen_storm and density > best_density):
			chosen = layer
			best_density = density
	if chosen.is_empty():
		_cloud_state_valid = false
		return
	var next_altitude: float = maxf(float(chosen.get("altitude_m", DEFAULT_CLOUD_ALTITUDE_M)), 100.0)
	var next_scale: float = maxf(float(chosen.get("scale_m", DEFAULT_CLOUD_SCALE_M)), 1.0)
	var next_offset: Vector2 = _as_vector2(chosen.get("offset", Vector2.ZERO))
	var next_seed: int = int(chosen.get("seed", 1))
	var raw_coverage: float = clampf(float(chosen.get("coverage", 0.0)), 0.0, 1.0)
	var raw_density: float = clampf(float(chosen.get("density", 1.0)), 0.0, 1.0)
	var next_coverage: float = clampf(raw_coverage + (profile_cover - 0.5) * 0.5, 0.0, 1.0)
	var next_density_scale: float = clampf(raw_density * profile_density, 0.0, 1.0)
	var next_cluster: float = clampf(float(chosen.get("cluster_strength", 0.0)), 0.0, 1.0)
	var changed: bool = not _cloud_state_valid or _cloud_altitude_m != next_altitude \
		or _cloud_scale_m != next_scale or _cloud_offset != next_offset or _cloud_seed != next_seed \
		or _cloud_coverage != next_coverage or _cloud_density_scale != next_density_scale \
		or _cluster_strength != next_cluster
	_cloud_state_valid = true
	_cloud_altitude_m = next_altitude
	_cloud_scale_m = next_scale
	_cloud_offset = next_offset
	_cloud_seed = next_seed
	_cloud_coverage = next_coverage
	_cloud_density_scale = next_density_scale
	_cluster_strength = next_cluster
	if changed:
		_events.set_cloud_altitude(_cloud_altitude_m - 300.0)
	if changed and _cloud_material != null:
		_apply_cloud_parameters()


func set_sound_speed(value: float) -> void:
	_sound_speed_mps = clampf(value, 300.0, 380.0)
	if _audio != null:
		_audio.set_sound_speed(_sound_speed_mps)


func set_audio_enabled(enabled_value: bool) -> void:
	var was_enabled: bool = _audio_allowed
	_audio_allowed = enabled_value
	if not enabled_value:
		_audio_rebuild_pending = false
	elif not was_enabled:
		_audio_rebuild_pending = true
	if _audio != null:
		_audio.set_audio_enabled(enabled_value)


func reset() -> void:
	_last_time_s = -1.0
	_last_tick = -1
	_current_event_id = ""
	_bolt_event_id = ""
	_event_placement.clear()
	_events.reset()
	_clear_visuals()
	if _audio != null:
		_audio.reset()
	_audio_rebuild_pending = _audio_allowed


func _ensure_visuals() -> void:
	if _world_light == null:
		_world_light = DirectionalLight3D.new()
		_world_light.name = "StormLightningLight"
		_world_light.light_color = Color(0.84, 0.91, 1.0)
		_world_light.light_energy = 0.0
		_world_light.shadow_enabled = false
		_world_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		add_child(_world_light)
	if _cloud_deck == null:
		_cloud_material = ShaderMaterial.new()
		_cloud_material.shader = CLOUD_FLASH_SHADER
		_cloud_material.set_shader_parameter("display_cap", LIGHTNING_DISPLAY_CAP)
		_cloud_material.set_shader_parameter("flash_radius_m", CLOUD_FLASH_RADIUS_M)
		_cloud_deck = MeshInstance3D.new()
		_cloud_deck.name = "StormCloudFlashDeck"
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2(CLOUD_PLANE_SIZE_M, CLOUD_PLANE_SIZE_M)
		_cloud_deck.mesh = plane
		_cloud_deck.material_override = _cloud_material
		_cloud_deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cloud_deck.position = Vector3(0.0, _cloud_altitude_m, 0.0)
		add_child(_cloud_deck)
		_apply_cloud_parameters()
	if _bolt_halo == null:
		_halo_material = ShaderMaterial.new()
		_halo_material.shader = LIGHTNING_BOLT_SHADER
		_halo_material.set_shader_parameter("core_pass", false)
		_halo_material.set_shader_parameter("bolt_intensity", 0.0)
		_halo_material.set_shader_parameter("display_cap", LIGHTNING_DISPLAY_CAP)
		_bolt_halo = MeshInstance3D.new()
		_bolt_halo.name = "StormBoltHalo"
		_bolt_halo.material_override = _halo_material
		_bolt_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bolt_halo)
	if _bolt_core == null:
		_core_material = ShaderMaterial.new()
		_core_material.shader = LIGHTNING_BOLT_SHADER
		_core_material.set_shader_parameter("core_pass", true)
		_core_material.set_shader_parameter("bolt_intensity", 0.0)
		_core_material.set_shader_parameter("display_cap", LIGHTNING_DISPLAY_CAP)
		_bolt_core = MeshInstance3D.new()
		_bolt_core.name = "StormBoltCore"
		_bolt_core.material_override = _core_material
		_bolt_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_bolt_core)
	_clear_visuals()


func _ensure_audio() -> void:
	if _audio != null:
		return
	_audio = StormAudio.new()
	_audio.name = "StormAudio"
	add_child(_audio)


func _apply_cloud_parameters() -> void:
	if _cloud_material == null:
		return
	_cloud_material.set_shader_parameter("cloud_altitude_m", _cloud_altitude_m)
	_cloud_material.set_shader_parameter("cloud_scale_m", _cloud_scale_m)
	_cloud_material.set_shader_parameter("cloud_offset", _cloud_offset)
	_cloud_material.set_shader_parameter("cloud_seed", _cloud_seed)
	_cloud_material.set_shader_parameter("cloud_coverage", _cloud_coverage)
	_cloud_material.set_shader_parameter("cloud_density_scale", _cloud_density_scale)
	_cloud_material.set_shader_parameter("cluster_strength", _cluster_strength)
	if _cloud_deck != null:
		_cloud_deck.position.y = _cloud_altitude_m


func _apply_event(event: Dictionary, level: float, listener_position: Vector3, exposure: float) -> void:
	var bounded_level: float = clampf(level, 0.0, 1.0)
	if event.is_empty() or bounded_level <= 0.001 or _flash_mode == FlashMode.OFF:
		_current_event_id = ""
		_clear_visuals()
		return
	var event_id: String = str(event.event_id)
	var event_changed: bool = _current_event_id != event_id
	# Freeze one emitted channel through all its pulses and camera cuts. Future schedule queries
	# stay pure; only this bounded presentation record retains the already displayed world copy.
	if str(_event_placement.get("event_id", "")) != event_id:
		_event_placement = event.duplicate(true)
	event = _event_placement
	_current_event_id = event_id
	_presented_event = event.duplicate(true)
	_presented_level = bounded_level * (0.18 if _flash_mode == FlashMode.REDUCED else 1.0)
	var source: Vector3 = _as_vector3(event.get("source_world", PackedFloat64Array()))
	var bank := _bank()
	var has_bank := bank != null and bank.visible and str(event.get("placement_mode", "")) == "storm_cell"
	if has_bank:
		bank.apply_flash(event, _presented_level, exposure)
	elif bank != null:
		bank.apply_flash({}, 0.0, exposure)
	if _cloud_material != null:
		_cloud_material.set_shader_parameter("scene_exposure", exposure)
		if event_changed:
			_cloud_material.set_shader_parameter("flash_source", source)
		_cloud_material.set_shader_parameter("flash_intensity",
			bounded_level * (0.27 if _flash_mode == FlashMode.REDUCED else 0.9))
		_cloud_deck.visible = _cloud_state_valid and _flash_mode != FlashMode.OFF and not has_bank
	if _flash_mode == FlashMode.FULL and str(event.get("kind", "")) == "cloud_to_ground":
		if _bolt_event_id != event_id:
			_build_bolt_meshes(event)
			_bolt_event_id = event_id
		_bolt_halo.visible = _bolt_halo.mesh != null
		_bolt_core.visible = _bolt_core.mesh != null
		_halo_material.set_shader_parameter("bolt_intensity", bounded_level)
		_core_material.set_shader_parameter("bolt_intensity", bounded_level)
		_halo_material.set_shader_parameter("scene_exposure", exposure)
		_core_material.set_shader_parameter("scene_exposure", exposure)
	else:
		_bolt_halo.visible = false
		_bolt_core.visible = false
		_halo_material.set_shader_parameter("bolt_intensity", 0.0)
		_core_material.set_shader_parameter("bolt_intensity", 0.0)
	if _flash_mode == FlashMode.FULL:
		_configure_light(source, listener_position, bounded_level, exposure)
	else:
		_world_light.light_energy = 0.0


func _configure_light(source: Vector3, listener_position: Vector3, level: float, exposure: float) -> void:
	var toward_source: Vector3 = source - listener_position
	if toward_source.length_squared() <= 1e-6:
		_world_light.light_energy = 0.0
		return
	var direction: Vector3 = toward_source.normalized()
	var up: Vector3 = Vector3.FORWARD if absf(direction.y) > 0.999 else Vector3.UP
	_world_light.global_transform = Transform3D(Basis.looking_at(-direction, up), source)
	# Cap only the transient storm contribution to the accepted scene exposure; the
	# World baseline and all other lights remain owned by the existing exposure path.
	_world_light.light_energy = minf(1.15 * level, LIGHTNING_DISPLAY_CAP / maxf(exposure, 0.001))


func _build_bolt_meshes(event: Dictionary) -> void:
	var source: Vector3 = _as_vector3(event.get("source_world", PackedFloat64Array()))
	var ground: Vector3 = _as_vector3(event.get("ground_world", PackedFloat64Array()))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(event.get("geometry_seed", 1))
	var main_path: Array[Vector3] = _make_main_channel(source, ground, rng)
	var paths: Array = [main_path]
	var branch_count: int = rng.randi_range(3, 5)
	for branch_index: int in branch_count:
		paths.append(_make_branch(main_path, rng, branch_index))
	_bolt_halo.mesh = _make_ribbon_mesh(paths, BOLT_HALO_HALF_WIDTH_M)
	_bolt_core.mesh = _make_ribbon_mesh(paths, BOLT_CORE_HALF_WIDTH_M)


func _make_main_channel(source: Vector3, ground: Vector3, rng: RandomNumberGenerator) -> Array[Vector3]:
	var point_count: int = MAX_PATH_SEGMENTS
	var path: Array[Vector3] = []
	var horizontal_drift: Vector2 = Vector2.ZERO
	for index: int in point_count + 1:
		var t: float = float(index) / float(point_count)
		var envelope: float = sin(PI * t)
		if index > 0 and index < point_count:
			horizontal_drift += Vector2(rng.randf_range(-105.0, 105.0), rng.randf_range(-105.0, 105.0))
			horizontal_drift = horizontal_drift.lerp(Vector2.ZERO, 0.075)
		var point: Vector3 = source.lerp(ground, t)
		point.x += horizontal_drift.x * envelope
		point.z += horizontal_drift.y * envelope
		path.append(point)
	return path


func _make_branch(main_path: Array[Vector3], rng: RandomNumberGenerator, branch_index: int) -> Array[Vector3]:
	var anchor_index: int = rng.randi_range(3, main_path.size() - 5)
	var origin: Vector3 = main_path[anchor_index]
	var sign: float = -1.0 if (branch_index % 2 == 0) else 1.0
	var total_side: float = sign * rng.randf_range(260.0, 780.0)
	var total_drop: float = rng.randf_range(420.0, 1150.0)
	var branch_steps: int = rng.randi_range(4, 8)
	var path: Array[Vector3] = [origin]
	var jitter: Vector3 = Vector3.ZERO
	for step_index: int in branch_steps:
		var t: float = float(step_index + 1) / float(branch_steps)
		jitter += Vector3(rng.randf_range(-65.0, 65.0), rng.randf_range(-35.0, 35.0), rng.randf_range(-65.0, 65.0))
		var point: Vector3 = origin + Vector3(total_side * t, -total_drop * t, sign * total_side * 0.28 * t) + jitter
		path.append(point)
	return path


func _make_ribbon_mesh(paths: Array, half_width_m: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for path_value: Variant in paths:
		if not path_value is Array:
			continue
		var path: Array = path_value
		if path.size() < 2:
			continue
		for segment: int in path.size() - 1:
			var start: Vector3 = path[segment]
			var finish: Vector3 = path[segment + 1]
			var direction: Vector3 = (finish - start).normalized()
			if direction.length_squared() < 0.5:
				continue
			var side: Vector3 = direction.cross(Vector3.UP)
			if side.length_squared() < 0.01:
				side = direction.cross(Vector3.RIGHT)
			side = side.normalized()
			var other_side: Vector3 = direction.cross(side).normalized()
			var taper_start: bool = segment == 0
			var taper_finish: bool = segment == path.size() - 2
			_add_ribbon_quad(vertices, normals, uvs, indices, start, finish, side, half_width_m,
				taper_start, taper_finish)
			_add_ribbon_quad(vertices, normals, uvs, indices, start, finish, other_side,
				half_width_m * 0.82, taper_start, taper_finish)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result


func _add_ribbon_quad(vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array, start: Vector3, finish: Vector3,
		side: Vector3, half_width_m: float, taper_start: bool, taper_finish: bool) -> void:
	var start_width: float = half_width_m * (0.12 if taper_start else 1.0)
	var finish_width: float = half_width_m * (0.12 if taper_finish else 1.0)
	var first_index: int = vertices.size()
	vertices.append(_point_to_local(start - side * start_width))
	vertices.append(_point_to_local(start + side * start_width))
	vertices.append(_point_to_local(finish + side * finish_width))
	vertices.append(_point_to_local(finish - side * finish_width))
	var face_normal: Vector3 = side.cross(finish - start).normalized()
	for unused: int in 4:
		normals.append(face_normal)
	# Segment endpoints meet at full width; only the ends of each whole path taper.
	uvs.append(Vector2(0.0, 0.5))
	uvs.append(Vector2(1.0, 0.5))
	uvs.append(Vector2(1.0, 0.5))
	uvs.append(Vector2(0.0, 0.5))
	indices.append_array(PackedInt32Array([
		first_index, first_index + 1, first_index + 2,
		first_index, first_index + 2, first_index + 3,
	]))


func _point_to_local(point_world: Vector3) -> Vector3:
	return to_local(point_world) if is_inside_tree() else point_world


func _pulse_peak_in_interval(event: Dictionary, from_s: float, to_s: float) -> float:
	var start_s: float = float(event.get("start_time_s", 0.0))
	var peak: float = 0.0
	var pulses: Variant = event.get("pulse_envelope", [])
	if not pulses is Array:
		return 0.0
	for pulse_value: Variant in pulses:
		if not pulse_value is Dictionary:
			continue
		var pulse: Dictionary = pulse_value
		var pulse_start: float = start_s + float(pulse.get("offset_s", 0.0))
		var duration: float = maxf(float(pulse.get("duration_s", 0.0)), 0.001)
		var pulse_end: float = pulse_start + duration
		if pulse_end < from_s or pulse_start > to_s:
			continue
		var midpoint: float = clampf((to_s + from_s) * 0.5, pulse_start, pulse_end)
		var local: float = (midpoint - pulse_start) / duration
		var attack: float = smoothstep(0.0, 0.14, local)
		var decay: float = 1.0 - smoothstep(0.55, 1.0, local)
		var envelope: float = maxf(attack * decay, 0.16)
		peak = maxf(peak, envelope * clampf(float(pulse.get("intensity", 0.0)), 0.0, 1.0))
	return peak * clampf(float(event.get("intensity", 1.0)), 0.0, 1.0)


func _clear_visuals() -> void:
	_current_event_id = ""
	_presented_event = {}
	_presented_level = 0.0
	var bank := _bank()
	if bank != null:
		bank.apply_flash({}, 0.0, 1.0)
	if _world_light != null:
		_world_light.light_energy = 0.0
	if _cloud_deck != null:
		_cloud_deck.visible = false
	if _bolt_halo != null:
		_bolt_halo.visible = false
	if _bolt_core != null:
		_bolt_core.visible = false
	if _cloud_material != null:
		_cloud_material.set_shader_parameter("flash_intensity", 0.0)
	if _halo_material != null:
		_halo_material.set_shader_parameter("bolt_intensity", 0.0)
	if _core_material != null:
		_core_material.set_shader_parameter("bolt_intensity", 0.0)


static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


static func _as_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is PackedFloat32Array and value.size() >= 2:
		return Vector2(value[0], value[1])
	if value is PackedFloat64Array and value.size() >= 2:
		return Vector2(value[0], value[1])
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
