# BAT-10/11/13: Lumber pack_ecm session end to end. Layout, sag and recovery, heating, ESC soft cut, exhaustion,
# exact replay, trace v13, launch guard and the unchanged ideal mode. Software verification only.
extends SceneTree

const Flight: Script = preload("res://sim/flight_session.gd")
const Recorder: Script = preload("res://sim/recorder.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")
const AircraftData: Script = preload("res://physics/aircraft_data.gd")
const PackEcm: Script = preload("res://physics/battery/pack_ecm.gd")

const TIMBER := "turbo-lumber-evolution"

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func flight(frozen: Dictionary = {}) -> Node:
	var value: Node = Flight.new()
	value.setup(Catalog.data_for(TIMBER, "pack"), TIMBER, frozen)
	value.input_enabled = false
	return value


func advance(value: Node, count: int) -> bool:
	var initial: int = value.sim.tick
	for _i: int in count:
		value.sim.step()
		if not value.sim.fault_reason.is_empty():
			print("fault: ", value.sim.fault_reason)
			return false
	return value.sim.tick == initial + count


## Loaded pack data with battery/ESC overrides, frozen for setup (the file itself is never edited).
func variant(battery_changes: Dictionary, lvc_changes: Dictionary = {}) -> Dictionary:
	var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(TIMBER, "pack"))
	var data: Dictionary = loaded.duplicate(true)
	data.model.propulsion.battery.merge(battery_changes, true)
	data.model.propulsion.esc.low_voltage_cutoff.merge(lvc_changes, true)
	if lvc_changes.has("voltage_filter_s"):
		data.model.propulsion.battery.lvc_filter_s = lvc_changes.voltage_filter_s
	return data


func _initialize() -> void:
	_catalog_modes()
	var a: Node = flight()
	if not a.is_flyable():
		check("pack Lumber is flyable: " + str(a.aircraft.get("errors", [])) + " " + str(a.start_error), false)
		a.free()
		_finish()
		return
	_layout_and_connection(a)
	_sag_recovery_and_heat(a)
	_replay_and_trace(a)
	a.free()
	_soft_cut()
	_exhaustion_without_lvc()
	_launch_guard_and_weak_cell()
	_finish()


func _finish() -> void:
	print("BAT-10/11/13 battery session: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _catalog_modes() -> void:
	check("Lumber offers the pack mode", Catalog.has_battery_mode(TIMBER, "pack"))
	check("pack data differs from the ideal data", Catalog.data_for(TIMBER, "pack") != Catalog.data_for(TIMBER, "ideal")
		and not Catalog.data_for(TIMBER, "ideal").is_empty())
	check("aircraft without battery data refuse the pack mode", not Catalog.has_battery_mode(Catalog.DEFAULT_ID, "pack")
		and Catalog.data_for(Catalog.DEFAULT_ID, "pack") == "")
	check("unknown battery mode refused", not Catalog.has_battery_mode(TIMBER, "magic"))
	var ideal: Node = Flight.new()
	ideal.setup(Catalog.data_for(TIMBER, "ideal"), TIMBER)
	check("ideal mode stays the fixed bus", ideal.is_flyable() and not ideal.battery_is_dynamic() and not ideal.battery_is_pack())
	ideal.free()
	var pack_data: Dictionary = AircraftData.load_file(Catalog.data_for(TIMBER, "pack"))
	var ideal_data: Dictionary = AircraftData.load_file(Catalog.data_for(TIMBER, "ideal"))
	check("pack variant keeps aircraft id, mass and inertia", pack_data.ok and ideal_data.ok
		and pack_data.model.id == TIMBER and pack_data.model.mass_kg == ideal_data.model.mass_kg
		and pack_data.model.inertia == ideal_data.model.inertia)


func _layout_and_connection(a: Node) -> void:
	var battery: Dictionary = a.aircraft.model.propulsion.battery
	var block: int = PackEcm.block_size(battery)
	check("pack session law", a.battery_is_pack() and a.battery_is_dynamic() and a.electric_law() == Flight.PACK_LAW)
	check("battery block sits before the wheel speeds", a.wheel_index() == a._rotor_index() + 1 + block
		and a.sim.continuous.size() == a._rotor_index() + 1 + block + a.wheel_count())
	var point: Dictionary = a.electrical_state()
	check("connected rest point", point.ok and point.battery_kind == "pack_ecm" and point.esc_state == "normal"
		and point.esc_detected_cells == 4 and point.esc_limit == 1.0)
	check("pack starts at ambient temperature with auxiliary sag", point.ok and point.temperature_k == point.ambient_k
		and point.bus_voltage_v < point.ocv_v and point.polarization_v == 0.0)
	check("identity reaches telemetry", point.ok and point.pack_id == "lipo-4s1p-3200-30c-class" and point.series == 4
		and point.rated_capacity_ah == 3.2)


func _sag_recovery_and_heat(a: Node) -> void:
	var start: Dictionary = a.electrical_state()
	a.engine_running = true
	a.sim.inputs[3] = 1.0
	check("full-throttle flight advances", advance(a, 480))
	var loaded: Dictionary = a.electrical_state()
	check("full throttle draws current and sags", loaded.pack_current_a > 10.0 and loaded.bus_voltage_v < loaded.ocv_v - 0.2)
	check("polarization builds under load", loaded.polarization_v > 0.0)
	check("pack heats under load", loaded.temperature_k > start.temperature_k)
	check("charge budget closes", absf(loaded.remaining_charge_c + loaded.consumed_charge_c - start.remaining_charge_c) < 1e-9
		and loaded.consumed_charge_c > 0.0 and loaded.soc < start.soc)
	check("energy and loss accumulate", loaded.terminal_energy_j > 0.0 and loaded.pack_heat_j > 0.0)
	a.sim.inputs[3] = 0.0
	check("rest after the climb advances", advance(a, 960))
	var rested: Dictionary = a.electrical_state()
	check("voltage recovers as polarization relaxes", rested.polarization_v < loaded.polarization_v
		and rested.bus_voltage_v > loaded.bus_voltage_v)
	check("idle keeps only auxiliary current", absf(rested.pack_current_a - a.aircraft.model.propulsion.battery.auxiliary_current_a) < 1e-12)


func _replay_and_trace(a: Node) -> void:
	var saved: Dictionary = a.checkpoint()
	check("pack checkpoint identity", saved.get("format") == "openrc-flight-checkpoint v6" and saved.get("electric_law") == Flight.PACK_LAW)
	var b: Node = flight()
	check("pack checkpoint restores on a fresh owner", b.restore_checkpoint(bytes_to_var(var_to_bytes(saved))))
	a.sim.inputs[3] = 0.8
	b.sim.inputs[3] = 0.8
	check("owners replay the pack exactly", advance(a, 240) and advance(b, 240)
		and var_to_bytes(a.checkpoint()) == var_to_bytes(b.checkpoint()))
	var wrong: Dictionary = saved.duplicate(true)
	wrong.electric_law = Flight.BATTERY_LAW
	check("a different electric law is refused", not b.restore_checkpoint(wrong))
	b.free()
	a.reset()
	var reset_point: Dictionary = a.electrical_state()
	check("reset reconnects a rested full pack", reset_point.ok and reset_point.consumed_charge_c == 0.0
		and reset_point.polarization_v == 0.0 and reset_point.esc_state == "normal")
	var record: RefCounted = Recorder.new(a.sim, a.electrical_state)
	record.start(a.trace_meta())
	a.engine_running = true
	a.sim.inputs[3] = 0.7
	check("traced pack flight advances", advance(a, 120))
	var csv: String = record.trace.to_csv()
	check("pack trace is v13 with pack and ESC channels", record.trace.row_count() == 121
		and csv.begins_with("# format: openrc-trace v13\n") and record.trace.columns().has("cell_voltage_min_v")
		and record.trace.columns().has("esc_phase") and record.trace.columns().has("pack_temperature_k"))
	check("trace endpoint matches telemetry", record.trace.value(120, "remaining_charge_c") == a.electrical_state().remaining_charge_c)


func _soft_cut() -> void:
	var low: Node = flight(variant({"initial_soc": 0.08}))
	check("low pack flies", low.is_flyable())
	if not low.is_flyable():
		low.free()
		return
	low.engine_running = true
	low.sim.inputs[3] = 1.0
	var cut_seen: bool = false
	var limit_at_end: float = 1.0
	for _second: int in 40:
		if not advance(low, 240):
			break
		var point: Dictionary = low.electrical_state()
		if point.esc_state == "soft_cut":
			cut_seen = true
			limit_at_end = point.esc_limit
			check("supervised duty never exceeds the ESC limit", point.effective_duty <= point.esc_limit + 1e-15)
			if point.esc_limit <= 0.5 + 1e-12:
				break
	check("loaded voltage trips the soft cut", cut_seen)
	check("soft cut ramps to the declared 50 % limit", absf(limit_at_end - 0.5) < 1e-12)
	low.free()


func _exhaustion_without_lvc() -> void:
	var empty: Node = flight(variant({"initial_soc": 0.03}, {"mode": "off"}))
	check("near-empty pack without LVC flies", empty.is_flyable())
	if not empty.is_flyable():
		empty.free()
		return
	empty.engine_running = true
	empty.sim.inputs[3] = 1.0
	var exhausted: bool = false
	var located: Array[String] = []
	empty.sim.events_located.connect(func(_tick: int, events: Array) -> void:
		for event: Dictionary in events:
			located.append(str(event.get("type", ""))))
	for _second: int in 120:
		if not advance(empty, 240):
			break
		if empty.electrical_state().exhausted:
			exhausted = true
			break
	var point: Dictionary = empty.electrical_state()
	check("weak cell reaches the data floor", exhausted and point.esc_state == "off")
	check("exhaustion event is located exactly once", located.count("battery_exhausted") == 1)
	check("exhausted pack disconnects every load", point.pack_current_a == 0.0 and point.auxiliary_current_a == 0.0)
	empty.free()


func _launch_guard_and_weak_cell() -> void:
	var probe: Node = flight()
	var stiff: Dictionary = probe.aircraft.duplicate(true)
	stiff.model.propulsion.battery.group_capacity_c = 1e-6
	check("pack charge stiffness refuses launch", not probe._prepare_aircraft(stiff).ok)
	var fast_filter: Dictionary = probe.aircraft.duplicate(true)
	fast_filter.model.propulsion.battery.lvc_filter_s = 1e-4
	check("too fast an ESC filter refuses launch", not probe._prepare_aircraft(fast_filter).ok)
	probe.free()
	var aged: Node = flight(variant({"weak_capacity_factor": 0.85, "weak_resistance_factor": 1.6}))
	aged.engine_running = true
	aged.sim.inputs[3] = 1.0
	check("aged pack flies", aged.is_flyable() and advance(aged, 720))
	var point: Dictionary = aged.electrical_state()
	check("weak cell sags below the average cell", point.cell_voltage_min_v < point.cell_voltage_avg_v and point.soc_weak < point.soc)
	aged.free()
