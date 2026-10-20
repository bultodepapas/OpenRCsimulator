## FUEL-06-R1: ordinary CSV mass/CG channels carry the accepted endpoint sample under a versioned suffix.
extends SceneTree

const Trace := preload("res://sim/trace.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_valid_sample()
	_refusals()
	print("mass trace: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL " + label)


func _record(trace: Trace, tick: int, t: float, sample: Dictionary) -> void:
	var state := PackedFloat64Array([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	trace.record(tick, t, state, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0]), PackedFloat64Array(), sample)


func _sample(tick: int, time_s: float) -> Dictionary:
	return {
		"ok": true,
		"tick": tick,
		"time_s": time_s,
		"mass_kg": 1.23456789,
		"cg_body_m": PackedFloat64Array([0.0125, -0.003, 0.001]),
	}


func _valid_sample() -> void:
	var trace := Trace.new()
	trace.meta = {"mass_trace_schema": Trace.MASS_TRACE_SCHEMA, "dt_s": 1.0 / 240.0}
	_record(trace, 0, 0.0, _sample(0, 0.0))
	_record(trace, 1, 1.0 / 240.0, _sample(1, 1.0 / 240.0))
	var csv: String = trace.to_csv()
	_check("mass rows select trace v14 and name the v3 base", csv.begins_with("# format: openrc-trace v14\n")
		and csv.contains("# mass_base_trace_format: openrc-trace v3\n")
		and csv.contains("# mass_trace_schema: openrc-mass-sample v1\n"))
	_check("mass and all body-CG components append in order",
		trace.columns().slice(-4) == Trace.MASS_COLUMNS)
	_check("each row uses the explicitly supplied accepted sample",
		trace.value(0, "mass_kg") == 1.23456789 and trace.value(1, "cg_body_x_m") == 0.0125
		and trace.value(1, "cg_body_y_m") == -0.003 and trace.value(1, "cg_body_z_m") == 0.001)

	var legacy := Trace.new()
	legacy.meta = {"dt_s": 1.0 / 240.0}
	_record(legacy, 0, 0.0, {})
	_check("legacy traces retain their existing format and columns",
		legacy.to_csv().begins_with("# format: openrc-trace v3\n") and not legacy.columns().has("mass_kg"))


func _refusals() -> void:
	var wrong_tick := Trace.new()
	wrong_tick.meta = {"mass_trace_schema": Trace.MASS_TRACE_SCHEMA}
	_record(wrong_tick, 1, 1.0 / 240.0, _sample(0, 1.0 / 240.0))
	_check("a stale accepted sample tick refuses the trace", wrong_tick.to_csv().is_empty())

	var missing := Trace.new()
	missing.meta = {"mass_trace_schema": Trace.MASS_TRACE_SCHEMA}
	_record(missing, 0, 0.0, {})
	_check("a versioned mass trace refuses a missing sample", missing.to_csv().is_empty())

	var unversioned := Trace.new()
	unversioned.meta = {}
	_record(unversioned, 0, 0.0, _sample(0, 0.0))
	_check("an unversioned trace refuses an unadvertised sample", unversioned.to_csv().is_empty())

	var bad_schema := Trace.new()
	bad_schema.meta = {"mass_trace_schema": "openrc-mass-sample v999"}
	_record(bad_schema, 0, 0.0, _sample(0, 0.0))
	_check("an unknown mass schema is refused", bad_schema.to_csv().is_empty())
