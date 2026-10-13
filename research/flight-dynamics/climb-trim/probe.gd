# D6e-R1: reproduce neutral, power-step and weather behavior through the session's input sampler.
# Run with --headless --path app --script <absolute path to this file>.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const Weather = preload("res://physics/wind_config.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for entry in Catalog.flyable_entries():
		for condition in ["trim", "quarter", "half", "quarter_gentle"]:
			var session = Session.new()
			if condition == "quarter_gentle":
				assert(session.setup_weather(Weather.GENTLE_PRACTICE))
			session.setup(entry.data, entry.id)
			root.add_child(session)
			session.set_physics_process(false)
			session.sim.set_physics_process(false)
			session.radio.connected = false
			session.read_raw = func() -> Dictionary: return {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
			session.rate_profile = "normal"
			assert(session.start.ok)
			if condition != "trim":
				session.commands.throttle = 0.5 if condition == "half" else 0.25
			var initial: PackedFloat64Array = session.sim.state.duplicate()
			for tick in 2400:
				session._physics_process(session.sim.dt())
				if session.sim.paused: break
				session.sim.step()
			var s: PackedFloat64Array = session.sim.state
			var air: Dictionary = session.air_data(s, session.sim.time())
			var velocity: PackedFloat64Array = M.q_rotate(RB._att(s), RB._slice3(s,RB.VEL))
			print(JSON.stringify({id=entry.id,condition=condition,trim_throttle=session.start.throttle,
				elevator_trim_deg=session.trims.pitch*session.throws_deg().elevator,inputs=Array(session.sim.inputs),
				seconds=session.sim.time(),altitude_gain_m=initial[2]-s[2],climb_mps=-velocity[2],
				airspeed_mps=air.V,pitch_deg=rad_to_deg(M.q_to_euler(RB._att(s))[1]),alpha_deg=rad_to_deg(air.alpha),
				fault=session.sim.fault_reason,crashed=not session.crash.is_empty()}))
			session.free()
	quit()
