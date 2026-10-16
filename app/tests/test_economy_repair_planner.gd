extends SceneTree

const Planner := preload("res://economy/repair_planner.gd")
const DOSSIER_FORMAT := "openrc-aircraft-economics v1"
const INSPECTION_FORMAT := "openrc-repair-inspection v1"
const PACKAGED_RECIPES_PATH := "res://data/economy/repair-recipes.json"
const RESEARCH_RECIPES_PATH := "res://../research/crash-economics/repair-recipes.json"

var _checks: int = 0
var _failures: int = 0
var _recipes: Dictionary = {}


func _initialize() -> void:
	_recipes = _read_recipes(PACKAGED_RECIPES_PATH)
	var source_recipes: Dictionary = _read_recipes(RESEARCH_RECIPES_PATH)
	_check("packaged and researched recipe JSON parse", not _recipes.is_empty() and not source_recipes.is_empty())
	_check("packaged runtime recipe snapshot matches the authored research source", JSON.stringify(_recipes) == JSON.stringify(source_recipes))
	_test_covering_costs_and_modes()
	_test_string_name_measurement_key()
	_test_damage_class_boundaries()
	_test_recipe_applicability()
	_test_package_rounding()
	_test_alternative_options_are_not_accumulated()
	_test_unknown_comparator_and_replacement()
	_test_invalid_data_and_overlap()
	_test_bounded_overflow()
	_test_input_purity()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _read_recipes(resource_path: String) -> Dictionary:
	var path: String = ProjectSettings.globalize_path(resource_path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed := JSON.new()
	if parsed.parse(file.get_as_text()) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	return parsed.data


func _test_covering_costs_and_modes() -> void:
	var dossier: Dictionary = _dossier()
	var inspected: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30)
	var diy: Dictionary = Planner.plan(dossier, inspected, _recipes, "diy")
	_check("explicit covering inspection produces a candidate", diy.ok and diy.components.covered_airframe_and_installation_hardware.options.size() == 1, str(diy))
	var diy_option: Dictionary = diy.components.covered_airframe_and_installation_hardware.options[0]
	_check("film consumption rounds allocation up to one cent value", diy_option.material_consumption_minor == 14)
	_check("package cash cost charges one full roll", diy_option.material_purchase_minor == 2299)
	_check("DIY cost preserves effort while explicitly excluding money rate", diy_option.labor_minutes == 30 and diy_option.labor_minor == 0)
	_check("DIY totals distinguish used material from package purchase", diy_option.repair_consumption_minor == 14 and diy_option.repair_cash_minor == 2299)
	_check("replacement comparator is only exact and explicitly scope-matched", diy.components.covered_airframe_and_installation_hardware.replacement_minor == 35000 and diy_option.comparison_cash == "repair_less")
	_check("planner never auto-selects a repair", diy.recommendation == null)
	var cash_choice: Dictionary = Planner.select_option(diy, "covered_airframe_and_installation_hardware", "covering-film-patch")
	var use_choice: Dictionary = Planner.select_option(diy, "covered_airframe_and_installation_hardware", "covering-film-patch", "consumption")
	_check("cash option returns calculator repair decision with component count and matched comparator", cash_choice.ok and cash_choice.decision.disposition == "repair" and cash_choice.decision.quantity == 1 and cash_choice.decision.repair_minor == 2299 and cash_choice.decision.replacement_comparable == true, str(cash_choice))
	_check("selected repair provenance carries the applicable aircraft/component scope", cash_choice.provenance.aircraft_id == "jensen-das-ugly-stik-60" and cash_choice.provenance.applicable_component_ids_for_aircraft == ["covered_airframe_and_installation_hardware"])
	_check("consumption option is explicit and still uses component count", use_choice.ok and use_choice.decision.quantity == 1 and use_choice.decision.repair_minor == 14 and use_choice.costing_basis == "consumption", str(use_choice))
	var paid: Dictionary = Planner.plan(dossier, inspected, _recipes, "paid")
	var paid_option: Dictionary = paid.components.covered_airframe_and_installation_hardware.options[0]
	_check("paid labor is calculated from explicit minutes and the recorded rate", paid_option.labor_minor == 2250 and paid_option.labor_rate_minor_per_hour == 4500)
	_check("paid total uses package purchase plus labor", paid_option.repair_cash_minor == 4549 and paid_option.repair_consumption_minor == 2264)


func _test_string_name_measurement_key() -> void:
	var inspected: Dictionary = _inspection("covering_only", {&"covering_area_milli_sq_in": 10500}, 1, true, 30)
	var result: Dictionary = Planner.plan(_dossier(), inspected, _recipes, "diy")
	_check("StringName measurement keys normalize without relaxing integer values", result.ok and result.components.covered_airframe_and_installation_hardware.options.size() == 1, str(result))


func _test_damage_class_boundaries() -> void:
	var structural: Dictionary = Planner.plan(_dossier(), _inspection("structural", {"structural_material_units": 1}, 1, true, 20), _recipes, "paid")
	_check("structural inspection gets only the structural candidate", structural.ok and structural.components.covered_airframe_and_installation_hardware.options.size() == 1 and structural.components.covered_airframe_and_installation_hardware.options[0].id == "structural-repair-unpriced-candidate", str(structural))
	var structural_option: Dictionary = structural.components.covered_airframe_and_installation_hardware.options[0]
	_check("structural cost remains null rather than assumed zero", structural_option.material_consumption_minor == null and structural_option.material_purchase_minor == null and structural_option.repair_cash_minor == null)
	var structural_choice: Dictionary = Planner.select_option(structural, "covered_airframe_and_installation_hardware", "structural-repair-unpriced-candidate")
	_check("unpriced structural repair refuses a finite selection", not structural_choice.ok and structural_choice.decision == null and _has(structural_choice.errors, "no finite"), str(structural_choice))
	var unknown: Dictionary = Planner.plan(_dossier(), _inspection("unknown", {}, 1, true, 30), _recipes, "diy")
	_check("unknown damage class offers no repair recipe", unknown.ok and unknown.components.covered_airframe_and_installation_hardware.options.is_empty())
	var pending: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30)
	pending.components.covered_airframe_and_installation_hardware.status = "pending"
	var uninspected: Dictionary = Planner.plan(_dossier(), pending, _recipes, "diy")
	_check("pending inspection cannot produce a film option", uninspected.ok and uninspected.components.covered_airframe_and_installation_hardware.options.is_empty())
	var pending_replacement: Dictionary = Planner.select_option(uninspected, "covered_airframe_and_installation_hardware", "replace")
	_check("pending inspection cannot select replacement from an assumed affected count", not pending_replacement.ok and pending_replacement.decision == null)


func _test_recipe_applicability() -> void:
	var baseline: Dictionary = _dossier()
	var baseline_plan: Dictionary = Planner.plan(baseline, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), _recipes, "diy")
	_check("Stik covering recipe is scoped to the authored combined airframe group", baseline_plan.ok and baseline_plan.components.covered_airframe_and_installation_hardware.options.size() == 1)
	var baseline_scope: Dictionary = baseline_plan.components.covered_airframe_and_installation_hardware.options[0].compatible_components
	_check("covering recipe records explicit aircraft/component applicability", baseline_scope.get("jensen-das-ugly-stik-60", []) == ["covered_airframe_and_installation_hardware"])

	var engine_inspection: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30, "engine_and_muffler")
	var engine_plan: Dictionary = Planner.plan(baseline, engine_inspection, _recipes, "diy")
	_check("covering-only label cannot make a Stik engine eligible for film", engine_plan.ok and engine_plan.components.engine_and_muffler.options.is_empty())

	var foam_dossier: Dictionary = _dossier()
	foam_dossier.aircraft_id = "turbo-lumber-evolution"
	foam_dossier.components = [{"id": "wing_main", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["foam-wing"]}]
	var foam_plan: Dictionary = Planner.plan(foam_dossier, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, false, 30, "wing_main"), _recipes, "diy")
	_check("covering-only label cannot make the foam aircraft wing eligible for film", foam_plan.ok and foam_plan.components.wing_main.options.is_empty())

	var p51_dossier: Dictionary = _dossier()
	p51_dossier.aircraft_id = "p51d-mustang-120"
	var p51_plan: Dictionary = Planner.plan(p51_dossier, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, false, 30), _recipes, "diy")
	_check("unresearched P-51 identity is ineligible despite a covering-only declaration", p51_plan.ok and p51_plan.components.covered_airframe_and_installation_hardware.options.is_empty())

	var unknown_component_plan: Dictionary = Planner.plan(baseline, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, false, 30, "unlisted_component"), _recipes, "diy")
	_check("unknown component ID is rejected before recipe costing", not unknown_component_plan.ok and _has(unknown_component_plan.errors, "unknown component"))

	var extra_dossier: Dictionary = _dossier()
	extra_dossier.aircraft_id = "gp-extra-300s-60"
	extra_dossier.components = [
		{"id": "wing_main", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-wing"]},
		{"id": "fuselage_front", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-fuselage-front"]},
		{"id": "fuselage_rear", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-fuselage-rear"]},
		{"id": "horizontal_tail", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-horizontal-tail"]},
		{"id": "vertical_tail", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-vertical-tail"]},
		{"id": "engine_main", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-engine"]},
		{"id": "canopy_pilot", "quantity": 1, "unit_minor": null, "physical_inventory_ids": ["extra-canopy"]},
	]
	var extra_inspected: Dictionary = {}
	for component_id: String in ["wing_main", "fuselage_front", "fuselage_rear", "horizontal_tail", "vertical_tail", "engine_main", "canopy_pilot"]:
		extra_inspected[component_id] = {
			"status": "inspected",
			"damage_class": "covering_only",
			"quantity": 1,
			"replacement_comparable": false,
			"measurements": {"covering_area_milli_sq_in": 10500},
			"labor_minutes": 30,
			"evidence": "explicit fixture inspection",
		}
	var extra_plan: Dictionary = Planner.plan(extra_dossier, {"format": INSPECTION_FORMAT, "basis": "inspection", "components": extra_inspected}, _recipes, "diy")
	var extra_surfaces_eligible: bool = extra_plan.ok
	for component_id: String in ["wing_main", "fuselage_front", "fuselage_rear", "horizontal_tail", "vertical_tail"]:
		extra_surfaces_eligible = extra_surfaces_eligible and extra_plan.components[component_id].options.size() == 1
	_check("Extra film candidate applies only to the mapped wing, fuselage and tail surfaces", extra_surfaces_eligible, str(extra_plan))
	_check("Extra engine and canopy remain outside covering recipe scope", extra_plan.ok and extra_plan.components.engine_main.options.is_empty() and extra_plan.components.canopy_pilot.options.is_empty())


func _test_package_rounding() -> void:
	var inspected: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 1833001}, 1, true, 0)
	var result: Dictionary = Planner.plan(_dossier(), inspected, _recipes, "diy")
	var option: Dictionary = result.components.covered_airframe_and_installation_hardware.options[0]
	var line: Dictionary = option.materials[0]
	_check("slightly more than one package rounds purchase to two packages", line.package_count == 2 and line.purchase_minor == 4598, str(line))
	_check("consumption allocation does not round up to the second package", line.consumption_minor == 2300, str(line))


func _test_alternative_options_are_not_accumulated() -> void:
	var alternatives: Dictionary = _recipes.duplicate(true)
	var second: Dictionary = alternatives.recipes[0].duplicate(true)
	second.id = "covering-film-patch-alternative"
	second.label = "Alternative candidate, same material source"
	alternatives.recipes.append(second)
	var result: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), alternatives, "diy")
	_check("each matching recipe remains a separate alternative", result.ok and result.components.covered_airframe_and_installation_hardware.options.size() == 2)
	_check("alternatives are not added into a combined materials total", result.components.covered_airframe_and_installation_hardware.options[0].repair_cash_minor == 2299 and result.components.covered_airframe_and_installation_hardware.options[1].repair_cash_minor == 2299)
	var selected: Dictionary = Planner.select_option(result, "covered_airframe_and_installation_hardware", "covering-film-patch")
	_check("selected option bills only its own one-package candidate", selected.ok and selected.decision.repair_minor == 2299)


func _test_unknown_comparator_and_replacement() -> void:
	var dossier: Dictionary = _dossier()
	dossier.components[0].unit_minor = null
	var result: Dictionary = Planner.plan(dossier, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), _recipes, "diy")
	_check("null exact replacement price stays null", result.components.covered_airframe_and_installation_hardware.replacement_minor == null and result.components.covered_airframe_and_installation_hardware.options[0].comparison_cash == "unknown")
	var replacement: Dictionary = Planner.select_option(result, "covered_airframe_and_installation_hardware", "replace")
	_check("explicit replacement selection does not invent a cost", replacement.ok and replacement.decision.disposition == "replace" and replacement.decision.quantity == 1 and not replacement.decision.has("repair_minor") and not replacement.unresolved.is_empty(), str(replacement))
	var incomparable: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, false, 30), _recipes, "diy")
	_check("replacement comparator is withheld without explicit same-scope confirmation", incomparable.components.covered_airframe_and_installation_hardware.replacement_minor == null)
	var incomparable_choice: Dictionary = Planner.select_option(incomparable, "covered_airframe_and_installation_hardware", "covering-film-patch")
	_check("selected incomparable repair carries its scope decision into the receipt", incomparable_choice.ok and incomparable_choice.decision.replacement_comparable == false, str(incomparable_choice))
	var bad_basis: Dictionary = Planner.select_option(result, "covered_airframe_and_installation_hardware", "covering-film-patch", "free")
	_check("unsupported cost basis is refused", not bad_basis.ok and bad_basis.decision == null)
	var cheap_replacement_dossier: Dictionary = _dossier()
	cheap_replacement_dossier.components[0].unit_minor = 100
	var comparison_plan: Dictionary = Planner.plan(cheap_replacement_dossier, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), _recipes, "diy")
	var repair_choice: Dictionary = Planner.select_option(comparison_plan, "covered_airframe_and_installation_hardware", "covering-film-patch")
	var explicit_replace: Dictionary = Planner.select_option(comparison_plan, "covered_airframe_and_installation_hardware", "replace")
	_check("a more expensive repair is refused without silently changing the action", not repair_choice.ok and repair_choice.decision == null and _has(repair_choice.errors, "choose replacement explicitly"))
	_check("replacement remains a separate explicit user choice", explicit_replace.ok and explicit_replace.decision.disposition == "replace")


func _test_invalid_data_and_overlap() -> void:
	var invalid_mode: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), _recipes, "automatic")
	_check("labor mode cannot be inferred", not invalid_mode.ok)
	var over_count: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 3, true, 30), _recipes, "diy")
	_check("affected count is bounded by dossier quantity", not over_count.ok and _has(over_count.errors, "exceeds the dossier"))
	var fraction: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 10.5}, 1, true, 30)
	var invalid_measure: Dictionary = Planner.plan(_dossier(), fraction, _recipes, "diy")
	_check("fractional material unit is rejected rather than rounded implicitly", not invalid_measure.ok and _has(invalid_measure.errors, "integer"))
	var duplicate_inventory: Dictionary = _dossier()
	duplicate_inventory.components[1].physical_inventory_ids = ["item_wing_airframe"]
	var duplicate_plan: Dictionary = Planner.plan(duplicate_inventory, _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), _recipes, "diy")
	_check("overlapping physical coverage is rejected before a finite plan", not duplicate_plan.ok and _has(duplicate_plan.errors, "overlaps"), str(duplicate_plan.errors))
	var duplicate_materials: Dictionary = _recipes.duplicate(true)
	duplicate_materials.recipes[0].materials.append(duplicate_materials.recipes[0].materials[0].duplicate(true))
	var duplicate_material_plan: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), duplicate_materials, "diy")
	_check("duplicate material line within one recipe cannot double bill", not duplicate_material_plan.ok and _has(duplicate_material_plan.errors, "duplicate or invalid material id"))
	var fractional_recipe: Dictionary = _recipes.duplicate(true)
	fractional_recipe.recipes[0].materials[0].package_price_minor = 2299.5
	var fractional_price_plan: Dictionary = Planner.plan(_dossier(), _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30), fractional_recipe, "diy")
	_check("fractional cents from recipe input are rejected", not fractional_price_plan.ok and _has(fractional_price_plan.errors, "bounded integer cents"))
	var nan_measure: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": NAN}, 1, true, 30)
	var nan_plan: Dictionary = Planner.plan(_dossier(), nan_measure, _recipes, "diy")
	_check("non-finite measurement cannot enter cost arithmetic", not nan_plan.ok and _has(nan_plan.errors, "integer"))


func _test_bounded_overflow() -> void:
	var oversized_book: Dictionary = _recipes.duplicate(true)
	oversized_book.recipes[0].materials[0].package_price_minor = 9000000000000000
	oversized_book.recipes[0].materials[0].package_units = 1
	oversized_book.recipes[0].materials[0].source.price_minor = 9000000000000000
	var inspected: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 1000000000}, 1, true, 0)
	var result: Dictionary = Planner.plan(_dossier(), inspected, oversized_book, "diy")
	_check("overflow yields unresolved null cost without wrapping", result.ok and result.components.covered_airframe_and_installation_hardware.options[0].repair_cash_minor == null and not result.components.covered_airframe_and_installation_hardware.options[0].unresolved.is_empty(), str(result.components.covered_airframe_and_installation_hardware.options[0]))
	var refused: Dictionary = Planner.select_option(result, "covered_airframe_and_installation_hardware", "covering-film-patch")
	_check("overflow candidate cannot be selected with a finite quote", not refused.ok and refused.decision == null)


func _test_input_purity() -> void:
	var dossier: Dictionary = _dossier()
	var inspected: Dictionary = _inspection("covering_only", {"covering_area_milli_sq_in": 10500}, 1, true, 30)
	var recipe_copy: Dictionary = _recipes.duplicate(true)
	var dossier_before: String = JSON.stringify(dossier)
	var inspection_before: String = JSON.stringify(inspected)
	var recipes_before: String = JSON.stringify(recipe_copy)
	Planner.plan(dossier, inspected, recipe_copy, "diy")
	_check("plan leaves caller dictionaries untouched", dossier_before == JSON.stringify(dossier) and inspection_before == JSON.stringify(inspected) and recipes_before == JSON.stringify(recipe_copy))


func _dossier() -> Dictionary:
	return {
		"format": DOSSIER_FORMAT,
		"currency": "USD",
		"aircraft_id": "jensen-das-ugly-stik-60",
		"source_sha256": "0123456789abcdef",
		"components": [
			{"id": "covered_airframe_and_installation_hardware", "quantity": 1, "unit_minor": 35000, "physical_inventory_ids": ["item_wing_airframe", "item_fuselage_front", "item_fuselage_rear", "item_stabilizer_elevator", "item_fin_rudder", "item_nose_gear_assembly", "item_main_gear_assembly", "item_engine_mount", "item_fuel_tank", "item_spinner_main", "item_control_hardware"]},
			{"id": "engine_and_muffler", "quantity": 1, "unit_minor": 24999, "physical_inventory_ids": ["item_engine_main", "item_muffler_main"]},
		],
	}


func _inspection(damage_class: String, measurements: Dictionary, quantity: int,
		replacement_comparable: bool, labor_minutes: int, component_id: String = "covered_airframe_and_installation_hardware") -> Dictionary:
	return {
		"format": INSPECTION_FORMAT,
		"basis": "inspection",
		"components": {
			component_id: {
				"status": "inspected",
				"damage_class": damage_class,
				"quantity": quantity,
				"replacement_comparable": replacement_comparable,
				"measurements": measurements,
				"labor_minutes": labor_minutes,
				"evidence": "human inspection; measurement entered explicitly",
			},
		},
	}


func _has(values: Array, substring: String) -> bool:
	for value: Variant in values:
		if substring in str(value):
			return true
	return false


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
