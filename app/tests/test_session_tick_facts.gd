# NK-2a: FlightSession memoizes capability/layout answers for one kernel tick. Only the kernel's pre_tick arms the
# memo; the accepted or rejected tick drops it, so aircraft data replaced or edited between ticks is read afresh.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
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
		session._rotor_index()]


func memo_empty(session: Node) -> bool:
	return not session._facts_armed and [session._fact_glow, session._fact_gear_retractable, session._fact_wheel_brake,
		session._fact_flaps, session._fact_wheel_count, session._fact_anchor_count, session._fact_downwash_index,
		session._fact_rotor_index].all(func(value: int) -> bool: return value == Flight._FACT_UNKNOWN)


func flight(id: String) -> Node:
	var session: Node = Flight.new()
	session.setup(str(Catalog.entry(id).data), id)
	check(id + " is flyable", session.is_flyable(), str(session.pause_reason))
	return session


func run_all() -> void:
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
	glow.free()

	print("Session tick facts: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
