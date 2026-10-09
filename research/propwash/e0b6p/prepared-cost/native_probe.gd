# Temporary direct/prepared-call probe copied into a disposable Godot app.
extends SceneTree

const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const Oracle = preload("res://physics/slipstream.gd")
const Fixture = preload("res://tests/test_wash_profile.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const Propulsion = preload("res://physics/propulsion.gd")

const REGIMES: Array[String] = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]
const WARMUP_CALLS: int = 500
const CALLS_PER_BATCH: int = 3000
const MEASURED_BATCHES: int = 7


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected output path and instrumented flag")
		quit(1)
		return
	var report_path: String = args[0]
	var instrumented: bool = args[1] == "true"
	if args[1] != "true" and args[1] != "false":
		push_error("Instrumented flag must be true or false")
		quit(1)
		return
	if not Adapter.available() or Adapter.backend == null:
		push_error("Native adapter failed to initialize")
		quit(1)
		return
	if instrumented and (not Adapter.backend.has_method("reset_attribution") or
			not Adapter.backend.has_method("get_attribution")):
		push_error("Instrumented candidate has no attribution API")
		quit(1)
		return
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var validated: Dictionary = AircraftData.validate_and_derive(raw)
	if not validated.get("ok", false):
		push_error("Fixture validation failed: " + str(validated.get("errors", [])))
		quit(1)
		return
	var model: Dictionary = validated.model
	var prop: Dictionary = model.propulsion
	var controls: Dictionary = {
		elevator = 0.1,
		rudder = -0.1,
		aileron_left = 0.0,
		aileron_right = 0.0,
	}
	var rows: Array[Dictionary] = []
	for regime: String in REGIMES:
		var speed: float = 0.0 if regime == "static" else 15.0
		if regime.begins_with("reverse"):
			var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
			speed = (-0.15 if regime == "reverse_fade" else -0.3) * vi0
		var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else 3.0)
		if regime.begins_with("reverse"):
			alpha = 0.0
		var state: PackedFloat64Array = PackedFloat64Array([
			0.0, 0.0, -100.0, speed * cos(alpha), 0.0, speed * sin(alpha),
			1.0, 0.0, 0.0, 0.0, 0.5 if regime == "spin" else 0.0, -0.3,
			1.5 if regime == "spin" else 0.0,
		])
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
		var velocity: PackedFloat64Array = air.v_air
		var thrust_torque_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, prop.max_rpm, prop, 1.225)
		var thrust_torque: PackedFloat64Array = PackedFloat64Array([thrust_torque_full[0], thrust_torque_full[1]])
		var fade: float = Oracle.reverse_weight(velocity, prop.max_rpm, prop)
		var downwash_cl: float = 0.3
		var transported_dv: PackedFloat64Array = PackedFloat64Array()
		if instrumented:
			Adapter.backend.call("reset_attribution")
		var prepared_ok: bool = __PREPARE_CALL__
		if instrumented and not prepared_ok:
			push_error("Explicit candidate preparation failed for " + regime)
			quit(1)
			return
		var prepared_token: int = __TOKEN_CALL__
		var preparation_stats: Dictionary = {}
		if instrumented:
			preparation_stats = Adapter.backend.call("get_attribution")
			if (int(preparation_stats.get("prepare_calls", -1)) != 1 or
					int(preparation_stats.get("kernel_calls", -1)) != 0):
				push_error("Preparation counter roster is malformed for " + regime)
				quit(1)
				return
			Adapter.backend.call("reset_attribution")

		for _warmup: int in WARMUP_CALLS:
			var warmup_result: Variant = _direct(state, velocity, controls, model, prepared_token,
					thrust_torque, 1.225, fade, downwash_cl, transported_dv, instrumented)
			if not _valid_loads(warmup_result):
				push_error("Direct native warm-up returned invalid loads for " + regime)
				quit(1)
				return
		for _warmup: int in WARMUP_CALLS:
			var warmup_adapter: PackedFloat64Array = Adapter.loads(state, air, controls, model,
					prop.max_rpm, 1.225, downwash_cl, transported_dv)
			if not _valid_loads(warmup_adapter):
				push_error("Native adapter warm-up returned invalid loads for " + regime)
				quit(1)
				return

		var direct_samples_us: Array[float] = []
		var direct_empty_loop_us: Array[float] = []
		var direct_stats: Array[Dictionary] = []
		var direct_loads: PackedFloat64Array = PackedFloat64Array()
		var direct_bytes_hex: String = ""
		for _batch: int in MEASURED_BATCHES:
			if instrumented:
				Adapter.backend.call("reset_attribution")
			var loop_start: int = Time.get_ticks_usec()
			var loop_sink: int = 0
			for index: int in CALLS_PER_BATCH:
				loop_sink += index & 1
			direct_empty_loop_us.append(float(Time.get_ticks_usec() - loop_start) / CALLS_PER_BATCH)
			var direct_start: int = Time.get_ticks_usec()
			var direct_last: Variant = null
			for _call_index: int in CALLS_PER_BATCH:
				direct_last = _direct(state, velocity, controls, model, prepared_token,
						thrust_torque, 1.225, fade, downwash_cl, transported_dv, instrumented)
			var direct_elapsed: int = Time.get_ticks_usec() - direct_start
			if not _valid_loads(direct_last):
				push_error("Direct native call returned invalid loads for " + regime)
				quit(1)
				return
			direct_loads = direct_last
			direct_bytes_hex = _bytes_hex(direct_loads)
			direct_samples_us.append(float(direct_elapsed) / CALLS_PER_BATCH)
			if instrumented:
				var direct_stat: Dictionary = Adapter.backend.call("get_attribution")
				if not _valid_stats(direct_stat, CALLS_PER_BATCH):
					push_error("Direct prepared native call counters are malformed for " + regime)
					quit(1)
					return
				direct_stats.append(direct_stat)

		var adapter_samples_us: Array[float] = []
		var adapter_stats: Array[Dictionary] = []
		var adapter_routes_batches: Array[Dictionary] = []
		var adapter_loads: PackedFloat64Array = PackedFloat64Array()
		var adapter_bytes_hex: String = ""
		var adapter_routes: Dictionary = {}
		for _batch: int in MEASURED_BATCHES:
			Adapter.reset_route_counts()
			if instrumented:
				Adapter.backend.call("reset_attribution")
			var adapter_start: int = Time.get_ticks_usec()
			var adapter_last: Variant = null
			for _call_index: int in CALLS_PER_BATCH:
				adapter_last = Adapter.loads(state, air, controls, model, prop.max_rpm,
						1.225, downwash_cl, transported_dv)
			var adapter_elapsed: int = Time.get_ticks_usec() - adapter_start
			if not _valid_loads(adapter_last):
				push_error("Native adapter call returned invalid loads for " + regime)
				quit(1)
				return
			adapter_loads = adapter_last
			adapter_bytes_hex = _bytes_hex(adapter_loads)
			adapter_samples_us.append(float(adapter_elapsed) / CALLS_PER_BATCH)
			adapter_routes = Adapter.route_counts.duplicate(true)
			adapter_routes_batches.append(adapter_routes)
			var expected_kernel_calls: int = 0 if regime == "reverse_off" else CALLS_PER_BATCH
			if (int(adapter_routes.get("native", -1)) != CALLS_PER_BATCH or
					int(adapter_routes.get("kernel_calls", -1)) != expected_kernel_calls or
					int(adapter_routes.get("legacy", -1)) != 0 or int(adapter_routes.get("refused", -1)) != 0):
				push_error("Adapter route counts are wrong for " + regime + ": " + str(adapter_routes))
				quit(1)
				return
			if instrumented:
				var adapter_stat: Dictionary = Adapter.backend.call("get_attribution")
				if not _valid_stats(adapter_stat, expected_kernel_calls):
					push_error("Adapter prepared native counters are malformed for " + regime)
					quit(1)
					return
				adapter_stats.append(adapter_stat)
		if direct_loads.to_byte_array() != adapter_loads.to_byte_array():
			push_error("Direct and adapter load bytes differ for " + regime)
			quit(1)
			return
		rows.append({
			"regime": regime,
			"fade": fade,
			"prepared_token": prepared_token,
			"preparation_stats": preparation_stats,
			"direct_loads": Array(direct_loads),
			"direct_loads_bytes_hex": direct_bytes_hex,
			"direct_external_us_per_call_batches": direct_samples_us,
			"direct_empty_loop_us_per_iteration_batches": direct_empty_loop_us,
			"direct_internal_stats_batches": direct_stats,
			"adapter_loads": Array(adapter_loads),
			"adapter_loads_bytes_hex": adapter_bytes_hex,
			"adapter_external_us_per_call_batches": adapter_samples_us,
			"adapter_internal_stats_batches": adapter_stats,
			"adapter_routes_batches": adapter_routes_batches,
			"adapter_routes_last_batch": adapter_routes,
		})
		print("Prepared native attribution %s: direct %.3f us/call; adapter %.3f us/call" % [
			regime, _median(direct_samples_us), _median(adapter_samples_us)])
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("Could not write native attribution report: " + report_path)
		quit(1)
		return
	output.store_string(JSON.stringify({
		"format": "openrc-e0b6p-prepared-native-attribution-profile v1",
		"instrumented": instrumented,
		"cpu": OS.get_processor_name(),
		"godot": Engine.get_version_info().string,
		"warmup_calls_per_regime": WARMUP_CALLS,
		"calls_per_batch": CALLS_PER_BATCH,
		"measured_batches": MEASURED_BATCHES,
		"rows": rows,
	}, "\t", true, true) + "\n")
	quit()


func _direct(state: PackedFloat64Array, velocity: PackedFloat64Array, controls: Dictionary, model: Dictionary,
		prepared_token: int, thrust_torque: PackedFloat64Array, rho: float, fade: float,
		downwash_cl: float, transported_dv: PackedFloat64Array, instrumented: bool) -> Variant:
	if instrumented:
		return Adapter.backend.call("loads_prepared", state, velocity, controls, prepared_token,
				thrust_torque, rho, fade, downwash_cl, transported_dv)
	return Adapter.backend.call("loads", state, velocity, controls, model, thrust_torque,
			rho, fade, downwash_cl, transported_dv)


func _valid_loads(value: Variant) -> bool:
	if not value is PackedFloat64Array:
		return false
	var loads: PackedFloat64Array = value
	if loads.size() != 6:
		return false
	for component: float in loads:
		if not is_finite(component):
			return false
	return true


func _valid_stats(stats: Dictionary, expected_calls: int) -> bool:
	var integer_keys: Array[String] = [
		"calls", "prepared_calls", "prepared_method_total_ns", "prepared_dispatch_ns",
		"prepared_input_decode_ns", "prepared_transport_decode_ns", "prepared_kernel_ns", "prepared_pack_ns",
		"prepare_calls", "prepare_method_total_ns", "prepare_model_decode_ns", "prepare_validation_ns",
		"kernel_calls", "kernel_total_ns", "static_validation_ns", "dynamic_validation_ns",
		"static_validation_timer_pairs", "dynamic_validation_timer_pairs", "axial_wake_ns",
		"axial_profile_ns", "swirl_ns", "kernel_finalize_ns", "clock_pair_overhead_ns",
	]
	for key: String in integer_keys:
		if not stats.has(key) or int(stats[key]) < 0:
			return false
	if (int(stats["calls"]) != expected_calls or int(stats["prepared_calls"]) != expected_calls or
			int(stats["kernel_calls"]) != expected_calls or int(stats["clock_pair_overhead_ns"]) <= 0):
		return false
	if (int(stats["static_validation_timer_pairs"]) != expected_calls * 3 or
			int(stats["dynamic_validation_timer_pairs"]) != expected_calls * 3):
		return false
	return true


func _bytes_hex(values: PackedFloat64Array) -> String:
	var result: String = ""
	for value: int in values.to_byte_array():
		result += "%02x" % value
	return result


func _median(samples: Array[float]) -> float:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	if sorted.size() % 2 == 0:
		return 0.5 * (sorted[middle - 1] + sorted[middle])
	return sorted[middle]
