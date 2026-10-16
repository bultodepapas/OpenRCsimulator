extends SceneTree

const Calculator = preload("res://economy/calculator.gd")
const Catalog = preload("res://economy/catalog.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_total_loss_and_salvage()
	_test_accounting_invariants_and_ordering()
	_test_no_duplicate_charge()
	_test_prop_only_with_engine_inspection()
	_test_known_inspection_fee_has_no_upper_bound()
	_test_unknown_price_and_known_zero()
	_test_repair_competes_with_replacement()
	_test_incomparable_repair_keeps_selected_cost()
	_test_invalid_quantity_and_fractional_cents()
	_test_inputs_are_not_mutated()
	_test_loaded_catalog_contract()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_total_loss_and_salvage() -> void:
	var dossier: Dictionary = _dossier()
	var zero_salvage: Dictionary = Calculator.calculate(dossier, _assessment(true))
	_check("complete baseline loss uses integer cents", zero_salvage["ok"] and zero_salvage["total_minor"] == 99433 and typeof(zero_salvage["total_minor"]) == TYPE_INT and zero_salvage["salvage_minor"] == 0, str(zero_salvage))
	_check("baseline low and high bounds are retained", zero_salvage["low_minor"] == 82734 and zero_salvage["high_minor"] == 133134, str(zero_salvage))
	_check("complete-build replacement is counted once", _line_count(zero_salvage, "final_assembly_and_commissioning") == 1 and zero_salvage["replacement_minor"] == 99433)
	var total_loss_inspection: Dictionary = _assessment(true)
	total_loss_inspection["components"] = {"engine_and_muffler": {"disposition": "inspect", "inspection_minor": 250}}
	var inspected_loss: Dictionary = Calculator.calculate(dossier, total_loss_inspection)
	_check("pending known-price total-loss salvage remains unknown", inspected_loss["known_subtotal_minor"] == 99683 and inspected_loss["high_minor"] == null and inspected_loss["low_minor"] == null and inspected_loss["total_minor"] == null and inspected_loss["salvage_minor"] == null, str(inspected_loss))
	var unknown_price: Dictionary = dossier.duplicate(true)
	for index: int in range((unknown_price["components"] as Array).size()):
		var component: Dictionary = unknown_price["components"][index]
		if component["id"] == "engine_and_muffler":
			component["unit_minor"] = null
			component["low_unit_minor"] = null
			component["high_unit_minor"] = null
			unknown_price["components"][index] = component
	var unknown_price_inspection: Dictionary = _assessment(true)
	unknown_price_inspection["components"] = {"engine_and_muffler": {"disposition": "inspect"}}
	var unknown_price_pending: Dictionary = Calculator.calculate(unknown_price, unknown_price_inspection)
	_check("pending salvage stays unknown when the inspected component has no price", unknown_price_pending["ok"] and unknown_price_pending["salvage_minor"] == null and unknown_price_pending["total_minor"] == null, str(unknown_price_pending))
	var unknown_condition: Dictionary = _assessment(true)
	unknown_condition["components"] = {"engine_and_muffler": {"disposition": "unknown"}}
	var unknown_condition_result: Dictionary = Calculator.calculate(dossier, unknown_condition)
	_check("unknown total-loss condition leaves salvage unknown", unknown_condition_result["salvage_minor"] == null and unknown_condition_result["total_minor"] == null, str(unknown_condition_result))
	var mixed_pending: Dictionary = _assessment(true)
	mixed_pending["components"] = {
		"fuselage_servos": {"disposition": "reuse", "quantity": 2},
		"engine_and_muffler": {"disposition": "inspect"},
	}
	var mixed_pending_result: Dictionary = Calculator.calculate(dossier, mixed_pending)
	_check("pending inspection makes mixed confirmed and possible salvage unknown", mixed_pending_result["salvage_minor"] == null and mixed_pending_result["total_minor"] == null and mixed_pending_result["known_subtotal_minor"] == 92635, str(mixed_pending_result))
	var blocked_salvage: Dictionary = _assessment(true)
	blocked_salvage["components"] = {"engine_and_muffler": {"disposition": "inspect", "salvage_eligible": false}}
	var blocked_salvage_result: Dictionary = Calculator.calculate(dossier, blocked_salvage)
	_check("explicitly blocked pending component contributes known zero salvage", blocked_salvage_result["salvage_minor"] == 0 and blocked_salvage_result["total_minor"] == null, str(blocked_salvage_result))
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
	var empty_complete: Dictionary = _dossier()
	empty_complete["components"] = []
	var empty_result: Dictionary = Calculator.calculate(empty_complete, _assessment(false))
	_check("an empty complete dossier cannot produce a zero-cost total", not empty_result["ok"] and _has_error(empty_result, "must cover at least one component"), str(empty_result["errors"]))


func _test_accounting_invariants_and_ordering() -> void:
	var dossier: Dictionary = _dossier()
	var assessment: Dictionary = _assessment(true)
	assessment["components"] = {"fuselage_servos": {"disposition": "reuse", "quantity": 2}}
	var result: Dictionary = Calculator.calculate(dossier, assessment)
	_check("exact total stays within reported bounds", result["low_minor"] <= result["total_minor"] and result["total_minor"] <= result["high_minor"], str(result))
	_check("replacement less explicit salvage reconciles with exact total", result["replacement_minor"] - result["salvage_minor"] == result["total_minor"], str(result))
	_check("known line amounts reconcile with subtotal including signed salvage", _line_amount_sum(result) == result["known_subtotal_minor"], str(result))
	var reordered: Dictionary = dossier.duplicate(true)
	var reversed_components: Array = (dossier["components"] as Array).duplicate(true)
	reversed_components.reverse()
	reordered["components"] = reversed_components
	var reordered_result: Dictionary = Calculator.calculate(reordered, assessment)
	_check("component order does not alter economics", result["total_minor"] == reordered_result["total_minor"] and result["low_minor"] == reordered_result["low_minor"] and result["high_minor"] == reordered_result["high_minor"], str(reordered_result))


func _test_prop_only_with_engine_inspection() -> void:
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {
		"propeller": {"disposition": "replace"},
		"engine_and_muffler": {"disposition": "inspect"},
		"covered_airframe_and_installation_hardware": {"disposition": "inspect"},
	}
	var result: Dictionary = Calculator.calculate(_dossier(), assessment)
	_check("prop strike keeps exact prop subtotal while engine inspection blocks total", result["ok"] and result["known_subtotal_minor"] == 539 and result["total_minor"] == null and not result["complete"], str(result))
	_check("prop plus engine and airframe inspection retain only the known lower bound", result["low_minor"] == 539 and result["high_minor"] == null and result["outcome"] == "inspection", str(result))
	var terminal: Dictionary = _assessment(false)
	terminal["terminal"] = true
	terminal["components"] = {"propeller": {"disposition": "inspect"}}
	var terminal_result: Dictionary = Calculator.calculate(_dossier(), terminal)
	_check("terminal replacement comparison stays separate from unbounded assessed costs", terminal_result["outcome"] == "inspection" and terminal_result["high_minor"] == null and terminal_result["range_basis"] == "component_price_bounds" and terminal_result["replacement_quote_low_minor"] == 82734 and terminal_result["replacement_quote_high_minor"] == 133134 and terminal_result["replacement_quote_scope"] == "complete_build_replacement_quote_comparison", str(terminal_result))
	var unknown_quote_dossier: Dictionary = _dossier()
	var unknown_quote_components: Array = unknown_quote_dossier["components"]
	for index: int in range(unknown_quote_components.size()):
		var component: Dictionary = unknown_quote_components[index]
		if component["id"] == "receiver":
			component["unit_minor"] = null
			component["low_unit_minor"] = null
			component["high_unit_minor"] = null
		unknown_quote_components[index] = component
	unknown_quote_dossier["components"] = unknown_quote_components
	var unknown_quote_assessment: Dictionary = _assessment(false)
	unknown_quote_assessment["terminal"] = true
	unknown_quote_assessment["components"] = {"receiver": {"disposition": "inspect"}}
	var unknown_quote: Dictionary = Calculator.calculate(unknown_quote_dossier, unknown_quote_assessment)
	_check("unknown inspection condition keeps assessed high and replacement quote unknown", unknown_quote["high_minor"] == null and unknown_quote["replacement_quote_high_minor"] == null and unknown_quote["total_minor"] == null, str(unknown_quote))


func _test_known_inspection_fee_has_no_upper_bound() -> void:
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {
		"propeller": {"disposition": "replace"},
		"engine_and_muffler": {"disposition": "inspect", "inspection_minor": 250},
		"covered_airframe_and_installation_hardware": {"disposition": "inspect", "inspection_minor": 100},
	}
	var result: Dictionary = Calculator.calculate(_dossier(), assessment)
	_check("known inspection fees add to subtotal but do not bound repair costs", result["known_subtotal_minor"] == 889 and result["low_minor"] == 889 and result["high_minor"] == null and result["total_minor"] == null, str(result))


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


func _test_incomparable_repair_keeps_selected_cost() -> void:
	var dossier: Dictionary = _dossier()
	var assessment: Dictionary = _assessment(false)
	assessment["components"] = {"propeller": {"disposition": "repair", "repair_minor": 600,
		"inspection_minor": 25, "replacement_comparable": false}}
	var result: Dictionary = Calculator.calculate(dossier, assessment)
	var line: Dictionary = result["lines"][0]
	_check("incomparable replacement does not replace a known selected repair", result["ok"] and result["complete"] and result["total_minor"] == 625 and line["action"] == "repair" and line["amount_minor"] == 625 and result["replacement_minor"] == null and result["unresolved"].is_empty(), str(result))
	var unknown: Dictionary = _dossier()
	unknown["components"] = [_component("propeller", 1, null, null, null, ["item_propeller_main"], "estimated")]
	var known_repair: Dictionary = _assessment(false)
	known_repair["components"] = {"propeller": {"disposition": "repair", "repair_minor": 600,
		"inspection_minor": 25, "replacement_comparable": false}}
	var unknown_result: Dictionary = Calculator.calculate(unknown, known_repair)
	_check("known incomparable repair and inspection fee remain exact when replacement price is unknown", unknown_result["ok"] and unknown_result["complete"] and unknown_result["total_minor"] == 625 and unknown_result["lines"][0]["action"] == "repair" and unknown_result["replacement_minor"] == null and unknown_result["unresolved"].is_empty(), str(unknown_result))
	var wrong_type: Dictionary = _assessment(false)
	wrong_type["components"] = {"propeller": {"disposition": "repair", "repair_minor": 600, "replacement_comparable": "false"}}
	var wrong_type_result: Dictionary = Calculator.calculate(dossier, wrong_type)
	_check("replacement comparability requires an explicit boolean", not wrong_type_result["ok"] and _has_error(wrong_type_result, "replacement_comparable: expected a boolean"), str(wrong_type_result["errors"]))
	var nonrepair: Dictionary = _assessment(false)
	nonrepair["components"] = {"propeller": {"disposition": "replace", "replacement_comparable": false}}
	var nonrepair_result: Dictionary = Calculator.calculate(dossier, nonrepair)
	_check("replacement comparability cannot decorate a nonrepair decision", not nonrepair_result["ok"] and _has_error(nonrepair_result, "only valid for an explicit repair decision"), str(nonrepair_result["errors"]))


func _test_invalid_quantity_and_fractional_cents() -> void:
	var empty_assessment: Dictionary = Calculator.calculate(_dossier(), _assessment(false))
	_check("empty assessment remains a valid no-damage result", empty_assessment["ok"] and empty_assessment["complete"] and empty_assessment["total_minor"] == 0 and empty_assessment["lines"].is_empty(), str(empty_assessment))
	var positive_quantity: Dictionary = _assessment(false)
	positive_quantity["components"] = {"propeller": {"disposition": "replace", "quantity": 1}}
	var positive_result: Dictionary = Calculator.calculate(_dossier(), positive_quantity)
	_check("positive affected quantity remains billable", positive_result["ok"] and positive_result["complete"] and positive_result["total_minor"] == 539 and positive_result["lines"][0]["quantity"] == 1, str(positive_result))
	var zero_quantity: Dictionary = _assessment(false)
	zero_quantity["components"] = {"propeller": {"disposition": "replace", "quantity": 0}}
	var zero_result: Dictionary = Calculator.calculate(_dossier(), zero_quantity)
	_check("zero affected quantity cannot produce a complete free replacement", not zero_result["ok"] and _has_error(zero_result, "expected an integer in 1.."), str(zero_result["errors"]))
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
	var partial_bounds: Dictionary = _dossier()
	var bounded_components: Array = partial_bounds["components"]
	var propeller: Dictionary = bounded_components[5]
	propeller["high_unit_minor"] = null
	bounded_components[5] = propeller
	partial_bounds["components"] = bounded_components
	var partial_bounds_result: Dictionary = Calculator.calculate(partial_bounds, _assessment(false))
	_check("one-sided price bounds are rejected", not partial_bounds_result["ok"] and _has_error(partial_bounds_result, "low/high bounds must both be null"), str(partial_bounds_result["errors"]))


func _test_inputs_are_not_mutated() -> void:
	var dossier: Dictionary = _dossier()
	var assessment: Dictionary = _assessment(true)
	assessment["components"] = {"fuselage_servos": {"disposition": "reuse", "quantity": 2}}
	var dossier_before: Dictionary = dossier.duplicate(true)
	var assessment_before: Dictionary = assessment.duplicate(true)
	Calculator.calculate(dossier, assessment)
	_check("calculator leaves dossier input unchanged", dossier == dossier_before)
	_check("calculator leaves assessment input unchanged", assessment == assessment_before)


func _test_loaded_catalog_contract() -> void:
	var loaded: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60")
	_check("calculator consumes the normalized runtime baseline dossier", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if bool(loaded.get("ok", false)):
		var dossier: Dictionary = loaded["dossier"]
		var propeller: Dictionary = {}
		for component_value: Variant in dossier["components"]:
			var component: Dictionary = component_value
			if component.get("id") == "propeller":
				propeller = component
		_check("loaded quantity and price fields are int minor-units", typeof(propeller.get("quantity")) == TYPE_INT and typeof(propeller.get("unit_minor")) == TYPE_INT and propeller.get("unit_minor") == 539)
		var total_loss: Dictionary = Calculator.calculate(dossier, _assessment(true))
		_check("actual baseline catalog produces the accepted integer-cent sum", total_loss.get("total_minor") == 99433 and total_loss.get("replacement_minor") == 99433, str(total_loss))
	for spec: Array in [["stik-glow-55ax-2t", 99433, 539], ["stik-glow-fs64v-4t", 130059, 1165]]:
		var variant := Catalog.load_for(spec[0])
		_check("variant economic dossier loads: " + spec[0], variant.get("ok", false))
		if not variant.get("ok", false):
			continue
		var loss := Calculator.calculate(variant.dossier, _assessment(true))
		_check("variant replacement includes its engine and prop once: " + spec[0], loss.get("total_minor") == spec[1] and _line_count(loss, "engine_and_muffler") == 1 and _line_count(loss, "propeller") == 1, str(loss))
		var inspected := _assessment(false)
		inspected.components = {"propeller": {"disposition": "replace"}, "engine_and_muffler": {"disposition": "inspect"}}
		var repair := Calculator.calculate(variant.dossier, inspected)
		_check("variant prop-only subtotal retains unknown engine inspection: " + spec[0], repair.get("known_subtotal_minor") == spec[2] and repair.get("total_minor") == null and repair.get("high_minor") == null)
		var salvage := _assessment(true)
		salvage.components = {"fuselage_servos": {"disposition": "reuse", "quantity": 2}}
		var reused := Calculator.calculate(variant.dossier, salvage)
		_check("variant conditional two-servo credit remains the installed baseline value: " + spec[0], reused.get("salvage_minor") == 6798 and reused.get("total_minor") == spec[1] - 6798)
	var incomplete: Dictionary = Catalog.load_for("gp-extra-300s-60")
	if bool(incomplete.get("ok", false)):
		var partial_report: Dictionary = Calculator.calculate(incomplete["dossier"], _assessment(true))
		_check("Extra known parts are a subtotal, never a full aircraft quote", partial_report.get("known_subtotal_minor") == 17534 and partial_report.get("total_minor") == null and partial_report.get("replacement_minor") == null, str(partial_report))
		var partial_reuse := _assessment(true)
		partial_reuse.components = {"aileron_servos": {"disposition": "reuse", "quantity": 2}}
		var extra_salvage := Calculator.calculate(incomplete.dossier, partial_reuse)
		_check("Extra two-servo reuse reduces known subtotal once without inventing unknown losses", extra_salvage.get("salvage_minor") == 6798 and extra_salvage.get("known_subtotal_minor") == 10736 and extra_salvage.get("total_minor") == null, str(extra_salvage))
		var extra_strike := _assessment(false)
		extra_strike.components = {"propeller": {"disposition": "replace"}, "engine_main": {"disposition": "inspect"}}
		var extra_repair := Calculator.calculate(incomplete.dossier, extra_strike)
		_check("Extra isolated strike prices prop only with unresolved inspection", extra_repair.get("known_subtotal_minor") == 539 and extra_repair.get("total_minor") == null and extra_repair.get("high_minor") == null)
	for spec: Array in [["turbo-lumber-evolution", 46587], ["p51d-mustang-120", 245671], ["sebart-avanti-s-a200-p100rx", 655912]]:
		var fleet: Dictionary = Catalog.load_for(spec[0])
		_check("fleet pricing dossier loads " + spec[0], fleet.get("ok", false))
		if fleet.get("ok", false):
			var report := Calculator.calculate(fleet.dossier, _assessment(true))
			_check("fleet known parts never masquerade as whole-build replacement " + spec[0], report.get("known_subtotal_minor") == spec[1] and report.get("total_minor") == null and report.get("replacement_minor") == null and report.get("high_minor") == null, str(report))
	incomplete = Catalog.load_for("xcell-60-research")
	if bool(incomplete.get("ok", false)):
		var partial_report: Dictionary = Calculator.calculate(incomplete["dossier"], _assessment(true))
		_check("runtime incomplete route cannot produce a total or zero replacement quote", not partial_report["complete"] and partial_report["total_minor"] == null and partial_report["replacement_minor"] == null and partial_report["low_minor"] == null and partial_report["high_minor"] == null and not partial_report["unresolved"].is_empty(), str(partial_report))


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


func _line_amount_sum(report: Dictionary) -> int:
	var total: int = 0
	for line_value: Variant in report.get("lines", []):
		var amount: Variant = (line_value as Dictionary).get("amount_minor")
		if typeof(amount) != TYPE_INT:
			return -1
		total += amount
	return total


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
