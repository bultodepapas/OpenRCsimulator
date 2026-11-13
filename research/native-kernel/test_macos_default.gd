## Exercise a real promoted source-editor marker on the production Main route.
## This test does not create a marker or qualify a candidate by itself.
extends SceneTree

const MainScene := preload("res://main.tscn")
const Admission := preload("res://sim/native_macos_admission.gd")
const Domain := preload("res://sim/native_macos_domain.gd")
const Flight := preload("res://sim/flight_session.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const OutOfTrim := preload("res://sim/out_of_trim.gd")
const STIK := "jensen-das-ugly-stik-60"
const START_TIMEOUT_MS := 180000

var _checks := 0
var _failures := PackedStringArray()


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	call_deferred("_run")


func _check(condition: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures.append(label + (": " + detail if not detail.is_empty() else ""))


func _launch(extra: PackedStringArray) -> Node:
	var main: Node = MainScene.instantiate()
	main.external_controller_selection = true
	var args := PackedStringArray(["--quick-flight", "--aircraft=" + STIK, "--weather=calm", "--soundscape=off"])
	args.append_array(extra)
	main.set_user_args(args)
	root.add_child(main)
	var deadline := Time.get_ticks_msec() + START_TIMEOUT_MS
	while not main.startup_complete and Time.get_ticks_msec() < deadline:
		if is_instance_valid(main.session):
			main.session.set_physics_process(false)
			if is_instance_valid(main.session.sim): main.session.sim.set_physics_process(false)
		await process_frame
	_check(main.startup_complete and main.startup_error.is_empty() and is_instance_valid(main.session),
		"production Main startup", str(main.startup_error))
	if not main.startup_complete or not main.startup_error.is_empty() or not is_instance_valid(main.session):
		main.free()
		return null
	main.set_process(false)
	main.session.set_physics_process(false)
	main.session.sim.set_physics_process(false)
	return main


func _physical(session: Node) -> PackedByteArray:
	return var_to_bytes([session.sim.tick, session.sim.state, session.sim.previous, session.sim.aux,
		session.sim.continuous, session.sim.inputs, session.sim.last_loads, session.sim.modes])


func _changed_surface(source: PackedFloat64Array) -> PackedFloat64Array:
	var changed := source.duplicate()
	for index: int in changed.size():
		if is_finite(changed[index]):
			changed[index] += 1.0
			return changed
	return PackedFloat64Array()


func _step(session: Node, label: String) -> bool:
	var tick: int = session.sim.tick
	session.sim.step()
	var advanced: bool = session.sim.tick == tick + 1 and session.sim.fault_reason.is_empty()
	_check(advanced, label, str(session.sim.fault_reason))
	return advanced


func _same_native(session: Node, writer: RefCounted, helper: RefCounted, stage: Callable,
		identity: Dictionary, physical: PackedByteArray, counters: Dictionary) -> bool:
	var after: Dictionary = helper.stage_stats()
	return writer.recording and writer.header.stage_backend == identity and session._native_stage == helper \
		and helper.owns_stage(session) and helper.configuration_matches(session) and session.sim.model.stage == stage \
		and session.stage_backend_identity() == identity and _physical(session) == physical \
		and after.stage_calls == counters.stage_calls and after.context_calls == counters.context_calls


func _recording_path() -> String:
	var explicit := ""
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--macos-default-log="): continue
		if not explicit.is_empty():
			_check(false, "recording output appears more than once")
			return ""
		explicit = argument.trim_prefix("--macos-default-log=")
		if explicit.is_empty() or not explicit.is_absolute_path() or explicit.simplify_path() != explicit \
				or not explicit.contains("/tmp/") or not explicit.ends_with(".orfl") \
				or not DirAccess.dir_exists_absolute(explicit.get_base_dir()) or FileAccess.file_exists(explicit):
			_check(false, "recording output must be a new absolute .orfl under tmp with an existing parent")
			return ""
	return explicit if not explicit.is_empty() else "user://macos-default-%d-%d.orfl" % [OS.get_process_id(), Time.get_ticks_usec()]


func _record_and_replay(main: Node, identity: Dictionary) -> void:
	var session: Node = main.session
	var path := _recording_path()
	if path.is_empty(): return
	var writer: RefCounted = main.flight_log
	_check(writer != null, "production Main provides its flight recorder")
	if writer == null: return
	var started: bool = writer.start(path) == OK
	_check(started, "recorder starts on automatic native flight", writer.failure)
	if not started: return
	_check(writer.header.get("stage_backend") == identity and writer.header.checkpoint.get("stage_backend") == identity,
		"recorder header and checkpoint bind installed native identity")
	# Both setters used to reach an unconditional refresh and replace a live helper.
	var helper: RefCounted = session._native_stage
	var original_world: Dictionary = session._collision_world
	var stage: Callable = session.sim.model.stage
	var tick_before: int = session.sim.tick
	var physical_before := _physical(session)
	var counters: Dictionary = helper.stage_stats()
	var trim_ok: bool = session.setup_out_of_trim(OutOfTrim.defaults(), 0)
	var trim_counters: Dictionary = helper.stage_stats()
	_check(tick_before > 0 and trim_ok and writer.recording and writer.header.stage_backend == identity \
		and session._native_stage == helper and helper.owns_stage(session) and session.sim.model.stage == stage \
		and session.stage_backend_identity() == identity and _physical(session) == physical_before \
		and trim_counters.stage_calls == counters.stage_calls and trim_counters.context_calls == counters.context_calls,
		"disabled out-of-trim cannot replace the live native recorder owner")
	var same_world: Dictionary = session.collision_world()
	var world_ok: bool = session.set_collision_world(same_world)
	var world_counters: Dictionary = helper.stage_stats()
	_check(world_ok and writer.recording and writer.header.stage_backend == identity \
		and session._native_stage == helper and helper.owns_stage(session) and session.sim.model.stage == stage \
		and session.stage_backend_identity() == identity and is_same(session._collision_world, original_world) \
		and _physical(session) == physical_before and world_counters.stage_calls == counters.stage_calls \
		and world_counters.context_calls == counters.context_calls,
		"equal collision world cannot replace the live native recorder owner")
	var old_field: Dictionary = session._runway_field
	var field_copy: Dictionary = old_field.duplicate(true)
	var field_ok: bool = session.set_field(field_copy)
	_check(field_ok and is_same(session._runway_field, old_field) \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"equal field retains the native recorder owner")
	var changed_field: Dictionary = field_copy.duplicate(true)
	changed_field.id = str(changed_field.get("id", "")) + "-changed"
	_check(not session.set_field(changed_field) and is_same(session._runway_field, old_field) \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"changed field provenance is refused without replacing the owner")
	var fuel_before := var_to_bytes([session.fuel_start_fill, session.get("_fuel_start_fill_known"),
		session.get("_trim_density")])
	var fuel_noop: bool = session.set_fuel_start_fill(1.0)
	var fuel_change: bool = session.set_fuel_start_fill(0.75)
	_check(fuel_noop and not fuel_change and var_to_bytes([session.fuel_start_fill,
		session.get("_fuel_start_fill_known"), session.get("_trim_density")]) == fuel_before \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"live fuel selection refuses a changed fill without modifying its recorder owner")
	var start_before := var_to_bytes(session.start)
	var ground_before: PackedByteArray = session.ground_surfaces.to_byte_array()
	var airframe_before: PackedByteArray = session.airframe_surfaces.to_byte_array()
	var hull_before: bool = session.soft_hull_contacts
	var cache_before: int = session.get("_soft_contacts_cache_tick")
	var start_error_before: String = session.start_error
	var backend_error_before: String = session.stage_backend_error
	var hull_object_before: Variant = session.get("_hull_contact")
	var same_ground: PackedFloat64Array = session.ground_surfaces.duplicate()
	var same_airframe: PackedFloat64Array = session.airframe_surfaces.duplicate()
	session.set_start_altitude(-float(session.start.state[2]))
	session.soft_hull_contacts = hull_before
	session.ground_surfaces = same_ground
	session.airframe_surfaces = same_airframe
	_check(var_to_bytes(session.start) == start_before and session.ground_surfaces.to_byte_array() == ground_before \
		and session.airframe_surfaces.to_byte_array() == airframe_before and session.soft_hull_contacts == hull_before \
		and session.get("_soft_contacts_cache_tick") == cache_before and session.start_error == start_error_before \
		and session.stage_backend_error == backend_error_before and is_same(session.get("_hull_contact"), hull_object_before) \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"equal launch-context setters preserve recorder and all accepted owner state")
	session.set_start_altitude(-float(session.start.state[2]) + 1.0)
	_check(var_to_bytes(session.start) == start_before and "new flight" in session.start_error \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"changed start altitude is refused before mutating the live owner")
	session.soft_hull_contacts = not hull_before
	_check(session.soft_hull_contacts == hull_before and session.get("_soft_contacts_cache_tick") == cache_before \
		and "hull contact" in session.stage_backend_error \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"changed hull contact mode is refused before mutating the live owner")
	var changed_ground := _changed_surface(same_ground)
	_check(not changed_ground.is_empty(), "ground surface fixture has a finite value")
	if not changed_ground.is_empty():
		session.ground_surfaces = changed_ground
		_check(session.ground_surfaces.to_byte_array() == ground_before and "ground surfaces" in session.stage_backend_error \
			and _same_native(session, writer, helper, stage, identity, physical_before, counters),
			"changed ground surfaces are refused before mutating the live owner")
	var changed_airframe := _changed_surface(same_airframe)
	_check(not changed_airframe.is_empty(), "airframe surface fixture has a finite value")
	if not changed_airframe.is_empty():
		session.airframe_surfaces = changed_airframe
		_check(session.airframe_surfaces.to_byte_array() == airframe_before \
			and is_same(session.get("_hull_contact"), hull_object_before) \
			and "airframe surfaces" in session.stage_backend_error \
			and _same_native(session, writer, helper, stage, identity, physical_before, counters),
			"changed airframe surfaces are refused before rebuilding the hull")
	var old_lake: Dictionary = session.get("_lake")
	var lake_ok: bool = session.set_lake_context(session.lake_context())
	_check(lake_ok and is_same(session.get("_lake"), old_lake) \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"equal lake retains the native recorder owner")
	var old_hull: Variant = session.get("_hull_contact")
	var airframe_copy: PackedFloat64Array = session.airframe_surfaces.duplicate()
	session.airframe_surfaces = airframe_copy
	_check(is_same(session.get("_hull_contact"), old_hull) \
		and _same_native(session, writer, helper, stage, identity, physical_before, counters),
		"equal airframe surfaces retain the native hull and recorder owner")
	var advanced := true
	for tick: int in 4:
		session.sim.inputs[0] = 0.02 if tick < 2 else -0.02
		session.sim.inputs[3] = 0.4
		advanced = _step(session, "recorded native tick %d" % tick) and advanced
		if tick == 0:
			_check(advanced and writer.recording and session.stage_backend_identity() == identity \
				and session._native_stage == helper and helper.owns_stage(session) \
				and helper.configuration_matches(session), "native recording advances after fuel refusal")
	_check(writer.stop() == OK, "recorder seals its native flight", writer.failure)
	var inspected: Dictionary = Reader.inspect(path)
	_check(inspected.get("ok", false) and inspected.get("complete", false), "recorded native file inspects", str(inspected.get("error", "")))
	if not advanced or not inspected.get("ok", false): return
	if inspected.get("complete", false):
		print("MACOS_DEFAULT_RECORDING path=", ProjectSettings.globalize_path(path))
	var header: Dictionary = inspected.header
	var recorded: Dictionary = Reader.recorded_stage_backend(header)
	_check(recorded.get("ok", false) and recorded.get("identity", {}) == identity,
		"recorded identity names the installed binary")
	var metadata: Variant = header.get("metadata")
	_check(metadata is Dictionary and metadata.get("selected_start_choice") == session.start_choice \
		and typeof(metadata.get("launch_trim_throttle")) == TYPE_STRING \
		and str(metadata.launch_trim_throttle).is_valid_float() and float(metadata.launch_trim_throttle) == 0.5,
		"real Main recording retains its production launch selection")
	var unknown_header: Dictionary = header.duplicate(true)
	unknown_header.metadata.selected_start_choice = "unknown"
	var unknown: Dictionary = Reader.prepare_replay(unknown_header)
	_check(not unknown.get("ok", false), "unknown recorded start refuses automatic replay")
	if unknown.get("ok", false): unknown.flight.free()
	var disabled: Dictionary = Reader.prepare_replay(header, "", false, false)
	_check(not disabled.get("ok", false), "explicitly disabled automatic replay refuses")
	if disabled.get("ok", false): disabled.flight.free()
	var changed_aircraft: Dictionary = header.duplicate(true)
	changed_aircraft.aircraft.input_identity.sha256 = "0".repeat(64)
	var aircraft_refusal: Dictionary = Reader.prepare_replay(changed_aircraft)
	_check(not aircraft_refusal.get("ok", false), "changed recorded stock aircraft refuses automatic replay")
	if aircraft_refusal.get("ok", false): aircraft_refusal.flight.free()
	var changed_binary: Dictionary = header.duplicate(true)
	var different_sha := "0".repeat(64) if identity.binary_sha256 != "0".repeat(64) else "1".repeat(64)
	changed_binary.stage_backend.binary_sha256 = different_sha
	changed_binary.checkpoint.stage_backend.binary_sha256 = different_sha
	var binary_refusal: Dictionary = Reader.prepare_replay(changed_binary)
	_check(not binary_refusal.get("ok", false), "different recorded native binary refuses automatic replay")
	if binary_refusal.get("ok", false): binary_refusal.flight.free()
	var replay: Dictionary = Reader.prepare_replay(header)
	_check(replay.get("ok", false), "recorded native replay prepares", str(replay.get("error", "")))
	if not replay.get("ok", false): return
	_check(replay.flight.stage_backend_identity() == identity and replay.flight.automatic_native_macos \
		and not replay.flight.experimental_native_macos and replay.flight._native_stage != null \
		and replay.flight._native_stage.configuration_matches(replay.flight),
		"replay owns the recorded marker-qualified native identity")
	var stream := FileAccess.open(path, FileAccess.READ)
	if stream == null:
		_check(false, "recorded replay stream opens")
		replay.flight.free()
		return
	stream.seek(8)
	Log.read_packet(stream)
	var observer := Log.new(replay.flight)
	var first := true
	var same := true
	var samples := 0
	while stream.get_position() < stream.get_length():
		var packet: Dictionary = Log.read_packet(stream)
		if not packet.ok:
			same = false
			break
		var block: Dictionary = packet.value
		if block.kind == "footer": break
		for row: Dictionary in block.rows:
			if not first:
				for key: String in row.intervention:
					replay.flight.sim.set(key, row.intervention[key].duplicate())
				replay.flight.sim.inputs = row.inputs.duplicate()
				replay.flight.sim.step()
			same = same and replay.flight.sim.tick == row.tick \
				and Reader.disagreement(row, observer._sample({})).is_empty()
			first = false
			samples += 1
	stream.close()
	_check(same and samples == 5, "recorded native flight replays each exact sample", "samples=%d" % samples)
	replay.flight.free()
	print("MACOS_DEFAULT_LOG ", path)


func _reference_does_not_promote(session: Node, marker: Dictionary, qualified_start: Dictionary) -> void:
	var original: Dictionary = session.stage_backend_identity()
	var outside: Dictionary = Domain.screen_session(session, true)
	var initially_reference: bool = session.automatic_native_macos and not session.experimental_native_macos \
		and session.stage_backend_status().requested == "native" and original.get("backend") == "gdscript_reference" \
		and session._native_stage == null and not outside.get("ok", false) and session.start.state[2] == -31.0
	_check(initially_reference, "unscreened custom altitude starts on reference", str(session.stage_backend_status()))
	if initially_reference:
		var saved_start: Dictionary = session.start.duplicate(true)
		var saved_trims: Dictionary = session.trims.duplicate(true)
		var saved_density: float = session.get("_trim_density")
		var saved_charge: float = session.get("_trim_charge")
		var original_stage: Callable = session.sim.model.stage
		var custom: Dictionary = session.trim_at(float(session.aircraft.model.start_speed), "level")
		var refused: Dictionary = Domain.screen_session(session, true)
		_check(custom.get("ok", false) and session.trim_throttle == 0.5 \
			and not custom.has("requested_throttle") and not refused.get("ok", false) \
			and refused.get("reason") == "start is not the bounded qualified trim result" \
			and session._native_stage == null and session.sim.model.stage == original_stage,
			"custom trim_at is refused before any native callback", str(refused))
		session.start = saved_start
		session.trims = saved_trims
		session.set("_trim_density", saved_density)
		session.set("_trim_charge", saved_charge)
	if not initially_reference or not _step(session, "outside-domain reference advances"): return
	var path := "user://macos-default-ref-%d-%d.orfl" % [OS.get_process_id(), Time.get_ticks_usec()]
	var writer := Log.new(session)
	var started := writer.start(path) == OK
	_check(started and writer.header.get("stage_backend") == original, "reference recorder starts", writer.failure)
	if not started: return
	var stage: Callable = session.sim.model.stage
	var model: RefCounted = session.sim.model
	var tick_before: int = session.sim.tick
	var physical_before := _physical(session)
	# Restore a screened selection with the public setter, then exercise setters
	# that previously invoked the same hidden backend refresh after tick zero.
	session.set_start_altitude(30.0)
	var selected: Dictionary = Domain.screen_session(session, true)
	var eligible: bool = Admission.selection_allowed(marker, selected, session.soft_hull_contacts)
	if not eligible:
		# Preserve the actual start from the separately admitted Main instance;
		# do not manufacture a marker or infer a hash for this reference fixture.
		session.start = qualified_start.duplicate(true)
		selected = Domain.screen_session(session, true)
		eligible = Admission.selection_allowed(marker, selected, session.soft_hull_contacts)
	_check(session.start.state[2] == -30.0 and eligible,
		"reference selection becomes marker-eligible before refresh", str(selected))
	var trim_ok: bool = session.setup_out_of_trim(OutOfTrim.defaults(), 0)
	_check(tick_before > 0 and trim_ok and writer.recording and session._native_stage == null \
		and session.stage_backend_identity() == original and session.sim.model == model and model.stage == stage \
		and session.sim.tick == tick_before and _physical(session) == physical_before,
		"disabled out-of-trim cannot promote a live reference recorder")
	var same_world: Dictionary = session.collision_world()
	var world_ok: bool = session.set_collision_world(same_world)
	_check(world_ok and writer.recording and session._native_stage == null \
		and session.stage_backend_identity() == original and session.sim.model == model and model.stage == stage \
		and session.sim.tick == tick_before and _physical(session) == physical_before,
		"equal collision world cannot promote a live reference recorder")
	var advanced := _step(session, "reference owner advances after no-op setters")
	_check(advanced and writer.recording and session.stage_backend_identity() == original,
		"reference recording continues with the original solver")
	_check(writer.stop() == OK, "reference recorder seals", writer.failure)
	var inspected: Dictionary = Reader.inspect(path)
	_check(inspected.get("ok", false) and inspected.get("complete", false) \
		and inspected.get("header", {}).get("stage_backend") == original, "reference recorder retains its solver identity")
	print("MACOS_DEFAULT_REFERENCE_LOG ", path)


func _reject_mutated_start(session: Node) -> void:
	var helper: RefCounted = session._native_stage
	if helper == null or typeof(session.start.get("V")) != TYPE_FLOAT:
		_check(false, "start mutation requires a guarded trim")
		return
	var original: float = session.start.V
	var counters: Dictionary = helper.stage_stats()
	var before := _physical(session)
	session.start.V = original + 0.01
	_check(not helper.configuration_matches(session) and session.checkpoint().is_empty(),
		"changed start metadata invalidates the native guard and checkpoint")
	session.start.V = original
	var after: Dictionary = helper.stage_stats()
	_check(helper.configuration_matches(session) and not session.checkpoint().is_empty() \
		and _physical(session) == before and after.stage_calls == counters.stage_calls \
		and after.context_calls == counters.context_calls, "restoring exact start metadata restores the guard")


func _lifecycle(session: Node, identity: Dictionary) -> void:
	var snapshot: Dictionary = session.checkpoint()
	_check(not snapshot.is_empty() and snapshot.get("stage_backend") == identity, "native checkpoint identifies owner")
	if snapshot.is_empty(): return
	var saved := _physical(session)
	if not _step(session, "advance before checkpoint restore"): return
	_check(session.restore_checkpoint(snapshot), "restore native checkpoint")
	_check(_physical(session) == saved and session.stage_backend_identity() == identity \
		and session._native_stage != null and session._native_stage.configuration_matches(session),
		"checkpoint restore retains physical bytes and guarded native owner", str(session.stage_backend_status()))
	if not _step(session, "restored native owner advances"): return
	session.reset()
	_check(session.sim.tick == 0 and session.is_flyable() and session.stage_backend_identity() == identity \
		and session._native_stage != null and session._native_stage.configuration_matches(session),
		"ordinary reset prepares a guarded native owner", str(session.stage_backend_status()))
	var message: String = session.reload()
	_check(message.begins_with("aircraft reloaded:") and session.is_flyable() \
		and session.stage_backend_identity() == identity and session._native_stage != null \
		and session._native_stage.configuration_matches(session), "stock reload keeps the automatic native route", message)
	if session._native_stage == null or session.stage_backend_identity() != identity: return
	var helper: RefCounted = session._native_stage
	var old_world: Dictionary = session._collision_world
	var old_field: Dictionary = session._runway_field
	var old_choice: String = session.start_choice
	var before := _physical(session)
	session.start_choice = "invalid-test-start"
	session.reset()
	_check(not session.start_error.is_empty() and session.start_choice == old_choice \
		and session._native_stage == helper and helper.owns_stage(session) and helper.configuration_matches(session) \
		and is_same(session._collision_world, old_world) and is_same(session._runway_field, old_field) \
		and _physical(session) == before, "rejected reset restores guarded owner and context", str(session.start_error))
	_step(session, "original owner advances after rejected reset")


func _reject_mutated_packed_world(session: Node) -> void:
	var helper: RefCounted = session._native_stage
	if helper == null:
		_check(false, "packed mutation requires installed owner")
		return
	var world: Dictionary = session._collision_world
	var chosen := ""
	for key: Variant in world.bins:
		if world.bins[key] is PackedInt64Array and not world.bins[key].is_empty():
			chosen = str(key)
			break
	_check(not chosen.is_empty(), "stock collision world has a packed bin")
	if chosen.is_empty(): return
	var tick: int = session.sim.tick
	var physical := _physical(session)
	var stage: Callable = session.sim.model.stage
	var before: Dictionary = helper.stage_stats()
	var original: int = world.bins[chosen][0]
	var alias: PackedInt64Array = world.bins[chosen]
	alias[0] = original + 1
	_check(world.bins[chosen][0] == original + 1, "actual packed alias mutates the live frozen world")
	_check(not helper.configuration_matches(session) and session.checkpoint().is_empty(),
		"packed mutation invalidates guard and checkpoint")
	session.sim.step()
	var after: Dictionary = helper.stage_stats()
	_check(session.sim.tick == tick and _physical(session) == physical and not session.sim.fault_reason.is_empty() \
		and not session.stage_backend_error.is_empty() and after.stage_calls == before.stage_calls \
		and after.context_calls == before.context_calls, "packed mutation faults before tick or native evaluation")
	_check(session._native_stage == helper and helper.owns_stage(session) and session.sim.model.stage == stage,
		"packed mutation does not swap the stage midflight")


func _run() -> void:
	if OS.get_name() != "macOS" or Engine.get_architecture_name() != "arm64" or OS.has_feature("template_release"):
		_check(false, "source-editor Mac arm64 is required")
	elif Admission.read_marker().is_empty():
		_check(false, "a separately generated, verified promotion marker is required")
	else:
		print("MACOS_DEFAULT_HARDWARE ", JSON.stringify({cpu = OS.get_processor_name(), model = OS.get_model_name()}))
		var marker: Dictionary = Admission.read_marker()
		var qualified_start := {}
		var main: Node = await _launch(PackedStringArray())
		if main != null:
			var session: Node = main.session
			var identity: Dictionary = session.stage_backend_identity()
			_check(session.is_flyable() and session.expected_aircraft_id == STIK \
				and session.trim_throttle == Flight.CRUISE_TRIM_THROTTLE and session.start_choice == Flight.START_RUNWAY,
				"Quick Flight selects stock Jensen and production trim", str(session.stage_backend_status()))
			_check(session.automatic_native_macos and not session.experimental_native_macos \
				and session.stage_backend_status().requested == "native" and identity.get("backend") == "native" \
				and session._native_stage != null and session._native_stage.owns_stage(session),
				"default Main route owns the native stage", str(session.stage_backend_status()))
			session.automatic_native_macos = false
			session.experimental_native_macos = true
			_check(session.automatic_native_macos and not session.experimental_native_macos,
				"live launch admission choice cannot change")
			if session._native_stage != null and identity.get("backend") == "native":
				qualified_start = session.start.duplicate(true)
				var selected: Dictionary = Domain.screen_session(session, true)
				_check(Admission.selection_allowed(marker, selected, session.soft_hull_contacts),
					"live start matches the independently qualified marker", str(selected))
				var world: Dictionary = session._collision_world
				var field: Dictionary = session._runway_field
				var context: Dictionary = session._native_stage.get("_macos_domain_context")
				var guard: Dictionary = context.get("native_guard", {})
				_check(guard.get("ok", false) and guard.get("nodes", 0) > 0 and guard.get("packed_leaves", 0) > 0 \
					and guard.get("packed_bytes", 0) > 0, "actual stock world has a prepared native packed guard")
				print("MACOS_DEFAULT_GUARD ", JSON.stringify(guard))
				_check(world.is_read_only() and world.get("proxies", []).is_read_only() \
					and world.get("bins", {}).is_read_only() and field.is_read_only() \
					and session._native_stage.configuration_matches(session), "automatic owner installs guarded frozen context")
				var before: Dictionary = session._native_stage.stage_stats()
				if _step(session, "automatic native stage advances"):
					var after: Dictionary = session._native_stage.stage_stats()
					_check(after.stage_calls > before.stage_calls and after.context_calls > before.context_calls,
						"native stage and tick context actually executed")
					_record_and_replay(main, identity)
					_lifecycle(session, identity)
					_reject_mutated_start(session)
					_reject_mutated_packed_world(session)
			main.free()
		var outside: Node = await _launch(PackedStringArray(["--alt=31"]))
		if outside != null:
			_reference_does_not_promote(outside.session, marker, qualified_start)
			outside.free()
		var reference: Node = await _launch(PackedStringArray(["--physics-backend=gdscript_reference"]))
		if reference != null:
			_check(reference.session.stage_backend_identity().get("backend") == "gdscript_reference" \
				and reference.session._native_stage == null, "explicit reference remains reference")
			reference.free()
		var denied: Node = await _launch(PackedStringArray(["--experimental-native-macos=false"]))
		if denied != null:
			_check(not denied.session.automatic_native_macos and not denied.session.experimental_native_macos \
				and denied.session.stage_backend_identity().get("backend") == "gdscript_reference" \
				and denied.session._native_stage == null, "explicit false does not auto-enable Mac native")
			denied.free()
	if _failures.is_empty():
		print("MACOS_DEFAULT_ROUTE verdict=pass checks=", _checks)
		quit(0)
	else:
		for failure: String in _failures: print("FAIL ", failure)
		print("MACOS_DEFAULT_ROUTE verdict=fail checks=%d failures=%d" % [_checks, _failures.size()])
		quit(1)
