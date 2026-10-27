# D6e-R1: fleet live-input equilibrium, physical trim sign/servo/reset, and faster cruise.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const GlowFlight = preload("res://physics/glow/flight.gd")
var failures := 0
var count := 0

func check(label: String, ok: bool, detail: String = "") -> void:
	count += 1
	if not ok: failures += 1
	print(("ok " if ok else "FAIL ") + label + (": " + detail if not detail.is_empty() else ""))

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

func finite_values(values: PackedFloat64Array) -> bool:
	if values.is_empty(): return false
	for value in values:
		if not is_finite(value): return false
	return true

func freeze_liquid_inventory(session: Node) -> Callable:
	# Test-only comparison fixture: hold only usable fuel constant so the solved
	# equilibrium is measured at constant mass. The production evaluator is restored
	# for the separate finite-fuel flight below.
	var production_stage: Callable = session.sim.model.stage
	var fuel_index: int = session._liquid_index()
	session.sim.model.stage = func(body: PackedFloat64Array, continuous: PackedFloat64Array, at: float) -> Dictionary:
		var response: Variant = production_stage.call(body, continuous, at)
		if typeof(response) != TYPE_DICTIONARY or response.is_empty():
			return {}
		var derivative: Variant = response.get("derivative", PackedFloat64Array())
		if typeof(derivative) != TYPE_PACKED_FLOAT64_ARRAY or derivative.size() != continuous.size() \
				or fuel_index < 0 or fuel_index >= derivative.size():
			return {}
		var held: PackedFloat64Array = derivative
		held[fuel_index] = 0.0
		response.derivative = held
		return response
	return production_stage

func run() -> void:
	for entry in Catalog.airplane_flyable_entries():
		var s = make_session(entry)
		check(entry.id + " valid start", s.start.ok)
		if not s.start.ok:
			s.free()
			continue
		var initial: PackedFloat64Array = s.sim.state.duplicate()
		var glow_install: Dictionary=s.aircraft.model.propulsion.get("glow",{})
		var finite_fuel_glow: bool=not glow_install.is_empty() and float(glow_install.initial_fuel_kg)>0.0
		var finite_fuel_liquid: bool = s.liquid_fuel_is_active()
		var initial_fuel_kg: float=float(s.sim.continuous[1]) if finite_fuel_glow else 0.0
		if finite_fuel_glow and glow_install.has("fuel_feed"):
			var initial_point: Dictionary=GlowFlight.point(s,s.sim.state,s.sim.continuous,0.0)
			var rates: Dictionary=initial_point.get("rates",{})
			var feed: Dictionary=initial_point.get("fuel_feed",{})
			var gravity: PackedFloat64Array=feed.get("g_eff",PackedFloat64Array())
			var telemetry: Dictionary=initial_point.get("telemetry",{})
			check(entry.id + " initial fuel transport balances feed-aware apparent gravity",
				initial_point.get("ok",false) and gravity.size()==3 and finite_values(gravity)
				and M.norm(gravity)>0.0 and absf(float(s.sim.continuous[5])-float(telemetry.get("fuel_target_kg_s",NAN)))<1e-12
				and absf(float(rates.get("fuel_transport_kg_s",NAN)))<1e-12)
			# Trim.solve does not yet include NITRO feed metering. Bound the actual
			# post-initialization force, moment, and shaft residuals instead of assuming
			# the nominal-mixture trim remains exact after the metered flow is applied.
			var initial_dynamics: Dictionary=GlowFlight.evaluate(s.sim.state,s.sim.continuous,0.0,s)
			var dynamics_rates: PackedFloat64Array=initial_dynamics.get("derivative",PackedFloat64Array())
			var body_rates: PackedFloat64Array=initial_dynamics.get("body_derivative",PackedFloat64Array())
			var loads: PackedFloat64Array=initial_dynamics.get("loads",PackedFloat64Array())
			var linear_residual: float=INF
			var angular_residual: float=INF
			if body_rates.size()>=RB.SIZE and finite_values(body_rates):
				linear_residual=M.norm(body_rates.slice(RB.VEL,RB.VEL+3))
				angular_residual=M.norm(body_rates.slice(RB.RATE,RB.RATE+3))
			var shaft_torque_fraction: float=INF
			var source_torque: float=float(initial_point.get("source",{}).get("shaft_torque_nm",NAN))
			var propeller_torque: float=float(initial_point.get("propeller",{}).get("torque_nm",NAN))
			if is_finite(source_torque) and is_finite(propeller_torque) and absf(propeller_torque)>1e-12:
				shaft_torque_fraction=absf(source_torque-propeller_torque)/absf(propeller_torque)
			check(entry.id + " feed-aware start remains near force, moment, and shaft trim",
				loads.size()==6 and finite_values(loads) and dynamics_rates.size()>0 and finite_values(dynamics_rates)
				and linear_residual<0.01 and angular_residual<0.003 and shaft_torque_fraction<0.0015
				and absf(dynamics_rates[0])<10.0)
		if finite_fuel_liquid:
			var frozen_start_mass: Dictionary = s.mass_properties()
			var initial_response: Variant = s.sim.model.stage.call(s.sim.state, s.sim.continuous, s.sim.time())
			var initial_fuel_rate: float = NAN
			if typeof(initial_response) == TYPE_DICTIONARY and not initial_response.is_empty():
				var initial_derivative: PackedFloat64Array = initial_response.get("derivative", PackedFloat64Array())
				var fuel_index: int = s._liquid_index()
				if fuel_index >= 0 and fuel_index < initial_derivative.size():
					initial_fuel_rate = float(initial_derivative[fuel_index])
			check(entry.id + " production liquid stage reports fuel consumption", frozen_start_mass.get("ok", false)
				and frozen_start_mass.get("finite_fuel", false) and is_finite(initial_fuel_rate) and initial_fuel_rate < 0.0)
			initial_fuel_kg = float(frozen_start_mass.get("fuel_remaining_kg", NAN))
			var production_stage: Callable = freeze_liquid_inventory(s)
			fly(s, 2400)
			var frozen_end_mass: Dictionary = s.mass_properties()
			var frozen_speed: float = M.norm(RB._slice3(s.sim.state, RB.VEL))
			check(entry.id + " frozen-inventory equilibrium holds height/speed for 10 s",
				s.sim.tick == 2400 and s.sim.fault_reason.is_empty() and finite_values(s.sim.state)
				and absf(s.sim.state[2] - initial[2]) < 0.001
				and absf(frozen_speed - s.start.V) < 0.001,
				"Δheight %.6f m, Δspeed %.6f m/s" % [s.sim.state[2] - initial[2], frozen_speed - s.start.V])
			check(entry.id + " frozen inventory preserves actual live mass and fuel",
				frozen_start_mass.get("ok", false) and frozen_end_mass.get("ok", false)
				and absf(float(frozen_end_mass.get("mass_kg", NAN)) - float(frozen_start_mass.get("mass_kg", NAN))) < 1e-9
				and absf(float(frozen_end_mass.get("fuel_remaining_kg", NAN)) - initial_fuel_kg) < 1e-12)
			# Restore the production law before reset and the real finite-inventory run.
			s.sim.model.stage = production_stage
			s.reset()
			initial = s.sim.state.duplicate()
			var production_start_mass: Dictionary = s.mass_properties()
			initial_fuel_kg = float(production_start_mass.get("fuel_remaining_kg", NAN))
			fly(s, 2400)
			var production_end_mass: Dictionary = s.mass_properties()
			var production_speed: float = M.norm(RB._slice3(s.sim.state, RB.VEL))
			# Production drift remains bounded by the broader gates: half-power fleet holds
			# (<1 m over 10 s) in test_half_power_start.gd and P-51 holds (<2 m / <0.3 m/s
			# over 30 s) in test_p51_handling.gd. This comparison adds no new drift tolerance.
			check(entry.id + " production finite-liquid neutral flight completes and consumes fuel",
				s.sim.tick == 2400 and s.sim.fault_reason.is_empty() and finite_values(s.sim.state)
				and finite_values(s.sim.continuous) and production_start_mass.get("ok", false)
				and production_end_mass.get("ok", false) and is_finite(production_speed) and production_speed > 0.0
				and float(production_end_mass.get("fuel_remaining_kg", NAN)) >= 0.0
				and float(production_end_mass.get("fuel_remaining_kg", NAN)) < initial_fuel_kg)
			print("%s finite-liquid neutral 10 s: fuel %.6f -> %.6f kg, live mass %.6f -> %.6f kg, Δheight %.6f m, Δspeed %.6f m/s" % [
				entry.id, initial_fuel_kg, float(production_end_mass.get("fuel_remaining_kg", NAN)),
				float(production_start_mass.get("mass_kg", NAN)), float(production_end_mass.get("mass_kg", NAN)),
				initial[2] - s.sim.state[2], production_speed - s.start.V])
		elif finite_fuel_glow:
			fly(s, 2400)
			var final_speed: float=M.norm(RB._slice3(s.sim.state,RB.VEL))
			check(entry.id + " finite-fuel neutral flight consumes fuel with finite motion", s.sim.tick==2400
				and s.sim.fault_reason.is_empty() and finite_values(s.sim.state) and finite_values(s.sim.continuous)
				and is_finite(final_speed) and final_speed>0.0 and s.sim.continuous[1]>=0.0
				and s.sim.continuous[1]<initial_fuel_kg
				and absf(initial[2]-s.sim.state[2])<0.15
				and absf(final_speed-s.start.V)<0.07)
		else:
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
		var pilot_correction_deg: float = 0.0
		if corrected:
			pilot_correction_deg = (faster.pitch_command - old_pitch) * jet.throws_deg().elevator
			check("pilot correction accepts faster-cruise elevator", jet.adjust_elevator_trim(pilot_correction_deg))
		# Start servos at the commanded positions to isolate equilibrium from actuator transients.
		jet.sim.inputs = jet._inputs()
		var aux: PackedFloat64Array = jet.sim.aux
		aux[2] = jet.trims.pitch
		jet.sim.aux = aux
		var height: float = -jet.sim.state[2]
		var production_stage: Callable = jet.sim.model.stage
		var finite_liquid: bool = jet.liquid_fuel_is_active()
		if finite_liquid:
			production_stage = freeze_liquid_inventory(jet)
		fly(jet, 1200)
		check("faster cruise completed", jet.sim.tick == 1200 and jet.sim.fault_reason.is_empty())
		gain.append(-jet.sim.state[2] - height)
		if finite_liquid:
			jet.sim.model.stage = production_stage
		if corrected and finite_liquid:
			jet.reset()
			jet.trims.pitch = old_pitch
			check("production Vantage Jet correction accepts same faster-cruise elevator", jet.adjust_elevator_trim(pilot_correction_deg))
			jet.sim.inputs = jet._inputs()
			aux = jet.sim.aux
			aux[2] = jet.trims.pitch
			jet.sim.aux = aux
			var production_start_mass: Dictionary = jet.mass_properties()
			var production_start_height: float = -jet.sim.state[2]
			var production_start_speed: float = M.norm(RB._slice3(jet.sim.state, RB.VEL))
			fly(jet, 1200)
			var production_end_mass: Dictionary = jet.mass_properties()
			var production_end_speed: float = M.norm(RB._slice3(jet.sim.state, RB.VEL))
			check("production Vantage Jet corrected cruise completes and consumes finite fuel",
				jet.sim.tick == 1200 and jet.sim.fault_reason.is_empty() and finite_values(jet.sim.state)
				and production_start_mass.get("ok", false) and production_end_mass.get("ok", false)
				and float(production_end_mass.get("fuel_remaining_kg", NAN)) >= 0.0
				and float(production_end_mass.get("fuel_remaining_kg", NAN)) < float(production_start_mass.get("fuel_remaining_kg", NAN)))
			print("Vantage Jet production 40 m/s corrected trim, 5 s: fuel %.6f -> %.6f kg, live mass %.6f -> %.6f kg, Δspeed %.6f m/s, Δheight %.6f m" % [
				float(production_start_mass.get("fuel_remaining_kg", NAN)), float(production_end_mass.get("fuel_remaining_kg", NAN)),
				float(production_start_mass.get("mass_kg", NAN)), float(production_end_mass.get("mass_kg", NAN)),
				production_end_speed - production_start_speed, -jet.sim.state[2] - production_start_height])
		jet.free()
	check("old trim climbs; pilot trim holds faster level cruise", gain[0] > 1.0 and absf(gain[1]) < 0.001)
	print("Cruise height change: stale %.6f m, adjusted %.6f m" % [gain[0], gain[1]])
	print("%d checks, %d failed" % [count, failures])
	quit(1 if failures else 0)
