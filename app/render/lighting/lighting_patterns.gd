extends RefCounted
## Pure render-side pattern math. Clocks are supplied from the displayed pose and never read from shader TIME.

const PATTERN_IDS := ["steady", "breath", "pulse", "chase", "wave", "rainbow", "segments", "sequence"]
const TICKS_PER_SECOND := 240.0
const MAX_CUES := 32
const MAX_PALETTE := 8


static func pattern_index(pattern_id: String) -> int:
	return PATTERN_IDS.find(pattern_id)


static func resolve(pattern: Dictionary, presentation_seconds: float, sequence: Array = [], zone_id := "") -> Dictionary:
	var seconds := presentation_seconds if is_finite(presentation_seconds) and presentation_seconds >= 0.0 else 0.0
	var active: Dictionary = pattern.duplicate(true)
	var phase := 0.0
	var cue_index := -1
	var cycle_index := 0
	var cue: Dictionary = {}
	if str(pattern.get("id", "steady")) != "sequence":
		var period_seconds := float(maxi(60, int(pattern.get("period_ticks", 960)))) / TICKS_PER_SECOND
		phase = fposmod(seconds, period_seconds) / period_seconds
		return {"pattern": active, "phase": phase, "cue_index": cue_index, "sequence_cycle": cycle_index, "cue_start_seconds": -1.0, "cue": cue}

	var cues: Array = sequence.slice(0, mini(sequence.size(), MAX_CUES))
	var total_ticks := 0
	for item: Variant in cues:
		if item is Dictionary:
			total_ticks += maxi(1, int(item.get("duration_ticks", 1)))
	if total_ticks <= 0:
		active["id"] = "steady"
		return {"pattern": active, "phase": 0.0, "cue_index": -1, "sequence_cycle": 0, "cue_start_seconds": -1.0, "cue": {}}

	var total_seconds := float(total_ticks) / TICKS_PER_SECOND
	cycle_index = int(floor(seconds / total_seconds))
	var tick_in_cycle := fposmod(seconds, total_seconds) * TICKS_PER_SECOND
	var start_tick := 0.0
	var cue_start_seconds := -1.0
	for index in cues.size():
		var item: Variant = cues[index]
		if not item is Dictionary:
			continue
		var duration := float(maxi(1, int(item.get("duration_ticks", 1))))
		if tick_in_cycle >= start_tick + duration and index < cues.size() - 1:
			start_tick += duration
			continue
		cue_index = index
		cue = item
		cue_start_seconds = float(cycle_index) * total_seconds + start_tick / TICKS_PER_SECOND
		var targets: Variant = item.get("zone_ids", [])
		var targets_zone: bool = targets is Array and (zone_id.is_empty() or zone_id in targets)
		var cue_pattern: Variant = item.get("pattern", {})
		if targets_zone and cue_pattern is Dictionary and str(cue_pattern.get("id", "")) != "sequence":
			active = cue_pattern.duplicate(true)
			var local_ticks := maxf(0.0, tick_in_cycle - start_tick)
			var period_ticks := float(maxi(60, int(active.get("period_ticks", 960))))
			phase = fposmod(local_ticks, period_ticks) / period_ticks
		else:
			# A cue that does not target this zone is a steady reference interval.
			active["id"] = "steady"
			phase = 0.0
		break
	return {"pattern": active, "phase": phase, "cue_index": cue_index, "sequence_cycle": cycle_index, "cue_start_seconds": cue_start_seconds, "cue": cue}


static func sample(pattern: Dictionary, presentation_seconds: float, arc_u: float, sequence: Array = [], zone_id := "") -> Color:
	var resolved := resolve(pattern, presentation_seconds, sequence, zone_id)
	var active: Dictionary = resolved.pattern
	var phase := float(resolved.phase)
	var u := fposmod(arc_u if is_finite(arc_u) else 0.0, 1.0)
	var palette_srgb := _palette(active)
	var palette: Array[Color] = []
	for color: Color in palette_srgb:
		palette.append(_to_linear_srgb(color))
	var base: Color = palette[0]
	var floor_level := clampf(float(active.get("floor", 0.2)), 0.0, 1.0)
	var duty := clampf(float(active.get("duty", 0.5)), 0.05, 0.95)
	var direction := -1.0 if bool(active.get("reverse", false)) else 1.0
	var pattern_id := str(active.get("id", "steady"))
	var phase_turns := float(active.get("phase_turns", 0.0))
	var spatial_offset := phase_turns if pattern_id == "segments" else 0.0
	var spatial := fposmod(u * direction + spatial_offset, 1.0)
	var temporal_phase := fposmod(phase + phase_turns, 1.0)
	match pattern_id:
		"steady", "sequence":
			return _to_srgb(base)
		"breath":
			var envelope := floor_level + (1.0 - floor_level) * (0.5 - 0.5 * cos(temporal_phase * TAU))
			return _to_srgb(_scale(base, envelope))
		"pulse":
			var on := _pulse_envelope(temporal_phase, duty)
			return _to_srgb(_scale(base, floor_level + (1.0 - floor_level) * on))
		"chase":
			var distance := absf(fposmod(spatial - temporal_phase + 0.5, 1.0) - 0.5)
			var half_width := maxf(0.04, duty * 0.5)
			var band := 1.0 - _smoothstep(half_width - 0.04, half_width + 0.04, distance)
			var hot: Color = palette[mini(1, palette.size() - 1)]
			return _to_srgb(_scale(base.lerp(hot, band), floor_level + (1.0 - floor_level) * band))
		"wave":
			return _to_srgb(_palette_at(palette, spatial - temporal_phase))
		"rainbow":
			return _to_srgb(_palette_at(palette, spatial + temporal_phase))
		"segments":
			var count := clampi(int(active.get("segments", 16)), 1, 256)
			var index := posmod(int(floor(spatial * count)), palette.size())
			return _to_srgb(_scale(palette[index], floor_level + (1.0 - floor_level) * duty))
		_:
			return _to_srgb(base)


static func uniforms(pattern: Dictionary) -> Dictionary:
	var pattern_id := str(pattern.get("id", "steady"))
	var index := pattern_index(pattern_id)
	if pattern_id == "sequence":
		index = pattern_index("steady")
	var colors := _palette(pattern)
	var packed := PackedColorArray()
	for i in MAX_PALETTE:
		packed.append(colors[mini(i, colors.size() - 1)] if i < colors.size() else colors[0])
	return {
		"pattern_settings": Vector4(float(maxi(index, 0)), float(colors.size()), clampf(float(pattern.get("floor", 0.2)), 0.0, 1.0), clampf(float(pattern.get("duty", 0.5)), 0.05, 0.95)),
		"pattern_extras": Vector4(float(clampi(int(pattern.get("segments", 16)), 1, 256)), 1.0 if bool(pattern.get("reverse", false)) else 0.0, float(pattern.get("phase_turns", 0.0)), 0.0),
		"palette": packed,
	}


static func sequence_state(sequence: Array, presentation_seconds: float) -> Dictionary:
	if not is_finite(presentation_seconds) or presentation_seconds < 0.0:
		return {"cue_index": -1, "sequence_cycle": 0, "cue_start_seconds": -1.0, "cue": {}}
	var state := resolve({"id": "sequence"}, presentation_seconds, sequence)
	return {"cue_index": state.cue_index, "sequence_cycle": state.sequence_cycle, "cue_start_seconds": state.cue_start_seconds, "cue": state.cue}


## Reactive data changes brightness only. Missing observations leave the authored pattern unchanged.
static func reactive_multiplier(reactive: Dictionary, telemetry: Dictionary) -> Dictionary:
	var source := str(reactive.get("source", "none"))
	var gain := clampf(_number_or(reactive.get("gain", 0.0), 0.0), 0.0, 1.0)
	if source == "none" or gain <= 0.0:
		return {"available": true, "multiplier": 1.0}
	if not telemetry.has(source):
		return {"available": false, "multiplier": 1.0}
	var raw: Variant = telemetry[source]
	if not (raw is int or raw is float) or not is_finite(float(raw)):
		return {"available": false, "multiplier": 1.0}
	# Rates arrive in rad/s and true airspeed in m/s; these are visual response scales,
	# not flight limits. Throttle is already normalized.
	var response := absf(float(raw)) / 4.0 if source in ["roll_rate", "pitch_rate"] else (
		maxf(float(raw), 0.0) / 40.0 if source == "airspeed" else clampf(float(raw), 0.0, 1.0))
	return {"available": true, "multiplier": 1.0 + gain * clampf(response, 0.0, 1.0)}


static func _palette(pattern: Dictionary) -> Array[Color]:
	var result: Array[Color] = []
	var raw: Variant = pattern.get("palette", [])
	if raw is Array:
		for value: Variant in raw:
			if result.size() >= MAX_PALETTE:
				break
			if value is Color:
				result.append(value)
			elif value is String:
				result.append(Color.from_string(value, Color.WHITE))
	if result.is_empty():
		result.append(Color.WHITE)
	return result


static func _palette_at(palette: Array[Color], t: float) -> Color:
	var position := fposmod(t, 1.0) * float(palette.size())
	var index := int(floor(position))
	var fraction := position - float(index)
	return palette[index % palette.size()].lerp(palette[(index + 1) % palette.size()], _smoothstep(0.0, 1.0, fraction))


static func _pulse_envelope(phase: float, duty: float) -> float:
	var edge := minf(0.08, duty * 0.25)
	return _smoothstep(0.0, edge, phase) * (1.0 - _smoothstep(maxf(0.0, duty - edge), duty, phase))


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge1 <= edge0:
		return 1.0 if value >= edge1 else 0.0
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _scale(color: Color, amount: float) -> Color:
	return Color(color.r * amount, color.g * amount, color.b * amount, color.a)


static func _to_linear_srgb(color: Color) -> Color:
	return Color(_channel_to_linear(color.r), _channel_to_linear(color.g), _channel_to_linear(color.b), color.a)


static func _to_srgb(color: Color) -> Color:
	return Color(_channel_to_srgb(color.r), _channel_to_srgb(color.g), _channel_to_srgb(color.b), color.a)


static func _channel_to_linear(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)


static func _channel_to_srgb(value: float) -> float:
	var linear := maxf(0.0, value)
	return 12.92 * linear if linear <= 0.0031308 else 1.055 * pow(linear, 1.0 / 2.4) - 0.055


static func _number_or(value: Variant, fallback: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return float(value)
