extends SceneTree
const Flight: Script = preload("res://sim/flight_session.gd")
const BODY_STATE_SIZE: int = 13
const END_TIME_S: float = 0.05
const RATES: Array[int] = [120, 240, 480, 960]
const PACKS: Array[String] = ["4s", "6s"]
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var instrumented: bool = false

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() not in [1, 2] or not args[0].is_absolute_path() or (args.size() == 2 and args[1] != "--instrumented"):
		printerr("usage: -- ABSOLUTE_OUTPUT_DIRECTORY [--instrumented]")
		quit(2)
		return
	instrumented = args.has("--instrumented")
	var mode: String = "instrumented" if instrumented else "control"
	var mode_dir: String = args[0].path_join(mode)
	DirAccess.make_dir_recursive_absolute(mode_dir)
	for pack_name: String in PACKS:
		for hz: int in RATES:
			var row: Dictionary = run_case(pack_name, hz, mode_dir)
			rows.append(row)
			if not row.get("ok", false):
				failures.append("%s %d Hz: %s" % [pack_name, hz, str(row.get("failure", "unknown failure"))])
	var report: Dictionary = {"format": "el2-powered-parity-v1", "mode": mode,
		"instrumented": instrumented, "end_time_s": END_TIME_S, "rates_hz": RATES,
		"rows": rows, "failures": failures}
	var report_path: String = mode_dir.path_join("results.json")
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("could not write " + report_path)
		quit(2)
		return
	else:
		file.store_string(JSON.stringify(report, "\t", true))
		file.close()
	print(JSON.stringify({"mode": mode, "cases": rows.size(), "failures": failures, "result_path": report_path}))
	quit(1 if not failures.is_empty() else 0)

func run_case(pack_name: String, hz: int, mode_dir: String) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var a: Node = Flight.new()
	a.setup("res://data/aircraft/synthetic_stik_electric_%s_battery.json" % pack_name)
	if not a.is_flyable() or not a.battery_is_dynamic() or a.sim.continuous.size() != 4:
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "fixture did not produce a flyable 4-state battery session"}
	var loaded_trim_point: Dictionary = a.electrical_state()
	var q0: float = 0.20 if pack_name == "4s" else 0.12
	a.commands.throttle = 1.0
	a.sim.inputs = a._inputs()
	var checkpoint: Dictionary = a.checkpoint()
	if checkpoint.is_empty():
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "could not form powered native checkpoint"}
	checkpoint.simulation.continuous[1] = q0
	checkpoint.simulation.continuous[2] = 0.0
	checkpoint.simulation.continuous[3] = 0.0
	if not a.restore_checkpoint(bytes_to_var(var_to_bytes(checkpoint))):
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "native checkpoint rejected low-charge fixture"}
	var seed_bytes: PackedByteArray = var_to_bytes(a.checkpoint())
	var seed_name: String = "seed_%s_%dhz.bin" % [pack_name, hz]
	var seed_file: FileAccess = FileAccess.open(mode_dir.path_join(seed_name), FileAccess.WRITE)
	if seed_file == null:
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "could not write event-start checkpoint bytes"}
	seed_file.store_buffer(seed_bytes)
	seed_file.close()
	var pre_event_point: Dictionary = a.electrical_state()
	if not pre_event_point.ok or pre_event_point.duty != 1.0 or pre_event_point.remaining_charge_c != q0 \
			or pre_event_point.motor_current_a <= 0.0 or pre_event_point.pack_current_a <= 0.0:
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "pre-event point was not full-duty motoring"}

	var steps: int = roundi(END_TIME_S * float(hz))
	var initial_tick: int = a.sim.tick
	var event_tick: int = -1
	var event_step_usec: int = -1
	var event_tick_wall_usec: int = -1
	var events: Array[Dictionary] = []
	var all_finite: bool = true
	for index: int in steps:
		var prior_charge: float = a.sim.continuous[1]
		var wall_start: int = Time.get_ticks_usec()
		a.sim.step()
		var wall_elapsed_usec: int = Time.get_ticks_usec() - wall_start
		if a.sim.tick != initial_tick + index + 1 or not a.sim.fault_reason.is_empty():
			var why: String = a.sim.fault_reason
			a.free()
			return {"pack": pack_name, "hz": hz, "ok": false, "failure": "session tick failed: " + why}
		if event_tick < 0:
			if instrumented and not a._el2_probe_events.is_empty():
				events = a._el2_probe_events.duplicate(true)
				event_step_usec = a._el2_probe_step_usec
				event_tick = a.sim.tick
				event_tick_wall_usec = wall_elapsed_usec
			elif prior_charge > 0.0 and a.sim.continuous[1] == 0.0:
				event_tick = a.sim.tick
				event_tick_wall_usec = wall_elapsed_usec
		all_finite = all_finite and finite_array(a.sim.state) and finite_array(a.sim.continuous) and finite_array(a.sim.aux)

	var endpoint_point: Dictionary = a.electrical_state()
	var endpoint_checkpoint: Dictionary = a.checkpoint()
	var checkpoint_bytes: PackedByteArray = var_to_bytes(endpoint_checkpoint)
	var checkpoint_name: String = "checkpoint_%s_%dhz.bin" % [pack_name, hz]
	var checkpoint_path: String = mode_dir.path_join(checkpoint_name)
	var checkpoint_file: FileAccess = FileAccess.open(checkpoint_path, FileAccess.WRITE)
	if checkpoint_file == null:
		a.free()
		return {"pack": pack_name, "hz": hz, "ok": false, "failure": "could not write endpoint checkpoint bytes"}
	checkpoint_file.store_buffer(checkpoint_bytes)
	checkpoint_file.close()
	var prop: Dictionary = a.aircraft.model.propulsion
	var row: Dictionary = {
		"pack": pack_name, "hz": hz, "ok": true, "dt_s": a.sim.dt(), "steps": steps,
		"end_time_s": a.sim.time(), "event_tick": event_tick, "events": events,
		"event_step_usec": event_step_usec, "event_tick_wall_usec": event_tick_wall_usec,
		"event_start_charge_c": q0, "configured_initial_charge_c": a._battery_initial_charge(),
		"loaded_trim_point": loaded_trim_point, "pre_event_point": pre_event_point,
		"charge_c": a.sim.continuous[1], "terminal_energy_j": a.sim.continuous[2],
		"pack_heat_j": a.sim.continuous[3], "endpoint_point": endpoint_point,
		"body_state": Array(a.sim.state), "rotor_rpm": a.sim.continuous[0],
		"capacity_ah": prop.battery.capacity_ah, "ocv_points": Array(prop.battery.ocv_points),
		"all_finite": all_finite, "checkpoint_file": checkpoint_name,
		"checkpoint_byte_count": checkpoint_bytes.size(), "seed_checkpoint_file": seed_name,
		"seed_checkpoint_byte_count": seed_bytes.size(),
	}
	row.ok = row.all_finite and endpoint_point.ok and endpoint_point.exhausted \
		and a.sim.time() == END_TIME_S and a.sim.tick == steps and a.sim.continuous[1] == 0.0 \
		and endpoint_point.mode == "exhausted" and endpoint_point.bus_voltage_v == 0.0 \
		and endpoint_point.motor_current_a == 0.0 and endpoint_point.motor_bus_current_a == 0.0 \
		and endpoint_point.battery_current_a == 0.0 and endpoint_point.auxiliary_current_a == 0.0 \
		and endpoint_point.pack_current_a == 0.0 and endpoint_point.pack_terminal_power_w == 0.0 \
		and endpoint_point.pack_loss_w == 0.0 and a.sim.continuous[2] > 0.0 and a.sim.continuous[3] > 0.0 \
		and event_tick >= 1 and (not instrumented or (events.size() == 1 and events[0].type == "battery_exhausted"))
	if not row.ok:
		row.failure = "endpoint/event/disconnect invariants failed"
	a.free()
	return row

func finite_array(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
