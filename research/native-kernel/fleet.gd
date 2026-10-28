## NK-3 fleet qualification through the production FlightSession backend selection.
## A passing row requires completed, healthy reference and native runs with identical typed
## initial, warm-up and sample state fingerprints. Every native tick must retain the same
## installed stage and invoke both native context and stage. Matching reference fallbacks fail.
## Rotorcraft use the production HelicopterFlightSession, with checkpoint replay.
## Known source startup refusals are checked against both requests, recorded separately,
## and cannot qualify a flight.
## Run via run.py --script fleet.gd --app-library; optional --option aircraft=<id>,
## --option weather=<preset>, --option soft-hull=on|off limit the declared matrix and label it scoped.
extends "trajectory.gd"

const NativeStage := preload("res://sim/native_stage.gd")
const WindConfig := preload("res://physics/wind_config.gd")
const HelicopterSession := preload("res://sim/helicopter_flight_session.gd")
const HELICOPTER_TRIM_REFUSAL := "hover trim line search could not reduce the full-force residual"
const STIK_RUNWAY_REFUSAL := "reset failed: runway start: idle support pose unresolved: bounded line search found no feasible descent step"
const STIK_RUNWAY_REFUSAL_AIRCRAFT := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t",
	"stik-glow-55ax-2t", "stik-glow-fs64v-4t"]
const STIK_RUNWAY_REFUSAL_WEATHER := ["crosswind", "spatial-crosswind-v1"]
const HELICOPTER_REPLAY_TICKS := 8


## The production loader must verify the receipt before the class is initialized.
## The generic oracle loader deliberately cannot be used for this check.
func _load_native_extension() -> bool:
	if _extension != NativeStage.EXTENSION_PATH:
		printerr("NK3_FLEET requires --app-library and the canonical production descriptor")
		return false
	var status: Dictionary = NativeStage.library_status()
	if not status.get("ok", false):
		printerr("NK3_FLEET production library refused: " + str(status.get("reason", "unknown")))
		return false
	_native = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
	if _native == null:
		printerr("NK3_FLEET production native class unavailable after receipt verification")
		return false
	return true


func _extra_option_names() -> PackedStringArray:
	return PackedStringArray(["warmup", "samples", "aircraft", "weather", "soft-hull"])


## Declare the complete stock catalog/preset matrix before applying any scope filters.
## Custom authored weather and arbitrary input histories require additional evidence.
static func _fleet_declared_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var presets: Array[Dictionary] = WindConfig.presets()
	for entry: Dictionary in Catalog.flyable_entries():
		var id := str(entry.id)
		if Catalog.is_rotorcraft(id):
			# HelicopterFlightSession refuses spatial, column and session-OU weather.
			for preset: Dictionary in presets:
				var config: Dictionary = preset.config
				if config.get("format") == WindConfig.SPATIAL_FORMAT \
						or WindConfig.has_vertical_atmosphere(config) or WindConfig.has_turbulence(config):
					continue
				for start: String in ["airborne", "ground"]:
					rows.append({aircraft = id, vehicle = "rotorcraft", case = start, battery = "ideal",
						default_battery = true, weather = str(preset.id), soft_hull = null,
						expected = "reference-refusal" if str(preset.id) == "hot-high" else "flight"})
			continue
		var default_battery: String = Catalog.default_battery_mode(id)
		var batteries: Array[String] = [default_battery]
		if default_battery != "ideal" and Catalog.has_battery_mode(id, "ideal"):
			batteries.append("ideal")
		elif default_battery != "pack" and Catalog.has_battery_mode(id, "pack"):
			batteries.append("pack")
		var starts: Array[String] = ["trim"]
		if Session.half_power_start_supported(id):
			starts.append("airborne_half_power")
		if Catalog.runway_supported(id):
			starts.append("runway")
		if Catalog.hand_launch_supported(id):
			starts.append("hand_launch")
		for battery: String in batteries:
			for preset: Dictionary in presets:
				for start: String in starts:
					for soft: bool in [true, false]:
						var row := {aircraft = id, vehicle = "fixed-wing", case = start, battery = battery,
							default_battery = battery == default_battery, weather = str(preset.id), soft_hull = soft}
						if id in STIK_RUNWAY_REFUSAL_AIRCRAFT and battery == "ideal" and start == "runway" \
								and str(preset.id) in STIK_RUNWAY_REFUSAL_WEATHER:
							row.expected = "reference-refusal"
						rows.append(row)
	return rows


static func _fleet_selected_rows(rows: Array[Dictionary], aircraft: String, weather: String,
		soft_hull: String) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for row: Dictionary in rows:
		if not aircraft.is_empty() and row.aircraft != aircraft:
			continue
		if not weather.is_empty() and row.weather != weather:
			continue
		if not soft_hull.is_empty() and (row.vehicle != "fixed-wing" or bool(row.soft_hull) != (soft_hull == "on")):
			continue
		selected.append(row)
	return selected


func _checks() -> void:
	_report.format = "openrc-nk3-fleet v2"
	_report.fleet = []
	_report.library = NativeStage.library_status()
	var warmup: int = int(_options.get("warmup", "600"))
	var samples: int = int(_options.get("samples", "2400"))
	var aircraft := str(_options.get("aircraft", ""))
	var weather := str(_options.get("weather", ""))
	var soft_hull := str(_options.get("soft-hull", ""))
	var declared := _fleet_declared_rows()
	var selected := _fleet_selected_rows(declared, aircraft, weather, soft_hull)
	var scoped := not aircraft.is_empty() or not weather.is_empty() or not soft_hull.is_empty()
	_report.fleet_scope = {scope = "scoped" if scoped else "full-declared-matrix",
		filters = {aircraft = aircraft, weather = weather, soft_hull = soft_hull},
		declared_rows = declared.size(), selected_rows = selected.size(),
		declared_aircraft = Catalog.flyable_ids(), warmup_requested = warmup, samples_requested = samples,
		matrix_complete = false, flight_passed = 0, reference_refused = 0, failed = 0,
		conditions = "Stock catalog battery/start/contact options and named compatible weather presets; expected reference refusals are counted separately and do not qualify a flight. Custom configurations and arbitrary input histories require separate evidence."}
	if warmup <= 0 or samples <= 0:
		_failures.append("fleet warmup and samples must be positive")
		return
	if (not aircraft.is_empty() and not Catalog.flyable_ids().has(aircraft)) \
			or (not weather.is_empty() and WindConfig.preset(weather).is_empty()) \
			or soft_hull not in ["", "on", "off"] or selected.is_empty():
		_failures.append("fleet filters select no supported rows or contain an unknown aircraft, weather or soft-hull option")
		return
	if not _report.library.ok:
		_failures.append("app native library unavailable: " + str(_report.library.reason))
		for row: Dictionary in selected:
			var unavailable: Dictionary = row.duplicate(true)
			unavailable.status = "not-run"
			unavailable.reason = "app native library unavailable: " + str(_report.library.reason)
			_report.fleet.append(unavailable)
		return
	for row: Dictionary in selected:
		_fleet_case(row, warmup, samples)
	for result: Dictionary in _report.fleet:
		match str(result.status):
			"pass": _report.fleet_scope.flight_passed += 1
			"reference-refused": _report.fleet_scope.reference_refused += 1
			_: _report.fleet_scope.failed += 1
	_report.fleet_scope.matrix_complete = not scoped and _failures.is_empty() \
		and _report.fleet.size() == declared.size()


## Build independent sessions with the actual production backend request, data path,
## field and collision-world lifecycle. No research adapter installs the stage here.
func _build_fleet_session(row: Dictionary, requested_backend: String) -> Dictionary:
	var rotorcraft: bool = row.vehicle == "rotorcraft"
	var session: Node = HelicopterSession.new() if rotorcraft else Session.new()
	if not session.setup_stage_backend(requested_backend):
		var reason := str(session.stage_backend_error)
		session.free()
		return {ok = false, reason = "backend selection failed: " + reason}
	session.input_enabled = true
	session.physics_enabled = true
	if not rotorcraft:
		session.crash_auto_restart = false
		session.soft_hull_contacts = bool(row.soft_hull)
	var path: String = Catalog.data_for(str(row.aircraft), str(row.battery))
	if path.is_empty():
		session.free()
		return {ok = false, reason = "catalog battery mode has no data path"}
	var setup_ok := true
	if rotorcraft:
		setup_ok = session.setup(path, str(row.aircraft))
	else:
		session.setup(path, str(row.aircraft))
	if (rotorcraft and not setup_ok) or (not rotorcraft and not session.is_flyable()):
		var reason := str(session.start_error) if rotorcraft else str(session.pause_reason)
		session.free()
		return {ok = false, reason = "aircraft setup failed: " + reason}
	var weather: Dictionary = WindConfig.preset(str(row.weather))
	if weather.is_empty() or not session.setup_weather(weather):
		var reason := str(session.weather_error)
		session.free()
		return {ok = false, reason = "weather setup failed: " + reason}
	var field: Dictionary = FieldLoader.load_from()
	if not field.ok or not session.set_field(field.field):
		session.free()
		return {ok = false, reason = "field load failed"}
	if _world_cache.is_empty():
		_world_cache = CollisionSetup.build(field.field)
	if not _world_cache.get("ok", false) or not session.set_collision_world(_world_cache.world):
		session.free()
		return {ok = false, reason = "collision world installation failed"}
	if rotorcraft:
		if not session.set_start_choice(str(row.case)):
			session.free()
			return {ok = false, reason = "helicopter start selection refused"}
	else:
		var lake_load: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
		if not lake_load.ok or not session.set_lake_context(lake_load.lake):
			session.free()
			return {ok = false, reason = "lake installation failed"}
		match str(row.case):
			"trim": session.start_choice = Session.START_AIRBORNE
			"airborne_half_power": session.start_choice = Session.START_HALF_POWER
			"runway": session.start_choice = Session.START_RUNWAY
			"hand_launch": session.start_choice = Session.START_HAND_LAUNCH
			_:
				session.free()
				return {ok = false, reason = "unknown fixed-wing start"}
	var reset_ok := true
	if rotorcraft:
		reset_ok = session.reset()
	else:
		session.reset()
	if not session.is_flyable() or not session.start_error.is_empty() or not session.sim.fault_reason.is_empty() \
			or session.sim.paused or not session.crash.is_empty() or (rotorcraft and not reset_ok):
		var reason := str(session.start_error) if not session.start_error.is_empty() else str(session.pause_reason)
		session.free()
		return {ok = false, phase = "reset", reason = "reset failed: " + reason}
	session.read_raw = _reader(session, str(row.case))
	return {ok = true, session = session}


static func _fleet_frame(session: Node) -> PackedByteArray:
	# As in research/performance/session_probe.gd: Variant encoding includes types,
	# lengths and tick boundaries; previous is part of the published state.
	var sim: Node = session.sim
	var frame: Array = [sim.tick, sim.state, sim.previous, sim.aux, sim.continuous,
		sim.inputs, sim.last_loads, sim.modes, sim.last_events]
	if session.get_script() == HelicopterSession:
		frame.append_array([session.commands, session.raw, session.shaft_phase,
			session.flight_mode, session.trainer_enabled, session.zero_drive_hold, session.power])
	return var_to_bytes(frame)


static func _fleet_hash_tick(digest: HashingContext, session: Node) -> void:
	digest.update(_fleet_frame(session))


static func _fleet_end(session: Node) -> Dictionary:
	return {tick = session.sim.tick, fault = str(session.sim.fault_reason), crashed = not session.crash.is_empty(),
		paused = session.sim.paused, held = not session.holds.is_empty(), pause_reason = str(session.pause_reason)}


static func _fleet_end_ok(end: Variant, ticks: int) -> bool:
	return end is Dictionary and typeof(end.get("tick")) == TYPE_INT and int(end.tick) == ticks \
		and typeof(end.get("fault")) == TYPE_STRING and end.fault.is_empty() \
		and typeof(end.get("crashed")) == TYPE_BOOL and not end.crashed \
		and typeof(end.get("paused")) == TYPE_BOOL and not end.paused \
		and typeof(end.get("held")) == TYPE_BOOL and not end.held


static func _fleet_stats_valid(stats: Variant) -> bool:
	return stats is Dictionary and typeof(stats.get("stage_calls")) == TYPE_INT \
		and typeof(stats.get("context_calls")) == TYPE_INT and stats.stage_calls >= 0 and stats.context_calls >= 0


static func _fleet_backend_error(session: Node, requested: String, identity: Dictionary,
		expected: Dictionary, helper: Variant, native: Object) -> String:
	if not _fleet_end_ok(_fleet_end(session), session.sim.tick):
		return "session is paused, held, crashed or faulted"
	var status: Dictionary = session.stage_backend_status()
	if status.get("requested") != requested or status.get("identity") != identity \
			or identity.get("backend") != requested:
		return "requested or actual backend changed"
	var model: Variant = session.sim.model
	if model.stage != expected.stage or model.loads != expected.loads or model.rotor_momentum != expected.rotor_momentum \
			or model.block_loads != expected.block_loads or model.block_derivative != expected.block_derivative \
			or model.stage_rotor_momentum != expected.stage_rotor_momentum:
		return "installed evaluators changed"
	if not expected.stage.is_valid() and not expected.loads.is_valid():
		return "no installed stage or body evaluator"
	if requested == NativeStage.BACKEND_NATIVE:
		if helper == null or native == null or session.get("_native_stage") != helper \
				or not helper.has_method("owns_stage") or not helper.owns_stage(session):
			return "production native evaluator is not installed or changed"
		if session.sim.continuous.is_empty():
			if expected.stage.is_valid() or expected.loads != Callable(native, "body_loads") \
					or expected.rotor_momentum != Callable(native, "body_rotor"):
				return "native body-load and rotor callbacks are not installed"
		elif expected.stage != Callable(native, "stage"):
			return "native joint stage is not installed"
	return ""


## Run without timing. The fingerprint includes the initial frame and every
## accepted warm-up/sample tick; a partial digest never becomes passing evidence.
func _fleet_run_session(session: Node, requested: String, warmup: int, samples: int,
		replay := false) -> Dictionary:
	var status: Dictionary = session.stage_backend_status()
	var identity: Dictionary = status.get("identity", {}) if status.get("identity", {}) is Dictionary else {}
	var result := {complete = false, error = "", requested = requested, actual = str(identity.get("backend", "")),
		identity = identity.duplicate(true), reason = str(status.get("reason", "")),
		warmup_completed = 0, samples_completed = 0, fingerprint_boundaries = 0, fingerprint = "",
		end = _fleet_end(session), stage_in_use = "", stage_calls = 0, context_calls = 0,
		native_covered_every_tick = false, aircraft_sha256 = str(session.aircraft.get("input_identity", {}).get("sha256", "")),
		replay_requested = mini(HELICOPTER_REPLAY_TICKS, warmup + samples) if replay else 0,
		replay_completed = 0, replay_ok = false, replay_native_covered = false}
	if warmup <= 0 or samples <= 0:
		result.error = "warmup and samples must be positive"
		return result
	if not _fleet_end_ok(result.end, 0):
		result.error = "initial session is unhealthy or not at tick zero"
		return result
	var expected := {stage = session.sim.model.stage, loads = session.sim.model.loads,
		rotor_momentum = session.sim.model.rotor_momentum, block_loads = session.sim.model.block_loads,
		block_derivative = session.sim.model.block_derivative, stage_rotor_momentum = session.sim.model.stage_rotor_momentum}
	result.stage_in_use = str(expected.stage.get_method()) if expected.stage.is_valid() \
		else str(expected.loads.get_method()) if expected.loads.is_valid() else ""
	var helper: Variant = session.get("_native_stage") if requested == NativeStage.BACKEND_NATIVE else null
	var native: Object = helper.get("_native") if helper != null else null
	if requested == NativeStage.BACKEND_NATIVE and (native == null or not native.has_method("stage_stats") \
			or not native.has_method("reset_stage_stats")):
		result.error = "production native stage or counters unavailable: " + result.reason
		return result
	var error := _fleet_backend_error(session, requested, identity, expected, helper, native)
	if not error.is_empty():
		result.error = error + (": " + result.reason if not result.reason.is_empty() else "")
		return result
	var previous_stats := {}
	if native != null:
		native.reset_stage_stats(false)
		previous_stats = helper.stage_stats()
		if not _fleet_stats_valid(previous_stats):
			result.error = "native counters are malformed"
			return result
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var saved := {}
	var replay_frames: Array[PackedByteArray] = []
	if replay:
		saved = session.checkpoint()
		if saved.is_empty():
			result.error = "helicopter checkpoint unavailable at tick zero"
			return result
		replay_frames.append(_fleet_frame(session))
	_fleet_hash_tick(digest, session)
	result.fingerprint_boundaries = 1
	for phase: String in ["warmup", "samples"]:
		var count: int = warmup if phase == "warmup" else samples
		for index: int in count:
			var tick: int = session.sim.tick
			var reads := _input_reads
			var advanced := _advance(session)
			var current_stats: Dictionary = helper.stage_stats() if native != null else {}
			error = _fleet_backend_error(session, requested, identity, expected, helper, native)
			if error.is_empty() and (not advanced or session.sim.tick != tick + 1 or _input_reads != reads + 1):
				error = "tick or input did not advance exactly once"
			if error.is_empty() and native != null and (not _fleet_stats_valid(current_stats) \
					or not _native_tick_covered(previous_stats, current_stats)):
				error = "native stage or tick context did not cover this tick"
			if not error.is_empty():
				result.error = "%s tick %d: %s" % [phase, index + 1, error]
				result.end = _fleet_end(session)
				if _fleet_stats_valid(current_stats):
					result.stage_calls = current_stats.stage_calls
					result.context_calls = current_stats.context_calls
				return result
			previous_stats = current_stats
			result["warmup_completed" if phase == "warmup" else "samples_completed"] += 1
			_fleet_hash_tick(digest, session)
			result.fingerprint_boundaries += 1
			if replay and replay_frames.size() <= result.replay_requested:
				replay_frames.append(_fleet_frame(session))
	result.fingerprint = digest.finish().hex_encode()
	result.end = _fleet_end(session)
	if native != null:
		result.stage_calls = previous_stats.stage_calls
		result.context_calls = previous_stats.context_calls
		result.native_covered_every_tick = true
	result.complete = _fleet_end_ok(result.end, warmup + samples)
	if not result.complete:
		result.error = "final session is unhealthy or incomplete"
		return result
	if replay:
		var restored: Variant = session.restore_checkpoint(saved)
		if not restored is Dictionary or not restored.get("ok", false) or _fleet_frame(session) != replay_frames[0]:
			result.complete = false
			result.error = "helicopter checkpoint restore refused or changed initial state"
			return result
		session.sim.set_paused(false)
		previous_stats = helper.stage_stats() if native != null else {}
		for index: int in result.replay_requested:
			var tick: int = session.sim.tick
			var reads := _input_reads
			var advanced := _advance(session)
			var current_stats: Dictionary = helper.stage_stats() if native != null else {}
			error = _fleet_backend_error(session, requested, identity, expected, helper, native)
			if error.is_empty() and (not advanced or session.sim.tick != tick + 1 or _input_reads != reads + 1):
				error = "tick or input did not advance exactly once"
			if error.is_empty() and native != null and (not _fleet_stats_valid(current_stats) \
					or not _native_tick_covered(previous_stats, current_stats)):
				error = "native stage or tick context did not cover replay tick"
			if error.is_empty() and _fleet_frame(session) != replay_frames[index + 1]:
				error = "restored continuation differs from the recorded state"
			if not error.is_empty():
				result.complete = false
				result.error = "replay tick %d: %s" % [index + 1, error]
				return result
			result.replay_completed += 1
			previous_stats = current_stats
		result.replay_ok = true
		result.replay_native_covered = native != null
	return result


static func _fleet_pair_error(reference: Dictionary, native: Dictionary, warmup: int, samples: int) -> String:
	if warmup <= 0 or samples <= 0:
		return "warmup and samples must be positive"
	for pair: Array in [[native, NativeStage.BACKEND_NATIVE], [reference, NativeStage.BACKEND_REFERENCE]]:
		var run: Dictionary = pair[0]
		var requested: String = pair[1]
		if not run.get("complete", false):
			return requested + " run incomplete: " + str(run.get("error", "not run"))
		var identity: Variant = run.get("identity", {})
		if run.get("requested") != requested or run.get("actual") != requested \
				or not identity is Dictionary or identity.get("backend") != requested:
			return requested + " run did not use its requested backend"
		if int(run.get("warmup_completed", -1)) != warmup or int(run.get("samples_completed", -1)) != samples \
				or int(run.get("fingerprint_boundaries", -1)) != warmup + samples + 1 \
				or not _fleet_end_ok(run.get("end"), warmup + samples):
			return requested + " run has incomplete or unhealthy ticks"
		var fingerprint: String = str(run.get("fingerprint", ""))
		var aircraft_sha: String = str(run.get("aircraft_sha256", ""))
		if fingerprint.length() != 64 or not fingerprint.is_valid_hex_number() \
				or aircraft_sha.length() != 64 or not aircraft_sha.is_valid_hex_number():
			return requested + " run lacks a complete fingerprint or aircraft identity"
	if not native.get("native_covered_every_tick", false) \
			or int(native.get("context_calls", 0)) < warmup + samples \
			or int(native.get("stage_calls", 0)) < 4 * (warmup + samples):
		return "native run lacked per-tick stage/context coverage"
	var replay_requested: int = int(native.get("replay_requested", 0))
	if replay_requested != int(reference.get("replay_requested", 0)):
		return "reference and native replay lengths differ"
	if replay_requested > 0:
		for run: Dictionary in [reference, native]:
			if not run.get("replay_ok", false) or int(run.get("replay_completed", -1)) != replay_requested:
				return "checkpoint replay incomplete"
		if not native.get("replay_native_covered", false):
			return "native checkpoint replay lacked per-tick coverage"
	if reference.aircraft_sha256 != native.aircraft_sha256:
		return "reference and native aircraft identities differ"
	if reference.fingerprint != native.fingerprint:
		return "reference and native typed state fingerprints differ"
	return ""


func _fleet_execute(row: Dictionary, requested: String, warmup: int, samples: int) -> Dictionary:
	var built := _build_fleet_session(row, requested)
	if not built.ok:
		return {complete = false, requested = requested, error = built.reason}
	var session: Node = built.session
	var result := _fleet_run_session(session, requested, warmup, samples, row.vehicle == "rotorcraft")
	session.free()
	return result


static func _fleet_expected_refusal(row: Dictionary, built: Dictionary) -> bool:
	if row.get("expected") != "reference-refusal" or built.get("ok", false) \
			or built.get("phase") != "reset":
		return false
	if row.get("vehicle") == "rotorcraft" and row.get("aircraft") == "xcell-60-research" \
			and row.get("battery") == "ideal" and row.get("weather") == "hot-high":
		match row.get("case"):
			"airborne":
				return built.get("reason") == "reset failed: Helicopter start refused: " + HELICOPTER_TRIM_REFUSAL
			"ground":
				return built.get("reason") == "reset failed: Ground trainer control reference refused: " + HELICOPTER_TRIM_REFUSAL
		return false
	return row.get("vehicle") == "fixed-wing" and row.get("aircraft") in STIK_RUNWAY_REFUSAL_AIRCRAFT \
		and row.get("battery") == "ideal" and row.get("case") == "runway" \
		and row.get("weather") in STIK_RUNWAY_REFUSAL_WEATHER and typeof(row.get("soft_hull")) == TYPE_BOOL \
		and built.get("reason") == STIK_RUNWAY_REFUSAL


static func _fleet_expected_refusal_pair(row: Dictionary, reference: Dictionary, native: Dictionary) -> bool:
	return _fleet_expected_refusal(row, reference) and _fleet_expected_refusal(row, native) \
		and reference.get("reason") == native.get("reason")


func _fleet_case(row: Dictionary, warmup: int, samples: int) -> void:
	if row.get("expected", "flight") == "reference-refusal":
		var reference := _build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
		var native := _build_fleet_session(row, NativeStage.BACKEND_NATIVE)
		var expected := _fleet_expected_refusal_pair(row, reference, native)
		var reference_reason := str(reference.get("reason", "reference unexpectedly started"))
		var native_reason := str(native.get("reason", "native unexpectedly started"))
		if reference.get("ok", false): reference.session.free()
		if native.get("ok", false): native.session.free()
		var reason := reference_reason if expected else "reference: %s; native: %s" % [reference_reason, native_reason]
		var result: Dictionary = row.duplicate(true)
		result.status = "reference-refused" if expected else "fail"
		result.reason = reason
		result.reference = {complete = false, requested = NativeStage.BACKEND_REFERENCE,
			phase = str(reference.get("phase", "")), error = reference_reason}
		result.native = {complete = false, requested = NativeStage.BACKEND_NATIVE,
			phase = str(native.get("phase", "")), error = native_reason}
		result.fingerprint_equal = false
		_report.fleet.append(result)
		_compare("fleet_reference_refusal", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if expected else 0.0]), row)
		if not expected:
			_failures.append("fleet %s/%s/%s expected matching reset refusals: %s" % [row.aircraft, row.case, row.weather, reason])
		print("NK3_FLEET aircraft=%s case=%s weather=%s status=%s reason=%s" % [row.aircraft, row.case, row.weather, result.status, reason])
		return
	# Fail admission before spending a second run on a known reference fallback.
	var native := _fleet_execute(row, NativeStage.BACKEND_NATIVE, warmup, samples)
	var reference := _fleet_execute(row, NativeStage.BACKEND_REFERENCE, warmup, samples) if native.get("complete", false) \
		else {complete = false, requested = NativeStage.BACKEND_REFERENCE, error = "not run: native run incomplete"}
	var error := _fleet_pair_error(reference, native, warmup, samples)
	var result: Dictionary = row.duplicate(true)
	result.status = "pass" if error.is_empty() else "fail"
	result.reason = error
	result.reference = reference
	result.native = native
	result.fingerprint_equal = error.is_empty() and reference.fingerprint == native.fingerprint
	_report.fleet.append(result)
	_compare("fleet_pair", PackedFloat64Array([1.0]), PackedFloat64Array([1.0 if error.is_empty() else 0.0]), row)
	if not error.is_empty():
		_failures.append("fleet %s/%s/%s/%s/soft=%s: %s" % [row.aircraft, row.battery, row.case, row.weather,
			row.soft_hull, error])
	print("NK3_FLEET aircraft=%s battery=%s case=%s weather=%s soft_hull=%s status=%s reason=%s" % [
		row.aircraft, row.battery, row.case, row.weather, row.soft_hull, result.status, error])
