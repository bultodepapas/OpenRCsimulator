# FT-04 (card v4): field tests of the standard flight-test card, on the field's runway with the landing test's geometry
# (threshold 15 m north of the field origin at 45 m west, runway east, aim 10 m past the threshold, gear down; qualified
# runway aircraft only). Each function takes the runner (flight_test.gd) and returns its { valid, metrics, notes }
# result. Model predictions, not physical validation.
extends RefCounted

const P := preload("pilot.gd")
const RB := preload("res://physics/rigid_body.gd")

const DT := 1.0 / 240.0
const THRESHOLD_NORTH := 15.0
const THRESHOLD_EAST := -45.0
const AIM_EAST := THRESHOLD_EAST + 10.0
const RUNWAY_HEADING := PI / 2.0


## Largest |stick| the pilot itself commanded on an axis from tick `from` on.
static func _peak_from(ctx: Dictionary, axis: String, from: int) -> float:
	var raw: PackedFloat64Array = ctx.get("raw_" + axis, PackedFloat64Array())
	var peak := 0.0
	for i in range(from, raw.size()):
		peak = maxf(peak, absf(raw[i]))
	return peak


static func _skipped(ft) -> Dictionary:
	return ft._result(false, {}, ["no qualified runway start for this aircraft"], { skipped = true })


## Dead-stick landing: first the engine-off glide at 1.4 Vs (cut at the start, speed held 20 s) gives this airplane's own
## glide angle; then an approach from 30 m on that path, aimed 10 m past the threshold, engine cut at the start, the
## elevator flying the path (the landing law, so the speed floats around 1.4 Vs), the flare one second of glide sink
## above the wheels, no brakes. Where it touches down against the aim, how fast and how hard.
static func dead_stick_landing(ft) -> Dictionary:
	if not ft.FlightSession.runway_aircraft_supported(ft.aircraft_id):
		return _skipped(ft)
	var v_glide: float = 1.4 * ft.vs
	var glide: Dictionary = ft._fly("dead_stick_landing_glide", { speed = v_glide, altitude = ft.HIGH }, 20.0, func(_t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		if not ctx.has("engine_out"):
			ctx.engine_out = ft._cut_engine()
		var k := P.schedule(s, ft.v_start)
		return { roll = P.bank(s, 0.0, k), pitch = P.hold_speed(s, v_glide, k, ctx, DT), yaw = P.ball(s, k, ctx, DT), throttle = 0.0 })
	if not glide.ok:
		return ft._failed(glide)
	var gtrace: RefCounted = glide.trace
	var r10: int = ft._row_at(gtrace, 10.0)
	var sink: float = -ft._slope(gtrace, "alt_m", r10, gtrace.row_count())
	var v_mean: float = ft._mean(ft._col(gtrace, "speed_mps", r10))
	if not (sink > 0.0) or glide.crashed != "":
		return ft._result(false, { glide_sink_mps = snappedf(sink, 0.01) }, ["the engine-off glide does not descend: " + glide.crashed])
	var ratio: float = sqrt(maxf(v_mean * v_mean - sink * sink, 0.0)) / sink
	var gamma := atan(1.0 / ratio)
	var h0 := 30.0
	var flare_h := clampf(sink * 1.0, 0.5, 3.0)
	var flight: Dictionary = ft._fly("dead_stick_landing", { speed = v_glide, altitude = h0, north = THRESHOLD_NORTH, east = AIM_EAST - h0 / tan(gamma), gear_down = true, floor = -INF }, 90.0,
			func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
		if not ctx.has("engine_out"):
			ctx.engine_out = ft._cut_engine()
		var k := P.schedule(s, ft.v_start)
		var h: float = ft._wheel_height(s)
		var c := { roll = P.bank(s, 0.0, k), yaw = P.ground_heading(s, RUNWAY_HEADING), throttle = 0.0, pitch = 0.0 }
		if not ctx.has("td_t") and ft._wheels_down(s) > 0:
			ctx.td_t = t
			ctx.td_sink = -P.climb_rate(s)
			ctx.td_v = P.speed(s)
			ctx.td_east = s[RB.POS + 1]
			ctx.td_pitch = P.euler(s)[1]
		if not ctx.has("td_t"):
			ctx.min_v = minf(float(ctx.get("min_v", INF)), P.speed(s))
			ctx.max_v = maxf(float(ctx.get("max_v", -INF)), P.speed(s))
			c.pitch = P.approach_pitch(s, h, (AIM_EAST - s[RB.POS + 1]) * tan(gamma), v_glide, gamma, ft.a1, k, ctx) if h > flare_h else P.flare(s, h, ft.a1, k, ctx)
		else:
			c.pitch = P.pitch(s, float(ctx.td_pitch), 1.0, ctx, DT) if P.speed(s) > 0.7 * ft.vs else clampf((0.7 * ft.vs - P.speed(s)) / 3.0, 0.0, 1.0)
			if t > float(ctx.td_t) + 0.3 and ft._wheels_down(s) == 0 and h > 0.3:
				ctx.bounced = true
		return c, \
		func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> bool:
			if ctx.has("td_t") and P.speed(s) < 1.0:
				ctx.stop_t = t
				ctx.stop_east = s[RB.POS + 1]
				return true
			return false)
	if not flight.ok:
		return ft._failed(flight)
	var ctx: Dictionary = flight.ctx
	var metrics := { engine_out = str(ctx.get("engine_out", "")), glide_speed_mps = snappedf(v_mean, 0.01), glide_sink_mps = snappedf(sink, 0.01),
		glide_ratio = snappedf(ratio, 0.01), glide_path_deg = snappedf(rad_to_deg(gamma), 0.1), start_distance_to_threshold_m = snappedf(THRESHOLD_EAST - (AIM_EAST - h0 / tan(gamma)), 0.1) }
	if not ctx.has("td_t"):
		return ft._result(false, metrics, ["no touchdown " + flight.crashed])
	var td_x: float = float(ctx.td_east) - THRESHOLD_EAST
	var on_runway: bool = td_x > -5.0 and td_x < 100.0
	var notes := []
	if not on_runway:
		notes.append("touchdown %.0f m from the threshold, off the 100 m runway" % td_x)
	if flight.crashed != "":
		notes.append(flight.crashed)
	metrics.merge({ approach_min_speed_mps = snappedf(float(ctx.get("min_v", NAN)), 0.01), approach_max_speed_mps = snappedf(float(ctx.get("max_v", NAN)), 0.01),
		touchdown_speed_mps = snappedf(ctx.td_v, 0.01), touchdown_speed_vs = snappedf(float(ctx.td_v) / ft.vs, 0.01), touchdown_sink_mps = snappedf(ctx.td_sink, 0.01),
		touchdown_pitch_deg = snappedf(rad_to_deg(ctx.td_pitch), 0.1), touchdown_past_threshold_m = snappedf(td_x, 0.1),
		touchdown_past_aim_m = snappedf(float(ctx.td_east) - AIM_EAST, 0.1), bounced = ctx.get("bounced", false),
		rollout_m = snappedf(float(ctx.get("stop_east", NAN)) - float(ctx.td_east), 0.1), flare_height_m = snappedf(flare_h, 0.01) })
	return ft._result(on_runway and flight.crashed == "" and str(ctx.get("engine_out", "")) != "", metrics, notes)


## Go-around (balked landing) on the landing test's approach: at 3 m above the runway the throttle goes to full, either
## slammed in 0.3 s or eased in over 2 s; the wings held level, the runway heading held with the rudder against the
## torque and propeller effects, and the elevator holding 1.3 Vs so the airplane climbs as its thrust allows. Whether it
## touches, how far it sinks, how much it yaws and rolls, and how long it takes to climb to 15 m.
static func go_around(ft) -> Dictionary:
	if not ft.FlightSession.runway_aircraft_supported(ft.aircraft_id):
		return _skipped(ft)
	var rows := []
	var notes := []
	var v_app: float = 1.3 * ft.vs
	var gamma := deg_to_rad(4.0)
	var h0 := 30.0
	for named in [["fast", 0.3], ["slow", 2.0]]:
		var ramp: float = named[1]
		var flight: Dictionary = ft._fly("go_around", { speed = v_app, altitude = h0, north = THRESHOLD_NORTH, east = AIM_EAST - h0 / tan(gamma), gear_down = true, floor = -INF }, 60.0,
				func(t: float, s: PackedFloat64Array, ctx: Dictionary) -> Dictionary:
			ctx.suffix = str(named[0])
			var k := P.schedule(s, ft.v_start)
			var h: float = ft._wheel_height(s)
			var c := { roll = P.bank(s, 0.0, k), yaw = P.ground_heading(s, RUNWAY_HEADING) }
			if not ctx.has("ga_t"):
				if h > 3.0:
					c.pitch = P.approach_pitch(s, h, (AIM_EAST - s[RB.POS + 1]) * tan(gamma), v_app, gamma, ft.a1, k, ctx)
					c.throttle = P.approach_throttle(s, v_app, float(ctx.start_throttle), ctx)
					ctx.last_throttle = c.throttle
					return c
				ctx.ga_t = t
				ctx.ga_h = h
				ctx.ga_throttle = float(ctx.get("last_throttle", ctx.start_throttle))
				ctx.erase("speed_i")
				ctx.erase("pitch_i")
			var since: float = t - float(ctx.ga_t)
			ctx.min_h = minf(float(ctx.get("min_h", INF)), h)
			ctx.touched = ctx.get("touched", false) or ft._wheels_down(s) > 0
			ctx.max_bank = maxf(float(ctx.get("max_bank", 0.0)), absf(P.euler(s)[2]))
			ctx.max_heading = maxf(float(ctx.get("max_heading", 0.0)), absf(wrapf(P.euler(s)[0] - RUNWAY_HEADING, -PI, PI)))
			if not ctx.has("climb_t") and h >= 15.0:
				ctx.climb_t = t
			c.pitch = P.hold_speed(s, v_app, k, ctx, DT)
			c.throttle = lerpf(float(ctx.ga_throttle), 1.0, clampf(since / ramp, 0.0, 1.0))
			return c, \
			func(t: float, _s: PackedFloat64Array, ctx: Dictionary) -> bool:
				return ctx.has("ga_t") and (t > float(ctx.ga_t) + 20.0 or (ctx.has("climb_t") and t > float(ctx.climb_t) + 2.0)))
		if not flight.ok:
			notes.append("%s: %s" % [named[0], flight.message])
			continue
		var ctx: Dictionary = flight.ctx
		var trace: RefCounted = flight.trace
		if not ctx.has("ga_t"):
			notes.append("%s: never reached 3 m on the approach %s" % [named[0], flight.crashed])
			rows.append({ case = named[0], completed = false })
			continue
		var row := { case = named[0], throttle_ramp_s = ramp, go_around_height_m = snappedf(float(ctx.ga_h), 0.01), throttle_at_go_around = snappedf(float(ctx.ga_throttle), 0.001),
			min_wheel_height_m = snappedf(float(ctx.get("min_h", NAN)), 0.01), touched = ctx.get("touched", false),
			max_bank_deg = snappedf(rad_to_deg(float(ctx.get("max_bank", 0.0))), 0.1), max_heading_error_deg = snappedf(rad_to_deg(float(ctx.get("max_heading", 0.0))), 0.1),
			peak_aileron_stick = snappedf(_peak_from(ctx, "roll", roundi(float(ctx.ga_t) * 240.0)), 0.001),
			peak_rudder_stick = snappedf(_peak_from(ctx, "yaw", roundi(float(ctx.ga_t) * 240.0)), 0.001),
			time_to_15_m_s = snappedf(float(ctx.get("climb_t", NAN)) - float(ctx.ga_t), 0.01),
			climb_rate_after_15_m_mps = snappedf(ft._slope(trace, "alt_m", ft._row_at(trace, float(ctx.get("climb_t", 0.0))), trace.row_count()), 0.01) if ctx.has("climb_t") else NAN }
		row.completed = ctx.has("climb_t") and flight.crashed == ""
		if not row.completed:
			notes.append("%s: %s" % [named[0], flight.crashed if flight.crashed != "" else "not at 15 m in 20 s"])
		elif row.touched:
			notes.append("%s: the wheels touched during the go-around" % named[0])
		rows.append(row)
	return ft._result(rows.size() == 2 and rows.all(func(r): return r.completed), {}, notes, { table = rows })
