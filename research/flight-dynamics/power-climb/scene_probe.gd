# D6e-R3: the owner's procedure in the complete flight scene (main.tscn: keyboard sampling, Home's gentle-breeze
# weather, real engine callbacks). Airborne start then a throttle setting held hands-off, and a keyboard-style
# runway takeoff (full throttle, up elevator held until airborne, then sticks centred and the throttle brought back).
# Prints height, speed, pitch and path every 2 s. Read-only research probe; nothing is written to the tree.
# Run: <godot> --headless --path app --audio-driver Dummy --script "$PWD/research/flight-dynamics/power-climb/scene_probe.gd" -- [--aircraft=<id,id>] [--seconds=40]
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
		for thr in throttles:
			cases.append(["%s, throttle to %.0f %% at 1 s" % [airborne_start, thr * 100.0], airborne_start, thr])
		if runway and runway_cases:
			cases.append(["runway: full throttle + up elevator until airborne + 3 s, then sticks centred and 50 %", "runway", 0.5])
			cases.append(["runway: as above, then 35 %", "runway", 0.35])
		for c in cases:
			var main = load("res://main.tscn").instantiate()
			main.aircraft_id = id
			main.weather_config = Weather.GENTLE_PRACTICE.duplicate(true)
			main.start_choice = str(c[1])
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
			print("SCENE ", id, " [", c[0], "] start ", c[1], " V=%.1f m/s, trim throttle %.3f, elevator trim %.3f, h0 %.1f m" % [_speed(s.sim.state), trim_throttle, float(s.trims.pitch), h0])
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
						s.commands.pitch = 0.35 # up elevator held, as a thumb on the down-arrow key
						if _airborne(s):
							if airborne_t < 0.0:
								airborne_t = t
							elif t - airborne_t > 3.0:
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
					print("  t=%5.1f h=%7.1f m  V=%5.1f m/s  pitch=%6.1f°  path=%6.1f°  thr=%.2f  rpm=%6.0f  %s" % [t, h, v, rad_to_deg(e[1]), rad_to_deg(asin(clampf(_climb(st) / maxf(v, 0.1), -1.0, 1.0))), float(s.sim.inputs[3]), float(s.sim.aux[0]), phase])
				if not s.crash.is_empty():
					print("  crash: ", s.pause_reason)
					break
			var final: PackedFloat64Array = s.sim.state
			print("RESULT ", id, " [", c[0], "] after %.0f s: height %.1f → %.1f m (max %.1f), speed %.1f m/s, min speed %.1f, inverted %s, airborne at %s" % [s.sim.time(), h0, -final[RB.POS + 2], max_h, _speed(final), min_v, ("%.1f s" % inverted_t) if inverted_t >= 0.0 else "never", ("%.1f s" % airborne_t) if airborne_t >= 0.0 else "n/a"])
			main.free()
			await process_frame
	quit()
