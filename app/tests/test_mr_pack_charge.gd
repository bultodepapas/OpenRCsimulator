# DR-21/05 (FPV audit 2026-11-16, A06): the damped bridge's regeneration is bounded by the pack's charge acceptance.
# A full pack accepts no charge (the audit's research air-start witness no longer overcharges), a nearly full pack
# approaches its capacity without crossing it, regeneration below full still charges, the stage energy balance closes
# (chemical power = terminal + loss, including the dissipation the limit adds) and an over-capacity frame is outside
# the law's domain. Software checks on estimated data: no ESC braking or LiPo charge-acceptance validation.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_full_pack_air_start()
	_near_full_braking()
	_regeneration_below_full()
	_domain()
	print("pack charge acceptance: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _session(soc: float) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare({}, {start = "air", altitude_m = 20.0, initial_soc = soc}):
		_check("air start at SOC %.3f prepares" % soc, false, str(s.load_error))
		s.free()
		return null
	s.resume()
	return s


func _capacity(s: Node) -> float:
	return 3600.0 * float(s.plant.prepared.battery.capacity_ah)


## Arm at zero throttle (an OFF tick, then ON), then hold `ticks` zero-throttle ticks: the spinning-down shafts brake.
func _brake(s: Node, ticks: int, watch: Callable) -> bool:
	var pilot: PackedFloat64Array = FC.neutral_input()
	var ok: bool = s.tick_once(pilot)
	pilot[FC.IN_ARM] = 1.0
	for i in ticks:
		ok = ok and s.tick_once(pilot)
		watch.call()
	return ok


## The audit's witness: full pack, shafts at the air-start speed, zero-throttle ON tick.
func _full_pack_air_start() -> void:
	var s := _session(1.0)
	if s == null:
		return
	var capacity := _capacity(s)
	var peak := [s.sim.continuous[Plant.C_CHARGE]]
	var watch := func() -> void: peak[0] = maxf(peak[0], s.sim.continuous[Plant.C_CHARGE])
	var ok := _brake(s, 240, watch)
	var t: Dictionary = s.plant.telemetry(s.frame())
	_check("audit A06: a full pack braking from the air start never exceeds its capacity", ok and peak[0] <= capacity,
		"peak %.9f C, capacity %.9f C" % [peak[0], capacity])
	_check("the armed flight keeps running (no fault) and consumed charge is never negative", s.fault_reason.is_empty()
		and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED and float(t.consumed_mah) >= 0.0, "%.9f mAh" % float(t.consumed_mah))
	s.free()


## Nearly full: the charge rises towards the capacity, monotonically bounded by it.
func _near_full_braking() -> void:
	var s := _session(0.99995)
	if s == null:
		return
	var capacity := _capacity(s)
	var start: float = s.sim.continuous[Plant.C_CHARGE]
	var peak := [start]
	var limited := [false]
	var watch := func() -> void:
		peak[0] = maxf(peak[0], s.sim.continuous[Plant.C_CHARGE])
		var bus: Dictionary = s.plant._evaluate(s.sim.state.slice(0, 13), s.sim.continuous, 0.0, s.sim.aux, s.sim.modes).bus
		limited[0] = limited[0] or bool(bus.get("acceptance_limited", false))
	var ok := _brake(s, 480, watch)
	_check("a nearly full pack takes regenerative charge but stays at or below its capacity", ok and peak[0] > start
		and peak[0] <= capacity and limited[0], "%.9f -> %.9f C (capacity %.9f), limited %s" % [start, peak[0], capacity, limited[0]])
	s.free()


## Below full, regeneration is unchanged: the pack charges by more than the acceptance window would ever allow near full.
func _regeneration_below_full() -> void:
	var s := _session(0.5)
	if s == null:
		return
	var start: float = s.sim.continuous[Plant.C_CHARGE]
	var peak := [start]
	var watch := func() -> void: peak[0] = maxf(peak[0], s.sim.continuous[Plant.C_CHARGE])
	_brake(s, 60, watch)
	_check("at half charge the braking shafts still charge the pack", peak[0] > start, "%.9f -> %.9f C" % [start, peak[0]])
	# Stage energy balance at a regenerating, an acceptance-limited and a driving point: Voc*I = V*I + loss.
	var plant: RefCounted = s.plant
	var duty := PackedFloat64Array([0.1, 0.1, 0.1, 0.1])
	var emf := PackedFloat64Array([5.0, 5.0, 5.0, 5.0])
	var enabled := PackedInt64Array([1, 1, 1, 1])
	var capacity := _capacity(s)
	for case: Array in [["regenerating, half charge", 0.5 * capacity, emf], ["acceptance-limited, nearly full", capacity - 0.01, emf],
			["driving", 0.5 * capacity, PackedFloat64Array([0.5, 0.5, 0.5, 0.5])]]:
		var bus: Dictionary = plant._bus(24.0, duty, case[2], enabled, true, case[1])
		var chemical: float = 24.0 * float(bus.i_pack)
		_check("energy balance, %s: open-circuit power = terminal + pack loss" % case[0], bus.ok
			and absf(chemical - float(bus.p_terminal_w) - float(bus.p_pack_loss_w)) < 1.0e-9 * maxf(1.0, absf(chemical))
			and float(bus.p_pack_loss_w) >= 0.0, "%s A, %s W" % [bus.i_pack, bus.p_pack_loss_w])
	var full: Dictionary = plant._bus(24.0, duty, emf, enabled, true, capacity)
	_check("a full pack takes no charging current; the bus floats above the open-circuit voltage", full.ok
		and float(full.i_pack) >= -1.0e-12 and float(full.v_bus) > 24.0, "%s A at %s V" % [full.i_pack, full.v_bus])
	s.free()


func _domain() -> void:
	var s := _session(1.0)
	if s == null:
		return
	var frame: Dictionary = s.frame()
	frame.continuous[Plant.C_CHARGE] = _capacity(s) + 0.01
	_check("an over-capacity frame is outside the law's domain", not s.plant.state_validator(frame, {}))
	s.free()
