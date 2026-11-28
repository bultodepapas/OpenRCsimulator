## F1: DamageAssessment.resolve with a prepared zone index answers exactly as its zone search.
## - Every stock aircraft's damage profile: events for each zone's source and probe (support, hull and impact events in
##   every lifecycle and response, with random measures) and for unknown probes resolve to identical bytes.
## - A repeated (source, probe) pair resolves to its first zone on both paths; a profile with a non-String zone source
##   gets no index (the search runs).
## - The ledger builds its index once per profile and rebuilds it for another profile.
extends SceneTree

const Incident := preload("res://economy/incident.gd")
const DamageAssessment := preload("res://economy/damage_assessment.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flight := preload("res://sim/flight_session.gd")

var checks := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)


func _events(profile: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var pairs: Array = []
	for zone: Dictionary in profile.get("zones", []):
		pairs.append([zone.source, zone.probe_id])
	pairs.append(["gear", "no_such_probe"])
	pairs.append(["propeller", "rotor_unknown"])
	for pair: Array in pairs:
		for event_type: String in ["support_contact", "hull_contact", "impact"]:
			for lifecycle: String in ["new", "persistent", "ended"]:
				for response: String in ["contact", "terminal"]:
					out.append({source = pair[0], contact_id = pair[1], event_type = event_type, lifecycle = lifecycle,
						response = response, tick = 40, measure = {compression_m = rng.randf_range(0.0, 0.2),
						normal_speed_mps = rng.randf_range(0.0, 12.0), depth_m = rng.randf_range(0.0, 0.1),
						slide_speed_mps = rng.randf_range(0.0, 30.0), travel_limit_m = 0.1}})
	return out


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6063
	var profiles := 0
	var compared := 0
	var mismatched := 0
	var matched := 0
	var last_profile: Dictionary = {}
	for id: String in Catalog.ids():
		if not Catalog.can_fly(id):
			continue
		var session: Node = Flight.new()
		session.setup(Catalog.data_for(id, Catalog.default_battery_mode(id)), id)
		var ledger := Incident.new()
		ledger.begin(id, str(session.aircraft.get("input_identity", {}).get("sha256", "")))
		session.free()
		var profile: Dictionary = ledger._damage_profile
		if profile.is_empty():
			continue
		profiles += 1
		var index: Dictionary = DamageAssessment.zone_index(profile)
		check("%s: a validated profile gets an index" % id, not index.is_empty())
		for event: Dictionary in _events(profile, rng):
			var searched: Dictionary = DamageAssessment.resolve(profile, event)
			var indexed: Dictionary = DamageAssessment.resolve(profile, event, index)
			compared += 1
			matched += int(searched.get("matched", false))
			if var_to_bytes(searched) != var_to_bytes(indexed):
				mismatched += 1
		# The ledger's own path builds the index once per profile instance.
		var event: Dictionary = _events(profile, rng)[0]
		ledger._resolve_damage(event)
		var built: Dictionary = ledger._damage_zones
		ledger._resolve_damage(event)
		check("%s: the ledger keeps its index for the same profile" % id, is_same(built, ledger._damage_zones)
			and is_same(ledger._damage_zones_profile, ledger._damage_profile))
		last_profile = profile
	check("indexed and searched resolutions are identical (%d events, %d profiles, %d matched)" % [compared, profiles,
		matched], mismatched == 0 and profiles >= 3 and matched > 100 and compared - matched > 100, str(mismatched))
	# A repeated pair resolves to its first zone on both paths.
	var doubled: Dictionary = last_profile.duplicate(true)
	var first_zone: Dictionary = doubled.zones[0]
	var copy: Dictionary = first_zone.duplicate(true)
	copy.response = {kind = "replace_on_impact"}
	copy.erase("component_responses")
	doubled.zones.append(copy)
	var probe := {source = first_zone.source, contact_id = first_zone.probe_id, event_type = "impact", lifecycle = "new",
		response = "contact", tick = 40, measure = {normal_speed_mps = 0.1}}
	check("a repeated source and probe resolves to the first zone on both paths",
		var_to_bytes(DamageAssessment.resolve(doubled, probe)) == var_to_bytes(DamageAssessment.resolve(doubled, probe,
		DamageAssessment.zone_index(doubled))))
	var odd: Dictionary = last_profile.duplicate(true)
	odd.zones[0].source = &"gear"
	check("a non-String zone source gets no index", DamageAssessment.zone_index(odd).is_empty())
	# Another profile instance rebuilds the ledger's index.
	var ledger := Incident.new()
	ledger._damage_profile = last_profile
	ledger._resolve_damage(probe)
	var first_index: Dictionary = ledger._damage_zones
	ledger._damage_profile = doubled
	ledger._resolve_damage(probe)
	check("another profile instance rebuilds the index", not is_same(first_index, ledger._damage_zones)
		and is_same(ledger._damage_zones_profile, doubled))
	print("damage zone index: %d checks, %d failed" % [checks, failed])
	quit(1 if failed > 0 or checks == 0 else 0)
