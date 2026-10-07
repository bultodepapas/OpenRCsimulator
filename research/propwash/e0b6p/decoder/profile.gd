# E0b6p decoder cleanup benchmark. Run only in a disposable app copy with both native libraries installed.
extends SceneTree

const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const Flight = preload("res://sim/flight_session.gd")
const TransportFixture = preload("res://tests/test_wash_transport.gd")
const ProfileFixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Aero = preload("res://physics/aero.gd")
const RB = preload("res://physics/rigid_body.gd")

const CANDIDATE_EXTENSION: String = "res://tests/e0b6p_native/candidate.gdextension"
const CANDIDATE_CLASS: StringName = &"OpenRCSmoothWakeCandidate"
const DIRECT_REGIMES: Array[String] = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]
const FLIGHT_REGIMES: Array[String] = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]
const DIRECT_WARMUP_PAIRS: int = 3
const DIRECT_MEASURED_PAIRS: int = 24
const DIRECT_CALLS_PER_BATCH: int = 64
const FLIGHT_WARMUP_PAIRS: int = 1
const FLIGHT_MEASURED_PAIRS: int = 15
const FLIGHT_TICKS_PER_BATCH: int = 24
const BOUNDARY_TICKS: int = 240
const BODY_VALUES: int = 13
const AUX_VALUES: int = 14
const CONTINUOUS_VALUES: int = 0

var _failures: Array[String] = []
var _direct_rows: Array[Dictionary] = []
var _flight_rows: Array[Dictionary] = []
var _route_counts: Dictionary = {}
var _backend_route_counts: Dictionary = {}
var _backend_classes: Dictionary = {}
var _baseline_loaded_before_candidate: bool = false
var _candidate_loaded: bool = false


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		_record_failure("Missing output JSON path in command-line user arguments")
		quit(1)
		return

	# Resolve and retain the reference backend before loading the candidate extension.
	if not Adapter.available() or Adapter.backend == null or not is_instance_valid(Adapter.backend):
		_record_failure("Reference OpenRCSmoothWake backend is unavailable")
		_write_report(args[0])
		quit(1)
		return
	var baseline_backend: Object = Adapter.backend
	_baseline_loaded_before_candidate = true

	GDExtensionManager.load_extension(CANDIDATE_EXTENSION)
	if not ClassDB.class_exists(CANDIDATE_CLASS):
		_record_failure("Candidate native extension did not register OpenRCSmoothWakeCandidate")
		_write_report(args[0])
		quit(1)
		return
	var candidate_value: Variant = ClassDB.instantiate(CANDIDATE_CLASS)
	var candidate_backend: Object = candidate_value as Object
	if candidate_backend == null or not is_instance_valid(candidate_backend):
		_record_failure("Candidate OpenRCSmoothWakeCandidate instance could not be created")
		_write_report(args[0])
		quit(1)
		return
	_candidate_loaded = true
	var baseline_class: StringName = baseline_backend.get_class()
	var candidate_class: StringName = candidate_backend.get_class()
	_backend_classes = {baseline = String(baseline_class), candidate = String(candidate_class)}
	_check("reference object has the expected native class", baseline_class == &"OpenRCSmoothWake", str(baseline_class))
	_check("candidate object has the expected native class", candidate_class == CANDIDATE_CLASS, str(candidate_class))
	_check("native backend object classes are distinct", baseline_class != candidate_class, str(_backend_classes))
	_backend_route_counts = {
		baseline = {native = 0, kernel_calls = 0, legacy = 0, refused = 0},
		candidate = {native = 0, kernel_calls = 0, legacy = 0, refused = 0},
	}

	Adapter.reset_route_counts()
	var direct_model_result: Dictionary = _build_direct_model()
	if not bool(direct_model_result.get("ok", false)):
		_record_failure("Direct profile fixture failed validation: " + str(direct_model_result.get("error", "unknown error")))
	else:
		_direct_rows = _profile_direct_calls(direct_model_result.model, baseline_backend, candidate_backend)

	_flight_rows = _profile_whole_flights(baseline_backend, candidate_backend)
	_route_counts = Adapter.route_counts.duplicate(true)
	_check("direct profile has six regimes", _direct_rows.size() == DIRECT_REGIMES.size(), str(_direct_rows.size()))
	_check("whole-flight profile has twelve cases", _flight_rows.size() == FLIGHT_REGIMES.size() * 2, str(_flight_rows.size()))
	_check("both implementations used the native kernel", int(_route_counts.get("kernel_calls", 0)) > 0,
		str(_route_counts))
	_check("adapter never used the legacy route", int(_route_counts.get("legacy", -1)) == 0, str(_route_counts))
	_check("adapter never refused a native load", int(_route_counts.get("refused", -1)) == 0, str(_route_counts))
	_check("adapter reached a native route", int(_route_counts.get("native", 0)) > 0, str(_route_counts))
	for backend_name: String in ["baseline", "candidate"]:
		var backend_counts: Dictionary = _backend_route_counts.get(backend_name, {})
		_check(backend_name + " reached the native kernel", int(backend_counts.get("kernel_calls", 0)) > 0,
			str(backend_counts))
		_check(backend_name + " used no legacy route", int(backend_counts.get("legacy", -1)) == 0,
			str(backend_counts))
		_check(backend_name + " had no refused loads", int(backend_counts.get("refused", -1)) == 0,
			str(backend_counts))

	var report_ok: bool = _write_report(args[0])
	quit(0 if _failures.is_empty() and report_ok else 1)


func _build_direct_model() -> Dictionary:
	var raw: Dictionary = ProfileFixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var result: Dictionary = AircraftData.validate_and_derive(raw)
	if not bool(result.get("ok", false)):
		return {ok = false, error = str(result.get("errors", []))}
	return {ok = true, model = result.model}


func _profile_direct_calls(model: Dictionary, baseline_backend: Object, candidate_backend: Object) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var prop: Dictionary = model.propulsion
	var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
	var controls: Dictionary = {elevator = 0.1, rudder = -0.1, aileron_left = 0.0, aileron_right = 0.0}
	for regime: String in DIRECT_REGIMES:
		var speed: float = 0.0 if regime == "static" else 15.0
		if regime.begins_with("reverse"):
			speed = (-0.15 if regime == "reverse_fade" else -0.3) * vi0
		var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else 3.0)
		if regime.begins_with("reverse"):
			alpha = 0.0
		var state: PackedFloat64Array = PackedFloat64Array([
			0.0, 0.0, -100.0, speed * cos(alpha), 0.0, speed * sin(alpha),
			1.0, 0.0, 0.0, 0.0, 0.5 if regime == "spin" else 0.0,
			-0.3, 1.5 if regime == "spin" else 0.0,
		])
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
		var timing_pairs: Array[Dictionary] = []
		var baseline_samples: Array[float] = []
		var candidate_samples: Array[float] = []
		var first_backend_samples: Array[String] = []
		var batch_ok: bool = true
		for pair_index: int in DIRECT_WARMUP_PAIRS + DIRECT_MEASURED_PAIRS:
			var first_mode: int = pair_index % 2
			var pair_times: Array[float] = [0.0, 0.0]
			var pair_outputs: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
			for order_index: int in 2:
				var mode: int = first_mode if order_index == 0 else 1 - first_mode
				var backend: Object = baseline_backend if mode == 0 else candidate_backend
				var batch: Dictionary = _time_direct_batch(state, air, controls, model, prop.max_rpm,
					backend, "baseline" if mode == 0 else "candidate", DIRECT_CALLS_PER_BATCH)
				pair_times[mode] = float(batch.get("us_per_call", 0.0))
				pair_outputs[mode] = batch.get("last_load", PackedFloat64Array())
				batch_ok = batch_ok and bool(batch.get("ok", false))
			if pair_index >= DIRECT_WARMUP_PAIRS:
				baseline_samples.append(pair_times[0])
				candidate_samples.append(pair_times[1])
				first_backend_samples.append("baseline" if first_mode == 0 else "candidate")
				var last_outputs_match: bool = _packed_exact(pair_outputs[0], pair_outputs[1])
				if not last_outputs_match:
					_check("timed direct batch outputs match for " + regime, false, "pair %d" % pair_index)
				timing_pairs.append({baseline_us_per_call = pair_times[0], candidate_us_per_call = pair_times[1],
					first_backend = "baseline" if first_mode == 0 else "candidate", exact_last_load = last_outputs_match})

		var baseline_load: PackedFloat64Array = _direct_load(state, air, controls, model, prop.max_rpm,
			baseline_backend, "baseline")
		var candidate_load: PackedFloat64Array = _direct_load(state, air, controls, model, prop.max_rpm,
			candidate_backend, "candidate")
		var finite: bool = _all_finite(baseline_load) and _all_finite(candidate_load)
		var shape_ok: bool = baseline_load.size() == 6 and candidate_load.size() == 6
		var exact: bool = shape_ok and finite and _packed_exact(baseline_load, candidate_load)
		_check("direct six-load output is finite and exact for " + regime, exact,
			"baseline=%d candidate=%d" % [baseline_load.size(), candidate_load.size()])
		if not batch_ok:
			_check("all direct timing batches completed for " + regime, false)
		rows.append({regime = regime, swirl_factor = 0.4, timing_unit = "us/call", scalar_values_compared = 6,
			baseline_load_values = baseline_load.size(), candidate_load_values = candidate_load.size(),
			baseline_finite = _all_finite(baseline_load), candidate_finite = _all_finite(candidate_load),
			exact = exact, timing_pairs = timing_pairs, baseline_samples_us = baseline_samples,
			candidate_samples_us = candidate_samples, first_backend_samples = first_backend_samples,
			warmup_pairs = DIRECT_WARMUP_PAIRS, measured_pairs = DIRECT_MEASURED_PAIRS,
			calls_per_backend_per_batch = DIRECT_CALLS_PER_BATCH})
	return rows


func _time_direct_batch(state: PackedFloat64Array, air: Dictionary, controls: Dictionary,
		model: Dictionary, rpm: float, backend: Object, backend_name: String, calls: int) -> Dictionary:
	# Select the backend before starting the clock; every invocation remains in the measured adapter path.
	Adapter.backend = backend
	var route_before: Dictionary = Adapter.route_counts.duplicate(true)
	var last_load: PackedFloat64Array = PackedFloat64Array()
	var started: int = Time.get_ticks_usec()
	for call_index: int in calls:
		last_load = Adapter.loads(state, air, controls, model, rpm, 1.225, 0.3)
	var elapsed: int = Time.get_ticks_usec() - started
	_record_backend_route_delta(backend_name, route_before, Adapter.route_counts.duplicate(true))
	var ok: bool = last_load.size() == 6 and _all_finite(last_load)
	return {ok = ok, us_per_call = float(elapsed) / float(calls), last_load = last_load}


func _direct_load(state: PackedFloat64Array, air: Dictionary, controls: Dictionary, model: Dictionary,
		rpm: float, backend: Object, backend_name: String) -> PackedFloat64Array:
	Adapter.backend = backend
	var route_before: Dictionary = Adapter.route_counts.duplicate(true)
	var result: PackedFloat64Array = Adapter.loads(state, air, controls, model, rpm, 1.225, 0.3)
	_record_backend_route_delta(backend_name, route_before, Adapter.route_counts.duplicate(true))
	return result


func _profile_whole_flights(baseline_backend: Object, candidate_backend: Object) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for regime: String in FLIGHT_REGIMES:
		for swirl_factor: float in [0.0, 0.4]:
			var case_row: Dictionary = _profile_flight_case(regime, swirl_factor, baseline_backend, candidate_backend)
			rows.append(case_row)
			if not bool(case_row.get("ok", false)):
				_check("whole-flight case completed: %s swirl=%s" % [regime, swirl_factor], false,
					str(case_row.get("error", "unknown error")))
			else:
				_check("whole-flight boundaries are finite, correctly shaped, and exact: %s swirl=%s" % [regime, swirl_factor],
					bool(case_row.get("exact", false)), str(case_row.get("boundary_comparison", {})))
	return rows


func _profile_flight_case(regime: String, swirl_factor: float, baseline_backend: Object,
		candidate_backend: Object) -> Dictionary:
	var flight: Node = Flight.new()
	if not TransportFixture.configure(flight):
		flight.free()
		return {ok = false, regime = regime, swirl_factor = swirl_factor, error = "flight fixture did not configure"}
	flight.aircraft.model.propulsion.slipstream.erase("transport_speed_floor")
	flight.aircraft.model.propulsion.slipstream.swirl_factor = swirl_factor
	flight.reset()
	var state: PackedFloat64Array = flight.sim.state.duplicate()
	var speed: float = 0.0 if regime == "static" else 15.0
	if regime.begins_with("reverse"):
		var prop: Dictionary = flight.aircraft.model.propulsion
		var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
		speed = (-0.15 if regime == "reverse_fade" else -0.3) * vi0
	var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else
		(0.0 if regime.begins_with("reverse") else 3.0))
	state[RB.POS + 2] = -100.0
	state[RB.VEL] = speed * cos(alpha)
	state[RB.VEL + 2] = speed * sin(alpha)
	if regime == "spin":
		state[RB.RATE] = 0.5
		state[RB.RATE + 1] = -0.3
		state[RB.RATE + 2] = 1.5
	flight.sim.aux[0] = flight.aircraft.model.propulsion.max_rpm
	var wing_air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
	flight.sim.aux[flight.downwash_index()] = Aero.wing_lift_coefficient(
		state, wing_air, flight._deflections(flight.sim.aux), flight.aircraft.model)
	flight.sim.continuous = flight._settled_wash(state, flight.sim.aux)
	if not flight.sim.reset(state):
		flight.free()
		return {ok = false, regime = regime, swirl_factor = swirl_factor, error = "initial flight state was refused"}
	var checkpoint: Dictionary = flight.sim.checkpoint()
	if checkpoint.is_empty():
		flight.free()
		return {ok = false, regime = regime, swirl_factor = swirl_factor, error = "initial checkpoint was refused"}

	var baseline_samples: Array[float] = []
	var candidate_samples: Array[float] = []
	var first_backend_samples: Array[String] = []
	var timing_ok: bool = true
	for pair_index: int in FLIGHT_WARMUP_PAIRS + FLIGHT_MEASURED_PAIRS:
		var first_mode: int = pair_index % 2
		var pair_times: Array[float] = [0.0, 0.0]
		for order_index: int in 2:
			var mode: int = first_mode if order_index == 0 else 1 - first_mode
			var backend: Object = baseline_backend if mode == 0 else candidate_backend
			var timing: Dictionary = _time_flight_batch(flight, checkpoint, backend)
			pair_times[mode] = float(timing.get("us_per_tick", 0.0))
			timing_ok = timing_ok and bool(timing.get("ok", false))
		if pair_index >= FLIGHT_WARMUP_PAIRS:
			baseline_samples.append(pair_times[0])
			candidate_samples.append(pair_times[1])
			first_backend_samples.append("baseline" if first_mode == 0 else "candidate")

	var baseline_capture: Dictionary = _capture_boundaries(flight, checkpoint, baseline_backend)
	var candidate_capture: Dictionary = _capture_boundaries(flight, checkpoint, candidate_backend)
	var exact: bool = false
	var scalar_values_compared: int = 0
	var boundary_comparison: Dictionary = {
		boundaries_per_backend = 0, body_values_per_boundary = BODY_VALUES,
		aux_values_per_boundary = AUX_VALUES, continuous_values_per_boundary = CONTINUOUS_VALUES,
		baseline_finite = false, candidate_finite = false, exact = false,
		scalar_values_compared = 0,
	}
	var captures_ok: bool = bool(baseline_capture.get("ok", false)) and bool(candidate_capture.get("ok", false))
	if captures_ok:
		var baseline_boundaries: Array[Dictionary] = baseline_capture.boundaries
		var candidate_boundaries: Array[Dictionary] = candidate_capture.boundaries
		var compare: Dictionary = _compare_boundaries(baseline_boundaries, candidate_boundaries)
		exact = bool(compare.get("exact", false))
		scalar_values_compared = int(compare.get("scalar_values_compared", 0))
		boundary_comparison = compare

	var ok: bool = timing_ok and captures_ok and exact
	var error: String = ""
	if not timing_ok:
		error = "one or more 24-tick timing batches faulted or failed to restore the checkpoint"
	elif not captures_ok:
		error = "boundary capture failed: baseline=%s candidate=%s" % [
			str(baseline_capture.get("error", "ok")), str(candidate_capture.get("error", "ok"))]
	elif not exact:
		error = "baseline and candidate boundaries differ"

	var result: Dictionary = {ok = ok, regime = regime, swirl_factor = swirl_factor,
		warmup_pairs = FLIGHT_WARMUP_PAIRS, measured_pairs = FLIGHT_MEASURED_PAIRS,
		ticks_per_batch = FLIGHT_TICKS_PER_BATCH, baseline_samples_us = baseline_samples,
		candidate_samples_us = candidate_samples, first_backend_samples = first_backend_samples,
		timing_unit = "us/tick",
		boundary_comparison = boundary_comparison, scalar_values_compared = scalar_values_compared,
		exact = exact, fault_free_timing_batches = timing_ok,
		baseline_boundary_capture_ok = bool(baseline_capture.get("ok", false)),
		candidate_boundary_capture_ok = bool(candidate_capture.get("ok", false))}
	if not error.is_empty():
		result["error"] = error
	flight.free()
	return result


func _time_flight_batch(flight: Node, checkpoint: Dictionary, backend: Object) -> Dictionary:
	# Backend selection and checkpoint restore are outside the measured region.
	Adapter.backend = backend
	if not flight.sim.restore_checkpoint(checkpoint):
		return {ok = false, us_per_tick = 0.0, error = "checkpoint restore failed"}
	var start_tick: int = flight.sim.tick
	var started: int = Time.get_ticks_usec()
	for tick: int in FLIGHT_TICKS_PER_BATCH:
		flight.sim.step()
	var elapsed: int = Time.get_ticks_usec() - started
	var fault_free: bool = flight.sim.fault_reason.is_empty() and flight.sim.tick == start_tick + FLIGHT_TICKS_PER_BATCH
	return {ok = fault_free, us_per_tick = float(elapsed) / float(FLIGHT_TICKS_PER_BATCH),
		error = "fault=%s tick=%d expected=%d" % [flight.sim.fault_reason, flight.sim.tick, start_tick + FLIGHT_TICKS_PER_BATCH]}


func _capture_boundaries(flight: Node, checkpoint: Dictionary, backend: Object) -> Dictionary:
	Adapter.backend = backend
	if not flight.sim.restore_checkpoint(checkpoint):
		return {ok = false, error = "checkpoint restore failed"}
	var start_tick: int = flight.sim.tick
	var boundaries: Array[Dictionary] = []
	for boundary_index: int in BOUNDARY_TICKS:
		flight.sim.step()
		if not flight.sim.fault_reason.is_empty():
			return {ok = false, error = "simulation fault at boundary %d: %s" % [boundary_index + 1, flight.sim.fault_reason]}
		var body: PackedFloat64Array = flight.sim.state
		var auxiliary: PackedFloat64Array = flight.sim.aux
		var continuous: PackedFloat64Array = flight.sim.continuous
		if body.size() != BODY_VALUES or auxiliary.size() != AUX_VALUES or continuous.size() != CONTINUOUS_VALUES:
			return {ok = false, error = "boundary %d has shape body=%d aux=%d continuous=%d" % [
				boundary_index + 1, body.size(), auxiliary.size(), continuous.size()]}
		if not _all_finite(body) or not _all_finite(auxiliary) or not _all_finite(continuous):
			return {ok = false, error = "boundary %d contains a non-finite value" % (boundary_index + 1)}
		boundaries.append({body = body.duplicate(), auxiliary = auxiliary.duplicate(), continuous = continuous.duplicate()})
	if flight.sim.tick != start_tick + BOUNDARY_TICKS:
		return {ok = false, error = "captured trajectory ended at tick %d, expected %d" % [flight.sim.tick, start_tick + BOUNDARY_TICKS]}
	return {ok = true, boundaries = boundaries, finite = true, count = boundaries.size()}


func _compare_boundaries(baseline: Array[Dictionary], candidate: Array[Dictionary]) -> Dictionary:
	var exact: bool = baseline.size() == BOUNDARY_TICKS and candidate.size() == BOUNDARY_TICKS
	var finite: bool = true
	var scalar_values_compared: int = 0
	var first_difference: int = -1
	if baseline.size() == candidate.size():
		for boundary_index: int in baseline.size():
			var baseline_boundary: Dictionary = baseline[boundary_index]
			var candidate_boundary: Dictionary = candidate[boundary_index]
			var baseline_body: PackedFloat64Array = baseline_boundary.body
			var candidate_body: PackedFloat64Array = candidate_boundary.body
			var baseline_aux: PackedFloat64Array = baseline_boundary.auxiliary
			var candidate_aux: PackedFloat64Array = candidate_boundary.auxiliary
			var baseline_continuous: PackedFloat64Array = baseline_boundary.continuous
			var candidate_continuous: PackedFloat64Array = candidate_boundary.continuous
			finite = finite and _all_finite(baseline_body) and _all_finite(candidate_body)
			finite = finite and _all_finite(baseline_aux) and _all_finite(candidate_aux)
			finite = finite and _all_finite(baseline_continuous) and _all_finite(candidate_continuous)
			scalar_values_compared += baseline_body.size() + baseline_aux.size() + baseline_continuous.size()
			exact = exact and _packed_exact(baseline_body, candidate_body)
			exact = exact and _packed_exact(baseline_aux, candidate_aux)
			exact = exact and _packed_exact(baseline_continuous, candidate_continuous)
			if first_difference == -1 and not (
				_packed_exact(baseline_body, candidate_body)
				and _packed_exact(baseline_aux, candidate_aux)
				and _packed_exact(baseline_continuous, candidate_continuous)):
				first_difference = boundary_index + 1
	return {
		boundaries_per_backend = baseline.size(),
		body_values_per_boundary = BODY_VALUES,
		aux_values_per_boundary = AUX_VALUES,
		continuous_values_per_boundary = CONTINUOUS_VALUES,
		baseline_finite = finite,
		candidate_finite = finite,
		scalar_values_compared = scalar_values_compared,
		exact = exact and finite,
		first_difference_boundary = first_difference,
	}


func _packed_exact(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	return left.size() == right.size() and left.to_byte_array() == right.to_byte_array()


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		return
	_record_failure(label + (": " + detail if not detail.is_empty() else ""))


func _record_failure(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _write_report(path: String) -> bool:
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		_record_failure("Could not open profile report for writing: " + path)
		return false
	var report: Dictionary = {
		format = "openrc-e0b6p-requiredfield-profile v1",
		status = "pass" if _failures.is_empty() else "fail",
		failures = _failures.size(),
		failure_details = _failures,
		cpu = OS.get_processor_name(),
		godot = Engine.get_version_info().string,
		backend_load_order = {
			reference_loaded_before_candidate = _baseline_loaded_before_candidate,
			candidate_loaded = _candidate_loaded,
			baseline_class = "OpenRCSmoothWake",
			candidate_class = String(CANDIDATE_CLASS),
		},
		protocol = {
			warmup_pairs = DIRECT_WARMUP_PAIRS,
			measured_pairs = DIRECT_MEASURED_PAIRS,
			calls_per_backend_per_batch = DIRECT_CALLS_PER_BATCH,
			flight_warmup_pairs = FLIGHT_WARMUP_PAIRS,
			flight_measured_pairs = FLIGHT_MEASURED_PAIRS,
			flight_ticks_per_batch = FLIGHT_TICKS_PER_BATCH,
			boundary_ticks_per_backend = BOUNDARY_TICKS,
			boundary_shape = {body = BODY_VALUES, auxiliary = AUX_VALUES, continuous = CONTINUOUS_VALUES},
			direct_timing_unit = "us/call",
			flight_timing_unit = "us/tick",
		},
		direct_rows = _direct_rows,
		flight_rows = _flight_rows,
		route_counts = _route_counts,
		checks = {
			direct_rows = _direct_rows.size(),
			whole_tick_rows = _flight_rows.size(),
			whole_tick_boundary_samples_per_backend = BOUNDARY_TICKS,
			whole_tick_body_values_per_boundary = BODY_VALUES,
			whole_tick_aux_values_per_boundary = AUX_VALUES,
			whole_tick_continuous_values_per_boundary = CONTINUOUS_VALUES,
			all_adapter_totals_valid = int(_route_counts.get("native", 0)) > 0
				and int(_route_counts.get("kernel_calls", 0)) > 0
				and int(_route_counts.get("legacy", -1)) == 0
				and int(_route_counts.get("refused", -1)) == 0,
		},
	}
	output.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	return true
