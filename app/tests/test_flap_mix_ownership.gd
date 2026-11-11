## AV-17-R5 / review R4: input mix ownership, checkpoint and accepted-tape replay.
extends SceneTree
const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := "res://data/aircraft/sebart_avanti_s_a200.json"
const INFO := {guid = "r4-fake-radio", name = "R4 fixture radio", vendor_id = 0x1209, product_id = 0x4f54}
var checks := 0
var failures := 0
var out := ""

func _initialize() -> void:
	out = ProjectSettings.globalize_path("res://../tmp/flap-mix-%d" % Time.get_ticks_usec())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func fixture() -> Node:
	var f := Flight.new()
	f.setup(AIRCRAFT)
	f.crash_auto_restart = false
	f.sim.state[RB.POS + 2] = -500.0
	f.sim.previous = f.sim.state.duplicate()
	f.trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	return f

func _run() -> void:
	_mixer()
	_checkpoint()
	_rejected_tick()
	_record()
	print("AV-17-R5 flap mix ownership: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _mixer() -> void:
	var f := fixture()
	check("Avanti prepared", f.is_flyable())
	f.commands = {roll = 0.0, pitch = 0.1, yaw = 0.0, throttle = 0.0}
	f._flap_requested = 1.0
	var inputs: PackedFloat64Array = f._inputs()
	var aux: PackedFloat64Array = f.sim.aux.duplicate()
	aux[f.flap_aux_index()] = 1.0
	var original := inputs.to_byte_array()
	var mixed: PackedFloat64Array = f._pre_step(aux, inputs, 1.0)
	check("legacy keyboard adds authored compensation", absf(mixed[2] - (0.1 - f.aircraft.model.flaps.elevator_mix_per_flap_fraction)) < 1e-12)
	check("mixer does not overwrite recorded pilot input", inputs.to_byte_array() == original)
	for kind in ["radio", "joystick"]:
		var profile := Profile.defaults(kind, "radio_custom")
		profile.flap_elevator_mix_owner = "transmitter"
		f.radio.connect_device(42, INFO, profile)
		inputs = f._inputs()
		var unmixed: PackedFloat64Array = f._pre_step(aux, inputs, 1.0)
		check(kind + " premixed pitch is not mixed twice", f.flap_mix_owner() == "transmitter" and absf(unmixed[2] - 0.1) < 1e-12)
		check(kind + " keeps flap actuator independent", unmixed[f.flap_aux_index()] == mixed[f.flap_aux_index()])
	f.input_enabled = false
	f._inputs()
	check("scripted maneuvers ignore a connected premixed radio", f.flap_mix_owner() == "simulator")
	f.input_enabled = true
	f.external_driver_enabled = true
	f._inputs()
	check("external command driver retains simulator mix", f.flap_mix_owner() == "simulator")
	f.external_driver_enabled = false
	f.radio.connect_device(42, INFO, Profile.defaults("gamepad", "mode2"))
	f._inputs()
	check("gamepad retains simulator mix", f.flap_mix_owner() == "simulator")
	f.radio.disconnect_device()
	f._inputs()
	check("keyboard fallback restores simulator mix", f.flap_mix_owner() == "simulator")
	f.commands.pitch = -1.0
	inputs = f._inputs()
	mixed = f._pre_step(aux, inputs, 1.0)
	check("simulator compensation saturates at physical command limit", mixed[2] == -1.0)
	f.free()

func _checkpoint() -> void:
	var f := fixture()
	f.input_enabled = false
	var legacy: Dictionary = f.checkpoint()
	check("legacy checkpoint omits optional ownership", not legacy.has("flap_mix_owner"))
	check("replay owner can be set explicitly", f.restore_input_mix_owner("transmitter"))
	var saved: Dictionary = f.checkpoint()
	check("transmitter checkpoint pins distinct configuration", saved.flap_mix_owner == "transmitter" and saved.configuration != legacy.configuration)
	f.restore_input_mix_owner("simulator")
	var published: Array = []
	var on_restore := func() -> void:
		published.append([f.flap_mix_owner(), f.checkpoint().get("flap_mix_owner", "simulator"),
			f.reset_closing_context().checkpoint.get("flap_mix_owner", "simulator")])
	f.resetting.connect(on_restore)
	check("transmitter checkpoint restores", f.restore_checkpoint(saved) and f.flap_mix_owner() == "transmitter" and not f.input_enabled)
	check("restore publishes new owner and retains old closing context", published == [["transmitter", "transmitter", "simulator"]])
	f.resetting.disconnect(on_restore)
	for value in [null, 4, true, "unknown", "simulator"]:
		var bad := saved.duplicate(true)
		bad.flap_mix_owner = value
		var before := var_to_bytes(f.checkpoint())
		check("malformed/contradictory owner refused " + str(value), not f.restore_checkpoint(bad) and before == var_to_bytes(f.checkpoint()))
	var downgraded := saved.duplicate(true)
	downgraded.erase("flap_mix_owner")
	downgraded.erase("flap_mix_contract")
	check("ownership cannot be stripped from transmitter checkpoint", not f.restore_checkpoint(downgraded))
	check("old checkpoint restores simulator ownership", f.restore_checkpoint(legacy) and f.flap_mix_owner() == "simulator")
	f.input_enabled = true
	check("replay API cannot override live pilot", not f.restore_input_mix_owner("transmitter"))
	f.free()

func _rejected_tick() -> void:
	for starting_owner in ["simulator", "transmitter"]:
		var f := fixture()
		var profile := Profile.defaults("radio", "radio_custom")
		profile.flap_elevator_mix_owner = starting_owner
		f.radio.connect_device(42, INFO, profile)
		f.sim.inputs = f._inputs()
		f.sim.step()
		var accepted_inputs: PackedFloat64Array = f.sim.inputs.duplicate()
		var accepted_tick: int = f.sim.tick
		profile = profile.duplicate(true)
		profile.flap_elevator_mix_owner = "transmitter" if starting_owner == "simulator" else "simulator"
		f.radio.use_profile(profile, "fault test")
		f.sim.inputs = f._inputs()
		check("new owner staged before rejected tick", f.flap_mix_owner() != starting_owner)
		var observations: Array = []
		f.sim.paused_changed.connect(func(_paused: bool) -> void: observations.append(f.flap_mix_owner()))
		f.sim.faulted.connect(func(_reason: String) -> void: observations.append(f.flap_mix_owner()))
		f.sim.inputs[0] = NAN
		f.sim.step()
		check("rejected tick restores prior accepted mix and input", f.sim.tick == accepted_tick \
			and f.flap_mix_owner() == starting_owner and f.sim.inputs.to_byte_array() == accepted_inputs.to_byte_array())
		check("fault observers see prior owner", observations == [starting_owner, starting_owner])
		f.free()

func _record() -> void:
	var f := fixture()
	f.external_controller_selection = false
	var profile := Profile.defaults("radio", "radio_custom")
	profile.aux = {"flaps": {"type": "axis", "axis": 9, "invert": false, "off": -1.0, "on": 1.0}}
	f.radio.connect_device(42, INFO, profile)
	var axes := {0: 0.0, 1: 0.1, 2: -1.0, 3: 0.0, 9: -1.0}
	f.read_axis = func(_device: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	f.read_button = func(_device: int, _button: int) -> bool: return false
	f.read_raw = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var logger := Log.new(f)
	var path := out.path_join("ownership.orfl")
	check("recording starts", logger.start(path) == OK)
	for tick in 192:
		if tick == 64:
			profile = profile.duplicate(true)
			profile.flap_elevator_mix_owner = "transmitter"
			check("premixed profile activates", f.radio.use_profile(profile, "test"))
			axes[9] = -1.0
		if tick == 1 or tick == 65: axes[9] = 1.0
		if tick == 128: f.radio.disconnect_device()
		if tick < 128:
			for axis in axes: f.radio.on_motion(42, axis, axes[axis])
		f._physics_process(0.0)
		f.sim.step()
		if tick == 63: check("sampled radio default mixes", f.flap_mix_owner() == "simulator" and f.flap_mix_diagnostics()[0] < 0.0)
		if tick == 127: check("sampled premixed radio bypasses compensation", f.flap_mix_owner() == "transmitter" and f.flap_mix_diagnostics()[0] == 0.0)
	check("all input-path ticks accepted", f.sim.tick == 192 and f.sim.fault_reason.is_empty())
	check("recording completes", logger.stop() == OK)
	var inspected := Reader.inspect(path)
	check("recording validates", inspected.ok and inspected.complete and inspected.rows == 193)
	if not inspected.ok:
		f.free()
		return
	check("profile identity recorded", inspected.header.control_profile.has("profile_id") and inspected.header.control_profile.profile_sha256.length() == 64)
	var profile_events := 0
	for event in inspected.events:
		if event.kind == "control_profile": profile_events += 1
	check("profile change and keyboard fallback identified", profile_events == 2)
	var prepared := Reader.prepare_replay(inspected.header)
	check("exact replay prepared", prepared.ok)
	if prepared.ok:
		var replay: Node = prepared.flight
		var observer := Log.new(replay)
		var file := FileAccess.open(path, FileAccess.READ)
		file.seek(8)
		Log.read_packet(file)
		var first := true
		var exact := true
		while file.get_position() < file.get_length():
			var packet := Log.read_packet(file)
			if packet.value.kind == "footer": break
			for row: Dictionary in packet.value.rows:
				if not first:
					exact = exact and replay.restore_input_mix_owner(row.flap_mix_owner)
					replay.sim.inputs = row.inputs.duplicate()
					replay.sim.step()
				exact = exact and Reader.disagreement(row, observer._sample({})).is_empty()
				first = false
		check("all numeric samples replay exactly across ownership changes", exact)
		file.close()
		replay.free()
	var malformed: Dictionary = inspected.header.duplicate(true)
	malformed.erase("flap_mix_contract")
	check("stripped log declaration refused", not Reader.flap_mix_contract_error(malformed).is_empty())
	malformed = inspected.header.duplicate(true)
	malformed.layout.flap_mix = 4
	check("wrong diagnostic width refused", not Reader.flap_mix_contract_error(malformed).is_empty())
	malformed = inspected.header.duplicate(true)
	malformed.checkpoint.flap_mix_owner = "simulator"
	check("explicit simulator checkpoint extension refused", not Reader.flap_mix_contract_error(malformed).is_empty())
	malformed = inspected.header.duplicate(true)
	malformed.checkpoint.flap_mix_contract = Log.FLAP_MIX_CONTRACT
	check("checkpoint contract without transmitter owner refused", not Reader.flap_mix_contract_error(malformed).is_empty())
	var sample := logger._sample({})
	for owner in [null, true, 1, "bad"]:
		var bad: Dictionary = sample.duplicate(true)
		bad.flap_mix_owner = owner
		check("malformed row owner refused " + str(owner), not Reader.validate_row(bad, inspected.header.layout, bad.tick).is_empty())
	var old_layout: Dictionary = inspected.header.layout.duplicate(true)
	old_layout.erase("flap_mix")
	check("row owner cannot be silently downgraded", not Reader.validate_row(sample, old_layout, sample.tick).is_empty())
	f.free()
