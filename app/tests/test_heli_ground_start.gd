extends SceneTree

const FieldLoader := preload("res://data/field_loader.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const GroundStart := preload("res://physics/rotorcraft/ground_start.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")

var _failures: int = 0
var _checks: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	_check("default field loads", bool(loaded_field.get("ok", false)), str(loaded_field.get("errors", [])))
	var loaded_aircraft: Dictionary = RotorcraftData.load_file("res://data/aircraft/xcell_60_research.json")
	_check("research trainer loads", bool(loaded_aircraft.get("ok", false)), str(loaded_aircraft.get("errors", [])))
	if not bool(loaded_field.get("ok", false)) or not bool(loaded_aircraft.get("ok", false)):
		quit(1)
		return
	var field: Dictionary = loaded_field.field
	var result: Dictionary = GroundStart.resolve(field, loaded_aircraft)
	_check("default authored pad resolves to a static support state", bool(result.get("ok", false)), str(result.get("reason", "")))
	if bool(result.get("ok", false)):
		var state: PackedFloat64Array = result.state
		_check("resolver returns the 13-value NED rigid-body state", state.size() == 13 and result.pad.heading == PI / 2.0)
		_check("candidate pose is N6, E0 and zero-rate", state[0] == 6.0 and state[1] == 0.0
			and state[3] == 0.0 and state[4] == 0.0 and state[5] == 0.0
			and state[10] == 0.0 and state[11] == 0.0 and state[12] == 0.0, str(state))
		_check("all four skids are compressed with positive normal reactions", result.contact_count == 4
			and result.normal_forces_n.size() == 4 and result.compressions_m.size() == 4
			and _all_positive(result.normal_forces_n) and _all_positive(result.compressions_m),
			"forces=%s compressions=%s" % [str(result.normal_forces_n), str(result.compressions_m)])
		var force: PackedFloat64Array = result.force_residual_n
		var moment: PackedFloat64Array = result.moment_residual_nm
		_check("full 3D force residual meets the flat-pad 1e-4 weight limit", force.size() == 3
			and result.relative_force_residual < 1.0e-4 and _norm(force) < 1.0e-4 * 8.2 * 9.80665,
			"residual=%s relative=%s" % [str(force), str(result.relative_force_residual)])
		_check("full 3D moment residual meets the flat-pad 1e-4 weight-radius limit", moment.size() == 3
			and result.relative_moment_residual < 1.0e-4 and _norm(moment) < 1.0e-4 * 8.2 * 9.80665 * 1.25,
			"residual=%s relative=%s" % [str(moment), str(result.relative_moment_residual)])
		_check("four equal spring contacts recover mg/(4k) level sag",
			absf(_mean(result.compressions_m) - 8.2 * 9.80665 / (4.0 * 10000.0)) < 1.0e-9,
			str(result.compressions_m))
		_check("resolver reports static tangential support as omitted", result.tangential_support.contains("not modeled"))
	var missing_pad: Dictionary = field.duplicate(true)
	missing_pad.erase("rotorcraft_pad")
	_check("no authored pad fails closed without airborne fallback", not bool(GroundStart.resolve(missing_pad, loaded_aircraft).get("ok", false)))
	var unsupported_aircraft: Dictionary = loaded_aircraft.duplicate(true)
	unsupported_aircraft["id"] = "unsupported-research-aircraft"
	_check("pad refuses an aircraft without an authored envelope", not bool(GroundStart.resolve(field, unsupported_aircraft).get("ok", false)))
	var oversized: Dictionary = loaded_aircraft.duplicate(true)
	var context: Dictionary = loaded_aircraft.context.duplicate(true)
	var main: Dictionary = context.main_model.duplicate(true)
	main["rotor_radius_m"] = 4.0
	context["main_model"] = main
	oversized["context"] = context
	_check("loaded rotor geometry cannot exceed the pad's recorded envelope", not bool(GroundStart.resolve(field, oversized).get("ok", false)))
	var table: Dictionary = GroundSurfaces.load_table()
	var built: Dictionary = GroundSurfaces.build(table.table, field)
	var center: PackedFloat64Array = GroundTerrain.sample_validated(6.0, 0.0, built.rects)
	_check("flat physical pad samples zero height and slope from the shared field surface table",
		center == PackedFloat64Array([0.0, 0.0, 0.0]), str(center))
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _all_positive(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value) or value <= 0.0:
			return false
	return true


func _norm(values: PackedFloat64Array) -> float:
	var sum: float = 0.0
	for value: float in values:
		sum += value * value
	return sqrt(sum)


func _mean(values: PackedFloat64Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())
