# Temporary profiling script staged into a disposable app copy by run_attribution.py.
extends SceneTree

const NativeAdapter = preload("res://tests/e0b6p_native/adapter.gd")
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
	var raw: Dictionary = Fixture.combined_raw()
	raw.propulsion.propeller.slipstream.swirl_factor.value = 0.4
	var validated: Dictionary = AircraftData.validate_and_derive(raw)
	if not validated.get("ok", false) or not NativeAdapter.available():
		push_error("Fixture validation or native extension initialization failed")
		quit(1)
		return
	var backend: Object = NativeAdapter.backend
	if instrumented and (not backend.has_method("reset_attribution") or not backend.has_method("get_attribution")):
		push_error("Instrumented extension is missing its attribution methods")
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
			1.0, 0.0, 0.0, 0.0, 0.5 if regime == "spin" else 0.0, -0.3, 1.5 if regime == "spin" else 0.0,
		])
		var air: Dictionary = Air.compute(state, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225)
		var velocity: PackedFloat64Array = air.v_air
		var thrust_torque_full: PackedFloat64Array = Propulsion.thrust_torque(velocity, prop.max_rpm, prop, 1.225)
		var thrust_torque: PackedFloat64Array = PackedFloat64Array([thrust_torque_full[0], thrust_torque_full[1]])
		var fade: float = Oracle.reverse_weight(velocity, prop.max_rpm, prop)
		var downwash_cl: float = 0.3
		var transported_dv: PackedFloat64Array = PackedFloat64Array()
		for _warmup: int in WARMUP_CALLS:
			var warmup_result: Variant = backend.call("loads", state, velocity, controls, model,
					thrust_torque, 1.225, fade, downwash_cl, transported_dv)
			if not _valid_loads(warmup_result):
				push_error("Direct native warm-up returned invalid loads for " + regime)
				quit(1)
				return
		var direct_samples_us: Array[float] = []
		var direct_empty_loop_us: Array[float] = []
		var direct_stats: Array[Dictionary] = []
		var direct_loads: PackedFloat64Array = PackedFloat64Array()
		for _batch: int in MEASURED_BATCHES:
			if instrumented:
				backend.call("reset_attribution")
			var loop_start: int = Time.get_ticks_usec()
			var loop_sink: int = 0
			for index: int in CALLS_PER_BATCH:
				loop_sink += index & 1
			direct_empty_loop_us.append(float(Time.get_ticks_usec() - loop_start) / CALLS_PER_BATCH)
			var direct_start: int = Time.get_ticks_usec()
			var direct_last: Variant = null
			for _call_index: int in CALLS_PER_BATCH:
				direct_last = backend.call("loads", state, velocity, controls, model,
						thrust_torque, 1.225, fade, downwash_cl, transported_dv)
			var direct_elapsed: int = Time.get_ticks_usec() - direct_start
			if not _valid_loads(direct_last):
				push_error("Direct native call returned invalid loads for " + regime)
				quit(1)
				return
			direct_loads = direct_last
			direct_samples_us.append(float(direct_elapsed) / CALLS_PER_BATCH)
			if instrumented:
				var stats_value: Variant = backend.call("get_attribution")
				if not stats_value is Dictionary:
					push_error("Attribution method did not return a Dictionary")
					quit(1)
					return
				var stats: Dictionary = stats_value
				if int(stats.get("calls", -1)) != CALLS_PER_BATCH:
					push_error("Direct attribution count differs from calls for " + regime)
					quit(1)
					return
				direct_stats.append(stats)
		var adapter_samples_us: Array[float] = []
		var adapter_stats: Array[Dictionary] = []
		var adapter_routes_batches: Array[Dictionary] = []
		var adapter_loads: PackedFloat64Array = PackedFloat64Array()
		var adapter_routes: Dictionary = {}
		for _batch: int in MEASURED_BATCHES:
			NativeAdapter.reset_route_counts()
			if instrumented:
				backend.call("reset_attribution")
			var adapter_start: int = Time.get_ticks_usec()
			var adapter_last: Variant = null
			for _call_index: int in CALLS_PER_BATCH:
				adapter_last = NativeAdapter.loads(state, air, controls, model, prop.max_rpm, 1.225, 0.3)
			var adapter_elapsed: int = Time.get_ticks_usec() - adapter_start
			if not _valid_loads(adapter_last):
				push_error("Native adapter returned invalid loads for " + regime)
				quit(1)
				return
			adapter_loads = adapter_last
			adapter_samples_us.append(float(adapter_elapsed) / CALLS_PER_BATCH)
			adapter_routes = NativeAdapter.route_counts.duplicate(true)
			adapter_routes_batches.append(adapter_routes)
			if instrumented:
				var adapter_stats_value: Variant = backend.call("get_attribution")
				if not adapter_stats_value is Dictionary:
					push_error("Attribution method did not return a Dictionary")
					quit(1)
					return
				var adapter_stat: Dictionary = adapter_stats_value
				if int(adapter_stat.get("calls", -1)) != int(adapter_routes.get("kernel_calls", -2)):
					push_error("Adapter route count differs from instrumented native calls for " + regime)
					quit(1)
					return
				adapter_stats.append(adapter_stat)
		if direct_loads != adapter_loads:
			push_error("Direct extension and shipping adapter loads differ for " + regime)
			quit(1)
			return
		rows.append({
			"regime": regime,
			"fade": fade,
			"direct_loads": Array(direct_loads),
			"direct_external_us_per_call_batches": direct_samples_us,
			"direct_empty_loop_us_per_iteration_batches": direct_empty_loop_us,
			"direct_internal_stats_batches": direct_stats,
			"adapter_loads": Array(adapter_loads),
			"adapter_external_us_per_call_batches": adapter_samples_us,
			"adapter_internal_stats_batches": adapter_stats,
			"adapter_routes_batches": adapter_routes_batches,
			"adapter_routes_last_batch": adapter_routes,
		})
		print("E0b6p attribution %s: direct %.3f us/call; adapter %.3f us/call" % [
			regime, _median(direct_samples_us), _median(adapter_samples_us)])
	var output: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	if output == null:
		push_error("Could not write attribution report: " + report_path)
		quit(1)
		return
	output.store_string(JSON.stringify({
		"format": "openrc-e0b6p-native-attribution-profile v1",
		"instrumented": instrumented,
		"cpu": OS.get_processor_name(),
		"godot": Engine.get_version_info().string,
		"warmup_calls_per_regime": WARMUP_CALLS,
		"calls_per_batch": CALLS_PER_BATCH,
		"measured_batches": MEASURED_BATCHES,
		"rows": rows,
	}, "\t", true, true) + "\n")
	quit()


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


func _median(samples: Array[float]) -> float:
	var sorted: Array[float] = samples.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	if sorted.size() % 2 == 0:
		return 0.5 * (sorted[middle - 1] + sorted[middle])
	return sorted[middle]
