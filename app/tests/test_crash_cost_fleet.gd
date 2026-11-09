extends SceneTree
## Constructed accepted observations through real serializers and the automatic profile owner.
## These fixtures establish software scope, not physical or desktop fleet qualification.
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
	var route_count := 0
	for id: String in Routes.ids():
		if id == "xcell-60-research":
			continue
		route_count += 1
		var loaded := Catalog.load_for(id)
		var physical := Aircraft.load_file(Routes.entry(id).data)
		_check(id + " inventory and profile", loaded.ok and physical.ok)
		var bindings := Contract.describe(physical.model, true)
		var owner := Incident.new()
		owner.begin_with_catalog(loaded, id, loaded.dossier.source_sha256)
		var selected := {}
		for zone: Dictionary in loaded.damage_profile.zones:
			if zone.source == "hull" and zone.response.get("terminal_replace", false):
				selected = zone
				break
		_check(id + " mapped local structure fixture", not selected.is_empty())
		if selected.is_empty():
			continue
		var index := -1
		for i in bindings.hull_probes.size():
			if bindings.hull_probes[i].id == selected.probe_id:
				index = i
		var state := RB.make_state(M.v3(0, 0, 0), M.v3(10, 0, 2), M.q_identity(), M.v3(0, 0, 0))
		var impact := Impact.hull_point(state, 1, physical.model.crash_hull, index, state, "impact")
		var event := Events.impact_event(impact, bindings, Hull.law())
		owner.observe(_snapshot(1, [event]), bindings, true)
		owner.evaluate_pending()
		_check(id + " automatic local bill", owner.report.get("complete", false) and owner.report.get("total_minor", 0) > 0 and owner.report.get("errors", []).is_empty())
		if not bindings.support_points.is_empty():
			var gear := Incident.new()
			gear.begin_with_catalog(loaded, id, loaded.dossier.source_sha256)
			gear.observe(_snapshot(1, [Events.support_event(0, .01, 0.0, .1, 1, bindings)]), bindings, false)
			gear.evaluate_pending()
			_check(id + " ordinary gear is quiet", not gear.has_damage())
			gear.observe(_snapshot(2, [Events.support_event(0, .11, .01, .1, 2, bindings)]), bindings, false)
			gear.evaluate_pending()
			_check(id + " local gear proxy has numeric bill", gear.report.get("known_subtotal_minor", 0) > 0 and gear.report.get("errors", []).is_empty())
		else:
			_check(id + " explicit gearless fixture", id == "moonrunner-x99")
		var prop_id: String = loaded.dossier.propeller_component_id
		if prop_id.is_empty():
			_check(id + " explicit no-propeller installation", bindings.get("rotor_disc", {}).is_empty())
		else:
			var prop := Incident.new()
			prop.begin_with_catalog(loaded, id, loaded.dossier.source_sha256)
			var strike := {"tick": 1, "rpm": 1000.0, "point_ned": M.v3(0, 0, 0), "velocity_ned": M.v3(10, 0, 0)}
			prop.observe(_snapshot(1, [Events.strike_event(strike, 1, Hull.law(), bindings)]), bindings, false)
			prop.evaluate_pending()
			_check(id + " prop bill with explicit pending scope", prop.report.get("known_subtotal_minor", 0) > 0 and prop.report.get("errors", []).is_empty())
	_check("all eleven fixed-wing configurations exercised", route_count == 11)
	print("crash cost fleet: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _snapshot(tick: int, events: Array) -> Dictionary:
	return {format = "openrc-aircraft-contact-state v1", tick = tick, events = events,
		active_hull_ids = PackedStringArray(), prop_strike = {}}


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL " + label)
