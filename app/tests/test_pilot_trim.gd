# D6e-R1: fleet live-input equilibrium, physical trim sign/servo/reset, and faster cruise.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var failures := 0
var count := 0

func check(label: String, ok: bool) -> void:
	count += 1
	if not ok: failures += 1
	print(("ok " if ok else "FAIL ") + label)

func _initialize() -> void:
	call_deferred("run")

func make_session(entry: Dictionary) -> Node:
	var session = Session.new()
	session.setup(entry.data, entry.id)
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	session.read_raw = func() -> Dictionary: return {roll=0.0, pitch=0.0, yaw=0.0, throttle=0.0}
	session.rate_profile = "normal"
	return session

func fly(session: Node, ticks: int) -> void:
	for tick in ticks:
		session._physics_process(session.sim.dt())
		if session.sim.paused: break
		session.sim.step()

func run() -> void:
	for entry in Catalog.airplane_flyable_entries():
		var s = make_session(entry)
		check(entry.id + " valid start", s.start.ok)
		if not s.start.ok:
			s.free()
			continue
		var initial: PackedFloat64Array = s.sim.state.duplicate()
		fly(s, 2400)
		check(entry.id + " live neutral holds height/speed for 10 s", s.sim.tick == 2400 and s.sim.fault_reason.is_empty()
			and absf(s.sim.state[2] - initial[2]) < 0.001
			and absf(M.norm(RB._slice3(s.sim.state, RB.VEL)) - s.start.V) < 0.001)
		var original: Dictionary = s.trims.duplicate()
		var state_bytes: PackedByteArray = s.sim.state.to_byte_array()
		var aux_bytes: PackedByteArray = s.sim.aux.to_byte_array()
		var power: float = s.commands.throttle
		check(entry.id + " accepts nose-down trim", s.adjust_elevator_trim(-0.5))
		check(entry.id + " trim only changes elevator command offset", s.sim.state.to_byte_array() == state_bytes
			and s.sim.aux.to_byte_array() == aux_bytes and s.commands.throttle == power
			and s.trims.roll == original.roll and s.trims.yaw == original.yaw)
		check(entry.id + " degrees independent of aircraft throw/rates", absf((s.flown_commands().pitch - original.pitch)
			* s.throws_deg().elevator + 0.5) < 1e-12)
		fly(s, 60)
		check(entry.id + " servo flies nose-down trim", absf(s.sim.aux[2] - s.trims.pitch) < 1e-12 and s.sim.state[RB.RATE + 1] < 0.0)
		check(entry.id + " finite trim bounded by physical throw", s.adjust_elevator_trim(1000.0) and s.trims.pitch == 1.0)
		check(entry.id + " opposite limit bounded", s.adjust_elevator_trim(-2000.0) and s.trims.pitch == -1.0)
		check(entry.id + " nonfinite trim rejected", not s.adjust_elevator_trim(NAN) and not s.adjust_elevator_trim(INF) and s.trims.pitch == -1.0)
		s.sim.set_paused(true)
		check(entry.id + " pause rejects trim", not s.adjust_elevator_trim(0.1))
		s.reset()
		check(entry.id + " reset restores solved trim and servos", s.trims == original and s.sim.aux[2] == original.pitch)
		if entry.id in ["turbo-lumber-evolution", "jensen-das-ugly-stik-60"]:
			s.commands.throttle = 0.25
			fly(s, 720)
			check(entry.id + " 25 percent power descends with neutral keyboard", s.sim.tick == 720
				and s.sim.inputs[3] == 0.25 and s.raw.pitch == 0.0 and s.sim.state[2] > initial[2] + 0.1)
		s.input_enabled = false
		check(entry.id + " replay rejects live trim", not s.adjust_elevator_trim(0.1))
		s.free()
	# Same faster jet operating point: old elevator trim climbs, corrected elevator holds level.
	var gain := []
	for corrected in [false, true]:
		var jet = make_session(Catalog.entry("sebart-avanti-s-a200-p100rx"))
		var old_pitch: float = jet.trims.pitch
		var faster: Dictionary = jet.trim_at(40.0)
		check("faster jet cruise can trim", faster.ok)
		jet.reset()
		jet.trims.pitch = old_pitch
		if corrected:
			check("pilot correction accepts faster-cruise elevator", jet.adjust_elevator_trim((faster.pitch_command - old_pitch) * jet.throws_deg().elevator))
		# Start servos at the commanded positions to isolate equilibrium from actuator transients.
		jet.sim.inputs = jet._inputs()
		var aux: PackedFloat64Array = jet.sim.aux
		aux[2] = jet.trims.pitch
		jet.sim.aux = aux
		var height: float = -jet.sim.state[2]
		fly(jet, 1200)
		check("faster cruise completed", jet.sim.tick == 1200 and jet.sim.fault_reason.is_empty())
		gain.append(-jet.sim.state[2] - height)
		jet.free()
	check("old trim climbs; pilot trim holds faster level cruise", gain[0] > 1.0 and absf(gain[1]) < 0.001)
	print("Cruise height change: stale %.6f m, adjusted %.6f m" % [gain[0], gain[1]])
	print("%d checks, %d failed" % [count, failures])
	quit(1 if failures else 0)
