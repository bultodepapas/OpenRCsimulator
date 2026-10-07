# Whole-tick E0b6p attribution. Run only in the disposable copy made by run.py.
extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const Fixture = preload("res://tests/test_wash_transport.gd")
const RB = preload("res://physics/rigid_body.gd")
const Aero = preload("res://physics/aero.gd")
const Air = preload("res://physics/air_data.gd")
const Adapter = preload("res://tests/e0b6p_native/adapter.gd")
const Profiler = preload("res://tests/e0b6p_attribution/profiler.gd")
const TICKS: int = 24
const BATCHES: int = 6
const TRAJECTORY_TICKS: int = 240
const REGIMES: Array[String] = ["forward", "stall", "static", "spin", "reverse_fade", "reverse_off"]


func _initialize() -> void:
	var rows: Array[Dictionary] = []
	Profiler.enabled = false
	for regime: String in REGIMES:
		for enabled_swirl: bool in [false, true]:
			var flight: Node = Flight.new()
			if not Fixture.configure(flight):
				quit(1)
				return
			flight.aircraft.model.propulsion.slipstream.erase("transport_speed_floor")
			flight.aircraft.model.propulsion.slipstream.swirl_factor = 0.4 if enabled_swirl else 0.0
			flight.reset()
			var state: PackedFloat64Array = flight.sim.state.duplicate()
			var speed: float = 0.0 if regime == "static" else 15.0
			if regime.begins_with("reverse"):
				var prop: Dictionary = flight.aircraft.model.propulsion
				var vi0: float = prop.max_rpm / 60.0 * prop.diameter * sqrt(2.0 * prop.ct[1] / PI)
				speed = (-0.15 if regime == "reverse_fade" else -0.3) * vi0
			var alpha: float = deg_to_rad(15.0 if regime in ["stall", "spin"] else (0.0 if regime.begins_with("reverse") else 3.0))
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
				quit(1)
				return
			var checkpoint: Dictionary = flight.sim.checkpoint()
			Adapter.reset_route_counts()
			var disabled_samples: Array[float] = []
			var enabled_samples: Array[Dictionary] = []
			for batch: int in BATCHES:
				var first_mode: int = batch % 2
				for order_index: int in 2:
					var mode: int = first_mode if order_index == 0 else 1 - first_mode
					Profiler.enabled = mode == 1
					if not flight.sim.restore_checkpoint(checkpoint):
						quit(1)
						return
					Profiler.reset()
					var started: int = Time.get_ticks_usec()
					for tick: int in TICKS:
						flight.sim.step()
					if flight.sim.tick != TICKS or not flight.sim.fault_reason.is_empty():
						push_error("Attribution timing run faulted: " + flight.sim.fault_reason)
						quit(1)
						return
					var elapsed: float = float(Time.get_ticks_usec() - started) / float(TICKS)
					if batch > 0:
						if mode == 0:
							disabled_samples.append(elapsed)
						else:
							enabled_samples.append({wall_us_per_tick = elapsed, profile = Profiler.snapshot(), pair = batch - 1})
			Profiler.enabled = true
			if not flight.sim.restore_checkpoint(checkpoint):
				quit(1)
				return
			Profiler.reset()
			var boundaries: Array[Dictionary] = []
			for tick: int in TRAJECTORY_TICKS:
				flight.sim.step()
				if not flight.sim.fault_reason.is_empty():
					push_error(flight.sim.fault_reason)
					quit(1)
					return
				boundaries.append({state = Array(flight.sim.state), aux = Array(flight.sim.aux),
					continuous = Array(flight.sim.continuous)})
			var trajectory_profile: Dictionary = Profiler.snapshot()
			Profiler.enabled = false
			var route_counts: Dictionary = Adapter.route_counts.duplicate(true)
			if int(route_counts.get("native", 0)) <= 0 or int(route_counts.get("refused", -1)) != 0:
				push_error("Native adapter did not serve the attribution trajectory: " + str(route_counts))
				quit(1)
				return
			rows.append({regime = regime, swirl_factor = 0.4 if enabled_swirl else 0.0,
				disabled_samples_us_per_tick = disabled_samples, enabled_samples = enabled_samples,
				trajectory_profile = trajectory_profile, native_route_counts = route_counts, boundaries = boundaries})
			print("E0b6p attribution %s swirl=%s enabled median %.1f us/tick" % [
				regime, enabled_swirl, _median_wall(enabled_samples)])
			flight.free()
	var path: String = OS.get_cmdline_user_args()[0]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open attribution report: " + path)
		quit(1)
		return
	file.store_string(JSON.stringify({format = "openrc-e0b6p-tick-attribution v1",
		cpu = OS.get_processor_name(), godot = Engine.get_version_info().string,
		ticks_per_timing_batch = TICKS, warmup_batches = 1, measured_batches = BATCHES - 1,
		trajectory_ticks = TRAJECTORY_TICKS, rows = rows}, "\t", true, true) + "\n")
	quit()


func _median_wall(samples: Array[Dictionary]) -> float:
	var values: Array[float] = []
	for sample: Dictionary in samples:
		values.append(float(sample.wall_us_per_tick))
	values.sort()
	var middle: int = floori(float(values.size()) * 0.5)
	return values[middle]
