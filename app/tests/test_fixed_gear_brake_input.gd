extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Trace := preload("res://sim/trace.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Wheels := preload("res://physics/wheel_profiles.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const RB := preload("res://physics/rigid_body.gd")
const Ground := preload("res://physics/ground_contact.gd")
const MainInput := preload("res://tests/fixtures/fixed_brake_main_input.gd")
var checks := 0
var failures := 0
var cleanup: Array[String] = []

func digest(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func legacy_metadata(f: Node) -> Dictionary:
	var metadata: Dictionary = f.trace_meta()
	metadata.created_utc = "fixed-brake-legacy-fixture-time"
	return metadata

func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	call_deferred("run_all")

func run_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../tmp/gp12-fixed-brake-session"))
	legacy()
	hardware_boundary()
	for flaps: bool in [false, true]:
		for brakes: bool in [false, true]:
			candidate(flaps, brakes)
	if not OS.get_cmdline_user_args().has("--retain-evidence"):
		for path: String in cleanup:
			DirAccess.remove_absolute(path)
	print("Fixed brake candidate: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func hardware_boundary() -> void:
	var data := fixture(false, true)
	if not data.ok: return
	var boundary := Flight.new()
	boundary.aircraft = data.duplicate(true)
	check("validated synthetic hardware is explicitly admitted", boundary.wheel_brake_available())
	for field: String in ["status", "availability", "source_availability", "provenance_value", "unit", "kind", "source"]:
		for wrong: Variant in [null, true, 1, [], {}, StringName("available")]:
			boundary.aircraft = data.duplicate(true)
			var contact: Dictionary = boundary.aircraft.model.landing_gear.contacts[0]
			match field:
				"status": boundary.aircraft.model.wheel_profile.status = wrong
				"availability": contact.brake_availability = wrong
				"source_availability": contact.wheel_provenance.brake_availability = wrong
				"provenance_value": contact.wheel_provenance.brake_torque.value = wrong
				"unit": contact.wheel_provenance.brake_torque.unit = wrong
				"kind": contact.wheel_provenance.brake_torque.kind = wrong
				"source": contact.wheel_provenance.brake_torque.source = wrong
			check("malformed hardware primitive fails closed " + field, not boundary.wheel_brake_available())
	for wrong: Variant in [null, true, [], 1, "applied"]:
		boundary.aircraft = data.duplicate(true)
		boundary.aircraft.model.wheel_profile = wrong
		check("malformed profile container fails closed", not boundary.wheel_brake_available())
		boundary.aircraft = data.duplicate(true)
		boundary.aircraft.model.landing_gear = wrong
		check("malformed gear container fails closed", not boundary.wheel_brake_available())
		boundary.aircraft = data.duplicate(true)
		boundary.aircraft.model.landing_gear.contacts = wrong
		check("malformed contacts container fails closed", not boundary.wheel_brake_available())
		boundary.aircraft = data.duplicate(true)
		boundary.aircraft.model.landing_gear.contacts[0] = wrong
		check("malformed contact fails closed", not boundary.wheel_brake_available())
	boundary.aircraft = data.duplicate(true)
	boundary.aircraft.model.landing_gear.contacts[0].brake_torque = 1.0
	boundary.aircraft.model.landing_gear.contacts[0].wheel_provenance.brake_torque.value = true
	check("bool provenance never equals numeric one", not boundary.wheel_brake_available())
	boundary.aircraft = data.duplicate(true)
	boundary.aircraft.model.wheel_profile.status = "legacy_fallback"
	check("positive torque alone cannot create hardware capability", not boundary.wheel_brake_available())
	boundary.free()

func fixture(flaps: bool, brakes: bool) -> Dictionary:
	var source_path := "res://data/aircraft/sebart_avanti_s_a200.json" if flaps else "res://data/aircraft/jensen_ugly_stik_60.json"
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if flaps:
		raw.capabilities.gear = "fixed_tricycle"
		raw.landing_gear.erase("retraction")
		for contact: Dictionary in raw.landing_gear.contacts:
			contact.erase("retraction_path")
	var validated := Data.validate_and_derive(raw)
	check("authored fixed fixture validates", validated.ok, str(validated.get("errors")))
	if not validated.ok: return validated
	var authored_file := FileAccess.open("res://../tmp/gp12-fixed-brake-session/authored-fixed-%s.json" % flaps, FileAccess.WRITE)
	authored_file.store_string(JSON.stringify(raw, "\t"))
	authored_file.close()
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Wheels.DEFAULT_PATH))
	var profile: Dictionary = table.profiles[raw.id].duplicate(true)
	for name: String in profile.contacts:
		var contact: Dictionary = profile.contacts[name]
		# Synthetic test hardware, deliberately not a manufacturer/stock claim.
		contact.brake_availability = "available" if brakes else "none"
		contact.brake_torque = {value = 0.2 if brakes else 0.0, unit = "N·m", kind = "estimated",
			source = "GP12 detached software fixture only; synthetic shared-brake hardware, no stock aircraft claim"}
	var path := ProjectSettings.globalize_path("res://../tmp/gp12-fixed-brake-session/profile-%s-%s.json" % [flaps, brakes])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({format = Wheels.FORMAT, profiles = {raw.id: profile}}))
	file.close()
	var applied := Wheels.apply_to_model(validated.model, path)
	check("synthetic provenance profile admitted by sole hardware owner", applied.ok, str(applied.get("errors")))
	if applied.ok:
		validated.model = applied.model
		validated.wheel_profile_identity = applied.identity
	return validated

func step(f: Node, count: int) -> void:
	for i: int in count:
		f.sim.inputs = f._inputs()
		f.sim.step()

func record(trace: RefCounted, f: Node) -> void:
	trace.meta.mass_trace_schema = "openrc-mass-sample v1"
	trace.record(f.sim.tick, f.sim.time(), f.sim.state, f.sim.last_loads, f.sim.inputs,
		f.sim.aux, f.sim.continuous, f.mass_properties())

func candidate(flaps: bool, brakes: bool) -> void:
	var data := fixture(flaps, brakes)
	if not data.ok: return
	var f := Flight.new()
	f.setup("fixture://fixed-brake", "", data)
	check("fixture launches through existing owner", f.is_flyable() and f.physics_enabled, str(f.runway_start_outcome))
	if not f.is_flyable():
		f.free()
		return
	var width: int = 4 + int(flaps) + int(brakes)
	check("fixed hardware independent of retraction", not f.gear_is_retractable() and f.wheel_brake_available() == brakes)
	check("conditional input slot and width", f.sim.inputs.size() == width and f.wheel_brake_input_index() == (4 if brakes else -1))
	check("flap input follows only installed commands", f.flap_input_index() == (width - 1 if flaps else -1))
	check("positive shared command matches hardware", f.set_wheel_brake(0.7) == brakes)
	step(f, 2)
	if brakes: check("accepted demand reaches fixed input", f.sim.inputs[4] == 0.7)
	var cp := f.checkpoint()
	check("checkpoint available", not cp.is_empty())
	check("conditional checkpoint identity only on new layout", cp.has("fixed_brake_input_law") == brakes
		and cp.has("wheel_brake_input_index") == brakes)
	var meta := f.trace_meta()
	check("conditional metadata identity and named roles", meta.has("fixed_brake_input_law") == brakes
		and Reader.input_names({inputs = width}, meta).ok)
	var trace := Trace.new()
	trace.meta = meta
	record(trace, f)
	check("Trace accepts supported owner shape and retains old unsupported refusal", trace.row_count() == (0 if flaps and not brakes else 1), str(trace.columns()))
	if flaps and not brakes:
		check("historically unsupported fixed turbine-wheel Trace stays refused", trace.row_count() == 0)
	check("Trace brake column exists only with hardware", trace.columns().has("cmd_wheel_brake") == brakes)
	check("Trace never invents gear extension", not trace.columns().has("gear_extension"))
	var csv := trace.to_csv()
	check("only fixed brake selects v17 with underlying identity", csv.begins_with("# format: openrc-trace v17\n") == brakes
		and csv.contains("# fixed_brake_base_trace_format: ") == brakes)
	if brakes:
		var output := FileAccess.open("res://../tmp/gp12-fixed-brake-session/trace-%s.csv" % flaps, FileAccess.WRITE)
		output.store_string(csv)
		output.close()
	if brakes and trace.row_count(): check("Trace records actual shared input", trace.value(0, "cmd_wheel_brake") == 0.7)
	step(f, 5)
	var expected := var_to_bytes(f.sim.checkpoint())
	check("checkpoint restores accepted brake state", f.restore_checkpoint(cp))
	f.sim.set_paused(false)
	step(f, 5)
	check("candidate checkpoint continuation is byte exact", expected == var_to_bytes(f.sim.checkpoint()))
	var before := var_to_bytes(f.checkpoint())
	if brakes:
		for field: String in ["fixed_brake_input_law", "wheel_brake_input_index", "fraction"]:
			var bad := cp.duplicate(true)
			if field == "fraction": bad.simulation.inputs[4] = NAN
			else: bad[field] = "wrong"
			check("malformed brake checkpoint refuses atomically " + field, not f.restore_checkpoint(bad)
				and before == var_to_bytes(f.checkpoint()))
		for key: String in ["fixed_brake_input_law", "wheel_brake_input_index", "gear_law", "input_layout"]:
			var hostile := Trace.new()
			hostile.meta = meta.duplicate(true)
			hostile.meta[key] = "bad"
			record(hostile, f)
			check("Trace rejects inconsistent role identity " + key, hostile.row_count() == 0)
		var oversized := Trace.new()
		oversized.meta = meta.duplicate(true)
		oversized.meta.input_layout = " ".repeat(257) + str(meta.input_layout)
		record(oversized, f)
		check("Trace bounds role JSON before parsing", oversized.row_count() == 0)
	check("zero releases clear without hardware/while paused", f.set_wheel_brake(0.0))
	f.sim.set_paused(true)
	check("paused positive command refused", not f.set_wheel_brake(1.0))
	check("paused release remains legal", f.set_wheel_brake(0.0))
	f.sim.set_paused(false)
	f.input_enabled = true
	if brakes:
		main_input(f)
	for bad: float in [-0.1, 1.1, NAN, INF]: check("invalid demand refused", not f.set_wheel_brake(bad))
	if brakes: check("nonzero demand staged before reset", f.set_wheel_brake(0.6) and f._inputs()[4] == 0.6)
	f.reset()
	check("existing reset clears brake demand", f._inputs().size() == width and (not brakes or f._inputs()[4] == 0.0))
	if brakes:
		check("reload starts with zero demand", f.set_wheel_brake(0.5) and not f.reload().is_empty() and f._inputs()[4] == 0.0)
		grounded_braking(f)
	# External packet admission and rejected packet preservation use the existing owner.
	f.external_driver_enabled = true
	var packet := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, brake = 0.4}
	check("external brake hardware validation", f.prepare_external_tick(packet).ok == brakes)
	if not brakes:
		packet.brake = 0.0
		check("external zero release needs no brake hardware", f.prepare_external_tick(packet).ok and f.step_external_tick())
		check("external release preserves unbraked layout", f.sim.inputs.size() == width and f._wheel_brake_demand == 0.0)
	if brakes:
		check("external packet commits exactly one normal tick", f.step_external_tick() and f.sim.inputs[4] == 0.4)
		var tick: int = f.sim.tick
		packet.brake = 1.1
		check("external invalid packet cannot advance", not f.prepare_external_tick(packet).ok and not f.step_external_tick() and f.sim.tick == tick)
		packet.brake = 0.3
		check("valid external packet can be staged before refusal", f.prepare_external_tick(packet).ok)
		packet.brake = NAN
		check("malformed replacement preserves prior staged packet", not f.prepare_external_tick(packet).ok
			and f.step_external_tick() and f.sim.inputs[4] == 0.3)
		log_roundtrip(f, data)
		rejected_tick(f)
		hardware_loss(f, flaps)
	f.free()

func hardware_loss(f: Node, flaps: bool) -> void:
	f.external_driver_enabled = false
	f.input_enabled = true
	f.sim.set_paused(false)
	check("brake demand is positive before hardware replacement", f.set_wheel_brake(0.8))
	f._frozen_aircraft = fixture(flaps, false)
	f.reload()
	check("accepted valid unbraked replacement removes capability and demand", f.is_flyable()
		and not f.wheel_brake_available() and f._wheel_brake_demand == 0.0 and f.sim.inputs.size() == 4 + int(flaps))
	f.external_driver_enabled = true
	var packet := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0, brake = 0.0}
	check("external release after real hardware replacement is admitted", f.prepare_external_tick(packet).ok and f.step_external_tick())
	var before := digest(f.commands)
	packet.roll = 2.0
	check("mixed invalid packet cannot partially apply release or controls", not f.prepare_external_tick(packet).ok
		and not f.step_external_tick() and before == digest(f.commands))

func rejected_tick(f: Node) -> void:
	var saved: Dictionary = f.checkpoint()
	var stage: Callable = f.sim.model.stage
	var generation: int = f.statistics_generation
	f.sim.model.stage = func(_body: PackedFloat64Array, _continuous: PackedFloat64Array, _time: float) -> Dictionary: return {}
	f.sim.step()
	var retained := true
	for key: String in ["state", "aux", "continuous", "inputs", "modes", "tick", "last_loads"]:
		retained = retained and var_to_bytes(f.sim.get(key)) == var_to_bytes(saved.simulation[key])
	check("rejected fixed-layout RK tick retains complete accepted physical frame", retained and not f.sim.fault_reason.is_empty())
	check("rejected fixed-layout tick creates no flight generation", generation == f.statistics_generation)
	f.sim.model.stage = stage
	check("fixed-layout restore recovers after rejected RK tick", f.restore_checkpoint(saved))

func grounded_braking(f: Node) -> void:
	var body: PackedFloat64Array = f.sim.state.duplicate()
	# Deliberate frozen loaded state; this is a force-routing oracle, not a trimmed runway launch claim.
	for i: int in 3:
		body[RB.RATE + i] = 0.0
		body[RB.VEL + i] = 0.0
	for i: int in 4: body[RB.ATT + i] = 1.0 if i == 0 else 0.0
	var lowest := -INF
	for contact: Dictionary in f.aircraft.model.landing_gear.contacts: lowest = maxf(lowest, contact.position[2])
	body[RB.POS + 2] = 0.005 - lowest
	body[RB.VEL] = 5.0
	var continuous: PackedFloat64Array = f.sim.continuous.duplicate()
	# Ground receives the rotating tail without the separate finite-fuel inventory slots.
	continuous.resize(f.wheel_index() + f.wheel_count())
	for i: int in f.wheel_count(): continuous[f.wheel_index() + i] = 5.0
	f.sim.inputs[4] = 0.0
	var free: Dictionary = f._ground_evaluation(body, f.sim.aux, continuous, {}, f.mass_properties())
	f.sim.inputs[4] = 1.0
	var braking: Dictionary = f._ground_evaluation(body, f.sim.aux, continuous, {}, f.mass_properties())
	check("existing ground law remains finite and loaded", free.ok and braking.ok and free.loads.size() == 6)
	var reduction := false
	if free.derivative.size() == f.wheel_count() and braking.derivative.size() == f.wheel_count():
		for i: int in f.wheel_count(): reduction = reduction or braking.derivative[i] < free.derivative[i]
	check("new input reaches existing finite-torque rim response", reduction)
	var anchors: PackedFloat64Array = f.sim.aux.slice(f.AUX_ANCHORS, f.AUX_ANCHORS + f.anchor_count() * Ground.ANCHOR_STRIDE)
	var direct := Ground.evaluate(body, f.current_landing_gear(f.sim.aux), f.sim.aux[f.AUX_SERVO + 2], f.ground_surfaces,
		anchors, continuous.slice(f.wheel_index()), 1.0, false, f.lake_context())
	check("exact existing rim derivative, including body reaction law", braking.ok and direct.derivative == braking.derivative)
	f.sim.inputs[4] = 0.0

func main_input(f: Node) -> void:
	var main := MainInput.new()
	main.session = f
	root.add_child(main)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	main._unhandled_input(key)
	check("real Main B path admits fixed hardware", main._wheel_brake_key_held and f._inputs()[4] == 1.0)
	f.sim.set_paused(true)
	key.pressed = false
	main._input(key)
	check("Main key release clears while paused", not main._wheel_brake_key_held and f._inputs()[4] == 0.0)
	f.sim.set_paused(false)
	key.pressed = true
	main._unhandled_input(key)
	main._notification(MainInput.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("Main focus loss clears shared brake", not main._wheel_brake_key_held and f._inputs()[4] == 0.0)
	main.session = null
	main.free()

func log_roundtrip(f: Node, data: Dictionary) -> void:
	var path := ProjectSettings.globalize_path("res://../tmp/gp12-fixed-brake-session/candidate-%d.orfl" % Time.get_ticks_usec())
	cleanup.append(path)
	var log := Log.new(f)
	check("existing ORFL starts new layout", log.start(path) == OK)
	step(f, 4)
	check("existing ORFL completes new layout", log.stop() == OK)
	var inspected := Reader.inspect(path)
	check("named-input ORFL reader accepts fixed brake", inspected.ok and inspected.complete)
	if not inspected.ok: return
	var replay := Flight.new()
	replay.input_enabled = false
	replay.setup("fixture://fixed-brake", "", data)
	check("new layout ORFL checkpoint restores candidate owner", replay.restore_checkpoint(inspected.header.checkpoint))
	var stream := FileAccess.open(path, FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var first := true
	var exact := true
	var observer := Log.new(replay)
	while stream.get_position() < stream.get_length():
		var packet := Log.read_packet(stream)
		if not packet.ok:
			exact = false
			break
		if packet.value.kind == "footer": break
		for row: Dictionary in packet.value.rows:
			if first:
				first = false
				continue
			replay.sim.inputs = row.inputs.duplicate()
			replay.sim.step()
			if not Reader.disagreement(row, observer._sample({})).is_empty(): exact = false
	check("every candidate ORFL row exact against source-pinned draft owner", exact)
	replay.free()
	stream.close()

func legacy() -> void:
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/fixed_brake_legacy_outputs.json"))
	for id: String in frozen.outputs:
		var expected: Dictionary = frozen.outputs[id]
		var f := Flight.new()
		f.setup(Catalog.entry(id).data)
		check("frozen legacy checkpoint/metadata exact " + id,
			Engine.get_version_info().string == frozen.engine and Engine.physics_ticks_per_second == frozen.physics_hz
			and digest(f.checkpoint()) == expected.checkpoint and digest(legacy_metadata(f)) == expected.metadata)
		var trace := Trace.new()
		trace.meta = legacy_metadata(f)
		record(trace, f)
		check("frozen legacy CSV exact " + id, trace.row_count() == 1 and trace.to_csv().sha256_text() == expected.trace_csv)
		step(f, 3)
		check("frozen legacy continuation exact " + id, digest(f.sim.checkpoint()) == expected.after_three_ticks)
		f.free()
