## NITRO trace checks: accepted glow state, finite fuel, per-tick event deltas, and legacy bytes.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Trace := preload("res://sim/trace.gd")
const RB := preload("res://physics/rigid_body.gd")
const GLOW_COLUMNS: Array[String] = [
	"glow_fuel_kg", "glow_temperature_k", "glow_running", "glow_stop_reason_code",
	"glow_phase_revolutions", "glow_mixture_command_phi", "glow_fuel_transport_kg_s",
	"glow_opportunity_count", "glow_fire_count", "glow_fire_events", "glow_firing_accumulator",
	"glow_shaft_work_j", "glow_propeller_work_j", "glow_thrust_work_j", "glow_chemical_work_j",
]

var _failures: int = 0
var _checks: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_test_legacy_csv_bytes()
	await _test_live_glow_traces()
	print("NITRO-TRACE: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _test_legacy_csv_bytes() -> void:
	var trace := Trace.new()
	var body := PackedFloat64Array()
	body.resize(RB.SIZE)
	body[RB.ATT] = 1.0
	trace.record(0, 0.0, body, PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	var header := "tick,t_s,north_m,east_m,down_m,alt_m,u_mps,v_mps,w_mps,speed_mps,qw,qx,qy,qz,yaw_deg,pitch_deg,roll_deg,p_radps,q_radps,r_radps,Fx_N,Fy_N,Fz_N,Mx_Nm,My_Nm,Mz_Nm,cmd_roll,cmd_pitch,cmd_yaw,cmd_throttle,engine_rpm,srv_roll,srv_pitch,srv_yaw"
	var row := PackedStringArray(["0"])
	for index in 33:
		row.append("1.000000000" if index == 9 else ("-0.000000000" if index == 4 else "0.000000000"))
	var expected := "# format: openrc-trace v3\n" + header + "\n" + ",".join(row) + "\n"
	var actual: String = trace.to_csv()
	if actual != expected:
		var mismatch: int = 0
		while mismatch < mini(actual.length(), expected.length()) and actual[mismatch] == expected[mismatch]:
			mismatch += 1
		print("LEGACY_DIFF index=", mismatch, " expected_len=", expected.length(), " actual_len=", actual.length(),
			" expected_tail=", expected.substr(maxi(0, mismatch - 20), 80), " actual_tail=", actual.substr(maxi(0, mismatch - 20), 80))
	_check("non-glow trace bytes remain v3-compatible", actual == expected, actual)
	_check("non-glow trace has no glow columns", not trace.columns().has("glow_fuel_kg"))


func _test_live_glow_traces() -> void:
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup()
	root.add_child(session)
	var recorder: RefCounted = Recorder.new(session.sim, session.electrical_state)
	for aircraft_id: String in ["stik-glow-55ax-2t", "stik-glow-fs64v-4t"]:
		var entry: Dictionary = Catalog.entry(aircraft_id)
		session.aircraft_path = entry.data
		_check("reload " + aircraft_id, session.reload().begins_with("aircraft reloaded:"))
		var family: String = "glow_2t" if aircraft_id.ends_with("2t") else "glow_4t"
		var before: Dictionary = session.glow_state()
		_check("accepted " + family + " source is running", before.get("ok", false) and before.get("family", "") == family
			and before.get("running", false), str(before))
		recorder.start(session.trace_meta())
		var trace: RefCounted = recorder.trace
		_check("" + family + " trace accepts tick zero", trace.row_count() == 1 and trace.to_csv().begins_with("# format: openrc-trace v9\n"))
		_check("" + family + " trace declares physical channels", trace.columns().slice(Trace.COLUMNS.size()) == GLOW_COLUMNS, str(trace.columns()))
		_check("" + family + " metadata preserves cycle family", trace.meta.glow_family == family
			and trace.meta.continuous_layout == "rpm; fuel kg, temperature K, servo, admission, fuel transport kg/s, crank revolutions; running, reason, opportunities, fires, firing accumulator; mixture; shaft/prop/thrust/chemical work J"
				+ ("; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail" if session.wheel_count() > 0 else ""))
		var initial_fuel: float = float(before.fuel_kg)
		for _tick in 120:
			session.sim.step()
		_check("" + family + " trace has contiguous accepted samples", trace.row_count() == 121 and trace.is_continuous() and trace.gaps().is_empty(), str(trace.row_count()))
		_check("" + family + " successfully records real fire events", trace.value(trace.row_count() - 1, "glow_fire_count") > float(before.fire_count))
		_check("" + family + " finite fuel remains bounded", trace.value(trace.row_count() - 1, "glow_fuel_kg") >= 0.0
			and trace.value(trace.row_count() - 1, "glow_fuel_kg") <= initial_fuel)
		_check("" + family + " work and state channels remain finite", _all_glow_rows_finite(trace, family))
		var prior_fires: int = int(trace.value(0, "glow_fire_count"))
		_check("" + family + " first row starts with zero new fire events", trace.value(0, "glow_fire_events") == 0.0)
		for row_index in range(1, trace.row_count()):
			var fires: int = int(trace.value(row_index, "glow_fire_count"))
			var opportunities: int = int(trace.value(row_index, "glow_opportunity_count"))
			_check("" + family + " events are the accepted fire-count delta at row %d" % row_index,
				trace.value(row_index, "glow_fire_events") == float(fires - prior_fires)
				and trace.value(row_index, "glow_fire_events") <= float(opportunities - int(trace.value(row_index - 1, "glow_opportunity_count"))))
			prior_fires = fires
		var work_before_cut: float = float(trace.value(trace.row_count() - 1, "glow_shaft_work_j"))
		var mechanical_rpm_before_cut: float = float(trace.value(trace.row_count() - 1, "engine_rpm"))
		_check("" + family + " cut command succeeds", session.glow_cut())
		for _tick in 4:
			session.sim.step()
		var last_row: int = trace.row_count() - 1
		_check("" + family + " cut is an accepted stopped mode", trace.value(last_row, "glow_running") == 0.0
			and trace.value(last_row, "glow_stop_reason_code") == 2.0)
		_check("" + family + " cut stops events but retains mechanical shaft state",
			trace.value(last_row, "glow_fire_count") == float(prior_fires)
			and trace.value(last_row, "engine_rpm") > 0.0
			and mechanical_rpm_before_cut > 0.0)
		var cut_state: Dictionary = session.glow_state()
		_check("" + family + " trace carries accepted work through cut", is_finite(trace.value(last_row, "glow_shaft_work_j"))
			and is_equal_approx(trace.value(last_row, "glow_shaft_work_j"), float(cut_state.shaft_work_j)),
			"before=%s after=%s" % [work_before_cut, cut_state.get("shaft_work_j", NAN)])
		_check("" + family + " CSV declares glow schema and mode semantics", trace.to_csv().contains("# glow_trace_schema: " + Trace.GLOW_TRACE_SCHEMA)
			and trace.to_csv().contains("# glow_mode_semantics:")
			and trace.to_csv().contains("glow_fire_events"))
		_test_bad_glow_samples(session)
		recorder.recording = false
	recorder.detach()
	session.free()


func _all_glow_rows_finite(trace: RefCounted, family: String) -> bool:
	var phase_limit: float = 1.0 if family == "glow_2t" else 2.0
	for row_index in trace.row_count():
		for column: String in GLOW_COLUMNS:
			if not is_finite(trace.value(row_index, column)):
				return false
		var fuel: float = trace.value(row_index, "glow_fuel_kg")
		var phase: float = trace.value(row_index, "glow_phase_revolutions")
		if fuel < 0.0 or phase < 0.0 or phase >= phase_limit:
			return false
	return true


func _test_bad_glow_samples(session: Node) -> void:
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var metadata: Dictionary = session.trace_meta()
	var bad_fuel := Trace.new()
	bad_fuel.meta = metadata.duplicate(true)
	bad_fuel.record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads,
		session.sim.inputs, session.sim.aux, continuous)
	var negative_fuel: PackedFloat64Array = continuous.duplicate()
	negative_fuel[1] = -1e-6
	bad_fuel.record(session.sim.tick + 1, session.sim.time() + session.sim.dt(), session.sim.state, session.sim.last_loads,
		session.sim.inputs, session.sim.aux, negative_fuel)
	_check("negative accepted fuel invalidates the glow trace", bad_fuel.row_count() == 1 and bad_fuel.to_csv().is_empty(),
		"rows=%d csv=%d invalid=%s" % [bad_fuel.row_count(), bad_fuel.to_csv().length(), bad_fuel._invalid_weather])
	var bad_event_count := Trace.new()
	bad_event_count.meta = metadata.duplicate(true)
	bad_event_count.record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads,
		session.sim.inputs, session.sim.aux, continuous)
	var rolled_back: PackedFloat64Array = continuous.duplicate()
	rolled_back[9] = maxf(0.0, rolled_back[9] - 1.0)
	var next_aux: PackedFloat64Array = session.sim.aux.duplicate()
	bad_event_count.record(session.sim.tick + 1, session.sim.time() + session.sim.dt(), session.sim.state,
		session.sim.last_loads, session.sim.inputs, next_aux, rolled_back)
	_check("decreasing opportunity counters invalidate rather than hide accepted events",
		bad_event_count.row_count() == 1 and bad_event_count.to_csv().is_empty(),
		"rows=%d csv=%d invalid=%s glow=%s opportunities=%s" % [bad_event_count.row_count(), bad_event_count.to_csv().length(),
		bad_event_count._invalid_weather, bad_event_count._glow, continuous[9]])
	if session.wheel_count() > 0:
		# GP-06a: the wheel tail after the glow slots must be declared exactly; a dropped or shifted tail invalidates.
		var no_suffix: Dictionary = metadata.duplicate(true)
		no_suffix.continuous_layout = str(no_suffix.continuous_layout).get_slice("; wheel rim speeds", 0)
		var shifted: Dictionary = metadata.duplicate(true)
		var layout: Array = JSON.parse_string(shifted.wheel_state_layout)
		layout[0].index = int(layout[0].index) - 1
		shifted.wheel_state_layout = JSON.stringify(layout, "", true, true)
		var no_wheels: PackedFloat64Array = continuous.slice(0, continuous.size() - session.wheel_count())
		for case: Array in [["undeclared wheel tail", no_suffix, continuous], ["shifted wheel index", shifted, continuous],
				["continuous state without its declared wheels", metadata, no_wheels]]:
			var bad := Trace.new()
			bad.meta = case[1].duplicate(true)
			bad.record(session.sim.tick, session.sim.time(), session.sim.state, session.sim.last_loads,
				session.sim.inputs, session.sim.aux, case[2])
			_check(str(case[0]) + " invalidates the glow trace", bad.row_count() == 0 and bad.to_csv().is_empty(),
				"rows=%d invalid=%s" % [bad.row_count(), bad._invalid_weather])
