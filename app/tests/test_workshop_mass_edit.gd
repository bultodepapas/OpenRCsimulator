extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const STIK_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"

var _checks := 0
var _failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _read(path: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func _initialize() -> void:
	var stik := _read(STIK_PATH)
	var p51 := _read(P51_PATH)
	_check("Stik source loaded", not stik.is_empty())
	_check("P-51 source loaded", not p51.is_empty())
	if stik.is_empty() or p51.is_empty():
		quit(1)
		return
	_test_inspect_and_apply(stik)
	_test_id_resolution(stik)
	_test_rejections(stik, p51)
	_test_balance_solver(stik)
	_test_pinned_boundary(stik)
	_test_fixed_reference_rebase(stik, p51)
	print("Workshop mass edit: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_inspect_and_apply(base: Dictionary) -> void:
	var original: Dictionary = base.duplicate(true)
	var inspection: Dictionary = MassEdit.inspect(base)
	_check("inspect validates stable source and loader", inspection.ok, str(inspection.get("errors", [])))
	_check("finite-fuel inventory uses source empty-tanks state", inspection.ok and inspection.weighing_state == "empty_tanks")
	_check("mass edit reports only v2 mass schema bounds", inspection.ok and inspection.mass_bounds_kg == [0.001, 5.0])
	_check("inventory IDs are all explicit", inspection.ok and inspection.inventory.size() == base.inventory.size())
	_check("liquid fuel row is unavailable", not _row(inspection, "item_fuel_main").get("editable", true))
	_check("virtual reference mass is unavailable", not _row(inspection, "item_balance_mass_virtual").get("editable", true))
	var noop: Dictionary = MassEdit.apply_to_validated_base(base, [])
	_check("empty edit is an exact no-op", noop.ok and noop.raw == original)
	if noop.ok:
		noop.raw.inventory[0].name = "detached result mutation probe"
	_check("no-op result is detached from source input", base == original)
	_check("empty edit leaves source untouched", base == original)
	var engine_index: int = _index_for(base, "item_engine_main")
	var old_mass: float = float(base.inventory[engine_index].mass.value)
	var measured: Dictionary = MassEdit.apply_to_validated_base(base, [{
		"id": "item_engine_main",
		"mass_kg": old_mass + 0.00001,
		"source": "0.01 g digital scale, engine assembly isolated, 2026-10-19",
	}])
	_check("small direct measurement passes the complete aircraft loader", measured.ok, str(measured.get("errors", [])))
	if measured.ok:
		var edited_item: Dictionary = measured.raw.inventory[_index_for(measured.raw, "item_engine_main")]
		_check("mass quantity retains measured provenance", edited_item.mass.kind == "measured"
			and edited_item.mass.source == "0.01 g digital scale, engine assembly isolated, 2026-10-19")
		_check("component station, dimensions and authored balance remain fixed",
			edited_item.position == base.inventory[engine_index].position
			and edited_item.size == base.inventory[engine_index].size
			and measured.raw.balance == base.balance
			and measured.raw.reference == base.reference)
		_check("fixed propeller thrust point is re-referenced after nonzero CG shift",
			_datum_point_preserved(base, measured.raw, ["propulsion", "propeller", "thrust_line_offset"]))
		var oracle: PackedFloat64Array = _independent_box_tensor(measured.raw.inventory, measured.data.model.cg_le)
		_check("loader inertia matches independent full 3x3 box/parallel-axis oracle", _arrays_close(measured.data.model.inertia, oracle),
			"loader=%s oracle=%s" % [measured.data.model.inertia, oracle])
	_check("mass edit never mutates the base input", base == original)
	var too_large_cg: Dictionary = MassEdit.apply_to_validated_base(base, [{
		"id": "item_engine_main", "mass_kg": old_mass + 0.1, "source": "component weighed on scale",
	}])
	_check("loader rejects mass changes that break authored plan-CG tolerance", not too_large_cg.ok
		and str(too_large_cg.errors).contains("balance"), str(too_large_cg.get("errors", [])))


func _test_id_resolution(base: Dictionary) -> void:
	var reordered: Dictionary = base.duplicate(true)
	reordered.inventory.reverse()
	var index: int = _index_for(reordered, "item_engine_main")
	reordered.inventory[index].name = "test-only renamed display label"
	var result: Dictionary = MassEdit.apply_to_validated_base(reordered, [{
		"id": "item_engine_main",
		"mass_kg": float(reordered.inventory[index].mass.value),
		"source": "component weighed on scale; stable ID reorder probe",
	}])
	_check("reorder and display rename still resolve the same authored ID", result.ok, str(result.get("errors", [])))
	if result.ok:
		var actual: Dictionary = result.raw.inventory[_index_for(result.raw, "item_engine_main")]
		_check("resolved row retains stable ID and renamed display label", actual.id == "item_engine_main"
			and actual.name == "test-only renamed display label")
	var stale: Dictionary = base.duplicate(true)
	stale.inventory[0].erase("id")
	var stale_result: Dictionary = MassEdit.apply_to_validated_base(stale, [])
	_check("missing/stale stable identity refuses the complete operation", not stale_result.ok
		and str(stale_result.errors).contains("stable ID"), str(stale_result.get("errors", [])))
	var duplicate: Dictionary = base.duplicate(true)
	duplicate.inventory[1].id = duplicate.inventory[0].id
	var duplicate_result: Dictionary = MassEdit.apply_to_validated_base(duplicate, [])
	_check("duplicate stable IDs refuse the complete operation", not duplicate_result.ok
		and str(duplicate_result.errors).contains("duplicate"), str(duplicate_result.get("errors", [])))


func _test_rejections(stik: Dictionary, p51: Dictionary) -> void:
	var index: int = _index_for(stik, "item_engine_main")
	var old_mass: float = float(stik.inventory[index].mass.value)
	var valid_source := "digital scale, component isolated"
	var unknown: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_unknown", "mass_kg": old_mass, "source": valid_source}])
	_check("unknown stable ID is rejected", not unknown.ok and str(unknown.errors).contains("not present"))
	var liquid: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_fuel_main", "mass_kg": 0.2, "source": valid_source}])
	_check("finite fuel mass is controlled only by fuel-system state", not liquid.ok and str(liquid.errors).contains("finite liquid fuel"))
	var virtual_mass: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_balance_mass_virtual", "mass_kg": 0.2, "source": valid_source}])
	_check("virtual balance-reference mass cannot be claimed as measured hardware", not virtual_mass.ok and str(virtual_mass.errors).contains("virtual reference-build"))
	var nan_mass: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": NAN, "source": valid_source}])
	_check("nonfinite measured mass is rejected", not nan_mass.ok and str(nan_mass.errors).contains("finite"))
	var low_mass: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": 0.0009, "source": valid_source}])
	_check("mass below exact schema lower bound is rejected", not low_mass.ok and str(low_mass.errors).contains("[0.001, 5.0]"))
	var high_mass: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": 5.01, "source": valid_source}])
	_check("mass above exact schema upper bound is rejected", not high_mass.ok and str(high_mass.errors).contains("[0.001, 5.0]"))
	var blank_source: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": old_mass, "source": "  "}])
	_check("blank measurement provenance is rejected", not blank_source.ok and str(blank_source.errors).contains("measurement description"))
	var long_source: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": old_mass, "source": "x".repeat(257)}])
	_check("measurement provenance length is bounded", not long_source.ok and str(long_source.errors).contains("measurement description"))
	var control_source: Dictionary = MassEdit.apply_to_validated_base(stik, [{"id": "item_engine_main", "mass_kg": old_mass, "source": "scale\nreading"}])
	_check("control characters are rejected from measurement provenance", not control_source.ok and str(control_source.errors).contains("measurement description"))
	var position_edit: Dictionary = MassEdit.apply_to_validated_base(stik, [{
		"id": "item_engine_main", "mass_kg": old_mass, "source": valid_source, "position": [0.2, 0.0, 0.0],
	}])
	_check("position movement has no supported edit operation", not position_edit.ok and str(position_edit.errors).contains("exactly id, mass_kg and source"))
	var duplicate_edit: Dictionary = MassEdit.apply_to_validated_base(stik, [
		{"id": "item_engine_main", "mass_kg": old_mass, "source": valid_source},
		{"id": "item_engine_main", "mass_kg": old_mass, "source": valid_source},
	])
	_check("duplicate edited IDs are rejected", not duplicate_edit.ok and str(duplicate_edit.errors).contains("duplicated"))
	var too_many: Array[Dictionary] = []
	for edit_index: int in range(33):
		too_many.append({"id": "item_engine_main", "mass_kg": old_mass, "source": valid_source})
	var over_limit: Dictionary = MassEdit.apply_to_validated_base(stik, too_many)
	_check("edit count is bounded before per-entry processing", not over_limit.ok and str(over_limit.errors).contains("more than 32"))
	var p51_liquid: Dictionary = MassEdit.apply_to_validated_base(p51, [{"id": "fuel_flight", "mass_kg": 0.5, "source": valid_source}])
	_check("gasoline inventory is also protected from component-mass edits", not p51_liquid.ok and str(p51_liquid.errors).contains("finite liquid fuel"))


func _test_balance_solver(base: Dictionary) -> void:
	var inspection: Dictionary = MassEdit.inspect(base)
	if not inspection.ok:
		_check("solver source inspection passed", false, str(inspection.errors))
		return
	var mass: float = float(inspection.mass_kg)
	var cg: Array = inspection.cg_le_m
	var state: String = str(inspection.weighing_state)
	var proposal: Dictionary = MassEdit.solve_fixed_station(base, "item_engine_main", mass, cg, state)
	_check("measured total mass and CG produce a valid fixed-station proposal", proposal.ok, str(proposal.get("errors", [])))
	if proposal.ok:
		_check("solver reports exact target and fixed station inputs", proposal.input.observed_total_mass_kg == mass
			and proposal.input.observed_cg_le_m == cg and proposal.input.weighing_state == state
			and proposal.input.fixed_station_le_m == base.inventory[_index_for(base, "item_engine_main")].position.value)
		_check("solver proposal is derived, loader-checked and unapplied", proposal.proposal.mass.kind == "derived"
			and proposal.loader_compatible and not proposal.applied and base.inventory == _read(STIK_PATH).inventory)
		_check("solver reproduces measured state CG", _vectors_close(proposal.predicted_cg_le_m, cg)
			and _max_abs(proposal.cg_residual_m) <= 1.0e-12, str(proposal.cg_residual_m))
	var shifted_cg: Array = cg.duplicate(true)
	shifted_cg[1] = float(shifted_cg[1]) + 0.05
	var impossible_cg: Dictionary = MassEdit.solve_fixed_station(base, "item_engine_main", mass, shifted_cg, state)
	_check("CG that a fixed station cannot realize is rejected", not impossible_cg.ok
		and str(impossible_cg.errors).contains("misses observed CG"), str(impossible_cg.get("errors", [])))
	var wrong_state: String = "as_inventory" if state == "empty_tanks" else "empty_tanks"
	var wrong_fuel_state: Dictionary = MassEdit.target_consistency_report(base, mass, cg, wrong_state)
	_check("solver/report refuses mismatched or unsupported fuel weighing state", not wrong_fuel_state.ok
		and str(wrong_fuel_state.errors).contains("weighing state"), str(wrong_fuel_state.get("errors", [])))
	var consistency: Dictionary = MassEdit.target_consistency_report(base, mass, cg, state)
	_check("target report is read-only and uses source CG tolerance", consistency.ok
		and consistency.mass_residual_kg == 0.0 and consistency.cg_within_source_tolerance
		and consistency.cg_tolerance_m == float(base.balance.cg_tolerance.value))
	var out_of_range: Dictionary = MassEdit.solve_fixed_station(base, "item_engine_main",
		float(base.plausibility.mass_range.value[1]) + 1.0, cg, state)
	_check("target above source plausibility mass range is rejected", not out_of_range.ok
		and str(out_of_range.errors).contains("plausibility.mass_range"))


func _test_pinned_boundary(base: Dictionary) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(STIK_PATH)
	var descriptor_result: Dictionary = Descriptor.load_for(str(base.id), bytes)
	_check("generated source descriptor validates", descriptor_result.ok, str(descriptor_result.get("errors", [])))
	if not descriptor_result.ok:
		return
	var descriptor: Dictionary = descriptor_result.descriptor
	var pinned: Dictionary = MassEdit.inspect_pinned(base, descriptor, bytes)
	_check("pinned inspect verifies exact bytes and descriptor", pinned.ok, str(pinned.get("errors", [])))
	var mass: float = float(base.inventory[_index_for(base, "item_engine_main")].mass.value)
	var applied: Dictionary = MassEdit.apply_pinned(base, descriptor, bytes, [{
		"id": "item_engine_main", "mass_kg": mass, "source": "scale verification, engine assembly",
	}])
	_check("pinned apply delegates to validated core", applied.ok, str(applied.get("errors", [])))
	var changed: Dictionary = base.duplicate(true)
	changed.reference.wing_span.value += 0.001
	var wrong_source: Dictionary = MassEdit.apply_pinned(changed, descriptor, bytes, [])
	_check("pinned apply refuses in-memory source differing from exact pinned bytes", not wrong_source.ok
		and str(wrong_source.errors).contains("do not match"), str(wrong_source.get("errors", [])))
	var bad_descriptor: Dictionary = descriptor.duplicate(true)
	bad_descriptor.base_sha256 = "0".repeat(64)
	var stale_pin: Dictionary = MassEdit.inspect_pinned(base, bad_descriptor, bytes)
	_check("pinned inspect refuses a stale source manifest hash", not stale_pin.ok
		and str(stale_pin.errors).contains("SHA-256"), str(stale_pin.get("errors", [])))


func _test_fixed_reference_rebase(stik: Dictionary, p51: Dictionary) -> void:
	_check_rebased_point(stik, ["propulsion", "propeller", "thrust_line_offset"], "finite-fuel glow Stik")
	_check_rebased_point(p51, ["propulsion", "propeller", "thrust_line_offset"], "finite-fuel P-51")
	var p51_index: int = _first_editable_index(p51)
	if p51_index >= 0:
		var p51_edit: Dictionary = _small_measured_edit(p51, p51_index)
		var p51_result: Dictionary = MassEdit.apply_to_validated_base(p51, [p51_edit])
		_check("P-51 mass shift preserves LE-authored slipstream source points", p51_result.ok
			and p51_result.raw.propulsion.propeller.slipstream == p51.propulsion.propeller.slipstream,
			str(p51_result.get("errors", [])))
	var avanti := _read("res://data/aircraft/sebart_avanti_s_a200.json")
	_check("Vantage Jet turbine source loaded", not avanti.is_empty())
	if not avanti.is_empty():
		_check_rebased_point(avanti, ["propulsion", "thrust_line_offset"], "finite-fuel Vantage Jet turbine thrust point")
		_check_rebased_point(avanti, ["propulsion", "intake_offset"], "finite-fuel Vantage Jet turbine intake")
	var timber := _read("res://data/aircraft/turbo_lumber_evolution.json")
	_check("Lumber electric source loaded", not timber.is_empty())
	if not timber.is_empty():
		_check_rebased_point(timber, ["propulsion", "propeller", "thrust_line_offset"], "electric Lumber propeller")


func _check_rebased_point(base: Dictionary, path: Array, label: String) -> void:
	var edit_index: int = _first_editable_index(base)
	if edit_index < 0:
		_check(label + " has an editable fixed-station component", false)
		return
	var old_cg: Array[float] = _full_inventory_cg(base)
	var result: Dictionary = MassEdit.apply_to_validated_base(base, [_small_measured_edit(base, edit_index)])
	_check(label + " small measured edit passes loader", result.ok, str(result.get("errors", [])))
	if not result.ok:
		return
	var new_cg: Array[float] = _full_inventory_cg(result.raw)
	_check(label + " test exercises nonzero inventory CG shift", _distance3(old_cg, new_cg) > 1.0e-12,
		"old=%s new=%s" % [old_cg, new_cg])
	_check(label + " preserves its original structural LE location", _datum_point_preserved(base, result.raw, path))


func _small_measured_edit(base: Dictionary, index: int) -> Dictionary:
	var mass: float = float(base.inventory[index].mass.value)
	var delta: float = 0.00001
	var updated_mass: float = mass + delta if mass + delta <= 5.0 else mass - delta
	return {
		"id": str(base.inventory[index].id),
		"mass_kg": updated_mass,
		"source": "10 mg digital scale check; component isolated, 2026-10-19",
	}


func _first_editable_index(base: Dictionary) -> int:
	var inspection: Dictionary = MassEdit.inspect(base)
	if not inspection.ok:
		return -1
	for row: Dictionary in inspection.inventory:
		if bool(row.get("editable", false)):
			return _index_for(base, str(row.id))
	return -1


func _datum_point_preserved(original: Dictionary, candidate: Dictionary, path: Array) -> bool:
	var original_quantity: Variant = _at_path(original, path)
	var candidate_quantity: Variant = _at_path(candidate, path)
	if not original_quantity is Dictionary or not candidate_quantity is Dictionary:
		return false
	var old_cg: Array[float] = _full_inventory_cg(original)
	var new_cg: Array[float] = _full_inventory_cg(candidate)
	for axis: int in range(3):
		var old_point: float = old_cg[axis] + float(original_quantity.value[axis])
		var new_point: float = new_cg[axis] + float(candidate_quantity.value[axis])
		if absf(old_point - new_point) > 1.0e-12:
			return false
	return candidate_quantity.kind == "derived" \
		and str(candidate_quantity.source).contains("fixed structural location re-referenced")


func _at_path(value: Dictionary, path: Array) -> Variant:
	var cursor: Variant = value
	for key: Variant in path:
		if not cursor is Dictionary or not cursor.has(str(key)):
			return null
		cursor = cursor[str(key)]
	return cursor


func _full_inventory_cg(base: Dictionary) -> Array[float]:
	var mass := 0.0
	var moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for item: Dictionary in base.inventory:
		var item_mass: float = float(item.mass.value)
		mass += item_mass
		for axis: int in range(3):
			moment[axis] += item_mass * float(item.position.value[axis])
	return [moment[0] / mass, moment[1] / mass, moment[2] / mass]


func _distance3(left: Array, right: Array) -> float:
	var square := 0.0
	for axis: int in range(3):
		square += pow(float(left[axis]) - float(right[axis]), 2.0)
	return sqrt(square)


func _row(inspection: Dictionary, item_id: String) -> Dictionary:
	for row: Dictionary in inspection.get("inventory", []):
		if row.get("id", "") == item_id:
			return row
	return {}


func _index_for(base: Dictionary, item_id: String) -> int:
	for index: int in range(base.inventory.size()):
		if str(base.inventory[index].get("id", "")) == item_id:
			return index
	return -1


## Independent full-tensor oracle: construct all nine matrix cells from intrinsic box inertia
## plus m((r·r)I - rrᵀ). This intentionally does not call AircraftData.inertia_about().
func _independent_box_tensor(inventory: Array, cg_le: PackedFloat64Array) -> PackedFloat64Array:
	var tensor: Array = [
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
	]
	for item: Dictionary in inventory:
		var mass: float = float(item.mass.value)
		var position: Array = item.position.value
		var size: Array = item.size.value
		var arm := [
			-(float(position[0]) - cg_le[0]),
			float(position[1]) - cg_le[1],
			-(float(position[2]) - cg_le[2]),
		]
		var intrinsic := [
			mass * (float(size[1]) * float(size[1]) + float(size[2]) * float(size[2])) / 12.0,
			mass * (float(size[0]) * float(size[0]) + float(size[2]) * float(size[2])) / 12.0,
			mass * (float(size[0]) * float(size[0]) + float(size[1]) * float(size[1])) / 12.0,
		]
		var radius_squared: float = float(arm[0]) * arm[0] + float(arm[1]) * arm[1] + float(arm[2]) * arm[2]
		for row: int in range(3):
			for column: int in range(3):
				var shift: float = mass * ((radius_squared if row == column else 0.0) - float(arm[row]) * float(arm[column]))
				tensor[row][column] += shift
				if row == column:
					tensor[row][column] += intrinsic[row]
	return PackedFloat64Array([
		tensor[0][0], tensor[1][1], tensor[2][2],
		tensor[0][1], tensor[0][2], tensor[1][2],
	])


func _arrays_close(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if absf(left[index] - right[index]) > 1.0e-11 * maxf(1.0, absf(right[index])):
			return false
	return true


func _vectors_close(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if absf(float(left[index]) - float(right[index])) > 1.0e-12:
			return false
	return true


func _max_abs(values: Array) -> float:
	var maximum := 0.0
	for value: Variant in values:
		maximum = maxf(maximum, absf(float(value)))
	return maximum
