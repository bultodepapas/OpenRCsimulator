extends Node3D

## Profile-driven, presentation-only smoke. A single 768-slot budget is shared by
## every enabled named show or accepted source endpoint in this profile.

const Schedule := preload("res://render/smoke/profile_smoke_schedule.gd")
const PROCESS_SHADER := preload("res://render/smoke/profile_process.gdshader")
const TICKS_PER_SECOND := 240
const MAX_INTERVAL_TICKS := 24
const TOTAL_PARTICLES := 768
const MAX_ENTRIES := 4
const MAX_SHOW_ENTRIES := 3
const MAX_SOURCE_ENTRIES := 1
const MAX_BIRTH_EVENTS := 32
const MAX_HISTORY_SECONDS := 8.3
const HISTORY_SAMPLE_S := 0.2
const SMOKE_ENTRY_KEYS: PackedStringArray = [
	"slot", "enabled", "color", "amount", "width_m", "lifetime_s", "shape", "mode",
	"burst_s", "pulse_period_s", "pulse_duty", "palette", "step_s",
]

var _schedule = Schedule.new()
var _profile: Dictionary = {}
var _bindings: Dictionary = {}
var _endpoint_by_id: Dictionary = {}
var _emitters: Dictionary = {}
var _last_transforms: Dictionary = {}
var _primed_slots: Dictionary = {}
var _history: Array[Dictionary] = []
var _configured := false
var _configuration_reset := false
var _playing := true
var _paused := false
var _stopped := false
var _last_tick := -1
var _last_interval_s := 0.0
var _fault := ""


## Bind the validated v1 profile to the full registered companion dictionary.
## A second configuration requires reset() so amount/lifetime edits cannot erase
## residual puffs without an explicit lifecycle action.
func configure(profile: Dictionary, bindings: Dictionary) -> bool:
	if _configured and not _configuration_reset:
		_fault = "reset required before profile reconfiguration"
		return false
	var validation := _validate_profile(profile, bindings)
	if not bool(validation.ok):
		_fault = str(validation.error)
		return false
	if _configured:
		for emitter: GPUParticles3D in _emitters.values():
			if is_instance_valid(emitter):
				emitter.free()
		_emitters.clear()
		_endpoint_by_id.clear()
		_last_transforms.clear()
		_primed_slots.clear()
	_profile = profile.duplicate(true)
	_bindings = bindings.duplicate(true)
	_endpoint_by_id = validation.endpoints
	var active_entries: Array[Dictionary] = []
	for entry: Dictionary in _profile.smoke:
		if bool(entry.enabled):
			active_entries.append(entry)
	_schedule = Schedule.new()
	var registered: Dictionary = {}
	for slot: String in validation.endpoints.keys():
		registered[slot] = validation.endpoints[slot]
	if not _schedule.configure(active_entries, registered):
		_fault = _schedule.fault_reason()
		return false
	_allocate_emitters(active_entries)
	_configured = true
	_configuration_reset = false
	_playing = true
	_paused = false
	_stopped = false
	_last_tick = -1
	_last_interval_s = 0.0
	_fault = ""
	return true


func play() -> void:
	_playing = true
	_paused = false
	_stopped = false


func pause() -> void:
	_paused = true


## Stop new births while existing particles continue to age and drift on advance().
func stop() -> void:
	_stopped = true


## Clear puffs and scheduler history. A reset also authorizes an explicit reconfigure.
func reset() -> void:
	_paused = false
	_playing = true
	_stopped = false
	_last_tick = -1
	_last_interval_s = 0.0
	_fault = ""
	_history.clear()
	_last_transforms.clear()
	_primed_slots.clear()
	_schedule.reset()
	for emitter: GPUParticles3D in _emitters.values():
		if not is_instance_valid(emitter):
			continue
		emitter.emitting = false
		emitter.restart(true)
		emitter.emitting = false
		RenderingServer.particles_request_process(emitter.get_base())
	_configuration_reset = true


## `pose.tick` is the authoritative integer simulation/preview clock at 240 Hz.
## `pose.slot_transforms` is supplied only by the registered model resolver.
func advance(dt: float, pose: Dictionary, wind: Vector3, request: Variant,
		source_sample: Variant) -> Dictionary:
	if not _configured:
		return {"ok": false, "error": "profile smoke is not configured"}
	if not is_finite(dt) or dt < 0.0 or not wind.is_finite():
		return _fail_closed("non-finite advance input")
	if typeof(pose.get("tick")) != TYPE_INT or int(pose.tick) < 0:
		return _fail_closed("pose requires a nonnegative integer 240 Hz tick")
	var tick := int(pose.tick)
	if _paused or not _playing:
		_schedule.rebase(tick)
		_last_tick = tick
		_prime_transforms(pose)
		return {"ok": true, "paused": true, "interval_ticks": 0}
	if _last_tick < 0:
		_last_tick = tick
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "primed": true, "interval_ticks": 0}
	if tick < _last_tick or tick - _last_tick > MAX_INTERVAL_TICKS:
		reset()
		_last_tick = tick
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "discontinuity_reset": true, "interval_ticks": 0}
	var interval_ticks := tick - _last_tick
	if interval_ticks == 0:
		return {"ok": true, "interval_ticks": 0}
	var interval_s := float(interval_ticks) / TICKS_PER_SECOND
	if dt > 0.1 + 0.000001 or absf(dt - interval_s) > 1.0 / TICKS_PER_SECOND + 0.000001:
		reset()
		_last_tick = tick
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "discontinuity_reset": true, "interval_ticks": 0}
	var effective_request: Variant = 0.0 if _stopped else request
	var effective_source: Variant = _source_with_stop(source_sample) if _stopped else source_sample
	var schedule_result: Dictionary = _schedule.advance(_last_tick, tick, effective_request, effective_source)
	var transforms: Dictionary = pose.get("slot_transforms", {})
	var camera_distance := _finite_camera_distance(pose.get("camera_distance_m", 0.0))
	var lod := 1.0 if camera_distance < 150.0 else (0.5 if camera_distance < 300.0 else (0.25 if camera_distance <= 600.0 else 0.0))
	var segment_data: Dictionary = {}
	for slot: String in _emitters.keys():
		var current_transform: Variant = _slot_transform(transforms, slot)
		if current_transform == null:
			_primed_slots[slot] = false
			segment_data[slot] = {"valid": false}
			continue
		var current: Transform3D = current_transform
		var was_primed := bool(_primed_slots.get(slot, false)) and _last_transforms.has(slot)
		var previous: Transform3D = _last_transforms.get(slot, current)
		segment_data[slot] = {"valid": true, "primed": was_primed, "previous": previous, "current": current}
		_last_transforms[slot] = current
		_primed_slots[slot] = true
	_record_history(tick, segment_data, wind, interval_s)
	if bool(schedule_result.get("ok", false)):
		for slot: String in _emitters.keys():
			_update_emitter(slot, schedule_result.events.get(slot, []), segment_data.get(slot, {"valid": false}),
				wind, interval_s, lod)
	else:
		_fault = str(schedule_result.get("error", "smoke event scheduler failed"))
		for slot: String in _emitters.keys():
			_update_emitter(slot, [], segment_data.get(slot, {"valid": false}), wind, interval_s, 0.0)
	_last_tick = tick
	_last_interval_s = interval_s
	_update_bounds(tick, segment_data, wind.length())
	return {"ok": bool(schedule_result.get("ok", false)), "error": _fault,
		"interval_ticks": interval_ticks, "event_log": schedule_result.get("event_log", [])}


func budget_info() -> Dictionary:
	var per_slot: Dictionary = {}
	var total := 0
	var show_count := 0
	var source_count := 0
	for slot: String in _emitters.keys():
		var emitter: GPUParticles3D = _emitters[slot]
		per_slot[slot] = emitter.amount
		total += emitter.amount
		if str(_endpoint_by_id[slot].kind) == "show":
			show_count += 1
		else:
			source_count += 1
	return {"configured": _configured, "capacity": total, "budget_limit": TOTAL_PARTICLES,
		"show_emitters": show_count, "source_emitters": source_count,
		"slot_particles": per_slot, "fault": _fault}


func _validate_profile(profile: Dictionary, bindings: Dictionary) -> Dictionary:
	if str(profile.get("schedule_policy", "")) != "ticks-240-v1":
		return _invalid("unsupported smoke schedule policy")
	if typeof(profile.get("visual_seed")) != TYPE_INT or int(profile.visual_seed) < 0 or int(profile.visual_seed) > 2147483647:
		return _invalid("visual_seed must be a nonnegative 31-bit integer")
	if not profile.get("smoke") is Array or profile.smoke.size() > MAX_ENTRIES:
		return _invalid("profile smoke must contain at most four registered entries")
	if not bindings.get("smoke_slots") is Array:
		return _invalid("bindings require registered smoke_slots")
	var endpoints: Dictionary = {}
	for value: Variant in bindings.smoke_slots:
		if not value is Dictionary:
			return _invalid("smoke slot registration must be an object")
		var endpoint: Dictionary = value
		var id := str(endpoint.get("id", ""))
		var kind := str(endpoint.get("kind", ""))
		if id.is_empty() or (kind != "show" and kind != "source") or endpoints.has(id):
			return _invalid("smoke slot IDs and kinds must be unique and registered")
		if not endpoint.has("position_m") or not endpoint.has("direction"):
			return _invalid("smoke slot requires its authored local pose")
		if kind == "source" and str(endpoint.get("source_kind", "")).is_empty():
			return _invalid("source endpoint requires a registered physical source kind")
		endpoints[id] = endpoint
	var seen: Dictionary = {}
	var show_count := 0
	var source_count := 0
	for value: Variant in profile.smoke:
		if not value is Dictionary:
			return _invalid("smoke profile entry must be an object")
		var entry: Dictionary = value
		if not _has_exact_keys(entry, SMOKE_ENTRY_KEYS):
			return _invalid("smoke profile entry has missing or unsupported keys")
		var slot := str(entry.slot)
		if slot.is_empty() or not endpoints.has(slot) or seen.has(slot):
			return _invalid("smoke profile must select unique registered slot IDs")
		seen[slot] = true
		if typeof(entry.enabled) != TYPE_BOOL:
			return _invalid("smoke enabled must be boolean")
		var endpoint: Dictionary = endpoints[slot]
		if str(endpoint.kind) == "show":
			show_count += 1
		else:
			source_count += 1
		if show_count > MAX_SHOW_ENTRIES or source_count > MAX_SOURCE_ENTRIES:
			return _invalid("profile exceeds three show endpoints or one source endpoint")
		var amount := _bounded(entry.amount, 0.0, 1.0)
		var width := _bounded(entry.width_m, 0.01, 2.0)
		var lifetime := _bounded(entry.lifetime_s, 0.1, 8.0)
		var burst := _bounded(entry.burst_s, 0.0, 8.0)
		var period := _bounded(entry.pulse_period_s, 0.0, 8.0)
		var duty := _bounded(entry.pulse_duty, 0.0, 1.0)
		var step := _bounded(entry.step_s, 0.0, 8.0)
		if amount < 0.0 or width < 0.0 or lifetime < 0.0 or burst < 0.0 or period < 0.0 or duty < 0.0 or step < 0.0:
			return _invalid("smoke profile number is nonfinite or outside its range")
		if str(entry.color).length() != 9 or not str(entry.color).begins_with("#"):
			return _invalid("smoke color must be canonical #RRGGBBAA")
		if str(entry.shape) not in ["ribbon", "cloud", "fan"] or str(entry.mode) not in ["hold", "burst", "pulse"]:
			return _invalid("smoke shape or mode is unsupported")
		if not entry.palette is Array or entry.palette.size() > 8:
			return _invalid("palette must contain at most eight swatches")
		for swatch: Variant in entry.palette:
			if typeof(swatch) != TYPE_STRING or str(swatch).length() != 9 or not str(swatch).begins_with("#"):
				return _invalid("palette swatches must be canonical #RRGGBBAA")
		if str(entry.mode) == "hold" and (burst != 0.0 or period != 0.0 or duty != 0.0):
			return _invalid("hold mode requires canonical zero timing fields")
		if str(entry.mode) == "burst" and (burst < 0.05 or period != 0.0 or duty != 0.0):
			return _invalid("burst mode requires burst_s 0.05..8 and canonical zero pulse fields")
		if str(entry.mode) == "pulse" and (burst != 0.0 or period < 0.05 or duty < 0.01):
			return _invalid("pulse mode requires pulse_period_s 0.05..8 and duty 0.01..1")
		if entry.palette.size() < 2 and step != 0.0:
			return _invalid("zero/one-color palettes require step_s zero")
		if entry.palette.size() >= 2 and step < 0.05:
			return _invalid("multiple palette colors require step_s 0.05..8")
	return {"ok": true, "endpoints": endpoints}


func _allocate_emitters(active_entries: Array[Dictionary]) -> void:
	if active_entries.is_empty():
		return
	var base_count := TOTAL_PARTICLES / active_entries.size()
	var extra := TOTAL_PARTICLES % active_entries.size()
	var mask := _mask_texture()
	for index in active_entries.size():
		var entry: Dictionary = active_entries[index]
		var slot := str(entry.slot)
		var count := base_count + (1 if index < extra else 0)
		var emitter := _make_emitter(slot, count, entry, mask, int(_profile.visual_seed))
		_emitters[slot] = emitter
		add_child(emitter)
		_primed_slots[slot] = false


func _make_emitter(slot: String, count: int, entry: Dictionary, mask: ImageTexture,
		visual_seed: int) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = "ProfileSmoke_" + slot
	emitter.emitting = false
	emitter.amount = count
	emitter.lifetime = float(entry.lifetime_s)
	emitter.local_coords = false
	emitter.speed_scale = 0.0
	emitter.fixed_fps = 1
	emitter.interpolate = false
	emitter.fract_delta = true
	emitter.use_fixed_seed = true
	emitter.seed = _slot_seed(visual_seed, slot)
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ShaderMaterial.new()
	process.shader = PROCESS_SHADER
	process.set_shader_parameter("width_m", float(entry.width_m))
	process.set_shader_parameter("size_growth", 0.42 if str(entry.shape) == "ribbon" else 0.7)
	process.set_shader_parameter("buoyancy", 0.18 if str(entry.shape) == "ribbon" else 0.27)
	process.set_shader_parameter("shape_mode", ["ribbon", "cloud", "fan"].find(str(entry.shape)))
	process.set_shader_parameter("amount", float(entry.amount))
	emitter.process_material = process
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = mask
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.12
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	emitter.draw_pass_1 = quad
	return emitter


func _update_emitter(slot: String, raw_events: Array, segment: Dictionary,
		wind: Vector3, interval_s: float, lod: float) -> void:
	var emitter: GPUParticles3D = _emitters[slot]
	var material := emitter.process_material as ShaderMaterial
	var valid_pose := bool(segment.get("valid", false))
	var can_birth := valid_pose and bool(segment.get("primed", false)) and lod > 0.0 and _fault.is_empty()
	if valid_pose:
		var previous: Transform3D = segment.previous
		var current: Transform3D = segment.current
		var begin_position := previous.origin
		var end_position := current.origin
		var begin_direction := (-previous.basis.z).normalized()
		var end_direction := (-current.basis.z).normalized()
		material.set_shader_parameter("segment_begin", begin_position)
		material.set_shader_parameter("segment_end", end_position)
		material.set_shader_parameter("direction_begin", begin_direction)
		material.set_shader_parameter("direction_end", end_direction)
		material.set_shader_parameter("carrier_velocity", (end_position - begin_position) / maxf(interval_s, 0.000001))
	material.set_shader_parameter("wind_velocity", wind)
	material.set_shader_parameter("interval_s", interval_s)
	material.set_shader_parameter("lod", lod if can_birth else 0.0)
	var time_values := PackedFloat32Array()
	var state_values := PackedVector4Array()
	var level_values := PackedFloat32Array()
	var has_active_event := false
	if can_birth:
		for item: Dictionary in raw_events:
			if time_values.size() >= MAX_BIRTH_EVENTS:
				_fault = "GPU birth-event buffer overflow"
				can_birth = false
				break
			var color: Color = item.color
			var level := clampf(float(item.level), 0.0, 1.0)
			time_values.append(float(item.offset_s))
			state_values.append(Vector4(color.r, color.g, color.b, color.a))
			level_values.append(level)
			has_active_event = has_active_event or level > 0.0
	material.set_shader_parameter("birth_event_times", time_values)
	material.set_shader_parameter("birth_event_states", state_values)
	material.set_shader_parameter("birth_event_levels", level_values)
	material.set_shader_parameter("birth_event_count", time_values.size())
	if not can_birth:
		material.set_shader_parameter("birth_event_count", 0)
		has_active_event = false
	emitter.emitting = has_active_event
	if has_active_event:
		emitter.request_particles_process(interval_s, 0.0)
		RenderingServer.particles_request_process(emitter.get_base())
	elif interval_s > 0.0:
		emitter.request_particles_process(0.0, interval_s)
		RenderingServer.particles_request_process(emitter.get_base())


func _prime_transforms(pose: Dictionary) -> void:
	var transforms: Variant = pose.get("slot_transforms", {})
	if not transforms is Dictionary:
		return
	for slot: String in _emitters.keys():
		var transform: Variant = _slot_transform(transforms, slot)
		if transform != null:
			_last_transforms[slot] = transform
			_primed_slots[slot] = true
		else:
			_last_transforms.erase(slot)
			_primed_slots[slot] = false


func _record_history(tick: int, segments: Dictionary, wind: Vector3, interval_s: float) -> void:
	var last_history_tick := int(_history.back().tick) if not _history.is_empty() else -TICKS_PER_SECOND
	if float(tick - last_history_tick) / TICKS_PER_SECOND < HISTORY_SAMPLE_S:
		return
	var box := AABB()
	var first := true
	var carrier_speed := 0.0
	for slot: String in segments.keys():
		var segment: Dictionary = segments[slot]
		if not bool(segment.get("valid", false)):
			continue
		var position: Vector3 = segment.current.origin
		if first:
			box = AABB(position, Vector3.ZERO)
			first = false
		else:
			box = box.expand(position)
		if interval_s > 0.0 and bool(segment.get("primed", false)):
			carrier_speed = maxf(carrier_speed,
				(segment.current.origin - segment.previous.origin).length() / interval_s)
	_history.append({"tick": tick, "box": box, "wind": wind.length(), "carrier": carrier_speed})
	while _history.size() > int(ceil(MAX_HISTORY_SECONDS / HISTORY_SAMPLE_S)) + 2:
		_history.pop_front()


func _update_bounds(tick: int, segments: Dictionary, wind_speed: float) -> void:
	var active_lifetime := 0.0
	for entry: Dictionary in _profile.smoke:
		if bool(entry.enabled):
			active_lifetime = maxf(active_lifetime, float(entry.lifetime_s))
	while not _history.is_empty() and float(tick - int(_history.front().tick)) / TICKS_PER_SECOND > active_lifetime + 0.3:
		_history.pop_front()
	var box := AABB()
	var first := true
	var maximum_wind := wind_speed
	var maximum_carrier := 0.0
	for sample: Dictionary in _history:
		if first:
			box = sample.box
			first = false
		else:
			box = box.merge(sample.box)
		maximum_wind = maxf(maximum_wind, float(sample.wind))
		maximum_carrier = maxf(maximum_carrier, float(sample.carrier))
	for slot: String in segments.keys():
		var segment: Dictionary = segments[slot]
		if bool(segment.get("valid", false)):
			if first:
				box = AABB(segment.current.origin, Vector3.ZERO)
				first = false
			else:
				box = box.expand(segment.current.origin)
	if first:
		box = AABB(Vector3.ZERO, Vector3.ONE)
	box = box.grow(3.0 + maximum_wind * active_lifetime + maximum_carrier * 0.65)
	for emitter: GPUParticles3D in _emitters.values():
		emitter.visibility_aabb = box


func _slot_transform(transforms: Variant, slot: String) -> Variant:
	if not transforms is Dictionary or not transforms.has(slot):
		return null
	var value: Variant = transforms[slot]
	if value is Transform3D:
		var transform: Transform3D = value
		if transform.origin.is_finite() and transform.basis.x.is_finite() and transform.basis.y.is_finite() \
				and transform.basis.z.is_finite() and (-transform.basis.z).length_squared() > 0.99:
			return transform
	return null


func _source_with_stop(sample: Variant) -> Variant:
	if sample is Dictionary:
		var stopped: Dictionary = sample.duplicate(true)
		stopped["level"] = 0.0
		if stopped.get("changes") is Array:
			for index in stopped.changes.size():
				if stopped.changes[index] is Dictionary:
					stopped.changes[index]["level"] = 0.0
		return stopped
	return {"kind": "", "running": false, "level": 0.0}


func _finite_camera_distance(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0.0
	var distance := float(value)
	return distance if is_finite(distance) and distance >= 0.0 else 0.0


func _slot_seed(visual_seed: int, slot: String) -> int:
	var hash := 2166136261
	for index in slot.length():
		hash = int((hash ^ slot.unicode_at(index)) * 16777619) & 0x7fffffff
	return int((visual_seed ^ hash) & 0x7fffffff)


func _mask_texture() -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 32.0 - 1.0
			var v := (y + 0.5) / 32.0 - 1.0
			var radius := sqrt(u * u + v * v)
			var lobes := 0.82 + 0.12 * sin(u * 11.0 + sin(v * 8.0)) * cos(v * 9.0)
			var alpha := pow(maxf(0.0, 1.0 - radius), 1.6) * lobes
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _bounded(value: Variant, minimum: float, maximum: float) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -1.0
	var number := float(value)
	if not is_finite(number) or number < minimum or number > maximum:
		return -1.0
	return number


func _has_exact_keys(value: Dictionary, keys: PackedStringArray) -> bool:
	if value.size() != keys.size() or not value.has_all(keys):
		return false
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not keys.has(str(key)):
			return false
	return true


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message, "endpoints": {}}


func _fail_closed(message: String) -> Dictionary:
	_fault = message
	for emitter: GPUParticles3D in _emitters.values():
		emitter.emitting = false
	return {"ok": false, "error": _fault, "interval_ticks": 0}
