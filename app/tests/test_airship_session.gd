# BL-07/BL-08/BL-12: the RC blimp session with the generated data on the flat fixture field. Handling sanity
# (sink when heavy, cruise, vectored climb, yaw, braking), ground start, terminal impact, admitted weather,
# exact replay of the input tape and per-tick cost. Software checks only; no physical validation is claimed.
extends SceneTree

const Session := preload("res://sim/airship/session.gd")
const M := preload("res://physics/math3d.gd")
const Data := preload("res://physics/airship/airship_data.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _session(options := {}) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	var ok: bool = s.prepare({}, options)
	_check("prepare " + str(options), ok, str(s.load_error))
	return s


func _fly(s: Node, seconds: float, sticks: PackedFloat64Array) -> bool:
	if s.paused and not s.resume(PackedFloat64Array([0.0, 0.0, 0.0, 0.0])):
		return false
	for i in int(seconds * 240.0):
		if not s.tick_once(sticks):
			return false
	return true


func _initialize() -> void:
	var loaded := Data.load_file(Session.DEFAULT_DATA)
	_check("generated data is admitted", loaded.ok, "; ".join(loaded.get("errors", [])))
	if not loaded.ok:
		_finish()
		return
	var s := _session()
	var t: Dictionary = s.telemetry()
	_check("default weigh-off is 80 g heavy", absf(float(t.heaviness_kg) - 0.08) < 1e-9, str(t.heaviness_kg))
	_check("ballast is physical (0 < ballast < max)", float(t.ballast_kg) > 0.0 and float(t.ballast_kg) < float(s.model.ballast.max_mass), str(t.ballast_kg))
	print("mass %.3f kg, ballast %.3f kg, helium %.3f kg, envelope %.3f kg, volume %.3f m3" % [s.model.mass, s.model.ballast_mass,
		s.model.gas_mass, s.model.shell_mass, s.model.envelope.volume])
	print("CG %s  CB %s" % [s.model.cg, s.model.cb])
	_check("CG below CB (pendulum stability)", float(s.model.cg[2]) > float(s.model.cb[2]), "%s vs %s" % [s.model.cg, s.model.cb])
	_check("resume refuses raised throttle", not s.resume(PackedFloat64Array([0.0, 0.0, 0.0, 0.5])))
	# Motors off, slightly heavy: gentle sink, no position hold.
	_fly(s, 8.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	t = s.telemetry()
	_check("80 g heavy, motors off: gentle sink", float(t.vertical_speed_mps) < -0.02 and float(t.vertical_speed_mps) > -0.8, "%.3f m/s" % t.vertical_speed_mps)
	# Cruise.
	s.reset()
	var started := Time.get_ticks_usec()
	_fly(s, 20.0, PackedFloat64Array([0.0, 0.0, 0.0, 1.0]))
	var per_tick := float(Time.get_ticks_usec() - started) / (20.0 * 240.0)
	t = s.telemetry()
	_check("full throttle cruise 3-10 m/s", float(t.ground_speed_mps) > 3.0 and float(t.ground_speed_mps) < 10.0, "%.2f m/s" % t.ground_speed_mps)
	_check("cruise draws plausible current", float(t.battery.current_a) > 3.0 and float(t.battery.current_a) < 20.0, "%.2f A" % t.battery.current_a)
	_check("cruise attitude stays moderate", absf(float(t.pitch_deg)) < 25.0 and absf(float(t.roll_deg)) < 15.0, "pitch %.1f roll %.1f" % [t.pitch_deg, t.roll_deg])
	print("cruise: %.2f m/s, %.1f W, AGL %.2f m, per tick %.1f us" % [t.ground_speed_mps, t.battery.power_w, t.agl_m, per_tick])
	_check("tick cost bounded (reference GDScript)", per_tick < 3000.0, "%.0f us" % per_tick)
	# Braking: full back stick vectors past vertical.
	var before := float(t.ground_speed_mps)
	_fly(s, 6.0, PackedFloat64Array([0.0, 1.0, 0.0, 1.0]))
	t = s.telemetry()
	_check("full back stick brakes", float(t.ground_speed_mps) < before * 0.6, "%.2f -> %.2f m/s" % [before, t.ground_speed_mps])
	# Vectored climb from rest.
	s.reset()
	_fly(s, 8.0, PackedFloat64Array([0.0, 0.75, 0.0, 0.8]))
	t = s.telemetry()
	_check("vectored climb", float(t.vertical_speed_mps) > 0.2 and float(t.agl_m) > 7.0, "%.2f m/s at %.1f m" % [t.vertical_speed_mps, t.agl_m])
	# Yaw with the stern thruster from rest.
	s.reset()
	var h0 := float(s.telemetry().heading_deg)
	_fly(s, 6.0, PackedFloat64Array([0.0, 0.0, 1.0, 0.0]))
	t = s.telemetry()
	var turned := fposmod(float(t.heading_deg) - h0 + 180.0, 360.0) - 180.0
	_check("right yaw turns the nose right at zero speed", turned > 10.0, "%.1f deg" % turned)
	# Exact replay of the recorded tape.
	s.reset()
	var tape := PackedFloat64Array()
	for i in 240 * 12:
		var phase := float(i) / 240.0
		tape.append_array(PackedFloat64Array([0.4 * sin(phase), 0.5 * sin(0.7 * phase), 0.6 * cos(0.3 * phase), clampf(0.3 + 0.3 * sin(0.2 * phase), 0.0, 1.0)]))
	_check("tape flight accepted", s.replay(tape))
	var first_state: PackedByteArray = s.state_snapshot().to_byte_array()
	var first_cont: PackedByteArray = s.continuous_snapshot().to_byte_array()
	var recorded: PackedFloat64Array = s.tape.duplicate()
	_check("session tape equals the flown sticks", recorded.to_byte_array() == tape.to_byte_array())
	_check("exact replay", s.replay(recorded) and s.state_snapshot().to_byte_array() == first_state \
		and s.continuous_snapshot().to_byte_array() == first_cont)
	# Ground start rests on the wheels.
	var g := _session({start = "ground"})
	var agl0 := float(g.telemetry().agl_m)
	_fly(g, 5.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	t = g.telemetry()
	_check("heavy ground start rests on the gear", g.crash.is_empty() and absf(float(t.agl_m) - agl0) < 0.03 and float(t.contact.gear_load_n) > 0.3,
		"AGL %.3f -> %.3f, gear %.2f N" % [agl0, t.agl_m, t.contact.gear_load_n])
	# Lift off by vectored thrust.
	_fly(g, 6.0, PackedFloat64Array([0.0, 0.75, 0.0, 0.8]))
	t = g.telemetry()
	_check("vectored lift-off from the wheels", float(t.agl_m) > agl0 + 0.5, "AGL %.2f m" % t.agl_m)
	# Terminal impact: dropped onto the field at 3 m/s.
	var c := _session({altitude_m = 1.2})
	var body: PackedFloat64Array = c.sim.state.duplicate()
	body[5] = 3.0
	c.sim.continuous = c.start_continuous.duplicate()
	c.sim.reset(body)
	_fly(c, 2.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	_check("fast envelope strike ends the flight", not c.crash.is_empty(), str(c.crash.get("reason", "none")))
	# Scenery obstacles of the default field: a release inside a tree or pole ends the flight on the first tick;
	# the open start does not.
	var FieldLoader = load("res://data/field_loader.gd")
	var CollisionSetup = load("res://scenery/collision_setup.gd")
	var field: Dictionary = FieldLoader.load_from().field
	var built: Dictionary = CollisionSetup.build(field)
	_check("default field obstacle inventory builds", built.ok and not built.world.proxies.is_empty(), str(built.get("errors", [])))
	var open: Node = Session.new()
	root.add_child(open)
	_check("obstacle inventory installs", open.set_collision_world(built.world))
	open.prepare(field, {})
	_fly(open, 2.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	_check("open start clear of obstacles", open.crash.is_empty(), str(open.crash.get("reason", "")))
	var pole: Dictionary = {}
	for proxy: Dictionary in built.world.proxies:
		if proxy.shape == "capsule" and float(proxy.radius) < 0.4 and float(proxy.half_length) > 1.0:
			pole = proxy
			break
	if not pole.is_empty():
		var hit: Node = Session.new()
		root.add_child(hit)
		hit.set_collision_world(built.world)
		var pilot: Dictionary = field.pilot
		var top := -(float(pole.down) - float(pole.half_length))
		hit.prepare(field, {north_offset_m = float(pole.north) - float(pilot.north), east_offset_m = float(pole.east) - float(pilot.east),
			altitude_m = maxf(0.5, top * 0.5 - 0.5), start = "air"})
		_fly(hit, 0.1, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
		_check("thin %s through the envelope is an obstacle strike" % pole.kind, str(hit.crash.get("reason", "")).begins_with("Obstacle strike"),
			str(hit.crash.get("reason", "none")))
	# Weather admission.
	var w: Node = Session.new()
	root.add_child(w)
	_check("gusty/strong wind outside the admitted domain is refused", not w.prepare({}, {wind_speed_mps = 6.0}))
	var breeze := _session({wind_speed_mps = 2.0, wind_from_deg = 270.0, heaviness_kg = 0.0})
	_fly(breeze, 6.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]))
	t = breeze.telemetry()
	_check("released in a steady breeze, drifts with the air", float(t.ground_speed_mps) > 1.7 and float(t.air_speed_mps) < 0.3,
		"ground %.2f air %.2f" % [t.ground_speed_mps, t.air_speed_mps])
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
