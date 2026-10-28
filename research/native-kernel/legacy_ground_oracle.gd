## NK-3 legacy landing-gear loads: the no-wheel-state law on flat and lake terrain.
## Fixtures are in-memory AircraftData derivations of the stock source files; no
## generated data is edited. A passing component oracle is not flight admission.
extends "stage_oracle.gd"

const LegacyGround := preload("res://physics/ground_contact.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const LEGACY_AIRCRAFT := ["jensen-das-ugly-stik-60", "gp-extra-300s-60"]
const MANY_CONTACTS := 24


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["ticks"])


func _source_hashes() -> Dictionary:
	var out: Dictionary = super._source_hashes()
	for path: String in ["res://physics/ground_contact.gd", "res://physics/aircraft_data.gd",
			"res://physics/ground_terrain.gd", "res://physics/lake_surface.gd", "res://physics/wheel_profiles.gd",
			"res://data/aircraft/jensen_ugly_stik_60.json", "res://data/aircraft/gp_extra_300s_60.json",
			"res://data/fields/default.json", "res://data/fields/lake.json"]:
		out[path] = FileAccess.get_sha256(path)
	return out


func _checks() -> void:
	_report.format = "openrc-nk3-legacy-ground-oracle v1"
	_report.legacy_ground = {cases = [], edge_cases = {}, trajectories = [], requested_states = _states}
	var ticks: int = int(_options.get("ticks", "64"))
	if _states < 20:
		_failures.append("legacy ground oracle needs at least 20 states per case")
		return
	for id: String in LEGACY_AIRCRAFT:
		var source: Dictionary = Catalog.entry(id)
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(source.data)))
		if not raw is Dictionary:
			_failures.append("legacy source could not be read: " + id)
			continue
		var derived: Dictionary = AircraftData.validate_and_derive(raw)
		if not derived.get("ok", false) or derived.model.get("landing_gear", {}).is_empty() \
				or derived.model.get("wheel_profile", {}).get("status", "") == "applied":
			_failures.append("legacy in-memory source was not admitted: " + id)
			continue
		var session := _build_session(id, "runway", false)
		if session == null: continue
		var context := {rest = session.sim.state.duplicate(), surfaces = session.ground_surfaces.duplicate(),
			lake = session._lake.duplicate(true)}
		var gear: Dictionary = derived.model.landing_gear
		for mode: String in ["flat", "flat-surfaces", "lake"]:
			_check_legacy_case(id, gear, context, mode)
		if id == LEGACY_AIRCRAFT[0]:
			# The authoring contract permits no breakaway_factor. Exercise that
			# actual validated layout without changing any source file.
			var raw_without_stiction: Dictionary = raw.duplicate(true)
			raw_without_stiction.landing_gear.erase("breakaway_factor")
			var no_stiction: Dictionary = AircraftData.validate_and_derive(raw_without_stiction)
			if not no_stiction.get("ok", false) or no_stiction.model.landing_gear.has("breakaway_factor"):
				_failures.append("validated legacy gear without stiction was not admitted")
			else:
				for mode: String in ["flat", "flat-surfaces", "lake"]:
					_check_legacy_case(id, no_stiction.model.landing_gear, context, mode, "no-stiction")
			var many_raw := _legacy_raw(MANY_CONTACTS)
			var many: Dictionary = AircraftData.validate_and_derive(many_raw)
			if not many.get("ok", false) or many.model.landing_gear.contacts.size() != MANY_CONTACTS:
				_failures.append("validated many-contact legacy gear was not admitted: " + str(many.get("errors", [])))
			else:
				for mode: String in ["flat", "flat-surfaces", "lake"]:
					_check_legacy_case(id, many.model.landing_gear, context, mode, "24-contacts")
		_check_legacy_edges(id, gear, context)
		session.free()
	if _report.legacy_ground.cases.size() != (LEGACY_AIRCRAFT.size() + 2) * 3:
		_failures.append("legacy aircraft/terrain matrix incomplete")
	if ticks <= 0:
		_failures.append("legacy trajectory ticks must be positive")
		return
	for mode: String in ["flat", "lake"]:
		for contacts: int in [3, MANY_CONTACTS]: _check_legacy_tape(mode, contacts, ticks)


func _check_legacy_case(id: String, gear: Dictionary, context: Dictionary, mode: String, variant := "stock") -> void:
	var surfaces: PackedFloat64Array = PackedFloat64Array() if mode == "flat" else context.surfaces
	var lake: Dictionary = context.lake if mode == "lake" else {}
	var prepared: Dictionary = _ground_ready(_native, gear, surfaces, lake)
	if not prepared.get("ok", false):
		_failures.append("legacy prepare %s/%s: %s" % [id, mode, str(prepared.get("error", ""))])
		return
	var count := {clear = 0, loaded = 0, stuck = 0, sliding = 0, malformed = 0,
		invalid_geometry = 0, lake_slope = 0, partial_anchors = 0}
	for i: int in _states:
		var malformed: bool = i % 10 == 0
		var body := _ground_state(context, context.surfaces, lake, malformed)
		if i % 5 == 0 and not malformed:
			body[2] = -float(gear.reach) - 5.0
		var steer: float = _special() if i % 19 == 0 else _rng.randf_range(-1.2, 1.2)
		var anchors := PackedFloat64Array()
		var anchored: bool = gear.has("breakaway_factor") and i % 3 == 1
		if gear.has("breakaway_factor") and i % 4 != 0:
			var rows: Array = LegacyGround._rows(body)
			for contact: Dictionary in gear.contacts:
				var r: PackedFloat64Array = contact.position
				var north: PackedFloat64Array = rows[0]
				var east: PackedFloat64Array = rows[1]
				anchors.append(body[0] + north[0] * r[0] + north[1] * r[1] + north[2] * r[2] + _rng.randf_range(-0.002, 0.002))
				anchors.append(body[1] + east[0] * r[0] + east[1] * r[1] + east[2] * r[2] + _rng.randf_range(-0.002, 0.002))
				anchors.append(1.0 if anchored else 0.0)
		if mode == "lake" and not anchors.is_empty() and i % 17 == 0:
			anchors.resize(anchors.size() - 1)
			anchored = false
			count.partial_anchors += 1
		var reference: PackedFloat64Array = LegacyGround.loads(body, gear, steer, surfaces, anchors,
			PackedFloat64Array(), 0.0, lake)
		var candidate: PackedFloat64Array = _native.legacy_ground_component(body, steer, anchors)
		_compare("legacy_ground_loads", reference, candidate, [id, mode, i, body, steer, anchors])
		if malformed: count.malformed += 1
		if reference.is_empty(): count.clear += 1
		elif reference.size() == 1: count.invalid_geometry += 1
		elif reference.size() == 6:
			count.loaded += 1
			if anchored: count.stuck += 1
			else: count.sliding += 1
		if mode == "lake" and is_finite(body[0]) and is_finite(body[1]):
			var sampled: Dictionary = LakeSurface.sample_covered_terrain_validated(lake, body[0], body[1])
			if sampled.get("covered", false) and (float(sampled.get("slope_north", 0.0)) != 0.0 \
					or float(sampled.get("slope_east", 0.0)) != 0.0): count.lake_slope += 1
	if count.clear == 0 or count.loaded == 0 or count.malformed == 0 or count.sliding == 0 \
			or (gear.has("breakaway_factor") and count.stuck == 0) \
			or (mode == "lake" and count.lake_slope == 0) \
			or (mode == "lake" and gear.has("breakaway_factor") and count.partial_anchors == 0):
		_failures.append("legacy ground branch coverage incomplete: %s/%s %s" % [id, mode, str(count)])
	_report.legacy_ground.cases.append({name = id + "/" + variant + "/" + mode, aircraft = id, mode = mode, variant = variant, states = _states,
		contacts = gear.contacts.size(), has_anchors = gear.has("breakaway_factor"), coverage = count})


func _check_legacy_edges(id: String, gear: Dictionary, context: Dictionary) -> void:
	var body: PackedFloat64Array = context.rest.duplicate()
	var empty := PackedFloat64Array()
	var cases := [
		{name = "invalid_surface", gear = gear, surfaces = _bad_table(context.surfaces), lake = context.lake},
		{name = "invalid_lake", gear = gear, surfaces = context.surfaces, lake = _bad_lake(context.lake)},
		{name = "empty_gear", gear = {}, surfaces = context.surfaces, lake = context.lake},
		{name = "empty_gear_flat", gear = {}, surfaces = empty, lake = {}},
	]
	for edge: Dictionary in cases:
		var prepared: Dictionary = _ground_ready(_native, edge.gear, edge.surfaces, edge.lake)
		if not prepared.get("ok", false):
			_failures.append("legacy edge prepare %s/%s: %s" % [id, edge.name, str(prepared.get("error", ""))])
			continue
		var reference: PackedFloat64Array = LegacyGround.loads(body, edge.gear, 0.0, edge.surfaces, empty, empty, 0.0, edge.lake)
		_compare("legacy_ground_edges", reference, _native.legacy_ground_component(body, 0.0, empty), [id, edge.name])
		_report.legacy_ground.edge_cases[id + "/" + edge.name] = reference.size()


## Derive a bounded test source in memory; no generated aircraft file is edited.
## Repeating each original support eight times while dividing its stiffness and
## damping by eight preserves the total spring/damper values and exceeds the
## old 16-contact and 64-anchor truncations.
func _legacy_raw(contact_count: int) -> Dictionary:
	var path: String = str(Catalog.entry(LEGACY_AIRCRAFT[0]).data)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.id = "workshop-legacy-gear-oracle-" + str(contact_count)
	if contact_count == MANY_CONTACTS:
		var base: Array = raw.landing_gear.contacts.duplicate(true)
		var contacts: Array = []
		for index: int in MANY_CONTACTS:
			var contact: Dictionary = base[index % base.size()].duplicate(true)
			contact.name = str(contact.name) + "_fixture_%d" % index
			contact.id = "contact_fixture_%d" % index
			contact.stiffness.value = float(contact.stiffness.value) / 8.0
			contact.damping.value = float(contact.damping.value) / 8.0
			contacts.append(contact)
		raw.landing_gear.contacts = contacts
	return raw


## A Workshop-shaped frozen source with an unmatched profile key remains valid
## and has sampled anchors and no rotating-wheel state.
func _legacy_flight(mode: String, contact_count: int) -> Node:
	var raw := _legacy_raw(contact_count)
	var checked: Dictionary = AircraftData.validate_and_derive(raw)
	if not checked.get("ok", false):
		_failures.append("legacy frozen source invalid: " + str(checked.get("errors", [])))
		return null
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model)
	if not profiled.get("ok", false) or profiled.model.wheel_profile.get("status") != "legacy_fallback":
		_failures.append("legacy frozen wheel-profile fallback was not admitted")
		return null
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(JSON.stringify(raw, "", true, true).to_utf8_buffer())
	checked.input_identity = {format = AircraftData.FORMAT, sha256 = digest.finish().hex_encode()}
	var session: Node = Session.new()
	session.input_enabled = false
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup("synthetic://legacy-ground-oracle", raw.id, checked)
	if not session.is_flyable() or session.wheel_count() != 0 or session.anchor_count() != contact_count:
		_failures.append("legacy frozen session setup or layout refused: " + str(session.pause_reason))
		session.free()
		return null
	var field: Dictionary = FieldLoader.load_from()
	var lake: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	if not field.ok or not lake.ok or not session.set_field(field.field) \
			or not session.set_lake_context(lake.lake if mode == "lake" else {}):
		_failures.append("legacy flight field/lake refused: " + mode)
		session.free()
		return null
	session.start_choice = Session.START_RUNWAY
	session.reset()
	if not session.is_flyable() or session.sim.paused or not session.sim.fault_reason.is_empty() \
			or not session.sim.continuous.is_empty() or not session.crash.is_empty():
		_failures.append("legacy ground flight reset refused: " + mode + " " + str(session.pause_reason))
		session.free()
		return null
	return session


static func _legacy_frame(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous, sim.inputs,
		sim.last_loads, sim.modes, sim.last_events, session.crash])


func _check_legacy_tape(mode: String, contact_count: int, ticks: int) -> void:
	var reference := _legacy_flight(mode, contact_count)
	var native := _legacy_flight(mode, contact_count)
	if reference == null or native == null:
		if reference != null: reference.free()
		if native != null: native.free()
		return
	var boundary: Dictionary = NativeConfiguration.prepare(native, WeatherAdapter.config_for)
	if not boundary.get("ok", false):
		_failures.append("legacy native source boundary refused: " + str(boundary.get("reason", "")))
		reference.free()
		native.free()
		return
	var prepared: Dictionary = _native.prepare_stage(boundary.config)
	if not prepared.get("ok", false) \
			or not _native.prepare_weather_guard(native, boundary.weather_identity).get("ok", false) \
			or not _native.prepare_configuration_guard(native, boundary.identity).get("ok", false):
		_failures.append("legacy native prepared stage refused: " + str(prepared.get("error", "")))
		reference.free()
		native.free()
		return
	var helper := NativeStage.new()
	helper._native = _native
	helper._prepared = true
	helper._family = "wheel"
	helper._configuration_identity = boundary.identity
	helper._weather_identity = boundary.weather_identity
	var original := {stage = native.sim.model.stage, loads = native.sim.model.loads,
		rotor = native.sim.model.rotor_momentum, pre_tick = native.sim.model.pre_tick}
	helper.install(native)
	var correct_route: bool = helper.is_installed() and helper.owns_stage(native) \
		and native.sim.model.loads == Callable(_native, "body_loads") \
		and native.sim.model.rotor_momentum == Callable(_native, "body_rotor") \
		and not native.sim.model.stage.is_valid() \
		and helper.tick_context(native, native.sim.aux, native.sim.inputs, native.sim.time())
	if not correct_route:
		_failures.append("legacy native callback installation refused: " + str(helper.reason))
		reference.free()
		native.free()
		return
	_native.reset_stage_stats(false)
	var previous: Dictionary = _native.stage_stats()
	var equal: bool = _compare("legacy_ground_tape_tick", _legacy_frame(reference), _legacy_frame(native), [mode, contact_count, 0])
	var ran := 0
	var contact_ticks := 0
	for i: int in ticks:
		var anchors: PackedFloat64Array = reference.sim.aux.slice(Session.AUX_ANCHORS,
			Session.AUX_ANCHORS + reference.anchor_count() * LegacyGround.ANCHOR_STRIDE)
		var ground_loads: PackedFloat64Array = LegacyGround.loads(reference.sim.state,
			reference.current_landing_gear(reference.sim.aux), reference.sim.aux[Session.AUX_SERVO + 2],
			reference.ground_surfaces, anchors, PackedFloat64Array(), 0.0, reference._lake)
		if ground_loads.size() == 6: contact_ticks += 1
		reference.sim.step()
		native.sim.step()
		var stats: Dictionary = _native.stage_stats()
		if reference.sim.tick != i + 1 or native.sim.tick != i + 1 or reference.sim.paused or native.sim.paused \
				or not reference.sim.fault_reason.is_empty() or not native.sim.fault_reason.is_empty() \
				or not reference.crash.is_empty() or not native.crash.is_empty() \
				or not helper.owns_stage(native) or not helper.configuration_matches(native) \
				or int(stats.stage_calls) - int(previous.stage_calls) < 4 \
				or int(stats.context_calls) - int(previous.context_calls) < 1:
			break
		previous = stats
		ran += 1
		equal = _compare("legacy_ground_tape_tick", _legacy_frame(reference), _legacy_frame(native), [mode, contact_count, i + 1]) and equal
	helper.uninstall(native)
	var restored: bool = native.sim.model.stage == original.stage and native.sim.model.loads == original.loads \
		and native.sim.model.rotor_momentum == original.rotor and native.sim.model.pre_tick == original.pre_tick
	var complete: bool = ran == ticks and equal and restored and contact_ticks > 0
	_report.legacy_ground.trajectories.append({name = mode + "/" + str(contact_count) + "-contacts", mode = mode,
		contacts = contact_count, anchor_values = reference.anchor_count() * LegacyGround.ANCHOR_STRIDE,
		requested_ticks = ticks, ticks_run = ran,
		complete = complete, contact_ticks = contact_ticks, correct_route = correct_route, restored = restored,
		native_stage_calls = int(previous.stage_calls), native_context_calls = int(previous.context_calls)})
	if not complete:
		_failures.append("legacy ground tape incomplete %s: %d/%d contact=%d restored=%s faults=%s/%s" \
			% [mode, ran, ticks, contact_ticks, restored, reference.sim.fault_reason, native.sim.fault_reason])
	reference.free()
	native.free()
