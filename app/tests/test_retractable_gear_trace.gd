# AV-09: coupled retractable gear and flap state in deterministic flight traces.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Trace := preload("res://sim/trace.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Flaps := preload("res://physics/flaps.gd")
const GEAR_COLUMNS := ["gear_extension", "gear_target_down", "cmd_gear_down", "cmd_wheel_brake"]
const FLAP_COLUMNS := ["cmd_flaps", "flap_fraction", "flap_deg"]
const TURBULENCE_COLUMNS := ["turbulence_north_mps", "turbulence_east_mps", "turbulence_down_mps",
	"loads_turbulence_north_mps", "loads_turbulence_east_mps", "loads_turbulence_down_mps"]
const TURBULENCE_MODEL := "uniform-ned-cosine-plus-temporal-ou-pcg32-normal53-v1"

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _snapshot_matches(sim: Node, expected: Dictionary) -> bool:
	var actual: Dictionary = sim.checkpoint()
	for key: String in ["state", "previous", "aux", "inputs", "modes", "last_loads", "continuous",
		"tick", "stop_at_tick", "mass", "gravity", "inertia", "dt"]:
		if not actual.has(key) or not expected.has(key) or var_to_bytes(actual[key]) != var_to_bytes(expected[key]):
			return false
	return true


func _record_one(metadata: Dictionary, session: Node, inputs: PackedFloat64Array,
		aux: PackedFloat64Array) -> Trace:
	var malformed := Trace.new()
	malformed.meta = metadata.duplicate(true)
	malformed.meta.mass_trace_schema = "openrc-mass-sample v1"
	malformed.record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads, inputs, aux,
		session.sim.continuous.duplicate(), session.mass_properties())
	return malformed


func _initialize() -> void:
	var flight := Flight.new()
	flight.setup(Catalog.entry("sebart-avanti-s-a200-p100rx").data)
	_check("Avanti exposes retractable gear, flaps, and seven accepted inputs", flight.gear_is_retractable()
		and flight.flaps_available() and flight.sim.inputs.size() == 7)
	var turbulence := {
		"format": "openrc-weather v2",
		"speed_mps": 0.0,
		"from_deg": 0.0,
		"gust_mps": 0.0,
		"gust_up_mps": 0.0,
		"gust_duration_s": 1.0,
		"gust_period_s": 2.0,
		"gust_delay_s": 0.0,
		"turbulence_rms_mps": [0.15, 0.2, 0.1],
		"turbulence_tau_s": 0.8,
		"turbulence_seed": 20261014,
	}
	_check("configure deterministic turbulence", flight.setup_weather(turbulence))
	flight.reset()
	var start_state: Dictionary = flight.gear_state()
	var meta: Dictionary = flight.trace_meta()
	var gear_index: int = flight.gear_aux_index()
	var flap_index: int = flight.flap_aux_index()
	var turbulence_index: int = flight.turbulence_index()
	var continuous: Array = JSON.parse_string(meta.recording_start_continuous)
	var wheel_layout: Array = JSON.parse_string(meta.wheel_state_layout)
	_check("recording metadata uses v9 gear/flap and complete turbine/wheel/liquid state",
		meta.metadata_schema == "openrc-flight-meta v9" and meta.gear_law == "retractable-point-gear-v1"
		and meta.gear_trace_schema == "openrc-gear-trace v1" and wheel_layout.size() == flight.wheel_count()
		and continuous.size() == 1 + wheel_layout.size() + 2 and meta.flap_law == Flaps.LAW
		and meta.flap_trace_schema == "openrc-flap-trace v1" and meta.flap_input_index == 6)
	_check("gear, flap, and turbulence AUX states use the declared order",
		gear_index >= 4 and flap_index == gear_index + 2 and turbulence_index == flap_index + 1
		and flight.sim.aux.size() == turbulence_index + 7)
	_check("start snapshot records stowed gear target", start_state.available and start_state.extension == 0.0
		and not start_state.target_down and flight.flap_state().actual == 0.0)

	var recorder := Recorder.new(flight.sim, flight.electrical_state, Callable(flight, "mass_properties"))
	recorder.start(meta)
	var trace_columns: Array = recorder.trace.columns()
	var gear_column: int = trace_columns.find(GEAR_COLUMNS[0])
	var flap_column: int = trace_columns.find(FLAP_COLUMNS[0])
	_check("recorder starts a complete v15 liquid/mass trace with gear and flap channels",
		recorder.trace.row_count() == 1 and gear_column >= 0 and flap_column == gear_column + GEAR_COLUMNS.size()
		and trace_columns.slice(gear_column, gear_column + GEAR_COLUMNS.size()) == GEAR_COLUMNS
		and trace_columns.slice(flap_column, flap_column + FLAP_COLUMNS.size()) == FLAP_COLUMNS
		and trace_columns.has("fuel_remaining_kg") and trace_columns.has("mass_kg")
		and recorder.trace.value(0, "fuel_remaining_kg") > 0.0 and recorder.trace.value(0, "mass_kg") > 0.0
		and recorder.trace.to_csv().contains("# format: openrc-trace v15\n")
		and recorder.trace.to_csv().contains("# mass_base_trace_format: openrc-trace v12\n"))
	_check("gear, wheel brake, and flap requests are accepted in flight",
		flight.set_gear_down(true) and flight.set_wheel_brake(0.5) and flight.set_flaps(1.0))
	flight.sim.inputs = flight._inputs()
	flight.sim.step()
	var mid_state: Dictionary = flight.gear_state()
	var extension: float = mid_state.extension
	_check("recorded actuator advances between locks", extension > 0.0 and extension < 1.0
		and mid_state.target_down and mid_state.status == "extending")
	_check("trace row keeps gear state separate from the four legacy commands",
		recorder.trace.row_count() == 2 and recorder.trace.value(1, "gear_extension") == extension
		and recorder.trace.value(1, "gear_target_down") == 1.0
		and recorder.trace.value(1, "cmd_gear_down") == 1.0
		and recorder.trace.value(1, "cmd_wheel_brake") == 0.5)
	var flap_status: Dictionary = flight.flap_state()
	_check("trace records normalized flap demand and the slewing endpoint",
		flap_status.available and flap_status.actual > 0.0 and flap_status.actual < 1.0
		and recorder.trace.value(1, "cmd_flaps") == 1.0
		and recorder.trace.value(1, "flap_fraction") == flap_status.actual
		and is_equal_approx(recorder.trace.value(1, "flap_deg"), flap_status.angle_deg))
	var csv_text: String = recorder.trace.to_csv()
	var data_rows := PackedStringArray()
	for line: String in csv_text.split("\n"):
		if not line.is_empty() and not line.begins_with("#"):
			data_rows.append(line)
	var header := data_rows[0].split(",") if not data_rows.is_empty() else PackedStringArray()
	var row := data_rows[2].split(",") if data_rows.size() > 2 else PackedStringArray()
	var csv_gear_column: int = header.find(GEAR_COLUMNS[0])
	var csv_flap_column: int = header.find(FLAP_COLUMNS[0])
	_check("CSV round-trip preserves turbulence, gear/flap channels, and finite mass/fuel tails",
		data_rows.size() == 3 and csv_gear_column >= 0 and csv_flap_column == csv_gear_column + GEAR_COLUMNS.size()
		and Array(header.slice(csv_gear_column, csv_gear_column + GEAR_COLUMNS.size())) == GEAR_COLUMNS
		and Array(header.slice(csv_flap_column, csv_flap_column + FLAP_COLUMNS.size())) == FLAP_COLUMNS
		and Array(header.slice(-9)) == ["fuel_remaining_kg", "fuel_usable_kg", "fuel_fill_fraction", "fuel_reserve_fraction",
			"fuel_source_latch", "mass_kg", "cg_body_x_m", "cg_body_y_m", "cg_body_z_m"]
		and header.find(TURBULENCE_COLUMNS[0]) >= 0
		and header.find(TURBULENCE_COLUMNS[-1]) < header.find(GEAR_COLUMNS[0])
		and header.find(GEAR_COLUMNS[-1]) < header.find(FLAP_COLUMNS[0])
		and is_equal_approx(float(row[header.find("gear_extension")]), extension)
		and float(row[header.find("gear_target_down")]) == 1.0
		and is_equal_approx(float(row[header.find("flap_fraction")]), flap_status.actual)
		and float(row[header.find("fuel_remaining_kg")]) > 0.0
		and float(row[header.find("mass_kg")]) > 0.0)
	_check("trace metadata retains turbulence and full gear start snapshots",
		csv_text.contains("# gear_aux_index: %d\n" % gear_index)
		and csv_text.contains("# turbulence_aux_index: %d\n" % turbulence_index)
		and csv_text.contains("# gear_trace_schema: openrc-gear-trace v1\n")
		and csv_text.contains("# flap_trace_schema: openrc-flap-trace v1\n")
		and csv_text.contains("# flap_aux_index: %d\n" % flap_index)
		and csv_text.contains("# recording_start_gear: [0.0,0.0]\n"))

	# The gear extension and target, wheel spin, turbulence interval, and accepted command
	# all belong to the checkpoint boundary and replay without live input sampling.
	var checkpoint: Dictionary = flight.checkpoint()
	var checkpoint_copy: Dictionary = bytes_to_var(var_to_bytes(checkpoint))
	_check("mid-extension checkpoint carries explicit gear law and AUX position",
		not checkpoint.is_empty() and checkpoint.get("gear_law") == "retractable-point-gear-v1"
		and checkpoint.get("gear_aux_index") == gear_index
		and checkpoint.simulation.aux[gear_index] > 0.0 and checkpoint.simulation.aux[gear_index] < 1.0
		and checkpoint.simulation.aux[gear_index + 1] == 1.0
		and checkpoint.simulation.inputs[4] == 1.0 and checkpoint.simulation.inputs[5] == 0.5
		and checkpoint.get("flap_law") == Flaps.LAW
		and checkpoint.get("flap_aux_index") == flap_index and checkpoint.get("flap_input_index") == 6
		and checkpoint.simulation.aux[flap_index] > 0.0 and checkpoint.simulation.aux[flap_index] < 1.0
		and checkpoint.simulation.inputs[6] == 1.0)
	recorder.recording = false
	recorder.detach()
	for _tick in 12:
		flight.sim.step()
	var expected_replay: Dictionary = flight.sim.checkpoint()
	flight.reset()
	var restored: bool = flight.restore_checkpoint(checkpoint_copy)
	_check("mid-extension checkpoint restores the accepted actuator state", restored
		and flight.gear_state().extension == checkpoint.simulation.aux[gear_index]
		and flight.gear_state().target_down and flight.sim.inputs[5] == 0.5
		and flight.flap_state().actual == checkpoint.simulation.aux[flap_index]
		and flight.flap_state().requested == 1.0 and flight.sim.inputs[6] == 1.0)
	for _tick in 12:
		flight.sim.step()
	_check("gear and turbulence replay reproduce every simulation boundary bit", _snapshot_matches(flight.sim, expected_replay))

	# Reject a command/state mismatch, malformed target, shortened AUX, and a misplaced
	# turbulence tail at the recorder boundary. Invalid traces never emit partial CSV.
	var baseline_meta: Dictionary = flight.trace_meta()
	var start_mismatch: Dictionary = baseline_meta.duplicate(true)
	start_mismatch.recording_start_gear = "[0.0,1.0]"
	var mismatch_trace := _record_one(start_mismatch, flight, flight.sim.inputs,
		PackedFloat64Array(flight.sim.aux.slice(0, flight.sim.aux.size())))
	_check("recorder rejects a start target that disagrees with the first AUX pair",
		mismatch_trace.row_count() == 0 and mismatch_trace._invalid_weather)
	var bad_target_aux: PackedFloat64Array = flight.sim.aux.duplicate()
	bad_target_aux[gear_index + 1] = 0.5
	var bad_target_trace := _record_one(baseline_meta, flight, flight.sim.inputs, bad_target_aux)
	_check("recorder rejects a nonbinary actuator target in AUX",
		bad_target_trace.row_count() == 0 and bad_target_trace._invalid_weather)
	var short_aux: PackedFloat64Array = flight.sim.aux.slice(0, gear_index + 1)
	var short_aux_trace := _record_one(baseline_meta, flight, flight.sim.inputs, short_aux)
	_check("recorder rejects a truncated gear AUX pair",
		short_aux_trace.row_count() == 0 and short_aux_trace._invalid_weather)
	var misplaced_turbulence_meta: Dictionary = baseline_meta.duplicate(true)
	misplaced_turbulence_meta.turbulence_aux_index = turbulence_index + 1
	var misplaced_trace := _record_one(misplaced_turbulence_meta, flight, flight.sim.inputs, flight.sim.aux)
	_check("recorder rejects gear/turbulence AUX index overlap",
		misplaced_trace.row_count() == 0 and misplaced_trace._invalid_weather)
	var nonbinary_command: PackedFloat64Array = flight.sim.inputs.duplicate()
	nonbinary_command[4] = 0.5
	var bad_command_trace := _record_one(baseline_meta, flight, nonbinary_command, flight.sim.aux)
	_check("recorder rejects nonbinary gear command input",
		bad_command_trace.row_count() == 0 and bad_command_trace._invalid_weather)
	var invalid_flap_command: PackedFloat64Array = flight.sim.inputs.duplicate()
	invalid_flap_command[6] = 1.5
	var bad_flap_command_trace := _record_one(baseline_meta, flight, invalid_flap_command, flight.sim.aux)
	_check("recorder rejects flap command outside normalized endpoints",
		bad_flap_command_trace.row_count() == 0 and bad_flap_command_trace._invalid_weather)

	flight.free()
	print("AV-09 retractable gear trace: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
