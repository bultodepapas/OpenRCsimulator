## NK-3: rotating wheel layouts beyond the former native-only limits.
## Run against an installed, verified candidate. Reference fallback is a failure.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const WheelProfiles := preload("res://physics/wheel_profiles.gd")
const Flight := preload("res://sim/flight_session.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const WeatherAdapter := preload("res://sim/native/weather_adapter.gd")
const LiquidAdapter := preload("res://sim/native/liquid_stage_adapter.gd")

const TICKS := 3
var checks := 0
var failures := 0


func _check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_run.call_deferred()


## These deliberately duplicated contacts isolate software layout boundaries;
## they are not intended to represent a physically validated aircraft.
func _source_and_profile(count: int, liquid := false) -> Dictionary:
	var source_path := "res://data/aircraft/p51d_mustang_120.json" if liquid \
		else "res://data/aircraft/jensen_ugly_stik_60.json"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WheelProfiles.DEFAULT_PATH))
	var source_contacts: Array = raw.landing_gear.contacts.duplicate(true)
	var source_profiles: Dictionary = profiles.profiles[raw.id].contacts
	raw.id = "native-admission-%s-%d-wheels" % ["liquid" if liquid else "prescribed", count]
	var contacts := []
	var wheel_entries := {}
	for index in count:
		var original: Dictionary = source_contacts[0 if index >= 3 else index]
		var name := str(original.name) + "_admission_%d" % index
		var copies: int = count - 2 if index == 0 or index >= 3 else 1
		var contact: Dictionary = original.duplicate(true)
		contact.name = name
		contact.id = "wheel_admission_%d" % index
		# Keep most duplicate contacts clear of the initial runway pose. Their
		# nonzero wheel speeds are still exercised by the stage component probe.
		if index >= 3:
			contact.position.value[2] = float(contact.position.value[2]) + 0.2
			if liquid:
				for point in range(2, contact.retraction_path.value.size(), 3):
					contact.retraction_path.value[point] = float(contact.retraction_path.value[point]) + 0.2
		contact.stiffness.value = float(original.stiffness.value) / copies
		contact.damping.value = float(original.damping.value) / sqrt(float(copies))
		contacts.append(contact)
		var wheel: Dictionary = source_profiles[original.name].duplicate(true)
		wheel.wheel_inertia.value = float(wheel.wheel_inertia.value) / copies
		wheel_entries[name] = wheel
	raw.landing_gear.contacts = contacts
	var checked: Dictionary = AircraftData.validate_and_derive(raw)
	_check("%d-contact aircraft validates" % count, checked.get("ok", false), str(checked.get("errors", [])))
	if not checked.get("ok", false): return {}
	var path := "user://native-wheel-admission-%d-%d.json" % [OS.get_process_id(), count]
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check("%d-wheel temporary profile opened" % count, file != null)
	if file == null: return {}
	file.store_string(JSON.stringify({format = WheelProfiles.FORMAT,
		profiles = {raw.id: {description = "native admission boundary", contacts = wheel_entries}}}))
	file.close()
	var profiled: Dictionary = WheelProfiles.apply_to_model(checked.model, path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check("%d-wheel profile validates" % count, profiled.get("ok", false), str(profiled.get("errors", [])))
	if not profiled.get("ok", false): return {}
	checked.model = profiled.model
	checked.wheel_profile_identity = profiled.identity
	checked.input_identity = {format = AircraftData.FORMAT, sha256 = JSON.stringify(raw, "", true, true).sha256_text()}
	return checked


func _flight(data: Dictionary, backend: String, count: int) -> Node:
	var session := Flight.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.crash_auto_restart = false
	_check("%d wheels select %s" % [count, backend], session.setup_stage_backend(backend))
	session.setup("synthetic://wheel-admission", str(data.model.id), data)
	_check("%d wheels start %s" % [count, backend], session.is_flyable() and not session.sim.paused
		and session.sim.fault_reason.is_empty() and session.crash.is_empty(),
		str({start = session.start_error, pause = session.pause_reason, backend = session.stage_backend_status()}))
	_check("%d wheels have full continuous layout" % count, session.wheel_count() == count \
		and session.sim.continuous.size() == session.wheel_index() + count + (2 if session.liquid_fuel_is_active() else 0))
	return session


func _frame(session: Node) -> PackedByteArray:
	var sim: Node = session.sim
	return var_to_bytes([sim.tick, sim.state, sim.previous, sim.aux, sim.continuous,
		sim.inputs, sim.last_loads, sim.modes, sim.last_events])


func _owns(session: Node) -> bool:
	var status: Dictionary = session.stage_backend_status()
	var helper: Variant = session._native_stage
	return status.get("requested") == NativeStage.BACKEND_NATIVE \
		and status.get("identity", {}).get("backend") == NativeStage.BACKEND_NATIVE \
		and helper != null and helper.owns_stage(session)


func _tape(reference: Node, candidate: Node, count: int) -> void:
	var label := "%d wheels (%s)" % [count, session_family(reference)]
	var owns := _owns(candidate)
	_check(label + " actually owns native stage", owns, str(candidate.stage_backend_status()))
	_check(label + " reference backend", reference.stage_backend_identity().get("backend") == NativeStage.BACKEND_REFERENCE)
	var same := _frame(reference) == _frame(candidate)
	var complete := true
	var covered := owns
	var previous := {}
	if owns:
		candidate._native_stage._native.reset_stage_stats(false)
		previous = candidate._native_stage.stage_stats()
	for tick in TICKS:
		reference.sim.step()
		candidate.sim.step()
		complete = complete and reference.sim.tick == tick + 1 and candidate.sim.tick == tick + 1 \
			and not reference.sim.paused and not candidate.sim.paused and reference.sim.fault_reason.is_empty() \
			and candidate.sim.fault_reason.is_empty() and reference.crash.is_empty() and candidate.crash.is_empty()
		same = same and _frame(reference) == _frame(candidate)
		if owns:
			var current: Dictionary = candidate._native_stage.stage_stats()
			covered = covered and _owns(candidate) \
				and int(current.get("context_calls", 0)) - int(previous.get("context_calls", 0)) >= 1 \
				and int(current.get("stage_calls", 0)) - int(previous.get("stage_calls", 0)) >= 4
			previous = current
	_check(label + " exact healthy tape with native context and RK calls", complete and same and covered,
		str({same = same, complete = complete, covered = covered, stats = previous,
			reference_fault = reference.sim.fault_reason, native_fault = candidate.sim.fault_reason}))
	if not (complete and same and covered): return
	var reference_cp: Dictionary = reference.checkpoint()
	var candidate_cp: Dictionary = candidate.checkpoint()
	var reference_tape := []
	var candidate_tape := []
	for _tick in TICKS:
		reference.sim.step()
		candidate.sim.step()
		reference_tape.append(_frame(reference))
		candidate_tape.append(_frame(candidate))
		complete = complete and not reference.sim.paused and not candidate.sim.paused \
			and reference.sim.fault_reason.is_empty() and candidate.sim.fault_reason.is_empty()
		same = same and reference_tape.back() == candidate_tape.back() and _owns(candidate)
	var restored: bool = reference.restore_checkpoint(reference_cp) and candidate.restore_checkpoint(candidate_cp)
	_check(label + " restores matching-backend checkpoints", restored)
	var replayed: bool = restored
	if restored:
		var replay_stats := {}
		if _owns(candidate):
			candidate._native_stage._native.reset_stage_stats(false)
			replay_stats = candidate._native_stage.stage_stats()
		else:
			replayed = false
		for tick in TICKS:
			reference.sim.step()
			candidate.sim.step()
			# Restore intentionally leaves the simulation paused; direct step is
			# the supported checkpoint replay path.
			replayed = replayed and _owns(candidate) \
				and reference.sim.tick == reference_cp.simulation.tick + tick + 1 \
				and candidate.sim.tick == candidate_cp.simulation.tick + tick + 1 \
				and _frame(reference) == reference_tape[tick] and _frame(candidate) == candidate_tape[tick]
			if _owns(candidate):
				var current: Dictionary = candidate._native_stage.stage_stats()
				replayed = replayed and int(current.get("context_calls", 0)) - int(replay_stats.get("context_calls", 0)) >= 1 \
					and int(current.get("stage_calls", 0)) - int(replay_stats.get("stage_calls", 0)) >= 4
				replay_stats = current
	_check(label + " replays checkpoints exactly with native ownership", complete and same and replayed)


func _set_context(native: Object, session: Node) -> bool:
	var d: Dictionary = session._deflections(session.sim.aux)
	return native.set_tick_context(session.sim.aux, session.sim.inputs,
		PackedFloat64Array([d.elevator, d.aileron_right, d.aileron_left, d.rudder, d.get("flap", 0.0)]), session.sim.time())


func session_family(session: Node) -> String:
	return "liquid" if session.liquid_fuel_is_active() else "prescribed"


func _same_stage(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty() or not a.has_all(["loads", "derivative", "rotor_momentum"]) \
			or not b.has_all(["loads", "derivative", "rotor_momentum"]): return false
	for key: String in ["loads", "derivative", "rotor_momentum"]:
		if var_to_bytes(a[key]) != var_to_bytes(b[key]): return false
	if a.has("body_derivative") != b.has("body_derivative"): return false
	if a.has("body_derivative") and var_to_bytes(a.body_derivative) != var_to_bytes(b.body_derivative): return false
	return true


func _same_preview(a: Dictionary, b: Dictionary, count: int) -> bool:
	if not a.has("stage_context") or not b.has("stage_context"): return false
	var x: Dictionary = a.stage_context
	var y: Dictionary = b.stage_context
	if not x.has_all(["air", "pre_reaction_loads", "wheel_derivative"]) \
			or not y.has_all(["air", "pre_reaction_loads", "wheel_derivative"]): return false
	if x.wheel_derivative.size() != count or y.wheel_derivative.size() != count: return false
	for key: String in ["pre_reaction_loads", "wheel_derivative"]:
		if var_to_bytes(x[key]) != var_to_bytes(y[key]): return false
	for key: String in ["v_air", "V", "alpha", "beta", "qbar"]:
		if not x.air.has(key) or not y.air.has(key) or var_to_bytes(x.air[key]) != var_to_bytes(y.air[key]): return false
	return true


## Exercise loaded ground and full stages with one kernel repeatedly prepared
## across small and large validated layouts, including stale-size refusals.
func _prepared_check(native: Object, session: Node, count: int, label: String) -> void:
	var config := WeatherAdapter.config_for(session)
	_check(label + " configuration", not config.is_empty())
	if config.is_empty(): return
	var result: Dictionary = native.prepare_stage(config)
	_check(label + " prepares", result.get("ok", false), str(result))
	if not result.get("ok", false): return
	_check(label + " installs context", _set_context(native, session))
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var values: PackedFloat64Array = session.sim.continuous.duplicate()
	_check(label + " preview accepts exact layout", native.set_preview_context(state, values, true))
	var too_short := values.duplicate()
	too_short.resize(too_short.size() - 1)
	var too_long := values.duplicate()
	too_long.append(1.0)
	_check(label + " preview rejects stale size", not native.set_preview_context(state, too_short, true))
	_check(label + " rejects short and long stage inputs", native.stage(state, too_short, session.sim.time()).is_empty()
		and native.stage(state, too_long, session.sim.time()).is_empty())
	_check(label + " rejects short and long ground inputs", not native.ground_component(state, too_short).get("ok", true)
		and not native.ground_component(state, too_long).get("ok", true))
	_check(label + " airborne stage is exact", _same_stage(session._wheel_evaluate(state, values, session.sim.time()),
		native.stage(state, values, session.sim.time())))
	# Bring the aircraft down onto the wheel contacts and use distinct nonzero
	# wheel speeds so copying and indexing all entries matter.
	state[2] = 0.02
	state[3] = 1.0
	for index in count:
		values[session.wheel_index() + index] = 2.0 + float(index % 7) * 0.25
	var reference: Dictionary = session._ground_evaluation(state, session.sim.aux, values)
	var actual: Dictionary = native.ground_component(state, values)
	var loaded: bool = reference.get("ok", false) and not reference.get("loads", PackedFloat64Array()).is_empty() \
		and reference.get("derivative", PackedFloat64Array()).size() == count
	if loaded:
		for rate: float in reference.derivative: loaded = loaded and is_finite(rate) and rate != 0.0
	_check(label + " exercises every loaded wheel", loaded, str(reference))
	var equal: bool = loaded and actual.get("ok", false) \
		and var_to_bytes(reference.loads) == var_to_bytes(actual.get("loads")) \
		and var_to_bytes(reference.derivative) == var_to_bytes(actual.get("derivative"))
	_check(label + " loaded contact and all wheel rates are exact", equal)
	_check(label + " loaded full stage is exact", _same_stage(session._wheel_evaluate(state, values, session.sim.time()),
		native.stage(state, values, session.sim.time())))


func _malformed(native: Object, session: Node) -> void:
	var config := WeatherAdapter.config_for(session)
	var bad_layouts := [
		{wheel_count = -1}, {wheel_count = session.wheel_count() + 1},
		{anchor_count = -1}, {anchor_count = 715827883}, {anchor_count = 2147483647},
		{anchors = 2147483647}, {aux_size = 2147483648},
		{wheel_index = 2147483647}, {rotor_index = 2147483647},
	]
	for bad: Dictionary in bad_layouts:
		var good: Dictionary = native.prepare_stage(config)
		_check("malformed control prepares", good.get("ok", false), str(good))
		if not good.get("ok", false): continue
		_check("malformed control has context", _set_context(native, session))
		var altered: Dictionary = config.duplicate(true)
		for key: Variant in bad: altered.layout[key] = bad[key]
		var refused: Dictionary = native.prepare_stage(altered)
		_check("malformed layout refused " + str(bad), not refused.get("ok", true), str(refused))
		_check("refusal disarms stale stage " + str(bad),
			not _set_context(native, session) and native.stage(session.sim.state, session.sim.continuous, session.sim.time()).is_empty()
			and not native.ground_component(session.sim.state, session.sim.continuous).get("ok", true))


## The liquid family has one source state before the wheels and two inventory
## states after them. It also uses the preview capture during normal handoff.
func _liquid_prepared(native: Object, session: Node, count: int) -> void:
	var label := "%d liquid wheels" % count
	var config := LiquidAdapter.config_for(session)
	_check(label + " configuration", not config.is_empty())
	if config.is_empty(): return
	var result: Dictionary = native.prepare_stage(config)
	_check(label + " prepares", result.get("ok", false), str(result))
	if not result.get("ok", false): return
	var state: PackedFloat64Array = session.sim.state
	var values: PackedFloat64Array = session.sim.continuous
	_check(label + " has all source, wheel and inventory states", values.size() == count + 3)
	_check(label + " reference captures preview", session._should_capture_substep_context(state, values, session.sim.time()))
	_check(label + " context and preview accept full layout",
		LiquidAdapter.set_context(session, native, session.sim.aux, session.sim.inputs, session.sim.time()) \
		and native.set_preview_context(state, values, true))
	var reference: Dictionary = session.sim.model.stage.call(state, values, session.sim.time())
	var actual: Dictionary = native.stage(state, values, session.sim.time())
	_check(label + " full prepared stage is exact", _same_stage(reference, actual))
	_check(label + " captured preview is exact", _same_preview(reference, actual, count))
	var malformed: Dictionary = config.duplicate(true)
	malformed.layout.liquid_index += 1
	var refused: Dictionary = native.prepare_stage(malformed)
	_check(label + " rejects inconsistent inventory index", not refused.get("ok", true), str(refused))
	_check(label + " invalid prepare disarms stage", native.stage(state, values, session.sim.time()).is_empty())


## A validated unprofiled airframe has no rotating-wheel or source state. The
## binding's public preview API must also handle an enabled capture with this
## genuinely empty continuous array, including after a larger preparation.
func _empty_preview(native: Object) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var data: Dictionary = AircraftData.validate_and_derive(raw)
	_check("body-only unprofiled aircraft validates", data.get("ok", false), str(data.get("errors", [])))
	if not data.get("ok", false): return
	data.input_identity = {format = AircraftData.FORMAT, sha256 = JSON.stringify(raw, "", true, true).sha256_text()}
	var session := _flight(data, NativeStage.BACKEND_REFERENCE, 0)
	var body_only: bool = session.sim.continuous.is_empty() and not session.sim.model.stage.is_valid() \
		and session.sim.model.loads.is_valid()
	_check("unprofiled session has body-only layout", body_only)
	_check("unfielded session has empty ground table", session.ground_surfaces.is_empty())
	if not body_only:
		session.free()
		return
	var config := WeatherAdapter.config_for(session)
	var prepared: Dictionary = native.prepare_stage(config)
	_check("body-only stage prepares after larger layout", prepared.get("ok", false), str(prepared))
	if prepared.get("ok", false):
		_check("body-only tick context", _set_context(native, session))
		var body: PackedFloat64Array = session.sim.state
		var empty := PackedFloat64Array()
		_check("body-only accepts enabled empty preview", native.set_preview_context(body, empty, true))
		var expected: PackedFloat64Array = session.sim.model.loads.call(body, session.sim.time())
		var actual: Dictionary = native.stage(body, empty, session.sim.time())
		_check("body-only empty stage has exact loads", not expected.is_empty() \
			and var_to_bytes(expected) == var_to_bytes(actual.get("loads")) \
			and var_to_bytes(expected) == var_to_bytes(native.body_loads(body, session.sim.time())))
		_check("body-only accepts disabled empty preview", native.set_preview_context(body, empty, false))
		var ground: Dictionary = native.prepare_ground({}, empty, {}, true)
		_check("empty table validates and prepares as ground", native.surface_table_is_valid(empty) \
			and ground.get("ok", false) and ground.get("surfaces_valid", false), str(ground))
	session.free()


func _run() -> void:
	var library: Dictionary = NativeStage.library_status()
	_check("verified native library", library.get("ok", false), str(library))
	if not library.get("ok", false): _done(); return
	var references := {}
	for count: int in [16, 17, 65]:
		var data := _source_and_profile(count)
		if data.is_empty(): continue
		var reference := _flight(data, NativeStage.BACKEND_REFERENCE, count)
		var candidate := _flight(data, NativeStage.BACKEND_NATIVE, count)
		_tape(reference, candidate, count)
		references[count] = reference
		candidate.free()
	var liquid_references := {}
	for count: int in [16, 65]:
		var liquid_data := _source_and_profile(count, true)
		if liquid_data.is_empty(): continue
		var liquid_reference := _flight(liquid_data, NativeStage.BACKEND_REFERENCE, count)
		var liquid_candidate := _flight(liquid_data, NativeStage.BACKEND_NATIVE, count)
		_tape(liquid_reference, liquid_candidate, count)
		liquid_references[count] = liquid_reference
		liquid_candidate.free()
	if references.size() == 3:
		var native: Object = ClassDB.instantiate(NativeStage.NATIVE_CLASS)
		for count: int in [16, 65, 17, 16, 65]:
			_prepared_check(native, references[count], count, "reprepare %d" % count)
		if liquid_references.size() == 2:
			_liquid_prepared(native, liquid_references[16], 16)
			_liquid_prepared(native, liquid_references[65], 65)
			_prepared_check(native, references[16], 16, "reprepare after liquid")
		_malformed(native, references[16])
		_prepared_check(native, references[65], 65, "reprepare after malformed")
		_empty_preview(native)
	for reference: Node in references.values(): reference.free()
	for reference: Node in liquid_references.values(): reference.free()
	_done()


func _done() -> void:
	print("NK3_NATIVE_WHEEL_ADMISSION verdict=", "pass" if failures == 0 else "fail",
		" checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
