extends SceneTree

const Tx = preload("res://economy/cost_transaction.gd")
const Quote = preload("res://economy/replacement_quote.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_test_pair_and_modes()
	_test_fees_and_atomic_rejection()
	_test_shared_repair()
	_test_repeated_packages()
	_test_package_options()
	print("cost transaction: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _check(label: String, condition: bool, detail: Variant = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL %s %s" % [label, str(detail)])


func _part(id: String, price: Variant) -> Dictionary:
	return {"id": id, "quantity": 1, "physical_inventory_ids": ["parent-" + id], "unit_minor": price,
		"low_unit_minor": price, "high_unit_minor": price, "price_basis": "fixture_allowance", "offer_id": null}


func _dossier() -> Dictionary:
	return {"format": "openrc-aircraft-economics v2", "aircraft_id": "fixture", "source_sha256": "a".repeat(64),
		"currency": "USD", "price_date": "2026-11-09", "valuation_kind": "fixture", "complete": true,
		"missing": [], "components": [_part("left", 2100), _part("right", 2100), _part("wing_a", 5000), _part("wing_b", 5000)]}


func _assessment() -> Dictionary:
	return {"components": {"left": {"disposition": "replace"}, "right": {"disposition": "reuse"}},
		"terminal": false, "total_loss": false, "unresolved": []}


func _context() -> Dictionary:
	var book := {"format": "openrc-game-purchase-book v1", "aircraft_id": "fixture", "packages": [
		{"id": "pair", "component_quantities": {"left": 1, "right": 1}, "cost_cents": 1500,
			"available": true, "compatible": true, "provenance": "Authored game allowance; not a retail offer."}]}
	var policy := {"format": "openrc-game-labor-policy v1", "currency": "USD", "paid_rate_minor_per_hour": 6000,
		"minutes_by_component": {"left": 20, "right": 20, "wing_a": 30, "wing_b": 30},
		"shared_setup_minutes": 5, "basis": "authored_game_policy", "evidence": "Synthetic scenario rate and times."}
	return {"identity": {"incident_id": "fixture-incident", "aircraft_id": "fixture", "source_sha256": "a".repeat(64)},
		"catalog_hash": "b".repeat(64), "profile_hash": "c".repeat(64), "recipe_hash": "d".repeat(64),
		"purchase_book_hash": Tx.digest(book), "labor_policy_hash": Tx.digest(policy), "revision": 4,
		"package_book": book, "labor_policy": policy, "blocked": {}, "confirmed_replacements": {}}


func _request(context: Dictionary) -> Dictionary:
	return {"format": Tx.FORMAT, "transaction_id": "fixture-transaction", "identity": context.identity.duplicate(true),
		"catalog_hash": context.catalog_hash, "profile_hash": context.profile_hash, "recipe_hash": context.recipe_hash,
		"purchase_book_hash": context.purchase_book_hash, "labor_policy_hash": context.labor_policy_hash,
		"expected_revision": context.revision, "repair_inspection": null, "repair_choices": [], "labor_mode": "diy",
		"costing_basis": "cash", "shared_labor_groups": [], "purchase_mode": "optimal", "selected_candidate_ids": [],
		"incurred_fees": []}


func _test_pair_and_modes() -> void:
	var dossier := _dossier()
	var current := _assessment()
	var context := _context()
	var before := current.duplicate(true)
	var dossier_before := dossier.duplicate(true)
	var context_before := context.duplicate(true)
	var adapted := Tx.package_candidates(context.package_book, dossier, current)
	_check("book partitions surviving right part as surplus", adapted.ok and adapted.candidates.size() == 1 and adapted.candidates[0].coverage_ids == ["left:0"] and adapted.candidates[0].surplus_ids == ["extra@right/0"], adapted)
	var diy := Tx.prepare_mode(dossier, current, {}, context, "diy")
	_check("automatic DIY pair is the actual displayed 1500-cent estimate", diy.ok and diy.report.complete and diy.report.total_minor == 1500 and diy.receipt.purchase.total_cost_cents == 1500, diy)
	_check("one package is charged and surplus receives no credit", _line_sum(diy.report) == 1500 and _count(diy.report, "selected_purchase") == 1 and _surplus(diy.report) == ["extra@right/0"], diy.report)
	_check("prepare leaves assessment, dossier and frozen context untouched", before == current and dossier_before == dossier and context_before == context)
	var paid := Tx.prepare_mode(dossier, current, {}, context, "paid")
	_check("paid 20-minute action plus shared five-minute setup is 2500 cents", paid.ok and paid.report.total_minor == 4000 and _sum_action(paid.report, "game_labor") == 2500, paid)
	var unknown_labor := _context()
	unknown_labor.labor_policy.minutes_by_component.erase("left")
	unknown_labor.labor_policy_hash = Tx.digest(unknown_labor.labor_policy)
	var pending_labor := Tx.prepare_mode(dossier, current, {}, unknown_labor, "diy")
	_check("missing relevant work time stays unresolved even under zero-rate DIY", pending_labor.ok and not pending_labor.report.complete and pending_labor.report.total_minor == null and pending_labor.report.known_subtotal_minor == 1500 and pending_labor.report.high_minor == null, pending_labor)
	var fractional := _context()
	fractional.labor_policy.paid_rate_minor_per_hour = 1
	fractional.labor_policy.shared_setup_minutes = 0
	fractional.labor_policy_hash = Tx.digest(fractional.labor_policy)
	var rounded := Tx.prepare_mode(dossier, current, {}, fractional, "paid")
	_check("new game-policy labor declares half-up rounding at each billed group", rounded.ok and rounded.report.total_minor == 1500 and rounded.receipt.policy_labor.rounding_policy == "half_up_per_work_group", rounded)
	var explicit := _request(context)
	explicit.purchase_mode = "explicit"
	explicit.selected_candidate_ids = ["individual-000"]
	var individual := Tx.prepare(explicit, dossier, current, {}, context)
	_check("explicit higher-priced individual is feasible without a global-optimum claim", individual.ok and individual.report.total_minor == 2100 and individual.receipt.purchase.status == "selected" and not individual.receipt.purchase.optimality_proven, individual)
	var ranged := dossier.duplicate(true)
	ranged.components[0].low_unit_minor = 2000
	ranged.components[0].high_unit_minor = 2300
	var bounded := Tx.prepare(explicit, ranged, current, {}, context)
	_check("selected individual retains its authored 2000..2300 price bounds", bounded.ok and bounded.report.total_minor == 2100 and bounded.report.low_minor == 2000 and bounded.report.high_minor == 2300 and not bounded.report.range_reasons.is_empty(), bounded)
	var unknown_context := _context()
	unknown_context.package_book.packages[0].cost_cents = null
	unknown_context.purchase_book_hash = Tx.digest(unknown_context.package_book)
	_check("unknown competing price prevents automatic optimality", not Tx.prepare_mode(dossier, current, {}, unknown_context, "diy").ok)
	var explicit_known := _request(unknown_context)
	explicit_known.purchase_mode = "explicit"
	explicit_known.selected_candidate_ids = ["individual-000"]
	_check("a known explicit choice survives an unknown competing price", Tx.prepare(explicit_known, dossier, current, {}, unknown_context).ok)
	var none := {"components": {"right": {"disposition": "reuse"}}, "terminal": false, "total_loss": false, "unresolved": []}
	_check("explicit purchase with no required units is rejected", Quote.quote_explicit(dossier, none, [], ["individual-000"]).status == "invalid_selection")
	var terminal_empty := {"components": {}, "terminal": true, "total_loss": false, "unresolved": []}
	var pending := Tx.prepare_mode(dossier, terminal_empty, {}, context, "diy")
	_check("terminal incident without any assessed components cannot become a free bill", pending.ok and not pending.report.complete and pending.report.total_minor == null and not pending.report.unresolved.is_empty(), pending)


func _test_fees_and_atomic_rejection() -> void:
	var dossier := _dossier()
	var current := _assessment()
	var context := _context()
	var request := _request(context)
	request.incurred_fees = [{"id": "inspection-1", "kind": "inspection", "amount_minor": 500}]
	var result := Tx.prepare(request, dossier, current, {}, context)
	_check("one identified inspection adds 500 cents exactly once", result.ok and result.report.total_minor == 2000 and _line_sum(result.report) == 2000 and _count(result.report, "incurred_fee") == 1, result)
	var other_option := Tx.prepare_package_option(dossier, result.assessment, {}, context, "diy", "pair")
	_check("an alternative package estimate includes the same sunk fee once", other_option.ok and other_option.report.total_minor == 2000 and _count(other_option.report, "incurred_fee") == 1, other_option)
	_check("frozen transaction replays from its base assessment and book", Tx.verify_receipt(result.receipt, dossier, {}, context))
	var unknown := request.duplicate(true)
	unknown.incurred_fees[0].amount_minor = null
	var pending := Tx.prepare(unknown, dossier, current, {}, context)
	_check("unknown incurred fee leaves a subtotal and no complete total", pending.ok and not pending.report.complete and pending.report.known_subtotal_minor == 1500 and pending.report.total_minor == null and pending.report.high_minor == null, pending)
	var duplicate := request.duplicate(true)
	duplicate.incurred_fees.append(duplicate.incurred_fees[0].duplicate(true))
	var original := current.duplicate(true)
	_check("duplicate fee is rejected without changing assessment", not Tx.prepare(duplicate, dossier, current, {}, context).ok and current == original)
	var component_fee := current.duplicate(true)
	component_fee.components.left.inspection_minor = 500
	var with_component_fee := Tx.prepare_mode(dossier, component_fee, {}, context, "diy")
	_check("inspection attached to a selected part stays charged once", with_component_fee.ok and with_component_fee.report.total_minor == 2000 and _count(with_component_fee.report, "incurred_fee") == 1, with_component_fee)
	var colliding := _request(context)
	colliding.incurred_fees = [{"id": "component:left:inspection", "kind": "inspection", "amount_minor": 500}]
	_check("same component fee ID cannot be added a second time", not Tx.prepare(colliding, dossier, component_fee, {}, context).ok)
	var cyclic := _request(context)
	var loop: Array = []
	loop.append(loop)
	cyclic.incurred_fees = loop
	_check("cyclic transaction data is refused before cloning", not Tx.prepare(cyclic, dossier, current, {}, context).ok)
	var cyclic_context := _context()
	var blocked_loop := {}
	blocked_loop["self"] = blocked_loop
	cyclic_context.blocked = blocked_loop
	_check("cyclic restriction snapshots are refused before cloning", not Tx.prepare(_request(cyclic_context), dossier, current, {}, cyclic_context).ok)
	_check("missing frozen context is a clean rejection", not Tx.prepare_mode(dossier, current, {}, {}, "diy").ok)
	var stale := request.duplicate(true)
	stale.expected_revision -= 1
	_check("stale revision is rejected atomically", not Tx.prepare(stale, dossier, current, {}, context).ok and current == original)
	var bad_hash := request.duplicate(true)
	bad_hash.purchase_book_hash = "e".repeat(64)
	_check("different frozen book identity is rejected", not Tx.prepare(bad_hash, dossier, current, {}, context).ok)
	var broken: Dictionary = result.receipt.duplicate(true)
	broken.purchase.selected_lines[0].cost_cents = 1
	_check("modified frozen receipt is rejected", not Tx.reconcile(dossier, result.assessment, broken).ok)
	broken.erase("receipt_digest")
	broken["receipt_digest"] = Tx.digest(broken)
	_check("recomputed receipt checksum cannot forge purchase arithmetic", not Tx.verify_receipt(broken, dossier, {}, context))
	var reimpact: Dictionary = result.assessment.duplicate(true)
	reimpact.components.right = {"disposition": "replace"}
	_check("later required unit invalidates the prior plan", not Tx.reconcile(dossier, reimpact, result.receipt).ok)
	var next_context := context.duplicate(true)
	next_context.revision += 1
	var next := Tx.prepare_mode(dossier, reimpact, {}, next_context, "diy")
	_check("reimpact produces a fresh pair estimate and retains old incurred fee once", next.ok and next.report.total_minor == 2000 and _count(next.report, "incurred_fee") == 1 and result.receipt.purchase.selected_coverage[0].surplus_ids == ["extra@right/0"], next)


func _test_shared_repair() -> void:
	var dossier := _dossier()
	var context := _context()
	var current := {"components": {"wing_a": {"disposition": "inspect"}, "wing_b": {"disposition": "inspect"}}, "terminal": false, "total_loss": false, "unresolved": []}
	var request := _request(context)
	request.labor_mode = "paid"
	request.incurred_fees = [{"id": "inspection-1", "kind": "inspection", "amount_minor": 500}]
	request.repair_inspection = {"format": "openrc-repair-inspection v1", "basis": "scenario_assumption", "components": {
		"wing_a": _repair_inspection(4), "wing_b": _repair_inspection(3)}}
	request.repair_choices = [{"component_id": "wing_a", "option_id": "patch"}, {"component_id": "wing_b", "option_id": "patch"}]
	request.shared_labor_groups = [{"id": "shared", "component_ids": ["wing_a", "wing_b"], "labor_minutes": 30,
		"scope": "shared_complete_work", "basis": "scenario_assumption", "evidence": "One shared synthetic job."}]
	var result := Tx.prepare(request, dossier, current, _recipes(), context)
	_check("two repairs share one 1000-cent pack, 3000 labor and 500 sunk fee", result.ok and result.report.total_minor == 4500 and _line_sum(result.report) == 4500 and _sum_action(result.report, "repair_material") == 1000 and _sum_action(result.report, "repair_labor") == 3000, result)
	var consumption := request.duplicate(true)
	consumption.costing_basis = "consumption"
	var allocated := Tx.prepare(consumption, dossier, current, _recipes(), context)
	_check("consumption basis is 700 plus 3000 labor and 500 fee", allocated.ok and allocated.report.total_minor == 4200 and _line_sum(allocated.report) == 4200, allocated)
	var restricted := context.duplicate(true)
	restricted.confirmed_replacements.wing_a = true
	_check("confirmed replacement cannot be downgraded through a repair transaction", not Tx.prepare(request, dossier, current, _recipes(), restricted).ok)
	var unexpected := request.duplicate(true)
	unexpected.repair_inspection.components.wing_a["unreviewed_override"] = true
	_check("closed versioned repair inspection rejects unknown fields", not Tx.prepare(unexpected, dossier, current, _recipes(), context).ok)
	var mixed := current.duplicate(true)
	mixed.components["left"] = {"disposition": "replace"}
	mixed.components["right"] = {"disposition": "reuse"}
	_check("mixed work refuses an ambiguous shared setup", not Tx.prepare(request, dossier, mixed, _recipes(), context).ok)
	var coordinated := request.duplicate(true)
	coordinated.shared_labor_groups.append({"id": "all-setup", "component_ids": ["wing_a", "wing_b", "left"],
		"labor_minutes": 5, "scope": "shared_setup_all_work", "basis": "scenario_assumption",
		"evidence": "The recipe and default work exclude this single shared setup."})
	var mixed_result := Tx.prepare(coordinated, dossier, mixed, _recipes(), context)
	_check("mixed repairs and replacement charge one explicitly shared setup", mixed_result.ok and mixed_result.report.total_minor == 8500 and _line_sum(mixed_result.report) == 8500 and _sum_action(mixed_result.report, "game_labor") == 2500, mixed_result)
	var double_setup := coordinated.duplicate(true)
	double_setup.shared_labor_groups[0].scope = "additional_setup"
	_check("separate recipe setup cannot be charged with the shared setup", not Tx.prepare(double_setup, dossier, mixed, _recipes(), context).ok)


func _test_repeated_packages() -> void:
	var dossier := _dossier()
	dossier.components[0].quantity = 4
	dossier.components[0].unit_minor = 80
	dossier.components[0].low_unit_minor = 80
	dossier.components[0].high_unit_minor = 80
	var assessment := {"components": {"left": {"disposition": "replace", "quantity": 4}}, "terminal": false, "total_loss": false, "unresolved": []}
	var context := _context()
	context.package_book.packages = [{"id": "two-pack", "component_quantities": {"left": 2}, "cost_cents": 100,
		"available": true, "compatible": true, "provenance": "Synthetic repeatable pair allowance."}]
	context.purchase_book_hash = Tx.digest(context.package_book)
	var result := Tx.prepare_mode(dossier, assessment, {}, context, "diy")
	_check("four required units use two 100-cent packs, not one pack plus two singles", result.ok and result.report.total_minor == 200 and _count(result.report, "selected_purchase") == 2 and _line_sum(result.report) == 200, result)
	var ids: Dictionary = {}
	for line: Dictionary in result.report.lines:
		for id: Variant in line.get("allocated_ids", []):
			ids[id] = true
	_check("two purchased pack instances allocate all four required units once", ids.size() == 4)
	var long_a := "x".repeat(90) + "a"
	var long_b := "x".repeat(90) + "b"
	var prefix_context := context.duplicate(true)
	prefix_context.package_book.packages = [
		{"id": long_a, "component_quantities": {"left": 2}, "cost_cents": 100, "available": true, "compatible": true, "provenance": "first allowance"},
		{"id": long_b, "component_quantities": {"left": 2}, "cost_cents": 90, "available": true, "compatible": true, "provenance": "second allowance"},
	]
	prefix_context.purchase_book_hash = Tx.digest(prefix_context.package_book)
	var first_option := Tx.prepare_package_option(dossier, assessment, {}, prefix_context, "diy", long_a)
	var second_option := Tx.prepare_package_option(dossier, assessment, {}, prefix_context, "diy", long_b)
	_check("long package IDs sharing a prefix remain distinct across generated allocations", first_option.ok and second_option.ok and first_option.report.total_minor == 260 and second_option.report.total_minor == 250, [first_option, second_option])
	_check("receipt freezes the exact source package identity rather than a candidate prefix", first_option.ok and first_option.receipt.purchase.selected_source_packages.size() == 1 and first_option.receipt.purchase.selected_source_packages[0].package_id == long_a and Tx.verify_receipt(first_option.receipt, dossier, {}, prefix_context), first_option)
	dossier.components[0].quantity = 12
	assessment.components.left.quantity = 12
	context.package_book.packages[0].component_quantities.left = 6
	context.purchase_book_hash = Tx.digest(context.package_book)
	var limited := Tx.prepare_mode(dossier, assessment, {}, context, "diy")
	_check("allocation overflow is refused instead of claiming an optimum", not limited.ok and str(limited.errors).contains("bound"), limited)
	context.package_book.packages[0].available = false
	context.purchase_book_hash = Tx.digest(context.package_book)
	var unavailable := Tx.prepare_mode(dossier, assessment, {}, context, "diy")
	_check("unavailable oversized alternative cannot block 12 known individual parts", unavailable.ok and unavailable.report.total_minor == 960, unavailable)
	context.package_book.packages[0].available = null
	context.purchase_book_hash = Tx.digest(context.package_book)
	var uncertain := Tx.prepare_mode(dossier, assessment, {}, context, "diy")
	_check("unknown eligibility is not silently excluded to bypass the allocation bound", not uncertain.ok and str(uncertain.errors).contains("bound"), uncertain)


func _test_package_options() -> void:
	var dossier := _dossier()
	var assessment := _assessment()
	var context := _context()
	context.package_book.packages.append({"id": "pair-extra", "component_quantities": {"left": 1},
		"cost_cents": 20, "available": true, "compatible": true, "provenance": "Synthetic separate option."})
	context.purchase_book_hash = Tx.digest(context.package_book)
	var pair := Tx.prepare_package_option(dossier, assessment, {}, context, "diy", "pair")
	_check("explicit package ID cannot match another package sharing its prefix", pair.ok and pair.report.total_minor == 1500 and pair.receipt.request.purchase_mode == "explicit" and not pair.receipt.purchase.optimality_proven, pair)
	_check("explicit package choice replays against the frozen book", pair.ok and Tx.verify_receipt(pair.receipt, dossier, {}, context))
	var alternative := Tx.prepare_package_option(dossier, assessment, {}, context, "diy", "pair-extra")
	_check("the other exact package ID selects its own 20-cent allowance", alternative.ok and alternative.report.total_minor == 20, alternative)
	var missing_unit_price := dossier.duplicate(true)
	missing_unit_price.components[0].unit_minor = null
	missing_unit_price.components[0].low_unit_minor = null
	missing_unit_price.components[0].high_unit_minor = null
	var chosen_pair := Tx.prepare_package_option(missing_unit_price, assessment, {}, context, "diy", "pair")
	_check("known chosen package prices its covered unit despite unknown individual price", chosen_pair.ok and chosen_pair.report.complete and chosen_pair.report.total_minor == 1500, chosen_pair)
	assessment.components["right"] = {"disposition": "replace"}
	var partial := Tx.prepare_package_option(dossier, assessment, {}, context, "diy", "pair-extra")
	_check("package option adds each uncovered individual exactly once", partial.ok and partial.report.total_minor == 2120 and _count(partial.report, "selected_purchase") == 2 and _line_sum(partial.report) == 2120, partial)
	_check("unknown package ID is rejected without inventing a price", not Tx.prepare_package_option(dossier, assessment, {}, context, "diy", "missing").ok)
	context.package_book.packages[1].available = null
	context.purchase_book_hash = Tx.digest(context.package_book)
	_check("unknown package availability cannot be explicitly selected", not Tx.prepare_package_option(dossier, assessment, {}, context, "diy", "pair-extra").ok)


func _repair_inspection(units: int) -> Dictionary:
	return {"status": "inspected", "damage_class": "covering_only", "quantity": 1, "replacement_comparable": false,
		"measurements": {"units": units}, "labor_minutes": 30, "evidence": "Synthetic explicit inspection."}


func _recipes() -> Dictionary:
	var source := {"kind": "fixture", "source_name": "fixture", "evidence": "synthetic", "price_minor": 1000,
		"currency": "USD", "source_url": "https://example.test/pack", "observed_on": "2026-11-09", "availability": "fixture"}
	return {"format": "openrc-repair-recipes v1", "currency": "USD", "recipes": [{"id": "patch", "label": "Patch", "repair_unit": "units",
		"damage_classes": ["covering_only"], "compatible_components": {"fixture": ["wing_a", "wing_b"]},
		"materials": [{"id": "film", "requirement_key": "units", "unit": "unit", "package_units": 10, "package_price_minor": 1000, "source": source}],
		"labor": {"diy_rate_minor_per_hour": 0, "paid_rate_minor_per_hour": 6000,
			"diy_provenance": {"kind": "fixture", "description": "DIY"},
			"paid_provenance": {"kind": "fixture", "description": "paid", "rate_minor_per_hour": 6000}}}]}


func _line_sum(report: Dictionary) -> int:
	var result := 0
	for line: Dictionary in report.get("lines", []):
		if line.get("amount_minor") != null:
			result += int(line.amount_minor)
	return result


func _sum_action(report: Dictionary, action: String) -> int:
	var result := 0
	for line: Dictionary in report.get("lines", []):
		if line.get("action") == action and line.get("amount_minor") != null:
			result += int(line.amount_minor)
	return result


func _count(report: Dictionary, action: String) -> int:
	var result := 0
	for line: Dictionary in report.get("lines", []):
		if line.get("action") == action:
			result += 1
	return result


func _surplus(report: Dictionary) -> Array:
	for line: Dictionary in report.get("lines", []):
		if line.get("action") == "selected_purchase":
			return line.get("surplus_ids", [])
	return []
