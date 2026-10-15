## AV-09: flap actuator, AUX routing, checkpoints, and exact log replay.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
const Trace := preload("res://sim/trace.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flaps := preload("res://physics/flaps.gd")
const RB := preload("res://physics/rigid_body.gd")
const Profile := preload("res://input/controller_profile.gd")

const AVANTI := "sebart-avanti-s-a200-p100rx"
const OTHER := "gp-extra-300s-60"
const DEVICE_ID := 42
const INFO := {"guid": "fake-av09-radio", "name": "EdgeTX radio", "vendor_id": 0x1209, "product_id": 0x4f54}

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _step(session: Node, count: int) -> void:
	for _tick in count:
		session.sim.inputs = session._inputs()
		session.sim.step()


func _snapshot_matches(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in ["state", "previous", "aux", "inputs", "modes", "last_loads", "continuous",
			"tick", "stop_at_tick", "mass", "gravity", "inertia", "dt"]:
		if not actual.has(key) or not expected.has(key) or var_to_bytes(actual[key]) != var_to_bytes(expected[key]):
			return false
	return true


func _initialize() -> void:
	_check_avanti_actuator()
	_check_radio_aux_path()
	_check_checkpoint_and_log_replay()
	_check_unchanged_other_aircraft()
	print("AV-09 flaps session: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check_avanti_actuator() -> void:
	var flight: Node = Flight.new()
	flight.setup(Catalog.entry(AVANTI).data)
	_check("Avanti is flyable with the declared flap module", flight.is_flyable() and flight.flaps_available())
	_check("flap input and AUX follow retractable gear slots",
		flight.flap_input_index() == 6 and flight.flap_aux_index() == flight.gear_aux_index() + 2
		and flight.sim.inputs.size() == 7)
	var start: Dictionary = flight.flap_state()
	_check("reset state starts with the actuator retracted", start.available and start.actual == 0.0
		and start.requested == 0.0 and start.angle_deg == 0.0)

	_check("full flap request is accepted", flight.set_flaps(1.0))
	flight.sim.inputs = flight._inputs()
	flight.sim.step()
	var first: Dictionary = flight.flap_state()
	_check("extension slews from zero by a finite fraction", is_finite(first.actual)
		and first.actual > 0.0 and first.actual < 1.0 and first.moving)
	_step(flight, 12)
	var extended: Dictionary = flight.flap_state()
	_check("extension continues monotonically without an instant jump", extended.actual > first.actual
		and extended.actual < 1.0 and is_finite(extended.angle_deg))

	_check("retraction request is accepted", flight.set_flaps(0.0))
	_step(flight, 1)
	var first_retract: Dictionary = flight.flap_state()
	_check("retraction slews from the deployed side", first_retract.actual < extended.actual
		and first_retract.actual > 0.0 and first_retract.moving)
	_step(flight, 12)
	_check("retraction remains finite and monotonic", is_finite(flight.flap_state().actual)
		and flight.flap_state().actual < first_retract.actual)

	flight.reset()
	var reset_status: Dictionary = flight.flap_state()
	_check("reset clears flap demand and actual actuator position", reset_status.actual == 0.0
		and reset_status.requested == 0.0 and flight.sim.inputs[flight.flap_input_index()] == 0.0)

	var advisory_limit: float = flight.flap_state().limit_mps
	flight.sim.state[RB.VEL] = advisory_limit + 5.0
	flight.sim.previous[RB.VEL] = advisory_limit + 5.0
	_check("overspeed advisory does not reject flap demand", flight.set_flaps(1.0))
	_step(flight, 3)
	var advisory_state: Dictionary = flight.flap_state()
	_check("flaps continue to move above the advisory limit", advisory_state.overspeed
		and advisory_state.actual > 0.0 and advisory_state.moving)
	var before_pause: float = flight.flap_state().actual
	var before_tick: int = flight.sim.tick
	flight.sim.set_paused(true)
	_check("paused flight refuses an actuator request", not flight.set_flaps(0.0))
	flight._physics_process(0.0)
	flight.sim._physics_process(0.0)
	_check("pause holds both the accepted tick and flap position", flight.sim.tick == before_tick
		and flight.flap_state().actual == before_pause,
		"tick %d→%d; flap %.9f→%.9f" % [before_tick, flight.sim.tick, before_pause, flight.flap_state().actual])
	flight.sim.set_paused(false)
	flight._physics_process(0.0)
	flight.sim._physics_process(0.0)
	_check("resume advances the requested flap slew", flight.sim.tick == before_tick + 1
		and flight.flap_state().actual > before_pause,
		"tick %d→%d; flap %.9f→%.9f" % [before_tick, flight.sim.tick, before_pause, flight.flap_state().actual])
	flight.free()


func _check_radio_aux_path() -> void:
	var flight: Node = Flight.new()
	flight.setup(Catalog.entry(AVANTI).data)
	flight.external_controller_selection = false
	flight.sim.set_paused(false)
	var profile: Dictionary = Profile.defaults("radio", "radio_custom")
	profile.aux = {"flaps": {"type": "axis", "axis": 9, "invert": false, "off": -1.0, "on": 1.0}}
	_check("test radio AUX profile is valid", Profile.validate(profile).ok)
	flight.radio.connect_device(DEVICE_ID, INFO, profile)
	var axes: Dictionary = {0: 0.0, 1: 0.0, 2: -1.0, 3: 0.0, 9: -1.0}
	flight.read_axis = func(_device: int, axis: int) -> float: return float(axes.get(axis, 0.0))
	flight.read_button = func(_device: int, _button: int) -> bool: return false
	flight.radio.on_motion(DEVICE_ID, 9, -1.0)
	flight._physics_process(0.0) # selected AUX channel's OFF sample arms its axis binding
	flight.sim.step()
	axes[9] = 1.0
	flight.radio.on_motion(DEVICE_ID, 9, 1.0)
	flight._physics_process(0.0)
	flight.sim._physics_process(0.0)
	var radio_status: Dictionary = flight.flap_state()
	_check("radio AUX reaches the appended flap input", radio_status.requested == 1.0
		and flight.sim.inputs[flight.flap_input_index()] == 1.0,
		"connected=%s aux=%.3f request=%.3f input=%.3f profile=%s" % [str(flight.radio.connected),
		flight.radio.auxiliary_amount("flaps"), radio_status.requested,
		flight.sim.inputs[flight.flap_input_index()], str(flight.radio.profile.get("aux", {}))])
	_check("radio AUX drives the real actuator on a physics tick", radio_status.actual > 0.0
		and radio_status.actual < 1.0 and radio_status.moving,
		"actual=%.9f requested=%.3f tick=%d" % [radio_status.actual, radio_status.requested, flight.sim.tick])
	flight.free()


func _check_checkpoint_and_log_replay() -> void:
	var flight: Node = Flight.new()
	flight.setup(Catalog.entry(AVANTI).data)
	flight.set_flaps(1.0)
	_step(flight, 40)
	var checkpoint: Dictionary = flight.checkpoint()
	var checkpoint_copy: Dictionary = bytes_to_var(var_to_bytes(checkpoint))
	var flap_index: int = flight.flap_aux_index()
	_check("checkpoint records the flap law, slots, moving actuator, and request",
		not checkpoint.is_empty() and checkpoint.get("flap_law") == Flaps.LAW
		and checkpoint.get("flap_aux_index") == flap_index and checkpoint.get("flap_input_index") == 6
		and checkpoint.simulation.aux[flap_index] > 0.0 and checkpoint.simulation.aux[flap_index] < 1.0
		and checkpoint.simulation.inputs[6] == 1.0)
	var tape_count: int = int(ceil(float(flight.aircraft.model.flaps.extension_time) / flight.sim.dt())) + 8
	_step(flight, tape_count)
	var expected: Dictionary = flight.sim.checkpoint()
	flight.reset()
	_check("flap checkpoint restores after reset", flight.restore_checkpoint(checkpoint_copy)
		and flight.flap_state().actual == checkpoint.simulation.aux[flap_index]
		and flight.flap_state().requested == 1.0)
	_step(flight, tape_count)
	_check("restored flap actuator and dynamics replay bit for bit", _snapshot_matches(flight.sim.checkpoint(), expected))

	var before_reject: PackedByteArray = var_to_bytes(flight.sim.checkpoint())
	var wrong_slot: Dictionary = checkpoint_copy.duplicate(true)
	wrong_slot.flap_input_index = 5
	_check("checkpoint with a wrong flap input slot is rejected atomically",
		not flight.restore_checkpoint(wrong_slot) and var_to_bytes(flight.sim.checkpoint()) == before_reject)
	var invalid_aux: Dictionary = checkpoint_copy.duplicate(true)
	invalid_aux.simulation.aux[flap_index] = NAN
	_check("checkpoint with non-finite flap AUX is rejected atomically",
		not flight.restore_checkpoint(invalid_aux) and var_to_bytes(flight.sim.checkpoint()) == before_reject)

	# The file starts during flap motion, records full deployment and retraction, then exact-replays each tick.
	var record_flight: Node = Flight.new()
	record_flight.setup(Catalog.entry(AVANTI).data)
	_check("recording session accepts a flap request", record_flight.set_flaps(1.0))
	_step(record_flight, 1)
	var log_path: String = ProjectSettings.globalize_path("res://../tmp/av09-flaps-%d.orfl" % Time.get_ticks_usec())
	var logger := FlightLog.new(record_flight)
	_check("moving-flap recording starts", logger.start(log_path) == OK)
	var full_extension_ticks: int = int(ceil(float(record_flight.aircraft.model.flaps.extension_time) / record_flight.sim.dt())) + 8
	for _tick in full_extension_ticks:
		record_flight.sim.inputs = record_flight._inputs()
		record_flight.sim.step()
	var deployed: Dictionary = record_flight.flap_state()
	_check("recorded run reaches the declared full flap stop", deployed.actual >= 1.0 - 1e-12 and not deployed.moving)
	_check("retraction command is accepted in the same recording", record_flight.set_flaps(0.0))
	_step(record_flight, 32)
	var retracting: Dictionary = record_flight.flap_state()
	_check("recording includes a finite retraction interval", retracting.actual > 0.0 and retracting.actual < 1.0 and retracting.moving)
	_check("moving flap recording finishes cleanly", logger.stop() == OK)
	var inspected: Dictionary = Reader.inspect(log_path)
	_check("moving flap log is complete and readable", inspected.ok and inspected.complete and inspected.rows > 40)
	if inspected.ok:
		var prepared: Dictionary = Reader.prepare_replay(inspected.header)
		_check("flap checkpoint prepares for exact replay", prepared.ok)
		if prepared.ok:
			var stream := FileAccess.open(log_path, FileAccess.READ)
			stream.seek(8)
			FlightLog.read_packet(stream)
			var first := true
			var replayed: int = 0
			var replay_exact: bool = true
			var observer := FlightLog.new(prepared.flight)
			while stream.get_position() < stream.get_length():
				var packet: Dictionary = FlightLog.read_packet(stream)
				if not packet.get("ok", false):
					replay_exact = false
					break
				var block: Dictionary = packet.value
				if block.kind == "footer":
					break
				for row: Dictionary in block.rows:
					if first:
						first = false
						continue
					for key: String in row.intervention:
						prepared.flight.sim.set(key, row.intervention[key].duplicate())
					prepared.flight.sim.inputs = row.inputs.duplicate()
					prepared.flight.sim.step()
					if not Reader.disagreement(row, observer._sample({})).is_empty():
						replay_exact = false
						break
					replayed += 1
				if not replay_exact:
					break
			stream.close()
			prepared.flight.free()
			_check("flap actuator exact replay reproduces every recorded tick", replay_exact and replayed == inspected.rows - 1,
				"replayed %d of %d ticks" % [replayed, inspected.rows - 1])
	if FileAccess.file_exists(log_path):
		_check("temporary flap replay file removed", DirAccess.remove_absolute(log_path) == OK)
	record_flight.free()
	flight.free()


func _check_unchanged_other_aircraft() -> void:
	var flight: Node = Flight.new()
	flight.setup(Catalog.entry(OTHER).data)
	_check("non-flap Extra keeps its original input and AUX layouts",
		flight.is_flyable() and not flight.flaps_available() and flight.flap_input_index() == -1
		and flight.flap_aux_index() == -1 and flight.sim.inputs.size() == 4)
	var meta: Dictionary = flight.trace_meta()
	var trace := Trace.new()
	trace.meta = meta
	trace.record(0, 0.0, flight.sim.state, flight.sim.last_loads, flight.sim.inputs, flight.sim.aux,
		flight.sim.continuous)
	_check("non-flap trace has no flap metadata or output columns", trace.row_count() == 1
		and not meta.has("flap_law") and not trace.columns().has("cmd_flaps")
		and not trace.columns().has("flap_fraction") and not trace.columns().has("flap_deg"))
	var initial_aux_size: int = flight.sim.aux.size()
	_step(flight, 30)
	_check("non-flap aircraft keeps the same channel lengths through flight", flight.sim.inputs.size() == 4
		and flight.sim.aux.size() == initial_aux_size and not flight.flaps_available())
	flight.free()
