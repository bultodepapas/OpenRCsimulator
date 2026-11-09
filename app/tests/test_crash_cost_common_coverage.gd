extends SceneTree
## Declared game-policy coverage only; these fixtures do not establish physical failure.
const Catalog = preload("res://economy/catalog.gd")
const Incident = preload("res://economy/incident.gd")
const Aircraft = preload("res://physics/aircraft_data.gd")
const Routes = preload("res://app_state/aircraft_catalog.gd")
const Contract = preload("res://physics/aircraft_contact_contract.gd")
const Events = preload("res://sim/aircraft_contact_events.gd")
const Hull = preload("res://physics/hull_contact.gd")
const ReportArchive = preload("res://economy/report_archive.gd")

# Independently reviewed financial groups. A priced group is not a claim that
# every unobserved physical hazard has been assessed.
const STIK = {"wing": ["airframe_wing"], "body": ["airframe_fuselage"], "tail": ["airframe_tail"],
	"gear": ["gear_main", "gear_nose"], "propulsion": ["engine_and_muffler", "engine_mount", "propeller"]}
const ESSENTIAL = {
	"jensen-das-ugly-stik-60": STIK,
	"stik-glow-61fx-2t": STIK,
	"stik-glow-55ax-2t": STIK,
	"stik-glow-fs64v-4t": STIK,
	"stik-electric-6s": {"wing": ["item_wing_airframe"], "body": ["item_fuselage_front", "item_fuselage_rear"],
		"tail": ["item_stabilizer_elevator", "item_fin_rudder"], "gear": ["item_main_gear_assembly", "item_nose_gear_assembly"],
		"propulsion": ["item_motor_main", "item_motor_mount", "item_propeller_main", "item_prop_adapter"]},
	"gp-extra-300s-60": {"wing": ["wing_main"], "body": ["fuselage_front", "fuselage_rear"], "tail": ["horizontal_tail", "vertical_tail"],
		"gear": ["landing_gear_main", "landing_gear_tail"], "propulsion": ["engine_main", "engine_mount", "propeller"]},
	"p51d-mustang-120": {"wing": ["wing_left", "wing_right", "wing_joiner"], "body": ["fuselage_front", "fuselage_rear"],
		"tail": ["horizontal_tail", "vertical_tail"], "gear": ["gear_main_left", "gear_main_right", "gear_tail"],
		"propulsion": ["engine_main", "engine_mount", "propeller"]},
	"f4u-corsair-250": {"wing": ["wing_left", "wing_right", "wing_joiner"], "body": ["fuselage_front", "fuselage_rear"],
		"tail": ["horizontal_tail", "vertical_tail"], "gear": ["gear_main_left", "gear_main_right", "gear_tail"],
		"propulsion": ["engine_moki_s250", "engine_mount", "propeller"]},
	"sebart-avanti-s-a200-p100rx": {"wing": ["wing_left", "wing_right", "wing_joiner"], "body": ["airframe_fuselage"],
		"tail": ["airframe_tail"], "gear": ["gear_main_left", "gear_main_right", "gear_nose"],
		"propulsion": ["engine_main", "turbine_accessories", "thrust_tube"]},
	"turbo-lumber-evolution": {"wing": ["wing_main", "wing_servos"], "body": ["fuselage_main"], "tail": ["tail_surfaces"],
		"gear": ["gear_main", "gear_tail"], "propulsion": ["motor_main", "propeller_main"]},
	"moonrunner-x99": {"wing": ["wing_left", "wing_right", "spars_main"], "body": ["body_main"],
		"propulsion": ["motor_main", "motor_mount", "propeller_main"]},
}
var checks := 0
var failures := 0
var zone_cases := 0
var target_cases := 0
var follow_cases := 0
var ledger := {"format": "openrc-crash-cost-coverage-evidence v1", "routes": {}}
var coverage_by_route := {}


func _initialize() -> void:
	var route_ids := Array(Routes.ids())
	route_ids.erase("xcell-60-research")
	route_ids.sort()
	var expected_ids := ESSENTIAL.keys()
	expected_ids.sort()
	check("exactly eleven fixed-wing routes are independently listed", route_ids == expected_ids)
	for id: String in route_ids:
		var loaded: Dictionary = Catalog.load_for(id)
		var physical: Dictionary = Aircraft.load_file(Routes.entry(id).data)
		check(id + " profile and physical bindings load", loaded.get("ok", false) and physical.get("ok", false))
		if not loaded.get("ok", false) or not physical.get("ok", false):
			continue
		var bindings: Dictionary = Contract.describe(physical.model, true)
		var coverage := _coverage(loaded, ESSENTIAL[id])
		check(id + " essential groups and every declared target are priced", coverage.ok, coverage)
		coverage_by_route[id] = coverage
		var owner := Incident.new()
		var route := {"essential_groups": coverage.groups, "declared_classes": {}, "class_financial_coverage": coverage.classes,
			"declared_zone_targets": coverage.zone_targets, "propeller_followups": coverage.followups}
		ledger.routes[id] = route
		for zone: Dictionary in loaded.damage_profile.zones:
			_test_zone(owner, loaded, id, bindings, zone, route.declared_classes)
		_test_missing_channels(owner, loaded, id, bindings)
	check("all fixed-wing routes pass explicit financial coverage", _fleet_ok(coverage_by_route))
	_test_missing_price_controls()
	_test_avanti_component_rules()
	var dir := ProjectSettings.globalize_path("res://").path_join("../tmp/crash-cost-round3-coverage").simplify_path()
	var directory_ok := DirAccess.make_dir_recursive_absolute(dir) == OK
	var path := dir.path_join("ledger-%d.json" % Time.get_ticks_usec())
	var file := FileAccess.open(path, FileAccess.WRITE) if directory_ok else null
	if file != null:
		file.store_string(JSON.stringify(ledger, "", true, true))
		file.close()
	check("bounded deterministic coverage ledger written", file != null)
	print("coverage: %d checks, %d failed; %d routes, %d zones, %d target associations, %d prop follow-ups" % [checks, failures, route_ids.size(), zone_cases, target_cases, follow_cases])
	print("coverage ledger: " + path)
	quit(1 if failures else 0)


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label, ": ", str(detail))


func _part(dossier: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in dossier.components:
		if row.id == id:
			return row
	return {}


func _priced(part: Dictionary) -> bool:
	var amount: Variant = part.get("unit_minor")
	return not part.is_empty() and typeof(amount) == TYPE_INT and amount >= 0 and not str(part.get("price_basis", "")).is_empty()


func _coverage(loaded: Dictionary, essential: Dictionary) -> Dictionary:
	var groups := {}
	var classes := {}
	var ok := true
	for group: String in essential:
		var ids: Array = essential[group].duplicate()
		ids.sort()
		var missing := []
		for id: String in ids:
			if not _priced(_part(loaded.dossier, id)):
				missing.append(id)
		groups[group] = {"ids": ids, "missing_price": missing}
		ok = ok and missing.is_empty()
	var zone_targets := {}
	var followups := []
	for zone: Dictionary in loaded.damage_profile.zones:
		var class_id := _class_id(zone)
		if not classes.has(class_id):
			classes[class_id] = {"missing_price": [], "missing_allowance": []}
		for id: String in zone.component_ids:
			zone_targets[id] = true
			var rule: Dictionary = zone.component_responses.get(id, zone.response)
			var allowance: Variant = rule.get("service_minor_by_component", {}).get(id)
			if not _priced(_part(loaded.dossier, id)) and id not in classes[class_id].missing_price:
				classes[class_id].missing_price.append(id)
			if (typeof(allowance) != TYPE_INT or allowance < 0) and id not in classes[class_id].missing_allowance:
				classes[class_id].missing_allowance.append(id)
			ok = ok and _priced(_part(loaded.dossier, id)) and rule.get("kind") == "channel_bands" \
				and rule.get("middle_action") == "repair" and typeof(allowance) == TYPE_INT and allowance >= 0
	if not loaded.damage_profile.propeller_followups.is_empty():
		classes["propeller/followup"] = {"missing_price": [], "missing_allowance": []}
	for follow: Dictionary in loaded.damage_profile.propeller_followups:
		followups.append(follow.component_id)
		if not _priced(_part(loaded.dossier, follow.component_id)):
			classes["propeller/followup"].missing_price.append(follow.component_id)
		if typeof(follow.service_minor) != TYPE_INT or follow.service_minor < 0:
			classes["propeller/followup"].missing_allowance.append(follow.component_id)
		ok = ok and _priced(_part(loaded.dossier, follow.component_id)) and follow.middle_action == "repair" \
			and typeof(follow.service_minor) == TYPE_INT and follow.service_minor >= 0
	var targets := zone_targets.keys()
	targets.sort()
	followups.sort()
	for item: Dictionary in classes.values():
		item.missing_price.sort()
		item.missing_allowance.sort()
	var required_followups: Array = loaded.dossier.propeller_inspection_ids.duplicate()
	required_followups.erase(loaded.dossier.propeller_component_id)
	required_followups.sort()
	ok = ok and followups == required_followups
	return {"ok": ok, "groups": groups, "classes": classes, "zone_targets": targets, "followups": followups}


func _fleet_ok(routes: Dictionary) -> bool:
	if routes.size() != ESSENTIAL.size():
		return false
	for id: String in ESSENTIAL:
		if not routes.has(id) or not routes[id].ok:
			return false
	return true


func _class_id(zone: Dictionary) -> String:
	var channel := "propeller_strike" if zone.source == "propeller" else str(zone.response.channel)
	return str(zone.source) + "/" + channel


func _begin(owner: RefCounted, loaded: Dictionary, id: String) -> void:
	owner.begin_with_catalog(loaded, id, loaded.dossier.source_sha256)


func _index(bindings: Dictionary, key: String, id: String) -> int:
	for i in bindings.get(key, []).size():
		if bindings[key][i].id == id:
			return i
	return -1


func _event(bindings: Dictionary, zone: Dictionary, severe: bool, missing_normal := false) -> Dictionary:
	if zone.source == "hull":
		var index := _index(bindings, "hull_probes", zone.probe_id)
		if index < 0:
			return {}
		var record := {"index": index, "new": true, "depth_m": 0.030 if severe else 0.014}
		if not missing_normal:
			record["normal_speed_mps"] = 45.0 if severe else 8.0
		var result := Events.hull_events([record], bindings, PackedStringArray(), 1)
		return result.events[0] if result.get("ok", false) and not result.events.is_empty() else {}
	if zone.source == "gear":
		var index := _index(bindings, "support_points", zone.probe_id)
		return Events.support_event(index, 1.01 if severe else 0.90, 0.0, 1.0, 1, bindings) if index >= 0 else {}
	if zone.source == "propeller":
		var strike := {"tick": 1, "rpm": 22000.0 if severe else 9000.0,
			"point_ned": PackedFloat64Array([0, 0, 0]), "velocity_ned": PackedFloat64Array([50 if severe else 20, 0, 0])}
		return Events.strike_event(strike, 1, Hull.law(), bindings)
	return {}


func _run(owner: RefCounted, loaded: Dictionary, id: String, bindings: Dictionary, event: Dictionary) -> Dictionary:
	_begin(owner, loaded, id)
	owner.observe({"tick": 1, "events": [event]}, bindings, false)
	owner.evaluate_pending()
	return owner.report


func _test_zone(owner: RefCounted, loaded: Dictionary, id: String, bindings: Dictionary, zone: Dictionary, classes: Dictionary) -> void:
	zone_cases += 1
	target_cases += zone.component_ids.size()
	var class_id := _class_id(zone)
	if not classes.has(class_id):
		classes[class_id] = {"zones": 0, "targets": [], "middle_ok": true, "severe_ok": true,
			"archive_middle_ok": true, "archive_severe_ok": true}
	var record: Dictionary = classes[class_id]
	record.zones += 1
	for component: String in zone.component_ids:
		if component not in record.targets:
			record.targets.append(component)
	record.targets.sort()
	var medium := _event(bindings, zone, false)
	var severe := _event(bindings, zone, true)
	var label: String = id + "/" + zone.source + "/" + zone.probe_id
	var valid := not medium.is_empty() and not severe.is_empty() and Events.validate_events([medium], 1, bindings) and Events.validate_events([severe], 1, bindings)
	check(label + " actual serializers accept both samples", valid)
	if not valid:
		record.middle_ok = false
		record.severe_ok = false
		return
	if zone.source == "propeller":
		_test_propeller(owner, loaded, id, bindings, medium, severe, record)
		return
	var response_ok := true
	var service := 0
	for component: String in zone.component_ids:
		var rule: Dictionary = zone.component_responses.get(component, zone.response)
		response_ok = response_ok and rule.get("kind") == "channel_bands" and rule.get("middle_action") == "repair" \
			and rule.get("channel") in ["depth_m", "contact_normal_proxy_mps", "compression_ratio"]
		service += int(rule.get("service_minor_by_component", {}).get(component, -1000000))
	var middle_report := _run(owner, loaded, id, bindings, medium)
	record.archive_middle_ok = _archive_round_trip(label + " middle", middle_report) and record.archive_middle_ok
	var middle_ok: bool = response_ok and middle_report.get("complete", false) and middle_report.get("total_minor") == service
	for component: String in zone.component_ids:
		middle_ok = middle_ok and owner._assessment.components.get(component, {}).get("disposition") == "repair"
	check(label + " middle scoped services sum independently", middle_ok, {"expected": service, "total": middle_report.get("total_minor"), "unresolved": middle_report.get("unresolved"), "decisions": owner._assessment.components})
	var severe_report := _run(owner, loaded, id, bindings, severe)
	record.archive_severe_ok = _archive_round_trip(label + " severe", severe_report) and record.archive_severe_ok
	var expected := _expected_purchase(loaded, zone.component_ids)
	var severe_ok: bool = severe_report.get("complete", false) and severe_report.get("total_minor") == expected
	for component: String in zone.component_ids:
		severe_ok = severe_ok and owner._assessment.components.get(component, {}).get("disposition") == "replace"
	check(label + " severe scoped purchases sum independently", severe_ok, {"expected": expected, "total": severe_report.get("total_minor"), "unresolved": severe_report.get("unresolved"), "decisions": owner._assessment.components})
	record.middle_ok = record.middle_ok and middle_ok
	record.severe_ok = record.severe_ok and severe_ok


## At most three single-unit zone targets are current; enumerate declared package
## covers independently and assign remaining units their authored individual prices.
func _expected_purchase(loaded: Dictionary, ids: Array) -> int:
	var n := ids.size()
	var best := []
	best.resize(1 << n)
	best.fill(9000000000000000)
	best[0] = 0
	for mask in range(1 << n):
		for i in n:
			if (mask & (1 << i)) == 0:
				var next := mask | (1 << i)
				best[next] = mini(best[next], int(best[mask]) + int(_part(loaded.dossier, ids[i]).unit_minor))
		for package: Dictionary in loaded.package_book.packages:
			if package.available != true or package.compatible != true or typeof(package.cost_cents) != TYPE_INT:
				continue
			var covered := 0
			for i in n:
				if int(package.component_quantities.get(ids[i], 0)) >= 1:
					covered |= 1 << i
			if covered != 0 and (covered & mask) == 0:
				best[mask | covered] = mini(best[mask | covered], int(best[mask]) + int(package.cost_cents))
	return int(best[(1 << n) - 1])


func _test_propeller(owner: RefCounted, loaded: Dictionary, id: String, bindings: Dictionary, medium: Dictionary, severe: Dictionary, record: Dictionary) -> void:
	var prop: String = loaded.dossier.propeller_component_id
	var expected: int = int(_part(loaded.dossier, prop).unit_minor)
	for follow: Dictionary in loaded.damage_profile.propeller_followups:
		follow_cases += 1
		expected += int(follow.service_minor)
	var middle_report := _run(owner, loaded, id, bindings, medium)
	record.archive_middle_ok = _archive_round_trip(id + " prop middle", middle_report) and record.archive_middle_ok
	var middle_ok: bool = middle_report.get("complete", false) and middle_report.get("total_minor") == expected \
		and owner._assessment.components.get(prop, {}).get("disposition") == "replace"
	for follow: Dictionary in loaded.damage_profile.propeller_followups:
		var row: Dictionary = owner._assessment.components.get(follow.component_id, {})
		middle_ok = middle_ok and row.get("disposition") == "repair" and row.get("repair_minor") == follow.service_minor
		if int(_part(loaded.dossier, follow.component_id).quantity) > 1:
			middle_ok = middle_ok and str(middle_report.game_assessment.current_outcomes[follow.component_id].quantity_scope).contains("count is unknown")
	check(id + " prop strike sums priced blade plus each whole-group service", middle_ok, {"expected": expected, "total": middle_report.get("total_minor"), "unresolved": middle_report.get("unresolved"), "decisions": owner._assessment.components})
	var severe_report := _run(owner, loaded, id, bindings, severe)
	record.archive_severe_ok = _archive_round_trip(id + " prop severe", severe_report) and record.archive_severe_ok
	var uncertain := false
	var severe_ids := [prop]
	var severe_ok: bool = owner._assessment.components.get(prop, {}).get("disposition") == "replace"
	for follow: Dictionary in loaded.damage_profile.propeller_followups:
		var grouped: bool = int(_part(loaded.dossier, follow.component_id).quantity) > 1
		var disposition: Variant = owner._assessment.components.get(follow.component_id, {}).get("disposition")
		severe_ok = severe_ok and disposition == ("inspect" if grouped else "replace")
		if grouped:
			uncertain = true
			# An unknown affected quantity cannot appear as purchased required units.
			for line: Dictionary in severe_report.get("lines", []):
				for allocated: String in line.get("allocated_ids", []):
					severe_ok = severe_ok and not allocated.begins_with(follow.component_id + ":")
		else:
			severe_ids.append(follow.component_id)
	if uncertain:
		severe_ok = severe_ok and severe_report.get("total_minor") == null and str(severe_report.get("unresolved", [])).contains("quantity-specific")
	else:
		severe_ok = severe_ok and severe_report.get("complete", false) and severe_report.get("total_minor") == _expected_purchase(loaded, severe_ids)
	check(id + " severe prop scope preserves grouped count uncertainty", severe_ok, {"total": severe_report.get("total_minor"), "unresolved": severe_report.get("unresolved"), "decisions": owner._assessment.components})
	record.middle_ok = record.middle_ok and middle_ok
	record.severe_ok = record.severe_ok and severe_ok


func _archive_round_trip(label: String, report: Dictionary) -> bool:
	var encoded := ReportArchive.encode(report)
	var decoded := ReportArchive.decode(encoded.text) if encoded.get("ok", false) else {"ok": false, "errors": encoded.get("errors", [])}
	var same: bool = decoded.get("ok", false) and decoded.get("report") == JSON.parse_string(JSON.stringify(report, "", true, true))
	check(label + " current archive codec round trip", same, {"encode": encoded.get("errors"), "decode": decoded.get("errors")})
	return same


func _test_missing_channels(owner: RefCounted, loaded: Dictionary, id: String, bindings: Dictionary) -> void:
	for zone: Dictionary in loaded.damage_profile.zones:
		if zone.source == "hull" and zone.response.get("channel") == "contact_normal_proxy_mps":
			var event := _event(bindings, zone, false, true)
			var report := _run(owner, loaded, id, bindings, event)
			_archive_round_trip(id + " missing channel", report)
			var missing_ok: bool = report.get("total_minor") == null and not report.get("complete", true) and report.get("contact_coverage_incomplete", false)
			for component: String in zone.component_ids:
				missing_ok = missing_ok and owner._assessment.components.get(component, {}).get("disposition") == "inspect"
			check(id + " absent required normal channel remains unresolved", missing_ok)
			return


func _test_missing_price_controls() -> void:
	var id := "jensen-das-ugly-stik-60"
	var original := Catalog.load_for(id)
	var physical := Aircraft.load_file(Routes.entry(id).data)
	var bindings := Contract.describe(physical.model, true)
	var owner := Incident.new()
	for spec: Array in [["wing", "airframe_wing", "hull/depth_m"], ["gear", "gear_main", "gear/compression_ratio"]]:
		var missing: Dictionary = original.duplicate(true)
		var part := _part(missing.dossier, spec[1])
		part.unit_minor = null
		part.low_unit_minor = null
		part.high_unit_minor = null
		var coverage := _coverage(missing, ESSENTIAL[id])
		var changed_fleet := coverage_by_route.duplicate(true)
		changed_fleet[id] = coverage
		check("missing " + spec[0] + " price fails class, route and fleet coverage", not coverage.ok \
			and coverage.groups[spec[0]].missing_price == [spec[1]] and coverage.classes[spec[2]].missing_price == [spec[1]] \
			and not _fleet_ok(changed_fleet))
		# A deliberately narrow strike scope may still be priced; it is not a fleet-coverage pass.
		var event := Events.strike_event({"tick": 1, "rpm": 4000.0,
			"point_ned": PackedFloat64Array([0, 0, 0]), "velocity_ned": PackedFloat64Array([5, 0, 0])}, 1, Hull.law(), bindings)
		var preview := _run(owner, missing, id, bindings, event)
		_archive_round_trip(id + " missing " + spec[0] + " price preview", preview)
		check("missing " + spec[0] + " price does not fabricate prop-only uncertainty", preview.get("complete", false) and preview.get("total_minor") == 539)


func _test_avanti_component_rules() -> void:
	var id := "sebart-avanti-s-a200-p100rx"
	var loaded := Catalog.load_for(id)
	var physical := Aircraft.load_file(Routes.entry(id).data)
	var bindings := Contract.describe(physical.model, true)
	var index := _index(bindings, "hull_probes", "probe_belly_station_plus_six")
	var owner := Incident.new()
	var cases := []
	# Independently specified policy bands: 3 leaves both turbine targets clear;
	# 20 replaces the structure, 37 also replaces the turbine, and 42 replaces all.
	for spec: Array in [[3.0, 2500, "repair", "scope_clear", "scope_clear"],
		[20.0, 148000, "replace", "repair", "repair"], [37.0, 420000, "replace", "replace", "repair"],
		[42.0, 458000, "replace", "replace", "replace"]]:
		var serialized := Events.hull_events([{"index": index, "new": true, "depth_m": 0.014,
			"normal_speed_mps": spec[0]}], bindings, PackedStringArray(), 1)
		var event: Dictionary = serialized.events[0] if serialized.get("ok", false) and not serialized.events.is_empty() else {}
		var report := _run(owner, loaded, id, bindings, event)
		_archive_round_trip("Avanti %.1f" % spec[0], report)
		var outcomes: Dictionary = report.get("game_assessment", {}).get("current_outcomes", {})
		var ok: bool = not event.is_empty() and report.get("complete", false) and report.get("total_minor") == spec[1]
		for item: Array in [["airframe_fuselage", spec[2]], ["engine_main", spec[3]], ["turbine_accessories", spec[4]]]:
			ok = ok and outcomes.get(item[0], {}).get("action") == item[1]
		cases.append({"normal_speed_mps": spec[0], "expected_total_minor": spec[1], "actions": [spec[2], spec[3], spec[4]], "passed": ok})
		check("Avanti independent component bands at %.1f m/s" % spec[0], ok, {"expected": spec, "total": report.get("total_minor"), "outcomes": outcomes})
	ledger.routes[id]["independent_component_cases"] = cases
