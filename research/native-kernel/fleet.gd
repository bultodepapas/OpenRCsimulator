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
const RuntimeSimulation := preload("res://sim/simulation.gd")
const GlowFlight := preload("res://physics/glow/flight.gd")
const FlightPropulsion := preload("res://physics/propulsion.gd")
const HELICOPTER_TRIM_REFUSAL := "hover trim line search could not reduce the full-force residual"
const STIK_RUNWAY_REFUSAL := "reset failed: runway start: idle support pose unresolved: bounded line search found no feasible descent step"
const STIK_RUNWAY_REFUSAL_AIRCRAFT := ["jensen-das-ugly-stik-60", "stik-glow-61fx-2t",
	"stik-glow-55ax-2t", "stik-glow-fs64v-4t"]
const STIK_RUNWAY_REFUSAL_WEATHER := ["crosswind", "spatial-crosswind-v1"]
const GLOW_REVERSE_TICKS := {"stik-glow-61fx-2t": 873, "stik-glow-55ax-2t": 801}
const GLOW_REVERSE_CODE := "glow_stopped_reverse_drive"
const GLOW_REVERSE_FAULT := "step rejected: RK joint stage evaluation is nonfinite or malformed"
const GLOW_FEED_ENDPOINT_ERROR := "Glow feed factor endpoint evaluation failed"
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
						elif id in GLOW_REVERSE_TICKS and battery == "ideal" and start == "runway" \
								and str(preset.id) == "gusty":
							row.expected = "runtime-domain-refusal"
							row.expected_runtime_tick = GLOW_REVERSE_TICKS[id]
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
		matrix_complete = false, flight_passed = 0, reference_refused = 0, runtime_refused = 0, failed = 0,
		conditions = "Stock catalog battery/start/contact options and named compatible weather presets; expected startup and runtime-domain refusals are counted separately and do not qualify a completed flight. Custom configurations and arbitrary input histories require separate evidence."}
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
			"runtime-domain-refused": _report.fleet_scope.runtime_refused += 1
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
	return _fleet_backend_owner_error(session, requested, identity, expected, helper, native)


## The rejecting-tick proof intentionally permits the recorded fault, but still
## checks the same backend identity, helper ownership and callback set.
static func _fleet_backend_owner_error(session: Node, requested: String, identity: Dictionary,
		expected: Dictionary, helper: Variant, native: Object) -> String:
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


## Only the four reproduced runway/gusty rows have this source-domain boundary.
static func _fleet_runtime_tick(row: Dictionary) -> int:
	if row.get("expected") != "runtime-domain-refusal" or row.get("vehicle") != "fixed-wing" \
			or row.get("battery") != "ideal" or row.get("case") != "runway" \
			or row.get("weather") != "gusty" or typeof(row.get("soft_hull")) != TYPE_BOOL \
			or not GLOW_REVERSE_TICKS.has(row.get("aircraft")):
		return -1
	var expected: int = GLOW_REVERSE_TICKS[row.aircraft]
	return expected if typeof(row.get("expected_runtime_tick")) == TYPE_INT and row.expected_runtime_tick == expected else -1


static func _fleet_rollback_frame(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous,
		sim.modes, sim.last_loads, sim.last_events])


static func _fleet_bytes_sha(value: Variant) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()


static func _fleet_finite_array(value: Variant, expected_size: int) -> bool:
	if not value is PackedFloat64Array or value.size() != expected_size:
		return false
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _fleet_runtime_payload_valid(trial: Variant, context: Variant, tick: int) -> bool:
	if not trial is Array or trial.size() != 3 or not context is Array or context.size() != 8 \
			or not _fleet_finite_array(trial[0], RB.SIZE) or not RuntimeSimulation.state_is_valid(trial[0]) \
			or not _fleet_finite_array(trial[1], GlowFlight.SIZE + 3) or typeof(trial[2]) != TYPE_FLOAT \
			or not is_finite(trial[2]) or not _fleet_finite_array(context[0], 14) \
			or not _fleet_finite_array(context[1], 4) or not _fleet_finite_array(context[2], 5):
		return false
	var values: PackedFloat64Array = trial[1]
	if values[0] != 0.0 or values[7] != 0.0 or values[8] != 2.0 \
			or values[GlowFlight.SOURCE_MODE_INDEX] != float(GlowFlight.MODE_MAIN_TANK):
		return false
	for index: int in [3, 4, 5]:
		if typeof(context[index]) != TYPE_FLOAT or not is_finite(context[index]): return false
	var tick_time: float = float(tick) * (1.0 / 240.0)
	return context[3] == tick_time and trial[2] == tick_time + (1.0 / 240.0) \
		and context[4] == 0.0 and context[5] == 0.0 and context[6] == false and context[7] == false \
		and typeof(context[6]) == TYPE_BOOL and typeof(context[7]) == TYPE_BOOL


## Re-evaluate only the rejected reference trial, with the captured pre-rollback context.
## This observes the existing source law; it changes no aircraft or kernel physics.
static func _fleet_reverse_reference(session: Node, trial: Dictionary, feed_factor: float) -> Dictionary:
	if not trial.get("body") is PackedFloat64Array or not trial.get("continuous") is PackedFloat64Array \
			or not trial.get("aux") is PackedFloat64Array or not trial.get("inputs") is PackedFloat64Array \
			or typeof(trial.get("stage_time")) != TYPE_FLOAT or not is_finite(trial.stage_time) \
			or not is_finite(feed_factor) or feed_factor not in [0.0, 2.0]:
		return {}
	var body: PackedFloat64Array = trial.body
	var values: PackedFloat64Array = trial.continuous
	if not session.sim._array_is_finite(body, RB.SIZE) or not session.sim._array_is_finite(values) \
			or values.size() != GlowFlight.SIZE + session.wheel_count() or values[0] != 0.0 \
			or not session.sim._array_is_finite(trial.aux) or not session.sim._array_is_finite(trial.inputs):
		return {}
	var old_aux: PackedFloat64Array = session.sim.aux
	var old_inputs: PackedFloat64Array = session.sim.inputs
	session.sim.aux = trial.aux.duplicate()
	session.sim.inputs = trial.inputs.duplicate()
	var proof := _fleet_reverse_reference_at_context(session, body, values, trial.stage_time, feed_factor)
	session.sim.aux = old_aux
	session.sim.inputs = old_inputs
	return proof


static func _fleet_reverse_reference_at_context(session: Node, body: PackedFloat64Array,
		values: PackedFloat64Array, at: float, feed_factor: float) -> Dictionary:
	var prop: Dictionary = session.aircraft.model.propulsion
	if not prop.has("glow") or not prop.glow.has("fuel_feed") or session.engine_running:
		return {}
	var install: Dictionary = prop.glow
	var state: Dictionary = GlowFlight.unpack(values, install)
	if state.is_empty() or bool(state.running) or values[GlowFlight.SOURCE_MODE_INDEX] != float(GlowFlight.MODE_MAIN_TANK):
		return {}
	var point: Dictionary = GlowFlight.point(session, body, values, at, true)
	if point.get("ok", false) or point.get("message") != GLOW_FEED_ENDPOINT_ERROR:
		return {}
	var air: Dictionary = session.air_data(body, at)
	var ambient: Dictionary = GlowFlight._environment(session, body)
	var prop_air: Dictionary = FlightPropulsion.stage_air_velocity(body, air, prop)
	if not ambient.get("ok", false) or not prop_air.get("ok", false):
		return {}
	var hub: PackedFloat64Array = prop_air.velocity_body
	var density: float = ambient.rho_kgm3
	var evaluator: Variant = session.get_meta(GlowFlight.PROPELLER_EVALUATOR_META, null)
	var identity_matches: bool = session.get_meta(GlowFlight.EVALUATOR_IDENTITY_META, {}) == install.identity
	var blade: Dictionary = GlowFlight.Blade.evaluate_prepared(evaluator, 0.0, M.dot(hub, prop.axis), density) \
		if evaluator is GlowFlight.Blade.PreparedEvaluator and identity_matches \
		else GlowFlight.Blade.evaluate(0.0, M.dot(hub, prop.axis), density, install.propeller)
	var mass_context: Dictionary = GlowFlight._stage_mass_context(session, values)
	if not blade.get("ok", false) or not mass_context.get("ok", false):
		return {}
	var mass: Dictionary = mass_context.properties
	var airframe: Dictionary = GlowFlight._airframe(session, body, values, air, hub, 0.0, blade, density)
	var coast: Dictionary = GlowFlight.Source.evaluate(install.profile, 0.001,
		GlowFlight.admission_at(install, state.air_fraction, 0.001), values[12],
		1.225 * float(ambient.engine_charge_ratio), false)
	if airframe.is_empty() or not coast.get("ok", false):
		return {}
	var local_cooling: float = M.norm(hub) + sqrt(maxf(0.0, blade.thrust_n) \
		/ (2.0 * density * PI * prop.diameter * prop.diameter / 4.0))
	var life_evaluator: Variant = session.get_meta(GlowFlight.EVALUATOR_META, null)
	var lifecycle_floor: float = 0.0 if install.has("feed_line") else install.unusable_fuel_kg
	var lifecycle: Dictionary = GlowFlight._lifecycle_evaluate(install, state, 0.0, local_cooling, ambient,
		values[12], feed_factor, life_evaluator, identity_matches, session, lifecycle_floor)
	if not lifecycle.get("ok", false):
		return {}
	var rejected_coupling: Dictionary = GlowFlight._stage_coupling(session, body, values, install, state,
		lifecycle.source, blade, airframe, mass, ambient)
	if rejected_coupling.get("ok", false):
		return {}
	var force: PackedFloat64Array = airframe.external.slice(0, 3)
	var torque: PackedFloat64Array = M.sub(airframe.external.slice(3, 6), M.cross(mass.cg_body_m, force))
	var rates: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var alpha: PackedFloat64Array = RB.inertia_mul(mass.inverse,
		M.sub(torque, M.cross(rates, RB.inertia_mul(mass.inertia, rates))))
	var axial_alpha: float = M.dot(prop.axis, alpha)
	var friction: float = -float(coast.shaft_torque_nm)
	var demand: float = -float(blade.torque_nm) - float(prop.rotor_inertia) * axial_alpha
	if not is_finite(friction) or friction <= 0.0 or not is_finite(demand) \
			or not is_finite(axial_alpha) or not is_finite(float(blade.torque_nm)) \
			or not is_finite(float(prop.rotor_inertia)) or float(prop.rotor_inertia) <= 0.0 or demand >= -friction:
		return {}
	return {code = GLOW_REVERSE_CODE, origin = "feed_endpoint", feed_factor = feed_factor, rpm = 0.0,
		demand_nm = demand, friction_nm = friction, prop_load_torque_nm = float(blade.torque_nm),
		axial_acceleration_rad_s2 = axial_alpha, rotor_inertia_kg_m2 = float(prop.rotor_inertia)}


static func _fleet_runtime_proof_error(row: Dictionary, proof: Dictionary, warmup: int, samples: int) -> String:
	var tick := _fleet_runtime_tick(row)
	if tick < 0 or warmup <= 0 or samples <= 0 or warmup + samples <= tick:
		return "undeclared runtime-domain row or horizon"
	for field: String in ["prefix_equal_every_tick", "terminal_equal", "reference_rollback", "native_rollback",
			"reference_owner_retained", "native_owner_retained", "native_covered_every_tick", "trial_equal",
			"context_equal", "reference_result_empty"]:
		if typeof(proof.get(field)) != TYPE_BOOL or not proof[field]:
			return "runtime-domain proof flag is missing: " + field
	if proof.get("code") != GLOW_REVERSE_CODE or proof.get("origin") != "feed_endpoint" \
			or typeof(proof.get("accepted_ticks")) != TYPE_INT or proof.accepted_ticks != tick \
			or typeof(proof.get("attempted_tick")) != TYPE_INT or proof.attempted_tick != tick + 1 \
			or typeof(proof.get("requested_ticks")) != TYPE_INT or proof.requested_ticks != warmup + samples \
			or typeof(proof.get("warmup_completed")) != TYPE_INT or proof.warmup_completed != mini(warmup, tick) \
			or typeof(proof.get("samples_completed")) != TYPE_INT or proof.samples_completed != maxi(0, tick - warmup):
		return "runtime-domain tick, phase or branch differs"
	if typeof(proof.get("prefix_boundaries")) != TYPE_INT or proof.prefix_boundaries != tick + 1 \
			or typeof(proof.get("reference_prefix_sha256")) != TYPE_STRING \
			or proof.reference_prefix_sha256.length() != 64 or not proof.reference_prefix_sha256.is_valid_hex_number() \
			or proof.get("native_prefix_sha256") != proof.reference_prefix_sha256 \
			or proof.get("prefix_equal_every_tick") != true or proof.get("terminal_equal") != true \
			or proof.get("reference_rollback") != true or proof.get("native_rollback") != true:
		return "runtime-domain accepted prefix or rollback differs"
	var reference_end: Variant = proof.get("reference_end")
	var native_end: Variant = proof.get("native_end")
	if not reference_end is Dictionary or not native_end is Dictionary or reference_end != native_end \
			or reference_end.get("tick") != tick or reference_end.get("fault") != GLOW_REVERSE_FAULT \
			or reference_end.get("paused") != true or reference_end.get("crashed") != false \
			or reference_end.get("held") != false:
		return "runtime-domain terminal state differs"
	var identity: Variant = proof.get("native_identity")
	var reference_identity: Variant = proof.get("reference_identity")
	var aircraft_hash: Variant = proof.get("reference_aircraft_sha256")
	if typeof(aircraft_hash) != TYPE_STRING or aircraft_hash.length() != 64 or not aircraft_hash.is_valid_hex_number() \
			or proof.get("native_aircraft_sha256") != aircraft_hash:
		return "runtime-domain aircraft identities differ"
	if not reference_identity is Dictionary or reference_identity.get("backend") != "gdscript_reference" \
			or not identity is Dictionary or identity.get("backend") != "native" or identity.get("abi_version") != 2 \
			or proof.get("native_owner_retained") != true or proof.get("native_covered_every_tick") != true \
			or typeof(proof.get("reference_input_reads")) != TYPE_INT or proof.reference_input_reads != tick + 1 \
			or typeof(proof.get("native_input_reads")) != TYPE_INT or proof.native_input_reads != tick + 1 \
			or typeof(proof.get("native_stage_calls")) != TYPE_INT or proof.native_stage_calls < 4 * tick + 1 \
			or typeof(proof.get("native_context_calls")) != TYPE_INT or proof.native_context_calls < tick + 1 \
			or typeof(proof.get("rejected_stage_calls")) != TYPE_INT or proof.rejected_stage_calls < 1 \
			or typeof(proof.get("rejected_context_calls")) != TYPE_INT or proof.rejected_context_calls < 1 \
			or proof.rejected_stage_calls > proof.native_stage_calls \
			or proof.rejected_context_calls > proof.native_context_calls \
			or proof.get("native_diagnostic_stage_call") != proof.native_stage_calls \
			or proof.get("native_diagnostic_context_call") != proof.native_context_calls:
		return "runtime-domain native ownership, input or stage coverage is incomplete"
	if proof.get("trial_equal") != true or proof.get("context_equal") != true \
			or proof.get("reference_result_empty") != true:
		return "runtime-domain rejected trial or sampled context differs"
	for field: String in ["trial", "context"]:
		var encoded: Variant = proof.get(field + "_bytes_hex")
		var expected_hash: Variant = proof.get(field + "_sha256")
		var native_encoded: Variant = proof.get("native_" + field + "_bytes_hex")
		var native_hash: Variant = proof.get("native_" + field + "_sha256")
		if typeof(encoded) != TYPE_STRING or encoded.is_empty() or encoded.length() > 4096 or encoded.length() % 2 != 0 \
				or not encoded.is_valid_hex_number() or typeof(expected_hash) != TYPE_STRING \
				or expected_hash.length() != 64 or not expected_hash.is_valid_hex_number() \
				or native_encoded != encoded or native_hash != expected_hash:
			return "runtime-domain typed " + field + " evidence is malformed"
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(encoded.hex_decode())
		if digest.finish().hex_encode() != expected_hash:
			return "runtime-domain typed " + field + " hash differs"
	var trial_payload: Variant = bytes_to_var(str(proof.trial_bytes_hex).hex_decode())
	var context_payload: Variant = bytes_to_var(str(proof.context_bytes_hex).hex_decode())
	if not _fleet_runtime_payload_valid(trial_payload, context_payload, tick):
		return "runtime-domain typed trial or context shape differs"
	var reference: Variant = proof.get("reference_cause")
	var native: Variant = proof.get("native_cause")
	if not reference is Dictionary or not native is Dictionary or reference.get("code") != GLOW_REVERSE_CODE \
			or native.get("code") != GLOW_REVERSE_CODE or reference.get("origin") != "feed_endpoint" \
			or native.get("origin") != "feed_endpoint" or typeof(native.get("feed_factor")) not in [TYPE_FLOAT, TYPE_INT] \
			or typeof(reference.get("feed_factor")) not in [TYPE_FLOAT, TYPE_INT] \
			or not is_finite(float(native.feed_factor)) or float(native.feed_factor) not in [0.0, 2.0]:
		return "runtime-domain rejecting branch is missing"
	var ref_values := PackedFloat64Array()
	var native_values := PackedFloat64Array()
	for field: String in ["feed_factor", "rpm", "demand_nm", "friction_nm", "prop_load_torque_nm",
			"axial_acceleration_rad_s2", "rotor_inertia_kg_m2"]:
		if typeof(reference.get(field)) not in [TYPE_FLOAT, TYPE_INT] \
				or typeof(native.get(field)) not in [TYPE_FLOAT, TYPE_INT] \
				or not is_finite(float(reference[field])) or not is_finite(float(native[field])):
			return "runtime-domain numeric branch evidence is malformed"
		ref_values.append(float(reference[field]))
		native_values.append(float(native[field]))
	var computed_demand: float = -ref_values[4] - ref_values[6] * ref_values[5]
	if var_to_bytes(ref_values) != var_to_bytes(native_values) or ref_values[1] != 0.0 \
			or ref_values[2] != computed_demand \
			or ref_values[3] <= 0.0 or ref_values[6] <= 0.0 or ref_values[2] >= -ref_values[3]:
		return "runtime-domain finite reverse-demand violation differs"
	return ""


## The reference stage is wrapped only for the known rejecting attempt. The native
## stage remains installed and its opt-in diagnostic records the actual C++ rejection.
func _fleet_runtime_run(reference: Node, native_session: Node, row: Dictionary,
		warmup: int, samples: int) -> Dictionary:
	var tick := _fleet_runtime_tick(row)
	if tick < 0 or warmup <= 0 or samples <= 0 or warmup + samples <= tick:
		return {error = "undeclared runtime-domain row or horizon"}
	var status: Dictionary = native_session.stage_backend_status()
	var identity: Variant = status.get("identity", {})
	var ref_status: Dictionary = reference.stage_backend_status()
	var ref_identity: Variant = ref_status.get("identity", {})
	var helper: Variant = native_session.get("_native_stage")
	var native: Object = helper.get("_native") if helper != null else null
	if not identity is Dictionary or native == null or not native.has_method("stage_stats") \
			or not native.has_method("reset_stage_stats") \
			or not native.has_method("set_stage_rejection_diagnostics") \
			or not native.has_method("stage_rejection_diagnostic"):
		return {error = "native stage, ownership or rejection diagnostic unavailable"}
	var model: Variant = native_session.sim.model
	var expected := {stage = model.stage, loads = model.loads, rotor_momentum = model.rotor_momentum,
		block_loads = model.block_loads, block_derivative = model.block_derivative,
		stage_rotor_momentum = model.stage_rotor_momentum}
	var ref_model: Variant = reference.sim.model
	var ref_expected := {stage = ref_model.stage, loads = ref_model.loads, rotor_momentum = ref_model.rotor_momentum,
		block_loads = ref_model.block_loads, block_derivative = ref_model.block_derivative,
		stage_rotor_momentum = ref_model.stage_rotor_momentum}
	var ref_aircraft_hash: String = str(reference.aircraft.get("input_identity", {}).get("sha256", ""))
	var native_aircraft_hash: String = str(native_session.aircraft.get("input_identity", {}).get("sha256", ""))
	if not ref_identity is Dictionary or ref_model.stage != GlowFlight.evaluate.bind(reference) \
			or ref_aircraft_hash.length() != 64 or not ref_aircraft_hash.is_valid_hex_number() \
			or ref_aircraft_hash != native_aircraft_hash \
			or not _fleet_backend_error(reference, NativeStage.BACKEND_REFERENCE, ref_identity, ref_expected, null, null).is_empty() \
			or not _fleet_backend_error(native_session, NativeStage.BACKEND_NATIVE, identity, expected, helper, native).is_empty() \
			or _fleet_frame(reference) != _fleet_frame(native_session):
		return {error = "initial reference/native state or native owner differs"}
	native.reset_stage_stats(false)
	var previous: Dictionary = helper.stage_stats()
	if not _fleet_stats_valid(previous):
		return {error = "native counters are malformed"}
	var reference_digest := HashingContext.new()
	var native_digest := HashingContext.new()
	reference_digest.start(HashingContext.HASH_SHA256)
	native_digest.start(HashingContext.HASH_SHA256)
	_fleet_hash_tick(reference_digest, reference)
	_fleet_hash_tick(native_digest, native_session)
	var reference_reads := 0
	var native_reads := 0
	for index in tick:
		var reads := _input_reads
		var ref_advanced := _advance(reference)
		var ref_delta := _input_reads - reads
		reference_reads += ref_delta
		reads = _input_reads
		var native_advanced := _advance(native_session)
		var native_delta := _input_reads - reads
		native_reads += native_delta
		var stats: Dictionary = helper.stage_stats()
		if not ref_advanced or not native_advanced or ref_delta != 1 or native_delta != 1 \
				or reference.sim.tick != index + 1 or native_session.sim.tick != index + 1 \
				or not _fleet_backend_error(reference, NativeStage.BACKEND_REFERENCE, ref_identity, ref_expected, null, null).is_empty() \
				or not _fleet_backend_error(native_session, NativeStage.BACKEND_NATIVE, identity, expected, helper, native).is_empty() \
				or not _fleet_stats_valid(stats) or not _native_tick_covered(previous, stats) \
				or _fleet_frame(reference) != _fleet_frame(native_session):
			return {error = "runtime-domain accepted prefix failed at tick %d" % (index + 1)}
		previous = stats
		_fleet_hash_tick(reference_digest, reference)
		_fleet_hash_tick(native_digest, native_session)
	var reference_before := _fleet_rollback_frame(reference)
	var native_before := _fleet_rollback_frame(native_session)
	var ref_sim: Node = reference.sim
	if ref_sim.model.stage != GlowFlight.evaluate.bind(reference) \
			or not _fleet_backend_error(reference, NativeStage.BACKEND_REFERENCE, ref_identity, ref_expected, null, null).is_empty():
		return {error = "reference evaluator or owner changed before the rejected attempt"}
	var original: Callable = ref_sim.model.stage
	var capture := {calls = 0, invalid = 0, trial = {}}
	var reference_wrapper := func(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float) -> Variant:
		capture.calls += 1
		var candidate: Variant = original.call(body, continuous, at)
		if not ref_sim._joint_stage_is_valid(candidate):
			capture.invalid += 1
			var deflection: Dictionary = reference._deflections(ref_sim.aux)
			var brake_index: int = reference.wheel_brake_input_index()
			var brake: float = ref_sim.inputs[brake_index] if brake_index >= 0 and brake_index < ref_sim.inputs.size() else 0.0
			capture.trial = {body = body.duplicate(), continuous = continuous.duplicate(), stage_time = at,
				aux = ref_sim.aux.duplicate(), inputs = ref_sim.inputs.duplicate(),
				deflections = PackedFloat64Array([deflection.elevator, deflection.aileron_right,
					deflection.aileron_left, deflection.rudder, deflection.get("flap", 0.0)]),
				tick_time = ref_sim.time(), brake = brake, throttle = reference.propulsion_throttle(),
				engine_running = reference.engine_running, injected_cut = reference.failure_power_cut_active(),
				result = candidate}
		return candidate
	ref_sim.model.stage = reference_wrapper
	var wrapped_expected := ref_expected.duplicate()
	wrapped_expected.stage = reference_wrapper
	native.set_stage_rejection_diagnostics(true)
	var reads := _input_reads
	var ref_advanced := _advance(reference)
	var ref_delta := _input_reads - reads
	reference_reads += ref_delta
	reads = _input_reads
	var native_advanced := _advance(native_session)
	var native_delta := _input_reads - reads
	native_reads += native_delta
	var final_stats: Dictionary = helper.stage_stats()
	var diagnostic: Variant = native.stage_rejection_diagnostic()
	if ref_advanced or native_advanced or ref_delta != 1 or native_delta != 1 \
			or capture.invalid != 1 or not capture.trial is Dictionary or capture.trial.is_empty() \
			or not diagnostic is Dictionary or diagnostic.is_empty() or not _fleet_stats_valid(final_stats):
		return {error = "runtime-domain rejecting attempt or diagnostic is missing"}
	var trial: Dictionary = capture.trial
	var ref_trial := [trial.body, trial.continuous, trial.stage_time]
	var native_trial := [diagnostic.get("body"), diagnostic.get("continuous"), diagnostic.get("stage_time")]
	var context_fields := ["aux", "inputs", "deflections", "tick_time", "brake", "throttle", "engine_running", "injected_cut"]
	var ref_context := []
	var native_context := []
	for field: String in context_fields:
		ref_context.append(trial.get(field))
		native_context.append(diagnostic.get(field))
	var trial_bytes := var_to_bytes(ref_trial)
	var context_bytes := var_to_bytes(ref_context)
	var native_trial_bytes := var_to_bytes(native_trial)
	var native_context_bytes := var_to_bytes(native_context)
	var factor: Variant = diagnostic.get("feed_factor")
	var reference_cause := _fleet_reverse_reference(reference, trial, float(factor)) \
		if typeof(factor) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(factor)) else {}
	var native_cause := {}
	for field: String in ["code", "origin", "feed_factor", "rpm", "demand_nm", "friction_nm", "prop_load_torque_nm",
			"axial_acceleration_rad_s2", "rotor_inertia_kg_m2"]:
		native_cause[field] = diagnostic.get(field)
	var proof := {code = diagnostic.get("code"), origin = diagnostic.get("origin"),
		accepted_ticks = tick, attempted_tick = tick + 1, requested_ticks = warmup + samples,
		warmup_completed = mini(warmup, tick), samples_completed = maxi(0, tick - warmup),
		prefix_boundaries = tick + 1, reference_prefix_sha256 = reference_digest.finish().hex_encode(),
		native_prefix_sha256 = native_digest.finish().hex_encode(), prefix_equal_every_tick = true,
		terminal_equal = _fleet_frame(reference) == _fleet_frame(native_session),
		reference_rollback = _fleet_rollback_frame(reference) == reference_before,
		native_rollback = _fleet_rollback_frame(native_session) == native_before,
		reference_end = _fleet_end(reference), native_end = _fleet_end(native_session),
		reference_identity = ref_identity.duplicate(true), reference_owner_retained = original == GlowFlight.evaluate.bind(reference) \
			and _fleet_backend_owner_error(reference, NativeStage.BACKEND_REFERENCE, ref_identity, \
				wrapped_expected, null, null).is_empty(),
		reference_aircraft_sha256 = ref_aircraft_hash, native_aircraft_sha256 = native_aircraft_hash,
		native_identity = identity.duplicate(true), native_owner_retained = _fleet_backend_owner_error(
			native_session, NativeStage.BACKEND_NATIVE, identity, expected, helper, native).is_empty(),
		native_covered_every_tick = true, reference_input_reads = reference_reads, native_input_reads = native_reads,
		native_stage_calls = final_stats.stage_calls, native_context_calls = final_stats.context_calls,
		rejected_stage_calls = int(final_stats.stage_calls) - int(previous.stage_calls),
		rejected_context_calls = int(final_stats.context_calls) - int(previous.context_calls),
		native_diagnostic_stage_call = diagnostic.get("stage_call"),
		native_diagnostic_context_call = diagnostic.get("context_call"),
		trial_equal = trial_bytes == native_trial_bytes, context_equal = context_bytes == native_context_bytes,
		reference_result_empty = trial.result is Dictionary and trial.result.is_empty(),
		trial_bytes_hex = trial_bytes.hex_encode(), trial_sha256 = _fleet_bytes_sha(ref_trial),
		native_trial_bytes_hex = native_trial_bytes.hex_encode(), native_trial_sha256 = _fleet_bytes_sha(native_trial),
		context_bytes_hex = context_bytes.hex_encode(), context_sha256 = _fleet_bytes_sha(ref_context),
		native_context_bytes_hex = native_context_bytes.hex_encode(), native_context_sha256 = _fleet_bytes_sha(native_context),
		reference_cause = reference_cause, native_cause = native_cause}
	if diagnostic.get("stage_call") != final_stats.stage_calls or diagnostic.get("context_call") != final_stats.context_calls \
			or proof.rejected_stage_calls != capture.calls:
		return {error = "runtime-domain diagnostic did not come from the actual rejecting stage"}
	var error := _fleet_runtime_proof_error(row, proof, warmup, samples)
	return {error = error, proof = proof}


func _fleet_runtime_case(row: Dictionary, warmup: int, samples: int) -> void:
	var reference := _build_fleet_session(row, NativeStage.BACKEND_REFERENCE)
	var native := _build_fleet_session(row, NativeStage.BACKEND_NATIVE)
	var outcome: Dictionary
	if not reference.get("ok", false) or not native.get("ok", false):
		outcome = {error = "runtime-domain setup failed: reference=%s; native=%s" \
			% [reference.get("reason", "ok"), native.get("reason", "ok")]}
	else:
		outcome = _fleet_runtime_run(reference.session, native.session, row, warmup, samples)
	if reference.get("ok", false): reference.session.free()
	if native.get("ok", false): native.session.free()
	var error: String = str(outcome.get("error", "runtime-domain proof missing"))
	var result: Dictionary = row.duplicate(true)
	result.status = "runtime-domain-refused" if error.is_empty() else "fail"
	result.reason = GLOW_REVERSE_CODE if error.is_empty() else error
	result.fingerprint_equal = false
	result.reference = {complete = false, requested = NativeStage.BACKEND_REFERENCE}
	result.native = {complete = false, requested = NativeStage.BACKEND_NATIVE}
	result.runtime_domain = outcome.get("proof", {})
	_report.fleet.append(result)
	_compare("fleet_runtime_domain_refusal", PackedFloat64Array([1.0]),
		PackedFloat64Array([1.0 if error.is_empty() else 0.0]), row)
	if not error.is_empty():
		_failures.append("fleet %s/%s/%s/soft=%s runtime-domain proof: %s" \
			% [row.aircraft, row.case, row.weather, row.soft_hull, error])
	print("NK3_FLEET aircraft=%s battery=%s case=%s weather=%s soft_hull=%s status=%s reason=%s" \
		% [row.aircraft, row.battery, row.case, row.weather, row.soft_hull, result.status, result.reason])


func _fleet_case(row: Dictionary, warmup: int, samples: int) -> void:
	if row.get("expected") == "runtime-domain-refusal" and warmup + samples > _fleet_runtime_tick(row):
		_fleet_runtime_case(row, warmup, samples)
		return
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
