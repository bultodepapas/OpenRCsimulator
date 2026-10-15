extends RefCounted

const FORMAT: String = "openrc-aircraft-economics v1"
const MAX_MINOR: int = 9000000000000000
const MAX_QUANTITY: int = 1000000
const DISPOSITIONS: Array[String] = ["reuse", "replace", "repair", "inspect", "unknown", "unrecoverable"]


## Calculates a plain report without changing either input.
## Assessment quantity is the affected count; repair and inspection cents are row totals.
static func calculate(dossier: Dictionary, assessment: Dictionary) -> Dictionary:
	var report: Dictionary = _empty_report()
	report["currency"] = dossier.get("currency", "USD") if typeof(dossier.get("currency", "USD")) == TYPE_STRING else "USD"
	report["valuation_kind"] = dossier.get("valuation_kind", "") if typeof(dossier.get("valuation_kind", "")) == TYPE_STRING else ""
	report["price_date"] = dossier.get("price_date", "") if typeof(dossier.get("price_date", "")) == TYPE_STRING else ""
	var errors: Array = []
	var unresolved: Array = []
	var components: Array = []
	var components_by_id: Dictionary = {}
	var assessment_components: Dictionary = {}
	var source_complete: bool = false
	var is_total_loss: bool = false
	var aggregate_ceiling: int = 0

	if dossier.get("format") != FORMAT:
		errors.append("dossier.format: expected '%s'" % FORMAT)
	if not _is_nonempty_string(dossier.get("aircraft_id")):
		errors.append("dossier.aircraft_id: expected a nonempty string")
	if not _is_nonempty_string(dossier.get("source_sha256")):
		errors.append("dossier.source_sha256: expected a nonempty string")
	if not _is_nonempty_string(dossier.get("currency")):
		errors.append("dossier.currency: expected a nonempty string")
	if not _is_nonempty_string(dossier.get("price_date")):
		errors.append("dossier.price_date: expected a nonempty string")
	if not _is_nonempty_string(dossier.get("valuation_kind")):
		errors.append("dossier.valuation_kind: expected a nonempty string")
	if typeof(dossier.get("complete")) != TYPE_BOOL:
		errors.append("dossier.complete: expected a boolean")
	else:
		source_complete = dossier["complete"]
	var raw_components: Variant = dossier.get("components")
	if typeof(raw_components) != TYPE_ARRAY:
		errors.append("dossier.components: expected an array")
	else:
		components = raw_components
		var seen_inventory: Dictionary = {}
		for index: int in range(components.size()):
			var component_value: Variant = components[index]
			if typeof(component_value) != TYPE_DICTIONARY:
				errors.append("dossier.components[%d]: expected an object" % index)
				continue
			var component: Dictionary = component_value
			var component_id: Variant = component.get("id")
			if not _is_nonempty_string(component_id):
				errors.append("dossier.components[%d].id: expected a nonempty string" % index)
				continue
			if components_by_id.has(component_id):
				errors.append("dossier.components[%d].id: duplicate '%s'" % [index, component_id])
				continue
			var quantity_value: Variant = component.get("quantity")
			if not _is_quantity(quantity_value) or quantity_value == 0:
				errors.append("dossier.components[%s].quantity: expected an integer in 1..%d" % [component_id, MAX_QUANTITY])
			var ids_value: Variant = component.get("physical_inventory_ids")
			if typeof(ids_value) != TYPE_ARRAY:
				errors.append("dossier.components[%s].physical_inventory_ids: expected an array" % component_id)
			else:
				for physical_id_value: Variant in ids_value:
					if not _is_nonempty_string(physical_id_value):
						errors.append("dossier.components[%s].physical_inventory_ids: entries must be nonempty strings" % component_id)
					elif seen_inventory.has(physical_id_value):
						errors.append("dossier.components[%s].physical_inventory_ids: '%s' is already covered by '%s'" % [component_id, physical_id_value, seen_inventory[physical_id_value]])
					else:
						seen_inventory[physical_id_value] = component_id
			for price_key: String in ["unit_minor", "low_unit_minor", "high_unit_minor"]:
				if not component.has(price_key):
					errors.append("dossier.components[%s]: missing '%s'" % [component_id, price_key])
				elif component[price_key] != null and not _is_minor(component[price_key]):
					errors.append("dossier.components[%s].%s: expected null or a nonnegative integer minor-unit amount" % [component_id, price_key])
			if _is_minor(component.get("low_unit_minor")) and _is_minor(component.get("high_unit_minor")) and component["low_unit_minor"] > component["high_unit_minor"]:
				errors.append("dossier.components[%s]: low_unit_minor exceeds high_unit_minor" % component_id)
			if _is_minor(component.get("unit_minor")) and _is_minor(component.get("low_unit_minor")) and component["unit_minor"] < component["low_unit_minor"]:
				errors.append("dossier.components[%s]: unit_minor is below low_unit_minor" % component_id)
			if _is_minor(component.get("unit_minor")) and _is_minor(component.get("high_unit_minor")) and component["unit_minor"] > component["high_unit_minor"]:
				errors.append("dossier.components[%s]: unit_minor exceeds high_unit_minor" % component_id)
			if not _is_nonempty_string(component.get("price_basis")):
				errors.append("dossier.components[%s].price_basis: expected a nonempty string" % component_id)
			if component.get("offer_id") != null and typeof(component.get("offer_id")) != TYPE_STRING:
				errors.append("dossier.components[%s].offer_id: expected null or a string" % component_id)
			var upper_unit: Variant = component.get("high_unit_minor") if component.get("high_unit_minor") != null else component.get("unit_minor")
			if _is_minor(upper_unit) and _is_quantity(quantity_value) and quantity_value > 0:
				var upper_product: Dictionary = _multiply_minor(upper_unit, quantity_value)
				if not bool(upper_product["ok"]) or int(upper_product["value"]) > MAX_MINOR - aggregate_ceiling:
					errors.append("dossier.components[%s]: aggregate amount exceeds supported integer range" % component_id)
				else:
					aggregate_ceiling += int(upper_product["value"])
			components_by_id[component_id] = component

	var raw_missing: Variant = dossier.get("missing", [])
	if typeof(raw_missing) != TYPE_ARRAY:
		errors.append("dossier.missing: expected an array")
	else:
		_append_unresolved(unresolved, raw_missing, "dossier.missing", errors)

	if typeof(assessment.get("terminal", false)) != TYPE_BOOL:
		errors.append("assessment.terminal: expected a boolean")
	if typeof(assessment.get("total_loss", false)) != TYPE_BOOL:
		errors.append("assessment.total_loss: expected a boolean")
	else:
		is_total_loss = assessment["total_loss"]
	var raw_assessment_components: Variant = assessment.get("components", {})
	if typeof(raw_assessment_components) != TYPE_DICTIONARY:
		errors.append("assessment.components: expected an object")
	else:
		assessment_components = raw_assessment_components
		for key_value: Variant in assessment_components.keys():
			if typeof(key_value) != TYPE_STRING or not components_by_id.has(key_value):
				errors.append("assessment.components: unknown component '%s'" % str(key_value))
				continue
			var decision_value: Variant = assessment_components[key_value]
			if typeof(decision_value) != TYPE_DICTIONARY:
				errors.append("assessment.components[%s]: expected an object" % key_value)
				continue
			var decision: Dictionary = decision_value
			if not DISPOSITIONS.has(decision.get("disposition", "")):
				errors.append("assessment.components[%s].disposition: expected a supported disposition" % key_value)
			if decision.has("quantity") and not _is_quantity(decision["quantity"]):
				errors.append("assessment.components[%s].quantity: expected an integer in 0..%d" % [key_value, MAX_QUANTITY])
			if decision.has("repair_minor") and not _is_minor(decision["repair_minor"]):
				errors.append("assessment.components[%s].repair_minor: expected a nonnegative integer minor-unit amount" % key_value)
			if decision.has("inspection_minor") and not _is_minor(decision["inspection_minor"]):
				errors.append("assessment.components[%s].inspection_minor: expected a nonnegative integer minor-unit amount" % key_value)
			if decision.has("salvage_eligible") and typeof(decision["salvage_eligible"]) != TYPE_BOOL:
				errors.append("assessment.components[%s].salvage_eligible: expected a boolean" % key_value)
			if decision.get("disposition") == "reuse" and decision.get("salvage_eligible", true) == false:
				errors.append("assessment.components[%s]: reuse conflicts with salvage_eligible=false" % key_value)
			for fee_key: String in ["repair_minor", "inspection_minor"]:
				if _is_minor(decision.get(fee_key)):
					var fee_amount: int = decision[fee_key]
					if fee_amount > MAX_MINOR - aggregate_ceiling:
						errors.append("assessment.components[%s]: aggregate amount exceeds supported integer range" % key_value)
					else:
						aggregate_ceiling += fee_amount
			var component_quantity: Variant = components_by_id[key_value].get("quantity", 0)
			var affected_quantity: int = int(decision.get("quantity", component_quantity))
			if _is_quantity(component_quantity) and affected_quantity > int(component_quantity):
				errors.append("assessment.components[%s].quantity: exceeds dossier quantity %d" % [key_value, component_quantity])

	var raw_assessment_unresolved: Variant = assessment.get("unresolved", [])
	if typeof(raw_assessment_unresolved) != TYPE_ARRAY:
		errors.append("assessment.unresolved: expected an array")
	else:
		_append_unresolved(unresolved, raw_assessment_unresolved, "assessment.unresolved", errors)

	if not errors.is_empty():
		report["ok"] = false
		report["errors"] = errors
		report["outcome"] = "unavailable"
		report["unresolved"] = unresolved
		return report

	var known_subtotal: int = 0
	var low_total: int = 0
	var high_total: int = 0
	var low_possible: bool = true
	var high_possible: bool = true
	var calculation_complete: bool = source_complete and unresolved.is_empty()
	var replacement_total: int = 0
	var replacement_complete: bool = true
	var salvage_total: int = 0
	var salvage_complete: bool = true
	var saw_inspection: bool = false
	var lines: Array = []
	if not unresolved.is_empty():
		saw_inspection = true

	if is_total_loss:
		for component_value: Variant in components:
			var component: Dictionary = component_value
			var component_id: String = component["id"]
			var component_quantity: int = component["quantity"]
			var price: Variant = component["unit_minor"]
			var low_price: Variant = component["low_unit_minor"] if component["low_unit_minor"] != null else price
			var high_price: Variant = component["high_unit_minor"] if component["high_unit_minor"] != null else price
			var reused_quantity: int = 0
			var decision: Dictionary = assessment_components.get(component_id, {})
			if decision.get("disposition") == "reuse":
				reused_quantity = int(decision.get("quantity", component_quantity))
				if reused_quantity > 0:
					if (component["physical_inventory_ids"] as Array).is_empty():
						_append_one(unresolved, "%s: no physical inventory binding; reuse cannot be credited" % component_id)
						reused_quantity = 0
						calculation_complete = false
					elif price == null:
						_append_one(unresolved, "%s: reuse has no exact baseline unit price" % component_id)
						salvage_complete = false
						calculation_complete = false
					else:
						var credit_result: Dictionary = _multiply_minor(price, reused_quantity)
						if not bool(credit_result["ok"]):
							_append_one(errors, "%s: salvage amount exceeds supported integer range" % component_id)
						else:
							salvage_total += int(credit_result["value"])
						var low_credit: Variant = null
						var high_credit: Variant = null
						if low_price != null:
							var low_result: Dictionary = _multiply_minor(low_price, reused_quantity)
							if bool(low_result["ok"]):
								low_credit = low_result["value"]
						if high_price != null:
							var high_result: Dictionary = _multiply_minor(high_price, reused_quantity)
							if bool(high_result["ok"]):
								high_credit = high_result["value"]
						if low_credit == null:
							low_possible = false
						else:
							low_total -= int(low_credit)
						if high_credit == null:
							high_possible = false
						else:
							high_total -= int(high_credit)
						lines.append(_line(component, reused_quantity, "salvage_credit", -int(credit_result["value"]), {"condition": "explicit reuse disposition", "credit_basis": "identical_baseline_avoided_purchase", "baseline_unit_minor": price}))
				if decision.has("inspection_minor"):
					var inspection_fee: int = decision["inspection_minor"]
					known_subtotal += inspection_fee
					low_total += inspection_fee
					high_total += inspection_fee
					lines.append(_line(component, 1, "inspection", inspection_fee, {}))
			if decision.get("disposition") == "inspect":
				saw_inspection = true
				_append_one(unresolved, "%s: salvage or condition is pending inspection" % component_id)
				calculation_complete = false
			if decision.get("disposition") == "unknown":
				_append_one(unresolved, "%s: condition is unknown" % component_id)
				calculation_complete = false

			var gross_result: Dictionary = _multiply_minor(price, component_quantity) if price != null else {"ok": false, "value": 0}
			var low_result: Dictionary = _multiply_minor(low_price, component_quantity) if low_price != null else {"ok": false, "value": 0}
			var high_result: Dictionary = _multiply_minor(high_price, component_quantity) if high_price != null else {"ok": false, "value": 0}
			if bool(gross_result["ok"]):
				replacement_total += int(gross_result["value"])
				known_subtotal += int(gross_result["value"])
			else:
				replacement_complete = false
				calculation_complete = false
				_append_one(unresolved, "%s: replacement price is unknown" % component_id)
			if bool(low_result["ok"]):
				low_total += int(low_result["value"])
			else:
				low_possible = false
			if bool(high_result["ok"]):
				high_total += int(high_result["value"])
			else:
				high_possible = false
			if reused_quantity > 0 and price != null:
				var reuse_result: Dictionary = _multiply_minor(price, reused_quantity)
				if bool(reuse_result["ok"]):
					known_subtotal -= int(reuse_result["value"])
				lines.append(_line(component, component_quantity, "replacement", int(gross_result["value"]) if bool(gross_result["ok"]) else null, {"reused_quantity": reused_quantity}))
			else:
				lines.append(_line(component, component_quantity, "replacement", int(gross_result["value"]) if bool(gross_result["ok"]) else null, {}))
			if decision.has("inspection_minor") and decision.get("disposition") != "reuse":
				var inspection_amount: int = decision["inspection_minor"]
				known_subtotal += inspection_amount
				low_total += inspection_amount
				high_total += inspection_amount
				lines.append(_line(component, 1, "inspection", inspection_amount, {}))

		if not replacement_complete:
			report["replacement_minor"] = null
		else:
			report["replacement_minor"] = replacement_total
		if not salvage_complete:
			report["salvage_minor"] = null
		else:
			report["salvage_minor"] = salvage_total
	else:
		var terminal: bool = assessment.get("terminal", false)
		if terminal and assessment_components.is_empty():
			saw_inspection = true
			calculation_complete = false
			_append_one(unresolved, "terminal incident: component assessment is pending")
		for component_value: Variant in components:
			var component: Dictionary = component_value
			var component_id: String = component["id"]
			if not assessment_components.has(component_id):
				continue
			var decision: Dictionary = assessment_components[component_id]
			var disposition: String = decision["disposition"]
			var component_quantity: int = component["quantity"]
			var quantity: int = int(decision.get("quantity", component_quantity))
			var price: Variant = component["unit_minor"]
			var low_price: Variant = component["low_unit_minor"] if component["low_unit_minor"] != null else price
			var high_price: Variant = component["high_unit_minor"] if component["high_unit_minor"] != null else price
			var replacement: Dictionary = _price_for_quantity(price, low_price, high_price, quantity)
			var base_amount: Variant = null
			var base_low: Variant = 0
			var base_high: Variant = 0
			var action: String = disposition
			var extra: Dictionary = {}
			var row_incomplete: bool = false
			if disposition == "reuse":
				base_amount = 0
				base_low = 0
				base_high = 0
			elif disposition == "replace" or disposition == "unrecoverable":
				action = "replacement"
				base_amount = replacement["amount"]
				base_low = replacement["low"]
				base_high = replacement["high"]
				if base_amount == null:
					row_incomplete = true
					replacement_complete = false
					_append_one(unresolved, "%s: replacement price is unknown" % component_id)
				else:
					replacement_total += int(base_amount)
			elif disposition == "repair":
				var has_repair_quote: bool = decision.has("repair_minor")
				var repair_quote: int = int(decision["repair_minor"]) if has_repair_quote else 0
				if has_repair_quote and replacement["amount"] != null:
					if repair_quote <= int(replacement["amount"]):
						base_amount = repair_quote
						base_low = repair_quote
						base_high = repair_quote
						action = "repair"
					else:
						base_amount = replacement["amount"]
						base_low = replacement["low"]
						base_high = replacement["high"]
						action = "replacement"
						replacement_total += int(base_amount)
				elif has_repair_quote and replacement["low"] != null and repair_quote <= int(replacement["low"]):
					base_amount = repair_quote
					base_low = repair_quote
					base_high = repair_quote
					action = "repair"
				elif has_repair_quote and replacement["high"] != null and repair_quote >= int(replacement["high"]):
					base_low = replacement["low"]
					base_high = replacement["high"]
					action = "replacement"
					row_incomplete = true
					replacement_complete = false
					_append_one(unresolved, "%s: replacement price range is still uncertain" % component_id)
				else:
					base_low = mini(repair_quote, int(replacement["low"])) if has_repair_quote and replacement["low"] != null else 0
					base_high = mini(repair_quote, int(replacement["high"])) if has_repair_quote and replacement["high"] != null else (repair_quote if has_repair_quote else replacement["high"])
					row_incomplete = true
					replacement_complete = false
					if has_repair_quote:
						_append_one(unresolved, "%s: repair and replacement costs cannot be ranked exactly" % component_id)
					else:
						_append_one(unresolved, "%s: repair quote is unknown" % component_id)
			elif disposition == "inspect":
				action = "inspection"
				base_amount = null
				base_low = 0
				base_high = replacement["high"]
				row_incomplete = true
				replacement_complete = false
				saw_inspection = true
				_append_one(unresolved, "%s: condition is pending inspection" % component_id)
			elif disposition == "unknown":
				base_amount = null
				base_low = 0
				base_high = replacement["high"]
				row_incomplete = true
				replacement_complete = false
				saw_inspection = true
				_append_one(unresolved, "%s: condition is unknown" % component_id)

			var inspection_fee: int = int(decision["inspection_minor"]) if decision.has("inspection_minor") else 0
			if decision.has("inspection_minor"):
				extra["inspection_minor"] = inspection_fee
			var line_amount: Variant = null
			if base_amount != null:
				line_amount = int(base_amount) + inspection_fee
				known_subtotal += int(line_amount)
			elif disposition == "inspect" and decision.has("inspection_minor"):
				line_amount = inspection_fee
				known_subtotal += inspection_fee
			elif inspection_fee > 0:
				known_subtotal += inspection_fee
			var line_low: Variant = int(base_low) + inspection_fee if base_low != null else null
			var line_high: Variant = int(base_high) + inspection_fee if base_high != null else null
			if line_low == null:
				low_possible = false
			else:
				low_total += int(line_low)
			if line_high == null:
				high_possible = false
			else:
				high_total += int(line_high)
			if row_incomplete or line_amount == null:
				calculation_complete = false
			lines.append(_line(component, quantity, action, line_amount, extra.merged({"low_minor": line_low, "high_minor": line_high})))

		if terminal and source_complete and (saw_inspection or not unresolved.is_empty()):
			var complete_build_high: int = 0
			var complete_build_high_known: bool = true
			for component_value: Variant in components:
				var component: Dictionary = component_value
				var component_high: Variant = component["high_unit_minor"] if component["high_unit_minor"] != null else component["unit_minor"]
				if component_high == null:
					complete_build_high_known = false
					break
				var product: Dictionary = _multiply_minor(component_high, component["quantity"])
				if not bool(product["ok"]):
					complete_build_high_known = false
					break
				complete_build_high += int(product["value"])
			if complete_build_high_known:
				high_total = maxi(high_total, complete_build_high)
				report["range_basis"] = "complete_build_replacement_quote_ceiling"

		report["replacement_minor"] = replacement_total if replacement_complete else null
		report["salvage_minor"] = 0

	if not errors.is_empty():
		report["ok"] = false
		report["errors"] = errors
		report["outcome"] = "unavailable"
		report["unresolved"] = unresolved
		return report

	if not unresolved.is_empty():
		calculation_complete = false
	report["ok"] = true
	report["errors"] = []
	report["known_subtotal_minor"] = known_subtotal
	report["low_minor"] = low_total if low_possible else null
	report["high_minor"] = high_total if high_possible else null
	report["total_minor"] = known_subtotal if calculation_complete else null
	report["complete"] = calculation_complete
	report["outcome"] = "total_loss" if is_total_loss else ("inspection" if saw_inspection else "repair")
	report["lines"] = lines
	report["unresolved"] = unresolved
	return report


static func _empty_report() -> Dictionary:
	return {
		"ok": false,
		"errors": [],
		"currency": "USD",
		"known_subtotal_minor": 0,
		"low_minor": null,
		"high_minor": null,
		"total_minor": null,
		"complete": false,
		"valuation_kind": "",
		"outcome": "unavailable",
		"lines": [],
		"salvage_minor": 0,
		"replacement_minor": null,
		"unresolved": [],
		"range_basis": "component_price_bounds",
		"price_date": "",
	}


static func _line(component: Dictionary, quantity: int, action: String, amount: Variant, extra: Dictionary) -> Dictionary:
	var line: Dictionary = {
		"id": component["id"],
		"quantity": quantity,
		"action": action,
		"amount_minor": amount,
		"price_basis": component["price_basis"],
		"offer_id": component.get("offer_id"),
	}
	for key_value: Variant in extra.keys():
		line[key_value] = extra[key_value]
	return line


static func _price_for_quantity(unit: Variant, low_unit: Variant, high_unit: Variant, quantity: int) -> Dictionary:
	var amount: Variant = null
	var low: Variant = null
	var high: Variant = null
	if unit != null:
		var amount_product: Dictionary = _multiply_minor(unit, quantity)
		if bool(amount_product["ok"]):
			amount = amount_product["value"]
	if low_unit != null:
		var low_product: Dictionary = _multiply_minor(low_unit, quantity)
		if bool(low_product["ok"]):
			low = low_product["value"]
	if high_unit != null:
		var high_product: Dictionary = _multiply_minor(high_unit, quantity)
		if bool(high_product["ok"]):
			high = high_product["value"]
	return {"amount": amount, "low": low, "high": high}


static func _multiply_minor(value: Variant, quantity: int) -> Dictionary:
	if not _is_minor(value) or quantity < 0:
		return {"ok": false, "value": 0}
	var unit_minor: int = value
	if unit_minor > 0 and quantity > MAX_MINOR / unit_minor:
		return {"ok": false, "value": 0}
	return {"ok": true, "value": unit_minor * quantity}


static func _append_unresolved(target: Array, values: Array, prefix: String, errors: Array) -> void:
	for index: int in range(values.size()):
		var value: Variant = values[index]
		if typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty():
			_append_one(target, String(value))
		else:
			errors.append("%s[%d]: expected a nonempty string" % [prefix, index])


static func _append_one(target: Array, value: String) -> void:
	if not target.has(value):
		target.append(value)


static func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()


static func _is_minor(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_MINOR


static func _is_quantity(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= MAX_QUANTITY
