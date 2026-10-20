# D6e-R3: the owner's procedure in the complete flight scene (main.tscn: keyboard sampling, Home's gentle-breeze
# weather, real engine callbacks). Airborne start then a throttle setting held hands-off, and a runway takeoff flown
# as a pilot flies it (full throttle with up elevator until airborne, a 12° climb-out held with the elevator, then at
# 40 m the sticks released and the throttle brought back).
# Prints height, speed, pitch and path every 2 s. Read-only research probe; nothing is written to the tree.
# Run: <godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/scene_probe.gd" -- [--aircraft=<id,id>] [--seconds=40] [--trim=reference|cruise] [--no-airborne] [--level-off=40] [--rotate=0.35]
# --trim=cruise is Home's launch trim (D6e-R4): every airplane trimmed for level flight at 50 % throttle, in the air
# and after the runway takeoff. The default keeps the technical route's reference trim.
extends SceneTree
const Weather = preload("res://physics/wind_config.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const FlightSession = preload("res://sim/flight_session.gd")

var aircraft: PackedStringArray = ["turbo-lumber-evolution", "sebart-avanti-s-a200-p100rx", "gp-extra-300s-60", "jensen-das-ugly-stik-60"]
var seconds := 40.0
var airborne_start := "airborne" # or airborne_half_power (D6e-R3: the 50 % level trim for every airplane)
var throttles: PackedFloat64Array = [0.5, 0.3]
var runway_cases := true
var airborne_cases := true
var trim_choice := "reference" # or cruise (D6e-R4)
const CLIMB_PITCH_RAD := 0.2094 # 12°, a trainer's climb-out attitude
var level_off_m := 40.0 # --level-off=<m>: a fast airplane released hands-off needs more height for its phugoid
var rotate_stick := 0.35 # --rotate=<stick>: up elevator held on the ground roll (the jet needs more than a trainer)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft = arg.substr(11).split(",")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--start="):
			airborne_start = arg.substr(8)
		elif arg.begins_with("--throttles="):
			throttles = PackedFloat64Array()
			for item in arg.substr(12).split(","):
				throttles.append(float(item))
		elif arg == "--no-runway":
			runway_cases = false
		elif arg == "--no-airborne":
			airborne_cases = false
		elif arg.begins_with("--trim="):
			trim_choice = arg.substr(7)
		elif arg.begins_with("--level-off="):
			level_off_m = float(arg.substr(12))
		elif arg.begins_with("--rotate="):
			rotate_stick = float(arg.substr(9))
	call_deferred("run")

func _euler(s: PackedFloat64Array) -> PackedFloat64Array:
	return M.q_to_euler(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]))

func _speed(s: PackedFloat64Array) -> float:
	return sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)

func _climb(s: PackedFloat64Array) -> float:
	return -M.q_rotate(M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]), M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))[2]

func _airborne(s: Node) -> bool:
	for c in s.gear_compressions(s.sim.state):
		if c > 0.0:
			return false
	return true

func run() -> void:
	for id in aircraft:
		var runway := FlightSession.runway_aircraft_supported(id)
		var cases := []
		if airborne_cases:
			for thr in throttles:
				cases.append(["%s, throttle to %.0f %% at 1 s" % [airborne_start, thr * 100.0], airborne_start, thr])
		if runway and runway_cases:
			cases.append(["runway: full throttle, 12° climb-out, released at %.0f m with 50 %%" % level_off_m, "runway", 0.5])
			cases.append(["runway: as above, with 35 %", "runway", 0.35])
		for c in cases:
			var main = load("res://main.tscn").instantiate()
			main.aircraft_id = id
			main.weather_config = Weather.GENTLE_PRACTICE.duplicate(true)
			main.start_choice = str(c[1])
			if trim_choice == "cruise":
				main.trim_throttle = FlightSession.CRUISE_TRIM_THROTTLE
			root.add_child(main)
			await process_frame
			var s = main.session
			s.reset()
			if not s.is_flyable():
				print("SCENE ", id, " [", c[0], "] start failed: ", s.start_error)
				main.free()
				await process_frame
				continue
			var throttle: float = float(c[2])
			var h0: float = -s.sim.state[RB.POS + 2]
			var trim_throttle: float = float(s.start.get("throttle", NAN))
			var meta: Dictionary = s.trace_meta()
			print("SCENE ", id, " [", c[0], "] start ", c[1], " (launched %s, launch trim %s%s) V=%.1f m/s, trim throttle %.3f, elevator trim %.3f, h0 %.1f m" % [str(meta.get("launch_choice", "?")), str(meta.get("launch_trim_throttle", "?")), "" if s.start_error.is_empty() else ", start error: " + s.start_error, _speed(s.sim.state), trim_throttle, float(s.trims.pitch), h0])
			if c[1] == "runway" and str(meta.get("launch_choice", "")) != "runway":
				print("SCENE ", id, " [", c[0], "] skipped: the runway launch was not installed")
				main.free()
				await process_frame
				continue
			var phase := "ground" if c[1] == "runway" else "hold"
			var airborne_t := -1.0
			var max_h := h0
			var min_v := INF
			var inverted_t := -1.0
			var began := false
			if c[1] == "runway" and s.glow_is_active() and not s.engine_running:
				s.glow_start()
			while s.sim.time() < seconds and not s.sim.paused:
				await physics_frame
				var t: float = s.sim.time()
				if c[1] == "runway":
					if phase == "ground":
						s.commands.throttle = 1.0
						if airborne_t < 0.0:
							s.commands.pitch = rotate_stick # up elevator held, as a thumb on the down-arrow key
							if _airborne(s):
								airborne_t = t
						else:
							# Climb-out: a 12° attitude held with the elevator, then released at 40 m with the throttle brought back.
							s.commands.pitch = clampf(3.0 * (CLIMB_PITCH_RAD - _euler(s.sim.state)[1]), -0.4, 0.6)
							if -s.sim.state[RB.POS + 2] - h0 >= level_off_m:
								phase = "hold"
								s.commands.pitch = 0.0
								s.commands.throttle = throttle
								began = true
					else:
						s.commands.pitch = 0.0
				elif t >= 1.0 and not began:
					s.commands.throttle = throttle
					began = true
				var st: PackedFloat64Array = s.sim.state
				var h: float = -st[RB.POS + 2]
				max_h = maxf(max_h, h)
				if began:
					min_v = minf(min_v, _speed(st))
				var up: PackedFloat64Array = M.q_rotate(M.q_conj(M.quat(st[RB.ATT], st[RB.ATT + 1], st[RB.ATT + 2], st[RB.ATT + 3])), M.v3(0, 0, -1))
				if inverted_t < 0.0 and up[2] > 0.0:
					inverted_t = t
				if s.sim.tick % 480 == 0:
					var e := _euler(st)
					var v := _speed(st)
					print("  t=%5.1f h=%7.1f m  V=%5.1f m/s  pitch=%6.1f°  bank=%6.1f°  hdg=%6.1f°  path=%6.1f°  thr=%.2f  rpm=%6.0f  %s" % [t, h, v, rad_to_deg(e[1]), rad_to_deg(e[2]), rad_to_deg(e[0]), rad_to_deg(asin(clampf(_climb(st) / maxf(v, 0.1), -1.0, 1.0))), float(s.sim.inputs[3]), float(s.sim.aux[0]), phase])
				if not s.crash.is_empty():
					print("  crash: ", s.pause_reason)
					break
			var final: PackedFloat64Array = s.sim.state
			print("RESULT ", id, " [", c[0], "] after %.0f s: height %.1f → %.1f m (max %.1f), speed %.1f m/s, min speed %.1f, inverted %s, airborne at %s" % [s.sim.time(), h0, -final[RB.POS + 2], max_h, _speed(final), min_v, ("%.1f s" % inverted_t) if inverted_t >= 0.0 else "never", ("%.1f s" % airborne_t) if airborne_t >= 0.0 else "n/a"])
			main.free()
			await process_frame
	quit()
