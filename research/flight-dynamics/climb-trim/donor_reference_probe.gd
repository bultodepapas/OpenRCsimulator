# Donor AERORP-to-CG moment-reference sensitivity on the recorded Ugly Stik inputs.
# Approximate coefficient-only re-reference; no production/data/golden writes.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Aero := preload("res://physics/aero.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")

const AIRCRAFT_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const AIRCRAFT_ID := "jensen-das-ugly-stik-60"
const END_TICK := 3600 # 15 s at this capture's 240 Hz simulation tick.
const CG_MOMENTS := {Cm0 = -0.0258776, Cma = -0.64056, Cmde = -0.8470306}
var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var input_path: String = get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input_path))
	assert(not source.is_empty(), "missing recorded input fixture")
	var samples := {}
	for row: Dictionary in source.samples:
		samples[int(row.tick)] = row
	var reports: Array = []
	for variant in ["baseline", "donor_moments_at_cg"]:
		var frozen: Dictionary = {}
		if variant == "donor_moments_at_cg":
			frozen = AircraftData.load_file(AIRCRAFT_PATH)
			assert(frozen.get("ok", false), "failed to load validated Stik data")
			frozen = frozen.duplicate(true)
			for key: String in CG_MOMENTS:
				frozen.model.aero[key] = CG_MOMENTS[key]
		var session := Session.new()
		assert(session.setup_weather(Weather.GENTLE_PRACTICE))
		session.setup(AIRCRAFT_PATH, AIRCRAFT_ID, frozen)
		root.add_child(session)
		session.set_physics_process(false)
		session.sim.set_physics_process(false)
		session.radio.connected = false
		raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
		session.read_raw = func() -> Dictionary: return raw.duplicate()
		session.rate_profile = "normal"
		assert(session.start.get("ok", false), "%s start trim failed: %s" % [variant, session.start.get("message", "?")])
		var initial_state: PackedFloat64Array = session.sim.state.duplicate()
		var initial_air: Dictionary = session.air_data(initial_state, session.sim.time())
		var initial_deflections: Dictionary = session._deflections(session.sim.aux)
		var max_checkpoint_error := 0.0
		var first_inverted := -1.0
		var max_abs_q := 0.0
		var max_height := -initial_state[RB.POS + 2]
		var rows: Array = []
		for tick in range(1, END_TICK + 1):
			if samples.has(tick):
				raw = samples[tick].raw
			session._physics_process(session.sim.dt())
			if session.sim.paused:
				break
			session.sim.step()
			var state: PackedFloat64Array = session.sim.state
			max_height = maxf(max_height, -state[RB.POS + 2])
			max_abs_q = maxf(max_abs_q, absf(state[RB.RATE + 1]))
			if first_inverted < 0.0 and M.q_rotate(RB._att(state), M.v3(0.0, 0.0, 1.0))[2] < 0.0:
				first_inverted = session.sim.time()
			if variant == "baseline" and samples.has(tick) and samples[tick].has("state"):
				for i in state.size():
					max_checkpoint_error = maxf(max_checkpoint_error, absf(state[i] - float(samples[tick].state[i])))
			if tick % 240 != 0:
				continue
			var deflections: Dictionary = session._deflections(session.sim.aux)
			var lag_index: int = session.downwash_index()
			var downwash_cl: float = session.sim.aux[lag_index] if lag_index >= 0 else NAN
			var evaluation: Dictionary = Dynamics.evaluate(state, session.aircraft.model, deflections,
				session.sim.aux[0], session.air_density(), session.wind_at(session.sim.time()), session.sim.gravity,
				PackedFloat64Array(), downwash_cl)
			var air: Dictionary = evaluation.air
			rows.append({
				time_s = session.sim.time(),
				height_m = -state[RB.POS + 2],
				speed_mps = air.V,
				alpha_deg = rad_to_deg(air.alpha),
				pitch_deg = rad_to_deg(M.q_to_euler(RB._att(state))[1]),
				pitch_rate_rad_s = state[RB.RATE + 1],
				pitch_accel_rad_s2 = evaluation.derivative[RB.RATE + 1],
				throttle = session.commands.throttle,
				elevator_deg_up = -rad_to_deg(deflections.elevator),
				blend = Aero.local_flow_weight(state, air, deflections, session.aircraft.model, downwash_cl),
				aero_pitch_moment_nm = evaluation.aero_loads[4],
				total_pitch_moment_nm = evaluation.loads[4],
			})
		reports.append({
			variant = variant,
			seconds = session.sim.time(),
			completed_15s = session.sim.tick == END_TICK,
			initial_speed_mps = initial_air.V,
			initial_alpha_deg = rad_to_deg(initial_air.alpha),
			initial_throttle = session.start.get("throttle", NAN),
			initial_pitch_trim_command = session.trims.pitch,
			initial_elevator_deg_up = -rad_to_deg(initial_deflections.elevator),
			first_inverted_s = first_inverted,
			max_height_m = max_height,
			max_abs_pitch_rate_rad_s = max_abs_q,
			max_baseline_checkpoint_error = max_checkpoint_error if variant == "baseline" else null,
			model_moments = {Cm0 = session.aircraft.model.aero.Cm0, Cma = session.aircraft.model.aero.Cma,
				Cmde = session.aircraft.model.aero.Cmde},
			rows = rows,
		})
		session.free()
	print("DONOR_REFERENCE_SENSITIVITY ", JSON.stringify({
		method = "Approximate source AERORP-to-CG static/control moment shift. Replaces only Cm0/Cma/Cmde; keeps all force derivatives, rate derivatives, local-tail geometry/incidence, atmosphere, propulsion, and recorded raw inputs fixed. Starting trim is recomputed by the normal FlightSession preparation using each model.",
		limits = "Not a complete nonlinear force/moment transport: drag projection, alpha-dependent wind/body transform, aileron-force reference terms, and local incidence re-derivation are omitted. Counterfactual sensitivity, not physical validation.",
		fixture = source.source,
		end_tick = END_TICK,
		reports = reports,
	}))
	quit(0 if reports.size() == 2 and reports[0].max_baseline_checkpoint_error < 1e-8 and reports.all(func(report: Dictionary) -> bool: return report.completed_15s) else 1)
