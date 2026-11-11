# DR-05 (foundation slice): four one-quadrant loads on one battery bus, FPV/03 §5 and FPV/05 PHY-05…08. Known
# answers: the computed four-load oracle and its one-load contrast; mixed drive/coast, disabled, zero-duty, unequal
# loads and zero pack resistance against an independent bisection of the scalar bus equation; the threshold
# equality convention; one bus voltage for every load; stage power identities on 1000 seeded cases; refusals;
# determinism; the one-load case against physics/electric_supply.gd. Invented parameters, no battery identification.
extends SceneTree

const Bus := preload("res://physics/multirotor/electric_bus.gd")
const Supply := preload("res://physics/electric_supply.gd")
const Motor := preload("res://physics/electric_motor.gd")
const LP := preload("res://tests/law_properties.gd")

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
	_oracle()
	_cases()
	_threshold()
	_random_identities()
	_refusals()
	_determinism()
	_supply_cross_check()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _f4(a: float, b: float, c: float, d: float) -> PackedFloat64Array:
	return PackedFloat64Array([a, b, c, d])


func _close(value: float, expected: float, tolerance: float) -> bool:
	return absf(value - expected) <= tolerance


## Independent oracle: bisection of the scalar, strictly increasing F(V) = V − Voc + Rp·(Iaux + Σ d·max(0, (d·V − E)/R))
## over [0, Voc]. Shares no code or active-set logic with the bus.
func _bisect(voc: float, rp: float, aux: float, d: PackedFloat64Array, e: PackedFloat64Array, r: PackedFloat64Array,
		on: PackedInt64Array) -> float:
	var lo := 0.0
	var hi := voc
	for _k in 200:
		var mid: float = 0.5 * (lo + hi)
		var pack := aux
		for i in 4:
			if on[i] == 1 and d[i] > 0.0:
				pack += d[i] * maxf(0.0, (d[i] * mid - e[i]) / r[i])
		if mid - voc + rp * pack > 0.0:
			hi = mid
		else:
			lo = mid
	return 0.5 * (lo + hi)


## Identities that must hold for any solved stage; returns the worst relative residual.
func _identity_residual(s: Dictionary, aux: float) -> float:
	var worst := 0.0
	var scale_p: float = maxf(1.0, absf(float(s.p_ocv_w)))
	worst = maxf(worst, absf(float(s.p_ocv_w) - float(s.p_terminal_w) - float(s.p_pack_loss_w)) / scale_p)
	var bridges := 0.0
	for i in 4:
		bridges += float(s.p_bridge_w[i])
		var scale_b: float = maxf(1.0, absf(float(s.p_bridge_w[i])))
		worst = maxf(worst, absf(float(s.p_bridge_w[i]) - float(s.p_em_w[i]) - float(s.p_copper_w[i])) / scale_b)
	worst = maxf(worst, absf(float(s.p_terminal_w) - float(s.v_bus) * aux - bridges) / maxf(1.0, absf(float(s.p_terminal_w))))
	return worst


func _oracle() -> void:
	var on := PackedInt64Array([1, 1, 1, 1])
	var s: Dictionary = Bus.solve(24.0, 0.05, 0.2, _f4(0.5, 0.5, 0.5, 0.5), _f4(8.0, 8.0, 8.0, 8.0), _f4(0.1, 0.1, 0.1, 0.1), on)
	_check("four-load oracle solves with every load active", s.ok and s.active == on, str(s.get("message", "")))
	var currents_ok := true
	var bridge_ok := true
	for i in 4:
		currents_ok = currents_ok and _close(s.i_motor[i], 26.6333333333333333, 1e-9)
		bridge_ok = bridge_ok and _close(s.p_bridge_w[i], 284.0001111111111, 1e-6) and _close(s.p_em_w[i], 213.0666666666667, 1e-6) \
			and _close(s.p_copper_w[i], 70.93344444444444, 1e-6)
	_check("Vbus = 21.3266666667 V, each I = 26.6333333333 A, Ipack = 53.4666666667 A (1e-9)",
		_close(s.v_bus, 21.3266666666666667, 1e-9) and currents_ok and _close(s.i_pack, 53.4666666666666667, 1e-9),
		"V %.10f I %.10f Ipack %.10f" % [s.v_bus, s.i_motor[0], s.i_pack])
	# The oracle's powers are quoted to 7 decimals; compare their exact rational values to 1e-9.
	_check("pack powers: OCV 1283.2 W, I²R 142.9342222 W, terminal 1140.2657778 W, aux 4.2653333 W (1e-9 of exact)",
		_close(s.p_ocv_w, 1283.2, 1e-9) and _close(s.p_pack_loss_w, 142.93422222222222, 1e-9)
		and _close(s.p_terminal_w, 1140.2657777777778, 1e-9) and _close(s.v_bus * 0.2, 4.2653333333333333, 1e-9),
		"ocv %.9f loss %.9f terminal %.9f" % [s.p_ocv_w, s.p_pack_loss_w, s.p_terminal_w])
	_check("per-bridge: 284.0001111 W = 213.0666667 W EM + 70.9334444 W copper", bridge_ok,
		"bridge %.9f em %.9f copper %.9f" % [s.p_bridge_w[0], s.p_em_w[0], s.p_copper_w[0]])
	var one: Dictionary = Bus.solve(24.0, 0.05, 0.2, _f4(0.5, 0.5, 0.5, 0.5), _f4(8.0, 8.0, 8.0, 8.0), _f4(0.1, 0.1, 0.1, 0.1),
		PackedInt64Array([1, 0, 0, 0]))
	_check("one load on the same pack: Vbus = 23.1022222222 V (1e-9), so four one-load solves would be wrong",
		one.ok and _close(one.v_bus, 23.1022222222222222, 1e-9) and absf(one.v_bus - s.v_bus) > 1.0, "%.10f" % one.v_bus)


func _expect_bisection(label: String, voc: float, rp: float, aux: float, d: PackedFloat64Array, e: PackedFloat64Array,
		r: PackedFloat64Array, on: PackedInt64Array, active: PackedInt64Array) -> Dictionary:
	var s: Dictionary = Bus.solve(voc, rp, aux, d, e, r, on)
	var v: float = _bisect(voc, rp, aux, d, e, r, on)
	var ok: bool = s.ok and s.active == active and absf(s.v_bus - v) <= 1e-9 * voc
	var same_bus := true
	if ok:
		for i in 4:
			if active[i] == 1:
				# Every active load sees the one returned bus: R·I + E = d·Vbus.
				same_bus = same_bus and absf(r[i] * s.i_motor[i] + e[i] - d[i] * s.v_bus) <= 1e-12 * voc
			else:
				same_bus = same_bus and s.i_motor[i] == 0.0 and (on[i] == 0 or d[i] == 0.0 or d[i] * s.v_bus <= e[i])
		ok = ok and same_bus and _identity_residual(s, aux) < 1e-12
	_check(label, ok, "V %.10f bisection %.10f active %s" % [float(s.get("v_bus", NAN)), v, str(s.get("active", ""))])
	return s


func _cases() -> void:
	var r := _f4(0.1, 0.1, 0.1, 0.1)
	_expect_bisection("mixed drive/coast: two loads overrun (E > d·Vbus) carry zero current, same bus as bisection",
		24.0, 0.05, 0.2, _f4(0.5, 0.6, 0.5, 0.6), _f4(8.0, 16.0, 7.0, 15.0), r, PackedInt64Array([1, 1, 1, 1]),
		PackedInt64Array([1, 0, 1, 0]))
	_expect_bisection("a disabled motor with nonzero duty draws nothing; the pack keeps auxiliary current",
		24.0, 0.05, 0.2, _f4(0.5, 0.5, 0.5, 0.5), _f4(8.0, 8.0, 8.0, 8.0), r, PackedInt64Array([1, 1, 0, 1]),
		PackedInt64Array([1, 1, 0, 1]))
	var idle: Dictionary = _expect_bisection("zero duty on every load: bus = Voc − Rp·Iaux, only auxiliary current",
		24.0, 0.05, 0.2, _f4(0.0, 0.0, 0.0, 0.0), _f4(0.0, 0.0, 0.0, 0.0), r, PackedInt64Array([1, 1, 1, 1]),
		PackedInt64Array([0, 0, 0, 0]))
	_check("zero duty: Vbus exactly 23.99 V and Ipack exactly Iaux", idle.ok and idle.v_bus == 24.0 - 0.05 * 0.2 and idle.i_pack == 0.2)
	_expect_bisection("unequal resistance and back-EMF on all four loads",
		16.8, 0.03, 0.5, _f4(0.7, 0.45, 0.9, 0.3), _f4(6.0, 3.5, 11.0, 1.0), _f4(0.05, 0.12, 0.08, 0.2),
		PackedInt64Array([1, 1, 1, 1]), PackedInt64Array([1, 1, 1, 1]))
	var stiff: Dictionary = _expect_bisection("zero pack resistance: the bus stays at Voc whatever the load",
		25.2, 0.0, 1.0, _f4(0.8, 0.6, 0.4, 0.2), _f4(5.0, 4.0, 3.0, 2.0), _f4(0.1, 0.07, 0.09, 0.11),
		PackedInt64Array([1, 1, 1, 1]), PackedInt64Array([1, 1, 1, 1]))
	_check("zero pack resistance: Vbus == Voc exactly and no pack loss", stiff.ok and stiff.v_bus == 25.2 and stiff.p_pack_loss_w == 0.0)


## The equality convention: a load with d·Vbus exactly equal to E is inactive with zero current, and a load just
## beyond the threshold changes the bus continuously.
func _threshold() -> void:
	var d := _f4(0.5, 0.5, 0.5, 0.8)
	var r := _f4(0.1, 0.1, 0.1, 0.1)
	var e := _f4(8.0, 8.0, 8.0, 0.0)
	var three: Dictionary = Bus.solve(24.0, 0.05, 0.2, d, e, r, PackedInt64Array([1, 1, 1, 0]))
	e[3] = d[3] * float(three.v_bus) # exactly at threshold on the three-load bus
	var at: Dictionary = Bus.solve(24.0, 0.05, 0.2, d, e, r, PackedInt64Array([1, 1, 1, 1]))
	_check("a load exactly at threshold (d·Vbus == E) is inactive with exactly zero current, same bus as without it",
		at.ok and at.active == PackedInt64Array([1, 1, 1, 0]) and at.i_motor[3] == 0.0 and at.v_bus == three.v_bus,
		"E %.15f V %.15f" % [e[3], float(at.get("v_bus", NAN))])
	var below_e := e.duplicate()
	below_e[3] -= 1e-9
	var above_e := e.duplicate()
	above_e[3] += 1e-9
	var drives: Dictionary = Bus.solve(24.0, 0.05, 0.2, d, below_e, r, PackedInt64Array([1, 1, 1, 1]))
	var coasts: Dictionary = Bus.solve(24.0, 0.05, 0.2, d, above_e, r, PackedInt64Array([1, 1, 1, 1]))
	_check("1 nV either side of the threshold: drive/coast switch with continuous bus (< 1e-9 V) and current (< 1e-7 A)",
		drives.ok and coasts.ok and drives.active[3] == 1 and coasts.active[3] == 0 and absf(drives.v_bus - coasts.v_bus) < 1e-9
		and drives.i_motor[3] > 0.0 and drives.i_motor[3] < 1e-7, "I %s dV %s" % [LP.sci(drives.i_motor[3]), LP.sci(drives.v_bus - coasts.v_bus)])


func _random_identities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	var worst_identity := 0.0
	var worst_bisection := 0.0
	var worst_current := 0.0
	var all_ok := true
	var mixed := 0
	for _case in 1000:
		var voc: float = rng.randf_range(7.0, 30.0)
		var rp: float = 0.0 if rng.randf() < 0.1 else rng.randf_range(0.005, 0.2)
		var aux: float = rng.randf_range(0.0, 3.0)
		var d := PackedFloat64Array()
		var e := PackedFloat64Array()
		var r := PackedFloat64Array()
		var on := PackedInt64Array()
		for _i in 4:
			d.append(0.0 if rng.randf() < 0.1 else rng.randf_range(0.0, 1.0))
			e.append(rng.randf_range(0.0, 0.9 * voc))
			r.append(rng.randf_range(0.02, 0.5))
			on.append(0 if rng.randf() < 0.1 else 1)
		var s: Dictionary = Bus.solve(voc, rp, aux, d, e, r, on)
		if not s.ok:
			all_ok = false
			continue
		worst_identity = maxf(worst_identity, _identity_residual(s, aux))
		worst_bisection = maxf(worst_bisection, absf(s.v_bus - _bisect(voc, rp, aux, d, e, r, on)) / voc)
		var count := 0
		for i in 4:
			count += s.active[i]
			if s.active[i] == 1:
				worst_current = maxf(worst_current, absf(r[i] * s.i_motor[i] + e[i] - d[i] * s.v_bus) / voc)
			elif s.i_motor[i] != 0.0 or (on[i] == 1 and d[i] > 0.0 and d[i] * s.v_bus > e[i]):
				worst_current = INF
		mixed += 1 if count > 0 and count < 4 else 0
	_check("1000 seeded stages solve", all_ok)
	_check("power identities p_ocv = p_terminal + p_loss, p_terminal = Vbus·Iaux + Σ p_bridge, p_bridge = p_em + p_copper (1e-9 rel)",
		worst_identity < 1e-9, LP.sci(worst_identity))
	_check("bus voltage equals the independent bisection (1e-9 of Voc)", worst_bisection < 1e-9, LP.sci(worst_bisection))
	_check("every load sees the same bus; inactive loads are not driving (1e-12 of Voc)", worst_current < 1e-12,
		"%s, %d mixed drive/coast stages" % [LP.sci(worst_current), mixed])


func _refusals() -> void:
	var d := _f4(0.5, 0.5, 0.5, 0.5)
	var e := _f4(8.0, 8.0, 8.0, 8.0)
	var r := _f4(0.1, 0.1, 0.1, 0.1)
	var on := PackedInt64Array([1, 1, 1, 1])
	var cases := [
		["NaN Voc", Bus.solve(NAN, 0.05, 0.2, d, e, r, on)],
		["NaN duty", Bus.solve(24.0, 0.05, 0.2, _f4(0.5, NAN, 0.5, 0.5), e, r, on)],
		["duty > 1", Bus.solve(24.0, 0.05, 0.2, _f4(0.5, 0.5, 1.0000001, 0.5), e, r, on)],
		["negative duty", Bus.solve(24.0, 0.05, 0.2, _f4(-0.1, 0.5, 0.5, 0.5), e, r, on)],
		["negative motor resistance", Bus.solve(24.0, 0.05, 0.2, d, e, _f4(0.1, -0.1, 0.1, 0.1), on)],
		["zero motor resistance", Bus.solve(24.0, 0.05, 0.2, d, e, _f4(0.1, 0.1, 0.0, 0.1), on)],
		["negative pack resistance", Bus.solve(24.0, -0.05, 0.2, d, e, r, on)],
		["negative back-EMF", Bus.solve(24.0, 0.05, 0.2, d, _f4(8.0, 8.0, 8.0, -1.0), r, on)],
		["negative auxiliary current", Bus.solve(24.0, 0.05, -0.2, d, e, r, on)],
		["enabled flag 2", Bus.solve(24.0, 0.05, 0.2, d, e, r, PackedInt64Array([1, 2, 1, 1]))],
		["three loads", Bus.solve(24.0, 0.05, 0.2, PackedFloat64Array([0.5, 0.5, 0.5]), e, r, on)],
		["auxiliary current that collapses the bus", Bus.solve(24.0, 0.05, 480.0, d, e, r, on)],
	]
	for case: Array in cases:
		_check("refuses %s" % case[0], not case[1].ok and not str(case[1].get("message", "")).is_empty(), str(case[1].get("message", "")))


func _determinism() -> void:
	var d := _f4(0.7, 0.45, 0.9, 0.3)
	var e := _f4(6.0, 3.5, 11.0, 1.0)
	var r := _f4(0.05, 0.12, 0.08, 0.2)
	var on := PackedInt64Array([1, 1, 0, 1])
	var a: Dictionary = Bus.solve(16.8, 0.03, 0.5, d, e, r, on)
	var b: Dictionary = Bus.solve(16.8, 0.03, 0.5, d, e, r, on)
	_check("same stage twice gives identical bytes", a.ok and var_to_bytes(a) == var_to_bytes(b))


## One load on electric_supply.gd: same OCV/Rp/aux pack, motor Kv = 1000 rpm/V at 8000 rpm (E = 8 V), R = 0.1 Ω.
## The supply's closed form (d·(Voc − Rp·Iaux) − E)/(R + d²·Rp) is algebraically the bus law with one active load.
func _supply_cross_check() -> void:
	var pack := { ocv_points = PackedFloat64Array([0.0, 24.0, 1.0, 24.0]), capacity_ah = 1.5, resistance_ohm = 0.05,
		auxiliary_current_a = 0.2 }
	var worst := 0.0
	var all_ok := true
	for case: Array in [[8000.0, 0.5, 0.0], [8000.0, 0.5, 1.3], [3000.0, 0.85, 0.7], [20000.0, 0.6, 0.5], [0.0, 0.2, 0.4]]:
		var rpm: float = case[0]
		var duty: float = case[1]
		var motor := { kv_rpm_per_volt = 1000.0, resistance_ohm = 0.1, no_load_current_a = case[2] }
		var supply: Dictionary = Supply.evaluate(rpm, duty, 0.5, pack, motor, true)
		var e: float = rpm / 1000.0
		var bus: Dictionary = Bus.solve(24.0, 0.05, 0.2, _f4(duty, 0.0, 0.0, 0.0), _f4(e, 0.0, 0.0, 0.0),
			_f4(0.1, 0.1, 0.1, 0.1), PackedInt64Array([1, 0, 0, 0]))
		if not supply.ok or not bus.ok:
			all_ok = false
			continue
		var source: Dictionary = Motor.evaluate(rpm, duty, float(supply.bus_voltage_v), motor, true)
		# The motor's electromagnetic power Kt·I·ω equals E·I; its copper loss is R·I².
		var em: float = float(source.shaft_power_w) + float(source.rotational_loss_w)
		var pairs := [
			[bus.v_bus, supply.bus_voltage_v], [bus.i_motor[0], supply.motor_current_a], [bus.i_pack, supply.pack_current_a],
			[bus.p_pack_loss_w, supply.pack_loss_w], [bus.p_terminal_w, supply.pack_terminal_power_w],
			[bus.p_ocv_w, supply.pack_open_circuit_power_w], [bus.p_bridge_w[0], supply.motor_bus_power_w],
			[bus.p_copper_w[0], supply.motor_copper_loss_w], [bus.p_em_w[0], em],
		]
		for pair: Array in pairs:
			worst = maxf(worst, absf(float(pair[0]) - float(pair[1])) / maxf(1.0, absf(float(pair[1]))))
		all_ok = all_ok and (bus.active[0] == 1) == (str(supply.mode) == "drive")
	_check("one load matches electric_supply.gd + electric_motor.gd: bus, currents, pack/bridge/copper/EM powers (1e-12 rel)",
		all_ok and worst < 1e-12, LP.sci(worst))
