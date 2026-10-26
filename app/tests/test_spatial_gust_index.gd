## Exact gust-law preservation across ordered-agenda pruning.
extends SceneTree

const Field := preload("res://physics/wind_spatial_field.gd")
const Config := preload("res://physics/wind_spatial_config.gd")
const Presets := preload("res://physics/wind_spatial_presets.gd")
var checks := 0
var failed := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var cases: Array[Dictionary] = [Config.defaults()]
	var sparse := Config.defaults()
	for i in 32:
		sparse.gusts.events.append(_event("sparse_%d" % i, 4.0 + 11.0 * i, 0.1 + 1.7 * (i % 6), 0.2, -0.15))
	cases.append(sparse)
	var mixed := Config.defaults()
	mixed.gusts.events = [
		_event("tie_a", 5.0, 0.1, 0.1, -0.2), _event("tie_b", 5.0, 1.0, -0.1, 0.2),
		_event("tie_c", 5.0, 10.0, 0.1, -0.2), _event("tie_d", 5.0, 120.0, -0.1, 0.2),
		_event("later", 126.0, 0.1, 0.1, 0.2),
	]
	cases.append(mixed)
	var rounding := Config.defaults()
	rounding.gusts.events = [_event("subtraction_endpoint", 63869.150306074676, 32.88826421165945, 0.5, -0.25)]
	cases.append(rounding)
	cases.append(Presets.get_preset("spatial-realistic-v1").spatial_wind)
	var fields: Array = []
	var canonical: Array[Dictionary] = []
	var times: Array[float] = [0.0, 1.0, 4.0, 5.0, 5.1, 6.0, 15.0, 125.0, 126.0, 126.1,
		63902.03857028633, 63902.038570286335, 63902.03857028634, 86400.0]
	for raw: Dictionary in cases:
		var built := Field.build(raw)
		check("agenda validates", built.ok)
		if not built.ok:
			printerr(built.errors)
			quit(1)
			return
		fields.append(built.field)
		canonical.append(built.field.configuration())
		for event: Dictionary in raw.gusts.events:
			var start := float(event.start_s)
			var duration := float(event.duration_s)
			for t: float in [start - 1e-9, start, start + 1e-9, start + duration * 0.5,
				start + duration - 1e-9, start + duration, start + duration + 1e-9]:
				times.append(maxf(0.0, t))
		# Caller and public-return mutation must not alter prepared bounds.
		raw.gusts.events.clear()
		var exposed: Dictionary = built.field.configuration()
		exposed.gusts.events.clear()
	times.sort()
	for reverse_order: bool in [false, true]:
		for n in times.size():
			var t: float = times[times.size() - n - 1 if reverse_order else n]
			for i in fields.size():
				var expected_first := 0
				var events: Array = canonical[i].gusts.events
				var max_duration := 0.0
				for event: Dictionary in events:
					max_duration = maxf(max_duration, float(event.duration_s))
				while expected_first < events.size() and t - float(events[expected_first].start_s) >= max_duration:
					expected_first += 1
				check("safe lower bound", fields[i]._first_possible_gust(t) == expected_first)
				for height: float in [0.0, 1e-12, 0.3, 1.5, 3.0, 20.0]:
					var actual: PackedFloat64Array = fields[i]._gust_wind(height, t)
					var expected := _serial(canonical[i], height, t)
					check("serial bytes at %s / %s" % [t, height], actual.to_byte_array() == expected.to_byte_array())
					actual[0] = NAN
	var corner: Dictionary = canonical[3].gusts.events[0]
	var corner_time := float(corner.start_s) + float(corner.duration_s)
	check("rounded sum differs from subtraction endpoint", corner_time - float(corner.start_s) < float(corner.duration_s))
	check("rounded sum does not expire subtraction-active event", fields[3]._gust_wind(20.0, corner_time)[0] > 0.0)
	# Rebuilding the same internal provider must replace, not retain, the duration bound.
	var rebuilt: Variant = fields[2]
	var checked := Config.resolve(canonical[1])
	rebuilt._apply_config(checked.config, checked.content_hash, null, "", "")
	check("rebuild replaces longer bound", rebuilt._first_possible_gust(20.0) == 1)
	checked = Config.resolve(Config.defaults())
	rebuilt._apply_config(checked.config, checked.content_hash, null, "", "")
	check("empty rebuild clears bound", rebuilt._first_possible_gust(20.0) == 0 and rebuilt._gust_max_duration == 0.0)
	print("gust index: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _event(id: String, start: float, duration: float, north: float, east: float) -> Dictionary:
	return {"id": id, "start_s": start, "duration_s": duration, "amplitude_ned_mps": [north, east, 0.0]}

## Pre-optimization serial loop; identical arithmetic/grouping and authored order.
func _serial(config: Dictionary, height: float, time: float) -> PackedFloat64Array:
	var result := PackedFloat64Array([0.0, 0.0, 0.0])
	var x := clampf(clampf(height / float(config.domain.ground_transition_height_m), 0.0, 1.0), 0.0, 1.0)
	var wall_weight := x * x * x * (10.0 + x * (-15.0 + 6.0 * x))
	for event: Dictionary in config.gusts.events:
		var elapsed := time - float(event.start_s)
		var duration := float(event.duration_s)
		if elapsed < 0.0 or elapsed >= duration:
			continue
		var s := elapsed / duration
		var one_minus_s := 1.0 - s
		var pulse := 64.0 * s * s * s * one_minus_s * one_minus_s * one_minus_s
		result[0] += float(event.amplitude_ned_mps[0]) * pulse * wall_weight
		result[1] += float(event.amplitude_ned_mps[1]) * pulse * wall_weight
	return result
