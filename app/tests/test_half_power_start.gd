# D6e-R1: selected initial operating point, fixed trim, lifecycle and failure controls.
# D6e-R3: the 50 % level trim is offered to every fixed-wing catalog airplane; each must start at half throttle, hold
# its height hands-off, climb with more power and descend with less. The refusal path keeps a rotorcraft out.
# Run: godot --headless --path app --script res://tests/test_half_power_start.gd
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Weather = preload("res://physics/wind_config.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print(("ok " if ok else "FAIL ") + label)
func make_session(path := "res://data/aircraft/jensen_ugly_stik_60.json", id := "") -> Node:
	var s = Session.new()
	s.start_choice = Session.START_HALF_POWER
	s.setup(path, id)
	root.add_child(s)
	s.set_physics_process(false)
	s.sim.set_physics_process(false)
	s.radio.connected = false
	s.read_raw = func() -> Dictionary: return {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
	return s
func fly(s: Node, ticks: int) -> void:
	for i in ticks:
		s._physics_process(s.sim.dt())
		if s.sim.paused: break
		s.sim.step()
func run() -> void:
	var s := make_session()
	check("selected profile is flyable at requested power", s.is_flyable() and absf(s.start.throttle - 0.5) < 1e-7)
	if not s.is_flyable():
		printerr(s.pause_reason)
		s.free()
		quit(1)
		return
	var initial: PackedFloat64Array = s.sim.state.duplicate()
	var initial_trims: Dictionary = s.trims.duplicate()
	var initial_speed: float = s.start.V
	var initial_alpha: float = s.start.alpha
	fly(s, 2400)
	check("neutral keyboard holds altitude for ten seconds", s.sim.tick == 2400 and absf(s.sim.state[2] - initial[2]) < 0.001)
	check("trim remains fixed during equilibrium flight", s.trims == initial_trims and s.raw.pitch == 0.0)
	s.commands.throttle = 1.0
	fly(s, 720)
	check("power increase still produces natural climb", s.sim.tick == 3120 and s.sim.state[2] < initial[2] - 0.5)
	check("no automatic elevator compensation after throttle change", s.trims == initial_trims and absf(s.sim.aux[2] - initial_trims.pitch) < 1e-10)
	s.reset()
	check("restart restores solved speed and power", s.sim.tick == 0 and s.start.V == initial_speed and absf(s.commands.throttle - 0.5) < 1e-7)
	s.commands.throttle = 0.25
	fly(s, 720)
	check("quarter power with neutral keyboard descends", s.sim.tick == 720 and s.sim.state[2] > initial[2] + 0.1)
	var message: String = s.reload()
	check("reload retains selected half-power equilibrium", s.is_flyable() and s.start.V == initial_speed and absf(s.commands.throttle - 0.5) < 1e-7)
	check("metadata names selected profile", s.trace_meta().selected_start_choice == Session.START_HALF_POWER and s.trace_meta().launch_choice == "airborne")
	print("HALF_POWER_START ", JSON.stringify({speed_mps=initial_speed, throttle=s.start.throttle, elevator_up_deg=initial_trims.pitch*s.throws_deg().elevator, reload_message=message}))
	s.set_start_altitude(45.0)
	check("changed launch atmosphere accepted", s.setup_weather(Weather.preset("cool-dense")))
	s.reset()
	# Lift scales with density, so a fresh solve changes the trimmed angle of attack. The speed can barely move: prescribed-rpm
	# thrust and drag both scale with density, and near the polar's minimum-drag CL only induced drag responds (D6e-R1).
	check("density change re-solves selected power and retains altitude", s.is_flyable() and absf(s.start.throttle - 0.5) < 1e-7
		and absf(s.start.alpha - initial_alpha) > 1e-3 and absf(s.sim.state[2] + 45.0) < 1e-9)
	fly(s, 2400)
	check("new atmosphere holds equilibrium", s.sim.tick == 2400 and absf(s.sim.state[2] + 45.0) < 0.001)
	s.free()
	# D6e-R3: every fixed-wing catalog airplane. Finite fuel and finite packs let the trimmed state drift a little in
	# ten seconds (mass, voltage, the turbine's 5 ml/s): the bound is 1 m against 1 mm for the fixed-energy Stik above.
	# Power steps get eight seconds: the P-51's engine spools in 4 s and its high thrust line balloons it when power is cut.
	var fleet := []
	for entry in Catalog.airplane_flyable_entries():
		var id: String = str(entry.id)
		check(id + " offers the 50 % start", Session.half_power_start_supported(id))
		var a := make_session(str(entry.data), id)
		a.set_start_altitude(300.0) # room for the quarter-throttle descent of a fast, clean airplane
		a.reset()
		check(id + " starts level at 50 % throttle", a.is_flyable() and absf(a.start.throttle - 0.5) < 1e-7 and a.start.V > 0.0)
		if not a.is_flyable():
			printerr(id, ": ", a.pause_reason)
			a.free()
			continue
		var h0: float = a.sim.state[2]
		var v0: float = a.start.V
		var slow: float = float(a.aircraft.model.start_speed)
		fly(a, 2400)
		var drift: float = absf(a.sim.state[2] - h0)
		check(id + " holds height hands-off for ten seconds (%.3f m)" % drift, a.sim.tick == 2400 and drift < 1.0)
		check(id + " flies faster at 50 % than at its slow start", v0 > slow and v0 < 2.5 * slow)
		a.reset()
		a.commands.throttle = 1.0
		fly(a, 2880)
		# The P-51's thrust line sits 71 mm above its CG: more power first lowers the nose and the height before the speed
		# builds, so the climb is judged after twelve seconds.
		check(id + " climbs at full throttle (%.1f m in 12 s)" % (h0 - a.sim.state[2]), a.sim.tick == 2880 and a.sim.state[2] < h0 - 0.5)
		a.reset()
		a.commands.throttle = 0.25
		fly(a, 1920)
		check(id + " descends at quarter throttle (%.1f m in 8 s)" % (h0 - a.sim.state[2]), a.sim.tick == 1920 and a.sim.state[2] > h0 + 0.1)
		fleet.append({id = id, speed_mps = snappedf(v0, 0.01), slow_start_mps = snappedf(slow, 0.01), elevator_up_deg = snappedf(a.start.pitch_command * a.throws_deg().elevator, 0.01), drift_10_s_m = snappedf(drift, 0.001)})
		a.free()
	print("HALF_POWER_FLEET ", JSON.stringify(fleet))
	var rotorcraft_id := ""
	for id in Catalog.ids():
		if Catalog.is_rotorcraft(id):
			rotorcraft_id = id
			break
	var unsupported := make_session(str(Catalog.entry(rotorcraft_id).data), rotorcraft_id)
	check("a rotorcraft (%s) cannot silently fall back" % rotorcraft_id, not rotorcraft_id.is_empty() and not Session.half_power_start_supported(rotorcraft_id) and not unsupported.is_flyable() and unsupported.sim.paused)
	unsupported.free()
	var late = Session.new()
	late.setup()
	root.add_child(late)
	late.set_physics_process(false)
	late.sim.set_physics_process(false)
	late.start_choice = Session.START_HALF_POWER
	late.reset()
	check("selecting profile after setup refits before reset", late.is_flyable() and absf(late.commands.throttle - 0.5) < 1e-7)
	late.free()
	print("HALF_POWER_CHECKS ", checks, " failures=", failures)
	quit(1 if failures else 0)
