# E0b6p stage-sharing mechanism proof. Run only in the disposable app staged by run.py.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const BaselineDynamics := preload("res://physics/dynamics.gd")
const CandidateDynamics := preload("res://tests/stage_sharing/dynamics.gd")
const BaselineFlight := preload("res://sim/flight_session.gd")
const CandidateFlight := preload("res://tests/stage_sharing/flight_session.gd")
const BaselinePropulsion := preload("res://physics/propulsion.gd")
const CandidatePropulsion := preload("res://tests/stage_sharing/propulsion.gd")
const WashFixture := preload("res://tests/test_wash_profile.gd")

const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const P51 := "res://data/aircraft/p51d_mustang_120.json"
const AVANTI := "res://data/aircraft/sebart_avanti_s_a200.json"
const RHO := 1.225

var rows: Array[Dictionary] = []
var failures: int = 0


func _initialize() -> void:
	_run_case("smooth_active", STIK, "smooth", false, 8, 4, 2, 1)
	_run_case("legacy_active", P51, "", false, 8, 4, 2, 1)
	_run_case("no_wash_active", STIK, "", false, 4, 4, 1, 1)
	_run_case("turbine", AVANTI, "", false, 0, 0, 0, 0)
	_run_case("stopped_no_residual", STIK, "smooth", true, 0, 0, 0, 0)
	_run_case("stopped_residual", STIK, "transport", true, 8, 8, 1, 1)
	var report := {
		format = "openrc-e0b6p-stage-sharing-mechanism v1",
		status = "pass" if failures == 0 else "fail",
		failures = failures,
		rows = rows,
	}
	_write_report(report)
	quit(1 if failures else 0)


func _run_case(name: String, aircraft_path: String, fixture: String, stopped: bool,
		expected_baseline: int, expected_candidate: int, expected_direct_baseline: int,
		expected_direct_candidate: int) -> void:
	var baseline: Node = _new_flight(BaselineFlight, aircraft_path, fixture)
	var candidate: Node = _new_flight(CandidateFlight, aircraft_path, fixture)
	if baseline == null or candidate == null:
		failures += 1
		if baseline != null:
			baseline.free()
		if candidate != null:
			candidate.free()
		rows.append({case = name, failure = "flight setup failed"})
		return
	if stopped:
		baseline.engine_running = false
		candidate.engine_running = false
	var residual_ready: bool = fixture != "transport" or (baseline.sim.continuous.size() == 3
		and candidate.sim.continuous.size() == 3 and baseline.sim.continuous[0] > 0.0
		and candidate.sim.continuous[0] > 0.0)
	var baseline_deflections: Dictionary = baseline._deflections(baseline.sim.aux)
	var candidate_deflections: Dictionary = candidate._deflections(candidate.sim.aux)
	var baseline_lag: float = _downwash(baseline)
	var candidate_lag: float = _downwash(candidate)
	var direct_rpm: float = 0.0 if stopped else float(baseline.sim.aux[0])
	var baseline_transport: PackedFloat64Array = baseline.sim.continuous
	var candidate_transport: PackedFloat64Array = candidate.sim.continuous
	BaselinePropulsion.stage_probe_calls = 0
	CandidatePropulsion.stage_probe_calls = 0
	var direct_baseline: PackedFloat64Array = BaselineDynamics.loads(baseline.sim.state, baseline.aircraft.model,
		baseline_deflections, direct_rpm, RHO, PackedFloat64Array([0.0, 0.0, 0.0]), baseline_lag, baseline_transport)
	var direct_baseline_calls: int = BaselinePropulsion.stage_probe_calls
	var direct_baseline_transport_calls: int = CandidatePropulsion.stage_probe_calls
	BaselinePropulsion.stage_probe_calls = 0
	CandidatePropulsion.stage_probe_calls = 0
	var direct_candidate: PackedFloat64Array = CandidateDynamics.loads(candidate.sim.state, candidate.aircraft.model,
		candidate_deflections, direct_rpm, RHO, PackedFloat64Array([0.0, 0.0, 0.0]), candidate_lag, candidate_transport)
	var direct_candidate_calls: int = CandidatePropulsion.stage_probe_calls
	var direct_candidate_transport_calls: int = BaselinePropulsion.stage_probe_calls
	var direct_valid: bool = _finite_array(direct_baseline, 6) and _finite_array(direct_candidate, 6)
	var direct_equal: bool = direct_valid and direct_baseline.to_byte_array() == direct_candidate.to_byte_array()
	BaselinePropulsion.stage_probe_calls = 0
	CandidatePropulsion.stage_probe_calls = 0
	baseline.sim.step()
	var baseline_calls: int = BaselinePropulsion.stage_probe_calls
	var baseline_transport_calls: int = CandidatePropulsion.stage_probe_calls
	BaselinePropulsion.stage_probe_calls = 0
	CandidatePropulsion.stage_probe_calls = 0
	candidate.sim.step()
	var candidate_calls: int = CandidatePropulsion.stage_probe_calls
	var candidate_transport_calls: int = BaselinePropulsion.stage_probe_calls
	var baseline_loads: PackedFloat64Array = baseline.sim.last_loads
	var candidate_loads: PackedFloat64Array = candidate.sim.last_loads
	var baseline_state: PackedFloat64Array = baseline.sim.state
	var candidate_state: PackedFloat64Array = candidate.sim.state
	var loads_valid: bool = _finite_array(baseline_loads, 6) and _finite_array(candidate_loads, 6)
	var state_valid: bool = _finite_array(baseline_state, RB.SIZE) and _finite_array(candidate_state, RB.SIZE)
	var aux_valid: bool = baseline.sim.aux.size() == candidate.sim.aux.size() \
		and _finite_array(baseline.sim.aux, -1) and _finite_array(candidate.sim.aux, -1)
	var continuous_valid: bool = baseline.sim.continuous.size() == candidate.sim.continuous.size() \
		and _finite_array(baseline.sim.continuous, -1) and _finite_array(candidate.sim.continuous, -1)
	var loads_equal: bool = loads_valid and baseline_loads.to_byte_array() == candidate_loads.to_byte_array()
	var state_equal: bool = state_valid and baseline_state.to_byte_array() == candidate_state.to_byte_array()
	var aux_equal: bool = aux_valid and baseline.sim.aux.to_byte_array() == candidate.sim.aux.to_byte_array()
	var continuous_equal: bool = continuous_valid \
		and baseline.sim.continuous.to_byte_array() == candidate.sim.continuous.to_byte_array()
	var direct_calls_ok: bool = direct_baseline_calls == expected_direct_baseline \
		and direct_candidate_calls == expected_direct_candidate \
		and direct_baseline_transport_calls == 0 and direct_candidate_transport_calls == 0
	var tick_ok: bool = baseline.sim.tick == 1 and candidate.sim.tick == 1
	var flight_calls_ok: bool = baseline_calls + baseline_transport_calls == expected_baseline \
		and candidate_calls + candidate_transport_calls == expected_candidate
	var ok: bool = residual_ready and direct_calls_ok and direct_equal and flight_calls_ok and tick_ok \
		and loads_equal and state_equal and aux_equal and continuous_equal \
		and baseline.sim.fault_reason.is_empty() and candidate.sim.fault_reason.is_empty()
	if not ok:
		failures += 1
	rows.append({
		case = name,
		baseline_calls = baseline_calls,
		candidate_calls = candidate_calls,
		baseline_transport_calls = baseline_transport_calls,
		candidate_transport_calls = candidate_transport_calls,
		direct_baseline_calls = direct_baseline_calls,
		direct_candidate_calls = direct_candidate_calls,
		direct_baseline_transport_calls = direct_baseline_transport_calls,
		direct_candidate_transport_calls = direct_candidate_transport_calls,
		expected_direct_baseline_calls = expected_direct_baseline,
		expected_direct_candidate_calls = expected_direct_candidate,
		direct_equal = direct_equal,
		expected_baseline_calls = expected_baseline,
		expected_candidate_calls = expected_candidate,
		residual_ready = residual_ready,
		loads_equal = loads_equal,
		state_equal = state_equal,
		aux_equal = aux_equal,
		continuous_equal = continuous_equal,
		baseline_fault = baseline.sim.fault_reason,
		candidate_fault = candidate.sim.fault_reason,
		passed = ok,
	})
	baseline.free()
	candidate.free()


func _new_flight(flight_script: Script, aircraft_path: String, fixture: String) -> Node:
	var flight: Node = flight_script.new()
	flight.setup(aircraft_path)
	root.add_child(flight)
	if not flight.is_flyable():
		flight.free()
		return null
	if fixture == "smooth" or fixture == "transport":
		var raw: Dictionary = WashFixture.combined_raw()
		if fixture == "transport":
			raw.propulsion.propeller.slipstream.transport_speed_floor = WashFixture.quantity(1.0, "m/s")
		var data: Dictionary = AD.validate_and_derive(raw)
		if not data.ok or not flight._apply(data):
			flight.free()
			return null
		flight.reset()
	if not flight.is_flyable():
		flight.free()
		return null
	return flight


func _downwash(flight: Node) -> float:
	var index: int = flight.downwash_index()
	return float(flight.sim.aux[index]) if index >= 0 and index < flight.sim.aux.size() else NAN


func _finite_array(values: PackedFloat64Array, expected_size: int) -> bool:
	if expected_size >= 0 and values.size() != expected_size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _write_report(report: Dictionary) -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		failures += 1
		printerr("stage-sharing mechanism requires an output JSON path after --")
		return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null:
		failures += 1
		printerr("could not open stage-sharing report: ", args[0])
		return
	# Include a late report status in case output writing itself failed after the case checks.
	report.failures = failures
	report.status = "pass" if failures == 0 else "fail"
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
