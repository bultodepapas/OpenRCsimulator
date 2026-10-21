extends Node3D

## Profile-driven, presentation-only smoke. A single 768-slot budget is shared by
## every enabled named show or accepted source endpoint in this profile.

const Presentation := preload("res://workshop/presentation.gd")
const Schedule := preload("res://render/smoke/profile_smoke_schedule.gd")
const PROCESS_SHADER := preload("res://render/smoke/profile_process.gdshader")
const TICKS_PER_SECOND := 240
const MAX_INTERVAL_TICKS := 24
const TOTAL_PARTICLES := 768
const MAX_ENTRIES := 8
const MAX_ACTIVE_ENTRIES := 4
const MAX_BIRTH_EVENTS := 32
const MAX_HISTORY_SECONDS := 8.3
const HISTORY_SAMPLE_S := 0.2

static var _shared_mask: ImageTexture

var _event_buffers: Dictionary = {}
var _resolved: Dictionary = {}
var _last_birth_tick: Dictionary = {}
var _presentation_time_s := 0.0
var _maximum_wash := 0.0
var _maximum_bore_radius := 0.0
var _lod := 1.0
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
var _last_presented_s := -1.0
var _last_tick := -1
var _last_interval_s := 0.0
var _fault := ""


## Bind the validated v1/v2 profile to the full registered companion dictionary.
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
	_profile.smoke = validation.entries
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
	_last_presented_s = -1.0
	_last_interval_s = 0.0
	_lod = 1.0
	_last_birth_tick.clear()
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
	_schedule.cancel_bursts()


## Clear puffs and scheduler history. A reset also authorizes an explicit reconfigure.
func reset() -> void:
	_paused = false
	_playing = true
	_stopped = false
	_last_tick = -1
	_last_presented_s = -1.0
	_last_interval_s = 0.0
	_presentation_time_s = 0.0
	_fault = ""
	_history.clear()
	_last_birth_tick.clear()
	_maximum_wash = 0.0
	_maximum_bore_radius = 0.0
	_last_transforms.clear()
	_primed_slots.clear()
	_schedule.reset()
	# Recreate the bounded GPU pools. GPUParticles3D restart can retain an
	# already-rendered frame on the compatibility renderer; replacing each pool
	# guarantees that reset clears all pre-reset puff state.
	var counts: Dictionary = {}
	for slot: String in _emitters.keys():
		var emitter: GPUParticles3D = _emitters[slot]
		counts[slot] = emitter.amount if is_instance_valid(emitter) else 0
		if is_instance_valid(emitter):
			emitter.free()
	_emitters.clear()
	var mask := _mask_texture()
	for entry: Dictionary in _profile.get("smoke", []):
		if not bool(entry.get("enabled", false)):
			continue
		var slot := str(entry.get("slot", ""))
		var count := int(counts.get(slot, 0))
		if slot.is_empty() or count <= 0:
			continue
		var emitter := _make_emitter(slot, count, entry, mask, int(_profile.visual_seed))
		_emitters[slot] = emitter
		add_child(emitter)
		_primed_slots[slot] = false
	_configuration_reset = true


## `pose.tick` floors the accepted presentation timestamp at 240 Hz.
## Optional `pose.presentation_time_s` aligns fractional rendered poses and births.
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
	var presented_s := float(tick) / TICKS_PER_SECOND
	if pose.has("presentation_time_s"):
		var timestamp: Variant = pose.presentation_time_s
		if (typeof(timestamp) != TYPE_FLOAT and typeof(timestamp) != TYPE_INT) or not is_finite(float(timestamp)) or float(timestamp) < 0.0:
			return _fail_closed("presentation timestamp must be finite and nonnegative")
		presented_s = float(timestamp)
		if floori(presented_s * TICKS_PER_SECOND + 0.000001) != tick:
			return _fail_closed("pose tick must floor the matching presentation timestamp")
	if _paused or not _playing:
		_schedule.rebase(tick, true)
		if _last_tick >= 0:
			for slot: String in _last_birth_tick:
				_last_birth_tick[slot] = int(_last_birth_tick[slot]) + maxi(0, tick - _last_tick)
		_last_tick = tick
		_last_presented_s = presented_s
		_prime_transforms(pose)
		return {"ok": true, "paused": true, "interval_ticks": 0}
	if _last_tick < 0:
		_last_tick = tick
		_last_presented_s = presented_s
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "primed": true, "interval_ticks": 0}
	if tick < _last_tick or presented_s < _last_presented_s or tick - _last_tick > MAX_INTERVAL_TICKS or bool(pose.get("teleport", false)):
		reset()
		_last_tick = tick
		_last_presented_s = presented_s
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "discontinuity_reset": true, "interval_ticks": 0}
	var interval_ticks := tick - _last_tick
	var interval_s := presented_s - _last_presented_s
	if interval_s <= 0.000000001:
		return {"ok": true, "interval_ticks": 0}
	var time_tolerance := 0.000001 if pose.has("presentation_time_s") else 1.0 / TICKS_PER_SECOND + 0.000001
	if dt > 0.1 + 0.000001 or interval_s > 0.1 + 0.000001 or absf(dt - interval_s) > time_tolerance:
		reset()
		_last_tick = tick
		_last_presented_s = presented_s
		_schedule.rebase(tick)
		_prime_transforms(pose)
		return {"ok": true, "discontinuity_reset": true, "interval_ticks": 0}
	_presentation_time_s += interval_s
	var safety_stop := bool(pose.get("safety_stop", false))
	if safety_stop or _stopped:
		_schedule.cancel_bursts()
	var effective_request: Variant = 0.0 if _stopped or safety_stop else request
	var effective_source: Variant = _source_with_stop(source_sample) if _stopped or safety_stop else source_sample
	var schedule_result: Dictionary = _schedule.advance(_last_tick, tick, effective_request, effective_source)
	var transforms: Dictionary = pose.get("slot_transforms", {})
	var camera_distance := _finite_camera_distance(pose.get("camera_distance_m", 0.0))
	var lod := _distance_lod(camera_distance)
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
				wind, interval_s, lod, tick)
	else:
		_fault = str(schedule_result.get("error", "smoke event scheduler failed"))
		for slot: String in _emitters.keys():
			_update_emitter(slot, [], segment_data.get(slot, {"valid": false}), wind, interval_s, 0.0, tick)
	_last_tick = tick
	_last_presented_s = presented_s
	_last_interval_s = interval_s
	_update_bounds(tick, segment_data, wind.length())
	return {"ok": bool(schedule_result.get("ok", false)), "error": _fault,
		"interval_ticks": interval_ticks, "interval_s": interval_s, "event_log": schedule_result.get("event_log", [])}


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
		"slot_particles": per_slot, "resolved_rates_hz": _resolved.duplicate(true), "saturated": _is_saturated(), "fault": _fault}


func _validate_profile(profile: Dictionary, bindings: Dictionary) -> Dictionary:
	if str(profile.get("schedule_policy", "")) != "ticks-240-v1":
		return _invalid("unsupported smoke schedule policy")
	if typeof(profile.get("visual_seed")) != TYPE_INT or int(profile.visual_seed) < 0 or int(profile.visual_seed) > 2147483647:
		return _invalid("visual_seed must be a nonnegative 31-bit integer")
	if not profile.get("smoke") is Array or profile.smoke.size() > MAX_ENTRIES:
		return _invalid("profile smoke must contain at most eight registered entries")
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
		var stable := not str(endpoint.get("source_id", "")).is_empty() and not str(endpoint.get("anchor_id", "")).is_empty() and not str(endpoint.get("source_kind", "")).is_empty()
		if kind == "show" and not stable and (not endpoint.has("position_m") or not endpoint.has("direction")):
			return _invalid("show endpoint requires its authored local pose")
		if kind == "source":
			var legacy := str(endpoint.get("source_anchor_ref", "")) == "exhausts[0]" and str(endpoint.get("source_kind", "")) == "glow_prop"
			if not legacy and not stable:
				return _invalid("source endpoint requires stable source and anchor identities")
		endpoints[id] = endpoint
	var seen: Dictionary = {}
	var active_count := 0
	var normalized: Array[Dictionary] = []
	for value: Variant in profile.smoke:
		if not value is Dictionary:
			return _invalid("smoke profile entry must be an object")
		var entry: Dictionary = value
		var normalized_entry: Dictionary = Presentation.normalize_smoke_entry(entry, int(profile.get("version", 1)))
		if not bool(normalized_entry.ok):
			return _invalid(str(normalized_entry.errors))
		entry = normalized_entry.value
		normalized.append(entry)
		var slot := str(entry.slot)
		if slot.is_empty() or not endpoints.has(slot) or seen.has(slot):
			return _invalid("smoke profile must select unique registered slot IDs")
		seen[slot] = true
		if typeof(entry.enabled) != TYPE_BOOL:
			return _invalid("smoke enabled must be boolean")
		if bool(entry.enabled):
			active_count += 1
		if active_count > MAX_ACTIVE_ENTRIES:
			return _invalid("profile exceeds four active emitters")
	return {"ok": true, "endpoints": endpoints, "entries": normalized}


func _allocate_emitters(active_entries: Array[Dictionary]) -> void:
	_event_buffers.clear()
	_resolved.clear()
	if active_entries.is_empty():
		return
	var version := int(_profile.get("version", 1))
	var demands: Array[int] = []
	var total_demand := 0
	for entry: Dictionary in active_entries:
		var demand := maxi(1, ceili(float(entry.get("emission_rate_hz", 48.0)) * float(entry.lifetime_s)))
		demands.append(demand)
		total_demand += demand
	var counts: Array[int] = []
	var assigned := 0
	for index in active_entries.size():
		var count := TOTAL_PARTICLES / active_entries.size() if version == 1 else demands[index]
		if version >= 2 and total_demand > TOTAL_PARTICLES:
			# Every configured outlet retains a small floor; proportional demand uses
			# the remainder. No pool changes while live particles exist.
			count = 8 + floori(float(TOTAL_PARTICLES - 8 * active_entries.size()) * demands[index] / total_demand)
		counts.append(count)
		assigned += count
	var target := TOTAL_PARTICLES if version == 1 or total_demand > TOTAL_PARTICLES else total_demand
	var remainder := target - assigned
	for index in remainder:
		counts[index % counts.size()] += 1
	var mask := _mask_texture()
	for index in active_entries.size():
		var entry: Dictionary = active_entries[index]
		var slot := str(entry.slot)
		var count := counts[index]
		var requested := float(entry.get("emission_rate_hz", float(count) / float(entry.lifetime_s)))
		var resolved := minf(requested, float(count) / float(entry.lifetime_s))
		_resolved[slot] = {"requested_hz": requested, "resolved_hz": resolved, "capacity": count, "density": float(entry.get("density", 1.0)),
			"bore_radius_m": float(_endpoint_by_id.get(slot, {}).get("radius_m", float(entry.width_m) * 0.025))}
		var emitter := _make_emitter(slot, count, entry, mask, int(_profile.visual_seed))
		_emitters[slot] = emitter
		add_child(emitter)
		_primed_slots[slot] = false


func _is_saturated() -> bool:
	for rate: Dictionary in _resolved.values():
		if float(rate.resolved_hz) + 0.00001 < float(rate.requested_hz):
			return true
	return false


func get_plume_bounds() -> AABB:
	for emitter: GPUParticles3D in _emitters.values():
		return emitter.visibility_aabb
	return AABB(Vector3.ZERO, Vector3.ONE)


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
	# Compatibility view-depth sorting renders a two-frame-old history buffer.
	# Fresh lifetime ordering keeps v2 puffs attached to a moving outlet; it is
	# an age order, not global transparent depth sorting. V1 keeps its old policy.
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if int(_profile.get("version", 1)) == 1 else GPUParticles3D.DRAW_ORDER_LIFETIME
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ShaderMaterial.new()
	process.shader = PROCESS_SHADER
	process.set_shader_parameter("width_m", float(entry.width_m))
	process.set_shader_parameter("size_growth", 0.42 if str(entry.shape) == "ribbon" else 0.7)
	process.set_shader_parameter("buoyancy", 0.18 if str(entry.shape) == "ribbon" else 0.27)
	process.set_shader_parameter("shape_mode", ["ribbon", "cloud", "fan"].find(str(entry.shape)))
	process.set_shader_parameter("amount", float(entry.amount) if int(_profile.get("version", 1)) == 1 else 1.0)
	process.set_shader_parameter("density", float(entry.get("density", 1.0)))
	process.set_shader_parameter("legacy_motion", int(_profile.get("version", 1)) == 1)
	for parameter: String in ["density", "jet_speed_mps", "dispersion_m2_s", "buoyancy_mps", "turbulence_mps", "drag_s", "velocity_inheritance"]:
		if entry.has(parameter):
			process.set_shader_parameter(parameter, float(entry[parameter]))
	var capacity_rate := float(count) / float(entry.lifetime_s)
	process.set_shader_parameter("rate_fraction", minf(1.0, float(entry.get("emission_rate_hz", capacity_rate)) / capacity_rate))
	process.set_shader_parameter("field_seed", float(visual_seed % 4096) * 0.0137)
	process.set_shader_parameter("bore_radius_m", float(_resolved[slot].bore_radius_m))
	var times := PackedFloat32Array()
	var states := PackedVector4Array()
	times.resize(MAX_BIRTH_EVENTS)
	states.resize(MAX_BIRTH_EVENTS)
	_event_buffers[slot] = {"times": times, "states": states, "levels": times.duplicate(), "next_states": states.duplicate(), "transitions": times.duplicate(), "wash": PackedVector3Array()}
	_event_buffers[slot].wash.resize(MAX_BIRTH_EVENTS)
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
		wind: Vector3, interval_s: float, lod: float, tick: int) -> void:
	var emitter: GPUParticles3D = _emitters[slot]
	var material := emitter.process_material as ShaderMaterial
	var valid_pose := bool(segment.get("valid", false))
	var can_birth := valid_pose and bool(segment.get("primed", false)) and lod > 0.0 and _fault.is_empty() and float(_resolved[slot].density) > 0.0
	if valid_pose:
		var previous: Transform3D = segment.previous
		var current: Transform3D = segment.current
		var begin_position := previous.origin
		var end_position := current.origin
		var begin_direction := (-previous.basis.z).normalized()
		var end_direction := (-current.basis.z).normalized()
		var bore_radius := float(_resolved[slot].bore_radius_m) * current.basis.x.length()
		material.set_shader_parameter("bore_radius_m", bore_radius)
		_maximum_bore_radius = maxf(_maximum_bore_radius, bore_radius)
		material.set_shader_parameter("segment_begin", begin_position)
		material.set_shader_parameter("segment_end", end_position)
		material.set_shader_parameter("direction_begin", begin_direction)
		material.set_shader_parameter("direction_end", end_direction)
		material.set_shader_parameter("carrier_velocity", (end_position - begin_position) / maxf(interval_s, 0.000001))
	material.set_shader_parameter("wind_velocity", wind)
	material.set_shader_parameter("interval_s", interval_s)
	material.set_shader_parameter("lod", lod if can_birth else 0.0)
	var buffers: Dictionary = _event_buffers[slot]
	buffers.times.fill(0.0)
	buffers.states.fill(Vector4.ZERO)
	buffers.levels.fill(0.0)
	buffers.next_states.fill(Vector4.ZERO)
	buffers.transitions.fill(0.0)
	buffers.wash.fill(Vector3.ZERO)
	material.set_shader_parameter("presentation_time_s", _presentation_time_s)
	var event_count := 0
	var has_active_event := false
	if can_birth:
		for item: Dictionary in raw_events:
			if event_count >= MAX_BIRTH_EVENTS:
				_fault = "GPU birth-event buffer overflow"
				can_birth = false
				break
			var color: Color = item.color
			var level := clampf(float(item.level), 0.0, 1.0)
			buffers.times[event_count] = float(item.tick) / TICKS_PER_SECOND - _last_presented_s
			buffers.states[event_count] = Vector4(color.r, color.g, color.b, color.a)
			buffers.levels[event_count] = level
			var next_color: Color = item.get("next_color", color)
			buffers.next_states[event_count] = Vector4(next_color.r, next_color.g, next_color.b, next_color.a)
			buffers.transitions[event_count] = float(item.get("transition_s", 0.0))
			buffers.wash[event_count] = item.get("wash_mps", Vector3.ZERO)
			_maximum_wash = maxf(_maximum_wash, buffers.wash[event_count].length())
			event_count += 1
			has_active_event = has_active_event or (level > 0.0 and (color.a > 0.0 or next_color.a > 0.0))
	material.set_shader_parameter("birth_event_times", buffers.times)
	material.set_shader_parameter("birth_event_states", buffers.states)
	material.set_shader_parameter("birth_event_levels", buffers.levels)
	material.set_shader_parameter("birth_event_next_states", buffers.next_states)
	material.set_shader_parameter("birth_event_transitions", buffers.transitions)
	material.set_shader_parameter("birth_event_wash", buffers.wash)
	material.set_shader_parameter("birth_event_count", event_count)
	if not can_birth:
		material.set_shader_parameter("birth_event_count", 0)
		has_active_event = false
	emitter.emitting = has_active_event
	if has_active_event:
		_last_birth_tick[slot] = tick
		emitter.request_particles_process(interval_s, 0.0)
		RenderingServer.particles_request_process(emitter.get_base())
	elif interval_s > 0.0 and tick <= int(_last_birth_tick.get(slot, -1000000)) + ceili(emitter.lifetime * TICKS_PER_SECOND) + MAX_INTERVAL_TICKS:
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
	var maximum_particle_extent := 0.0
	var maximum_spawn_extent := _maximum_bore_radius
	var maximum_intrinsic_flow_speed := 0.0
	var maximum_jet := 0.65
	var maximum_drag := 0.65
	var v2 := int(_profile.get("version", 1)) >= 2
	for entry: Dictionary in _profile.smoke:
		if bool(entry.enabled):
			var lifetime := float(entry.lifetime_s)
			var width := float(entry.width_m)
			var shape := str(entry.shape)
			var growth := 0.42 if shape == "ribbon" else 0.7
			var buoyancy := 0.18 if shape == "ribbon" else 0.27
			if v2:
				buoyancy = absf(float(entry.buoyancy_mps))
				maximum_jet = maxf(maximum_jet, float(entry.jet_speed_mps))
				maximum_drag = maxf(maximum_drag, float(entry.drag_s))
			active_lifetime = maxf(active_lifetime, lifetime)
			maximum_particle_extent = maxf(maximum_particle_extent,
				(sqrt(width * width * 0.04 + 2.0 * float(entry.get("dispersion_m2_s", 0.1)) * lifetime) * 1.35) if v2 else width * (0.025 + growth * sqrt(lifetime)))
			if shape == "cloud":
				maximum_spawn_extent = maxf(maximum_spawn_extent, width * 0.71)
			maximum_intrinsic_flow_speed = maxf(maximum_intrinsic_flow_speed,
				buoyancy + (float(entry.get("turbulence_mps", 0.22)) if v2 else sqrt(3.0) * 0.22))
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
	var puff_extent := maximum_particle_extent + maximum_spawn_extent
	var drift_extent := maximum_wind * active_lifetime \
		+ maximum_intrinsic_flow_speed * active_lifetime + (maximum_jet + _maximum_wash) * minf(maximum_drag, active_lifetime) \
		+ maximum_carrier * minf(maximum_drag, active_lifetime)
	box = box.grow(1.0 + puff_extent + drift_extent)
	for emitter: GPUParticles3D in _emitters.values():
		emitter.visibility_aabb = box


func _slot_transform(transforms: Variant, slot: String) -> Variant:
	if not transforms is Dictionary or not transforms.has(slot):
		return null
	var value: Variant = transforms[slot]
	if value is Transform3D:
		var transform: Transform3D = value
		if transform.origin.is_finite() and transform.basis.x.is_finite() and transform.basis.y.is_finite() \
				and transform.basis.z.is_finite() and _rigid_basis(transform.basis):
			return transform
	return null


func _source_with_stop(sample: Variant) -> Variant:
	if sample is Dictionary:
		var stopped: Dictionary = sample.duplicate(true)
		stopped["level"] = 0.0
		stopped["running"] = false
		if stopped.get("sources") is Dictionary:
			for source_id: String in stopped.sources:
				stopped.sources[source_id] = _source_with_stop(stopped.sources[source_id])
		if stopped.get("changes") is Array:
			for index in stopped.changes.size():
				if stopped.changes[index] is Dictionary:
					stopped.changes[index]["level"] = 0.0
					stopped.changes[index]["running"] = false
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
	if is_instance_valid(_shared_mask):
		return _shared_mask
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var u := (x + 0.5) / 32.0 - 1.0
			var v := (y + 0.5) / 32.0 - 1.0
			var radius := sqrt(u * u + v * v)
			var lobes := 0.82 + 0.12 * sin(u * 11.0 + sin(v * 8.0)) * cos(v * 9.0)
			var alpha := pow(maxf(0.0, 1.0 - radius), 1.6) * lobes
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_shared_mask = ImageTexture.create_from_image(image)
	return _shared_mask


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message, "endpoints": {}}


func _fail_closed(message: String) -> Dictionary:
	_fault = message
	for emitter: GPUParticles3D in _emitters.values():
		emitter.emitting = false
	return {"ok": false, "error": _fault, "interval_ticks": 0}


func _distance_lod(distance: float) -> float:
	# Ten-percent hysteresis avoids birth-rate chatter at distance boundaries.
	if _lod == 1.0 and distance > 165.0:
		_lod = 0.5
	if _lod == 0.5:
		if distance < 135.0: _lod = 1.0
		elif distance > 330.0: _lod = 0.25
	if _lod == 0.25:
		if distance < 270.0: _lod = 0.5
		elif distance > 660.0: _lod = 0.0
	if _lod == 0.0 and distance < 540.0:
		_lod = 0.25
	if distance > 700.0:
		_lod = 0.0
	return _lod


func _rigid_basis(value: Basis) -> bool:
	var sx := value.x.length()
	var sy := value.y.length()
	var sz := value.z.length()
	if minf(sx, minf(sy, sz)) < 0.00001 or value.determinant() <= 0.0:
		return false
	return absf(sx - sy) <= sx * 0.0001 and absf(sx - sz) <= sx * 0.0001 \
		and absf(value.x.dot(value.y)) <= sx * sy * 0.0001 \
		and absf(value.x.dot(value.z)) <= sx * sz * 0.0001 \
		and absf(value.y.dot(value.z)) <= sy * sz * 0.0001
