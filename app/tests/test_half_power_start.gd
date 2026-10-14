# D6e-R1: selected initial operating point, fixed trim, lifecycle and failure controls.
# Run: godot --headless --path app --script res://tests/test_half_power_start.gd
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Weather = preload("res://physics/wind_config.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print(("ok " if ok else "FAIL ") + label)
func make_session(path := "res://data/aircraft/jensen_ugly_stik_60.json") -> Node:
	var s = Session.new()
	s.start_choice = Session.START_HALF_POWER
	s.setup(path)
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
	var unsupported := make_session("res://data/aircraft/turbo_lumber_evolution.json")
	check("unsupported aircraft cannot silently fall back", not unsupported.is_flyable() and unsupported.sim.paused)
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
