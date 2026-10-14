# C7: the flight trace — complete, self-describing, exact enough to debug with.
# Run: godot --headless --path . --script res://tests/test_trace.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const Trace := preload("res://sim/trace.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _float64_bits(value: float) -> int:
	var encoded := PackedByteArray()
	encoded.resize(8)
	encoded.encode_double(0, value)
	return encoded.decode_u64(0)


func _float64_from_bits(bits: int) -> float:
	var encoded := PackedByteArray()
	encoded.resize(8)
	encoded.encode_u64(0, bits)
	return encoded.decode_double(0)


func _coupled_trace_meta() -> Dictionary:
	return {
		"propulsion_model": "propeller-shaft-coupled-rk4-v1",
		"shaft_integrator": "coupled-rk4",
		"rotor_coupling": "relative-spin-locked-inertia-reaction-v1",
		"continuous_layout": "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled",
		# JSON-decoded initial RPM for the hot-high P-51 trace boundary regression.
		"recording_start_continuous": "[3618.1583849604676]",
		"recording_start_aux": "[3618.1583849604676,0.0,0.0,0.0]",
	}


func _gear_trace_meta(dt: float) -> Dictionary:
	return {
		"metadata_schema": "openrc-flight-meta v8",
		"gear_law": "retractable-point-gear-v1",
		"gear_aux_index": 4,
		"gear_trace_schema": "openrc-gear-trace v1",
		"input_layout": JSON.stringify(["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake"]),
		"recording_start_tick": 0,
		"recording_start_gear": "[0.0,1.0]",
		"dt_s": dt,
	}


func _turbine_gear_trace_meta(dt: float) -> Dictionary:
	var contacts := ["nose", "left_main", "right_main"]
	var layout: Array = []
	var brakes: Array = []
	for i: int in contacts.size():
		layout.append({"index": i + 1, "contact": contacts[i], "unit": "m/s rim speed"})
		brakes.append({"contact": contacts[i], "availability": "available" if i > 0 else "none",
			"max_torque_nm": 12.0 if i > 0 else 0.0})
	return {
		"metadata_schema": "openrc-flight-meta v8",
		"propulsion_model": "turbine-rpm-governor-rk4-v1",
		"turbine_integrator": "rk4",
		"continuous_layout": "turbine shaft rpm; RK4 coupled; prescribed fuel mass; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail",
		"recording_start_continuous": "[44000.0,0.0,0.0,0.0]",
		"recording_start_aux": "[44000.0,0.0,0.0,0.0]",
		"wheel_state_model": "relative-wheel-rim-speed-rk4-v1",
		"wheel_state_layout": JSON.stringify(layout),
		"wheel_profile_status": "applied",
		"wheel_profile_sha256": "a".repeat(64),
		"wheel_profile_input_sha256": "b".repeat(64),
		"wheel_profile_hash_convention": "profile_sha256 is canonical JSON for the selected aircraft profile; input_sha256 is SHA-256 of exact wheel_profiles.json bytes",
		"wheel_brakes": JSON.stringify(brakes),
		"launch_continuous": "[44000.0,0.0,0.0,0.0]",
		"gear_law": "retractable-point-gear-v1",
		"gear_aux_index": 4,
		"gear_trace_schema": "openrc-gear-trace v1",
		"input_layout": JSON.stringify(["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake"]),
		"recording_start_tick": 0,
		"recording_start_gear": "[0.0,1.0]",
		"dt_s": dt,
	}


func _initialize() -> void:
	var sim: Node = Sim.new()
	var aircraft := AircraftData.load_file(Scenarios.AIRCRAFT)
	sim.mass = aircraft.model.mass_kg
	sim.inertia = aircraft.model.inertia
	root.add_child(sim)
	var trace := Trace.new()
	trace.meta = { scenario = "test" }
	sim.stepped.connect(trace.record)
	sim.reset(Scenarios.throw_across_view())
	for i in 360:
		sim.step()

	# Completeness: tick 0 plus one row per step, no gaps, time = tick · dt.
	_check("361 rows for 1.5 s at 240 Hz", trace.row_count() == 361, str(trace.row_count()))
	_check("no missing ticks", trace.gaps().is_empty(), str(trace.gaps()))
	_check("ticks continuous from 0", trace.is_continuous() and trace.value(0, "tick") == 0.0)
	var time_ok := true
	for r in trace.row_count():
		time_ok = time_ok and absf(trace.value(r, "t_s") - trace.value(r, "tick") * sim.dt()) < 1e-12
	_check("t_s = tick · dt", time_ok)

	# JSON metadata is allowed one adjacent positive float64 and must reject two ULPs.
	var header_rpm := 3618.1583849604676
	var coupled_trace := Trace.new()
	coupled_trace.meta = _coupled_trace_meta()
	var fractional_rpm := _float64_from_bits(_float64_bits(header_rpm) + 1)
	coupled_trace.record(0, 0.0, sim.state, sim.last_loads, sim.inputs,
		PackedFloat64Array([fractional_rpm, 0.0, 0.0, 0.0]))
	_check("coupled trace fixture is one ULP above decoded JSON RPM",
		_float64_bits(fractional_rpm) - _float64_bits(coupled_trace._coupled_start_rpm) == 1)
	_check("coupled trace accepts one-ULP JSON RPM round-trip", coupled_trace.row_count() == 1
		and not coupled_trace._invalid_weather
		and Trace._positive_float64_within_one_ulp(fractional_rpm, coupled_trace._coupled_start_rpm))
	var two_ulp_trace := Trace.new()
	two_ulp_trace.meta = _coupled_trace_meta()
	var two_ulp_rpm := _float64_from_bits(_float64_bits(header_rpm) + 2)
	two_ulp_trace.record(0, 0.0, sim.state, sim.last_loads, sim.inputs,
		PackedFloat64Array([two_ulp_rpm, 0.0, 0.0, 0.0]))
	_check("coupled trace rejects two-ULP RPM mismatch",
		_float64_bits(two_ulp_rpm) - _float64_bits(two_ulp_trace._coupled_start_rpm) == 2
		and two_ulp_trace.row_count() == 0 and two_ulp_trace._invalid_weather)
	var mismatched_trace := Trace.new()
	mismatched_trace.meta = _coupled_trace_meta()
	mismatched_trace.record(0, 0.0, sim.state, sim.last_loads, sim.inputs,
		PackedFloat64Array([header_rpm + 1e-6, 0.0, 0.0, 0.0]))
	_check("coupled trace rejects a 1e-6 RPM start mismatch", mismatched_trace.row_count() == 0
		and mismatched_trace._invalid_weather)

	# Retractable gear adds four explicit tail columns, while keeping the legacy four commands aligned.
	var gear_state := PackedFloat64Array([0.0, 0.0, 5.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var gear_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var gear_inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.25])
	var gear_aux := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	var gear_trace := Trace.new()
	gear_trace.meta = _gear_trace_meta(sim.dt())
	gear_trace.record(0, 0.0, gear_state, gear_loads, gear_inputs, gear_aux)
	gear_aux[4] = 0.2
	gear_trace.record(1, sim.dt(), gear_state, gear_loads, gear_inputs, gear_aux)
	_check("gear trace records six inputs in stable tail columns", gear_trace.row_count() == 2
		and not gear_trace._invalid_weather and gear_trace.columns().slice(-4) == Trace.GEAR_COLUMNS)
	_check("gear trace keeps the four legacy cmd columns aligned", gear_trace.value(1, "cmd_throttle") == 0.0
		and gear_trace.value(1, "gear_extension") == 0.2 and gear_trace.value(1, "gear_target_down") == 1.0
		and gear_trace.value(1, "cmd_gear_down") == 1.0 and gear_trace.value(1, "cmd_wheel_brake") == 0.25)
	var turbine_gear_trace := Trace.new()
	turbine_gear_trace.meta = _turbine_gear_trace_meta(sim.dt())
	var turbine_gear_aux := PackedFloat64Array([44000.0, 0.0, 0.0, 0.0, 0.0, 1.0])
	turbine_gear_trace.record(0, 0.0, gear_state, gear_loads, gear_inputs, turbine_gear_aux,
		PackedFloat64Array([44000.0, 0.0, 0.0, 0.0]))
	_check("v8 turbine trace accepts complete gear and wheel tails",
		turbine_gear_trace.row_count() == 1 and not turbine_gear_trace._invalid_weather
		and turbine_gear_trace.columns().slice(-4) == Trace.GEAR_COLUMNS)
	var incomplete_turbine_gear := Trace.new()
	var incomplete_turbine_meta := _turbine_gear_trace_meta(sim.dt())
	incomplete_turbine_meta.erase("wheel_state_layout")
	incomplete_turbine_gear.meta = incomplete_turbine_meta
	incomplete_turbine_gear.record(0, 0.0, gear_state, gear_loads, gear_inputs, turbine_gear_aux,
		PackedFloat64Array([44000.0, 0.0, 0.0, 0.0]))
	_check("v8 turbine gear trace rejects incomplete wheel metadata",
		incomplete_turbine_gear.row_count() == 0 and incomplete_turbine_gear._invalid_weather)
	var wheel_without_gear := Trace.new()
	var wheel_only_meta := _turbine_gear_trace_meta(sim.dt())
	wheel_only_meta.erase("gear_law")
	wheel_only_meta.erase("gear_aux_index")
	wheel_only_meta.erase("gear_trace_schema")
	wheel_only_meta.erase("recording_start_gear")
	wheel_only_meta.erase("input_layout")
	wheel_without_gear.meta = wheel_only_meta
	wheel_without_gear.record(0, 0.0, gear_state, gear_loads,
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([44000.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([44000.0, 0.0, 0.0, 0.0]))
	_check("v8 turbine wheel metadata requires complete retractable gear metadata",
		wheel_without_gear.row_count() == 0 and wheel_without_gear._invalid_weather)
	var gear_csv := gear_trace.to_csv()
	_check("gear trace declares its schema and bumped overall format", gear_csv.contains("# format: openrc-trace v10\n")
		and gear_csv.contains("# gear_trace_schema: openrc-gear-trace v1\n")
		and gear_csv.contains("gear_extension,gear_target_down,cmd_gear_down,cmd_wheel_brake\n"))

	var missing_gear_schema := Trace.new()
	var missing_schema_meta := _gear_trace_meta(sim.dt())
	missing_schema_meta.erase("gear_trace_schema")
	missing_gear_schema.meta = missing_schema_meta
	missing_gear_schema.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]))
	_check("six-input gear trace rejects a missing schema", missing_gear_schema.row_count() == 0 and missing_gear_schema._invalid_weather)
	var missing_gear_index := Trace.new()
	var missing_index_meta := _gear_trace_meta(sim.dt())
	missing_index_meta.erase("gear_aux_index")
	missing_gear_index.meta = missing_index_meta
	missing_gear_index.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]))
	_check("six-input gear trace rejects a missing AUX index", missing_gear_index.row_count() == 0 and missing_gear_index._invalid_weather)
	var undeclared_six_inputs := Trace.new()
	undeclared_six_inputs.meta = {"scenario": "legacy without gear metadata"}
	undeclared_six_inputs.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]))
	_check("gear-shaped input is rejected without opt-in metadata", undeclared_six_inputs.row_count() == 0 and undeclared_six_inputs._invalid_weather)

	var malformed_gear_input := Trace.new()
	malformed_gear_input.meta = _gear_trace_meta(sim.dt())
	var invalid_gear_inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.5, 0.25])
	malformed_gear_input.record(0, 0.0, gear_state, gear_loads, invalid_gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]))
	_check("gear trace rejects nonbinary down command", malformed_gear_input.row_count() == 0 and malformed_gear_input._invalid_weather)
	var malformed_gear_aux := Trace.new()
	malformed_gear_aux.meta = _gear_trace_meta(sim.dt())
	malformed_gear_aux.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	_check("gear trace rejects a truncated AUX row", malformed_gear_aux.row_count() == 0 and malformed_gear_aux._invalid_weather)
	var mismatched_gear_start := Trace.new()
	mismatched_gear_start.meta = _gear_trace_meta(sim.dt())
	mismatched_gear_start.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.25, 1.0]))
	_check("gear trace rejects a first-row extension that differs from its start snapshot",
		mismatched_gear_start.row_count() == 0 and mismatched_gear_start._invalid_weather)
	var discontinuous_gear_trace := Trace.new()
	discontinuous_gear_trace.meta = _gear_trace_meta(sim.dt())
	discontinuous_gear_trace.record(0, 0.0, gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 1.0]))
	discontinuous_gear_trace.record(2, 2.0 * sim.dt(), gear_state, gear_loads, gear_inputs, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.2, 1.0]))
	_check("gear trace rejects a dropped tick instead of saving incomplete data",
		discontinuous_gear_trace.row_count() == 1 and discontinuous_gear_trace._invalid_weather
		and discontinuous_gear_trace.to_csv().is_empty())

	# Exactness on EVERY row against its own timestamp: altitude 30 - ½gt², east -40 + 15t.
	# (Checking only the final row missed a one-tick time-labeling bug.)
	var worst_alt := 0.0
	var worst_east := 0.0
	for r in trace.row_count():
		var t := trace.value(r, "t_s")
		worst_alt = maxf(worst_alt, absf(trace.value(r, "alt_m") - (30.0 - 0.5 * 9.80665 * t * t)))
		worst_east = maxf(worst_east, absf(trace.value(r, "east_m") - (-40.0 + 15.0 * t)))
	_check("every row: alt = 30 - ½g·t²", worst_alt < 1e-9, str(worst_alt))
	_check("every row: east = -40 + 15·t", worst_east < 1e-9, str(worst_east))
	var last := trace.row_count() - 1
	_check("alt at 1.5 s = 30 - ½g·1.5²", absf(trace.value(last, "alt_m") - (30.0 - 0.5 * 9.80665 * 2.25)) < 1e-9)
	_check("east at 1.5 s = -17.5 m", absf(trace.value(last, "east_m") + 17.5) < 1e-9)
	_check("heading 90° throughout", absf(trace.value(last, "yaw_deg") - 90.0) < 1e-9)

	# CSV: metadata first, one header, units on physical columns, same width on every row.
	var lines := trace.to_csv().strip_edges().split("\n")
	_check("first line names the format", lines[0] == "# format: openrc-trace v3", lines[0])
	var header := ""
	var data := 0
	var widths_ok := true
	for line in lines:
		if line.begins_with("#"):
			continue
		if header == "":
			header = line
			continue
		data += 1
		widths_ok = widths_ok and line.split(",").size() == Trace.COLUMNS.size()
	_check("header matches COLUMNS", header == ",".join(Trace.COLUMNS))
	_check("every data row has every column", widths_ok and data == 361, "%d rows" % data)
	var unitless := []
	for c in Trace.COLUMNS:
		var dimensionless: bool = c in ["tick", "qw", "qx", "qy", "qz"] or c.begins_with("cmd_") or c.begins_with("srv_")
		if c.ends_with("_rpm"):
			continue # rpm is its own unit
		if not dimensionless and not (c.ends_with("_m") or c.ends_with("_s") or c.ends_with("_mps") or c.ends_with("_deg") or c.ends_with("_radps") or c.ends_with("_N") or c.ends_with("_Nm")):
			unitless.append(c)
	_check("physical columns carry units", unitless.is_empty(), str(unitless))

	# Preserve the exact bytes of the original unversioned trace path.
	var legacy_trace := Trace.new()
	legacy_trace.meta = {"scenario": "legacy"}
	legacy_trace.record(0, 0.0, gear_state, gear_loads, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	var expected_legacy := "# format: openrc-trace v3\n# scenario: legacy\n" \
		+ "tick,t_s,north_m,east_m,down_m,alt_m,u_mps,v_mps,w_mps,speed_mps,qw,qx,qy,qz,yaw_deg,pitch_deg,roll_deg,p_radps,q_radps,r_radps,Fx_N,Fy_N,Fz_N,Mx_Nm,My_Nm,Mz_Nm,cmd_roll,cmd_pitch,cmd_yaw,cmd_throttle,engine_rpm,srv_roll,srv_pitch,srv_yaw\n" \
		+ "0,0.000000000,0.000000000,0.000000000,5.000000000,-5.000000000,0.000000000,0.000000000,0.000000000,0.000000000,1.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000,0.000000000\n"
	_check("gear trace work preserves legacy CSV bytes", legacy_trace.to_csv() == expected_legacy, legacy_trace.to_csv())

	# Round trip: the CSV text parses back to the recorded value at 1e-9 precision.
	var last_cells := lines[lines.size() - 1].split(",")
	var col := Trace.COLUMNS.find("down_m")
	_check("CSV round trip", absf(float(last_cells[col]) - trace.value(last, "down_m")) < 1e-9, last_cells[col])

	# A dropped sample is visible.
	var holey := Trace.new()
	for k in 11:
		if k != 5:
			holey.record(k, k * sim.dt(), sim.state, sim.last_loads, sim.inputs)
	_check("gaps() reports a dropped tick", holey.gaps() == PackedInt64Array([5]), str(holey.gaps()))
	_check("a dropped tick breaks continuity", not holey.is_continuous())
	var dup := Trace.new()
	for k in [0, 0, 1, 2]:
		dup.record(k, k * sim.dt(), sim.state, sim.last_loads, sim.inputs)
	_check("a duplicated tick breaks continuity", not dup.is_continuous())

	# Save and read back from disk.
	var path := "user://test-traces/trace-test.csv"
	_check("save succeeds", trace.save(path) == OK)
	_check("file on disk equals to_csv()", FileAccess.get_file_as_string(path) == trace.to_csv())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
