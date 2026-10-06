# P51-08: the P-51D 1/4 flown through its performance envelope in the real session loop (aero, shaft-balance
# engine, slipstream, gear, crash checks), by simple closed-loop pilots: parked on the grass runway, the takeoff with
# and without rudder, climb, maximum level speed, idle glide, 1-g stalls power off and on, a steep turn, the roll
# rate across speeds, and an approach with a flare and rollout. The bands come from research/p51/p51-08/envelope.md
# (expected values with their sources); this test checks that the simulation stays inside them.
# Run: godot --headless --path . --script res://tests/test_p51_envelope.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Ground := preload("res://physics/ground_contact.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const FieldLoader := preload("res://data/field_loader.gd")

const DATA := "res://data/aircraft/p51d_mustang_120.json"
const G := 9.80665
## The field's runway (app/data/fields): east-west, centre 15 m north, 100 m long. Take off towards the east.
const THRESHOLD := [15.0, -45.0]

var _failures := 0
var _count := 0
var session: Node
var model: Dictionary
var vs1g := 0.0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	session = FlightSession.new()
	session.setup(DATA)
	root.add_child(session)
	session.input_enabled = false
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("data loads, trims, and the field's surfaces apply", session.aircraft.ok and session.start.get("ok", false) and session.set_field(field.get("field", field)),
		str(session.start.get("message", "")) + " " + session.surface_error)
	if _failures > 0:
		_finish()
		return
	model = session.aircraft.model
	vs1g = sqrt(2.0 * model.mass_kg * G / (1.225 * model.reference.S * model.envelope.CL_max))
	print("info mass %.2f kg, 1-g stall (CL_max %.2f) %.1f m/s" % [model.mass_kg, model.envelope.CL_max, vs1g])
	_ground()
	_takeoff()
	_performance()
	_stalls()
	_handling()
	_landing()
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


# --- State helpers ------------------------------------------------------------------------------------------------

func _euler(s: PackedFloat64Array) -> PackedFloat64Array: # [yaw, pitch, roll]
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))


func _speed(s: PackedFloat64Array) -> float:
	return sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)


func _climb_rate(s: PackedFloat64Array) -> float:
	return -M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]), M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))[2]


func _alpha(s: PackedFloat64Array) -> float:
	return atan2(s[RB.VEL + 2], s[RB.VEL])


func _beta(s: PackedFloat64Array) -> float:
	return atan2(s[RB.VEL + 1], sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 2] ** 2))


func _wheels_down(s: PackedFloat64Array) -> int:
	var n := 0
	for c in Ground.compressions(s, model.landing_gear):
		n += int(c > 0.0)
	return n


# --- Flying -------------------------------------------------------------------------------------------------------

## Starts the session from `state` with the engine at `rpm` (0 = stopped) and servos at the given commands, trims
## kept from the in-air trim (a pilot's radio trims). Then flies `seconds`, calling pilot(t, s) -> { roll, pitch, yaw,
## throttle } every tick and ticking the session like the game (crash checks included). Returns { rows (Array of
## { t, s, rpm, cmd }), crashed (String or ""), state }; rows are sampled every `every` ticks.
func fly(state: PackedFloat64Array, rpm: float, seconds: float, pilot: Callable, every := 12) -> Dictionary:
	session.reset()
	session.engine_running = rpm > 0.0
	session.commands = { roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0 }
	var first: Dictionary = pilot.call(0.0, state)
	session.commands = first
	session.sim.inputs = session._inputs()
	var i: PackedFloat64Array = session.sim.inputs
	session.sim.aux = PackedFloat64Array([rpm, i[0], i[1], i[2]])
	session.sim.reset(state)
	session.sim.set_paused(false)
	var dt: float = session.sim.dt()
	var rows := []
	var crashed := ""
	for k in roundi(seconds / dt):
		var s: PackedFloat64Array = session.sim.state
		var t := k * dt
		var c: Dictionary = pilot.call(t, s)
		session.commands = { roll = clampf(c.roll, -1.0, 1.0), pitch = clampf(c.pitch, -1.0, 1.0), yaw = clampf(c.yaw, -1.0, 1.0), throttle = clampf(c.throttle, 0.0, 1.0) }
		session.sim.inputs = session._inputs()
		session._physics_process(dt)
		if not session.crash.is_empty():
			crashed = session.pause_reason
			break
		if k % every == 0:
			rows.append({ t = t, s = s.duplicate(), rpm = session.sim.aux[0], cmd = session.commands.duplicate() })
		session.sim.step()
	return { rows = rows, crashed = crashed, state = session.sim.state.duplicate() }


## Parked at the runway threshold heading east, all three wheels on the grass, settled for 3 s with the engine at
## idle and the stick held back (the tail wheel stays planted). Returns the settled state.
func park() -> PackedFloat64Array:
	var gear: Dictionary = model.landing_gear
	var main: PackedFloat64Array = gear.contacts[0].position
	var tail: PackedFloat64Array = gear.contacts[2].position
	var pitch := atan2(main[2] - tail[2], main[0] - tail[0]) # nose up: the tail wheel is higher in body z
	var down := -(-main[0] * sin(pitch) + main[2] * cos(pitch)) + 0.005
	var s := RB.make_state(M.v3(THRESHOLD[0], THRESHOLD[1], down), M.v3(0, 0, 0), M.q_from_euler(PI / 2.0, pitch, 0.0), M.v3(0, 0, 0))
	var idle: float = Propulsion.steady_rpm(0.0, 0.0, model.propulsion, 1.225)
	var settle := fly(s, idle, 3.0, func(_t, _s): return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0 })
	var out: PackedFloat64Array = settle.state
	out[RB.POS] = THRESHOLD[0]
	out[RB.POS + 1] = THRESHOLD[1]
	for k in 3:
		out[RB.VEL + k] = 0.0
		out[RB.RATE + k] = 0.0
	return out


## Trimmed level flight at `speed` and `altitude` (m), heading east over the field. Returns { state, rpm, throttle }.
func airborne(speed: float, altitude: float) -> Dictionary:
	var t: Dictionary = session.trim_at(speed, "level")
	assert(t.ok, "trim at %.1f m/s: %s" % [speed, t.message])
	session.set_start_altitude(altitude)
	return { state = session.start.state.duplicate(), rpm = float(t.rpm), throttle = float(t.throttle) }


## Pilot building blocks (pilot units: +roll right, +pitch nose up, +yaw nose right).
func wings_level(s: PackedFloat64Array, bank := 0.0) -> float:
	return 2.0 * (bank - _euler(s)[2]) - 0.3 * s[RB.RATE]


func hold_heading(s: PackedFloat64Array, heading: float) -> float:
	return 3.0 * wrapf(heading - _euler(s)[0], -PI, PI) - 1.0 * s[RB.RATE + 2]


func hold_pitch(s: PackedFloat64Array, pitch: float) -> float:
	return 3.0 * (pitch - _euler(s)[1]) - 0.6 * s[RB.RATE + 1]


## Elevator for an airspeed (pitch up when too fast), through a pitch-attitude inner loop.
func hold_speed(s: PackedFloat64Array, speed: float, pitch_trim: float) -> float:
	return hold_pitch(s, clampf(pitch_trim + 0.04 * (_speed(s) - speed), -0.5, 0.5))


## Elevator for an altitude (m), through a pitch-attitude inner loop.
func hold_altitude(s: PackedFloat64Array, altitude: float) -> float:
	return hold_pitch(s, clampf(0.02 * (altitude + s[RB.POS + 2]) - 0.03 * _climb_rate(s), -0.35, 0.35))


# --- Ground -------------------------------------------------------------------------------------------------------

var parked := PackedFloat64Array()


func _ground() -> void:
	parked = park()
	var e := _euler(parked)
	var static_rpm: float = Propulsion.steady_rpm(1.0, 0.0, model.propulsion, 1.225)
	var idle_rpm: float = Propulsion.steady_rpm(0.0, 0.0, model.propulsion, 1.225)
	print("info parked: pitch %.1f°, %d wheels down; static rpm %.0f, idle %.0f" % [rad_to_deg(e[1]), _wheels_down(parked), static_rpm, idle_rpm])
	_check("parked: sits on all three wheels at its three-point attitude (12-15°)", _wheels_down(parked) == 3 and rad_to_deg(e[1]) > 12.0 and rad_to_deg(e[1]) < 15.0, "%.1f°" % rad_to_deg(e[1]))
	_check("static full-throttle rpm 4700-5600 (research: 4-blade 26x12 on a DA-120, 5000-5400)", static_rpm > 4700.0 and static_rpm < 5600.0, "%.0f rpm" % static_rpm)
	var idle := fly(parked, idle_rpm, 10.0, func(_t, _s): return { roll = 0.0, pitch = 1.0, yaw = 0.0, throttle = 0.0 })
	var moved: float = idle.state[RB.POS + 1] - parked[RB.POS + 1]
	var idle_thrust: float = Propulsion.loads(M.v3(0, 0, 0), idle_rpm, model.propulsion, 1.225)[0]
	# A 26 in 4-blade at 1400 rpm pushes ~19 N against ~16 N of rolling resistance on the grass strip: it creeps, as
	# big warbirds do at idle (no brakes are simulated); it must not run away.
	print("info idle: %.1f N of thrust, %.1f m rolled in 10 s, %.2f m/s" % [idle_thrust, moved, _speed(idle.state)])
	_check("idle on the grass runway, stick back: at most a slow creep (below 1.5 m/s after 10 s), no crash", idle.crashed == "" and _speed(idle.state) < 1.5, "%.2f m/s" % _speed(idle.state))


# --- Takeoff ------------------------------------------------------------------------------------------------------

## Takeoff pilot: throttle up over 2 s; stick back below 40 % of the stall speed (tail wheel planted), then the tail
## comes up to a level attitude, rotation at 1.25 Vs to 8°; ailerons hold the wings level; rudder holds the runway
## heading unless `rudder` is false. Returns the summary.
func takeoff(rudder: bool, seconds := 12.0) -> Dictionary:
	var info := { liftoff_t = -1.0, liftoff_x = 0.0, liftoff_v = 0.0, max_dev = 0.0, max_yaw = 0.0, max_bank = 0.0, rudder_used = 0.0, heading_at_tail_up = 0.0, tail_up_t = -1.0 }
	var x0: float = parked[RB.POS + 1]
	var pilot := func(t: float, s: PackedFloat64Array) -> Dictionary:
		var v := _speed(s)
		var c := { roll = wings_level(s), yaw = hold_heading(s, PI / 2.0) if rudder else 0.0, throttle = clampf(t / 2.0, 0.0, 1.0) }
		if v < 0.4 * vs1g:
			c.pitch = 0.6
		elif v < 1.25 * vs1g:
			c.pitch = hold_pitch(s, deg_to_rad(1.0))
			if info.tail_up_t < 0.0 and _euler(s)[1] < deg_to_rad(4.0):
				info.tail_up_t = t
		else:
			c.pitch = hold_pitch(s, deg_to_rad(8.0))
		if _wheels_down(s) == 0 and info.liftoff_t < 0.0:
			info.liftoff_t = t
			info.liftoff_x = s[RB.POS + 1] - x0
			info.liftoff_v = v
		var dev := absf(wrapf(_euler(s)[0] - PI / 2.0, -PI, PI))
		if info.liftoff_t < 0.0:
			info.max_dev = maxf(info.max_dev, absf(s[RB.POS] - THRESHOLD[0]))
			info.max_yaw = maxf(info.max_yaw, dev)
			info.max_bank = maxf(info.max_bank, absf(_euler(s)[2]))
			info.rudder_used = maxf(info.rudder_used, c.yaw)
		return c
	var r := fly(parked, Propulsion.steady_rpm(0.0, 0.0, model.propulsion, 1.225), seconds, pilot)
	info.crashed = r.crashed
	info.state = r.state
	return info


func _takeoff() -> void:
	var free := takeoff(false, 3.0)
	var heading_change := rad_to_deg(wrapf(_euler(free.state)[0] - PI / 2.0, -PI, PI))
	print("info takeoff without rudder: heading %+.1f° after 3 s, crashed '%s'" % [heading_change, free.crashed])
	_check("takeoff run without rudder swings LEFT (torque, slipstream swirl, P-factor, gyro)", heading_change < -3.0, "%+.1f°" % heading_change)
	var to := takeoff(true)
	print("info takeoff: liftoff %.1f s, %.0f m, %.1f m/s (Vs %.1f); tail up %.1f s; max heading error %.1f°, runway offset %.1f m, bank %.1f°, max right rudder %.2f" %
		[to.liftoff_t, to.liftoff_x, to.liftoff_v, vs1g, to.tail_up_t, rad_to_deg(to.max_yaw), to.max_dev, rad_to_deg(to.max_bank), to.rudder_used])
	_check("takeoff with rudder: no crash, airborne within 10 s", to.crashed == "" and to.liftoff_t > 0.0 and to.liftoff_t < 10.0, "%s %.1f s" % [to.crashed, to.liftoff_t])
	_check("ground roll 15-60 m (research: 20-50 m class estimate; Top Flite review ~60 ft for a smaller model)", to.liftoff_x > 15.0 and to.liftoff_x < 60.0, "%.0f m" % to.liftoff_x)
	_check("lift-off between 1.05 and 1.5 Vs (rotation at 1.25 Vs)", to.liftoff_v > 1.05 * vs1g and to.liftoff_v < 1.5 * vs1g, "%.1f m/s" % to.liftoff_v)
	_check("the pilot needs right rudder (> 20 %) and keeps the heading within 10° and on the 12 m strip", to.rudder_used > 0.2 and rad_to_deg(to.max_yaw) < 10.0 and to.max_dev < 6.0,
		"rudder %.2f, %.1f°, %.1f m" % [to.rudder_used, rad_to_deg(to.max_yaw), to.max_dev])


# --- Performance --------------------------------------------------------------------------------------------------

func _mean_rate(rows: Array, t0: float, t1: float) -> float:
	var first := {}
	var last := {}
	for r in rows:
		if r.t >= t0 and first.is_empty():
			first = r
		if r.t <= t1:
			last = r
	return (-last.s[RB.POS + 2] + first.s[RB.POS + 2]) / (last.t - first.t)


func _performance() -> void:
	# Maximum level speed: full throttle from 30 m/s, altitude and heading held, 40 s.
	var a := airborne(30.0, 100.0)
	var vmax := fly(a.state, a.rpm, 40.0, func(_t, s): return { roll = wings_level(s), pitch = hold_altitude(s, 100.0), yaw = hold_heading(s, PI / 2.0), throttle = 1.0 })
	var rows: Array = vmax.rows
	var v_end := _speed(vmax.state)
	var v_5 := _speed(rows[rows.size() - 100].s)
	print("info full-throttle level: %.1f m/s (%.0f km/h, %.0f mph) at %.0f rpm, still accelerating %.2f m/s over the last 5 s" % [v_end, v_end * 3.6, v_end * 2.237, rows[-1].rpm, v_end - v_5])
	# Band: Mejzlik's 26x12 tables reach zero thrust at J 0.76-0.81 (an aerodynamic pitch near 20 in, not the nominal
	# 12), so the unloaded propeller is no limit near 40 m/s; a Top Flite Giant owner expected ~115 mph (51 m/s) flat
	# out (research synthesis, P51-09). Gear down (retracts are not simulated).
	_check("maximum level speed 38-56 m/s (gear down; P51-09 envelope)", vmax.crashed == "" and v_end > 38.0 and v_end < 56.0, "%.1f m/s" % v_end)
	_check("the propeller unloads in flight: full-throttle rpm at top speed above the static rpm", rows[-1].rpm > Propulsion.steady_rpm(1.0, 0.0, model.propulsion, 1.225), "%.0f rpm" % rows[-1].rpm)
	# Climb at 1.4 Vs, full throttle, speed held by the elevator.
	var vc := 1.4 * vs1g
	a = airborne(vc, 60.0)
	var climb := fly(a.state, a.rpm, 15.0, func(_t, s): return { roll = wings_level(s), pitch = hold_speed(s, vc, deg_to_rad(20.0)), yaw = hold_heading(s, PI / 2.0), throttle = 1.0 })
	var roc := _mean_rate(climb.rows, 6.0, 14.0)
	print("info full-throttle climb at %.1f m/s: %.1f m/s (%.0f°)" % [vc, roc, rad_to_deg(asin(clampf(roc / vc, -1.0, 1.0)))])
	_check("full-throttle climb at 1.4 Vs: 5-14 m/s (thrust/weight 1.1 static)", climb.crashed == "" and roc > 5.0 and roc < 14.0, "%.1f m/s" % roc)
	# Idle glide at 1.4 Vs: the windmilling 4-blade brakes.
	a = airborne(vc, 150.0)
	var glide := fly(a.state, a.rpm, 20.0, func(_t, s): return { roll = wings_level(s), pitch = hold_speed(s, vc, deg_to_rad(-6.0)), yaw = hold_heading(s, PI / 2.0), throttle = 0.0 })
	var sink := -_mean_rate(glide.rows, 8.0, 18.0)
	print("info idle glide at %.1f m/s: sink %.2f m/s, L/D %.1f, propeller at %.0f rpm" % [vc, sink, vc / sink, glide.rows[-1].rpm])
	var clean := 1.0 / (2.0 * sqrt(float(model.aero.CD0) * float(model.aero.k_induced)))
	_check("idle glide L/D 4-8.5: below the clean airframe's %.1f (windmilling propeller drag)" % clean, glide.crashed == "" and vc / sink > 4.0 and vc / sink < minf(8.5, clean), "%.1f" % (vc / sink))


# --- Stalls -------------------------------------------------------------------------------------------------------

## Stall: the pilot holds the altitude with the elevator (power off: the airplane slows at 1 g) or raises the nose
## 2°/s from 10° (power on), ailerons level, feet off the rudder, until the wing quits: the stall is the moment the
## airplane sinks 2 m/s or banks 20° while the stick is coming back. The pilot then holds full up for 1.5 s and
## recovers (stick forward to neutral, wings level, power as set). Returns { v_stall, bank (largest in the 1.5 s,
## + right), lost (altitude lost from the stall to the end of the recovery, m), crashed }.
func stall(throttle: float, power_on: bool) -> Dictionary:
	var a := airborne(1.4 * vs1g, 150.0)
	var info := { v_stall = -1.0, t_stall = -1.0, bank = 0.0, h_stall = 0.0, h_min = 1e9, v_min = 1e9 }
	var r := fly(a.state, a.rpm, 20.0, func(t: float, s: PackedFloat64Array) -> Dictionary:
		var h := -s[RB.POS + 2]
		info.v_min = minf(info.v_min, _speed(s)) if info.t_stall < 0.0 else info.v_min
		if info.t_stall < 0.0 and t > 1.0 and (_climb_rate(s) < -2.0 or absf(_euler(s)[2]) > deg_to_rad(20.0)):
			info.t_stall = t
			info.v_stall = info.v_min
			info.h_stall = h
		var c := { roll = wings_level(s), pitch = 0.0, yaw = 0.0, throttle = throttle }
		if info.t_stall < 0.0:
			if power_on:
				c.pitch = hold_pitch(s, deg_to_rad(minf(10.0 + 2.0 * t, 45.0)))
			else:
				c.pitch = hold_pitch(s, clampf(0.05 * (150.0 - h) + 0.08 * -_climb_rate(s), -0.3, 0.6))
		elif t < info.t_stall + 1.5:
			c.pitch = 1.0
			c.roll = 0.0
			if absf(_euler(s)[2]) > absf(info.bank):
				info.bank = _euler(s)[2]
		else:
			c.pitch = clampf(hold_pitch(s, 0.0), -0.3, 0.3) if _speed(s) < 1.3 * vs1g else hold_pitch(s, deg_to_rad(5.0))
			info.h_min = minf(info.h_min, h)
		return c)
	info.crashed = r.crashed
	info.lost = info.h_stall - info.h_min
	return info


func _stalls() -> void:
	var off := stall(0.0, false)
	print("info power-off stall: %.1f m/s (Vs %.1f), wing drop to %+.0f° bank in 1.5 s at full up, %.0f m lost in the recovery" % [off.v_stall, vs1g, rad_to_deg(off.bank), off.lost])
	_check("power-off 1-g stall within 0.85-1.1 Vs", off.v_stall > 0.85 * vs1g and off.v_stall < 1.1 * vs1g, "%.1f m/s" % off.v_stall)
	_check("power-off stall recovers (stick forward, wings level) within 40 m, no crash", off.crashed == "" and off.lost < 40.0, "%.0f m" % off.lost)
	var on := stall(0.5, true)
	print("info power-on (50 %%) stall: %.1f m/s, wing drop to %+.0f° bank in 1.5 s at full up, %.0f m lost" % [on.v_stall, rad_to_deg(on.bank), on.lost])
	_check("power-on stall is slower than power-off (thrust and slipstream)", on.v_stall > 0.0 and on.v_stall < off.v_stall, "%.1f vs %.1f m/s" % [on.v_stall, off.v_stall])
	_check("power-on stall drops the LEFT wing (torque and P-factor; RC reports: early lift-off stalls the left wing)", on.bank < deg_to_rad(-15.0), "%+.0f°" % rad_to_deg(on.bank))
	_check("power-on stall recovers within 60 m, no crash", on.crashed == "" and on.lost < 60.0, "%.0f m" % on.lost)


# --- Handling across speeds ---------------------------------------------------------------------------------------

func _handling() -> void:
	var rates := []
	for v in [1.3 * vs1g, 25.0, 35.0]:
		var a := airborne(v, 120.0)
		var t_peak := { p = 0.0 }
		var r := fly(a.state, a.rpm, 2.0, func(t: float, s: PackedFloat64Array) -> Dictionary:
			t_peak.p = maxf(t_peak.p, s[RB.RATE])
			var beta := _beta(s)
			return { roll = 1.0 if t > 0.1 else 0.0, pitch = 0.0, yaw = clampf(10.0 * beta, -1.0, 1.0), throttle = a.throttle })
		rates.append(rad_to_deg(t_peak.p))
	print("info full-aileron roll rate (high rate, coordinated) at %.1f / 25 / 35 m/s: %.0f / %.0f / %.0f °/s" % [1.3 * vs1g, rates[0], rates[1], rates[2]])
	_check("roll rate grows with airspeed and stays scale-like (60-250 °/s)", rates[0] < rates[1] and rates[1] < rates[2] and rates[0] > 60.0 and rates[2] < 250.0, str(rates))
	# 60° level turn at 30 m/s, full throttle: 2 g sustained, altitude held.
	var a := airborne(30.0, 120.0)
	var turn := fly(a.state, a.rpm, 10.0, func(_t, s): return { roll = wings_level(s, deg_to_rad(60.0)), pitch = hold_altitude(s, 120.0), yaw = clampf(10.0 * _beta(s), -1.0, 1.0), throttle = 1.0 })
	var v_end := _speed(turn.state)
	var lost: float = 120.0 + turn.state[RB.POS + 2]
	print("info 60° level turn from 30 m/s, full throttle: %.1f m/s after 10 s, altitude lost %.1f m" % [v_end, lost])
	_check("60° bank 2-g level turn sustained at full throttle (speed above 1.45 Vs, altitude within 8 m)", turn.crashed == "" and v_end > 1.45 * vs1g and absf(lost) < 8.0, "%.1f m/s, %.1f m" % [v_end, lost])


# --- Approach and landing -----------------------------------------------------------------------------------------

func _landing() -> void:
	var v_app := 1.3 * vs1g
	var gamma := deg_to_rad(4.0)
	var aim: float = THRESHOLD[1] - 5.0 # glide-path aim just short of the threshold: the flare floats into the runway
	var x0 := aim - 15.0 / tan(gamma)
	var a := airborne(v_app, 15.0)
	var s0: PackedFloat64Array = a.state
	s0[RB.POS] = THRESHOLD[0]
	s0[RB.POS + 1] = x0
	var info := { td_t = -1.0, td_sink = 0.0, td_v = 0.0, td_x = 0.0, bounced = false, airborne_after = 0.0, stop_x = 0.0, max_yaw = 0.0 }
	var r := fly(s0, a.rpm, 30.0, func(t: float, s: PackedFloat64Array) -> Dictionary:
		var h := -s[RB.POS + 2]
		var c := { roll = wings_level(s), yaw = hold_heading(s, PI / 2.0), throttle = 0.0, pitch = 0.0 }
		var down := _wheels_down(s)
		if info.td_t < 0.0 and down > 0:
			info.td_t = t
			info.td_sink = -_climb_rate(s)
			info.td_v = _speed(s)
			info.td_x = s[RB.POS + 1]
		if info.td_t < 0.0:
			if h > 1.2: # on the glide path: elevator on the path, throttle on the speed
				var h_path := (aim - s[RB.POS + 1]) * tan(gamma)
				c.pitch = hold_pitch(s, clampf(-gamma + 0.15 * (h_path - h) - 0.1 * _climb_rate(s) * 0.0, -0.3, 0.2))
				c.throttle = clampf(a.throttle + 0.15 * (v_app - _speed(s)), 0.0, 1.0)
			else: # flare: close the throttle, raise the nose towards the three-point attitude
				c.pitch = hold_pitch(s, deg_to_rad(10.0) * clampf(1.0 - h / 1.2, 0.3, 1.0))
		else:
			c.pitch = 1.0 # stick back on the ground: tail wheel down and steering
			if t > info.td_t + 0.3 and down == 0 and h > 0.3:
				info.bounced = true
			info.max_yaw = maxf(info.max_yaw, absf(wrapf(_euler(s)[0] - PI / 2.0, -PI, PI)))
		return c)
	info.stop_x = r.state[RB.POS + 1]
	var v_end := _speed(r.state)
	print("info landing: touchdown %.1f m/s, sink %.2f m/s, %.0f m past the threshold; bounced %s; rollout to %.1f m/s %.0f m past touchdown; heading error max %.1f°; crashed '%s'" %
		[info.td_v, info.td_sink, info.td_x - THRESHOLD[1], info.bounced, v_end, info.stop_x - info.td_x, rad_to_deg(info.max_yaw), r.crashed])
	_check("approach and flare: touchdown in the first half of the runway below 1.2 m/s sink, no crash", r.crashed == "" and info.td_t > 0.0 and info.td_sink < 1.2 and info.td_x > THRESHOLD[1] - 5.0 and info.td_x < THRESHOLD[1] + 50.0, "sink %.2f m/s at %.0f m" % [info.td_sink, info.td_x - THRESHOLD[1]])
	_check("rollout: slows below 3 m/s within 100 m, heading held within 15° (no ground loop)", v_end < 3.0 and info.stop_x - info.td_x < 100.0 and rad_to_deg(info.max_yaw) < 15.0, "%.1f m/s, %.0f m, %.1f°" % [v_end, info.stop_x - info.td_x, rad_to_deg(info.max_yaw)])
