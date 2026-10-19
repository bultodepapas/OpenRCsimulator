# FT-04 (card v4): aerobatic and inverted tests of the standard flight-test card. Each function takes the runner
# (flight_test.gd) and returns its { valid, metrics, notes, table } result. Figure geometry and the qualities measured
# follow the FAI F3 aerobatic manoeuvre execution guide (Sporting Code Volume F3, Annex 5B, 2026): lines, loops, rolls,
# snap rolls, stall turns. The pilot is pilot.gd; its technique, not the best the airplane can do, sets heights, times
# and sizes. Model predictions, not physical validation.
extends RefCounted

const P := preload("pilot.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const DT := 1.0 / 240.0
const SLOW_ROLL_RATE := deg_to_rad(90.0) # one roll in 4 s
const POINT_ROLL_RATE := deg_to_rad(180.0)
const POINT_HOLD_S := 1.0


static func _side(side: float) -> String:
	return "right" if side > 0.0 else "left"


static func _max_beta(ft, trace: RefCounted, r0 := 0, r1 := -1) -> float:
	var beta := 0.0
	for r in range(r0, trace.row_count() if r1 < 0 else mini(r1, trace.row_count())):
		beta = maxf(beta, absf(ft._beta_deg(trace, r)))
	return beta


static func _min_load(ft, trace: RefCounted) -> float:
	var m := INF
	for r in trace.row_count():
		m = minf(m, ft._load_factor(trace, r))
	return m


## Largest |stick| the pilot itself commanded on an axis (before the radio trims) over the flight.
static func _peak_stick(ctx: Dictionary, axis: String, signed := 0.0) -> float:
	var peak := 0.0
	for x in ctx.get("raw_" + axis, PackedFloat64Array()):
		if signed == 0.0:
			peak = maxf(peak, absf(x))
		else:
			peak = maxf(peak, x * signed)
	return peak


# --- Inverted ----------------------------------------------------------------------------------------------------

## Inverted level flight at three speeds (the start speed, 0.6 and 0.8 Vmax): the elevator, angle of attack and
## throttle that inverted flight needs as the speed changes. Same pilot as `inverted`; 0.6 Vmax repeats it.
static func inverted_speeds(ft) -> Dictionary:
	var rows := []
	var notes := []
	var valid := true
	for named in [["start", float(ft.v_start)], ["0.6Vmax", 0.6 * float(ft.vmax)], ["0.8Vmax", 0.8 * float(ft.vmax)]]:
		var speed: float = named[1]
		var r: Dictionary = ft._inverted_pass("inverted_speeds", speed, PI, deg_to_rad(160.0), str(named[0]))
		if not r.ok:
			notes.append("%s: %s" % [named[0], r.message])
			valid = false
			continue
		if not r.held:
			notes.append("%s: %s" % [named[0], r.why])
		valid = valid and r.held
		var row: Dictionary = { case = named[0], speed_target_mps = snappedf(speed, 0.01) }
		row.merge(r.metrics)
		row.held = r.held
		rows.append(row)
	return ft._result(valid and rows.size() == 3, {}, notes, { table = rows })


## Inverted coordinated turn both ways: 45° of bank from inverted (roll 135°), height held through an angle of attack
## bounded by the negative stall start, speed held at the inverted-pass speed with the throttle, feet on the ball.
## Sustained speed, turn rate, radius and the negative load factor.
static func inverted_turn(ft) -> Dictionary:
	var rows := []
	var notes := []
	var speed: float = maxf(ft.v_start, 0.6 * ft.vmax)
	for side in [1.0, -1.0]:
		var r: Dictionary = ft._inverted_pass("inverted_turn", speed, side * deg_to_rad(135.0), deg_to_rad(115.0), _side(side), 20.0)
		if not r.ok:
			notes.append("%s: %s" % [_side(side), r.message])
			continue
		var trace: RefCounted = r.trace
		var r0: int = ft._row_at(trace, 12.0)
		var n: int = trace.row_count()
		var rate := absf(ft._track_rate(trace, r0, n))
		var v: float = ft._mean(ft._col(trace, "speed_mps", r0))
		var bank: float = ft._mean(ft._col(trace, "roll_deg", r0))
		var climb: float = ft._slope(trace, "alt_m", r0, n)
		var held: bool = absf(absf(bank) - 135.0) < 5.0 and absf(climb) < 1.0 and r.crashed == ""
		if not held:
			notes.append("%s: bank %.1f°, vertical speed %.2f m/s %s" % [_side(side), bank, climb, r.crashed])
		rows.append({ case = _side(side), direction = _side(side), sustained_speed_mps = snappedf(v, 0.01), turn_rate_dps = snappedf(rate, 0.1),
			radius_m = snappedf(v / deg_to_rad(rate), 0.1) if rate > 0.0 else NAN, bank_deg = snappedf(bank, 0.1), vertical_speed_mps = snappedf(climb, 0.01),
			load_factor_g = snappedf(ft._mean(PackedFloat64Array(range(r0, n).map(func(i): return ft._load_factor(trace, i)))), 0.01),
			elevator_stick = snappedf(ft._mean(ft._col(trace, "cmd_pitch", r0)), 0.001), throttle = snappedf(ft._mean(ft._col(trace, "cmd_throttle", r0)), 0.001),
			alpha_deg = snappedf(ft._mean(PackedFloat64Array(range(r0, n).map(func(i): return ft._alpha_deg(trace, i)))), 0.1), held = held })
	return ft._result(rows.size() == 2 and rows.all(func(x): return x.held), {}, notes, { table = rows })


# --- Loops and part loops ----------------------------------------------------------------------------------------

## Immelmann turn: from 0.8 Vmax at full throttle a half loop (α held 2° below the stall start, roll rate stopped, feet
## off), then at the top a half roll with full right aileron while the nose holds the new line, then level flight.
## FAI: the roll starts as the half loop ends. Height gained, speed over the top and at the exit, heading reversal.
static func immelmann(ft) -> Dictionary:
	var entry: float = maxf(ft.v_start, 0.8 * ft.vmax)
	var target: float = ft.a1 - deg_to_rad(2.0)
	var flight: Dictionary = ft._fly("immelmann", { speed = entry, altitude = ft.HIGH }, 20.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, ft.v_start)
		if not ctx.has("top_t"):
			ctx.turned = float(ctx.get("turned", 0.0)) + s[RB.RATE + 1] * DT
			if float(ctx.turned) < PI:
				return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, target, k, ctx, DT), throttle = 1.0 }
			ctx.top_t = t
			ctx.top_v = P.speed(s)
			ctx.top_heading = P.track(s)
		if not ctx.has("rolled_t"):
			ctx.rolled = float(ctx.get("rolled", 0.0)) + s[RB.RATE] * DT
			if float(ctx.rolled) < PI - deg_to_rad(10.0):
				var line := P.point_nose(s, P.direction(float(ctx.top_heading), 0.0), k)
				return { roll = 1.0, pitch = line[0], yaw = line[1], throttle = 1.0 }
			ctx.rolled_t = t
			ctx.exit_alt = P.altitude(s)
		return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, float(ctx.exit_alt), k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 1.0 }, \
		func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
			return ctx.has("rolled_t") and t > float(ctx.rolled_t) + 3.0)
	if not flight.ok:
		return ft._failed(flight)
	var trace: RefCounted = flight.trace
	var ctx: Dictionary = flight.ctx
	var n: int = trace.row_count()
	var notes := []
	if not ctx.has("top_t"):
		notes.append("half loop not completed in 20 s")
	elif not ctx.has("rolled_t"):
		notes.append("half roll not completed")
	if flight.crashed != "":
		notes.append(flight.crashed)
	var exit_bank: float = trace.value(n - 1, "roll_deg")
	var done: bool = ctx.has("rolled_t") and flight.crashed == "" and not ctx.has("floor_t")
	if done and absf(exit_bank) >= 15.0:
		notes.append("exit bank %.1f°" % exit_bank)
	var alt0: float = trace.value(0, "alt_m")
	return ft._result(done and absf(exit_bank) < 15.0, { entry_speed_mps = snappedf(entry, 0.01), alpha_target_deg = snappedf(rad_to_deg(target), 0.1),
		top_speed_mps = snappedf(float(ctx.get("top_v", NAN)), 0.01), top_speed_vs = snappedf(float(ctx.get("top_v", NAN)) / ft.vs, 0.01),
		half_loop_time_s = snappedf(float(ctx.get("top_t", NAN)), 0.01), half_roll_time_s = snappedf(float(ctx.get("rolled_t", NAN)) - float(ctx.get("top_t", NAN)), 0.01),
		height_gain_m = snappedf(float(ctx.get("exit_alt", NAN)) - alt0, 0.1), exit_speed_mps = snappedf(trace.value(n - 1, "speed_mps"), 0.01),
		heading_error_deg = snappedf(wrapf(trace.value(n - 1, "yaw_deg") - trace.value(0, "yaw_deg") - 180.0, -180.0, 180.0), 0.1),
		exit_bank_deg = snappedf(exit_bank, 0.1), max_load_factor_g = snappedf(ft._max_load(trace), 0.01), max_sideslip_deg = snappedf(_max_beta(ft, trace), 0.1) }, notes)


## Split-S: from the start speed with the throttle closed, a half roll with full right aileron to inverted while the
## nose holds the line, then a half loop down (α held 2° below the stall start, roll rate stopped) to level flight.
## The height it takes, the exit speed and the load factor.
static func split_s(ft) -> Dictionary:
	var entry: float = ft.v_start
	var target: float = ft.a1 - deg_to_rad(2.0)
	var flight: Dictionary = ft._fly("split_s", { speed = entry, altitude = ft.HIGH }, 20.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, ft.v_start)
		if not ctx.has("heading0"):
			ctx.heading0 = P.track(s)
		if t < 0.25:
			return { roll = P.bank(s, 0.0, k), throttle = 0.0 }
		if not ctx.has("inverted_t"):
			ctx.rolled = float(ctx.get("rolled", 0.0)) + s[RB.RATE] * DT
			var line := P.point_nose(s, P.direction(float(ctx.heading0), 0.0), k)
			if float(ctx.rolled) < PI - deg_to_rad(10.0):
				return { roll = 1.0, pitch = line[0], yaw = line[1], throttle = 0.0 }
			ctx.inverted_t = t
		if t < float(ctx.inverted_t) + 0.3:
			var line := P.point_nose(s, P.direction(float(ctx.heading0), 0.0), k)
			return { roll = P.bank_pi(s, PI, k, ctx, DT), pitch = line[0], yaw = line[1], throttle = 0.0 }
		if not ctx.has("level_t"):
			ctx.turned = float(ctx.get("turned", 0.0)) + s[RB.RATE + 1] * DT
			if not (float(ctx.turned) > PI / 2.0 and P.nose_elevation(s) >= 0.0):
				return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, target, k, ctx, DT), throttle = 0.0 }
			ctx.level_t = t
			ctx.level_v = P.speed(s)
			ctx.level_alt = P.altitude(s)
		return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, float(ctx.level_alt), k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = ctx.start_throttle }, \
		func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
			return ctx.has("level_t") and t > float(ctx.level_t) + 2.0)
	if not flight.ok:
		return ft._failed(flight)
	var trace: RefCounted = flight.trace
	var ctx: Dictionary = flight.ctx
	var n: int = trace.row_count()
	var notes := []
	if not ctx.has("level_t"):
		notes.append("not back to level flight in 20 s")
	if flight.crashed != "":
		notes.append(flight.crashed)
	var exit_bank: float = trace.value(n - 1, "roll_deg")
	var done: bool = ctx.has("level_t") and flight.crashed == "" and not ctx.has("floor_t")
	var alt0: float = trace.value(0, "alt_m")
	return ft._result(done and absf(exit_bank) < 15.0, { entry_speed_mps = snappedf(entry, 0.01), alpha_target_deg = snappedf(rad_to_deg(target), 0.1),
		half_roll_time_s = snappedf(float(ctx.get("inverted_t", NAN)) - 0.25, 0.01), time_to_level_s = snappedf(float(ctx.get("level_t", NAN)), 0.01),
		height_lost_m = snappedf(alt0 - ft._min(ft._col(trace, "alt_m")), 0.1), height_lost_to_level_m = snappedf(alt0 - float(ctx.get("level_alt", NAN)), 0.1),
		exit_speed_mps = snappedf(float(ctx.get("level_v", NAN)), 0.01), max_speed_mps = snappedf(ft._max(ft._col(trace, "speed_mps")), 0.01),
		max_load_factor_g = snappedf(ft._max_load(trace), 0.01), heading_error_deg = snappedf(wrapf(trace.value(n - 1, "yaw_deg") - trace.value(0, "yaw_deg") - 180.0, -180.0, 180.0), 0.1),
		exit_bank_deg = snappedf(exit_bank, 0.1), max_sideslip_deg = snappedf(_max_beta(ft, trace), 0.1) }, notes)


## Outside (pushed) loop from upright: from 0.6 Vmax at 300 m, α held 2° inside the negative stall start, roll rate
## stopped, feet off; throttle closed on the way down (the first half), full on the way up. Depth, time, minimum speed,
## the negative load factor, sideslip and heading change.
static func outside_loop(ft) -> Dictionary:
	var entry: float = maxf(ft.v_start, 0.6 * ft.vmax)
	var target: float = -(ft.n1 - deg_to_rad(2.0))
	var flight: Dictionary = ft._fly("outside_loop", { speed = entry, altitude = 300.0 }, 25.0, func(_t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		ctx.turned = float(ctx.get("turned", 0.0)) + s[RB.RATE + 1] * DT
		var k := P.schedule(s, ft.v_start)
		return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, target, k, ctx, DT), throttle = 0.0 if float(ctx.turned) > -PI else 1.0 }, \
		func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if float(ctx.get("turned", 0.0)) <= -TAU:
				ctx.closed_t = t
				return true
			return false)
	if not flight.ok:
		return ft._failed(flight)
	var trace: RefCounted = flight.trace
	var n: int = trace.row_count()
	var beta := _max_beta(ft, trace)
	var closed: bool = flight.ctx.has("closed_t")
	var notes := []
	if not closed:
		notes.append("loop not closed in 25 s")
	if beta >= 10.0:
		notes.append("sideslip above 10°: rolling departure, not a clean loop")
	if flight.crashed != "":
		notes.append(flight.crashed)
	return ft._result(closed and flight.crashed == "" and beta < 10.0, { entry_speed_mps = snappedf(entry, 0.01), alpha_target_deg = snappedf(rad_to_deg(target), 0.1),
		loop_time_s = snappedf(float(flight.ctx.get("closed_t", NAN)), 0.01), loop_depth_m = snappedf(trace.value(0, "alt_m") - ft._min(ft._col(trace, "alt_m")), 0.1),
		min_speed_mps = snappedf(ft._min(ft._col(trace, "speed_mps")), 0.01), max_speed_mps = snappedf(ft._max(ft._col(trace, "speed_mps")), 0.01),
		min_load_factor_g = snappedf(_min_load(ft, trace), 0.01), max_sideslip_deg = snappedf(beta, 0.1),
		heading_change_deg = snappedf(wrapf(trace.value(n - 1, "yaw_deg") - trace.value(0, "yaw_deg"), -180.0, 180.0), 0.1),
		height_change_m = snappedf(trace.value(n - 1, "alt_m") - trace.value(0, "alt_m"), 0.1) }, notes)


# --- Rolls -------------------------------------------------------------------------------------------------------

## What a level line needs at each bank, from this run's knife-edge (100 % throttle, both ways) and inverted (0.8 Vmax)
## results: top rudder, the aileron against the knife-edge rolling moment and the nose elevation in knife-edge, push and
## nose elevation inverted. A competent pilot puts them in before the airplane needs them; the line PI and the roll
## loop correct the rest. Missing results leave that term at zero.
static func _line_feedforward(ft) -> Dictionary:
	var out := { rudder_right = 0.0, rudder_left = 0.0, aileron_right = 0.0, aileron_left = 0.0, ke_elevation_right = 0.0, ke_elevation_left = 0.0,
		inverted_stick = 0.0, inverted_elevation = 0.0, notes = [] }
	var ke: Array = ft.results.get("knife_edge", {}).get("table", [])
	for side in ["right", "left"]:
		var rows := ke.filter(func(r): return str(r.get("case", "")) == side + "_100pct")
		if rows.is_empty():
			out.notes.append("no %s knife-edge result: no top-rudder feedforward that way" % side)
			continue
		out["rudder_" + side] = absf(float(rows[0].rudder_stick))
		out["aileron_" + side] = float(rows[0].aileron_stick)
		out["ke_elevation_" + side] = deg_to_rad(float(rows[0].pitch_attitude_deg))
	var inv: Array = ft.results.get("inverted_speeds", {}).get("table", []).filter(func(r): return str(r.get("case", "")) == "0.8Vmax")
	if inv.is_empty() or not inv[0].get("held", false):
		out.notes.append("no held inverted result at 0.8 Vmax: no push feedforward")
	else:
		out.inverted_stick = float(inv[0].elevator_stick)
		out.inverted_elevation = deg_to_rad(-float(inv[0].alpha_deg))
	return out


## Slow roll both ways: one roll at a constant 90°/s (FAI: constant rate and flight path) from 0.8 Vmax at full throttle,
## with the line (height and heading) held by elevator and rudder at every bank through point_nose, with the knife-edge
## and inverted feedforward (top rudder, knife-edge aileron, push). Height and heading change, roll-rate constancy, and
## the rudder and elevator it took.
static func slow_roll(ft) -> Dictionary:
	return _roll(ft, "slow_roll", false)


## Four-point roll both ways: 90° part rolls at 180°/s with a 1 s point (the bank held) after each, line held as in the
## slow roll. Over-rotation at each point (FAI "bumping the point"), height and heading change.
static func point_roll(ft) -> Dictionary:
	return _roll(ft, "point_roll", true)


static func _roll(ft, name: String, points: bool) -> Dictionary:
	var entry: float = maxf(ft.v_start, 0.8 * ft.vmax)
	var ff := _line_feedforward(ft)
	var rows := []
	var notes: Array = ff.notes.duplicate()
	var valid := true
	for side in [1.0, -1.0]:
		var flight: Dictionary = ft._fly(name, { speed = entry, altitude = ft.HIGH }, 16.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = _side(side)
			var k := P.schedule(s, ft.v_start)
			var e := P.euler(s)
			if not ctx.has("alt0"):
				ctx.alt0 = P.altitude(s)
				ctx.heading0 = e[0]
				ctx.theta_up = P.nose_elevation(s)
			var phi: float = e[2]
			var c := cos(phi)
			var sn := sin(phi)
			var right: bool = sn > 0.0
			var e_alt: float = float(ctx.alt0) - P.altitude(s)
			ctx.alt_i = clampf(float(ctx.get("alt_i", 0.0)) + e_alt * DT, -40.0, 40.0)
			var theta: float = float(ctx.theta_up) * maxf(c, 0.0) ** 2 + float(ff.inverted_elevation) * maxf(-c, 0.0) ** 2 \
				+ float(ff.ke_elevation_right if right else ff.ke_elevation_left) * sn * sn
			var wanted: float = theta + clampf(0.02 * e_alt - 0.03 * P.climb_rate(s) + 0.004 * float(ctx.alt_i), -0.3, 0.3)
			var line := P.point_nose(s, P.direction(float(ctx.heading0), wanted), k,
				PackedFloat64Array([float(ff.inverted_stick) * maxf(-c, 0.0), -sn * float(ff.rudder_right if right else ff.rudder_left)]))
			var c_out := { pitch = line[0], yaw = line[1], throttle = 1.0, roll = 0.0 }
			var aileron_ff: float = absf(sn) * float(ff.aileron_right if right else ff.aileron_left)
			if t < 0.5:
				c_out.roll = P.bank(s, 0.0, k)
				return c_out
			if ctx.has("done_t"):
				c_out.roll = P.bank_pi(s, 0.0, k, ctx, DT)
				return c_out
			ctx.rolled = float(ctx.get("rolled", 0.0)) + side * s[RB.RATE] * DT
			if not points:
				if float(ctx.rolled) >= TAU - deg_to_rad(5.0):
					ctx.done_t = t
					ctx.erase("bank_i")
				c_out.roll = clampf(P.roll_rate(s, side * SLOW_ROLL_RATE, k, ctx, DT) + aileron_ff, -1.0, 1.0) if not ctx.has("done_t") else P.bank_pi(s, 0.0, k, ctx, DT)
				return c_out
			# Four points: roll at the part-roll rate to within 10° of the next point, then hold it for the point time.
			var seg: int = int(ctx.get("seg", 0))
			var point: float = (seg + 1) * PI / 2.0
			if not ctx.has("hold_t"):
				if float(ctx.rolled) < point - deg_to_rad(10.0):
					c_out.roll = clampf(P.roll_rate(s, side * POINT_ROLL_RATE, k, ctx, DT) + aileron_ff, -1.0, 1.0)
					return c_out
				ctx.hold_t = t
				ctx.erase("bank_i")
			var target: float = wrapf(side * point, -PI, PI)
			var over: float = side * wrapf(phi - target, -PI, PI)
			var overs: Array = ctx.get("overshoot", [])
			while overs.size() <= seg:
				overs.append(-INF)
			overs[seg] = maxf(float(overs[seg]), rad_to_deg(over))
			ctx.overshoot = overs
			var holds: Array = ctx.get("hold_sticks", [])
			while holds.size() <= seg:
				holds.append([])
			if t > float(ctx.hold_t) + 0.5:
				holds[seg].append([line[0], line[1]])
			ctx.hold_sticks = holds
			c_out.roll = clampf(P.bank_pi(s, target, k, ctx, DT) + aileron_ff, -1.0, 1.0)
			if t >= float(ctx.hold_t) + POINT_HOLD_S:
				ctx.erase("hold_t")
				ctx.erase("roll_rate_i")
				ctx.seg = seg + 1
				if seg + 1 >= 4:
					ctx.done_t = t
			return c_out, \
			func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
				return ctx.has("done_t") and t > float(ctx.done_t) + 2.0)
		if not flight.ok:
			notes.append(flight.message)
			valid = false
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var n: int = trace.row_count()
		var done: bool = ctx.has("done_t")
		var r_end: int = ft._row_at(trace, float(ctx.get("done_t", trace.value(n - 1, "t_s"))))
		var r0: int = ft._row_at(trace, 0.5)
		var alt0: float = trace.value(0, "alt_m")
		var alts: PackedFloat64Array = ft._col(trace, "alt_m", r0, r_end + 1)
		var row := { case = _side(side), direction = _side(side), entry_speed_mps = snappedf(entry, 0.01),
			roll_time_s = snappedf(float(ctx.get("done_t", NAN)) - 0.5, 0.01),
			height_change_m = snappedf(trace.value(r_end, "alt_m") - alt0, 0.1),
			max_height_deviation_m = snappedf(maxf(ft._max(alts) - alt0, alt0 - ft._min(alts)), 0.1),
			heading_change_deg = snappedf(wrapf(trace.value(r_end, "yaw_deg") - trace.value(0, "yaw_deg"), -180.0, 180.0), 0.1),
			max_sideslip_deg = snappedf(_max_beta(ft, trace, r0, r_end + 1), 0.1),
			peak_rudder_stick = snappedf(_peak_stick(ctx, "yaw"), 0.001), peak_push_stick = snappedf(_peak_stick(ctx, "pitch", -1.0), 0.001),
			aileron_saturated_fraction = snappedf(ft._saturated(ctx, "roll", roundi(0.5 * 240.0), roundi(float(ctx.get("done_t", 0.0)) * 240.0)), 0.01),
			exit_bank_deg = snappedf(trace.value(n - 1, "roll_deg"), 0.1) }
		if not points:
			# Roll-rate constancy over the middle 80 % of the roll (FAI 5B.8.5 b).
			var rates := PackedFloat64Array()
			var turned := 0.0
			for r in range(r0, r_end):
				turned += side * trace.value(r, "p_radps") * (trace.value(r + 1, "t_s") - trace.value(r, "t_s"))
				if turned > 0.1 * TAU and turned < 0.9 * TAU:
					rates.append(side * trace.value(r, "p_radps"))
			var mean: float = ft._mean(rates)
			var spread := 0.0
			for x in rates:
				spread += (x - mean) ** 2
			row.mean_roll_rate_dps = snappedf(rad_to_deg(mean), 0.1)
			row.roll_rate_rms_variation = snappedf(sqrt(spread / maxf(rates.size(), 1)) / mean, 0.001) if mean > 0.0 else NAN
		else:
			var overs: Array = ctx.get("overshoot", [])
			var holds: Array = ctx.get("hold_sticks", [])
			for i in 4:
				row["over_rotation_point_%d_deg" % (i + 1)] = snappedf(float(overs[i]), 0.1) if i < overs.size() else NAN
			# Knife-edge points (1 and 3) and the inverted point (2): the sticks the line held there (pilot's own).
			for i in [0, 1, 2]:
				if i < holds.size() and not holds[i].is_empty():
					var pitch_sum := 0.0
					var yaw_sum := 0.0
					for pair in holds[i]:
						pitch_sum += pair[0]
						yaw_sum += pair[1]
					row["point_%d_elevator_stick" % (i + 1)] = snappedf(pitch_sum / holds[i].size(), 0.001)
					row["point_%d_rudder_stick" % (i + 1)] = snappedf(yaw_sum / holds[i].size(), 0.001)
		var held: bool = done and flight.crashed == "" and not ctx.has("floor_t") and absf(row.exit_bank_deg) < 15.0
		if not held:
			notes.append("%s: roll %s, exit bank %.1f° %s" % [_side(side), "done" if done else "not completed", row.exit_bank_deg, flight.crashed])
		valid = valid and held
		rows.append(row)
	return ft._result(valid and rows.size() == 2, {}, notes, { table = rows })


## Snap roll both ways (FAI 5B.8.7: a rapid auto-rotative roll with the wing stalled). From 1.6 Vs at the level-trim
## throttle: full up elevator, full rudder and full aileron the same way, released early by 0.2 s of roll rate (at least
## 20°) before 360°, or as soon as the autorotation dies (roll rate below a third of its peak) or after 4 s. Then the
## sticks centred with the rudder against the yaw rate (a damper; a full opposite rudder keyed to the roll rate's sign
## sustained a Dutch-roll limit cycle on the Avanti) until roll and yaw stop, wings levelled and the dive pulled out
## with half the stall-start α while the rudder keeps damping, then height held with the ball centred. Judge's questions: did the wing stall before the roll built up (a snap, not an
## aileron roll), is there yaw in the rotation (autorotation), did the autorotation last to the finish (FAI zeroes a snap
## whose autorotation ends more than 90° short), where did the rotation stop, and the height and heading it cost.
static func snap_roll(ft) -> Dictionary:
	var rows := []
	var notes := []
	var entry: float = 1.6 * ft.vs
	for side in [1.0, -1.0]:
		var flight: Dictionary = ft._fly("snap_roll", { speed = entry, altitude = ft.HIGH }, 16.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = _side(side)
			var k := P.schedule(s, ft.v_start)
			if t < 0.25:
				return { roll = P.bank(s, 0.0, k), throttle = ctx.start_throttle }
			if not ctx.has("stopped_t"):
				ctx.rolled = float(ctx.get("rolled", 0.0)) + side * s[RB.RATE] * DT
				ctx.max_alpha = maxf(float(ctx.get("max_alpha", -INF)), P.alpha(s))
				if not ctx.has("alpha_at_45") and float(ctx.rolled) >= PI / 4.0:
					ctx.alpha_at_45 = float(ctx.max_alpha)
			if not ctx.has("release_t"):
				var rate: float = side * s[RB.RATE]
				ctx.p_sum = float(ctx.get("p_sum", 0.0)) + rate * DT
				ctx.r_sum = float(ctx.get("r_sum", 0.0)) + side * s[RB.RATE + 2] * DT
				ctx.peak_rate = maxf(float(ctx.get("peak_rate", 0.0)), rate)
				var reason := ""
				if float(ctx.rolled) >= TAU - maxf(deg_to_rad(20.0), 0.2 * rate):
					reason = "finish point"
				elif t > 1.0 and rate < float(ctx.peak_rate) / 3.0:
					reason = "autorotation ended"
				elif t > 4.25:
					reason = "4 s"
				if reason.is_empty():
					return { pitch = 1.0, roll = side, yaw = side, throttle = ctx.start_throttle }
				ctx.release_t = t
				ctx.release_rolled = float(ctx.rolled)
				ctx.release_reason = reason
			var yaw_damper := clampf(-2.0 * k * s[RB.RATE + 2], -1.0, 1.0)
			if not ctx.has("stopped_t"):
				if (absf(s[RB.RATE]) > deg_to_rad(30.0) or absf(s[RB.RATE + 2]) > deg_to_rad(30.0)) and t < float(ctx.release_t) + 3.0:
					return { pitch = 0.0, roll = 0.0, yaw = yaw_damper, throttle = ctx.start_throttle }
				ctx.stopped_t = t
				ctx.stop_rolled = float(ctx.rolled)
			# Wings level and pull out of the dive at half the stall-start α (a full height-hold pull would stall again).
			if not ctx.has("level_t"):
				if (absf(P.euler(s)[2]) > deg_to_rad(10.0) or P.climb_rate(s) < 0.0) and t < float(ctx.stopped_t) + 6.0:
					return { roll = P.bank(s, 0.0, k), pitch = P.alpha_hold(s, 0.5 * ft.a1, k, ctx, DT), yaw = yaw_damper, throttle = ctx.start_throttle }
				ctx.level_t = t
				ctx.level_alt = P.altitude(s)
			return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, float(ctx.level_alt), k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = ctx.start_throttle }, \
			func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
				return ctx.has("level_t") and t > float(ctx.level_t) + 2.0)
		if not flight.ok:
			notes.append(flight.message)
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var n: int = trace.row_count()
		var a_max: float = rad_to_deg(float(ctx.get("max_alpha", NAN)))
		var a45: float = rad_to_deg(float(ctx.get("alpha_at_45", NAN)))
		var stalled: bool = a45 > rad_to_deg(ft.a1)
		var autorotation_t: float = float(ctx.get("release_t", NAN)) - 0.25
		var p_mean: float = float(ctx.get("p_sum", 0.0)) / autorotation_t if autorotation_t > 0.0 else NAN
		var r_mean: float = float(ctx.get("r_sum", 0.0)) / autorotation_t if autorotation_t > 0.0 else NAN
		var release_deg: float = rad_to_deg(float(ctx.get("release_rolled", NAN)))
		var r_stop: int = ft._row_at(trace, float(ctx.get("stopped_t", 0.0)))
		var row := { case = _side(side), direction = _side(side), entry_speed_mps = snappedf(entry, 0.01),
			alpha_before_45_deg_of_roll_deg = snappedf(a45, 0.1), max_alpha_deg = snappedf(a_max, 0.1),
			entered = "snap (stalled autorotation)" if stalled else "aileron roll (wing not stalled)",
			release_reason = str(ctx.get("release_reason", "")), release_after_deg = snappedf(release_deg, 0.1),
			autorotation_short_of_finish_deg = snappedf(360.0 - release_deg, 0.1) if str(ctx.get("release_reason", "")) != "finish point" else 0.0,
			time_to_release_s = snappedf(autorotation_t, 0.01), peak_roll_rate_dps = snappedf(rad_to_deg(float(ctx.get("peak_rate", NAN))), 0.1),
			mean_roll_rate_dps = snappedf(rad_to_deg(p_mean), 0.1), mean_yaw_rate_dps = snappedf(rad_to_deg(r_mean), 0.1),
			yaw_to_roll_ratio = snappedf(r_mean / p_mean, 0.001) if p_mean != 0.0 else NAN,
			stop_after_deg = snappedf(rad_to_deg(float(ctx.get("stop_rolled", NAN))), 0.1),
			stop_error_deg = snappedf(rad_to_deg(float(ctx.get("stop_rolled", NAN)) - TAU), 0.1),
			peak_load_factor_g = snappedf(ft._max_load(trace), 0.01),
			height_lost_m = snappedf(trace.value(0, "alt_m") - ft._min(ft._col(trace, "alt_m")), 0.1),
			time_to_level_s = snappedf(float(ctx.get("level_t", NAN)) - float(ctx.get("stopped_t", NAN)), 0.01),
			heading_change_at_stop_deg = snappedf(wrapf(trace.value(r_stop, "yaw_deg") - trace.value(0, "yaw_deg"), -180.0, 180.0), 0.1),
			exit_bank_deg = snappedf(trace.value(n - 1, "roll_deg"), 0.1) }
		var held: bool = ctx.has("level_t") and flight.crashed == "" and not ctx.has("floor_t") and absf(row.exit_bank_deg) < 15.0
		row.recovered = held
		if not held:
			notes.append("%s snap: %s, exit bank %.1f° %s" % [_side(side), "levelled" if ctx.has("level_t") else ("rotation stopped" if ctx.has("stopped_t") else "rotation not stopped"), row.exit_bank_deg, flight.crashed])
		elif row.release_reason != "finish point":
			notes.append("%s snap: autorotation ended %.0f° short of the finish (%s)" % [_side(side), row.autorotation_short_of_finish_deg, row.release_reason])
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })


# --- Stall turn --------------------------------------------------------------------------------------------------

## Stall turn (hammerhead) both ways (FAI 5B.8.11). From 0.8 Vmax at full throttle pull to a vertical up-line (α held
## 2° below the stall start), hold it with elevator and rudder (point_nose), close the throttle 0.5 s after the line is
## set, kick full rudder with a half-throttle blip of slipstream, ailerons stopping roll and the elevator stopping
## pitch, until the nose is 70° below the horizon; hold the down-line 1 s at idle and pull out at half the stall-start
## α. Two kicks: at 0.35 Vs, as the airplane comes to a stop (FAI), and early at 0.6 Vs, which a judge marks as a skid
## but which leaves the rudder free-stream authority. Reports the pivot as a judge would: radius in wingspans (≥ 2 is a
## wing-over), torque-off (roll during the pivot), flop (pitch during the pivot), and a tail slide (moving backwards).
static func stall_turn(ft) -> Dictionary:
	var rows := []
	var notes := []
	var entry: float = maxf(ft.v_start, 0.8 * ft.vmax)
	var span: float = float(ft.model.reference.b)
	for kick_named in [["0.35Vs", 0.35], ["0.6Vs", 0.6]]:
		for side in [1.0, -1.0]:
			rows.append(_stall_turn_case(ft, entry, float(kick_named[1]) * ft.vs, "%s_%s" % [_side(side), kick_named[0]], side, span, notes))
	rows = rows.filter(func(r): return not r.is_empty())
	# The card is met when the pilot flew the figure and recovered; what the pivot looked like is the airplane's answer.
	return ft._result(rows.size() == 4 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })


static func _stall_turn_case(ft, entry: float, kick: float, name: String, side: float, span: float, notes: Array) -> Dictionary:
	var flight: Dictionary = ft._fly("stall_turn", { speed = entry, altitude = ft.HIGH }, 40.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		ctx.suffix = name
		var k := P.schedule(s, ft.v_start)
		var elev := P.nose_elevation(s)
		var phase: String = ctx.get("phase", "pull")
		if phase == "pull":
			if elev < deg_to_rad(80.0):
				return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, ft.a1 - deg_to_rad(2.0), k, ctx, DT), throttle = 1.0 }
			ctx.phase = "up"
			ctx.up_t = t
			phase = "up"
		if phase == "up":
			var line := P.point_nose(s, M.v3(0.0, 0.0, -1.0), k)
			if t < float(ctx.up_t) + 0.5 or P.speed(s) > kick:
				if t > float(ctx.up_t) + 15.0:
					ctx.phase = "stuck"
				return { roll = P.roll_damper(s, k), pitch = line[0], yaw = line[1], throttle = 1.0 if t < float(ctx.up_t) + 0.5 else 0.0 }
			ctx.phase = "pivot"
			phase = "pivot"
			ctx.kick_t = t
			ctx.kick_v = P.speed(s)
			ctx.kick_alt = P.altitude(s)
			ctx.kick_n = s[RB.POS]
			ctx.kick_e = s[RB.POS + 1]
			ctx.kick_elev = elev
		if phase == "pivot":
			ctx.roll_rot = float(ctx.get("roll_rot", 0.0)) + s[RB.RATE] * DT
			ctx.pitch_rot = float(ctx.get("pitch_rot", 0.0)) + s[RB.RATE + 1] * DT
			ctx.max_roll_rot = maxf(float(ctx.get("max_roll_rot", 0.0)), absf(float(ctx.roll_rot)))
			ctx.max_pitch_rot = maxf(float(ctx.get("max_pitch_rot", 0.0)), absf(float(ctx.pitch_rot)))
			ctx.min_u = minf(float(ctx.get("min_u", INF)), s[RB.VEL])
			ctx.radius = maxf(float(ctx.get("radius", 0.0)), sqrt((s[RB.POS] - float(ctx.kick_n)) ** 2 + (s[RB.POS + 1] - float(ctx.kick_e)) ** 2))
			ctx.top_alt = maxf(float(ctx.get("top_alt", -INF)), P.altitude(s))
			if elev > deg_to_rad(-70.0) and t < float(ctx.kick_t) + 6.0:
				return { roll = P.roll_damper(s, k), pitch = clampf(-k * 0.6 * s[RB.RATE + 1], -1.0, 1.0), yaw = side, throttle = 0.5 }
			ctx.pivoted = elev <= deg_to_rad(-70.0)
			ctx.phase = "down"
			phase = "down"
			ctx.pivot_t = t
		if phase == "down":
			var line := P.point_nose(s, M.v3(0.0, 0.0, 1.0), k)
			if t < float(ctx.pivot_t) + 1.0:
				return { roll = P.roll_damper(s, k), pitch = line[0], yaw = line[1], throttle = 0.0 }
			ctx.phase = "pullout"
			ctx.pullout_t = t
			ctx.pullout_alt = P.altitude(s)
			ctx.erase("alpha_i")
		return { roll = P.roll_damper(s, k), pitch = P.alpha_hold(s, 0.5 * ft.a1, k, ctx, DT), throttle = 0.0 }, \
		func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if ctx.get("phase", "") == "stuck":
				return true
			if ctx.get("phase", "") == "pullout" and P.climb_rate(s) > 0.0:
				ctx.level_t = t
				ctx.level_v = P.speed(s)
				return true
			return false)
	if not flight.ok:
		notes.append(flight.message)
		return {}
	var trace: RefCounted = flight.trace
	var ctx: Dictionary = flight.ctx
	var pivoted: bool = ctx.get("pivoted", false)
	var radius_spans: float = float(ctx.get("radius", NAN)) / span
	var outcome := "no up-line"
	if ctx.get("phase", "") == "stuck":
		outcome = "did not slow to the kick speed"
	elif ctx.has("kick_t") and not pivoted:
		outcome = "no pivot in 6 s (nose not 70° down)"
	elif pivoted:
		if float(ctx.get("min_u", 0.0)) < -1.0:
			outcome = "tail slide"
		elif radius_spans >= 2.0:
			outcome = "wing-over"
		elif rad_to_deg(float(ctx.get("max_pitch_rot", 0.0))) > 45.0:
			outcome = "flop"
		else:
			outcome = "pivot"
	var row := { case = name, direction = _side(side), entry_speed_mps = snappedf(entry, 0.01), kick_speed_target_mps = snappedf(kick, 0.01),
		kick_speed_mps = snappedf(float(ctx.get("kick_v", NAN)), 0.01), up_line_time_s = snappedf(float(ctx.get("kick_t", NAN)) - float(ctx.get("up_t", NAN)), 0.01),
		height_gain_to_kick_m = snappedf(float(ctx.get("kick_alt", NAN)) - trace.value(0, "alt_m"), 0.1),
		pivot_time_s = snappedf(float(ctx.get("pivot_t", NAN)) - float(ctx.get("kick_t", NAN)), 0.01),
		pivot_radius_m = snappedf(float(ctx.get("radius", NAN)), 0.01), pivot_radius_spans = snappedf(radius_spans, 0.01),
		torque_off_deg = snappedf(rad_to_deg(float(ctx.get("max_roll_rot", NAN))), 0.1), pitch_during_pivot_deg = snappedf(rad_to_deg(float(ctx.get("max_pitch_rot", NAN))), 0.1),
		min_forward_speed_mps = snappedf(float(ctx.get("min_u", NAN)), 0.01), outcome = outcome,
		height_lost_top_to_level_m = snappedf(float(ctx.get("top_alt", NAN)) - ft._min(ft._col(trace, "alt_m", ft._row_at(trace, float(ctx.get("kick_t", 0.0))))), 0.1),
		exit_speed_mps = snappedf(float(ctx.get("level_v", NAN)), 0.01) }
	var done: bool = ctx.has("level_t") and flight.crashed == "" and not ctx.has("floor_t")
	row.recovered = done
	if not done or outcome != "pivot":
		notes.append("%s: %s%s %s" % [name, outcome, "" if done else ", not recovered", flight.crashed])
	return row
