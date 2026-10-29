## Optional synthetic role authoring over actual existing hull physics. No stock
## calibration/eligibility claim; role metadata must not change any physical byte.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Contacts := preload("res://physics/aircraft_contact_contract.gd")
const Profiles := preload("res://statistics/profiles.gd")
const Adapter := preload("res://statistics/fixed_wing_adapter.gd")
const Service := preload("res://statistics/service.gd")
const Role := preload("res://physics/intended_hull_support.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const X8 := "res://data/aircraft/moonrunner_x99.json"
const ID := "moonrunner-x99"
var checks := 0
var failed := 0

class PacketOwner extends Node:
	var sim := {tick = 1}
	var statistics_generation := 0
	var value := {}
	func hull_support_observation() -> Dictionary: return value


func _initialize() -> void:
	# Hash the actual loaded scripts, so concurrent workspace edits cannot turn
	# a later file hash into a claim about the code used by this session receipt.
	var loaded_sources := {}
	for script: Script in [Session, Data, Contacts, Profiles, Adapter, Role, get_script()]:
		loaded_sources[script.resource_path] = script.get_source_code().sha256_text()
	print("GP14_LOADED_SOURCES ", JSON.stringify(loaded_sources, "", true))
	_bindings()
	_actual_contacts()
	_refusals()
	_absence_baseline()
	print("Intended hull support sessions: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label, " ", detail)


func quantity(number: float, unit: String) -> Dictionary:
	return {value = number, unit = unit, kind = "estimated", source = "synthetic optional observation fixture only; no stock calibration"}


func source(allowed := PackedStringArray()) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(X8))
	var ids: Array = Array(allowed) if not allowed.is_empty() else raw.crash_hull_ids.duplicate()
	raw.capabilities.landing_support = "authored_hull_v1"
	raw.intended_hull_support = {format = Role.FORMAT, role = "belly", contact_law = Role.CONTACT_LAW,
		evidence = {kind = "estimated", source = "synthetic broad fixture roles, deliberately not stock X8 authoring"},
		allowed_contact_ids = ids, stop_groups = [[ids[0]]] if not ids.has("probe_belly") else [["probe_belly"]],
		rest_pose = {roll = quantity(0.0, "rad"), pitch = quantity(0.0, "rad")},
		control_envelope = {roll_tolerance = quantity(0.7, "rad"), pitch_tolerance = quantity(0.7, "rad"),
			max_angular_speed = quantity(10.0, "rad/s")}}
	return raw


func player(raw: Dictionary = {}) -> Node:
	var node := Session.new()
	node.input_enabled = false
	node.crash_auto_restart = false
	node.soft_hull_contacts = true
	if raw.is_empty(): node.setup(X8, ID)
	else:
		var path := "user://gp14_role_fixture_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(raw, "", true, true))
		file.close()
		var loaded := Data.load_file(path)
		node.setup(path, ID, loaded)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return node


func body(node: Node, clearance: float, q := PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), sink := 0.0) -> PackedFloat64Array:
	var extent := -INF
	for i: int in range(0, node.aircraft.model.crash_hull.size(), 3):
		extent = maxf(extent, M.q_rotate(q, node.aircraft.model.crash_hull.slice(i, i + 3))[2])
	return RB.make_state(M.v3(0.0, 0.0, -extent - clearance), M.v3(0.0, 0.0, sink), q, M.v3(0.0, 0.0, 0.0))


func install(node: Node, state: PackedFloat64Array) -> bool:
	if not node.sim.reset(state): return false
	node.engine_running = false
	node.sim.continuous[node._rotor_index()] = 0.0
	return true


func _bindings() -> void:
	var loaded := Data.validate_and_derive(source())
	check("synthetic authored source loads", loaded.ok)
	if not loaded.ok: return
	var bindings := Contacts.describe(loaded.model, true)
	var profile := Profiles.resolve(ID, loaded.model, bindings)
	check("valid prepared role is separately bound with zero fake wheels", bindings.ok and bindings.support_points.is_empty()
		and bindings.intended_hull_support.identity == loaded.model.intended_hull_support.identity)
	check("explicit role has derived rest/clearance and authored group", profile.landing_available and profile.rest_height_m > 0
		and profile.main_indices.is_empty() and profile.stop_indices.is_empty() and profile.hull_stop_group_count == 1)
	check("legacy terminal hull policy cannot award soft support credit", not Profiles.resolve(ID, loaded.model, Contacts.describe(loaded.model, false)).landing_available)
	loaded.model.crash_hull[0] += 0.001
	check("changed physical geometry refuses stale prepared role", not Contacts.describe(loaded.model, true).ok)
	check("stale role also disables profile credit", not Profiles.resolve(ID, loaded.model, bindings).landing_available)
	var unopted := Data.load_file(X8)
	check("stock X8 is still unavailable with no invented role", not Profiles.resolve(ID, unopted.model, Contacts.describe(unopted.model, true)).landing_available)


func _actual_contacts() -> void:
	var node := player(source())
	var reference := player()
	check("actual optional and unopted sessions install", node.is_flyable() and reference.is_flyable())
	var state := body(node, 0.35)
	check("identical physical drop initializes", install(node, state) and install(reference, state))
	check("tick zero role packet explicitly unavailable", not node.hull_support_observation().available
		and node.hull_support_observation().reason == "no_current_accepted_hull_tick")
	var service := Service.new()
	service.setup("", false)
	service.begin_activity(node, ID, "Synthetic optional-role X8")
	# Shorten only air-start confirmation for a bounded 35cm physical drop. All
	# contact/stability/stop timers remain the existing product detector defaults.
	var fixture_profile: Dictionary = service.adapter.profile.duplicate(true)
	fixture_profile.rules = {liftoff_clearance_s = 0.02}
	service.detector.configure(fixture_profile, true)
	var found := false
	var detached := true
	var no_physical_change := true
	var zero_airborne_stop := false
	var first := {}
	for i: int in 1200:
		node.sim.step()
		reference.sim.step()
		var physical_before := var_to_bytes(node.sim.checkpoint())
		var packet: Dictionary = node.hull_support_observation()
		var sample: Dictionary = service.adapter.sample()
		if packet.available and not packet.facts.touching: zero_airborne_stop = zero_airborne_stop or not sample.stop_support
		if packet.available and packet.facts.intended_support:
			found = true
			if first.is_empty(): first = {packet = packet.duplicate(true), contacts = node.contact_events(), profile = service.adapter.profile.duplicate(true)}
			packet.facts.intended_support = false
			detached = detached and node.hull_support_observation().facts.intended_support
		no_physical_change = no_physical_change and physical_before == var_to_bytes(node.sim.checkpoint()) \
			and var_to_bytes(node.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint())
	check("accepted real hull contact obtains intended support", found)
	check("empty wheel list never vacuously grants airborne stop", zero_airborne_stop)
	check("all observer/role metadata reads preserve complete physics bytes", no_physical_change)
	check("nested role receipts are detached", detached)
	check("gentle authored support remains nonterminal without gear-up accident", node.crash.is_empty()
		and not node.accident_observation().gear_up_contact and service.query().crashes == 0, str(node.crash))
	check("single existing classifier awards controlled full stop", service.query().full_stops == 1 and service.query().landings == 1, str(service.query()))
	check("historical contact and accident envelopes remain exact", node.contact_events().size() == 5 and node.accident_observation().size() == 8)
	var saved: Dictionary = node.checkpoint()
	var before: Dictionary = node.hull_support_observation()
	check("full session optional-role checkpoint restores", not saved.is_empty() and node.restore_checkpoint(saved))
	check("restored accepted observation facts are exact", before.facts == node.hull_support_observation().facts)
	node.sim.set_paused(false)
	for i: int in 8: node.sim.step()
	var continuation := var_to_bytes(node.sim.checkpoint())
	check("same saved optional-role state restores again", node.restore_checkpoint(saved))
	node.sim.set_paused(false)
	for i: int in 8: node.sim.step()
	check("optional-role continuation replays byte-exact", continuation == var_to_bytes(node.sim.checkpoint()))
	check("trace declares observational policy identity only when authored", node.trace_meta().get("intended_hull_support_identity") == before.identity
		and not reference.trace_meta().has("intended_hull_support_identity"))
	if not first.is_empty(): _packet_contract(first)
	service.end_activity()
	service.close()
	service.free()
	node.free()
	reference.free()
	# Independent accepted physical fixtures probe wrong-pose and incidental IDs.
	for wrong_pose: bool in [false, true]:
		var fixture := player(source(PackedStringArray(["probe_belly"]))) if not wrong_pose else player(source())
		var q := M.q_from_euler(0.0, 0.0, 0.8) if wrong_pose else M.q_identity()
		var adapter := Adapter.new()
		adapter.configure(fixture, ID, Callable())
		check("adversarial contact fixture initializes", install(fixture, body(fixture, -0.001 if wrong_pose else -0.03, q)))
		fixture.sim.step()
		var packet: Dictionary = fixture.hull_support_observation()
		var sample := adapter.sample()
		check("wrong pose or incidental accepted IDs cannot mask incident", packet.available and packet.facts.touching
			and not packet.facts.intended_support and sample.incident and not sample.intended_support, str([wrong_pose, packet]))
		check("adversarial fixture proves mixed or covered-wrong-pose facts", packet.facts.role_coverage == "mixed" if not wrong_pose
			else (packet.facts.role_covered and not packet.facts.pose_within_envelope))
		# Legacy checkpoint contact history may have real active IDs but no event
		# detail. Restore that valid presentation variant at the SAME body state.
		var without_detail: Dictionary = fixture.checkpoint()
		without_detail.contact_state.events = []
		check("same physical contact restores without optional event detail", fixture.restore_checkpoint(without_detail))
		check("active-ID incident survives missing compact event detail", fixture.contact_events().events.is_empty() and adapter.sample().incident)
		fixture.free()


func _packet_contract(captured: Dictionary) -> void:
	var stub := PacketOwner.new()
	stub.sim.tick = captured.packet.tick
	stub.statistics_generation = captured.packet.generation
	var adapter := Adapter.new()
	adapter.session = stub
	adapter.profile = captured.profile
	stub.value = captured.packet.duplicate(true)
	check("strict accepted role packet is consumable", not adapter._hull_support_observation(captured.contacts).is_empty())
	for field: String in captured.packet:
		stub.value = captured.packet.duplicate(true)
		stub.value.erase(field)
		check("missing role envelope field rejected: " + field, adapter._hull_support_observation(captured.contacts).is_empty())
	for mutation: Dictionary in [{version = 2}, {generation = -1}, {tick = 0}, {available = 1}, {identity = "stale"}, {extra = false}]:
		stub.value = captured.packet.duplicate(true)
		stub.value.merge(mutation, true)
		check("malformed/stale role header rejected", adapter._hull_support_observation(captured.contacts).is_empty())
	stub.value = captured.packet.duplicate(true)
	stub.value.facts.pose_within_envelope = false
	check("role-covered wrong-pose packet cannot retain intended truth", adapter._hull_support_observation(captured.contacts).is_empty())
	stub.value = captured.packet.duplicate(true)
	var stale_contacts: Dictionary = captured.contacts.duplicate(true)
	stale_contacts.tick -= 1
	check("role observation cannot attach to stale contact history", adapter._hull_support_observation(stale_contacts).is_empty())
	stub.free()


func _refusals() -> void:
	var node := player(source())
	check("rollback fixture initializes", install(node, body(node, -0.001)))
	var before := var_to_bytes(node.hull_support_observation())
	node.sim.model.post_tick = func(_old, _candidate, _tick): return PackedFloat64Array([NAN])
	node.sim.step()
	check("failed interval publishes no new optional role receipt", node.sim.tick == 0 and not node.sim.fault_reason.is_empty()
		and before == var_to_bytes(node.hull_support_observation()))
	node.free()
	node = player(source())
	var lake := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	check("explicit lake context installs before flight", lake.ok and node.set_lake_context(lake.lake))
	check("lake scope explicitly cannot qualify flat-solid intent", not node.hull_support_observation().available
		and node.hull_support_observation().reason == "intended_hull_support_lake_scope_unavailable"
		and not Profiles.resolve(ID, node.aircraft.model, node.contact_contract()).landing_available)
	node.free()


func _absence_baseline() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--absence-baseline="): continue
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(argument.get_slice("=", 1)))
		for path: String in baseline:
			var loaded := Data.load_file(path)
			check("absence baseline retains same input source: " + path, loaded.ok and loaded.input_identity.sha256 == baseline[path].input_identity,
				str({before = baseline[path].input_identity, current = loaded.input_identity.sha256}))
			for soft: bool in [false, true]:
				var digest := HashingContext.new()
				digest.start(HashingContext.HASH_SHA256)
				digest.update(var_to_bytes(Contacts.describe(loaded.model, soft)))
				check("unopted contact binding bytes unchanged", digest.finish().hex_encode() == baseline[path].modes[str(soft)])
