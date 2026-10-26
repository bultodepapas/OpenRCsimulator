extends RefCounted
## Bounded per-presented-frame workload evidence. Enable only in separate audit runs.

const METRICS := {
	"sparks_cpu_live": ["vfx", "sparks_cpu_live"],
	"trails_cpu_live": ["vfx", "trails_cpu_live"],
	"sparks_gpu_capacity": ["vfx", "sparks_gpu_instance_capacity"],
	"trails_gpu_capacity": ["vfx", "trails_gpu_instance_capacity"],
	"gpu_anchors_allocated": ["vfx", "gpu_anchors_allocated"],
	"spill_lights_allocated": ["vfx", "spill_lights_allocated"],
	"skin_emission_passes": ["skins", "active_emission_passes"],
	"skin_texture_bytes": ["skins", "composed_texture_mipped_bytes"],
	"frame_parameter_writes": ["frame_parameter_writes"],
}

var _frames := 0
var _first_tick := -1
var _last_tick := -1
var _last_frame := -1
var _last_wall_s := -1.0
var _metrics: Dictionary = {}
var _failure := ""


func record(budget: Dictionary, tick: int, frame: int, wall_s: float) -> bool:
	if not _failure.is_empty():
		return false
	if typeof(budget.get("active")) != TYPE_BOOL or str(budget.get("selection", "")) not in ["inherit", "disabled", "preset", "custom"] \
			or not (budget.get("vfx") is Dictionary) or not (budget.get("skins") is Dictionary) \
			or not budget.has("frame_parameter_writes"):
		_failure = "Workload audit requires a complete rig budget source."
		return false
	for helper: String in ["vfx", "skins"]:
		var count_key := "effects_allocated" if helper == "vfx" else "targets"
		var count_value: Variant = budget[helper].get(count_key)
		if typeof(count_value) != TYPE_INT or int(count_value) < 0:
			_failure = "Workload audit requires an explicit '%s' helper count." % helper
			return false
		if int(count_value) > 0:
			for key: String in METRICS:
				var path: Array = METRICS[key]
				if path.size() == 2 and path[0] == helper and not budget[helper].has(path[1]):
					_failure = "Workload audit active helper omits '%s'." % key
					return false
	if tick < 0 or tick < _last_tick or frame != _last_frame + 1 or not is_finite(wall_s) or wall_s < 0.0 or wall_s < _last_wall_s:
		_failure = "Workload audit requires contiguous presented frames, nondecreasing ticks and finite monotonic wall time."
		return false
	# Validate the whole sample before committing any counters. Missing metrics
	# represent absent/disabled helpers, whose production budget dictionaries omit them.
	var values: Dictionary = {}
	for key: String in METRICS:
		var value: Variant = budget
		for part: String in METRICS[key]:
			if not (value is Dictionary):
				_failure = "Workload audit metric '%s' has a malformed parent." % key
				return false
			if not value.has(part):
				value = 0
				break
			value = value[part]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 1e12 or float(value) != floor(float(value)):
			_failure = "Workload audit metric '%s' is not a bounded nonnegative count." % key
			return false
		values[key] = int(value)
	for key: String in METRICS:
		var value: int = values[key]
		var entry: Dictionary = _metrics.get(key, {"max": 0, "first_peak_frame": -1,
			"first_peak_tick": -1, "first_peak_wall_s": -1.0, "positive_frames": 0, "rising_edges": 0, "previous_positive": false})
		if value > int(entry.max) or _frames == 0:
			entry.max = value
			entry.first_peak_frame = frame
			entry.first_peak_tick = tick
			entry.first_peak_wall_s = wall_s
		if value > 0:
			entry.positive_frames += 1
			if not entry.previous_positive:
				entry.rising_edges += 1
		entry.previous_positive = value > 0
		_metrics[key] = entry
	if _frames == 0:
		_first_tick = tick
	_frames += 1
	_last_tick = tick
	_last_frame = frame
	_last_wall_s = wall_s
	return true


func report() -> Dictionary:
	var metrics := _metrics.duplicate(true)
	for key: String in metrics:
		metrics[key].erase("previous_positive")
	return {"format": "openrc-lighting-workload-audit v1", "enabled": true, "ok": _failure.is_empty() and _frames > 0,
		"failure": _failure, "observed_frames": _frames, "first_tick": _first_tick, "last_tick": _last_tick,
		"last_wall_s": _last_wall_s, "metrics": metrics,
		"scope": "Every presented frame observed by the capture loop, including warmup; CPU live states and allocated GPU capacities, not pixel visibility or field-light overlap.",
		"timing_qualification_eligible": false}
