extends Node3D
class_name WaterEffects

## Small, bounded, render-only water impact presentation. Impact locations use
## world NED metres; visuals are placed on the configured mean water plane.
## Aircraft sinking changes only the supplied render root, never simulation state.
const ImpactSnapshot = preload("res://physics/impact_snapshot.gd")
const SPLASH_ONE: AudioStreamWAV = preload("res://assets/audio/water/peludo-splash1.wav")
const SPLASH_TWO: AudioStreamWAV = preload("res://assets/audio/water/peludo-splash2.wav")
const VISTULA_AMBIENCE: AudioStreamMP3 = preload("res://assets/audio/water/randommind-vistula-short.mp3")

const CHECKPOINT_VERSION := 1
const MAX_DROPLETS := 16
const RING_COUNT := 2
const MAX_EFFECT_DURATION_S := 3.2
const PLUME_DURATION_S := 0.82
const SINK_DURATION_S := 2.8
const SINK_DEPTH_M := 0.55
const MAX_LAKE_DEPTH_M := 20.0
const MAX_WORLD_COORD_M := 1_100_000.0
const MAX_FRAME_DELTA_S := 0.25
const RING_SEGMENTS := 48

const FX_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 tint : source_color = vec4(0.39, 0.68, 0.68, 0.42);
uniform float effect_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float effect_clock_s = 0.0;
uniform vec2 wind_xz = vec2(0.8, 0.6);
uniform float wind_rate = 1.0;
uniform float wave_height_m : hint_range(0.0, 0.012) = 0.006;

void vertex() {
	float phase = 7.0 * length(VERTEX.xz)
		+ 2.0 * dot(VERTEX.xz, wind_xz)
		- effect_clock_s * wind_rate;
	VERTEX.y += clamp(wave_height_m, 0.0, 0.012) * sin(phase)
		* clamp(effect_alpha, 0.0, 1.0);
}

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb;
	ALPHA = tint.a * clamp(effect_alpha, 0.0, 1.0) * COLOR.a;
}
"""

var _configured: bool = false
var _audio_enabled: bool = true
var _lake: Dictionary = {}
var _water_level_down_m: float = 0.45
var _lake_depth_m: float = 5.0
var _wind_xz: Vector2 = Vector2(0.8, 0.6)
var _wind_rate: float = 1.0

var _has_event: bool = false
var _elapsed_s: float = 0.0
var _impact_point_ned: PackedFloat64Array = PackedFloat64Array()
var _impact_depth_m: float = 0.0
var _event_seed: int = 1
var _impact_audio_emitted: bool = false
var _impact_audio_source_index: int = -1
var _impact_audio_requests_this_event: int = 0

var _fx_shader: Shader
var _plume: MeshInstance3D
var _plume_material: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[ShaderMaterial] = []
var _droplets: MultiMeshInstance3D
var _droplet_multimesh: MultiMesh
var _droplet_material: StandardMaterial3D
var _droplet_velocities: Array[Vector3] = []
var _droplet_delays: PackedFloat32Array = PackedFloat32Array()
var _droplet_lifetimes: PackedFloat32Array = PackedFloat32Array()
var _droplet_radii: PackedFloat32Array = PackedFloat32Array()
var _impact_voice: AudioStreamPlayer3D

var _aircraft_root: Node3D
var _aircraft_base_transform: Transform3D = Transform3D.IDENTITY
var _has_aircraft_base: bool = false


## `lake` must be LakeLoader's normalized dictionary. The scenery owner adds this
## node to the render world and calls update with the user's pause state.
func configure(lake: Dictionary, audio_enabled: bool = true) -> bool:
	clear()
	var raw_level: Variant = lake.get("water_level_down_m")
	if not _is_finite_number(raw_level) or float(raw_level) < 0.05 or float(raw_level) > 2.0:
		push_error("WaterEffects.configure requires a normalized lake water_level_down_m in [0.05, 2.0].")
		_configured = false
		_lake = {}
		return false
	_lake = lake.duplicate(true)
	_water_level_down_m = float(raw_level)
	_lake_depth_m = _read_max_depth(_lake)
	var wind_ne: Variant = _lake.get("wind_ne_mps", _lake.get("wind_ne", []))
	var wind_vector := _read_wind_xz(wind_ne)
	_wind_xz = wind_vector.direction
	_wind_rate = wind_vector.rate
	_audio_enabled = audio_enabled
	_ensure_nodes()
	_configured = true
	_set_effect_materials(0.0)
	return true


## Begin one water impact. `point_ned` is the observed N/E/D contact in metres.
## A Snapshot without kinematics is intentionally ignored because it has no
## trustworthy impact position. A Dictionary uses the same `point_ned` field.
func begin(impact: Variant, aircraft_root: Node3D = null) -> bool:
	if not _configured:
		push_error("WaterEffects.begin requires configure() first.")
		return false
	var point: PackedFloat64Array = _impact_point(impact)
	if point.size() != 3:
		return false
	for coordinate: float in point:
		if not is_finite(coordinate) or absf(coordinate) > MAX_WORLD_COORD_M:
			return false

	clear()
	_has_event = true
	_elapsed_s = 0.0
	_impact_point_ned = point
	_impact_depth_m = clampf(maxf(point[2] - _water_level_down_m, 0.0), 0.0, _lake_depth_m)
	_event_seed = _seed_for_impact(point, _impact_tick(impact))
	if is_instance_valid(aircraft_root):
		_aircraft_root = aircraft_root
		_aircraft_base_transform = aircraft_root.global_transform
		_has_aircraft_base = true
	_generate_droplets(_event_seed)
	_sync_visuals()
	_play_impact_voice()
	return true


## Advance only when the caller says the user has not paused. Crash freeze or
## physics-session hold state is deliberately not inferred here.
func update(dt: float, paused: bool = false) -> void:
	if _impact_voice != null and _impact_voice.playing:
		_impact_voice.stream_paused = paused
	if not _has_event:
		return
	if not paused and is_finite(dt) and dt > 0.0:
		_elapsed_s = minf(_elapsed_s + minf(dt, MAX_FRAME_DELTA_S), MAX_EFFECT_DURATION_S)
	_sync_visuals()
	_sync_aircraft_sink()


## Hide pooled visuals, stop only the impact one-shot, and restore the visual root.
## The separate ambient player returned by ambient_player() is not owned here.
func clear() -> void:
	if _has_aircraft_base and is_instance_valid(_aircraft_root):
		_aircraft_root.global_transform = _aircraft_base_transform
	_aircraft_root = null
	_has_aircraft_base = false
	_has_event = false
	_elapsed_s = 0.0
	_impact_point_ned = PackedFloat64Array()
	_impact_depth_m = 0.0
	_impact_audio_emitted = false
	_impact_audio_source_index = -1
	_impact_audio_requests_this_event = 0
	if _impact_voice != null:
		_impact_voice.stop()
		_impact_voice.stream_paused = false
		_impact_voice.stream = null
	_hide_visuals()


## Render-only state; sound is marked as already emitted and is never replayed by restore.
func checkpoint() -> Dictionary:
	return {
		"version": CHECKPOINT_VERSION,
		"has_event": _has_event,
		"elapsed_s": _elapsed_s,
		"point_ned": _impact_point_ned.duplicate(),
		"impact_depth_m": _impact_depth_m,
		"seed": _event_seed,
		"impact_audio_emitted": _impact_audio_emitted,
		"impact_audio_source_index": _impact_audio_source_index,
	}


## Validate without mutating this node. Empty Dictionary means the state is invalid.
func prepare_restore(state: Variant) -> Dictionary:
	if typeof(state) != TYPE_DICTIONARY:
		return {}
	var raw: Dictionary = state
	if raw.get("version") != CHECKPOINT_VERSION or typeof(raw.get("has_event")) != TYPE_BOOL:
		return {}
	var has_event: bool = raw["has_event"]
	var prepared := {
		"version": CHECKPOINT_VERSION,
		"has_event": has_event,
		"elapsed_s": 0.0,
		"point_ned": PackedFloat64Array(),
		"impact_depth_m": 0.0,
		"seed": 1,
		"impact_audio_emitted": false,
		"impact_audio_source_index": -1,
	}
	if not has_event:
		return prepared

	var elapsed: Variant = raw.get("elapsed_s")
	var depth: Variant = raw.get("impact_depth_m")
	var seed_value: Variant = raw.get("seed")
	var audio_emitted: Variant = raw.get("impact_audio_emitted")
	var audio_source: Variant = raw.get("impact_audio_source_index")
	var point := _read_point_ned(raw.get("point_ned"))
	if not _is_finite_number(elapsed) or float(elapsed) < 0.0 or float(elapsed) > MAX_EFFECT_DURATION_S:
		return {}
	if not _is_finite_number(depth) or float(depth) < 0.0 or float(depth) > _lake_depth_m:
		return {}
	if typeof(seed_value) != TYPE_INT or int(seed_value) < 1 or int(seed_value) > 2_147_483_647:
		return {}
	if typeof(audio_emitted) != TYPE_BOOL or typeof(audio_source) != TYPE_INT:
		return {}
	if bool(audio_emitted):
		if int(audio_source) < 0 or int(audio_source) > 1:
			return {}
	elif int(audio_source) != -1:
		return {}
	if point.size() != 3:
		return {}
	for coordinate: float in point:
		if not is_finite(coordinate) or absf(coordinate) > MAX_WORLD_COORD_M:
			return {}
	prepared["elapsed_s"] = float(elapsed)
	prepared["point_ned"] = point
	prepared["impact_depth_m"] = float(depth)
	prepared["seed"] = int(seed_value)
	prepared["impact_audio_emitted"] = bool(audio_emitted)
	prepared["impact_audio_source_index"] = int(audio_source)
	return prepared


## Restore phase and visuals without replaying audio. An optional new aircraft root
## captures its current transform as the sink's unsunk baseline.
func restore(state: Variant, aircraft_root: Node3D = null) -> bool:
	var prepared: Dictionary = prepare_restore(state)
	if prepared.is_empty():
		return false
	if bool(prepared.has_event) and not _configured:
		return false
	var selected_root: Node3D = aircraft_root if is_instance_valid(aircraft_root) else _aircraft_root
	var selected_base: Transform3D = _aircraft_base_transform if selected_root == _aircraft_root and _has_aircraft_base \
		else (selected_root.global_transform if is_instance_valid(selected_root) else Transform3D.IDENTITY)
	clear()
	if not bool(prepared.has_event):
		return true
	_has_event = true
	_elapsed_s = float(prepared.elapsed_s)
	_impact_point_ned = prepared.point_ned.duplicate()
	_impact_depth_m = float(prepared.impact_depth_m)
	_event_seed = int(prepared.seed)
	_impact_audio_emitted = bool(prepared.impact_audio_emitted)
	_impact_audio_source_index = int(prepared.impact_audio_source_index)
	if is_instance_valid(selected_root):
		_aircraft_root = selected_root
		_aircraft_base_transform = selected_base
		_has_aircraft_base = true
	_generate_droplets(_event_seed)
	if _impact_audio_emitted and _impact_voice != null:
		_impact_voice.stream = _splash_stream(_impact_audio_source_index)
		_impact_voice.global_position = _surface_world_position()
		# Deliberately leave playback stopped: a checkpoint restore cannot duplicate the event sound.
	_sync_visuals()
	_sync_aircraft_sink()
	return true


## A standalone localized ambience player. Audio is disabled by omitting its stream.
## The licensed five-minute river recording loops; source and license are in audio/water/LICENSES.md.
static func ambient_player(lake: Dictionary, audio_on: bool = true) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "LakeWaterAmbience"
	player.max_polyphony = 1
	player.unit_size = 12.0
	player.max_distance = 120.0
	player.volume_db = -28.0 if audio_on else -80.0
	player.panning_strength = 0.6
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.position = _lake_center_world(lake)
	if audio_on:
		var loop_stream := VISTULA_AMBIENCE.duplicate() as AudioStreamMP3
		loop_stream.loop = true
		loop_stream.loop_offset = 0.0
		player.stream = loop_stream
		player.autoplay = true
	return player


func _ensure_nodes() -> void:
	if _plume != null:
		return
	_fx_shader = Shader.new()
	_fx_shader.code = FX_SHADER_CODE

	var plume_mesh := CylinderMesh.new()
	plume_mesh.top_radius = 0.0
	plume_mesh.bottom_radius = 0.16
	plume_mesh.height = 0.36
	plume_mesh.radial_segments = 12
	plume_mesh.rings = 1
	_plume = MeshInstance3D.new()
	_plume.name = "WaterPlume"
	_plume.mesh = plume_mesh
	_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_plume_material = _new_effect_material(Color(0.72, 0.84, 0.81, 0.42), 0.004)
	_plume.material_override = _plume_material
	add_child(_plume)

	var ring_mesh := _make_ring_mesh()
	for ring_index: int in RING_COUNT:
		var ring := MeshInstance3D.new()
		ring.name = "WaterRing%d" % ring_index
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var color := Color(0.33, 0.62, 0.63, 0.42) if ring_index == 0 else Color(0.42, 0.69, 0.68, 0.31)
		var material := _new_effect_material(color, 0.003)
		ring.material_override = material
		add_child(ring)
		_rings.append(ring)
		_ring_materials.append(material)

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_droplet_multimesh = MultiMesh.new()
	_droplet_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_droplet_multimesh.use_colors = true
	_droplet_multimesh.mesh = sphere
	_droplet_multimesh.instance_count = MAX_DROPLETS
	_droplet_multimesh.visible_instance_count = MAX_DROPLETS
	_droplets = MultiMeshInstance3D.new()
	_droplets.name = "WaterDropletPool"
	_droplets.multimesh = _droplet_multimesh
	_droplets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_droplet_material = StandardMaterial3D.new()
	_droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_droplet_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_droplet_material.vertex_color_use_as_albedo = true
	_droplet_material.albedo_color = Color(0.48, 0.72, 0.72, 0.78)
	_droplet_material.render_priority = 2
	_droplets.material_override = _droplet_material
	add_child(_droplets)

	_impact_voice = AudioStreamPlayer3D.new()
	_impact_voice.name = "WaterImpactVoice"
	_impact_voice.max_polyphony = 1
	_impact_voice.unit_size = 12.0
	_impact_voice.max_distance = 120.0
	_impact_voice.panning_strength = 0.7
	_impact_voice.volume_db = -12.0
	_impact_voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_impact_voice)
	_hide_visuals()


func _new_effect_material(color: Color, wave_height: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _fx_shader
	material.render_priority = 2
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("effect_alpha", 0.0)
	material.set_shader_parameter("effect_clock_s", 0.0)
	material.set_shader_parameter("wind_xz", _wind_xz)
	material.set_shader_parameter("wind_rate", _wind_rate)
	material.set_shader_parameter("wave_height_m", wave_height)
	return material


func _make_ring_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var uvs := PackedVector2Array()
	for index: int in RING_SEGMENTS:
		var angle0 := TAU * float(index) / float(RING_SEGMENTS)
		var angle1 := TAU * float(index + 1) / float(RING_SEGMENTS)
		var inner0 := Vector3(cos(angle0) * 0.94, 0.0, sin(angle0) * 0.94)
		var outer0 := Vector3(cos(angle0), 0.0, sin(angle0))
		var inner1 := Vector3(cos(angle1) * 0.94, 0.0, sin(angle1) * 0.94)
		var outer1 := Vector3(cos(angle1), 0.0, sin(angle1))
		var base := vertices.size()
		vertices.append_array(PackedVector3Array([inner0, outer0, inner1, outer1]))
		normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
		uvs.append_array(PackedVector2Array([
			Vector2(cos(angle0) * 0.47 + 0.5, sin(angle0) * 0.47 + 0.5),
			Vector2(cos(angle0) * 0.5 + 0.5, sin(angle0) * 0.5 + 0.5),
			Vector2(cos(angle1) * 0.47 + 0.5, sin(angle1) * 0.47 + 0.5),
			Vector2(cos(angle1) * 0.5 + 0.5, sin(angle1) * 0.5 + 0.5),
		]))
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ring := ArrayMesh.new()
	ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return ring


func _generate_droplets(seed_value: int) -> void:
	_droplet_velocities.clear()
	_droplet_delays.resize(MAX_DROPLETS)
	_droplet_lifetimes.resize(MAX_DROPLETS)
	_droplet_radii.resize(MAX_DROPLETS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index: int in MAX_DROPLETS:
		var angle := rng.randf_range(0.0, TAU)
		var horizontal_speed := rng.randf_range(0.18, 0.75)
		var vertical_speed := rng.randf_range(0.8, 1.55)
		_droplet_velocities.append(Vector3(cos(angle) * horizontal_speed, vertical_speed, sin(angle) * horizontal_speed))
		_droplet_delays[index] = rng.randf_range(0.0, 0.12)
		_droplet_lifetimes[index] = rng.randf_range(0.42, 0.92)
		_droplet_radii[index] = rng.randf_range(0.012, 0.032)
		_hide_droplet(index)
	_droplets.visible = true


func _sync_visuals() -> void:
	if not _has_event or _plume == null:
		_hide_visuals()
		return
	_set_effect_materials(_elapsed_s)
	var surface := _surface_world_position()
	var shallow_scale := clampf(1.0 - 0.15 * _impact_depth_m / maxf(_lake_depth_m, 0.1), 0.85, 1.0)
	var plume_fade_in := smoothstep(0.0, 0.10, _elapsed_s)
	var plume_fade_out := 1.0 - smoothstep(0.48, PLUME_DURATION_S, _elapsed_s)
	var plume_alpha := clampf(plume_fade_in * plume_fade_out, 0.0, 1.0)
	_plume.visible = plume_alpha > 0.01
	var plume_height := lerpf(0.12, 0.85, smoothstep(0.0, 0.24, _elapsed_s)) * shallow_scale
	var plume_width := lerpf(1.5, 2.8, smoothstep(0.0, 0.18, _elapsed_s)) * shallow_scale
	_plume.global_transform = Transform3D(
		Basis.IDENTITY.scaled(Vector3(plume_width, plume_height / 0.36, plume_width)),
		surface + Vector3.UP * plume_height * 0.5
	)
	_plume_material.set_shader_parameter("effect_alpha", plume_alpha * 0.85)

	for ring_index: int in RING_COUNT:
		var start_delay := 0.04 + float(ring_index) * 0.12
		var duration := 1.55 + float(ring_index) * 0.55
		var progress := clampf((_elapsed_s - start_delay) / duration, 0.0, 1.0)
		var ring_alpha := (1.0 - smoothstep(0.58, 1.0, progress)) if _elapsed_s >= start_delay else 0.0
		var ring_radius := lerpf(0.10, 1.5 + float(ring_index) * 0.85, smoothstep(0.0, 1.0, progress))
		var ring := _rings[ring_index]
		ring.visible = ring_alpha > 0.01 and _elapsed_s < start_delay + duration
		ring.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(ring_radius, 1.0, ring_radius)), surface + Vector3.UP * (0.012 + 0.004 * ring_index))
		_ring_materials[ring_index].set_shader_parameter("effect_alpha", ring_alpha * (0.72 if ring_index == 0 else 0.58))

	_droplets.global_transform = Transform3D(Basis.IDENTITY, surface)
	var gravity := 2.6
	var any_droplet_visible := false
	for index: int in MAX_DROPLETS:
		var age := _elapsed_s - _droplet_delays[index]
		var lifetime := _droplet_lifetimes[index]
		if age < 0.0 or age > lifetime:
			_hide_droplet(index)
			continue
		var velocity := _droplet_velocities[index]
		var offset := Vector3(velocity.x * age, 0.08 + velocity.y * age - 0.5 * gravity * age * age, velocity.z * age)
		if offset.y <= 0.015:
			_hide_droplet(index)
			continue
		var fade := 1.0 - smoothstep(0.68, 1.0, age / lifetime)
		var radius := _droplet_radii[index]
		var droplet_basis := Basis.IDENTITY.scaled(Vector3(radius, radius, radius))
		_droplet_multimesh.set_instance_transform(index, Transform3D(droplet_basis, offset))
		_droplet_multimesh.set_instance_color(index, Color(0.82, 0.94, 0.94, fade))
		any_droplet_visible = true
	_droplets.visible = any_droplet_visible


func _sync_aircraft_sink() -> void:
	if not _has_aircraft_base or not is_instance_valid(_aircraft_root):
		return
	var fraction := clampf(_elapsed_s / SINK_DURATION_S, 0.0, 1.0)
	var progress := smoothstep(0.0, 1.0, fraction)
	var tilt := deg_to_rad(5.0) * progress
	var sunk_basis := _aircraft_base_transform.basis * Basis(Vector3.RIGHT, tilt)
	var sunk_origin := _aircraft_base_transform.origin - Vector3.UP * (SINK_DEPTH_M * progress)
	_aircraft_root.global_transform = Transform3D(sunk_basis, sunk_origin)


func _set_effect_materials(clock_s: float) -> void:
	if _plume_material != null:
		_set_material_clock(_plume_material, clock_s)
	for material: ShaderMaterial in _ring_materials:
		_set_material_clock(material, clock_s)


func _set_material_clock(material: ShaderMaterial, clock_s: float) -> void:
	material.set_shader_parameter("effect_clock_s", clock_s)
	material.set_shader_parameter("wind_xz", _wind_xz)
	material.set_shader_parameter("wind_rate", _wind_rate)


func _hide_visuals() -> void:
	if _plume != null:
		_plume.visible = false
	if _rings.size() == RING_COUNT:
		for ring: MeshInstance3D in _rings:
			ring.visible = false
		for material: ShaderMaterial in _ring_materials:
			material.set_shader_parameter("effect_alpha", 0.0)
	if _plume_material != null:
		_plume_material.set_shader_parameter("effect_alpha", 0.0)
	if _droplet_multimesh != null:
		for index: int in MAX_DROPLETS:
			_hide_droplet(index)
	if _droplets != null:
		_droplets.visible = false


func _hide_droplet(index: int) -> void:
	if _droplet_multimesh == null or index < 0 or index >= MAX_DROPLETS:
		return
	_droplet_multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	_droplet_multimesh.set_instance_color(index, Color(1.0, 1.0, 1.0, 0.0))


func _play_impact_voice() -> void:
	_impact_audio_emitted = _audio_enabled
	_impact_audio_source_index = posmod(_event_seed, 2) if _audio_enabled else -1
	_impact_audio_requests_this_event = 1 if _audio_enabled else 0
	if not _audio_enabled or _impact_voice == null:
		return
	_impact_voice.stream = _splash_stream(_impact_audio_source_index)
	_impact_voice.global_position = _surface_world_position()
	_impact_voice.volume_db = -12.0
	_impact_voice.stream_paused = false
	# Dummy output is used for tests and has no mixer; preserve selection state without queuing a voice.
	if AudioServer.get_driver_name() != "Dummy":
		_impact_voice.play()


func _surface_world_position() -> Vector3:
	return Vector3(_impact_point_ned[1], -_water_level_down_m, -_impact_point_ned[0])


func _impact_point(impact: Variant) -> PackedFloat64Array:
	var raw_point: Variant
	if impact is ImpactSnapshot.Snapshot:
		var snapshot: ImpactSnapshot.Snapshot = impact
		if not snapshot.has_kinematics:
			return PackedFloat64Array()
		raw_point = snapshot.point_ned
	elif typeof(impact) == TYPE_DICTIONARY:
		raw_point = impact.get("point_ned")
	else:
		return PackedFloat64Array()
	return _read_point_ned(raw_point)


static func _read_point_ned(raw_point: Variant) -> PackedFloat64Array:
	var point := PackedFloat64Array()
	if raw_point is Vector3:
		point = PackedFloat64Array([raw_point.x, raw_point.y, raw_point.z])
	elif raw_point is Array or raw_point is PackedFloat64Array or raw_point is PackedFloat32Array:
		if raw_point.size() != 3:
			return PackedFloat64Array()
		for value: Variant in raw_point:
			if not _is_finite_number(value):
				return PackedFloat64Array()
			point.append(float(value))
	else:
		return PackedFloat64Array()
	return point


func _impact_tick(impact: Variant) -> int:
	if impact is ImpactSnapshot.Snapshot:
		return maxi(int(impact.tick), 0)
	if typeof(impact) == TYPE_DICTIONARY:
		var tick: Variant = impact.get("tick", 0)
		if typeof(tick) == TYPE_INT:
			return maxi(int(tick), 0)
	return 0


static func _seed_for_impact(point: PackedFloat64Array, tick: int) -> int:
	var north_mm := int(round(point[0] * 1000.0))
	var east_mm := int(round(point[1] * 1000.0))
	var down_mm := int(round(point[2] * 1000.0))
	var mixed := (north_mm * 73_856_093) ^ (east_mm * 19_349_663) ^ (down_mm * 83_492_791) ^ (tick % 2_147_483_647)
	var seed := absi(mixed) % 2_147_483_646 + 1
	return seed


static func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


static func _read_max_depth(lake: Dictionary) -> float:
	var profile: Variant = lake.get("bed_profile", [])
	if profile is Array and not profile.is_empty() and profile[-1] is Dictionary:
		var depth: Variant = profile[-1].get("depth_m")
		if _is_finite_number(depth):
			return clampf(float(depth), 0.0, MAX_LAKE_DEPTH_M)
	return 5.0


static func _read_wind_xz(raw_wind: Variant) -> Dictionary:
	var wind_ne := Vector2.ZERO
	if raw_wind is Array or raw_wind is PackedFloat64Array or raw_wind is PackedFloat32Array:
		if raw_wind.size() >= 2 and _is_finite_number(raw_wind[0]) and _is_finite_number(raw_wind[1]):
			wind_ne = Vector2(float(raw_wind[0]), float(raw_wind[1]))
	var speed := minf(wind_ne.length(), 10.0)
	if speed <= 1e-6:
		return {"direction": Vector2(0.8, 0.6), "rate": 1.0}
	# Render x is east and render z is negative north.
	var direction_xz := Vector2(wind_ne.y, -wind_ne.x).normalized()
	return {"direction": direction_xz, "rate": 0.65 + 0.22 * speed}


static func _lake_center_world(lake: Dictionary) -> Vector3:
	var raw_polygon: Variant = lake.get("shoreline_ne_m")
	var has_polygon: bool = (raw_polygon is PackedFloat64Array or raw_polygon is PackedFloat32Array or raw_polygon is Array) \
		and raw_polygon.size() >= 6 and raw_polygon.size() % 2 == 0
	var center_ne := _polygon_centroid(raw_polygon)
	if not has_polygon:
		center_ne = Vector2(
			float(lake.get("origin_north_m", 0.0)),
			float(lake.get("origin_east_m", 0.0))
		)
	var level: Variant = lake.get("water_level_down_m", 0.45)
	var water_down := float(level) if _is_finite_number(level) else 0.45
	return Vector3(center_ne.y, -water_down, -center_ne.x)


static func _polygon_centroid(raw_polygon: Variant) -> Vector2:
	if not (raw_polygon is PackedFloat64Array or raw_polygon is PackedFloat32Array or raw_polygon is Array):
		return Vector2.ZERO
	if raw_polygon.size() < 6 or raw_polygon.size() % 2 != 0:
		return Vector2.ZERO
	var twice_area := 0.0
	var centroid_north := 0.0
	var centroid_east := 0.0
	var point_count: int = raw_polygon.size() / 2
	for index: int in point_count:
		var next := (index + 1) % point_count
		var north: Variant = raw_polygon[index * 2]
		var east: Variant = raw_polygon[index * 2 + 1]
		var next_north: Variant = raw_polygon[next * 2]
		var next_east: Variant = raw_polygon[next * 2 + 1]
		if not _is_finite_number(north) or not _is_finite_number(east) \
			or not _is_finite_number(next_north) or not _is_finite_number(next_east):
			return Vector2.ZERO
		var cross := float(east) * float(next_north) - float(next_east) * float(north)
		twice_area += cross
		centroid_east += (float(east) + float(next_east)) * cross
		centroid_north += (float(north) + float(next_north)) * cross
	if absf(twice_area) < 1e-6:
		return Vector2.ZERO
	return Vector2(centroid_north / (3.0 * twice_area), centroid_east / (3.0 * twice_area))


func _splash_stream(index: int) -> AudioStreamWAV:
	return SPLASH_ONE if index == 0 else SPLASH_TWO
