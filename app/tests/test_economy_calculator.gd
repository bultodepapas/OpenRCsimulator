extends SceneTree

const Calculator = preload("res://economy/calculator.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_total_loss_and_salvage()
	_test_no_duplicate_charge()
	_test_prop_only_with_engine_inspection()
	_test_unknown_price_and_known_zero()
	_test_repair_competes_with_replacement()
	_test_invalid_quantity_and_fractional_cents()
	_test_inputs_are_not_mutated()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_total_loss_and_salvage() -> void:
	var dossier: Dictionary = _dossier()
	var zero_salvage: Dictionary = Calculator.calculate(dossier, _assessment(true))
	_check("complete baseline loss uses integer cents", zero_salvage["ok"] and zero_salvage["total_minor"] == 99433 and typeof(zero_salvage["total_minor"]) == TYPE_INT, str(zero_salvage))
	_check("baseline low and high bounds are retained", zero_salvage["low_minor"] == 82734 and zero_salvage["high_minor"] == 133134, str(zero_salvage))
	_check("complete-build replacement is counted once", _line_count(zero_salvage, "final_assembly_and_commissioning") == 1 and zero_salvage["replacement_minor"] == 99433)
	var two_servos: Dictionary = _assessment(true)
	two_servos["components"] = {"fuselage_servos": {"disposition": "reuse", "quantity": 2}}
	var two_result: Dictionary = Calculator.calculate(dossier, two_servos)
	_check("two explicitly reused servos credit exactly 67.98", two_result["salvage_minor"] == 6798 and two_result["total_minor"] == 92635 and two_result["known_subtotal_minor"] == 92635, str(two_result))
	_check("two-servo salvage is one explicit credit line", _line_count_action(two_result, "salvage_credit") == 1)
	var four_servos: Dictionary = _assessment(true)
	four_servos["components"] = {
		"fuselage_servos": {"disposition": "reuse", "quantity": 3},
		"central_aileron_servo": {"disposition": "reuse", "quantity": 1},
	}
	var four_result: Dictionary = Calculator.calculate(dossier, four_servos)
	_check("four explicitly reused servos credit exactly 135.96", four_result["salvage_minor"] == 13596 and four_result["total_minor"] == 85837, str(four_result))


func _test_no_duplicate_charge() -> void:
	var dossier: Dictionary = _dossier()
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {"propeller": {"disposition": "replace"}}
	var result: Dictionary = Calculator.calculate(dossier, assessment)
	_check("one damaged propeller produces one $5.39 line", result["known_subtotal_minor"] == 539 and result["total_minor"] == 539 and _line_count(result, "propeller") == 1, str(result))
	var duplicate: Dictionary = _dossier()
	var duplicate_components: Array = duplicate["components"]
	var clone: Dictionary = (duplicate_components[0] as Dictionary).duplicate(true)
	clone["id"] = "duplicate_coverage"
	duplicate_components.append(clone)
	duplicate["components"] = duplicate_components
	var invalid: Dictionary = Calculator.calculate(duplicate, assessment)
	_check("overlapping physical coverage is rejected before duplicate billing", not invalid["ok"] and _has_error(invalid, "already covered"), str(invalid["errors"]))


func _test_prop_only_with_engine_inspection() -> void:
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {
		"propeller": {"disposition": "replace"},
		"engine_and_muffler": {"disposition": "inspect"},
	}
	var result: Dictionary = Calculator.calculate(_dossier(), assessment)
	_check("prop strike keeps exact prop subtotal while engine inspection blocks total", result["ok"] and result["known_subtotal_minor"] == 539 and result["total_minor"] == null and not result["complete"], str(result))
	_check("prop and engine bounds remain visible", result["low_minor"] == 539 and result["high_minor"] == 35539 and result["outcome"] == "inspection", str(result))
	var terminal: Dictionary = _assessment(false)
	terminal["terminal"] = true
	terminal["components"] = {"propeller": {"disposition": "inspect"}}
	var terminal_result: Dictionary = Calculator.calculate(_dossier(), terminal)
	_check("terminal uncertainty uses the full-build quote only as a labeled ceiling", terminal_result["outcome"] == "inspection" and terminal_result["high_minor"] == 133134 and terminal_result["range_basis"] == "complete_build_replacement_quote_ceiling", str(terminal_result))


func _test_unknown_price_and_known_zero() -> void:
	var unknown: Dictionary = _dossier()
	var unknown_prop: Dictionary = _component("propeller", 1, null, 400, 600, ["item_propeller_main"], "exact_product_price")
	unknown["components"] = [unknown_prop]
	var replace_assessment: Dictionary = _assessment(false)
	replace_assessment["components"] = {"propeller": {"disposition": "replace"}}
	var unknown_result: Dictionary = Calculator.calculate(unknown, replace_assessment)
	_check("unknown price stays null but retains its known interval", unknown_result["ok"] and unknown_result["known_subtotal_minor"] == 0 and unknown_result["total_minor"] == null and unknown_result["low_minor"] == 400 and unknown_result["high_minor"] == 600, str(unknown_result))
	var zero: Dictionary = _dossier()
	zero["components"] = [_component("propeller", 1, 0, 0, 0, ["item_propeller_main"], "estimated")]
	var zero_result: Dictionary = Calculator.calculate(zero, replace_assessment)
	_check("a known zero-cent price stays a valid zero", zero_result["ok"] and zero_result["complete"] and zero_result["total_minor"] == 0 and zero_result["known_subtotal_minor"] == 0, str(zero_result))
	var zero_repair: Dictionary = _dossier()
	var repair: Dictionary = _assessment(false)
	repair["components"] = {"propeller": {"disposition": "repair", "repair_minor": 0}}
	var repair_result: Dictionary = Calculator.calculate(zero_repair, repair)
	_check("an explicit zero repair quote is not treated as missing", repair_result["complete"] and repair_result["total_minor"] == 0 and repair_result["lines"][0]["action"] == "repair", str(repair_result))


func _test_repair_competes_with_replacement() -> void:
	var cheaper_repair: Dictionary = _assessment(false)
	cheaper_repair["components"] = {"propeller": {"disposition": "repair", "repair_minor": 400}}
	var repaired: Dictionary = Calculator.calculate(_dossier(), cheaper_repair)
	_check("cheaper feasible repair is selected", repaired["total_minor"] == 400 and repaired["lines"][0]["action"] == "repair", str(repaired))
	var cheaper_replacement: Dictionary = _assessment(false)
	cheaper_replacement["components"] = {"propeller": {"disposition": "repair", "repair_minor": 600}}
	var replaced: Dictionary = Calculator.calculate(_dossier(), cheaper_replacement)
	_check("cheaper exact replacement is selected", replaced["total_minor"] == 539 and replaced["lines"][0]["action"] == "replacement", str(replaced))


func _test_invalid_quantity_and_fractional_cents() -> void:
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {"propeller": {"disposition": "replace", "quantity": 2}}
	var quantity_result: Dictionary = Calculator.calculate(_dossier(), assessment)
	_check("quantity beyond component coverage is rejected", not quantity_result["ok"] and _has_error(quantity_result, "exceeds dossier quantity"), str(quantity_result["errors"]))
	var fractional: Dictionary = _dossier()
	var fractional_prop: Dictionary = _component("propeller", 1, 5.39, 5.39, 5.39, ["item_propeller_main"], "exact_product_price")
	fractional["components"] = [fractional_prop]
	var fraction_result: Dictionary = Calculator.calculate(fractional, _assessment(false))
	_check("fractional currency units are rejected where integer cents are required", not fraction_result["ok"] and _has_error(fraction_result, "nonnegative integer minor-unit amount"), str(fraction_result["errors"]))
	var high_quantity: Dictionary = _assessment(false)
	high_quantity["components"] = {"propeller": {"disposition": "replace", "quantity": 1.5}}
	var fractional_quantity: Dictionary = Calculator.calculate(_dossier(), high_quantity)
	_check("fractional quantities are rejected", not fractional_quantity["ok"] and _has_error(fractional_quantity, "expected an integer"), str(fractional_quantity["errors"]))
	var too_large: Dictionary = _dossier()
	too_large["components"] = [_component("propeller", 1, 9000000000000001, null, null, ["item_propeller_main"], "estimated")]
	var overflow_result: Dictionary = Calculator.calculate(too_large, _assessment(false))
	_check("amounts beyond the supported integer-cent bound are rejected", not overflow_result["ok"] and _has_error(overflow_result, "integer minor-unit amount"), str(overflow_result["errors"]))


func _test_inputs_are_not_mutated() -> void:
	var dossier: Dictionary = _dossier()
	var assessment: Dictionary = _assessment(true)
	assessment["components"] = {"fuselage_servos": {"disposition": "reuse", "quantity": 2}}
	var dossier_before: Dictionary = dossier.duplicate(true)
	var assessment_before: Dictionary = assessment.duplicate(true)
	Calculator.calculate(dossier, assessment)
	_check("calculator leaves dossier input unchanged", dossier == dossier_before)
	_check("calculator leaves assessment input unchanged", assessment == assessment_before)


func _assessment(total_loss: bool) -> Dictionary:
	return {"components": {}, "terminal": false, "total_loss": total_loss, "unresolved": []}


func _dossier() -> Dictionary:
	return {
		"format": "openrc-aircraft-economics v1",
		"aircraft_id": "jensen-das-ugly-stik-60",
		"source_sha256": "bdcf4d64c45676a112d837513ee1eef7ed017c39fa8b39b21236cd801950f723",
		"currency": "USD",
		"price_date": "2026-10-15",
		"valuation_kind": "reconstructed_assembled_build",
		"components": [
			_component("covered_airframe_and_installation_hardware", 1, 35000, 28000, 45000, ["item_wing_airframe", "item_fuselage_front", "item_fuselage_rear", "item_stabilizer_elevator", "item_fin_rudder", "item_nose_gear_assembly", "item_main_gear_assembly", "item_engine_mount", "item_fuel_tank", "item_spinner_main", "item_control_hardware"], "estimated"),
			_component("engine_and_muffler", 1, 24999, 22500, 35000, ["item_engine_main", "item_muffler_main"], "price_proxy"),
			_component("fuselage_servos", 3, 3399, 3399, 4399, ["item_fuselage_servos"], "price_proxy"),
			_component("central_aileron_servo", 1, 3399, 3399, 4399, ["item_aileron_servo"], "price_proxy"),
			_component("receiver", 1, 9999, 9999, 9999, ["item_receiver_main"], "price_proxy"),
			_component("propeller", 1, 539, 539, 539, ["item_propeller_main"], "exact_product_price"),
			_component("receiver_battery", 1, 2500, 2000, 3500, ["item_receiver_battery"], "estimated"),
			_component("onboard_fuel", 1, 300, 100, 500, ["item_fuel_main"], "estimated"),
			_component("final_assembly_and_commissioning", 1, 12500, 6000, 21000, [], "estimated"),
		],
		"exclusions": [{"physical_inventory_id": "item_balance_mass_virtual", "reason": "virtual"}],
		"missing": [],
		"complete": true,
	}


func _component(id: String, quantity: int, unit_minor: Variant, low_minor: Variant, high_minor: Variant, inventory_ids: Array, price_basis: String) -> Dictionary:
	return {
		"id": id,
		"quantity": quantity,
		"unit_minor": unit_minor,
		"low_unit_minor": low_minor,
		"high_unit_minor": high_minor,
		"physical_inventory_ids": inventory_ids,
		"price_basis": price_basis,
		"offer_id": "test_offer" if price_basis == "exact_product_price" else null,
		"notes": "test fixture",
	}


func _line_count(report: Dictionary, component_id: String) -> int:
	var count: int = 0
	for line_value: Variant in report.get("lines", []):
		if (line_value as Dictionary).get("id") == component_id:
			count += 1
	return count


func _line_count_action(report: Dictionary, action: String) -> int:
	var count: int = 0
	for line_value: Variant in report.get("lines", []):
		if (line_value as Dictionary).get("action") == action:
			count += 1
	return count


func _has_error(report: Dictionary, needle: String) -> bool:
	for error_value: Variant in report.get("errors", []):
		if needle in String(error_value):
			return true
	return false


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
