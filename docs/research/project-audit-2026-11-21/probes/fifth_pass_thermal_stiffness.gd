extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Pack = preload("res://physics/battery/pack_ecm.gd")
const PATH: String = "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
var failures: int = 0

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok: failures += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(PATH)
	check("complete custom aircraft passes production loader", loaded.ok)
	if not loaded.ok:
		print("REFUSAL " + str(loaded.errors))
		quit(1)
		return
	var flight: Node = Flight.new()
	flight.setup(PATH, "turbo-lumber-evolution")
	flight.input_enabled = false
	check("custom aircraft passes production flight setup", flight.is_flyable())
	if not flight.is_flyable():
		print("SETUP_REFUSAL " + str(flight.start_error))
		flight.free()
		quit(1)
		return
	flight.engine_running = false
	flight.sim.inputs[3] = 0.0
	var prop: Dictionary = flight.aircraft.model.propulsion
	var battery: Dictionary = prop.battery
	var point: Dictionary = flight.electrical_state()
	var index: int = flight._rotor_index() + 1 + Pack.temperature_index(battery)
	var ambient: float = float(point.ambient_k)
	var initial_delta: float = 0.1
	flight.sim.continuous[index] = ambient + initial_delta
	var cp: Dictionary = flight.checkpoint()
	var restored: Node = Flight.new()
	restored.setup(PATH, "turbo-lumber-evolution")
	restored.input_enabled = false
	check("warm state is admitted by checkpoint restore", restored.restore_checkpoint(bytes_to_var(var_to_bytes(cp))))
	var initial_tick: int = restored.sim.tick
	var dt: float = restored.sim.dt()
	var tau: float = float(battery.thermal_capacity_j_per_k) / float(battery.h_still_w_per_k)
	var old_ratio: float = restored._pack_step_ratio(prop)
	var before: float = restored.sim.continuous[index]
	restored.sim.step()
	var after: float = restored.sim.continuous[index]
	var z: float = -dt / tau
	var factor: float = 1.0 + z + z*z/2.0 + z*z*z/6.0 + z*z*z*z/24.0
	var expected_exact: float = ambient + initial_delta * exp(z)
	check("production session accepts the tick", restored.sim.tick == initial_tick + 1 and restored.sim.fault_reason.is_empty())
	check("cooling increases the temperature excess", after - ambient > before - ambient)
	check("result matches RK4 unstable scalar cooling multiplier", absf((after-ambient) / initial_delta - factor) < 1e-8)
	var after_point: Dictionary = restored.electrical_state()
	check("motor and pack current remain zero", after_point.ok and float(after_point.pack_current_a) == 0.0)
	print("R5_THERMAL_RESULT " + JSON.stringify({scope = "complete custom battery+aircraft loader, launch, warm checkpoint restore and one accepted reference FlightSession tick; constructed custom pack; not shipped pack accuracy", dt_s = dt, initial_tick = initial_tick, final_tick = restored.sim.tick, fault = restored.sim.fault_reason, thermal_tau_s = tau, old_pack_step_ratio = old_ratio, temperature_index = index, ambient_k = ambient, before_k = before, after_k = after, exact_after_k = expected_exact, rk4_multiplier = factor, exact_multiplier = exp(z), pack_current_a = after_point.get("pack_current_a", -1), body_temperature_default = point.temperature_k}))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	raw.propulsion.battery.auxiliary_current_a.value = 0.3
	var warmup_path: String = "res://thermal_positive_heat_aircraft.json"
	var output: FileAccess = FileAccess.open(warmup_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(raw, "\t", true, true))
	output.close()
	var fresh: Node = Flight.new()
	fresh.setup(warmup_path, "turbo-lumber-evolution")
	fresh.input_enabled = false
	fresh.engine_running = false
	fresh.sim.inputs[3] = 0.0
	check("positive auxiliary-current variant passes complete setup", fresh.is_flyable())
	if fresh.is_flyable():
		var fresh_initial: Dictionary = fresh.electrical_state()
		var fresh_t: float = fresh.sim.continuous[index]
		var fresh_tick: int = fresh.sim.tick
		fresh.sim.step()
		var fresh_after: Dictionary = fresh.electrical_state()
		check("positive-heat case starts exactly at ambient without injected temperature", fresh_t == float(fresh_initial.ambient_k))
		check("fresh positive-heat session accepts the tick", fresh.sim.tick == fresh_tick + 1 and fresh.sim.fault_reason.is_empty())
		check("positive pack heat nevertheless lowers temperature below ambient", fresh_after.ok and float(fresh_initial.cell_heat_w) > 0.0 and float(fresh_after.temperature_k) < float(fresh_after.ambient_k))
		print("R5_THERMAL_STARTUP_RESULT " + JSON.stringify({scope = "fresh production setup at ambient, no injected temperature or checkpoint; custom pack, 0.3 A auxiliaries and source disabled", before_k = fresh_t, after_k = fresh_after.get("temperature_k", 0.0), ambient_k = fresh_after.get("ambient_k", 0.0), initial_heat_w = fresh_initial.get("cell_heat_w", 0.0), final_heat_w = fresh_after.get("cell_heat_w", 0.0), initial_current_a = fresh_initial.pack_current_a, final_current_a = fresh_after.get("pack_current_a", 0.0), accepted_tick = fresh.sim.tick, fault = fresh.sim.fault_reason}))
	fresh.free()
	flight.free()
	restored.free()
	var refinement: Array = []
	for hz: int in [240, 480, 960, 1920]:
		Engine.physics_ticks_per_second = hz
		var sample: Node = Flight.new()
		sample.setup(PATH, "turbo-lumber-evolution")
		sample.input_enabled = false
		sample.engine_running = false
		sample.sim.inputs[3] = 0.0
		sample.sim.continuous[index] = ambient + initial_delta
		var count: int = hz / 240
		for _i: int in count:
			sample.sim.step()
		check("isolated thermal refinement accepts %d Hz steps" % hz, sample.sim.tick == count and sample.sim.fault_reason.is_empty())
		refinement.append({hz = hz, ticks = sample.sim.tick, time_s = float(count) / float(hz), temperature_excess_k = sample.sim.continuous[index] - ambient, exact_excess_k = initial_delta * exp(-1.0 / (240.0 * tau)), fault = sample.sim.fault_reason})
		sample.free()
	Engine.physics_ticks_per_second = 240
	print("R5_THERMAL_REFINEMENT_RESULT " + JSON.stringify(refinement))
	print("R5 thermal witness: %d failures" % failures)
	quit(1 if failures else 0)
