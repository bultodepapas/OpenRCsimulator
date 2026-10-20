# FT-04 (card v4): power-off tests of the standard flight-test card. The engine fails the way the session's own source
# cut does it (flight_test.gd _cut_engine: glow_cut() or the source disabled), so a glow engine stops instead of idling
# and a propeller windmills or stops as the propulsion model decides; a continuous turbine idles (no hot cutoff yet).
# Each function takes the runner and returns its { valid, metrics, notes, table } result. Model predictions, not
# physical validation.
extends RefCounted

const P := preload("pilot.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const RB := preload("res://physics/rigid_body.gd")

const DT := 1.0 / 240.0


## Engine failure in the climb: full-throttle climb at 1.6 Vs (speed held with the elevator) from 250 m, the engine cut
## at 6 s, the climb attitude held for the pilot's reaction time (1 s or 2 s), then the nose lowered to glide at 1.4 Vs.
## How far the speed falls, how close the wing comes to the stall, and the height the airplane still gains or loses.
static func engine_cut_climb(ft) -> Dictionary:
	var rows := []
	var notes := []
	var climb_speed: float = 1.6 * ft.vs
	var glide_speed: float = 1.4 * ft.vs
	var cut_at := 6.0
	for named in [["1s", 1.0], ["2s", 2.0]]:
		var delay: float = named[1]
		var flight: Dictionary = ft._fly("engine_cut_climb", { speed = climb_speed, altitude = ft.HIGH }, cut_at + 14.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "delay_" + str(named[0])
			var k := P.schedule(s, ft.v_start)
			var c := { roll = P.bank(s, 0.0, k), yaw = P.ball(s, k, ctx, DT), throttle = 0.0 }
			if t < cut_at:
				c.pitch = P.hold_speed(s, climb_speed, k, ctx, DT)
				c.throttle = 1.0
				return c
			if not ctx.has("cut_t"):
				ctx.cut_t = t
				ctx.engine_out = ft._cut_engine()
				ctx.cut_pitch = P.euler(s)[1]
				ctx.cut_v = P.speed(s)
				ctx.cut_alt = P.altitude(s)
			ctx.min_v = minf(float(ctx.get("min_v", INF)), P.speed(s))
			ctx.max_alpha = maxf(float(ctx.get("max_alpha", -INF)), P.alpha(s))
			ctx.top_alt = maxf(float(ctx.get("top_alt", -INF)), P.altitude(s))
			ctx.slow_s = float(ctx.get("slow_s", 0.0)) + (DT if P.speed(s) < 1.2 * ft.vs else 0.0)
			if t < float(ctx.cut_t) + delay:
				c.pitch = P.pitch(s, float(ctx.cut_pitch), k, ctx, DT)
				return c
			if not ctx.has("react_t"):
				# The pilot pushes over to a glide: the speed loop starts afresh from the new target.
				ctx.react_t = t
				ctx.react_v = P.speed(s)
				ctx.erase("speed_i")
				ctx.erase("pitch_i")
			c.pitch = P.hold_speed(s, glide_speed, k, ctx, DT)
			return c)
		if not flight.ok:
			notes.append("%s: %s" % [named[0], flight.message])
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var n: int = trace.row_count()
		var cut_alt: float = float(ctx.get("cut_alt", NAN))
		var r10: int = ft._row_at(trace, cut_at + 10.0)
		var row := { case = "delay_" + str(named[0]), reaction_s = delay, climb_speed_mps = snappedf(climb_speed, 0.01), glide_speed_mps = snappedf(glide_speed, 0.01),
			climb_pitch_at_cut_deg = snappedf(rad_to_deg(float(ctx.get("cut_pitch", NAN))), 0.1), speed_at_cut_mps = snappedf(float(ctx.get("cut_v", NAN)), 0.01),
			speed_after_reaction_mps = snappedf(float(ctx.get("react_v", NAN)), 0.01), min_speed_mps = snappedf(float(ctx.get("min_v", NAN)), 0.01),
			min_speed_vs = snappedf(float(ctx.get("min_v", NAN)) / ft.vs, 0.01), max_alpha_deg = snappedf(rad_to_deg(float(ctx.get("max_alpha", NAN))), 0.1),
			alpha_margin_to_stall_deg = snappedf(rad_to_deg(ft.a1 - float(ctx.get("max_alpha", NAN))), 0.1), stalled = float(ctx.get("max_alpha", 0.0)) > ft.a1,
			time_below_1_2vs_s = snappedf(float(ctx.get("slow_s", 0.0)), 0.01), height_gained_after_cut_m = snappedf(float(ctx.get("top_alt", NAN)) - cut_alt, 0.1),
			height_change_10_s_m = snappedf(trace.value(r10, "alt_m") - cut_alt, 0.1) if r10 < n else NAN,
			rpm_10_s_after_cut = roundi(trace.value(mini(r10, n - 1), "engine_rpm")), engine_out = str(ctx.get("engine_out", "")) }
		var done: bool = str(ctx.get("engine_out", "")) != "" and flight.crashed == "" and not ctx.has("floor_t")
		row.completed = done
		if str(ctx.get("engine_out", "")) == "":
			notes.append("%s: the engine cut was refused" % named[0])
		elif not done:
			notes.append("%s: %s" % [named[0], flight.crashed if flight.crashed != "" else "reached the floor"])
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.completed), {}, notes, { table = rows })


## The turn back after an engine failure: engine cut at the start, speed held with the elevator at 1.3 Vs × √n (the same
## margin over the stall in the turn as 1.3 Vs straight), 4 s of straight glide, then a coordinated turn at 30°, 45° and
## 60° of bank for a full circle. The height each bank costs per 180° of heading: the classic "impossible turn" number.
static func glide_turn(ft) -> Dictionary:
	var rows := []
	var notes := []
	var valid := true
	for degrees in [30.0, 45.0, 60.0]:
		var bank := deg_to_rad(degrees)
		var speed: float = 1.3 * ft.vs * sqrt(1.0 / cos(bank))
		var flight: Dictionary = ft._fly("glide_turn", { speed = speed, altitude = ft.HIGH }, 60.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = "%.0fdeg" % degrees
			if not ctx.has("engine_out"):
				ctx.engine_out = ft._cut_engine()
			var k := P.schedule(s, ft.v_start)
			var track := P.track(s)
			if t >= 4.0:
				if not ctx.has("turn_alt"):
					ctx.turn_alt = P.altitude(s)
					ctx.turned = 0.0
				else:
					ctx.turned = float(ctx.turned) + wrapf(track - float(ctx.track), -PI, PI)
				if not ctx.has("half_t") and absf(float(ctx.turned)) >= PI:
					ctx.half_t = t
					ctx.half_alt = P.altitude(s)
			ctx.track = track
			return { roll = P.bank(s, bank if t >= 4.0 else 0.0, k), pitch = P.hold_speed(s, speed, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 0.0 }, \
			func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
				if absf(float(ctx.get("turned", 0.0))) >= TAU:
					ctx.full_t = t
					return true
				return false)
		if not flight.ok:
			notes.append("%.0f°: %s" % [degrees, flight.message])
			valid = false
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var r2: int = ft._row_at(trace, 2.0)
		var r4: int = ft._row_at(trace, 4.0)
		var r_full: int = ft._row_at(trace, float(ctx.get("full_t", trace.value(trace.row_count() - 1, "t_s"))))
		var r_half: int = ft._row_at(trace, float(ctx.get("half_t", 4.0)))
		var turn_alt: float = float(ctx.get("turn_alt", NAN))
		var rate := absf(ft._track_rate(trace, r_half, r_full)) if r_full > r_half + 2 else NAN
		var v: float = ft._mean(ft._col(trace, "speed_mps", r_half, r_full))
		var row := { case = "%.0fdeg" % degrees, bank_deg = degrees, speed_target_mps = snappedf(speed, 0.01),
			straight_sink_mps = snappedf(-ft._slope(trace, "alt_m", r2, r4), 0.01),
			time_to_180_s = snappedf(float(ctx.get("half_t", NAN)) - 4.0, 0.01), height_lost_180_m = snappedf(turn_alt - float(ctx.get("half_alt", NAN)), 0.1),
			time_to_360_s = snappedf(float(ctx.get("full_t", NAN)) - 4.0, 0.01), height_lost_360_m = snappedf(turn_alt - trace.value(r_full, "alt_m"), 0.1),
			turn_sink_mps = snappedf(-ft._slope(trace, "alt_m", r_half, r_full), 0.01), speed_in_turn_mps = snappedf(v, 0.01),
			radius_m = snappedf(v / deg_to_rad(rate), 0.1) if is_finite(rate) and rate > 0.0 else NAN,
			bank_held_deg = snappedf(ft._mean(ft._col(trace, "roll_deg", r_half, r_full)), 0.1), engine_out = str(ctx.get("engine_out", "")) }
		var done: bool = str(ctx.get("engine_out", "")) != "" and ctx.has("full_t") and flight.crashed == "" and absf(absf(row.bank_held_deg) - degrees) < 5.0
		if not done:
			notes.append("%.0f°: %s, bank %.1f° %s" % [degrees, "circle completed" if ctx.has("full_t") else "circle not completed", row.bank_held_deg, flight.crashed])
		valid = valid and done
		rows.append(row)
	var best := {}
	for row in rows:
		if is_finite(row.height_lost_180_m) and (best.is_empty() or row.height_lost_180_m < best.height_lost_180_m):
			best = row
	return ft._result(valid and rows.size() == 3, { least_height_per_180_bank_deg = best.get("bank_deg", NAN),
		least_height_lost_180_m = best.get("height_lost_180_m", NAN) }, notes, { table = rows })


## D6e-R3 (card v5): hands-off throttle steps from the trimmed airborne start, the maneuver behind the reported
## "tendency to climb". At 1 s the throttle leaves the trim value for idle, 25, 50, 75 or 100 % and stays there for
## 30 s. The elevator stays at its trim (no pilot pitch input); the wings are held level and the ball centred so a
## spiral does not mask the longitudinal answer. Reports the height, speed, path angle and attitude the fixed trim
## gives at each power, the level speed that throttle trims at (from trim_sweep), the constant-speed climb angle the
## thrust excess at the trim speed predicts, and whether the airplane goes past inverted. A departure is the
## airplane's answer, not a pilot failure; validity only asks that every flight completed without a crash.
static func power_step(ft) -> Dictionary:
	var rows := []
	var notes := []
	var start_alt := 400.0
	for named in [["idle", 0.0], ["25pct", 0.25], ["50pct", 0.5], ["75pct", 0.75], ["100pct", 1.0]]:
		var throttle: float = named[1]
		var label: String = named[0]
		var flight: Dictionary = ft._fly("power_step", { speed = ft.v_start, altitude = start_alt }, 31.0, func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = label
			var k := P.schedule(s, ft.v_start)
			if t >= 1.0:
				var pitch: float = P.euler(s)[1]
				ctx.max_pitch = maxf(float(ctx.get("max_pitch", -INF)), pitch)
				ctx.min_pitch = minf(float(ctx.get("min_pitch", INF)), pitch)
				ctx.max_alpha = maxf(float(ctx.get("max_alpha", -INF)), P.alpha(s))
				ctx.min_v = minf(float(ctx.get("min_v", INF)), P.speed(s))
				ctx.max_v = maxf(float(ctx.get("max_v", -INF)), P.speed(s))
				ctx.max_alt = maxf(float(ctx.get("max_alt", -INF)), P.altitude(s))
				if not ctx.has("inverted_t") and P.up_body(s)[2] > 0.0:
					ctx.inverted_t = t
			return { roll = P.bank(s, 0.0, k), pitch = 0.0, yaw = P.ball(s, k, ctx, DT),
				throttle = float(ctx.start_throttle) if t < 1.0 else throttle })
		if not flight.ok:
			notes.append("%s: %s" % [label, flight.message])
			continue
		var trace: RefCounted = flight.trace
		var ctx: Dictionary = flight.ctx
		var n: int = trace.row_count()
		var alt0: float = trace.value(0, "alt_m")
		var v0: float = trace.value(0, "speed_mps")
		var row := { case = label, throttle = throttle, trim_throttle = snappedf(float(ctx.start_throttle), 0.001),
			trim_speed_mps = snappedf(v0, 0.01) }
		for at in [5.0, 10.0, 20.0, 30.0]:
			var r: int = mini(ft._row_at(trace, 1.0 + at), n - 1)
			row["height_change_%.0f_s_m" % at] = snappedf(trace.value(r, "alt_m") - alt0, 0.1)
			row["speed_%.0f_s_mps" % at] = snappedf(trace.value(r, "speed_mps"), 0.01)
		# The path over the last five seconds flown: rate of climb, path angle, attitude and engine speed.
		var r0: int = ft._row_at(trace, maxf(float(flight.t_end) - 5.0, 1.0))
		var rate: float = ft._slope(trace, "alt_m", r0, n)
		var v_end: float = ft._mean(ft._col(trace, "speed_mps", r0))
		row.vertical_speed_end_mps = snappedf(rate, 0.01)
		row.path_angle_end_deg = snappedf(rad_to_deg(asin(clampf(rate / maxf(v_end, 0.1), -1.0, 1.0))), 0.1)
		row.pitch_end_deg = snappedf(ft._mean(ft._col(trace, "pitch_deg", r0)), 0.1)
		row.rpm_end = roundi(ft._mean(ft._col(trace, "engine_rpm", r0)))
		row.max_pitch_deg = snappedf(rad_to_deg(float(ctx.get("max_pitch", NAN))), 0.1)
		row.min_pitch_deg = snappedf(rad_to_deg(float(ctx.get("min_pitch", NAN))), 0.1)
		row.max_alpha_deg = snappedf(rad_to_deg(float(ctx.get("max_alpha", NAN))), 0.1)
		row.min_speed_mps = snappedf(float(ctx.get("min_v", NAN)), 0.01)
		row.max_speed_mps = snappedf(float(ctx.get("max_v", NAN)), 0.01)
		row.max_height_gain_m = snappedf(float(ctx.get("max_alt", NAN)) - alt0, 0.1)
		row.inverted_at_s = snappedf(float(ctx.get("inverted_t", NAN)), 0.01)
		row.reached_floor_s = snappedf(float(ctx.get("floor_t", NAN)), 0.01)
		row.level_speed_at_throttle_mps = snappedf(_level_speed_at(ft, throttle), 0.01)
		row.predicted_path_angle_deg = snappedf(_energy_climb_angle(ft, throttle), 0.1)
		row.completed = flight.crashed == ""
		if flight.crashed != "":
			notes.append("%s: %s" % [label, flight.crashed])
		if ctx.has("inverted_t"):
			notes.append("%s: past inverted at %.2f s with the elevator at its trim" % [label, float(ctx.inverted_t)])
		rows.append(row)
	var metrics := {}
	for row in rows:
		if row.case == "50pct" or row.case == "100pct":
			metrics["height_change_10_s_%s_m" % row.case] = row.height_change_10_s_m
			metrics["path_angle_end_%s_deg" % row.case] = row.path_angle_end_deg
			metrics["inverted_at_%s_s" % row.case] = row.inverted_at_s
	return ft._result(rows.size() == 5 and rows.all(func(r): return r.completed), metrics, notes, { table = rows })


## Level speed at which the trim sweep needs this throttle (linear between its rows), NAN outside the swept bracket.
static func _level_speed_at(ft, throttle: float) -> float:
	var table: Array = ft.results.get("trim_sweep", {}).get("table", [])
	for i in range(1, table.size()):
		var a: Dictionary = table[i - 1]
		var b: Dictionary = table[i]
		var ta: float = float(a.throttle)
		var tb: float = float(b.throttle)
		if (ta <= throttle and throttle <= tb) or (tb <= throttle and throttle <= ta):
			if tb == ta:
				return float(a.speed_mps)
			return lerpf(float(a.speed_mps), float(b.speed_mps), (throttle - ta) / (tb - ta))
	return NAN


## Constant-speed climb angle the thrust excess at the trim speed predicts: sin γ = (T(θ, V_trim) − T_trim) / W, with
## the steady engine speed of the session's own propulsion law. NAN when that law has no steady point there.
static func _energy_climb_angle(ft, throttle: float) -> float:
	var start: Dictionary = ft.session.start
	var s0: PackedFloat64Array = start.get("state", PackedFloat64Array())
	if s0.size() < RB.SIZE or not start.get("ok", false):
		return NAN
	var rho: float = ft.session.air_density(s0)
	var charge: float = ft.session.engine_charge_ratio(s0)
	var prop: Dictionary = ft.model.propulsion
	var v_air := PackedFloat64Array([s0[RB.VEL], s0[RB.VEL + 1], s0[RB.VEL + 2]])
	var t_trim := _steady_thrust(prop, v_air, float(start.throttle), rho, charge)
	var t_new := _steady_thrust(prop, v_air, throttle, rho, charge)
	if not is_finite(t_trim) or not is_finite(t_new):
		return NAN
	var sample: Dictionary = ft.session.mass_properties()
	var mass: float = float(sample.get("mass_kg", ft.model.mass_kg)) if sample.get("ok", true) else float(ft.model.mass_kg)
	return rad_to_deg(asin(clampf((t_new - t_trim) / (mass * ft.G), -1.0, 1.0)))


static func _steady_thrust(prop: Dictionary, v_air: PackedFloat64Array, throttle: float, rho: float, charge: float) -> float:
	var axis: PackedFloat64Array = Propulsion.axis(prop)
	var u: float = v_air[0] * axis[0] + v_air[1] * axis[1] + v_air[2] * axis[2]
	var rpm: float = Propulsion.steady_rpm(throttle, u, prop, rho, charge)
	if not is_finite(rpm):
		return NAN
	return Propulsion.loads(v_air, rpm, prop, rho)[0]
