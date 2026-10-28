# NK-2a: FlightSession memoizes capability/layout answers for one kernel tick. Only the kernel's pre_tick arms the
# memo; the accepted or rejected tick drops it, so aircraft data replaced or edited between ticks is read afresh.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const BatteryData := preload("res://physics/battery/battery_data.gd")
const IDEAL := "res://data/aircraft/synthetic_stik_electric_4s.json"
const OCV := "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
const PACK := "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"
var checks := 0
var failures := 0


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	call_deferred("run_all")


func answers(session: Node) -> Array:
	return [session.glow_is_active(), session.gear_is_retractable(), session.wheel_brake_available(),
		session.flaps_available(), session.wheel_count(), session.anchor_count(), session.downwash_index(),
		session._rotor_index(), session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]


func memo_empty(session: Node) -> bool:
	return not session._facts_armed and [session._fact_glow, session._fact_gear_retractable, session._fact_wheel_brake,
		session._fact_flaps, session._fact_wheel_count, session._fact_anchor_count, session._fact_downwash_index,
		session._fact_rotor_index, session._fact_battery_dynamic, session._fact_battery_pack,
		session._fact_battery_block_size].all(
		func(value: int) -> bool: return value == Flight._FACT_UNKNOWN)


func memo_populated(session: Node) -> bool:
	return session._facts_armed and [session._fact_glow, session._fact_gear_retractable, session._fact_wheel_brake,
		session._fact_flaps, session._fact_wheel_count, session._fact_anchor_count, session._fact_downwash_index,
		session._fact_rotor_index, session._fact_battery_dynamic, session._fact_battery_pack,
		session._fact_battery_block_size].all(
		func(value: int) -> bool: return value != Flight._FACT_UNKNOWN)


func flight(id: String) -> Node:
	var session: Node = Flight.new()
	session.setup(str(Catalog.entry(id).data), id)
	check(id + " is flyable", session.is_flyable(), str(session.pause_reason))
	return session


func battery_definitions() -> Dictionary:
	var result := {}
	for entry: Array in [["ideal", IDEAL], ["ocv", OCV], ["pack", PACK]]:
		var loaded: Dictionary = AircraftData.load_file(entry[1])
		check("normalized battery fixture loads: " + entry[0], loaded.get("ok", false), str(loaded.get("errors", [])))
		if not loaded.get("ok", false): return {}
		result[entry[0]] = loaded.model.propulsion.battery.duplicate(true)
	# A second real, hash-checked pack exercises a changed branch count with the same pack kind.
	var errors := PackedStringArray()
	var two: Dictionary = BatteryData.load_pack(errors, "battery_layout_fixture", "liion-4s1p-3000-hg2",
		"5a2f33dd7843f3cf7e5b6133e10cebd331a0d8d2b45977fb0b5c5425b4077afe")
	check("pack fixtures have one and two valid branches", errors.is_empty() and not two.is_empty()
		and int(result.pack.branches) == 1 and int(two.branches) == 2, str(errors))
	if not errors.is_empty() or two.is_empty() or int(result.pack.branches) != 1 or int(two.branches) != 2:
		return {}
	# The normalized pack is complete; copy the same validated installation settings for query-only replacement.
	for key: String in ["kind", "initial_soc", "auxiliary_current_a", "cooling_airflow_fraction", "weak_capacity_factor",
			"weak_resistance_factor", "weak_soc_offset", "mount_inventory_id"]:
		two[key] = result.pack[key]
	result.pack_two = two
	return result


func battery_case(label: String, path: String, expected: Array, batteries: Dictionary) -> void:
	var session: Node = Flight.new()
	session.setup(path)
	check(label + " fixture is flyable", session.is_flyable(), str(session.pause_reason))
	if not session.is_flyable():
		session.free()
		return
	var direct := [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
	check(label + " direct answers are correct and do not arm the memo", direct == expected and memo_empty(session), str(direct))
	var wheel_at: int = session._rotor_index() + 1 + int(expected[2])
	check(label + " battery block agrees with the actual continuous layout", session.shaft_is_coupled()
		and session.wheel_index() == wheel_at and session.sim.continuous.size() == wheel_at + session.wheel_count())
	if expected[0]:
		check(label + " battery block validates in the actual continuous layout", session._battery_values_valid(session.sim.continuous))

	var inside := {}
	var kernel_pre_tick: Callable = session.sim.model.pre_tick
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = kernel_pre_tick.call(aux, inputs, dt)
		inside.armed = session._facts_armed
		inside.first = [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		inside.cached = [session._fact_battery_dynamic, session._fact_battery_pack, session._fact_battery_block_size]
		inside.again = [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		return out
	var tick: int = session.sim.tick
	session.sim.step()
	check(label + " accepted tick advances", session.sim.tick == tick + 1 and session.sim.fault_reason.is_empty(), session.sim.fault_reason)
	check(label + " memoized answers match direct answers on repeat", inside.get("armed", false)
		and inside.get("first") == direct and inside.get("again") == direct
		and inside.get("cached") == [int(expected[0]), int(expected[1]), expected[2]], str(inside))
	check(label + " accepted tick clears battery facts", memo_empty(session))

	# Use complete normalized battery definitions. These replacements exercise queries only; no physics tick
	# runs against a different battery layout, and the original complete configuration is restored afterward.
	var prop: Dictionary = session.aircraft.model.propulsion
	var had_battery: bool = prop.has("battery")
	var saved: Dictionary = prop.get("battery", {}).duplicate(true)
	for example: Array in [["fixed_voltage", batteries.ideal, [false, false, 0]],
			["ocv_resistance", batteries.ocv, [true, false, 3]], ["one_branch_pack", batteries.pack, [true, true, 11]],
			["two_branch_pack", batteries.pack_two, [true, true, 13]]]:
		prop["battery"] = example[1].duplicate(true)
		var changed := [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		check(label + " edited battery is read outside a tick: " + str(example[0]), changed == example[2]
			and session.wheel_index() == session._rotor_index() + 1 + int(example[2][2]) and memo_empty(session), str(changed))
		if example[2][0] and example[2][2] != expected[2]:
			check(label + " changed battery refuses the old layout: " + str(example[0]),
				not session._battery_values_valid(session.sim.continuous))
		session._facts_armed = true # the next kernel tick's fact lifetime
		var inside_changed := [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		check(label + " edited battery is read when rearmed: " + str(example[0]), inside_changed == example[2]
			and session._fact_battery_dynamic == int(example[2][0]) and session._fact_battery_pack == int(example[2][1])
			and session._fact_battery_block_size == int(example[2][2]))
		session._drop_tick_facts()
	if had_battery:
		prop["battery"] = saved
	else:
		prop.erase("battery")
	check(label + " restoring the original battery restores direct answers", [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()] == direct
		and memo_empty(session))

	session._pre_step(session.sim.aux, session.sim.inputs, session.sim.dt())
	check(label + " direct pre_step does not retain battery facts", memo_empty(session))
	inside.clear()
	session._weather_pending_reset = true
	session.sim.step()
	check(label + " rejected tick faults and clears battery facts", not session.sim.fault_reason.is_empty()
		and inside.get("armed", false) and inside.get("first") == direct and memo_empty(session), str(inside))
	session._weather_pending_reset = false
	# Seed valid cached answers and verify the reset boundary clears them, even without another physics step.
	session._facts_armed = true
	session._fact_battery_dynamic = int(expected[0])
	session._fact_battery_pack = int(expected[1])
	session._fact_battery_block_size = int(expected[2])
	session.reset()
	check(label + " reset clears cached facts and preserves direct answers", memo_empty(session)
		and [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()] == direct and session.is_flyable(), session.pause_reason)
	session.free()


func signal_boundary_cases(batteries: Dictionary) -> void:
	var session: Node = Flight.new()
	session.setup(OCV)
	check("signal-boundary fixture is flyable", session.is_flyable(), str(session.pause_reason))
	if not session.is_flyable():
		session.free()
		return
	var prop: Dictionary = session.aircraft.model.propulsion
	var saved: Dictionary = prop.battery.duplicate(true)

	# The kernel emits located events after committing a tick but before stepped. Emit the signal directly
	# here to exercise observer ordering; battery_case separately drives real accepted simulation ticks.
	session._facts_armed = true
	var prior: Array = answers(session)
	check("event boundary starts with every fact cached", memo_populated(session) and prior.slice(8, 11) == [true, false, 3])
	var event_seen := {}
	session.sim.events_located.connect(func(_tick: int, _events: Array[Dictionary]) -> void:
		event_seen.empty_before = memo_empty(session)
		prop["battery"] = batteries.pack.duplicate(true)
		event_seen.fresh = [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		event_seen.empty_after = memo_empty(session))
	var events: Array[Dictionary] = [{type = "test"}]
	session.sim.events_located.emit(session.sim.tick, events)
	check("located-event observer sees fresh data before stepped", event_seen.get("empty_before", false)
		and event_seen.get("fresh") == [true, true, 11] and event_seen.get("empty_after", false), str(event_seen))
	prop["battery"] = saved.duplicate(true)

	# Drive a genuine rejected tick. The pause signal precedes faulted, and its observer can edit configuration.
	session.sim.set_paused(false)
	var fault_seen := {faulted_emitted = false}
	session.sim.faulted.connect(func(_reason: String) -> void: fault_seen.faulted_emitted = true)
	session.sim.paused_changed.connect(func(paused: bool) -> void:
		if not paused: return
		fault_seen.paused_seen = true
		fault_seen.faulted_before_pause = fault_seen.faulted_emitted
		fault_seen.reason = session.sim.fault_reason
		fault_seen.empty_before = memo_empty(session)
		prop["battery"] = batteries.pack_two.duplicate(true)
		fault_seen.fresh = [session.battery_is_dynamic(), session.battery_is_pack(), session._battery_block_size()]
		fault_seen.empty_after = memo_empty(session))
	var seeded := {}
	var kernel_pre_tick: Callable = session.sim.model.pre_tick
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = kernel_pre_tick.call(aux, inputs, dt)
		var previous: Array = answers(session)
		seeded.all_facts = memo_populated(session)
		seeded.battery = previous.slice(8, 11)
		return out
	session._weather_pending_reset = true
	session.sim.step()
	check("fault pause observer sees fresh data before faulted", seeded.get("all_facts", false)
		and seeded.get("battery") == [true, false, 3] and fault_seen.get("paused_seen", false)
		and not fault_seen.get("faulted_before_pause", true) and not str(fault_seen.get("reason", "")).is_empty()
		and fault_seen.get("empty_before", false) and fault_seen.get("fresh") == [true, true, 13]
		and fault_seen.get("empty_after", false) and fault_seen.get("faulted_emitted", false)
		and memo_empty(session), str({seeded = seeded, fault = fault_seen}))
	prop["battery"] = saved
	session.free()


func run_all() -> void:
	var batteries := battery_definitions()
	if batteries.is_empty():
		print("Session tick facts: %d checks, %d failed" % [checks, failures])
		quit(1)
		return
	var session := flight("p51d-mustang-120")
	check("kernel pre_tick arms the memo", session.sim.model.pre_tick == Callable(session, "_kernel_pre_step"))
	var outside := answers(session)
	check("P-51 exercises every memoized branch", outside.slice(1, 4) == [true, true, true] and outside[4] > 0 \
		and outside[5] > 0 and outside[6] >= 0, str(outside))
	check("memo starts empty", memo_empty(session))

	var inside := {}
	var kernel_pre_tick: Callable = session.sim.model.pre_tick
	session.sim.model.pre_tick = func(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
		var out: PackedFloat64Array = kernel_pre_tick.call(aux, inputs, dt)
		inside.armed = session._facts_armed
		inside.retractable = session._fact_gear_retractable
		inside.answers = answers(session)
		return out
	var tick: int = session.sim.tick
	session.sim.step()
	check("accepted tick advances", session.sim.tick == tick + 1 and session.sim.fault_reason.is_empty(), session.sim.fault_reason)
	check("memo is armed inside the tick", inside.get("armed", false) and inside.get("retractable") == 1, str(inside))
	check("memoized answers equal the direct answers", inside.get("answers") == outside, str(inside.get("answers")))
	check("accepted tick drops the memo", memo_empty(session))

	# Data edited in place between ticks is read afresh.
	session.aircraft.model.capabilities.flaps = "not_simulated"
	check("in-place edit after a tick is visible", not session.flaps_available())
	session.aircraft.model.capabilities.flaps = "simulated"
	check("restored edit is visible", session.flaps_available())

	session._pre_step(session.sim.aux, session.sim.inputs, session.sim.dt())
	check("a direct _pre_step call never arms the memo", memo_empty(session))

	inside.clear()
	session._weather_pending_reset = true # _pre_step refuses the tick
	session.sim.step()
	check("rejected tick faults", not session.sim.fault_reason.is_empty())
	check("memo was armed in the rejected tick", inside.get("armed", false), str(inside))
	check("rejected tick drops the memo", memo_empty(session))
	session.free()

	# A stale memo left by an interrupted tick cannot survive a reload (the commit and the kernel reset both drop it).
	var glow := flight("jensen-das-ugly-stik-60")
	glow._facts_armed = true
	glow._fact_glow = 0
	glow.setup(str(Catalog.entry("stik-glow-61fx-2t").data), "stik-glow-61fx-2t")
	check("a reload drops a stale memo", memo_empty(glow) and glow.glow_is_active())
	# Battery-shaped metadata cannot make a combustion engine an electric source.
	glow.aircraft.model.propulsion["battery"] = batteries.pack.duplicate(true)
	check("combustion source ignores battery metadata", not glow.battery_is_dynamic() and not glow.battery_is_pack()
		and glow._battery_block_size() == 0 and memo_empty(glow))
	glow.free()
	var invalid: Node = Flight.new()
	check("invalid aircraft short-circuits both direct battery predicates", not invalid.battery_is_dynamic()
		and not invalid.battery_is_pack() and invalid._battery_block_size() == 0 and memo_empty(invalid))
	invalid._facts_armed = true
	check("invalid aircraft caches false without accessing a missing model", not invalid.battery_is_dynamic()
		and not invalid.battery_is_pack() and invalid._battery_block_size() == 0 and invalid._fact_battery_dynamic == 0
		and invalid._fact_battery_pack == 0 and invalid._fact_battery_block_size == 0)
	invalid._drop_tick_facts()
	check("invalid-aircraft cached answers clear with the tick", memo_empty(invalid))
	invalid.free()
	battery_case("ideal battery", IDEAL, [false, false, 0], batteries)
	battery_case("OCV battery", OCV, [true, false, 3], batteries)
	battery_case("ECM pack", PACK, [true, true, 11], batteries)
	signal_boundary_cases(batteries)

	print("Session tick facts: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
