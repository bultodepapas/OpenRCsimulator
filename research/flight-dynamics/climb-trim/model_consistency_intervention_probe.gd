# Counterfactual coefficient-consistency experiments. No production data writes.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Weather := preload("res://physics/wind_config.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Trim := preload("res://physics/trim.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const ID := "jensen-das-ugly-stik-60"
var raw := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
var samples := {}
var absolute_throttle := PackedFloat64Array()

func _initialize() -> void:
	_run.call_deferred()

func _hashes() -> Dictionary:
	var result := {}
	for path: String in [PATH, "res://sim/flight_session.gd", "res://sim/simulation.gd", "res://physics/aero.gd", "res://physics/dynamics.gd", "res://physics/aircraft_data.gd", get_script().resource_path]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _candidate_models() -> Array:
	var base: Dictionary = AircraftData.load_file(PATH)
	assert(base.ok)
	var model: Dictionary = base.model
	var arm: float = float(model.surfaces.horizontal.position[0]) - float(model.reference.arp_le[0])
	var matched: Dictionary = base.duplicate(true)
	matched.model.aero.CLde = -model.aero.Cmde * model.reference.c / arm
	# The second candidate uses the CURRENT local model's control response, not new measured data.
	# Compute wind-axis lift derivative and transport its CG moment back to the coefficient ARP.
	var state: PackedFloat64Array = Trim.state_for(15.0, 0.0, 0.0, 0.0, M.v3(0.0, 0.0, -500.0))
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), 1.225)
	var eps := 1e-5
	var d := {elevator = eps, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.0}
	var positive: PackedFloat64Array = Aero._local_loads(state, air, d, model, 1.225)
	d.elevator = -eps
	var negative: PackedFloat64Array = Aero._local_loads(state, air, d, model, 1.225)
	var dfx: float = (positive[0] - negative[0]) / (2.0 * eps)
	var dfz: float = (positive[2] - negative[2]) / (2.0 * eps)
	var dmy: float = (positive[4] - negative[4]) / (2.0 * eps)
	var arp_x: float = -(model.reference.arp_le[0] - model.cg_le[0])
	var arp_z: float = -(model.reference.arp_le[2] - model.cg_le[2])
	var paired: Dictionary = base.duplicate(true)
	paired.model.aero.CLde = -dfz / (air.qbar * model.reference.S)
	paired.model.aero.Cmde = (dmy - (arp_z * dfx - arp_x * dfz)) / (air.qbar * model.reference.S * model.reference.c)
	return [{name = "baseline", frozen = base}, {name = "tail_arm_CLde_only", frozen = matched}, {name = "paired_local_elevator_derivatives", frozen = paired}]

func _case(candidate: Dictionary, protocol: String) -> Dictionary:
	var session := Session.new()
	if protocol == "capture_15s":
		assert(session.setup_weather(Weather.GENTLE_PRACTICE))
	session.setup(PATH, ID, candidate.frozen.duplicate(true))
	root.add_child(session)
	session.set_physics_process(false)
	session.sim.set_physics_process(false)
	session.radio.connected = false
	raw = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	session.read_raw = func() -> Dictionary: return raw.duplicate()
	session.rate_profile = "normal"
	assert(session.start.get("ok", false), "candidate startup did not trim")
	var end_tick := 3600 if protocol == "capture_15s" else 7200
	if protocol != "capture_15s":
		session.sim.state[2] = -500.0
		session.sim.previous = session.sim.state.duplicate()
	var initial: PackedFloat64Array = session.sim.state.duplicate()
	var initial_air: Dictionary = session.air_data(initial, 0.0)
	var initial_rpm: float = session.sim.aux[0]
	var initial_power: float = session.commands.throttle
	var initial_elevator: float = -rad_to_deg(session._deflections(session.sim.aux).elevator)
	var max_height := -initial[2]
	var min_height := -initial[2]
	var max_q := 0.0
	var max_elevator_delta := 0.0
	var max_blend := 0.0
	var first_inverted := -1.0
	var source_error := 0.0
	var rows: Array = []
	for tick in range(1, end_tick + 1):
		if protocol == "capture_15s" and samples.has(tick):
			raw = samples[tick].raw
		session._physics_process(session.sim.dt())
		if session.sim.paused:
			break
		if protocol == "capture_15s" and candidate.name == "baseline":
			absolute_throttle.append(session.commands.throttle)
		elif protocol != "trim_hold_30s":
			session.commands.throttle = absolute_throttle[tick - 1] if tick <= 3600 else 1.0
			session.sim.inputs = session._inputs()
		session.sim.step()
		var s: PackedFloat64Array = session.sim.state
		max_height = maxf(max_height, -s[2])
		min_height = minf(min_height, -s[2])
		max_q = maxf(max_q, absf(s[11]))
		if first_inverted < 0.0 and M.q_rotate(RB._att(s), M.v3(0.0, 0.0, 1.0))[2] < 0.0:
			first_inverted = session.sim.time()
		if protocol == "capture_15s" and candidate.name == "baseline" and samples.has(tick) and samples[tick].has("state"):
			for i in s.size():
				source_error = maxf(source_error, absf(s[i] - float(samples[tick].state[i])))
		var d: Dictionary = session._deflections(session.sim.aux)
		max_elevator_delta = maxf(max_elevator_delta, absf(-rad_to_deg(d.elevator) - initial_elevator))
		if tick % 120 != 0:
			continue
		var lag_index: int = session.downwash_index()
		var lag: float = session.sim.aux[lag_index] if lag_index >= 0 else NAN
		var evaluation: Dictionary = Dynamics.evaluate(s, session.aircraft.model, d, session.sim.aux[0], session.air_density(), session.wind_at(session.sim.time()), session.sim.gravity, PackedFloat64Array(), lag)
		var blend: float = Aero.local_flow_weight(s, evaluation.air, d, session.aircraft.model, lag)
		max_blend = maxf(max_blend, blend)
		rows.append({time_s = session.sim.time(), height_m = -s[2], speed_mps = evaluation.air.V,
			alpha_deg = rad_to_deg(evaluation.air.alpha), pitch_deg = rad_to_deg(M.q_to_euler(RB._att(s))[1]),
			roll_deg = rad_to_deg(M.q_to_euler(RB._att(s))[2]), q_rad_s = s[11], blend = blend,
			throttle = session.commands.throttle, elevator_deg_up = -rad_to_deg(d.elevator)})
	var result := {candidate = candidate.name, protocol = protocol, seconds = session.sim.time(), complete = session.sim.tick == end_tick,
		fault = session.sim.fault_reason, crashed = not session.crash.is_empty(), initial_throttle = initial_power,
		initial_speed_mps = initial_air.V, initial_alpha_deg = rad_to_deg(initial_air.alpha), initial_rpm = initial_rpm,
		initial_elevator_deg_up = initial_elevator, CLde_per_rad = session.aircraft.model.aero.CLde, Cmde_per_rad = session.aircraft.model.aero.Cmde,
		first_inverted_s = first_inverted, max_height_gain_m = max_height + initial[2], min_height_gain_m = min_height + initial[2],
		final_height_gain_m = -session.sim.state[2] + initial[2], max_abs_q_rad_s = max_q, max_sampled_local_blend = max_blend,
		max_elevator_change_deg = max_elevator_delta, baseline_checkpoint_error = source_error if candidate.name == "baseline" and protocol == "capture_15s" else null, rows = rows}
	session.free()
	return result

func _run() -> void:
	var hashes := _hashes()
	var fixture_path: String = get_script().resource_path.get_base_dir().path_join("ugly-loop-inputs.json")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	for row: Dictionary in source.samples:
		samples[int(row.tick)] = row
	var candidates := _candidate_models()
	var reports: Array = []
	for protocol: String in ["capture_15s", "calm_history_then_full_30s", "trim_hold_30s"]:
		for candidate: Dictionary in candidates:
			var report := _case(candidate, protocol)
			reports.append(report)
			print("MODEL_CONSISTENCY_CASE ", JSON.stringify({candidate = candidate.name, protocol = protocol, complete = report.complete, inversion = report.first_inverted_s, height_gain = report.final_height_gain_m}))
	var source_unchanged := hashes == _hashes()
	var ok: bool = source_unchanged and reports[0].baseline_checkpoint_error < 1e-8 and reports.all(func(r: Dictionary) -> bool: return r.complete and r.fault.is_empty() and not r.crashed and r.max_elevator_change_deg < 1e-10)
	var result := {ok = ok, source_unchanged_during_run = source_unchanged, source_sha256 = hashes, fixture_sha256 = FileAccess.get_sha256(fixture_path),
		method = "Three global elevator-coefficient variants, normal startup re-trim at identical 15 m/s. First15s retain recorded weather/raw controls, but all variants receive IDENTICAL absolute throttle commands extracted from the baseline. Calm 30s extends that history by holding full power after15s, starts500m. Trim-hold controls keep each variant's own solved startup throttle. Elevator stays fixed in every run.",
		candidate_derivation = "CLde-only = -Cmde*c/(horizontal_tail_x-ARP_x), lift-only small-angle tail-arm relation. Paired variant replaces CLde/Cmde with central derivatives of current local loads at alpha=0,V=15,rates=0,de=0, transporting CG derivative back to ARP, including drag-arm term.",
		limits = "Uncalibrated model-consistency sensitivity, NOT validated replacements. Other static/rate coefficients, estimated tail geometry/incidence and regime construction remain unchanged. Re-trim changes initial alpha/elevator/RPM; actual commands and original checkpoints are reported. Inversion is body-down reversal, NOT proof of a complete pitch loop. Sampled blend is only at0.5s intervals.", reports = reports}
	var output: String = ProjectSettings.globalize_path("res://../docs/research/flight-dynamics/climb-trim/model-consistency-interventions.json")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("MODEL_CONSISTENCY_RESULT ", JSON.stringify({ok = ok, source_unchanged = source_unchanged, output = output}))
	quit(0 if ok else 1)
