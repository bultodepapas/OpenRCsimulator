extends SceneTree

const Flight: Script = preload("res://sim/flight_session.gd")
const TICK_HZ: int = 240
const POST_EVENT_TICKS: int = 8


func _initialize() -> void:
	var output_dir: String = ""
	var smoke: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_dir = argument.trim_prefix("--out=")
		elif argument == "--smoke":
			smoke = true
		else:
			printerr("unknown argument: " + argument)
			quit(2)
			return
	if output_dir.is_empty() or not output_dir.is_absolute_path():
		printerr("usage: -- --out=ABSOLUTE_DIRECTORY [--smoke]")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_dir) != OK:
		printerr("could not create output directory: " + output_dir)
		quit(2)
		return

	Engine.physics_ticks_per_second = TICK_HZ
	var rows: Array[Dictionary] = []
	var failures: Array[String] = []
	for specification: Dictionary in _case_specs(smoke):
		var row: Dictionary = _run_case(specification, output_dir)
		rows.append(row)
		if not row.get("ok", false):
			failures.append("%s: %s" % [str(specification.get("id", "case")), str(row.get("failure", "failed"))])
	var report: Dictionary = {
		"format": "el2a-p2-whole-session-event-probe-v1",
		"tick_hz": TICK_HZ,
		"smoke": smoke,
		"session_start": "FlightSession.setup trimmed airborne start; one fresh FlightSession per case",
		"event_timing": "wall microseconds around only the fixed simulation tick containing an accepted event",
		"event_state": "accepted full-step endpoint at the containing tick; root floats are intentionally not exposed",
		"rows": rows,
		"failures": failures,
	}
	var report_file: FileAccess = FileAccess.open(output_dir.path_join("probe.json"), FileAccess.WRITE)
	if report_file == null:
		printerr("could not write probe.json")
		quit(2)
		return
	report_file.store_string(JSON.stringify(report, "\t", true))
	report_file.close()
	print(JSON.stringify({"cases": rows.size(), "failures": failures, "probe": output_dir.path_join("probe.json")}))
	quit(1 if not failures.is_empty() else 0)


func _case_specs(smoke: bool) -> Array[Dictionary]:
	if smoke:
		return [{
			"id": "battery-powered-smoke-4s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_4s_battery.json",
			"mode": "battery",
			"engine_running": true,
			"throttle": 1.0,
			"charge_c": 0.20,
			"max_time_s": 0.05,
			"required_events": ["battery_exhausted"],
		}]
	return [
		{
			"id": "battery-powered-4s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_4s_battery.json",
			"mode": "battery",
			"engine_running": true,
			"throttle": 1.0,
			"charge_c": 4.0,
			"max_time_s": 3.0,
			"required_events": ["battery_exhausted"],
		},
		{
			"id": "battery-coast-4s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_4s_battery.json",
			"mode": "battery",
			"engine_running": false,
			"throttle": 0.0,
			"charge_c": 0.25,
			"max_time_s": 3.0,
			"required_events": ["battery_exhausted"],
		},
		{
			"id": "battery-powered-6s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_6s_battery.json",
			"mode": "battery",
			"engine_running": true,
			"throttle": 1.0,
			"charge_c": 2.4,
			"max_time_s": 3.0,
			"required_events": ["battery_exhausted"],
		},
		{
			"id": "battery-coast-6s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_6s_battery.json",
			"mode": "battery",
			"engine_running": false,
			"throttle": 0.0,
			"charge_c": 0.25,
			"max_time_s": 3.0,
			"required_events": ["battery_exhausted"],
		},
		{
			"id": "fixed-voltage-rotor-stop",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_4s.json",
			"mode": "fixed_voltage",
			"engine_running": true,
			"throttle": 1.0,
			"cut_after_ticks": 120,
			"max_time_s": 20.0,
			"required_events": ["rotor_stop"],
		},
		{
			"id": "battery-no-event-4s",
			"aircraft": "res://data/aircraft/synthetic_stik_electric_4s_battery.json",
			"mode": "no_event",
			"engine_running": true,
			"throttle": 0.5,
			"ticks": TICK_HZ,
			"required_events": [],
		},
	]


func _run_case(specification: Dictionary, output_dir: String) -> Dictionary:
	var aircraft_path: String = str(specification.aircraft)
	var flight: Node = Flight.new()
	flight.setup(aircraft_path)
	var result: Dictionary = {"id": specification.id, "ok": false, "failure": ""}
	if not flight.is_flyable() or flight.sim == null or flight.sim.tick != 0:
		flight.free()
		result.failure = "fresh trimmed FlightSession was not flyable at tick zero"
		return result
	var dynamic_battery: bool = flight.battery_is_dynamic()
	if specification.mode == "battery" and not dynamic_battery:
		flight.free()
		result.failure = "dynamic-battery fixture did not load a charge state"
		return result
	if specification.mode == "fixed_voltage" and dynamic_battery:
		flight.free()
		result.failure = "fixed-voltage fixture unexpectedly loaded a dynamic pack"
		return result

	var rotor_index: int = flight._rotor_index()
	var charge_index: int = rotor_index + 1 if dynamic_battery else -1
	flight.engine_running = bool(specification.engine_running)
	flight.commands.throttle = float(specification.throttle)
	flight.sim.inputs = flight._inputs()
	if dynamic_battery and specification.has("charge_c"):
		var seed: Dictionary = flight.checkpoint()
		var continuous: PackedFloat64Array = seed.simulation.continuous.duplicate()
		if charge_index >= continuous.size() or float(specification.charge_c) <= 0.0:
			flight.free()
			result.failure = "requested initial charge does not fit the loaded state"
			return result
		continuous[charge_index] = float(specification.charge_c)
		seed.simulation.continuous = continuous
		if not flight.restore_checkpoint(seed):
			flight.free()
			result.failure = "near-empty native start checkpoint was rejected"
			return result
	var start_bytes: PackedByteArray = var_to_bytes(flight.checkpoint())
	var seed_name: String = str(specification.id) + "-seed.bin"
	if not _write_bytes(output_dir.path_join(seed_name), start_bytes):
		flight.free()
		result.failure = "could not save full native seed checkpoint"
		return result

	var events: Array[Dictionary] = []
	var start_charge: float = flight.sim.continuous[charge_index] if dynamic_battery else -1.0
	var step_count: int = int(specification.ticks) if specification.mode == "no_event" \
		else roundi(float(specification.max_time_s) * float(TICK_HZ))
	var stop_after_tick: int = -1
	var required: Array = specification.required_events
	var event_wall_samples: Dictionary = {}
	var all_finite: bool = true
	var saw_unsafe_rpm: bool = false
	var cut_applied: bool = false
	for index: int in step_count:
		if specification.has("cut_after_ticks") and not cut_applied and flight.sim.tick >= int(specification.cut_after_ticks):
			flight.commands.throttle = 0.0
			cut_applied = true
		flight.sim.inputs = flight._inputs()
		var previous_charge: float = flight.sim.continuous[charge_index] if dynamic_battery else -1.0
		var previous_rpm: float = flight.sim.continuous[rotor_index]
		var tick_start_usec: int = Time.get_ticks_usec()
		flight.sim.step()
		var tick_wall_usec: int = Time.get_ticks_usec() - tick_start_usec
		if flight.sim.fault_reason != "":
			result.failure = "simulation fault: " + flight.sim.fault_reason
			break
		if flight.sim.tick != index + 1:
			result.failure = "session tick counter advanced unexpectedly"
			break
		var current_rpm: float = flight.sim.continuous[rotor_index]
		if current_rpm < 0.0:
			saw_unsafe_rpm = true
		var transitioned: Array[String] = []
		if dynamic_battery and previous_charge > 0.0 and flight.sim.continuous[charge_index] == 0.0:
			transitioned.append("battery_exhausted")
		if previous_rpm > 0.0 and current_rpm == 0.0:
			transitioned.append("rotor_stop")
		for event_type: String in transitioned:
			var sample: Dictionary = {
				"type": event_type,
				"tick": flight.sim.tick,
				"containing_tick_time_s": flight.sim.time(),
				"event_tick_wall_usec": tick_wall_usec,
				"body_state": Array(flight.sim.state),
				"continuous_state": Array(flight.sim.continuous),
				"rotor_index": rotor_index,
				"charge_index": charge_index,
				"rotor_rpm": current_rpm,
				"remaining_charge_c": flight.sim.continuous[charge_index] if dynamic_battery else -1.0,
				"terminal_energy_j": flight.sim.continuous[charge_index + 1] if dynamic_battery else 0.0,
				"pack_heat_j": flight.sim.continuous[charge_index + 2] if dynamic_battery else 0.0,
			}
			events.append(sample)
			event_wall_samples[event_type] = tick_wall_usec
			if required.has(event_type):
				stop_after_tick = maxi(stop_after_tick, flight.sim.tick + POST_EVENT_TICKS)
		if not _finite_values(flight.sim.state) or not _finite_values(flight.sim.continuous) \
				or (dynamic_battery and flight.sim.continuous[charge_index] < 0.0):
			result.failure = "accepted state contains a nonfinite or negative-charge value"
			break
		if not transitioned.is_empty():
			for k: int in range(1, events.size()):
				if int(events[k].tick) < int(events[k - 1].tick):
					result.failure = "observed events are out of chronological tick order"
					break
		if not result.failure.is_empty():
			break
		if specification.mode == "no_event" and flight.sim.tick >= int(specification.ticks):
			break
		if not required.is_empty() and stop_after_tick >= 0 and flight.sim.tick >= stop_after_tick:
			break

	var endpoint_bytes: PackedByteArray = var_to_bytes(flight.checkpoint())
	var endpoint_name: String = str(specification.id) + "-endpoint.bin"
	if not _write_bytes(output_dir.path_join(endpoint_name), endpoint_bytes) and result.failure == "":
		result.failure = "could not save full native endpoint checkpoint"
	var event_types: Array[String] = []
	for event: Dictionary in events:
		event_types.append(str(event.type))
	for event_type: String in required:
		if not event_types.has(event_type) and result.failure == "":
			result.failure = "required event did not occur: " + event_type
	if specification.mode == "no_event" and not events.is_empty() and result.failure == "":
		result.failure = "no-event control crossed an event boundary"
	if saw_unsafe_rpm and result.failure == "":
		result.failure = "accepted relative rotor RPM became negative"
	var electrical: Dictionary = flight.electrical_state() if dynamic_battery else {"ok": false}
	result.merge({
		"ok": result.failure == "",
		"mode": specification.mode,
		"aircraft_path": aircraft_path,
		"dynamic_battery": dynamic_battery,
		"engine_running": bool(specification.engine_running),
		"initial_throttle": float(specification.throttle),
		"cut_after_ticks": int(specification.get("cut_after_ticks", -1)),
		"tick_hz": TICK_HZ,
		"ticks": flight.sim.tick,
		"end_time_s": flight.sim.time(),
		"initial_charge_c": start_charge,
		"final_charge_c": flight.sim.continuous[charge_index] if dynamic_battery else -1.0,
		"final_rotor_rpm": flight.sim.continuous[rotor_index],
		"final_electrical_mode": str(electrical.get("mode", "")),
		"all_finite": _finite_values(flight.sim.state) and _finite_values(flight.sim.continuous),
		"event_types": event_types,
		"event_wall_samples_usec": event_wall_samples,
		"events": events,
		"required_events": required,
		"seed_checkpoint_file": seed_name,
		"seed_checkpoint_bytes": start_bytes.size(),
		"endpoint_checkpoint_file": endpoint_name,
		"endpoint_checkpoint_bytes": endpoint_bytes.size(),
	}, true)
	flight.free()
	return result


func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.close()
	return true


func _finite_values(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
