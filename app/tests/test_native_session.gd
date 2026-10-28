## NK-3: session-owned native stage selection, lifecycle and exact reference parity.
## CI without a library (or with a stale receipt) exercises the explicit reference fallback.
## An independently prepared helper gates the native branch; an unexpected session fallback fails.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const NativeStage := preload("res://sim/native_stage.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Weather := preload("res://physics/wind_config.gd")

const STIK := "jensen-das-ugly-stik-60"
const P51 := "p51d-mustang-120"
const TICKS := 960

var checks := 0
var failures := 0
var _native_exercised := false
var field := {}
var alternate_field := {}
var lake := {}


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	call_deferred("run_all")


func runway(mode: String, id := STIK) -> Node:
	var session: Node = Flight.new()
	session.input_enabled = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	check("select " + mode, session.setup_stage_backend(mode))
	session.setup(str(Catalog.entry(id).data), id)
	check(id + " setup is flyable", session.is_flyable(), str(session.pause_reason))
	check("field and lake accept " + mode, session.set_field(field) and session.set_lake_context(lake))
	session.start_choice = Flight.START_RUNWAY
	session.reset()
	check("runway reset succeeds " + mode, session.sim.tick == 0 and session.is_flyable()
		and session.crash.is_empty(), str(session.start_error))
	session.read_raw = func() -> Dictionary:
		var tick: int = session.sim.tick
		return {roll = 0.0, pitch = 0.06 if tick >= 600 else 0.0,
			yaw = 0.1 if tick >= 200 and tick < 260 else 0.0,
			throttle = clampf(-1.0 + 2.0 * tick / 240.0, -1.0, 1.0)}
	return session


func advance(session: Node) -> bool:
	var tick: int = session.sim.tick
	session._physics_process(session.sim.dt())
	session.sim._physics_process(session.sim.dt())
	return session.sim.tick == tick + 1


func physical(session: Node) -> PackedByteArray:
	return var_to_bytes([session.sim.tick, session.sim.state, session.sim.previous, session.sim.aux,
		session.sim.continuous, session.sim.inputs, session.sim.last_loads, session.sim.modes])


func same_steps(native: Node, reference: Node, count: int, label: String) -> void:
	var mismatches := 0
	var first := -1
	var advanced := 0
	for index: int in count:
		var n_ok := advance(native)
		var r_ok := advance(reference)
		if not n_ok or not r_ok:
			break
		advanced += 1
		if physical(native) != physical(reference):
			mismatches += 1
			if first < 0: first = index + 1
	check(label + " completes", advanced == count, "%d/%d; %s / %s" %
		[advanced, count, native.sim.fault_reason, reference.sim.fault_reason])
	check(label + " is byte-identical each tick", advanced == count and mismatches == 0,
		"mismatches=%d first=%d" % [mismatches, first])


func selection() -> void:
	var session := Flight.new()
	check("default selects reference", session.stage_backend_status().requested == NativeStage.BACKEND_REFERENCE
		and session.stage_backend_identity() == NativeStage.reference_identity())
	session.input_enabled = false
	session.setup(str(Catalog.entry(STIK).data), STIK)
	var old_model: RefCounted = session.sim.model
	var old_stage: Callable = old_model.stage
	var before := physical(session)
	check("reference session starts on reference evaluator", session.is_flyable()
		and session.stage_backend_identity() == NativeStage.reference_identity()
		and old_stage.get_method() == &"_wheel_evaluate" and not session.checkpoint().has("stage_backend"))
	check("backend choice is immutable after setup", not session.setup_stage_backend(NativeStage.BACKEND_NATIVE)
		and session.stage_backend_status().requested == NativeStage.BACKEND_REFERENCE
		and session.stage_backend_identity() == NativeStage.reference_identity()
		and session.sim.model == old_model and session.sim.model.stage == old_stage and physical(session) == before)
	session.free()
	var choice := Flight.new()
	check("unknown selection is refused", not choice.setup_stage_backend("unknown")
		and choice.stage_backend_status().requested == NativeStage.BACKEND_REFERENCE)
	check("valid choices can change before setup", choice.setup_stage_backend(NativeStage.BACKEND_NATIVE)
		and choice.setup_stage_backend(NativeStage.BACKEND_REFERENCE))
	choice.free()


func trajectory(native: Node, reference: Node) -> void:
	check("native start installs the owned stage", native.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE
		and native._native_stage != null and native._native_stage.owns_stage(native))
	var before := physical(native)
	var helper: RefCounted = native._native_stage
	var stage: Callable = native.sim.model.stage
	check("native selection cannot change after setup", not native.setup_stage_backend(NativeStage.BACKEND_REFERENCE)
		and native.stage_backend_status().requested == NativeStage.BACKEND_NATIVE
		and native._native_stage == helper and native.sim.model.stage == stage and physical(native) == before)
	check("native and reference reset bytes agree", physical(native) == physical(reference))
	same_steps(native, reference, TICKS, "takeoff roll")
	check("takeoff tape actually moved aircraft", absf(native.sim.state[3]) > 1.0)
	var old_context := var_to_bytes([native.sim.aux, native.sim.inputs])
	native.reset()
	reference.reset()
	check("reset replaces old tick context", native.sim.tick == 0 and reference.sim.tick == 0
		and old_context != var_to_bytes([native.sim.aux, native.sim.inputs]))
	check("reset tick-zero loads and all physical bytes match", physical(native) == physical(reference)
		and native.is_flyable() and reference.is_flyable())
	same_steps(native, reference, 48, "post-reset continuation")


func checkpoints(native: Node, reference: Node) -> void:
	var native_cp: Dictionary = native.checkpoint()
	var ref_cp: Dictionary = reference.checkpoint()
	check("native checkpoint wraps its physical format and backend", native_cp.get("format") == Flight.NATIVE_CHECKPOINT_FORMAT
		and native_cp.get("stage_physics_format") == ref_cp.get("format")
		and native_cp.get("stage_backend") == native.stage_backend_identity()
		and native_cp.get("simulation") == ref_cp.get("simulation"))
	var n_before := physical(native)
	var r_before := physical(reference)
	var n_helper: RefCounted = native._native_stage
	var n_model: RefCounted = native.sim.model
	var wrong: Dictionary = native_cp.duplicate(true)
	wrong.stage_backend.binary_sha256 = "0".repeat(64) if wrong.stage_backend.binary_sha256 != "0".repeat(64) else "1".repeat(64)
	check("different native binary refuses restore", not native.restore_checkpoint(wrong)
		and physical(native) == n_before and native._native_stage == n_helper and native.sim.model == n_model
		and native._native_stage.owns_stage(native))
	check("native rejects reference checkpoint", not native.restore_checkpoint(ref_cp)
		and physical(native) == n_before and native._native_stage == n_helper and native._native_stage.owns_stage(native))
	check("reference rejects native checkpoint", not reference.restore_checkpoint(native_cp)
		and physical(reference) == r_before and reference.stage_backend_identity() == NativeStage.reference_identity())
	var malformed: Dictionary = native_cp.duplicate(true)
	malformed.erase("stage_physics_format")
	check("native wrapper without inner format refuses restore", not native.restore_checkpoint(malformed)
		and physical(native) == n_before and native._native_stage == n_helper and native._native_stage.owns_stage(native))
	same_steps(native, reference, 16, "pre-restore continuation")
	check("matching native and reference checkpoints restore", native.restore_checkpoint(native_cp)
		and reference.restore_checkpoint(ref_cp))
	check("restore reinstates saved bytes and native identity", physical(native) == n_before
		and physical(reference) == r_before and native.stage_backend_identity() == native_cp.stage_backend)
	# Restore is intentionally paused. Replay feeds the same stored inputs directly to sim.step().
	var equal := true
	var advanced := 0
	for index: int in 32:
		for session: Node in [native, reference]:
			session.sim.inputs[0] = 0.05 if index < 16 else -0.04
			session.sim.inputs[1] = 0.02
			session.sim.inputs[2] = -0.01
			session.sim.inputs[3] = 0.35
			session.sim.step()
		if native.sim.tick != native_cp.simulation.tick + index + 1 or reference.sim.tick != ref_cp.simulation.tick + index + 1:
			break
		advanced += 1
		equal = equal and physical(native) == physical(reference)
	check("restored tape stays byte-identical", advanced == 32 and equal,
		"%d/32; %s / %s" % [advanced, native.sim.fault_reason, reference.sim.fault_reason])


func rejected_reset() -> void:
	var session := runway(NativeStage.BACKEND_NATIVE)
	var model: RefCounted = session.sim.model
	model.aux_size = session.sim.aux.size()
	model.continuous_size = session.sim.continuous.size()
	model.modes_size = session.sim.modes.size()
	model.state_layout_identity = "native-session-reset-fixture-v1"
	var reject := [false]
	var calls := [0]
	var observed_candidate := [false]
	var old_helper: RefCounted = session._native_stage
	model.state_validator = func(_frame: Dictionary, context: Dictionary) -> bool:
		if reject[0] and context.tick == 0:
			calls[0] += 1
			observed_candidate[0] = session._native_stage != old_helper and session._native_stage != null
			return false
		return true
	check("reset fixture installs explicit layout", session.sim.reset(session.sim.state.duplicate()))
	for index: int in 8: session.sim.step()
	check("reset fixture advances", session.sim.tick == 8 and not session.checkpoint().is_empty())
	var before := physical(session)
	var saved := var_to_bytes(session.checkpoint())
	var old_stage: Callable = model.stage
	reject[0] = true
	session.reset()
	reject[0] = false
	check("reset is rejected after a new helper was staged", calls[0] > 0 and observed_candidate[0]
		and not session.start_error.is_empty())
	check("rejected reset retains helper, model and stage", session._native_stage == old_helper
		and session.sim.model == model and model.stage == old_stage and old_helper.owns_stage(session))
	check("rejected reset retains checkpoint and physical bytes", physical(session) == before
		and var_to_bytes(session.checkpoint()) == saved)
	session.sim.step()
	check("old helper flies after reset rollback", session.sim.tick == 9 and session.sim.fault_reason.is_empty())
	session.free()


func reprepare() -> void:
	var native := runway(NativeStage.BACKEND_NATIVE)
	var reference := runway(NativeStage.BACKEND_REFERENCE)
	# Exercise meaningful accepted configuration changes at tick zero, where lake replacement is permitted.
	for change: String in ["lake-clear", "lake-install", "soft-off", "soft-on", "field"]:
		var old_helper: RefCounted = native._native_stage
		var old_surfaces: PackedFloat64Array = native.ground_surfaces.duplicate()
		var n_ok := true
		var r_ok := true
		match change:
			"lake-clear":
				n_ok = native.set_lake_context({})
				r_ok = reference.set_lake_context({})
			"lake-install":
				n_ok = native.set_lake_context(lake)
				r_ok = reference.set_lake_context(lake)
			"soft-off":
				native.soft_hull_contacts = false
				reference.soft_hull_contacts = false
			"soft-on":
				native.soft_hull_contacts = true
				reference.soft_hull_contacts = true
			"field":
				n_ok = native.set_field(alternate_field)
				r_ok = reference.set_field(alternate_field)
				check("field replacement changes physical surfaces", native.ground_surfaces != old_surfaces)
		check(change + " accepted and re-prepared", n_ok and r_ok and native._native_stage != old_helper
			and native.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE
			and native._native_stage.configuration_matches(native), str(native.stage_backend_status()))
		native.reset()
		reference.reset()
		check(change + " reset loads match", physical(native) == physical(reference))
	# Run after the final field/lake/hull combination, rather than comparing only setup metadata.
	same_steps(native, reference, 24, "re-prepared field/lake/hull")
	native.free()
	reference.free()


func stale_mutation() -> void:
	var session := runway(NativeStage.BACKEND_NATIVE)
	for index: int in 8: session.sim.step()
	var helper: RefCounted = session._native_stage
	var engine: Object = helper.get("_native")
	var stats: Dictionary = engine.call("stage_stats")
	var before := physical(session)
	var old_mass: float = session.aircraft.model.mass_kg
	session.aircraft.model.mass_kg = old_mass + 0.01 # in-place bypass of accepted boundaries
	check("in-place model edit refuses checkpoint", session.checkpoint().is_empty())
	session.sim.step()
	var after: Dictionary = engine.call("stage_stats")
	check("in-place edit faults before native context or stage", session.sim.tick == 8
		and physical(session) == before and not session.sim.fault_reason.is_empty()
		and not session.stage_backend_error.is_empty()
		and after.stage_calls == stats.stage_calls and after.context_calls == stats.context_calls)
	session.aircraft.model.mass_kg = old_mass
	session.reset()
	check("reset after reverting edit restores a native flight", session.is_flyable()
		and session.stage_backend_identity().backend == NativeStage.BACKEND_NATIVE and session.sim.tick == 0)
	session.free()


func publication_guard(expect_native: bool) -> void:
	for field_name: String in ["ground_surfaces", "airframe_surfaces"]:
		var session := runway(NativeStage.BACKEND_NATIVE)
		for index: int in 4: session.sim.step()
		var before: PackedFloat64Array = session.get(field_name).duplicate()
		var attempted := [0]
		var installed := [null]
		var stats_at_publication := [{}]
		session.resetting.connect(func() -> void:
			attempted[0] += 1
			installed[0] = session._native_stage
			if installed[0] != null:
				stats_at_publication[0] = installed[0].get("_native").call("stage_stats")
			session.set(field_name, PackedFloat64Array()), CONNECT_ONE_SHOT)
		session.reset()
		check(field_name + " publication attempted exactly once", attempted[0] == 1)
		check(field_name + " publication cannot change prepared data", session.get(field_name) == before
			and session._native_stage == installed[0]
			and session.sim.tick == 0 and session.sim.paused and not session.sim.fault_reason.is_empty())
		if expect_native:
			check(field_name + " retains its prepared native helper", session._native_stage != null
				and session._native_stage.configuration_matches(session))
			if session._native_stage != null:
				var engine: Object = session._native_stage.get("_native")
				session.sim.step()
				var after: Dictionary = engine.call("stage_stats")
				check(field_name + " rejected publication cannot advance native", session.sim.tick == 0
					and after.stage_calls == stats_at_publication[0].stage_calls
					and after.context_calls == stats_at_publication[0].context_calls)
		else:
			session.sim.step()
			check(field_name + " rejected publication cannot advance reference", session.sim.tick == 0)
		session.free()


func old_helper() -> void:
	var session := runway(NativeStage.BACKEND_NATIVE)
	var old: RefCounted = session._native_stage
	var replacement := VehicleModel.new()
	replacement.stage = Callable(session, "_wheel_evaluate")
	replacement.pre_tick = Callable(session, "_kernel_pre_step")
	check("replacement model installs", session.sim.set_model(replacement))
	var new_stage: Callable = replacement.stage
	var new_pre_tick: Callable = replacement.pre_tick
	old.uninstall(session)
	check("old helper cannot overwrite a replacement model", session.sim.model == replacement
		and replacement.stage == new_stage and replacement.pre_tick == new_pre_tick)
	session.free()


func unsupported_weather(expect_native: bool) -> void:
	var session := runway(NativeStage.BACKEND_NATIVE)
	var reference := runway(NativeStage.BACKEND_REFERENCE)
	check("calm custom atmosphere selection accepts", reference.setup_weather(Weather.preset("cool-dense")))
	reference.reset()
	var calm_checkpoint: Dictionary = reference.checkpoint()
	check("reference checkpoint is calm and carries custom atmosphere", reference.is_flyable()
		and reference.weather_is_calm() and calm_checkpoint.has("weather_config"))
	if expect_native:
		var would_promote: Dictionary = NativeStage.new().prepare(reference)
		check("calm custom reference checkpoint would otherwise qualify for native", would_promote.ok,
			str(would_promote.get("reason", "")))
	check("gusty weather selection accepts", session.setup_weather(Weather.preset("gusty")))
	session.reset()
	check("unported weather falls back with reason", session.is_flyable()
		and session.stage_backend_identity() == NativeStage.reference_identity()
		and not str(session.stage_backend_status().reason).is_empty(), str(session.stage_backend_status()))
	session.sim.step()
	check("fallback weather advances", session.sim.tick == 1 and session.sim.fault_reason.is_empty())
	check("reference calm checkpoint restores into native-requested fallback", session.restore_checkpoint(calm_checkpoint))
	check("reference restore does not silently promote backend", session.stage_backend_status().requested == NativeStage.BACKEND_NATIVE
		and session.stage_backend_identity() == NativeStage.reference_identity()
		and session.weather_is_calm() and physical(session) == physical(reference), str(session.stage_backend_status()))
	session.sim.step()
	reference.sim.step()
	check("reference restore continues with matching bytes", session.sim.tick == 1
		and physical(session) == physical(reference) and session.sim.fault_reason.is_empty())
	reference.free()
	session.free()


func run_all() -> void:
	var loaded_field: Dictionary = FieldLoader.load_from()
	var loaded_lake: Dictionary = LakeLoader.load_from()
	var raw_field: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	for surface: Dictionary in raw_field.surfaces:
		if surface.id == raw_field.runway:
			surface.length_east_west.value = float(surface.length_east_west.value) + 2.0
	var loaded_alternate: Dictionary = FieldLoader.validate(raw_field)
	check("field and lake fixtures load", loaded_field.ok and loaded_lake.ok and loaded_alternate.ok,
		str(loaded_alternate.get("errors", [])))
	if not loaded_field.ok or not loaded_lake.ok or not loaded_alternate.ok:
		finish()
		return
	field = loaded_field.field
	alternate_field = loaded_alternate.field
	lake = loaded_lake.lake
	selection()
	var reference := runway(NativeStage.BACKEND_REFERENCE)
	var probe := NativeStage.new()
	var status: Dictionary = NativeStage.library_status()
	var prepared: Dictionary = probe.prepare(reference)
	var native := runway(NativeStage.BACKEND_NATIVE)
	var actual: Dictionary = native.stage_backend_status()
	check("session preserves requested backend", actual.requested == NativeStage.BACKEND_NATIVE)
	if not prepared.ok:
		check("unavailable or stale helper gives a reason", not str(prepared.reason).is_empty())
		if status.ok:
			check("installed library refusal is a stale source", str(prepared.reason).begins_with("mirrored source differs"), str(prepared.reason))
		check("session falls back with reason", actual.identity == NativeStage.reference_identity()
			and not str(actual.reason).is_empty() and native.sim.model.stage.get_method() == &"_wheel_evaluate", str(actual))
		same_steps(native, reference, 24, "fallback")
		print("NK3_NATIVE_SESSION_SKIP native unavailable or stale: ", prepared.reason)
	else:
		check("eligible native request does not fall back", actual.identity.get("backend") == NativeStage.BACKEND_NATIVE,
			str(actual))
		if actual.identity.get("backend") == NativeStage.BACKEND_NATIVE:
			_native_exercised = true
			trajectory(native, reference)
			checkpoints(native, reference)
			rejected_reset()
			reprepare()
			stale_mutation()
			old_helper()
	unsupported_weather(prepared.ok)
	publication_guard(prepared.ok)
	var unsupported := runway(NativeStage.BACKEND_NATIVE, P51)
	check("unsupported aircraft uses reference with a reason", unsupported.stage_backend_identity() == NativeStage.reference_identity()
		and not str(unsupported.stage_backend_status().reason).is_empty(), str(unsupported.stage_backend_status()))
	unsupported.free()
	native.free()
	reference.free()
	finish()


func finish() -> void:
	print("NK3_NATIVE_SESSION checks=%d failures=%d" % [checks, failures])
	if _native_exercised and checks > 0 and failures == 0:
		print("NK3_NATIVE_SESSION_NATIVE verdict=pass")
	quit(1 if failures else 0)
