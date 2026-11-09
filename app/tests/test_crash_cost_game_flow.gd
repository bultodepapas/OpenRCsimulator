extends SceneTree
## Constructed accepted-observation game-policy matrix. No final dispositions are injected.
const Catalog := preload("res://economy/catalog.gd")
const Incident := preload("res://economy/incident.gd")
const Aircraft := preload("res://physics/aircraft_data.gd")
const Routes := preload("res://app_state/aircraft_catalog.gd")
const Contract := preload("res://physics/aircraft_contact_contract.gd")
const Events := preload("res://sim/aircraft_contact_events.gd")
const Impact := preload("res://physics/impact_snapshot.gd")
const Hull := preload("res://physics/hull_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	var count := 0
	for id: String in Routes.ids():
		if id == "xcell-60-research": continue
		count += 1
		var loaded := Catalog.load_for(id)
		var physical := Aircraft.load_file(Routes.entry(id).data)
		check(id + " admitted", loaded.ok and physical.ok)
		if not loaded.ok or not physical.ok: continue
		var bindings := Contract.describe(physical.model, true)
		var zone: Dictionary = {}
		for candidate: Dictionary in loaded.damage_profile.zones:
			if candidate.source == "hull" and candidate.component_ids.size() == 1 and candidate.response.get("terminal_replace", false):
				if zone.is_empty(): zone = candidate
				if not loaded.package_book.packages.is_empty() and loaded.package_book.packages[0].component_quantities.has(candidate.component_ids[0]):
					zone = candidate
					break
		check(id + " local primary region exists", not zone.is_empty())
		if zone.is_empty(): continue
		var index := _index(bindings, zone.probe_id)
		var cash: int = int(zone.response.service_minor_by_component[zone.component_ids[0]])
		var owner := _owner(loaded, id)
		owner.observe(_packet(1, [_hull(bindings, index, 1, .001, false)]), bindings, false)
		owner.evaluate_pending()
		check(id + " quiet local contact", not owner.has_damage())
		owner.observe(_packet(2, [_hull(bindings, index, 2, .014, true)]), bindings, false)
		owner.evaluate_pending()
		check(id + " automatic local service cash", owner.report.get("complete", false) and owner.report.get("total_minor") == cash)
		owner.observe(_packet(3, [_hull(bindings, index, 3, .014, true)]), bindings, false)
		owner.evaluate_pending()
		check(id + " persistent same band stays resolved once", owner.report.get("complete", false) and owner.report.get("total_minor") == cash)
		var minutes: int = int(loaded.labor_policy.minutes_by_component[zone.component_ids[0]]) + int(loaded.labor_policy.shared_setup_minutes)
		var paid: Dictionary = owner.set_costing_mode("paid")
		check(id + " normal shop option reconciles one setup", paid.get("ok", false) and owner.report.get("complete", false) and owner.report.get("total_minor") == cash + minutes * 75)
		var prior: Dictionary = owner.report.duplicate(true)
		owner.set_costing_mode("paid")
		check(id + " repeated option cannot rebill", owner.report.get("total_minor") == prior.get("total_minor"))
		owner.set_costing_mode("diy")
		check(id + " DIY round trip returns original cash", owner.report.get("total_minor") == cash)
		var replacement := _owner(loaded, id)
		var state := RB.make_state(M.v3(0, 0, 0), M.v3(10, 0, 2), M.q_identity(), M.v3(0, 0, 0))
		var impact := Impact.hull_point(state, 1, physical.model.crash_hull, index, state, "impact")
		replacement.observe(_packet(1, [Events.impact_event(impact, bindings, Hull.law())]), bindings, true)
		replacement.evaluate_pending()
		check(id + " terminal local purchase is numeric", replacement.report.get("complete", false) and replacement.report.get("total_minor", 0) > 0)
		check(id + " selected purchase rows reconcile", _sum(replacement.report) == replacement.report.get("total_minor"))
		if not loaded.package_book.packages.is_empty():
			var option: Dictionary = replacement.set_purchase_package(loaded.package_book.packages[0].id)
			check(id + " normal trusted package option works", option.get("ok", false) and replacement.report.get("complete", false))
			check(id + " package allocation and extras disclosed", _has_purchase_scope(replacement.report))
			replacement.set_purchase_package("")
			check(id + " recommended recovery is available", replacement.report.get("purchase_package_id", "") == "" and replacement.report.get("complete", false))
		var prop_id: String = loaded.dossier.propeller_component_id
		if prop_id.is_empty():
			check(id + " no fabricated propeller", bindings.get("rotor_disc", {}).is_empty())
		else:
			var prop := _owner(loaded, id)
			var strike := {"tick": 1, "rpm": 4000.0, "point_ned": M.v3(0, 0, 0), "velocity_ned": M.v3(10, 0, 0)}
			prop.observe(_packet(1, [Events.strike_event(strike, 1, Hull.law(), bindings)]), bindings, false)
			prop.evaluate_pending()
			var price := _price(loaded.dossier, prop_id)
			check(id + " gentle prop checks resolve automatically", prop.report.get("complete", false) and prop.report.get("total_minor") == price)
			var medium := _owner(loaded, id)
			strike.velocity_ned = M.v3(20, 0, 0)
			strike.rpm = 9000.0
			medium.observe(_packet(1, [Events.strike_event(strike, 1, Hull.law(), bindings)]), bindings, false)
			medium.evaluate_pending()
			var services := 0
			for follow: Dictionary in loaded.damage_profile.propeller_followups: services += int(follow.service_minor)
			check(id + " medium prop service scope reconciles", medium.report.get("complete", false) and medium.report.get("total_minor") == price + services)
	check("all fixed-wing routes enumerated", count == 11)
	print("game flow: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _owner(loaded: Dictionary, id: String) -> RefCounted:
	var owner := Incident.new()
	owner.begin_with_catalog(loaded, id, loaded.dossier.source_sha256)
	return owner


func _hull(bindings: Dictionary, index: int, tick: int, depth: float, persistent: bool) -> Dictionary:
	var prior := PackedStringArray([bindings.hull_probes[index].id]) if persistent else PackedStringArray()
	var record := {"index": index, "new": not persistent, "depth_m": depth, "normal_speed_mps": 2.0,
		"slide_speed_mps": 3.0, "point_ned": M.v3(0, 0, depth), "velocity_ned": M.v3(3, 0, 2)}
	var serialized := Events.hull_events([record], bindings, prior, tick)
	return serialized.events[0] if serialized.ok and not serialized.events.is_empty() else {}


func _packet(tick: int, events: Array) -> Dictionary:
	return {format = "openrc-aircraft-contact-state v1", tick = tick, events = events, active_hull_ids = PackedStringArray(), prop_strike = {}}


func _index(bindings: Dictionary, id: String) -> int:
	for i in bindings.hull_probes.size():
		if bindings.hull_probes[i].id == id: return i
	return -1


func _price(dossier: Dictionary, id: String) -> int:
	for part: Dictionary in dossier.components:
		if part.id == id: return int(part.unit_minor)
	return -1


func _sum(report: Dictionary) -> int:
	var out := 0
	for line: Dictionary in report.get("lines", []):
		if line.get("amount_minor") != null: out += int(line.amount_minor)
	return out


func _has_purchase_scope(report: Dictionary) -> bool:
	for line: Dictionary in report.get("lines", []):
		if line.get("action") == "selected_purchase" and not line.get("surplus_ids", []).is_empty(): return true
	return false


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + label)
