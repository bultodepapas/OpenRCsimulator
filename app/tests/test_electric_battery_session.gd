# EL2a: complete charge/energy session boundary and independent aux-only budgets.
extends SceneTree
const Flight: Script = preload("res://sim/flight_session.gd")
const Recorder: Script = preload("res://sim/recorder.gd")
const Trace: Script = preload("res://sim/trace.gd")
const Weather: Script = preload("res://physics/wind_config.gd")
const Prop: Script = preload("res://physics/propulsion.gd")
var checks: int = 0
var failures: int = 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func flight(config: String) -> Node:
	var value: Node = Flight.new()
	value.setup("res://data/aircraft/synthetic_stik_electric_%s_battery.json" % config)
	value.input_enabled = false
	return value

func advance(value: Node, count: int) -> bool:
	var initial: int = value.sim.tick
	for i: int in count:
		value.sim.step()
		if not value.sim.fault_reason.is_empty():
			print("fault: ", value.sim.fault_reason)
			return false
	return value.sim.tick == initial + count

func chemical_energy(pack: Dictionary, initial: float, final_charge: float) -> float:
	# Independent integral for these declared two-knot linear fixtures only.
	var curve: PackedFloat64Array = pack.ocv_points
	return curve[1] * (initial - final_charge) + (curve[3] - curve[1]) / (7200.0 * pack.capacity_ah) * (initial * initial - final_charge * final_charge)

func aux_budget(config: String) -> void:
	var a: Node = flight(config)
	var pack: Dictionary = a.aircraft.model.propulsion.battery
	a.engine_running = false
	var q0: float = a.sim.continuous[1]
	var duration: float = 120.0 * a.sim.dt()
	check("aux-only advances", advance(a, 120))
	var q1: float = q0 - pack.auxiliary_current_a * duration
	var heat: float = pack.resistance_ohm * pack.auxiliary_current_a * pack.auxiliary_current_a * duration
	var energy: float = chemical_energy(pack, q0, q1) - heat
	check("aux-only charge is analytic", absf(a.sim.continuous[1] - q1) < 2e-9)
	check("aux-only heat is analytic", absf(a.sim.continuous[3] - heat) < 1e-12)
	check("aux-only terminal energy is analytic", absf(a.sim.continuous[2] - energy) < 5e-8)
	# A declared low-charge numerical fixture reaches zero part-way through one real tick.
	a.reset()
	a.engine_running = false
	var event_time: float = a.sim.dt() * 0.37
	q0 = pack.auxiliary_current_a * event_time
	a.sim.continuous[1] = q0
	check("partial-tick charge fixture reset", a.sim.reset(a.sim.state))
	var rpm: float = a.sim.continuous[0]
	check("exhaustion tick advances", advance(a, 1))
	var point: Dictionary = a.electrical_state()
	check("exhaustion commits exact zero charge and SOC", point.ok and point.exhausted and point.remaining_charge_c == 0.0 and point.soc == 0.0)
	check("exhaustion disconnects motor and auxiliary", point.pack_current_a == 0.0 and point.battery_current_a == 0.0 and point.auxiliary_current_a == 0.0 and point.bus_voltage_v == 0.0)
	heat = pack.resistance_ohm * pack.auxiliary_current_a * pack.auxiliary_current_a * event_time
	energy = chemical_energy(pack, q0, 0.0) - heat
	check("partial-tick exhaustion energy is analytic", absf(point.terminal_energy_j - energy) < 2e-9 and absf(point.pack_heat_j - heat) < 1e-11)
	check("rotor coasts across electrical exhaustion", point.rpm > 0.0 and point.rpm < rpm)
	var empty: Dictionary = a.checkpoint()
	var b: Node = flight(config)
	check("exhausted checkpoint restores fresh owner", b.restore_checkpoint(bytes_to_var(var_to_bytes(empty))))
	a.engine_running = true
	b.engine_running = true
	check("exhausted source command does not recharge", advance(a, 10) and advance(b, 10) and a.sim.continuous[1] == 0.0 and a.sim.continuous[2] == point.terminal_energy_j)
	check("exhausted continuation is exact", var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
	a.reset()
	check("reset restores initial pack and zero accumulators", a.sim.continuous[1] == a._battery_initial_charge() and a.sim.continuous[2] == 0.0 and a.sim.continuous[3] == 0.0 and not a.electrical_state().exhausted)
	a.free()
	b.free()

func session_checks(config: String) -> void:
	var a: Node = flight(config)
	check("battery flight trims and selects coupled state", a.is_flyable() and a.battery_is_dynamic() and a.sim.continuous.size() == 4)
	if not a.is_flyable():
		a.free()
		return
	for capacity: float in [1e-320, 1e-9]:
		var stiff: Dictionary = a.aircraft.duplicate(true)
		stiff.model.propulsion.battery.capacity_ah = capacity
		check("battery feedback stiffness refuses launch", not a._prepare_aircraft(stiff).ok)
	var original: Dictionary = a.checkpoint()
	var initial: Dictionary = a.electrical_state()
	check("initial point includes sag and auxiliary load", initial.ok and initial.bus_voltage_v < initial.ocv_v and initial.pack_current_a > initial.battery_current_a)
	check("explicit battery checkpoint identity", original.format == "openrc-flight-checkpoint v6" and original.electric_law == Flight.BATTERY_LAW)
	var record: RefCounted = Recorder.new(a.sim, a.electrical_state)
	record.start(a.trace_meta())
	check("powered battery flight advances", advance(a, 240))
	var point: Dictionary = a.electrical_state()
	check("charge decreases and energy accumulates", point.remaining_charge_c < initial.remaining_charge_c and point.terminal_energy_j > 0.0 and point.pack_heat_j > 0.0)
	check("charge budget closes without redundant state", point.consumed_charge_c + point.remaining_charge_c == initial.remaining_charge_c)
	check("chemical work closes with terminal plus heat", absf(chemical_energy(a.aircraft.model.propulsion.battery, initial.remaining_charge_c, point.remaining_charge_c) - point.terminal_energy_j - point.pack_heat_j) < 2e-6)
	check("battery trace is v8 and records endpoints", record.trace.row_count() == 241 and record.trace.to_csv().begins_with("# format: openrc-trace v8\n") and record.trace.columns().has("remaining_charge_c"))
	check("trace last sample matches committed charge", record.trace.value(240, "remaining_charge_c") == point.remaining_charge_c)
	var saved: Dictionary = a.checkpoint()
	var b: Node = flight(config)
	check("native checkpoint restores on another owner", b.restore_checkpoint(bytes_to_var(var_to_bytes(saved))))
	check("owners advance replay exactly", advance(a, 120) and advance(b, 120) and var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
	var isolated: PackedByteArray = var_to_bytes(b.checkpoint())
	a.reset()
	check("reset of one owner leaves other unchanged", var_to_bytes(b.checkpoint()) == isolated)
	var frozen: PackedByteArray = var_to_bytes(b.checkpoint())
	b.hold("battery-test")
	b.sim._physics_process(b.sim.dt())
	check("pause freezes charge and energy with flight", var_to_bytes(b.checkpoint()) == frozen)
	b.release("battery-test")
	var invalid: Dictionary = saved.duplicate(true)
	for key: String in ["format", "electric_law", "configuration"]:
		invalid = saved.duplicate(true)
		invalid[key] = "wrong"
		check("reject wrong checkpoint " + key, not b.restore_checkpoint(invalid) and var_to_bytes(b.checkpoint()) == frozen)
	for index: int in [1, 2, 3]:
		invalid = saved.duplicate(true)
		invalid.simulation.continuous[index] = -0.1
		check("reject negative battery state " + str(index), not b.restore_checkpoint(invalid) and var_to_bytes(b.checkpoint()) == frozen)
	invalid = saved.duplicate(true)
	invalid.simulation.continuous[1] = initial.remaining_charge_c + 1.0
	check("reject charge above configured initial charge", not b.restore_checkpoint(invalid))
	invalid = saved.duplicate(true)
	invalid.simulation.continuous[1] = NAN
	check("reject nonfinite battery state", not b.restore_checkpoint(invalid))
	var wrong: Node = flight("6s" if config == "4s" else "4s")
	check("reject other pack configuration", not wrong.restore_checkpoint(saved))
	wrong.free()
	# Recorder must not accept a plausible-looking stale or internally inconsistent battery sample.
	for defect: String in ["missing", "soc", "exhausted", "charge", "nan"]:
		var bad: RefCounted = Trace.new()
		bad.meta = a.trace_meta()
		bad.electrical_sample = func() -> Dictionary:
			var sample: Dictionary = a.electrical_state()
			match defect:
				"missing": sample.erase("remaining_charge_c")
				"soc": sample.soc = 0.1
				"exhausted": sample.exhausted = true
				"charge": sample.consumed_charge_c = 1.0
				"nan": sample.pack_heat_j = NAN
			return sample
		bad.record(a.sim.tick, a.sim.time(), a.sim.state, a.sim.last_loads, a.sim.inputs, a.sim.aux)
		check("trace rejects malformed battery sample " + defect, bad.row_count() == 0)
	# A runtime supply failure rolls back all continuous and sampled values together.
	check("prepare fault checkpoint", b.restore_checkpoint(saved))
	var before_state: PackedFloat64Array = b.sim.state.duplicate()
	var before_extra: PackedFloat64Array = b.sim.continuous.duplicate()
	var before_aux: PackedFloat64Array = b.sim.aux.duplicate()
	var before_modes: PackedInt64Array = b.sim.modes.duplicate()
	var before_tick: int = b.sim.tick
	b.aircraft.model.propulsion.battery.resistance_ohm = INF
	b.sim.step()
	check("invalid supply triggers whole-state rollback", not b.sim.fault_reason.is_empty() and b.sim.tick == before_tick and b.sim.state == before_state and b.sim.continuous == before_extra and b.sim.aux == before_aux and b.sim.modes == before_modes)
	record.detach()
	a.free()
	b.free()

func weather_checks() -> void:
	for preset: String in ["turbulent", "hot-high"]:
		var a: Node = Flight.new()
		check("battery weather selected", a.setup_weather(Weather.preset(preset)))
		a.setup("res://data/aircraft/synthetic_stik_electric_4s_battery.json")
		a.input_enabled = false
		check("battery weather flight trims", a.is_flyable())
		var recorder: RefCounted = Recorder.new(a.sim, a.electrical_state)
		recorder.start(a.trace_meta())
		check("battery weather advances", advance(a, 120))
		check("weather composes with v8 battery columns", recorder.trace.row_count() == 121 and recorder.trace.to_csv().begins_with("# format: openrc-trace v8\n") and recorder.trace.columns().has("pack_heat_j"))
		var b: Node = flight("4s")
		check("battery checkpoint restores weather and RNG", b.restore_checkpoint(bytes_to_var(var_to_bytes(a.checkpoint()))))
		check("battery weather replay is exact", advance(a, 120) and advance(b, 120) and var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
		recorder.detach()
		a.free()
		b.free()

func _initialize() -> void:
	check("malformed battery capability is refused", not Prop.has_dynamic_battery({kind = "electric_prop", battery = "invalid"}))
	for config: String in ["4s", "6s"]:
		session_checks(config)
		aux_budget(config)
	weather_checks()
	print("EL2a battery session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
