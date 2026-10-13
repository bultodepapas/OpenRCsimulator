## SM-01…09. Bounded native GPU puffs, driven once per presented simulation interval.
## Reads aircraft/propulsion/weather; never writes physics, controls or checkpoints.
extends Node3D

const PROCESS_SHADER := preload("res://render/smoke/process.gdshader")
const EXHAUST_LIFE := 1.25
const PUMP_LIFE := 6.0
const EXHAUST_COUNT := 96
const PUMP_COUNT := 768
const MAX_INTERVAL := 0.1

var exhaust: GPUParticles3D
var pump: GPUParticles3D
var levels: Dictionary = {exhaust = 0.0, pump = 0.0}
var presented_s := 0.0
var last_interval_s := 0.0
var _anchor: Dictionary
var _primed := false
var _last_position := Vector3.ZERO
var _last_direction := Vector3.BACK
var _max_wind := 0.0
var _bounds: Array[Dictionary] = []


## The optional model contract: finite model-local mouth/direction, positive bore radius,
## explicit propulsion kind and explicit pump capability. Unsupported aircraft return [].
static func valid_anchor(raw: Variant) -> bool:
	if not raw is Dictionary or not raw.get("position") is Vector3 or not raw.get("direction") is Vector3:
		return false
	var p: Vector3 = raw.position
	var d: Vector3 = raw.direction
	return p.is_finite() and d.is_finite() and d.length_squared() > 0.99 and d.length_squared() < 1.01 \
		and typeof(raw.get("radius_m")) == TYPE_FLOAT and is_finite(raw.radius_m) and raw.radius_m > 0.0 \
		and raw.get("kind", "") == "glow_prop" and typeof(raw.get("pump")) == TYPE_BOOL


static func operating_levels(kind: String, rpm: float, idle_rpm: float, max_rpm: float, throttle: float,
		pump_request: float, running := true) -> Dictionary:
	if not running or kind != "glow_prop" or not is_finite(rpm) or not is_finite(idle_rpm) \
		or not is_finite(max_rpm) or not is_finite(throttle) or not is_finite(pump_request) \
		or idle_rpm <= 0.0 or max_rpm <= idle_rpm:
		return {exhaust = 0.0, pump = 0.0}
	var firing := smoothstep(idle_rpm * 0.25, idle_rpm * 0.85, rpm)
	var load := clampf(rpm / max_rpm, 0.0, 1.0)
	# Oil-bearing glow exhaust is faint at normal running; no black soot or failure inferred.
	return {exhaust = firing * lerpf(0.35, 1.0, load),
		pump = clampf(pump_request, 0.0, 1.0) * firing * smoothstep(0.08, 0.28, throttle)}


func configure(anchor: Dictionary) -> bool:
	if not valid_anchor(anchor) or exhaust != null:
		return false
	_anchor = anchor.duplicate()
	name = "EngineSmoke"
	var mask := _mask()
	exhaust = _emitter("GlowExhaust", EXHAUST_COUNT, EXHAUST_LIFE, 6101, mask, false)
	pump = _emitter("AuxPump", PUMP_COUNT, PUMP_LIFE, 6102, mask, true)
	return true


## Original deterministic 64² mask: soft lobes with no square edge, async noise or external asset.
static func _mask() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 32.0 - 1.0
			var v := (y + 0.5) / 32.0 - 1.0
			var radius := sqrt(u * u + v * v)
			var lobes := 0.82 + 0.12 * sin(u * 11.0 + sin(v * 8.0)) * cos(v * 9.0)
			var alpha := pow(maxf(0.0, 1.0 - radius), 1.6) * lobes
			img.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(img)


func _emitter(label: String, count: int, life: float, fixed_seed: int, mask: ImageTexture, dense: bool) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.name = label
	node.emitting = false
	node.amount = count
	node.lifetime = life
	node.local_coords = false
	node.speed_scale = 0.0
	# Manual requests are <= 0.1 s: one GPU update per request, with fractional birth DELTA.
	# Native fixed_fps=30 would subdivide the request using one final emitter pose for every substep.
	node.fixed_fps = 1
	node.interpolate = false
	node.fract_delta = true
	node.use_fixed_seed = true
	node.seed = fixed_seed
	node.set_meta("last_birth_s", -INF)
	node.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ShaderMaterial.new()
	process.shader = PROCESS_SHADER
	process.set_shader_parameter("size_start", 0.065 if dense else 0.018)
	process.set_shader_parameter("size_growth", 1.2 if dense else 0.38)
	process.set_shader_parameter("buoyancy", 0.32 if dense else 0.18)
	process.set_shader_parameter("tint", Vector3(0.94, 0.95, 0.96) if dense else Vector3(0.86, 0.9, 0.96))
	node.process_material = process
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = mask
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	# SM-06: native depth fade softens billboards meeting the airframe/runway (Compatibility A/B).
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	node.draw_pass_1 = quad
	add_child(node)
	return node


func reset() -> void:
	_primed = false
	presented_s = 0.0
	last_interval_s = 0.0
	_max_wind = 0.0
	_bounds.clear()
	levels = {exhaust = 0.0, pump = 0.0}
	for emitter: GPUParticles3D in [exhaust, pump]:
		if emitter != null:
			emitter.set_meta("last_birth_s", -INF)
			emitter.restart(true)
			emitter.emitting = false # restart() enables births; reset must leave both systems OFF
			RenderingServer.particles_request_process(emitter.get_base())


## transform is the rendered model root, including the authoritative CG/datum conversion.
## Wind is from the same session.wind_at(clock_s) used by the airplane, detached at the render boundary.
func advance(clock_s: float, model_transform: Transform3D, kind: String, rpm: float, idle_rpm: float,
		max_rpm: float, throttle: float, wind: Vector3, pump_request: float, running := true,
		camera_distance_m := 0.0, wash_velocity := Vector3.ZERO) -> void:
	if exhaust == null or not is_finite(clock_s) or not wind.is_finite():
		return
	var position: Vector3 = model_transform * _anchor.position
	var direction: Vector3 = (model_transform.basis * _anchor.direction).normalized()
	var dt := clock_s - presented_s
	if not _primed or dt < -0.000001 or dt > MAX_INTERVAL:
		reset()
		_primed = true
		presented_s = clock_s
		_last_position = position
		_last_direction = direction
		return
	if dt <= 0.000001:
		return # pause: no wall-time aging and no queued delta
	levels = operating_levels(kind, rpm, idle_rpm, max_rpm, throttle, pump_request if _anchor.pump else 0.0, running)
	var lod := 1.0 if camera_distance_m < 150.0 else (0.5 if camera_distance_m < 300.0 else 0.25)
	if camera_distance_m > 600.0:
		lod = 0.0
	var carrier := (position - _last_position) / dt
	var speed_ratio := clampf(rpm / maxf(max_rpm, 1.0), 0.0, 1.0)
	for emitter: GPUParticles3D in [exhaust, pump]:
		var dense := emitter == pump
		var level: float = levels.pump if dense else levels.exhaust
		var mat := emitter.process_material as ShaderMaterial
		mat.set_shader_parameter("segment_begin", _last_position)
		mat.set_shader_parameter("segment_end", position)
		mat.set_shader_parameter("direction_begin", _last_direction)
		mat.set_shader_parameter("direction_end", direction)
		mat.set_shader_parameter("carrier_velocity", carrier)
		mat.set_shader_parameter("wind_velocity", wind)
		mat.set_shader_parameter("interval_s", dt)
		mat.set_shader_parameter("jet_speed", lerpf(0.5, 4.0, speed_ratio))
		mat.set_shader_parameter("wash_velocity", wash_velocity)
		mat.set_shader_parameter("density", level * lod)
		mat.set_shader_parameter("opacity", 0.62 * level if dense else 0.16 * level)
		emitter.emitting = level * lod > 0.001
		if emitter.emitting:
			emitter.set_meta("last_birth_s", clock_s)
		# Even when culled, residual puffs must age and react to the shared changing wind.
		if emitter.emitting or clock_s - float(emitter.get_meta("last_birth_s")) <= emitter.lifetime + MAX_INTERVAL:
			emitter.request_particles_process(dt if emitter.emitting else 0.0, 0.0 if emitter.emitting else dt)
			RenderingServer.particles_request_process(emitter.get_base())
	_update_bounds(clock_s, position, wind.length(), carrier.length() + wash_velocity.length() + 4.0)
	_last_position = position
	_last_direction = direction
	presented_s = clock_s
	last_interval_s = dt


func _update_bounds(clock_s: float, position: Vector3, wind_speed: float, carrier_speed: float) -> void:
	_max_wind = maxf(_max_wind, wind_speed)
	if _bounds.is_empty() or clock_s - float(_bounds.back().time) > 0.2:
		_bounds.append({time = clock_s, box = AABB(position, Vector3.ZERO), speed = carrier_speed})
	else:
		_bounds.back().box = (_bounds.back().box as AABB).expand(position)
		_bounds.back().speed = maxf(_bounds.back().speed, carrier_speed)
	while not _bounds.is_empty() and clock_s - float(_bounds.front().time) > PUMP_LIFE + 0.3:
		_bounds.pop_front()
	var box := AABB(position, Vector3.ZERO)
	var maximum_speed := 0.0
	for sample: Dictionary in _bounds:
		box = box.merge(sample.box)
		maximum_speed = maxf(maximum_speed, sample.speed)
	box = box.grow(5.0 + _max_wind * PUMP_LIFE + maximum_speed * 0.65)
	exhaust.visibility_aabb = box
	pump.visibility_aabb = box
