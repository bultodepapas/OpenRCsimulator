extends SceneTree

const Role := preload("res://physics/intended_hull_support.gd")
const M := preload("res://physics/math3d.gd")
const Hull := preload("res://physics/hull_contact.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
var checks := 0
var failed := 0


func _initialize() -> void:
	_authoring()
	_observations()
	_pose()
	_malformed_queries()
	_stock_unchanged()
	print("Intended hull support: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL ", label)


func quantity(value: float, unit: String) -> Dictionary:
	return {value = value, unit = unit, kind = "estimated", source = "synthetic policy fixture; no stock qualification"}


func raw_fixture() -> Dictionary:
	return {format = Role.FORMAT, role = "belly", contact_law = Role.CONTACT_LAW,
		evidence = {kind = "estimated", source = "synthetic explicit underside role, not a commercial airframe claim"},
		allowed_contact_ids = ["belly_front", "belly_left", "belly_right"],
		stop_groups = [["belly_left", "belly_right"], ["belly_front", "belly_left"]],
		rest_pose = {roll = quantity(0.0, "rad"), pitch = quantity(0.1, "rad")},
		control_envelope = {roll_tolerance = quantity(0.2, "rad"), pitch_tolerance = quantity(0.15, "rad"),
			max_angular_speed = quantity(0.5, "rad/s")}}


func model_fixture() -> Dictionary:
	return {id = "synthetic-gearless", physical_identity = {version = 1, status = "authored",
		hull_ids = PackedStringArray(["belly_front", "belly_left", "belly_right", "wingtip"]), support_ids = PackedStringArray()},
		crash_hull = PackedFloat64Array([0.3, 0.0, 0.1, -0.1, -0.2, 0.12, -0.1, 0.2, 0.12, 0.0, 1.0, 0.0])}


func observe(prepared: Dictionary, ids: PackedStringArray,
		q := PackedFloat64Array(), normal := PackedFloat64Array([0.0, 0.0, -1.0]),
		rate := PackedFloat64Array([0.0, 0.0, 0.0]), law := "", surface := "solid_ground") -> Dictionary:
	var attitude: PackedFloat64Array = q if not q.is_empty() else M.q_from_euler(0.0, 0.1, 0.0)
	return Role.evaluate(prepared, ids, attitude, normal, rate, law if not law.is_empty() else Hull.law(), surface)


func _authoring() -> void:
	var raw := raw_fixture()
	var model := model_fixture()
	var prepared := Role.prepare(raw, model)
	check("synthetic explicit authoring compiles", prepared.ok)
	check("prepared pins existing soft-hull force law", prepared.required_hull_law == Hull.law())
	check("prepared has no independent contact coordinates or physical force parameters", not prepared.has("crash_hull")
		and not prepared.has("stiffness") and not prepared.has("radius"))
	check("same authoring identity deterministic", Role.prepare(raw_fixture(), model_fixture()).identity == prepared.identity)
	check("installation binds current physical owner", Role.matches_model(prepared, model_fixture()))
	var changed := model_fixture()
	changed.crash_hull[2] += 0.001
	check("physical hull-coordinate change changes geometry pin", Role.prepare(raw_fixture(), changed).hull_geometry_identity != prepared.hull_geometry_identity)
	check("hot reload refuses stale geometry binding", not Role.matches_model(prepared, changed))
	changed = model_fixture()
	changed.physical_identity.hull_ids[3] = "tail"
	check("incidental hull-ID change changes geometry pin", Role.prepare(raw_fixture(), changed).hull_geometry_identity != prepared.hull_geometry_identity)
	check("hot reload refuses stale ID binding", not Role.matches_model(prepared, changed))
	var policy := raw_fixture()
	policy.evidence.source = "different declared evidence"
	check("provenance change changes policy identity", Role.prepare(policy, model_fixture()).identity != prepared.identity)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(prepared, "", true, true))
	check("prepared policy roundtrips through full-precision JSON", Role.matches_model(roundtrip, model_fixture())
		and observe(roundtrip, PackedStringArray(["belly_front"])).intended_support)
	raw.allowed_contact_ids.clear()
	model.crash_hull[0] = 999.0
	check("prepared detaches raw and physical owner inputs", observe(prepared, PackedStringArray(["belly_front"])).intended_support)
	for key: String in Role.RAW_KEYS:
		policy = raw_fixture()
		policy.erase(key)
		check("missing authored field rejected: " + key, not Role.prepare(policy, model_fixture()).ok)
	for mutation: Dictionary in [
		{format = "v99"}, {format = 1}, {role = "foam"}, {role = 1}, {contact_law = 1}, {contact_law = "terminal_hull"}, {extra = 1},
		{allowed_contact_ids = []}, {allowed_contact_ids = ["missing"]},
		{allowed_contact_ids = ["belly_front", "belly_front"]}, {allowed_contact_ids = ["bad/id"]},
		{stop_groups = []}, {stop_groups = [[]]}, {stop_groups = [["wingtip"]]},
		{stop_groups = [["belly_left", "belly_right"], ["belly_right", "belly_left"]]},
		{evidence = {kind = "guessed", source = "fixture"}}, {evidence = {kind = "estimated", source = " "}},
		{rest_pose = {roll = quantity(0.0, "rad")}},
		{control_envelope = {roll_tolerance = quantity(0.2, "rad"), pitch_tolerance = quantity(0.1, "rad")}}
	]:
		policy = raw_fixture()
		policy.merge(mutation, true)
		check("malformed role authoring rejected: " + str(mutation), not Role.prepare(policy, model_fixture()).ok)
	for field: String in ["roll", "pitch"]:
		for number: float in [NAN, INF, PI]:
			policy = raw_fixture()
			policy.rest_pose[field].value = number
			check("finite bounded rest pose required", not Role.prepare(policy, model_fixture()).ok)
	for quantity_key: String in ["value", "unit", "kind", "source"]:
		policy = raw_fixture()
		policy.rest_pose.roll.erase(quantity_key)
		check("complete quantity evidence required: " + quantity_key, not Role.prepare(policy, model_fixture()).ok)
	for malformed: Variant in [0.0, "0", true, [], {value = 0.0, unit = "deg", kind = "estimated", source = "fixture"}]:
		policy = raw_fixture()
		policy.rest_pose.roll = malformed
		check("wrong dimensional/type rest quantity rejected", not Role.prepare(policy, model_fixture()).ok)
	for number: float in [0.0, -0.1, NAN, 1.0e6]:
		policy = raw_fixture()
		policy.control_envelope.roll_tolerance.value = number
		check("finite positive supported envelope required", not Role.prepare(policy, model_fixture()).ok)
	for field: String in ["id", "physical_identity", "crash_hull"]:
		changed = model_fixture()
		changed.erase(field)
		check("missing normalized owner field refused: " + field, not Role.prepare(raw_fixture(), changed).ok)
	for mutation: Dictionary in [{landing_gear = {contacts = [1]}}, {landing_gear = false}, {crash_hull = [0, 0, 0]},
		{physical_identity = {version = 1, status = "authored", hull_ids = PackedStringArray(["belly_front"]), support_ids = []}}]:
		changed = model_fixture()
		changed.merge(mutation, true)
		check("malformed/unsupported owner refused", not Role.prepare(raw_fixture(), changed).ok)
	changed = model_fixture()
	changed.physical_identity.support_ids = PackedStringArray(["wheel"])
	check("installed wheel identity refused in initial gearless domain", not Role.prepare(raw_fixture(), changed).ok)
	changed = model_fixture()
	changed.crash_hull[0] = NAN
	check("nonfinite existing geometry refused", not Role.prepare(raw_fixture(), changed).ok)
	for key: String in ["version", "status", "support_ids"]:
		changed = model_fixture()
		changed.physical_identity[key] = false
		check("wrong physical identity primitive rejected: " + key, not Role.prepare(raw_fixture(), changed).ok)
	policy = raw_fixture()
	policy.stop_groups = []
	for i: int in 17: policy.stop_groups.append(["belly_front"])
	check("stop-group count is bounded before compilation", not Role.prepare(policy, model_fixture()).ok)
	policy = raw_fixture()
	policy.evidence.source = "x".repeat(2049)
	check("provenance text is bounded", not Role.prepare(policy, model_fixture()).ok)


func _observations() -> void:
	var prepared := Role.prepare(raw_fixture(), model_fixture())
	var empty := observe(prepared, PackedStringArray())
	check("no contact never becomes intended support or stop", empty.ok and not empty.touching
		and not empty.intended_support and not empty.stop_support and empty.role_coverage == "empty")
	var first := observe(prepared, PackedStringArray(["belly_front"]))
	check("one accepted allowed contact is intended support", first.ok and first.touching and first.intended_support
		and first.role_coverage == "intended_only" and not first.stop_support and first.controlled)
	for ids: PackedStringArray in [PackedStringArray(["belly_left", "belly_right"]), PackedStringArray(["belly_front", "belly_left"])]:
		check("either all-of authored stop group satisfies support geometry", observe(prepared, ids).stop_support)
	var mixed := observe(prepared, PackedStringArray(["belly_left", "belly_right", "wingtip"]))
	check("mixed intended and wingtip contact is never globally exempt", mixed.ok and mixed.touching
		and not mixed.intended_support and not mixed.stop_support and mixed.role_coverage == "mixed")
	check("mixed contacts retain pose and physical evidence", mixed.controlled and mixed.matched_stop_group_index == 0
		and mixed.intended_contact_ids.size() == 2 and mixed.incidental_contact_ids == PackedStringArray(["wingtip"]))
	var incidental := observe(prepared, PackedStringArray(["wingtip"]))
	check("known incidental hull remains real contact but not intended", incidental.touching and not incidental.intended_support
		and incidental.role_coverage == "incidental_only")
	var reordered := observe(prepared, PackedStringArray(["belly_right", "belly_left"]))
	check("stop membership independent of contact iteration order", reordered.stop_support and reordered.matched_stop_group_index == 0)
	check("same pure query repeat byte-identical", var_to_bytes(reordered) == var_to_bytes(observe(prepared, PackedStringArray(["belly_right", "belly_left"]))))
	check("observation has no crash/landing outcome or timers", not first.has("crash") and not first.has("landing_success") and not first.has("dt"))


func _pose() -> void:
	var prepared := Role.prepare(raw_fixture(), model_fixture())
	var ids := PackedStringArray(["belly_left", "belly_right"])
	for yaw: float in [-PI, -1.3, 0.0, 2.2, PI]:
		var q := M.q_from_euler(yaw, 0.1, 0.0)
		var result := observe(prepared, ids, q)
		check("flat-field rest pose yaw invariant", result.controlled and absf(result.pose_facts.pitch_rad - 0.1) < 1.0e-14)
		var opposite_q := q.duplicate()
		for i: int in 4: opposite_q[i] = -opposite_q[i]
		var sign_flipped := observe(prepared, ids, opposite_q)
		check("quaternion sign invariant", result.controlled == sign_flipped.controlled
			and result.intended_support == sign_flipped.intended_support and result.stop_support == sign_flipped.stop_support
			and absf(result.pose_facts.roll_rad - sign_flipped.pose_facts.roll_rad) < 1.0e-14
			and absf(result.pose_facts.pitch_rad - sign_flipped.pose_facts.pitch_rad) < 1.0e-14)
	# Independent yaw-independent slope frame: q = slope rotation * local heading * authored rest.
	# normal = slope rotation * up. Composition cancels the slope and heading in body normal.
	for slope: float in [-0.5, 0.3]:
		var terrain := M.q_from_axis_angle(PackedFloat64Array([0.0, 1.0, 0.0]), slope)
		var normal := PackedFloat64Array([-M.sin_(slope), 0.0, -M.cos_(slope)])
		for yaw: float in [-1.0, 0.0, 2.0]:
			var q := M.q_mul(terrain, M.q_from_euler(yaw, 0.1, 0.0))
			var result := observe(prepared, ids, q, normal)
			check("normalized slope normal and local heading preserve rest pose", result.controlled
				and absf(result.pose_facts.pitch_rad - 0.1) < 1.0e-14 and absf(result.pose_facts.roll_rad) < 1.0e-14)
	for angles: PackedFloat64Array in [PackedFloat64Array([0.0, 0.1, 0.21]), PackedFloat64Array([0.0, 0.26, 0.0]),
		PackedFloat64Array([0.0, 0.1, PI])]:
		var result := observe(prepared, ids, M.q_from_euler(angles[0], angles[1], angles[2]))
		check("wrong-pose contact retains role facts but cannot mask an incident", not result.controlled
			and result.role_covered and not result.intended_support and not result.stop_support and result.touching
			and result.intended_contact_ids == ids and not result.pose_within_envelope)
	var fast := observe(prepared, ids, PackedFloat64Array(), PackedFloat64Array([0.0, 0.0, -1.0]), PackedFloat64Array([0.3, 0.4, 0.01]))
	check("full body-rate norm gates control independently of pose", not fast.controlled and fast.pose_within_envelope and fast.intended_support)
	var tilted_raw := raw_fixture()
	tilted_raw.rest_pose.roll.value = 0.12
	tilted_raw.rest_pose.pitch.value = -0.05
	var tilted := Role.prepare(tilted_raw, model_fixture())
	var aligned := observe(tilted, ids, M.q_from_euler(0.8, -0.05, 0.12))
	check("authored nonzero roll/pitch recovered with correct FRD signs", aligned.controlled
		and absf(aligned.pose_facts.roll_error_rad) < 1.0e-14 and absf(aligned.pose_facts.pitch_error_rad) < 1.0e-14)


func _malformed_queries() -> void:
	var prepared := Role.prepare(raw_fixture(), model_fixture())
	for ids: PackedStringArray in [PackedStringArray(["missing"]), PackedStringArray(["belly_front", "belly_front"])]:
		check("unknown or duplicate accepted IDs fail closed", not observe(prepared, ids).ok)
	for normal: PackedFloat64Array in [PackedFloat64Array([0.0, 0.0, -2.0]), PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([NAN, 0.0, -1.0]), PackedFloat64Array([0.0, -1.0])]:
		check("terrain normal must be explicitly normalized finite3D", not observe(prepared, PackedStringArray(["belly_front"]), M.q_identity(), normal).ok)
	for q: PackedFloat64Array in [PackedFloat64Array([1.0, 1.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([NAN, 0.0, 0.0, 0.0]), PackedFloat64Array([1.0, 0.0])]:
		check("attitude finite unit4D required", not observe(prepared, PackedStringArray(["belly_front"]), q).ok)
	check("unsupported contact law cannot qualify support", not observe(prepared, PackedStringArray(["belly_front"]), M.q_identity(), PackedFloat64Array([0.0, 0.0, -1.0]), PackedFloat64Array([0.0, 0.0, 0.0]), "terminal-hull").ok)
	check("water support not inferred from belly role", not observe(prepared, PackedStringArray(["belly_front"]), M.q_identity(), PackedFloat64Array([0.0, 0.0, -1.0]), PackedFloat64Array([0.0, 0.0, 0.0]), Hull.law(), "water").ok)
	for key: String in Role.PREPARED_KEYS:
		var changed := prepared.duplicate(true)
		changed.erase(key)
		check("missing prepared field fails closed: " + key, not observe(changed, PackedStringArray(["belly_front"])).ok)
	var changed := prepared.duplicate(true)
	changed.control_envelope.max_angular_speed = 999.0
	check("mutated compiled policy rejected", not observe(changed, PackedStringArray(["belly_front"])).ok)
	changed = prepared.duplicate(true)
	changed.all_hull_ids.append("new_probe")
	check("mutated physical bindings rejected", not observe(changed, PackedStringArray(["belly_front"])).ok)
	for mutation: Dictionary in [{rest_pose = 0.0}, {control_envelope = {}}, {allowed_contact_ids = ["wingtip"]},
		{stop_groups = []}, {hull_geometry_identity = "not-a-digest"}, {ok = 1}, {format = false}, {law = 1},
		{required_hull_law = false}, {rest_pose = {roll = "0", pitch = 0.1}}]:
		changed = prepared.duplicate(true)
		changed.merge(mutation, true)
		changed.erase("identity")
		changed.identity = Role._hash(changed)
		check("checksum alone cannot validate inconsistent compiled policy", not observe(changed, PackedStringArray(["belly_front"])).ok)
	changed = prepared.duplicate(true)
	changed.hull_geometry_identity = "0".repeat(64)
	changed.erase("identity")
	changed.identity = Role._hash(changed)
	check("installation rejects forged owner pin even with recomputed checksum", not Role.matches_model(changed, model_fixture()))
	var many := PackedStringArray()
	for i: int in 257: many.append("probe_%d" % i)
	check("accepted contact query has finite count bound", not observe(prepared, many).ok)
	changed = prepared.duplicate(true)
	changed.provenance.evidence.source = changed
	check("cyclic malformed resource rejected without traversal escape", not observe(changed, PackedStringArray(["belly_front"])).ok)


func _stock_unchanged() -> void:
	for path: String in ["res://data/aircraft/skywalker_x8.json", "res://data/aircraft/battery/skywalker_x8_6s_pack.json"]:
		var loaded := AircraftData.load_file(path)
		check("stock X8 still loads without intended role", loaded.ok)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check("stock authoring has no optional role module", not raw.has("intended_hull_support"))
		check("no absent-module default can enable stock X8 credit", not Role.prepare({}, loaded.model).ok)
