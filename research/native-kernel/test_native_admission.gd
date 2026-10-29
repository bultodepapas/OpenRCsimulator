## NK-3: production native ownership and exact short tapes at valid admission boundaries.
## Run after installing a verified candidate. A reference fallback is a failure.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Compiler := preload("res://workshop/compiler.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Flight := preload("res://sim/flight_session.gd")
const Helicopter := preload("res://sim/helicopter_flight_session.gd")
const HeliAdapter := preload("res://sim/native/helicopter_stage_adapter.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const NativeConfiguration := preload("res://sim/native/native_configuration.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const PrescribedAdapter := preload("res://sim/native/prescribed_stage_adapter.gd")
const SmoothFixture := preload("res://tests/test_wash_transport.gd")

const TICKS := 3
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
# Two floats per CT row put this table just beyond the former recursive budget.
const SNAPSHOT_CT_ROWS := 524289
var checks := 0
var failures := 0


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Zero wash and an off-axis piece isolate admission from calibration and trim.
func _legacy_raw(count: int, bounds := "donor") -> Dictionary:
	var raw := _read("res://data/aircraft/jensen_ugly_stik_60.json")
	var donor := _read("res://data/aircraft/gp_extra_300s_60.json")
	var prop: Dictionary = donor.propulsion.propeller
	var wake: Dictionary = prop.slipstream.duplicate(true)
	var piece: Dictionary = wake.pieces[1].duplicate(true)
	piece.root.value = [1.0, 2.0, 2.0]
	if bounds == "lower":
		piece.area.value = 0.001
		piece.span.value = 0.01
		piece.chords.value = [0.005, 0.005]
	elif bounds == "upper":
		piece.area.value = 1.0
		piece.span.value = 2.0
		piece.chords.value = [1.0, 1.0]
	wake.wash_factor.value = [0.0, 0.0]
	wake.swirl_factor.value = 0.0
	wake.erase("propeller_sidewash")
	wake.pieces = []
	for _i in count: wake.pieces.append(piece.duplicate(true))
	raw.propulsion.propeller.thrust_angles = prop.thrust_angles.duplicate(true)
	raw.propulsion.propeller.slipstream = wake
	return raw


func _validated(raw: Dictionary, label: String) -> Dictionary:
	var data: Dictionary = AircraftData.validate_and_derive(raw)
	check(label + " validates", data.get("ok", false), str(data.get("errors", [])))
	if not data.get("ok", false): return {}
	var profiled: Dictionary = WheelProfiles.apply_to_model(data.model)
	check(label + " wheel profile", profiled.get("ok", false), str(profiled.get("errors", [])))
	if not profiled.get("ok", false): return {}
	data.model = profiled.model
	data.wheel_profile_identity = profiled.identity
	data.input_identity = {format = AircraftData.FORMAT, sha256 = JSON.stringify(raw, "", true, true).sha256_text()}
	return data


func _compiled(raw: Dictionary, scale: float, label: String) -> Dictionary:
	var built: Dictionary = Compiler.compile(raw, {scale = scale})
	check(label + " compiles", built.get("ok", false), str(built.get("errors", [])))
	if not built.get("ok", false): return {}
	var data: Dictionary = built.data
	data.input_identity = {format = AircraftData.FORMAT, sha256 = JSON.stringify(built.raw, "", true, true).sha256_text()}
	return data


func _flight(data: Dictionary, backend: String, label: String) -> Node:
	var session := Flight.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.crash_auto_restart = false
	check(label + " selects " + backend, session.setup_stage_backend(backend))
	session.setup("synthetic://native-admission", "jensen-das-ugly-stik-60", data)
	check(label + " starts " + backend, session.is_flyable() and not session.sim.paused
		and session.sim.fault_reason.is_empty() and session.crash.is_empty(),
		str({start = session.start_error, pause = session.pause_reason, backend = session.stage_backend_status()}))
	return session


func _helicopter(field: Dictionary, backend: String, label: String) -> Node:
	var session := Helicopter.new()
	session.input_enabled = false
	session.physics_enabled = false
	check(label + " selects " + backend, session.setup_stage_backend(backend))
	check(label + " helicopter setup " + backend, session.setup(), str(session.start_error))
	check(label + " field accepted " + backend, session.set_field(field), str(session.surface_error))
	check(label + " reset " + backend, session.reset(), str(session.start_error))
	check(label + " starts " + backend, session.is_flyable() and not session.sim.paused
		and session.sim.fault_reason.is_empty() and session.crash.is_empty(), str(session.pause_reason))
	return session


func _frame(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	var values: Array = [sim.tick, sim.state, sim.previous, sim.aux, sim.continuous,
		sim.inputs, sim.last_loads, sim.modes, sim.last_events]
	if session.get_script() == Helicopter:
		values.append_array([session.commands, session.raw, session.shaft_phase, session.flight_mode,
			session.trainer_enabled, session.zero_drive_hold, session.power])
	return var_to_bytes(values)


## A byte match counts only when the production helper owns each native call.
func _tape(reference: Node, candidate: Node, label: String) -> void:
	var status: Dictionary = candidate.stage_backend_status()
	var helper: Variant = candidate._native_stage
	var owns: bool = status.get("requested") == NativeStage.BACKEND_NATIVE \
		and status.get("identity", {}).get("backend") == NativeStage.BACKEND_NATIVE \
		and helper != null and helper.owns_stage(candidate)
	check(label + " owns native stage", owns, str(status))
	check(label + " reference owns reference stage", reference.stage_backend_identity().get("backend") == NativeStage.BACKEND_REFERENCE)
	var same := _frame(reference) == _frame(candidate)
	var complete := true
	var covered := owns
	var previous := {}
	if owns:
		helper._native.reset_stage_stats(false)
		previous = helper.stage_stats()
	for tick in TICKS:
		reference.sim.step()
		candidate.sim.step()
		var healthy: bool = reference.sim.tick == tick + 1 and candidate.sim.tick == tick + 1 \
			and not reference.sim.paused and not candidate.sim.paused and reference.sim.fault_reason.is_empty() \
			and candidate.sim.fault_reason.is_empty() and reference.crash.is_empty() and candidate.crash.is_empty()
		complete = complete and healthy
		same = same and _frame(reference) == _frame(candidate)
		if owns:
			var current: Dictionary = helper.stage_stats()
			covered = covered and helper.owns_stage(candidate) \
				and int(current.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1 \
				and int(current.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4
			previous = current
	check(label + " completes exact tape with native coverage", complete and same and covered,
		str({reference_tick = reference.sim.tick, native_tick = candidate.sim.tick,
			reference_fault = reference.sim.fault_reason, native_fault = candidate.sim.fault_reason,
			equal = same, covered = covered, stats = previous}))


func _fixed_pair(data: Dictionary, label: String, check_guard := false) -> void:
	if data.is_empty(): return
	var reference := _flight(data, NativeStage.BACKEND_REFERENCE, label)
	var candidate := _flight(data, NativeStage.BACKEND_NATIVE, label)
	if check_guard:
		var boundary: Dictionary = NativeConfiguration.prepare(reference, WeatherAdapter.config_for)
		check(label + " configuration boundary", boundary.get("ok", false), str(boundary.get("reason", "")))
		if boundary.get("ok", false):
			var guard: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
			var result: Dictionary = guard.prepare_configuration_guard(reference, boundary.identity)
			check(label + " configuration guard accepts large valid model", result.get("ok", false), str(result))
			if result.get("ok", false):
				check(label + " configuration guard matches", guard.configuration_guard_matches(reference))
				var pieces: Array = reference.aircraft.model.propulsion.slipstream.pieces
				var last: Dictionary = pieces[pieces.size() - 1]
				var area: float = last.area
				last.area = area * 1.01
				check(label + " detects late-piece mutation", not guard.configuration_guard_matches(reference))
				last.area = area
				check(label + " matches again after exact restoration", guard.configuration_guard_matches(reference))
	_tape(reference, candidate, label)
	reference.free()
	candidate.free()


func _wake_boundaries() -> Dictionary:
	# Each legacy piece has seven watched containers/values. The largest case
	# crosses the former 65,536-watch cap independently of the old decoder cap.
	for count: int in [1024, 1025, 10000]:
		var label := "legacy wake pieces=" + str(count)
		var data := _validated(_legacy_raw(count), label)
		_fixed_pair(data, label, count == 10000)
	for entry: Dictionary in [{scale = 0.1, bounds = "lower"}, {scale = 5.0, bounds = "upper"}]:
		var label := "legacy wake scale=" + str(entry.scale)
		var data := _compiled(_legacy_raw(1, entry.bounds), entry.scale, label)
		if data.is_empty(): continue
		var piece: Dictionary = data.model.propulsion.slipstream.pieces[0]
		var outside: bool = (piece.area < 0.001 and piece.span < 0.01 and piece.chords[0] < 0.005) \
			if entry.bounds == "lower" else (piece.area > 1.0 and piece.span > 2.0 and piece.chords[0] > 1.0)
		check(label + " crosses all original dimension bounds", outside, str(piece))
		_fixed_pair(data, label)
	var smooth := _compiled(SmoothFixture.raw_fixture(), 0.1, "smooth transport scale=0.1")
	if not smooth.is_empty():
		check("smooth transport speed remains unscaled", smooth.model.propulsion.slipstream.transport_speed_floor == 1.0)
		_fixed_pair(smooth, "smooth transport scale=0.1")
	return _validated(_legacy_raw(1), "malformed wake control")


func _many_fields() -> Array:
	var raw := _read(FieldLoader.DEFAULT_PATH)
	var template: Dictionary = raw.surfaces[1].duplicate(true)
	template.type = "mown"
	template.width_north_south.value = 1.0
	template.length_east_west.value = 1.0
	while raw.surfaces.size() < 999:
		var surface: Dictionary = template.duplicate(true)
		surface.id = "native_admission_%04d" % raw.surfaces.size()
		surface.center_north.value = 5000.0 + 2.0 * raw.surfaces.size()
		surface.center_east.value = 5000.0
		raw.surfaces.append(surface)
	var below: Dictionary = FieldLoader.validate(raw)
	check("999-rectangle field validates", below.get("ok", false), str(below.get("errors", [])))
	var last: Dictionary = template.duplicate(true)
	last.id = "native_admission_0999"
	last.center_north.value = 5000.0 + 2.0 * raw.surfaces.size()
	last.center_east.value = 5000.0
	raw.surfaces.append(last)
	var above: Dictionary = FieldLoader.validate(raw)
	check("1000-rectangle field validates", above.get("ok", false), str(above.get("errors", [])))
	return [below, above]


func _helicopter_boundaries() -> void:
	var fields := _many_fields()
	if not fields[0].get("ok", false) or not fields[1].get("ok", false): return
	for i in fields.size():
		var label := "helicopter surface values=" + str(6000 + i * 6)
		var reference := _helicopter(fields[i].field, NativeStage.BACKEND_REFERENCE, label)
		var candidate := _helicopter(fields[i].field, NativeStage.BACKEND_NATIVE, label)
		check(label + " table shape", reference.ground_surfaces.size() == 6000 + i * 6 \
			and Terrain.is_valid_surface_table(reference.ground_surfaces))
		_terrain_samples(reference.ground_surfaces, label)
		_tape(reference, candidate, label)
		if i == 0: _bad_surfaces(reference)
		reference.free()
		candidate.free()


func _terrain_samples(surfaces: PackedFloat64Array, label: String) -> void:
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var prepared: Dictionary = native.prepare_ground({}, surfaces, {}, true)
	check(label + " native terrain validates", native.surface_table_is_valid(surfaces) \
		and prepared.get("ok", false) and prepared.get("surfaces_valid", false), str(prepared))
	if not prepared.get("ok", false): return
	# Cover the first, middle and last rectangles, their feathered edges and the
	# catch-all, so the reverse traversal order is exercised by actual samples.
	var rows: int = surfaces.size() / 6
	var points: Array[PackedFloat64Array] = [PackedFloat64Array([0.0, 0.0])]
	if rows > 1:
		for row: int in [0, (rows - 1) / 2, rows - 2]:
			var at := row * 6
			points.append(PackedFloat64Array([(surfaces[at] + surfaces[at + 1]) * 0.5,
				(surfaces[at + 2] + surfaces[at + 3]) * 0.5]))
			points.append(PackedFloat64Array([surfaces[at] + 0.25, surfaces[at + 2] + 0.25]))
	for point: PackedFloat64Array in points:
		var expected: PackedFloat64Array = Terrain.sample_validated(point[0], point[1], surfaces)
		var actual: PackedFloat64Array = native.terrain_sample(point[0], point[1], false)
		check(label + " terrain sample " + str(point), expected.to_byte_array() == actual.to_byte_array())


func _prop_geometry(prop: Dictionary) -> Dictionary:
	var out := {}
	for key: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
		if prop.has(key): out[key] = prop[key]
	return out


func _bad_wake(data: Dictionary) -> void:
	if data.is_empty(): return
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var model: Dictionary = data.model
	var ss: Dictionary = model.propulsion.slipstream
	check("wake malformed control aero", native.prepare_aero(model).get("ok", false))
	check("wake malformed control propeller", native.prepare_propeller(_prop_geometry(model.propulsion)).get("ok", false))
	for defect: String in ["area_zero", "span_negative", "chord_zero", "area_nan", "direction", "extra_key"]:
		check("wake valid control before " + defect, native.prepare_wake(ss).get("ok", false))
		var bad: Dictionary = ss.duplicate(true)
		match defect:
			"area_zero": bad.pieces[0].area = 0.0
			"span_negative": bad.pieces[0].span = -1.0
			"chord_zero": bad.pieces[0].chords[0] = 0.0
			"area_nan": bad.pieces[0].area = NAN
			"direction": bad.pieces[0].span_dir = PackedFloat64Array([1.0, 1.0, 0.0])
			"extra_key": bad.pieces[0].unexpected = true
		check("wake refuses " + defect, not native.prepare_wake(bad).get("ok", true))
		var stale: PackedFloat64Array = native.wake_component(1, PackedFloat64Array([0, 0, -3, 10, 0, 0, 1, 0, 0, 0, 0, 0, 0]),
			PackedFloat64Array([0, 0, 0]), 1.225, PackedFloat64Array([0, 0, 0, 0]), 1000.0,
			PackedFloat64Array([1, 1]), 0.0, PackedFloat64Array(), PackedFloat64Array())
		check("wake refusal clears previous prepare " + defect, stale.is_empty())
	var smooth_data: Dictionary = AircraftData.validate_and_derive(SmoothFixture.raw_fixture())
	check("smooth malformed control validates", smooth_data.get("ok", false), str(smooth_data.get("errors", [])))
	if not smooth_data.get("ok", false): return
	model = smooth_data.model
	ss = model.propulsion.slipstream
	check("smooth malformed control aero", native.prepare_aero(model).get("ok", false))
	check("smooth malformed control propeller", native.prepare_propeller(_prop_geometry(model.propulsion)).get("ok", false))
	for defect: String in ["count", "profile_order", "profile_area", "profile_nan", "transport_zero", "transport_infinite", "mixed_laws"]:
		check("smooth valid control before " + defect, native.prepare_wake(ss).get("ok", false))
		var bad: Dictionary = ss.duplicate(true)
		match defect:
			"count":
				while bad.pieces.size() <= 8: bad.pieces.append(bad.pieces[0].duplicate(true))
			"profile_order": bad.pieces[0].profile = PackedFloat64Array([0.0, 0.0, 0.1, 0.1])
			"profile_area": bad.pieces[0].area *= 1.1
			"profile_nan": bad.pieces[0].profile[0] = NAN
			"transport_zero": bad.transport_speed_floor = 0.0
			"transport_infinite": bad.transport_speed_floor = INF
			"mixed_laws": bad.propeller_sidewash = 0.5
		check("smooth wake refuses " + defect, not native.prepare_wake(bad).get("ok", true))


## Exercise the exposed guard with a compact aliased DAG. Build the identity
## directly so the production deep-copy step does not expand the test graph.
func _guard_alias(data: Dictionary) -> void:
	if data.is_empty(): return
	var session := _flight(data, NativeStage.BACKEND_REFERENCE, "guard alias")
	var boundary: Dictionary = NativeConfiguration.prepare(session, WeatherAdapter.config_for)
	check("guard alias boundary", boundary.get("ok", false), str(boundary.get("reason", "")))
	if not boundary.get("ok", false):
		session.free()
		return
	var identity: RefCounted = boundary.identity
	var fields: Dictionary = identity.session_values.duplicate()
	var expected_aircraft: Dictionary = fields.aircraft.duplicate()
	fields.aircraft = expected_aircraft
	identity.session_values = fields
	var live_leaf := {value = 1.0}
	var expected_leaf := {value = 1.0}
	var live: Variant = live_leaf
	var saved: Variant = expected_leaf
	# 24 doubled levels would otherwise visit over 16 million leaves.
	for i in 24:
		if i % 2 == 0:
			live = [live, live]
			saved = [saved, saved]
		else:
			live = {left = live, right = live}
			saved = {left = saved, right = saved}
	session.aircraft.native_admission_alias = live
	expected_aircraft.native_admission_alias = saved
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var started := Time.get_ticks_msec()
	var result: Dictionary = native.prepare_configuration_guard(session, identity)
	var elapsed := Time.get_ticks_msec() - started
	check("guard accepts matching shared arrays and dictionaries", result.get("ok", false), str(result))
	check("guard alias preparation is bounded", elapsed < 10000, "%d ms" % elapsed)
	if result.get("ok", false):
		check("guard initially matches shared graph", native.configuration_guard_matches(session))
		live_leaf.value = 2.0
		check("guard detects shared leaf mutation", not native.configuration_guard_matches(session))
		live_leaf.value = 1.0
		check("guard detects restored shared leaf", native.configuration_guard_matches(session))
		var root: Dictionary = live
		var edge: Variant = root.right
		root.right = []
		check("guard retains each alias parent edge", not native.configuration_guard_matches(session))
		root.right = edge
		check("guard matches restored alias edge", native.configuration_guard_matches(session))
	# The same pair at a deeper path must not bypass the depth limit merely
	# because it has already been checked at a shallower depth.
	var live_deep: Variant = live_leaf
	var saved_deep: Variant = expected_leaf
	for _i in 33:
		live_deep = [live_deep]
		saved_deep = [saved_deep]
	session.aircraft.native_admission_alias = [live_leaf, live_deep]
	expected_aircraft.native_admission_alias = [expected_leaf, saved_deep]
	check("guard rejects alias past depth limit", not native.prepare_configuration_guard(session, identity).get("ok", true) \
		and not native.configuration_guard_matches(session))
	var cycle_live: Array = []
	var cycle_saved: Array = []
	cycle_live.append(cycle_live)
	cycle_saved.append(cycle_saved)
	session.aircraft.native_admission_alias = cycle_live
	expected_aircraft.native_admission_alias = cycle_saved
	check("guard rejects cycles", not native.prepare_configuration_guard(session, identity).get("ok", true) \
		and not native.configuration_guard_matches(session))
	session.aircraft.erase("native_admission_alias")
	expected_aircraft.erase("native_admission_alias")
	cycle_live.clear()
	cycle_saved.clear()
	session.free()


func _prescribed_raw() -> Dictionary:
	var raw := _read(P51_PATH)
	raw.propulsion.erase("fuel_consumption")
	raw.capabilities.energy = "prescribed_fuel"
	return raw


func _prescribed_test_config() -> Dictionary:
	var raw := _prescribed_raw()
	var data := _validated(raw, "prescribed control")
	if data.is_empty(): return {}
	var session := Flight.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup("synthetic://native-prescribed-admission", raw.id, data)
	check("prescribed control starts", session.is_flyable() and not session.sim.paused \
		and session.sim.fault_reason.is_empty(), str(session.pause_reason))
	var config: Dictionary = PrescribedAdapter.config_for(session)
	check("prescribed control config exists", not config.is_empty())
	if not config.is_empty(): config = config.duplicate(true)
	session.free()
	return config


## Alter only the two source snapshots. Existing session model and other stage
## prerequisites stay unchanged, so the decoder error identifies comparison.
func _snapshot_with_sources(config: Dictionary, actual: Dictionary, saved: Dictionary) -> Dictionary:
	var changed: Dictionary = config.duplicate()
	var model: Dictionary = config.model.duplicate()
	var prescribed: Dictionary = config.prescribed.duplicate()
	model.propulsion = actual
	prescribed.source = saved
	changed.model = model
	changed.prescribed = prescribed
	return changed


func _snapshot_alias(config: Dictionary) -> void:
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var initial: Dictionary = native.prepare_stage(config)
	check("prescribed snapshot valid control prepares", initial.get("ok", false), str(initial))
	if not initial.get("ok", false): return
	var actual: Dictionary = config.model.propulsion.duplicate()
	var saved: Dictionary = config.prescribed.source.duplicate()
	var live_leaf := {value = 1.0}
	var saved_leaf := {value = 1.0}
	var live: Variant = live_leaf
	var snapshot_value: Variant = saved_leaf
	for i in 24:
		if i % 2 == 0:
			live = [live, live]
			snapshot_value = [snapshot_value, snapshot_value]
		else:
			live = {left = live, right = live}
			snapshot_value = {left = snapshot_value, right = snapshot_value}
	actual.native_admission_alias = live
	saved.native_admission_alias = snapshot_value
	var changed := _snapshot_with_sources(config, actual, saved)
	var started := Time.get_ticks_msec()
	var result: Dictionary = native.prepare_stage(changed)
	check("prescribed shared DAG compares then rejects unknown field", not result.get("ok", true) \
		and str(result.get("error", "")).contains("unsupported prescribed shaft source.native_admission_alias"), str(result))
	check("prescribed shared DAG comparison is bounded", Time.get_ticks_msec() - started < 10000)
	saved_leaf.value = 2.0
	result = native.prepare_stage(changed)
	check("prescribed shared DAG catches changed leaf", not result.get("ok", true) \
		and result.get("error") == "prescribed source differs from the committed model", str(result))
	var live_deep: Variant = live_leaf
	var saved_deep: Variant = saved_leaf
	saved_leaf.value = 1.0
	for _i in 33:
		live_deep = [live_deep]
		saved_deep = [saved_deep]
	actual.native_admission_alias = [live_leaf, live_deep]
	saved.native_admission_alias = [saved_leaf, saved_deep]
	result = native.prepare_stage(changed)
	check("prescribed snapshot rejects deeper alias", not result.get("ok", true) \
		and result.get("error") == "prescribed source differs from the committed model", str(result))
	var live_cycle: Array = []
	var saved_cycle: Array = []
	live_cycle.append(live_cycle)
	saved_cycle.append(saved_cycle)
	actual.native_admission_alias = live_cycle
	saved.native_admission_alias = saved_cycle
	result = native.prepare_stage(changed)
	check("prescribed snapshot rejects cycles", not result.get("ok", true) \
		and result.get("error") == "prescribed source differs from the committed model", str(result))
	actual.erase("native_admission_alias")
	saved.erase("native_admission_alias")
	live_cycle.clear()
	saved_cycle.clear()


func _large_prescribed_snapshot(config: Dictionary) -> void:
	var raw := _prescribed_raw()
	var rows := []
	rows.resize(SNAPSHOT_CT_ROWS)
	for i: int in rows.size(): rows[i] = [float(i) / float(rows.size() - 1), 0.1]
	raw.propulsion.propeller.ct_table.value = rows
	# This is the complete reference v2 validation, not a fabricated normalized
	# source. J increases from 0 to 1, and each thrust coefficient is valid.
	var data: Dictionary = AircraftData.validate_and_derive(raw)
	check("large prescribed table passes full aircraft validation", data.get("ok", false), str(data.get("errors", [])))
	if not data.get("ok", false): return
	var actual: Dictionary = data.model.propulsion
	check("large prescribed table exceeds the former flat budget", actual.ct.size() == SNAPSHOT_CT_ROWS * 2 \
		and actual.ct.size() > 1024 * 1024, str(actual.ct.size()))
	var saved: Dictionary = actual.duplicate(true)
	var candidate := _snapshot_with_sources(config, actual, saved)
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var prepared: Dictionary = native.prepare_stage(candidate)
	check("large validated prescribed source prepares natively", prepared.get("ok", false), str(prepared))


func _bad_surfaces(session: Node) -> void:
	var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	var snapshot: Dictionary = HeliAdapter.snapshot(session)
	for table: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([-INF, INF, -INF, INF, 0.5, 7.5])]:
		# The accepted context/skids are frozen; keep those exact objects and
		# replace only the detached table under test.
		var small: Dictionary = snapshot.duplicate()
		small.surfaces = table
		var valid: bool = Terrain.is_valid_surface_table(table)
		var prepared: Dictionary = native.prepare_helicopter(small)
		check("helicopter empty or catch-all table validates and prepares", valid and prepared.get("ok", false),
			str({table = table, reference_valid = valid, native = prepared}))
	_terrain_samples(PackedFloat64Array([-INF, INF, -INF, INF, 0.5, 7.5]), "single catch-all")
	check("helicopter valid surface control", native.prepare_helicopter(snapshot).get("ok", false))
	for defect: String in ["stride", "nan", "reversed", "outside"]:
		var bad: Dictionary = snapshot.duplicate()
		var table: PackedFloat64Array = snapshot.surfaces.duplicate()
		match defect:
			"stride": table.resize(table.size() - 1)
			"nan": table[4] = NAN
			"reversed": table[1] = table[0]
			"outside": table[table.size() - 6] = 0.0
		bad.surfaces = table
		check("reference refuses surface " + defect, not Terrain.is_valid_surface_table(table))
		var refused: Dictionary = native.prepare_helicopter(bad)
		check("native refuses surface " + defect, not native.surface_table_is_valid(table) \
			and not refused.get("ok", true) and refused.get("error") == "invalid helicopter surface table", str(refused))
		var stale: Dictionary = native.heli_component(session.sim.state, session.sim.continuous, 0.0,
			HeliAdapter.tick(session, session.sim.inputs), PackedFloat64Array([0.0, 0.0, 0.0]))
		check("helicopter refusal clears previous prepare " + defect, not stale.get("ok", true))
		check("helicopter prepare recovers " + defect, native.prepare_helicopter(snapshot).get("ok", false))


func _run() -> void:
	var library: Dictionary = NativeStage.library_status()
	check("verified installed library available", library.get("ok", false), str(library))
	if library.get("ok", false):
		var control := _wake_boundaries()
		_bad_wake(control)
		_guard_alias(control)
		_helicopter_boundaries()
		var prescribed := _prescribed_test_config()
		if not prescribed.is_empty():
			_snapshot_alias(prescribed)
			_large_prescribed_snapshot(prescribed)
	print("NK3_NATIVE_ADMISSION verdict=%s checks=%d failures=%d" % ["pass" if failures == 0 else "fail", checks, failures])
	quit(1 if failures else 0)
