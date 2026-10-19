# FT-04 (card v4): stall and spin variants of the standard flight-test card: the accelerated stall in a turn, the
# skidded (cross-controlled) stall, the stall held with the stick back, the inverted stall and the inverted spin. Each
# function takes the runner (flight_test.gd) and returns its { valid, metrics, notes, table } result. A break needs α
# within 1° of the solved stall start (as the v3 stalls), so a pilot transient is not a stall. Model predictions, not
# physical validation; the post-stall model is the subject of open physics work (FT-03 finding 1, D10-R4).
extends RefCounted

const P := preload("pilot.gd")
const RB := preload("res://physics/rigid_body.gd")

const DT := 1.0 / 240.0


static func _side(side: float) -> String:
	return "right" if side > 0.0 else "left"


## The break: α near the stall start with a 2 m/s sink or 20° away from the wanted bank, or a wing that only mushes
## (the elevator at its stop for 1 s with α above 0.8 of the stall start). `sign` is +1 upright, −1 inverted.
static func _broke(ft, s: PackedFloat64Array, ctx: Dictionary, t: float, bank: float, sign: float) -> String:
	var alpha: float = sign * P.alpha(s)
	var limit: float = ft.a1 if sign > 0.0 else ft.n1
	if t > 3.0 and alpha > limit - deg_to_rad(1.0) and (P.climb_rate(s) < -2.0 or absf(wrapf(P.euler(s)[2] - bank, -PI, PI)) > deg_to_rad(20.0)):
		return "wing drop or sink"
	var raw: PackedFloat64Array = ctx.get("raw_pitch", PackedFloat64Array())
	if raw.size() > 240 and alpha > 0.8 * limit:
		for j in range(raw.size() - 240, raw.size()):
			if sign * raw[j] < 0.98:
				return ""
		return "elevator limit (mush)"
	return ""


## Accelerated stall in a level turn both ways at 30° and 45° of bank (the turn to final): from 1.4 Vs × √n at idle,
## bank held with the ailerons, height with the elevator (it pulls harder as the speed decays), feet on the ball, until
## the break; then unload to half the stall-start α, level the wings, full power. The stall speed against Vs × √n,
## which way the wing goes (inside or outside the turn), and the height the recovery takes.
static func stall_turning(ft) -> Dictionary:
	var rows := []
	var notes := []
	for named in [["30_right", 30.0, 1.0], ["30_left", 30.0, -1.0], ["45_right", 45.0, 1.0], ["45_left", 45.0, -1.0]]:
		var side: float = named[2]
		var bank: float = side * deg_to_rad(named[1])
		var n_turn: float = 1.0 / cos(bank)
		var row := _stall_case(ft, "stall_turning", str(named[0]), 1.4 * ft.vs * sqrt(n_turn), bank, 0.0, notes)
		if row.is_empty():
			continue
		row.bank_deg = named[1]
		row.ratio_to_vs_root_n = snappedf(float(row.stall_speed_mps) / (ft.vs * sqrt(n_turn)), 0.001)
		rows.append(row)
	return ft._result(rows.size() == 4 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })


## Cross-controlled (skidded) stall both ways, the base-to-final stall: 20° of bank held with the ailerons while half
## bottom rudder (into the turn) skids the nose around, height held with the elevator at idle, until the break; then
## the standard recovery. Which way it rolls off: into the rudder ("under", the snap the pilot fears) or away.
static func stall_cross_controlled(ft) -> Dictionary:
	var rows := []
	var notes := []
	for side in [1.0, -1.0]:
		var bank: float = side * deg_to_rad(20.0)
		var row := _stall_case(ft, "stall_cross_controlled", _side(side), 1.4 * ft.vs * sqrt(1.0 / cos(bank)), bank, side * 0.5, notes)
		if row.is_empty():
			continue
		row.rudder_stick = side * 0.5
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })


## One idle stall at a bank (rad) with an optional fixed rudder (stick, else the ball is centred). The roll-off is the
## largest bank change in the first second after the break (+ right); `roll_off` says whether it went to the inside of
## the turn (the bank's side) or the outside.
static func _stall_case(ft, name: String, case_id: String, entry: float, bank: float, rudder: float, notes: Array) -> Dictionary:
	var alt0: float = ft.HIGH
	var flight: Dictionary = ft._fly(name, { speed = entry, altitude = alt0 }, 45.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		ctx.suffix = case_id
		var k := P.schedule(s, ft.v_start)
		var e := P.euler(s)
		if not ctx.has("break_t"):
			var kind := _broke(ft, s, ctx, t, bank, 1.0)
			if kind.is_empty():
				return { roll = P.bank_pi(s, bank, k, ctx, DT), pitch = P.hold_altitude(s, alt0, k, ctx, DT),
					yaw = rudder if rudder != 0.0 and t > 1.0 else P.ball(s, k, ctx, DT), throttle = 0.0 }
			ctx.break_t = t
			ctx.break_kind = kind
			ctx.break_v = P.speed(s)
			ctx.break_alpha = P.alpha(s)
			ctx.break_bank = e[2]
			ctx.break_alt = P.altitude(s)
		var since: float = t - float(ctx.break_t)
		if since <= 1.0:
			var change: float = wrapf(e[2] - float(ctx.break_bank), -PI, PI)
			if absf(change) >= absf(float(ctx.get("roll_off", 0.0))):
				ctx.roll_off = change
		ctx.max_bank = maxf(float(ctx.get("max_bank", 0.0)), absf(e[2]))
		return { roll = P.bank(s, 0.0, k) if since > 0.3 else 0.0, pitch = P.alpha_hold(s, 0.5 * ft.a1, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 1.0 }, \
		func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if ctx.has("break_t") and t - float(ctx.break_t) > 1.5 and P.climb_rate(s) > 0.0 and P.speed(s) > 1.2 * float(ctx.break_v):
				ctx.recovered_t = t
				return true
			return false)
	if not flight.ok:
		notes.append("%s: %s" % [case_id, flight.message])
		return {}
	var ctx: Dictionary = flight.ctx
	var trace: RefCounted = flight.trace
	if not ctx.has("break_t"):
		notes.append("%s: no stall break within 45 s" % case_id)
		return { case = case_id, recovered = false }
	var r0: int = ft._row_at(trace, float(ctx.break_t))
	var inside_sign: float = signf(bank) if bank != 0.0 else signf(float(ctx.get("roll_off", 0.0)))
	var roll_off: float = rad_to_deg(float(ctx.get("roll_off", 0.0)))
	var row := { case = case_id, entry_speed_mps = snappedf(entry, 0.01), break_kind = str(ctx.break_kind),
		stall_speed_mps = snappedf(float(ctx.break_v), 0.01), stall_speed_vs = snappedf(float(ctx.break_v) / ft.vs, 0.001), stall_alpha_deg = snappedf(rad_to_deg(float(ctx.break_alpha)), 0.1),
		bank_at_break_deg = snappedf(rad_to_deg(float(ctx.break_bank)), 0.1), roll_off_in_1_s_deg = snappedf(roll_off, 0.1),
		roll_off = "inside" if roll_off * inside_sign > 0.0 else "outside", max_bank_in_recovery_deg = snappedf(rad_to_deg(float(ctx.get("max_bank", 0.0))), 0.1),
		altitude_lost_m = snappedf(trace.value(r0, "alt_m") - ft._min(ft._col(trace, "alt_m", r0)), 0.1),
		recovery_time_s = snappedf(float(ctx.get("recovered_t", NAN)) - float(ctx.break_t), 0.01) }
	row.recovered = ctx.has("recovered_t") and flight.crashed == "" and not ctx.has("floor_t")
	if not row.recovered:
		notes.append("%s: not recovered %s" % [case_id, flight.crashed])
	return row


## The stall held, from 400 m: a power-off wings-level stall as stall_power_off, then the stick held fully back for 5 s
## after the break, once with the ailerons and rudder neutral and once with them used to hold the wings level and the
## ball centred (the normal use of controls a certification stall test allows); then the standard recovery. Does it
## mush, drop a wing or start to spin: the bank, the rotation about the vertical and the height in those 5 s.
static func stall_held(ft) -> Dictionary:
	var rows := []
	var notes := []
	var alt0 := 400.0
	for named in [["controls_neutral", false], ["wings_level", true]]:
		var use_controls: bool = named[1]
		var flight: Dictionary = ft._fly("stall_held", { speed = 1.4 * ft.vs, altitude = alt0 }, 40.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = str(named[0])
			var k := P.schedule(s, ft.v_start)
			var e := P.euler(s)
			if not ctx.has("break_t"):
				var kind := _broke(ft, s, ctx, t, 0.0, 1.0)
				if kind.is_empty():
					return { roll = P.bank(s, 0.0, k), pitch = P.hold_altitude(s, alt0, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 0.0 }
				ctx.break_t = t
				ctx.break_kind = kind
				ctx.break_v = P.speed(s)
				ctx.break_alt = P.altitude(s)
				ctx.break_heading = e[0]
			var since: float = t - float(ctx.break_t)
			if since <= 5.0:
				ctx.max_bank = maxf(float(ctx.get("max_bank", 0.0)), absf(e[2]))
				var yaw_rate: float = absf(ft._earth_yaw_rate(s))
				ctx.max_yaw_rate = maxf(float(ctx.get("max_yaw_rate", 0.0)), yaw_rate)
				if since > 3.0:
					ctx.late_yaw = float(ctx.get("late_yaw", 0.0)) + yaw_rate * DT
				ctx.heading_turned = float(ctx.get("heading_turned", 0.0)) + ft._earth_yaw_rate(s) * DT
				ctx.held_alt = P.altitude(s)
				return { pitch = 1.0, roll = P.bank(s, 0.0, k) if use_controls else 0.0, yaw = P.ball(s, k, ctx, DT) if use_controls else 0.0, throttle = 0.0 }
			if not ctx.has("release_t"):
				ctx.release_t = t
				ctx.erase("alpha_i")
			return { roll = P.bank(s, 0.0, k), pitch = P.alpha_hold(s, 0.5 * ft.a1, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 1.0 }, \
			func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
				if ctx.has("release_t") and t - float(ctx.release_t) > 1.0 and P.climb_rate(s) > 0.0 and P.speed(s) > 1.2 * float(ctx.break_v):
					ctx.recovered_t = t
					return true
				return false)
		if not flight.ok:
			notes.append("%s: %s" % [named[0], flight.message])
			continue
		var ctx: Dictionary = flight.ctx
		var trace: RefCounted = flight.trace
		if not ctx.has("break_t"):
			notes.append("%s: no stall break within 40 s" % named[0])
			rows.append({ case = named[0], recovered = false })
			continue
		var max_bank: float = rad_to_deg(float(ctx.get("max_bank", 0.0)))
		var late_rate: float = rad_to_deg(float(ctx.get("late_yaw", 0.0)) / 2.0)
		var outcome := "mush"
		if late_rate > 90.0:
			outcome = "spin entry"
		elif max_bank >= 30.0:
			outcome = "wing drop"
		var row := { case = named[0], break_kind = str(ctx.break_kind), stall_speed_mps = snappedf(float(ctx.break_v), 0.01),
			max_bank_held_deg = snappedf(max_bank, 0.1), max_rotation_rate_dps = snappedf(rad_to_deg(float(ctx.get("max_yaw_rate", 0.0))), 0.1),
			rotation_rate_last_2_s_dps = snappedf(late_rate, 0.1), heading_change_held_deg = snappedf(rad_to_deg(float(ctx.get("heading_turned", 0.0))), 0.1),
			height_lost_held_m = snappedf(float(ctx.break_alt) - float(ctx.get("held_alt", NAN)), 0.1), outcome = outcome,
			height_lost_to_recovery_m = snappedf(float(ctx.break_alt) - ft._min(ft._col(trace, "alt_m", ft._row_at(trace, float(ctx.break_t)))), 0.1),
			recovery_time_s = snappedf(float(ctx.get("recovered_t", NAN)) - float(ctx.get("release_t", NAN)), 0.01) }
		row.recovered = ctx.has("recovered_t") and flight.crashed == "" and not ctx.has("floor_t")
		if not row.recovered:
			notes.append("%s: not recovered %s" % [named[0], flight.crashed])
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })


## Inverted 1-g stall: from 1.6 Vs roll inverted (the inverted pass law), then idle with the height held through a push
## that may go past the negative stall start, wings level inverted, feet on the ball, until the break; then release the
## push (α to 0), roll upright, full power and pull out at half the stall-start α. The inverted stall speed against the
## upright one, and the height it takes.
static func stall_inverted(ft) -> Dictionary:
	var alt0: float = ft.HIGH
	var flight: Dictionary = ft._fly("stall_inverted", { speed = 1.6 * ft.vs, altitude = alt0 }, 50.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		var k := P.schedule(s, ft.v_start)
		var e := P.euler(s)
		if not ctx.has("break_t"):
			var pitch: float = -k * 0.6 * s[RB.RATE + 1]
			if not ctx.has("over_t") and absf(e[2]) >= deg_to_rad(160.0):
				ctx.over_t = t
				ctx.bank_i = 0.0
				ctx.alpha_i = 0.0
			if ctx.has("over_t"):
				var kind := _broke(ft, s, ctx, t - float(ctx.over_t), PI, -1.0)
				if not kind.is_empty():
					ctx.break_t = t
					ctx.break_kind = kind
					ctx.break_v = P.speed(s)
					ctx.break_alpha = P.alpha(s)
					ctx.break_bank = e[2]
				else:
					var e_alt: float = alt0 - P.altitude(s)
					ctx.inv_i = clampf(float(ctx.get("inv_i", 0.0)) + e_alt * DT, -40.0, 40.0)
					var wanted := clampf(-(0.02 * e_alt - 0.03 * P.climb_rate(s) + 0.004 * float(ctx.inv_i)), -(ft.n1 + deg_to_rad(15.0)), deg_to_rad(5.0))
					pitch = P.alpha_hold(s, wanted, k, ctx, DT)
			if not ctx.has("break_t"):
				return { roll = P.bank_pi(s, PI, k, ctx, DT), pitch = pitch, yaw = P.ball(s, k, ctx, DT), throttle = 0.0 if ctx.has("over_t") else ctx.start_throttle }
		var since: float = t - float(ctx.break_t)
		if since <= 1.0:
			var change: float = wrapf(e[2] - float(ctx.break_bank), -PI, PI)
			if absf(change) >= absf(float(ctx.get("roll_off", 0.0))):
				ctx.roll_off = change
		var upright: bool = absf(e[2]) < deg_to_rad(30.0)
		if upright and not ctx.has("upright_t"):
			ctx.upright_t = t
			ctx.erase("alpha_i")
		return { roll = P.bank(s, 0.0, k) if since > 0.3 else 0.0, pitch = P.alpha_hold(s, 0.5 * ft.a1 if ctx.has("upright_t") else 0.0, k, ctx, DT),
			yaw = P.ball(s, k, ctx, DT), throttle = 1.0 }, \
		func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if ctx.has("upright_t") and t - float(ctx.break_t) > 1.5 and P.climb_rate(s) > 0.0 and P.speed(s) > 1.2 * float(ctx.break_v):
				ctx.recovered_t = t
				return true
			return false)
	if not flight.ok:
		return ft._failed(flight)
	var ctx: Dictionary = flight.ctx
	var trace: RefCounted = flight.trace
	var notes := []
	if not ctx.has("break_t"):
		notes.append("no inverted stall break within 50 s" if ctx.has("over_t") else "never inverted")
		return ft._result(false, {}, notes)
	var r0: int = ft._row_at(trace, float(ctx.break_t))
	var recovered: bool = ctx.has("recovered_t") and flight.crashed == "" and not ctx.has("floor_t")
	if not recovered:
		notes.append("not recovered " + flight.crashed)
	return ft._result(recovered, { break_kind = str(ctx.break_kind), stall_speed_mps = snappedf(float(ctx.break_v), 0.01),
		ratio_to_upright_vs = snappedf(float(ctx.break_v) / ft.vs, 0.001), stall_alpha_deg = snappedf(rad_to_deg(float(ctx.break_alpha)), 0.1),
		roll_off_in_1_s_deg = snappedf(rad_to_deg(float(ctx.get("roll_off", 0.0))), 0.1),
		altitude_lost_m = snappedf(trace.value(r0, "alt_m") - ft._min(ft._col(trace, "alt_m", r0)), 0.1),
		recovery_time_s = snappedf(float(ctx.get("recovered_t", NAN)) - float(ctx.break_t), 0.01) }, notes)


## Inverted spins both ways (by rudder): roll inverted at 1.6 Vs and 400 m (the inverted pass law), idle, and once the
## bank has been held for 1 s apply full down elevator and full rudder for 6 s; then opposite rudder with the elevator
## neutral until the rotation about the vertical falls below 0.5 rad/s, roll upright and pull out at half the
## stall-start α. Spin or spiral, the turn time and height per turn, and the recovery.
static func spin_inverted(ft) -> Dictionary:
	var rows := []
	var notes := []
	for side in [1.0, -1.0]:
		var flight: Dictionary = ft._fly("spin_inverted", { speed = 1.6 * ft.vs, altitude = 400.0 }, 40.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = _side(side)
			var k := P.schedule(s, ft.v_start)
			var e := P.euler(s)
			if not ctx.has("entry_t"):
				if not ctx.has("level_inverted_t") and absf(e[2]) >= deg_to_rad(170.0):
					ctx.level_inverted_t = t
				if ctx.has("level_inverted_t") and t > float(ctx.level_inverted_t) + 1.0:
					ctx.entry_t = t
					ctx.entry_alt = P.altitude(s)
				else:
					return { roll = P.bank_pi(s, PI, k, ctx, DT), pitch = -k * 0.6 * s[RB.RATE + 1], yaw = P.ball(s, k, ctx, DT), throttle = 0.0 }
			var since: float = t - float(ctx.entry_t)
			if since < 6.0:
				ctx.turns_pro = float(ctx.get("turns_pro", 0.0)) + absf(ft._earth_yaw_rate(s)) / TAU * DT
				ctx.min_alpha = minf(float(ctx.get("min_alpha", INF)), P.alpha(s))
				if since > 4.0:
					ctx.rate_samples = ctx.get("rate_samples", []) + [absf(ft._earth_yaw_rate(s))]
				ctx.pro_alt = P.altitude(s)
				return { pitch = -1.0, yaw = side, throttle = 0.0 }
			if not ctx.has("stopped_t"):
				ctx.turns_recovery = float(ctx.get("turns_recovery", 0.0)) + absf(ft._earth_yaw_rate(s)) / TAU * DT
				if absf(ft._earth_yaw_rate(s)) < 0.5 and since > 6.25:
					ctx.stopped_t = t
				else:
					return { pitch = 0.0, yaw = -side, throttle = 0.0 }
			var upright: bool = absf(e[2]) < deg_to_rad(30.0)
			if upright and not ctx.has("upright_t"):
				ctx.upright_t = t
				ctx.erase("alpha_i")
			return { roll = P.bank(s, 0.0, k), pitch = P.alpha_hold(s, 0.5 * ft.a1 if ctx.has("upright_t") else 0.0, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 0.0 }, \
			func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
				if ctx.has("upright_t") and P.climb_rate(s) > 0.0 and t > float(ctx.upright_t) + 0.5:
					ctx.level_t = t
					return true
				return false)
		if not flight.ok:
			notes.append(flight.message)
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		if not ctx.has("entry_t"):
			notes.append("%s: never held inverted" % _side(side))
			rows.append({ case = _side(side), recovered = false })
			continue
		var rate: float = ft._mean(PackedFloat64Array(ctx.get("rate_samples", [])))
		var turns_pro: float = float(ctx.get("turns_pro", 0.0))
		var min_alpha: float = rad_to_deg(float(ctx.get("min_alpha", NAN)))
		var row := { case = _side(side), rudder = _side(side), steady_turn_time_s = snappedf(TAU / rate, 0.01) if rate > 0.0 else NAN,
			turns_in_6_s = snappedf(turns_pro, 0.01), height_lost_per_turn_m = snappedf((float(ctx.entry_alt) - float(ctx.get("pro_alt", NAN))) / maxf(turns_pro, 0.01), 0.1),
			min_alpha_deg = snappedf(min_alpha, 0.1), recovery_turns = snappedf(float(ctx.get("turns_recovery", NAN)), 0.01),
			recovery_time_s = snappedf(float(ctx.get("stopped_t", NAN)) - float(ctx.entry_t) - 6.0, 0.01),
			total_height_lost_m = snappedf(float(ctx.entry_alt) - ft._min(ft._col(trace, "alt_m")), 0.1) }
		row.entered = "spin" if rate > TAU / 3.0 and min_alpha < -rad_to_deg(ft.n1) else "spiral (no spin)"
		row.recovered = ctx.has("level_t") and flight.crashed == "" and not ctx.has("floor_t")
		if not row.recovered:
			notes.append("%s inverted spin not recovered %s" % [_side(side), flight.crashed])
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.recovered), {}, notes, { table = rows })
