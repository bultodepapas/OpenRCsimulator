extends SceneTree

const Step := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_step.gd")
const Impulse := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_impulse.gd")
const Normal := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/normal_compliance.gd")
const Admission := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/normal_contact_admission.gd")
const Rotor := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rotor_coupling.gd")
const Geometry := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/wheel_geometry.gd")
const Datum := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/fixed_datum_body.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rigid_body.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")
const Sim := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/sim/simulation.gd")
const Model := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/sim/vehicle_model.gd")
const MASS := 2.0
const RADIUS := 0.1
const STIFFNESS := 500.0
var _normal: Dictionary
var _rotors: Dictionary
var _checks := 0
var _failed := 0
var _gravity := 9.80665
var _grip := .6
var _rolling := .02
var _brake := 0.0
var _highest_algebraic_load := 0.0
var _shaft_capture_selected := false
var _shaft_friction_rate := 0.0
var _shaft_drive_torque := 0.0
var _cull_unloaded_wheel_rows := false


func _check(label: String, yes: bool, detail := "") -> void:
	_checks += 1
	if not yes:
		_failed += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_fixture()
	if not _failed:
		_operator_and_refinement()
		_damage_sampling()
		_discarded_refinement()
		_damped_work()
		_kernel_drop_spin_brake_replay()
		_rejections()
		_paired_paths()
		_error_gate_rejections()
		_capture_passthrough()
		_capture_bindings()
		_two_sided()
	print("Aircraft ground step: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _p(values: Array) -> PackedFloat64Array:
	return PackedFloat64Array(values)


func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	return out


func _fixture() -> void:
	var parameters := {format = Normal.FORMAT}
	var values := {stiffness = STIFFNESS, compression_damping = 0.0, rebound_damping = 0.0,
		damping_onset = .002, stroke = .4, stop_stiffness = 0.0, stop_scale = .01, stop_exponent = 3.0, stop_damping = 0.0}
	for key: String in values:
		parameters[key] = {value = values[key], unit = Normal.SPECS[key][0], kind = "estimated",
			source = "Independent synthetic passive one-wheel plus shaft fixture; no stock physical validation"}
	_normal = Normal.prepare(parameters)
	_rotors = Rotor.prepare_system(_p([1, 1, 1, 0, 0, 0]), _p([.02, .01]), _p([.01, .005]),
		_p([0, -1, 0, 0, -1, 0]), {partition_id = "step-fixture", reference_pose_id = "coincident-fixed-hubs",
		kind = "estimated", source = "Synthetic aggregate reference only, not measured inventory ownership"})
	_check("synthetic compliance and closed rotor partition prepare", _normal.ok and _rotors.ok)


func _initial(down := -.3, velocity := PackedFloat64Array([3.0, 0.0, .5])) -> PackedFloat64Array:
	var out := RB.make_state(_p([0, 0, down]), velocity, M.q_identity(), _zeros(3))
	out.append_array(_p([500.0, 0.0])) # RPM, hardware rim m/s, not duplicate inertia.
	return out


func _evaluate(s: PackedFloat64Array, _t: float) -> Dictionary:
	var q := M.q_normalized(s.slice(RB.ATT, RB.ATT + 4))
	var inverse := _p([q[0], -q[1], -q[2], -q[3]])
	var axle := _p([0, -1, 0])
	var geometry := Geometry.plane(s.slice(0, 3), M.q_rotate(q, axle), RADIUS, _zeros(3), _p([0, 0, -1]))
	if not geometry.ok: return {ok = false}
	var velocity_ned := M.q_rotate(q, s.slice(RB.VEL, RB.VEL + 3))
	var gap_rate := -velocity_ned[2]
	var normal := Normal.evaluate(_normal, -geometry.signed_gap_m, -gap_rate)
	if not normal.ok: return {ok = false}
	_highest_algebraic_load = maxf(_highest_algebraic_load, normal.normal_load_n)
	var n := M.q_rotate(inverse, _p([0, 0, -1]))
	var rho := M.q_rotate(inverse, geometry.hub_arm_ned)
	var force := M.scale(n, normal.normal_load_n)
	var moment := M.cross(rho, force)
	var spin := _p([s[13] * TAU / 60.0, s[14] / RADIUS])
	var rotor := Rotor.evaluate_system(_rotors, _p([1, 1, 1, 0, 0, 0]), s.slice(RB.RATE, RB.RATE + 3),
		spin, _rotors.reference_axes, _zeros(6), _zeros(6), moment, _p([0, 0, 0, moment[0], moment[1], moment[2]]), _p([_shaft_drive_torque, 0]))
	if not rotor.ok: return {ok = false}
	var body_rate := Datum.derivative_with_angular_acceleration(s.slice(0, RB.SIZE),
		{mass_kg = MASS, cg_body_m = _zeros(3), inertia = _p([1, 1, 1, 0, 0, 0]), inverse = _p([1, 1, 1, 0, 0, 0])},
		force, _gravity, rotor.angular_acceleration)
	var rate := body_rate.duplicate()
	rate.append(rotor.spin_acceleration[0] * 60 / TAU)
	rate.append(rotor.spin_acceleration[1] * RADIUS)
	var tangent := M.cross(axle, n)
	tangent = M.scale(tangent, 1.0 / M.norm(tangent))
	var side := M.cross(tangent, n)
	var rows := [Impulse.point_tangent(rho, rho, axle, 1, tangent, 2), Impulse.point_tangent(rho, rho, axle, 1, side, 2),
		Impulse.external_rolling(axle, 1, 2), Impulse.internal_brake(1, 2)]
	var jac := PackedFloat64Array()
	var bias := PackedFloat64Array()
	var limits := _p([_grip * normal.normal_load_n, _grip * normal.normal_load_n, _rolling * normal.normal_load_n * RADIUS, _brake])
	var groups: Array = [PackedInt32Array([0, 1]), PackedInt32Array([2]), PackedInt32Array([3])]
	if _cull_unloaded_wheel_rows and normal.normal_load_n == 0.0 and _brake == 0.0:
		rows.clear()
		limits = PackedFloat64Array()
		groups = []
	for row: Dictionary in rows:
		if not row.ok: return {ok = false}
		jac.append_array(row.row)
		bias.append(row.bias)
	var capture_row := bias.size()
	if _shaft_capture_selected:
		var shaft := Impulse.internal_brake(0, 2)
		jac.append_array(shaft.row)
		bias.append(0.0)
		limits.append(_shaft_friction_rate)
		groups.append(PackedInt32Array([capture_row]))
	var sample := {ok = true, format = Step.SAMPLE_FORMAT, fixed_hubs = true, static_ground = true, source_policy = "none",
		mass_kg = MASS, cg_body_m = _zeros(3), rotor_stage = rotor.stage,
		rotor_state_indices = PackedInt64Array([13, 14]), sigma_per_state = _p([TAU / 60.0, 1.0 / RADIUS]),
		nonnegative_rotors = PackedInt64Array([0]), jacobian = jac, slip_bias = bias,
		limit_rates = limits, groups = groups,
		contact_ids = PackedStringArray(["fixture_wheel"]), normal_load_n = _p([normal.normal_load_n]),
		potential_j = normal.potential_j - MASS * _gravity * s[2], normal_dissipation_w = normal.dissipation_w, external_power_w = _shaft_drive_torque * spin[0],
		derivative = rate, loads = force + moment}
	if _shaft_capture_selected: sample.capture = {rotor_index = 0, impulse_row = capture_row}
	return sample


func _derivative(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var evaluated := _evaluate(s, t)
	return evaluated.derivative if evaluated.ok else _p([NAN])


## Analytic WHOLE-PIECE fixture certificate, not an always-true callback.
## Both axes are body -y and hubs=CM. Initial motion and all rows stay in xz/
## pitch, so the world axle remains horizontal and rho is exactly vertical.
## Normal motion is m*xddot=m*g-k*x+ (unilateral), independent of tangent/brake.
## Vertical energy E=.5*m*vd²+.5*k*x+²-m*g*x bounds x and vd for ALL time.
func _certificate(s: PackedFloat64Array, _t: float, h: float, point: Dictionary) -> Dictionary:
	var q := M.q_normalized(s.slice(RB.ATT, RB.ATT + 4))
	var axle_world := M.q_rotate(q, _p([0, -1, 0]))
	var velocity := M.q_rotate(q, s.slice(RB.VEL, RB.VEL + 3))
	var invariant: bool = absf(axle_world[2]) < 1e-10 and absf(s[RB.RATE]) + absf(s[RB.RATE + 2]) < 1e-10 and absf(velocity[1]) < 1e-10
	if not invariant: return {ok = false, admitted = false, identity = "analytic-plane-pitch-invariant-v1"}
	var x := RADIUS + s[2]
	var energy := .5 * MASS * velocity[2] * velocity[2] + .5 * STIFFNESS * maxf(0, x) * maxf(0, x) - MASS * _gravity * x
	var offset := .5 * MASS * MASS * _gravity * _gravity / STIFFNESS
	var compression_bound := MASS * _gravity / STIFFNESS + sqrt(maxf(0, 2 * (energy + offset) / STIFFNESS))
	var speed_bound := sqrt(maxf(0, 2 * (energy + offset) / MASS))
	var envelope := Normal.bounds(_normal, compression_bound, speed_bound)
	var normal_row := {normal_body = M.q_rotate(_p([q[0], -q[1], -q[2], -q[3]]), _p([0, 0, -1])),
		arm_datum_body = M.q_rotate(_p([q[0], -q[1], -q[2], -q[3]]), _p([0, 0, RADIUS])), spin_jacobian = _zeros(2)}
	var mobility := Admission.mobility(MASS, _zeros(3), point.rotor_stage, [normal_row])
	if not mobility.ok or not envelope.ok: return {ok = false, admitted = false, identity = "analytic-plane-pitch-invariant-v1"}
	var local := Admission.admit(mobility.matrix, _p([envelope.position_derivative_bound_npm]), _p([envelope.rate_derivative_bound_nsm]), h, 1)
	# The energy bound remains below the declared mechanical-stop onset; no
	# geometric branch changes or unbounded nonlinear stop derivative is hidden.
	return {ok = compression_bound < .4 and speed_bound < 20, admitted = local.ok,
		identity = "analytic-plane-pitch-invariant-energy-envelope-v1"}


func _advance(state: PackedFloat64Array, t: float, h: float, options := {}) -> Dictionary:
	return Step.advance(state, t, h, _derivative, PackedFloat64Array(), _evaluate, _certificate, options)


func _operator_and_refinement() -> void:
	var initial := _initial(-.08, _p([3, 0, .3]))
	var before := initial.to_byte_array()
	var out := _advance(initial, 0, .04)
	_check("bounded normal+impulse operator accepts coupled fixture", out.get("ok", false), str(out))
	if not out.get("ok", false): return
	var receipt: Dictionary = out.integration_receipt
	_check("whole modal certificate actually forces refinement", receipt.accepted_substeps == 8)
	_check("receipt declares first-order split and algebraic quadrature", receipt.contact_operator_order == 1 and receipt.law == Step.LAW
		and receipt.quadrature_method.contains("not_damage") and receipt.normal_sampling_method.contains("not_interval_maximum"))
	_check("normal sampled receipt contains only accepted start/end boundaries", receipt.normal_samples_n.size() == 9 and receipt.normal_sample_times_s.size() == 9
		and receipt.normal_sample_times_s[0] == 0 and absf(receipt.normal_sample_times_s[-1] - .04) < 1e-15)
	_check("simultaneous friction spins the wheel and dissipates relative energy", out.state[14] > 0 and receipt.tangent_dissipation_j > 0 and receipt.absolute_impulse_sum > 0)
	_check("normal/contact work ledger closes", absf(receipt.energy_balance_residual_j) < 1e-6 and receipt.normal_dissipation_j == 0)
	_check("operator is pure and deterministic", initial.to_byte_array() == before and var_to_bytes(out) == var_to_bytes(_advance(initial, 0, .04)))
	var rejected := _advance(initial, 0, .2)
	_check("unaffordable normal envelope rejects without partial state/receipt", not rejected.ok and rejected.status == "admission_exhausted"
		and not rejected.has("state") and not rejected.has("integration_receipt"))
	# Full first-order split refinement, holding the same physical tape and time.
	var coarse := initial.duplicate()
	var fine := initial.duplicate()
	var finest := initial.duplicate()
	for i in 4: coarse = _advance(coarse, i * .01, .01).state
	for i in 8: fine = _advance(fine, i * .005, .005).state
	for i in 16: finest = _advance(finest, i * .0025, .0025).state
	_check("whole split refinement converges rather than claiming fourth order", absf(fine[14] - finest[14]) < absf(coarse[14] - finest[14]) + 1e-12)


func _damage_sampling() -> void:
	_gravity = 0
	_grip = 0
	_rolling = 0
	var h := 1.0 / 240.0
	var omega := sqrt(STIFFNESS / MASS)
	var initial := _initial(-.06, _p([0, 0, omega * .04 * tan(.5 * omega * h)]))
	_highest_algebraic_load = 0
	var out := _advance(initial, 0, h)
	_check("accepted sampling oracle integrates", out.ok)
	if out.ok:
		var r: Dictionary = out.integration_receipt
		var endpoints := maxf(STIFFNESS * .04, maxf(0, STIFFNESS * (out.state[2] + RADIUS)))
		_check("RK algebraic midpoint is higher than both accepted boundaries", _highest_algebraic_load > endpoints + .001)
		_check("algebraic high load cannot enter sampled damage peak", absf(r.sampled_peak_normal_n[0] - endpoints) < 1e-10
			and r.sampled_peak_normal_n[0] < _highest_algebraic_load)
	_gravity = 9.80665
	_grip = .6
	_rolling = .02


func _discarded_refinement() -> void:
	_gravity = 0
	var initial := _initial(-.8, _p([1, 0, 0]))
	var admitted_calls := [0]
	var certificate := func(s, t, h, _point):
		# Exact whole-interval free flight: no vertical motion/gravity, and the
		# wheel remains at least .7m above the plane. The owner asks for a finer
		# mesh after t=.02; n=2 therefore accepts a prefix then abandons it.
		var clear: bool = s[2] + RADIUS < -.6 and s[RB.VEL + 2] == 0.0 and M.norm(s.slice(RB.RATE, RB.RATE + 3)) == 0
		var allowed: float = .02 if t + h <= .020000000000001 else .01
		var admitted: bool = clear and h <= allowed + 1e-15
		if admitted: admitted_calls[0] += 1
		return {ok = clear, admitted = admitted, identity = "exact-airborne-piecewise-accuracy-envelope"}
	var out := Step.advance(initial, 0, .04, _derivative, PackedFloat64Array(), _evaluate, certificate)
	_check("refinement may abandon a previously accepted local prefix", out.ok and admitted_calls[0] == 5)
	if out.ok:
		var r: Dictionary = out.integration_receipt
		_check("receipt contains only final chosen four-piece path", r.accepted_substeps == 4 and r.normal_samples_n.size() == 5 and r.normal_sample_times_s.size() == 5)
		_check("abandoned prefix cannot duplicate work or impulses", r.normal_dissipation_j == 0 and r.tangent_dissipation_j == 0
			and r.absolute_impulse_sum == 0 and absf(out.state[0] - .04) < 1e-14)
	_gravity = 9.80665


func _damped_work() -> void:
	var original := _normal
	var raw: Dictionary = _normal.provenance.duplicate(true)
	raw.compression_damping.value = 3.0
	raw.rebound_damping.value = 2.0
	raw.damping_onset.value = .01
	_normal = Normal.prepare(raw)
	var out := _advance(_initial(-.08, _p([0, 0, .5])), 0, .01)
	_check("asymmetric normal damping composes with accepted quadrature", out.ok, str(out))
	if out.ok:
		var r: Dictionary = out.integration_receipt
		_check("normal heat is positive and distinct from tangent heat", r.normal_dissipation_j > 0 and r.tangent_dissipation_j == 0)
		_check("normal potential plus coupled kinetic loss equals quadrature heat", absf(r.final_mechanical_energy_j - r.initial_mechanical_energy_j + r.normal_dissipation_j) < 1e-6)
	_normal = original


func _joint(body: PackedFloat64Array, continuous: PackedFloat64Array, t: float) -> Dictionary:
	var state := body.duplicate()
	state.append_array(continuous)
	var sample := _evaluate(state, t)
	if not sample.ok: return {}
	return {loads = sample.loads, derivative = sample.derivative.slice(RB.SIZE), body_derivative = sample.derivative.slice(0, RB.SIZE), rotor_momentum = _zeros(3)}


func _simulation(initial: PackedFloat64Array, error_gate: Callable = Callable(), strict_shaft_domain := false) -> Node:
	var sim := Sim.new()
	sim.mass = MASS
	sim.inertia = _p([1, 1, 1, 0, 0, 0])
	sim.gravity = _gravity
	sim.aux = _zeros(5)
	sim.modes = PackedInt64Array([0])
	sim.continuous = initial.slice(RB.SIZE)
	var model := Model.new()
	model.aux_size = 5
	model.modes_size = 1
	model.continuous_size = 2
	model.state_layout_identity = "analytic-passive-plane-contact-step-fixture-v1"
	if strict_shaft_domain:
		model.state_layout_identity += ":finite-shaft-capture"
		model.state_validator = func(frame, _context): return frame.continuous[0] >= 0.0
	model.stage = _joint
	model.step_policy = func(s, t, h, f, k1): return Step.advance(s, t, h, f, k1, _evaluate, _certificate, {}, error_gate)
	model.endpoint_transition = func(_previous, candidate, context):
		if context.body_filtered or not context.has("integration_receipt"): return {}
		var receipt: Dictionary = context.integration_receipt
		candidate.aux[0] += receipt.normal_dissipation_j + receipt.tangent_dissipation_j
		candidate.aux[1] = receipt.accepted_substeps
		candidate.aux[2] = receipt.sampled_peak_normal_n[0]
		candidate.aux[3] = receipt.energy_balance_residual_j
		candidate.aux[4] = receipt.normal_samples_n[-1][0]
		candidate.events = []
		if candidate.modes[0] == 0 and receipt.sampled_peak_normal_n[0] > 0:
			candidate.modes[0] = 1
			candidate.events.append({type = "fixture_touchdown", time_s = receipt.sampled_peak_times_s[0]})
		elif candidate.modes[0] == 1 and receipt.normal_samples_n[-1][0] == 0:
			candidate.modes[0] = 2
			candidate.events.append({type = "fixture_liftoff", time_s = context.time_s})
		return candidate
	_check("actual VehicleModel accepts bounded step composer", sim.set_model(model))
	_check("kernel accepts fixture reset", sim.reset(initial.slice(0, RB.SIZE)), sim.fault_reason + " loads " + str(_evaluate(initial, 0).loads))
	return sim


func _kernel_drop_spin_brake_replay() -> void:
	var sim := _simulation(_initial())
	var seen := []
	sim.events_located.connect(func(_tick, events):
		for event: Dictionary in events: seen.append(event.type))
	var initial: PackedFloat64Array = sim.state.duplicate()
	initial.append_array(sim.continuous)
	var initial_energy := Step._energy(initial, _evaluate(initial, 0))
	for i in 170: sim.step()
	_check("one shared kernel publishes drop touchdown and passive rebound/liftoff", sim.tick == 170 and sim.fault_reason.is_empty()
		and seen.has("fixture_touchdown") and seen.has("fixture_liftoff"), sim.fault_reason)
	_check("touchdown spins hardware wheel and published heat is positive", sim.continuous[1] > .1 and sim.aux[0] > 0)
	var end: PackedFloat64Array = sim.state.duplicate()
	end.append_array(sim.continuous)
	_check("independent total mechanical energy plus accumulated contact loss closes", absf(Step._energy(end, _evaluate(end, sim.time())) + sim.aux[0] - initial_energy) < 1e-5)
	var checkpoint: Dictionary = sim.checkpoint()
	_check("checkpoint is kernel v2 and does not persist transient receipt", checkpoint.format == Sim.ENDPOINT_CHECKPOINT_FORMAT and not checkpoint.has("integration_receipt"))
	for i in 25: sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("kernel checkpoint restores the accepted coupled frame", sim.restore_checkpoint(checkpoint))
	for i in 25: sim.step()
	_check("checkpoint continuation is byte-exact through contact operator", expected == var_to_bytes(sim.checkpoint()))
	sim.free()
	# Airborne braking uses finite hardware torque even with exactly zero N.
	_brake = .2
	var airborne := _initial(-.8, _zeros(3))
	airborne[14] = 3.0
	var braked := _advance(airborne, 0, .04)
	_check("airborne brake acts independently of zero tire/rolling limits", braked.ok and braked.state[14] < 3.0
		and braked.integration_receipt.sampled_peak_normal_n[0] == 0 and braked.integration_receipt.tangent_dissipation_j > 0)
	_brake = 0


func _rejections() -> void:
	var initial := _initial()
	for kind: String in ["moving_hub", "moving_ground", "source", "events", "stale_spin", "negative_limit", "nonfinite", "hold", "prescribed_slip", "untyped_flag"]:
		var sample: Callable = func(s, t):
			var p := _evaluate(s, t)
			match kind:
				"moving_hub": p.fixed_hubs = false
				"moving_ground": p.static_ground = false
				"source": p.source_policy = "glow"
				"events": p.source_events = [{type = "fuel_exhausted"}]
				"stale_spin": p.rotor_stage.velocity[3] += 1
				"negative_limit": p.limit_rates[0] = -1
				"nonfinite": p.normal_load_n[0] = NAN
				"hold": p.rotor_stage.hold_indices = PackedInt64Array([0])
				"prescribed_slip": p.slip_bias[0] = .1
				"untyped_flag": p.fixed_hubs = 1
			return p
		var rejected := Step.advance(initial, 0, .004, _derivative, PackedFloat64Array(), sample, _certificate)
		_check("unsupported/malformed domain never publishes state or receipt: " + kind, not rejected.ok and not rejected.has("state") and not rejected.has("integration_receipt"))
	var reverse := initial.duplicate()
	reverse[13] = -1
	_check("unsupported reverse shaft rejects explicitly", _advance(reverse, 0, .004).status == "unsupported_reverse")
	var bad_certificate := func(_s, _t, _h, _p): return {ok = true, admitted = true}
	_check("uncertified callback cannot masquerade as an interval certificate", not Step.advance(initial, 0, .004, _derivative, PackedFloat64Array(), _evaluate, bad_certificate).ok)
	_check("nonphysical refinement option rejected", not _advance(initial, 0, .004, {max_substeps = 32}).ok)
	# A deliberately inconsistent derivative cannot create unexplained accepted work.
	var wrong := func(s, t):
		var rate := _derivative(s, t)
		rate[RB.VEL] += 100.0
		return rate
	var unexplained := Step.advance(initial, 0, .004, wrong, PackedFloat64Array(), _evaluate, _certificate)
	_check("unexplained free-flow energy never publishes a partial approximation", not unexplained.ok and not unexplained.has("state"))
	var sim := _simulation(initial)
	var before := var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs, sim.last_loads])
	var publications := [0]
	sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): publications[0] += 1)
	sim.model.step_policy = func(s, t, h, f, k1): return Step.advance(s, t, h, f, k1, _evaluate,
		func(_s, _t, _h, _p): return {ok = true, admitted = false, identity = "analytic-envelope-unaffordable"})
	sim.step()
	_check("kernel rolls back failed contact admission without observer publication", sim.tick == 0 and not sim.fault_reason.is_empty() and publications[0] == 0)
	_check("failed candidate leaves complete accepted frame unchanged", before == var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes, sim.inputs, sim.last_loads]))
	_check("faulted numerical admission cannot export a flying checkpoint", sim.checkpoint().is_empty())
	sim.free()


## Deliberately versioned FIXTURE accuracy, not proposed stock-flight tolerances.
## Compare world-CM velocity, rotation, all spins in rad/s and local contact work;
## no absolute NED or total stored shaft energy inflates the normalization.
func _path_error(a: PackedFloat64Array, b: PackedFloat64Array, ar: Dictionary, br: Dictionary,
		_dt: float, wheel_spin_atol := .03) -> Dictionary:
	var error := 0.0
	for i in 3: error = maxf(error, absf(a[i] - b[i]) / 1e-4)
	var qa := M.q_normalized(a.slice(RB.ATT, RB.ATT + 4))
	var qb := M.q_normalized(b.slice(RB.ATT, RB.ATT + 4))
	var va := M.q_rotate(qa, a.slice(RB.VEL, RB.VEL + 3))
	var vb := M.q_rotate(qb, b.slice(RB.VEL, RB.VEL + 3))
	for i in 3:
		error = maxf(error, absf(va[i] - vb[i]) / .003)
		error = maxf(error, absf(a[RB.RATE + i] - b[RB.RATE + i]) / .001)
	var cosine := 0.0
	for i in 4: cosine += qa[i] * qb[i]
	error = maxf(error, 2 * acos(clampf(absf(cosine), 0, 1)) / 1e-4)
	error = maxf(error, absf(a[13] - b[13]) * TAU / 60.0 / .001)
	error = maxf(error, absf(a[14] - b[14]) / RADIUS / wheel_spin_atol)
	error = maxf(error, absf(ar.normal_dissipation_j - br.normal_dissipation_j) / .03)
	error = maxf(error, absf(ar.tangent_dissipation_j - br.tangent_dissipation_j) / .03)
	return {ok = true, admitted = error <= 1.0, normalized_error = error,
		identity = "analytic-plane-first-order-fixture-spin-atol-" + str(wheel_spin_atol) + "-radps-v1"}


func _paired_paths() -> void:
	_gravity = 0
	_rolling = 0
	var initial := _initial(-.06, _p([3, 0, 0]))
	var seen := []
	var gate := func(a, b, ar, br, h):
		seen.append([ar.accepted_substeps, br.accepted_substeps])
		return _path_error(a, b, ar, br, h, .001)
	var out := Step.advance(initial, 0, .01, _derivative, PackedFloat64Array(), _evaluate, _certificate, {}, gate)
	_check("paired complete-path gate eventually accepts a finer composition", out.ok, str(out))
	if out.ok:
		var r: Dictionary = out.integration_receipt
		_check("real unit-scaled error requests pair retries", seen.size() == 3 and seen[0] == [2, 4] and seen[-1] == [8, 16], str(seen))
		_check("only final finer path normal samples are published", r.accepted_substeps == 16 and r.normal_samples_n.size() == 17
			and r.error_control.coarse_substeps == 8 and r.error_control.fine_substeps == 16)
		_check("receipt pins gate identity and raw normalized difference", r.error_control.normalized_error <= 1
			and r.error_control.identity.contains("0.001") and r.error_control.method.contains("no_Richardson"))
		var omega := sqrt(STIFFNESS / MASS)
		var exact_rim := _grip * STIFFNESS * .04 * sin(omega * .01) / omega
		var coarse := _advance(initial, 0, .01)
		_check("independent continuous sliding oracle confirms finer first-order rim result", absf(out.state[14] - exact_rim) < .00015
			and absf(out.state[14] - exact_rim) < absf(coarse.state[14] - exact_rim))
		_check("paired deterministic result does not retain trial receipts", var_to_bytes(out) == var_to_bytes(Step.advance(initial, 0, .01,
			_derivative, PackedFloat64Array(), _evaluate, _certificate, {}, _path_error.bind(.001))))
	var tight := Step.advance(initial, 0, .01, _derivative, PackedFloat64Array(), _evaluate, _certificate, {}, _path_error.bind(1e-10))
	_check("unaffordable paired accuracy rejects with no approximate state or receipt", not tight.ok and tight.status == "error_control_exhausted"
		and not tight.has("state") and not tight.has("integration_receipt"))
	var identity_calls := [0]
	var changing_identity := func(a, b, ar, br, h):
		identity_calls[0] += 1
		var judged := _path_error(a, b, ar, br, h, .001)
		judged.identity = "changing-accuracy-" + str(identity_calls[0])
		return judged
	var drift := Step.advance(initial, 0, .01, _derivative, PackedFloat64Array(), _evaluate, _certificate, {}, changing_identity)
	_check("accuracy identity cannot drift between paired comparisons", not drift.ok and drift.status == "invalid_error_gate" and not drift.has("state"))
	var only16 := func(s, t, h, p):
		var physical := _certificate(s, t, h, p)
		physical.admitted = physical.admitted and h <= .01 / 16.0 + 1e-15
		return physical
	var unpaired := Step.advance(initial, 0, .01, _derivative, PackedFloat64Array(), _evaluate, only16, {}, _path_error)
	_check("a first admissible 16-piece path is not falsely called refinement-checked", not unpaired.ok and unpaired.status == "error_control_exhausted")
	var old_frequency := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 100
	var sim := _simulation(initial, _path_error.bind(.03))
	sim.step()
	_check("actual kernel accepts a completely compared finer contact path", sim.tick == 1 and sim.fault_reason.is_empty() and sim.aux[1] >= 2 and sim.aux[1] <= 16, sim.fault_reason)
	var checkpoint: Dictionary = sim.checkpoint()
	sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("paired accepted checkpoint restores", sim.restore_checkpoint(checkpoint))
	sim.step()
	_check("paired policy checkpoint continuation is byte-exact", expected == var_to_bytes(sim.checkpoint()) and sim.tick == 2, sim.fault_reason)
	sim.free()
	Engine.physics_ticks_per_second = old_frequency
	_gravity = 9.80665
	_rolling = .02


func _error_gate_rejections() -> void:
	_gravity = 0
	_rolling = 0
	var initial := _initial(-.06, _p([3, 0, 0]))
	var original := initial.to_byte_array()
	for kind: String in ["type", "negative", "nan", "identity", "oversize", "extra", "inconsistent", "mutate_state", "mutate_receipt", "decline"]:
		var bad := func(a, b, ar, br, h):
			var judged := _path_error(a, b, ar, br, h)
			match kind:
				"type": return []
				"negative": judged.normalized_error = -1.0
				"nan": judged.normalized_error = NAN
				"identity": judged.identity = 3
				"oversize": judged.identity = "x".repeat(257)
				"extra": judged.unknown = self
				"inconsistent":
					judged.admitted = true
					judged.normalized_error = 2.0
				"mutate_state": b[0] += 1
				"mutate_receipt": br.normal_samples_n[0][0] += 1
				"decline": judged.ok = false
			return judged
		var rejected := Step.advance(initial, 0, .01, _derivative, PackedFloat64Array(), _evaluate, _certificate, {}, bad)
		_check("malformed/mutating error gate is atomic: " + kind, not rejected.ok and not rejected.has("state")
			and not rejected.has("integration_receipt") and initial.to_byte_array() == original)
	var oversized := _zeros(Step.MAX_STATE_SIZE + 1)
	oversized[RB.ATT] = 1
	_check("comparison state size is bounded before callback allocation", not Step.advance(oversized, 0, .01, _derivative,
		PackedFloat64Array(), _evaluate, _certificate, {}, _path_error).ok)
	_gravity = 9.80665
	_rolling = .02
	var sim := _simulation(_initial())
	var before := var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes])
	var published := [0]
	sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): published[0] += 1)
	sim.model.step_policy = func(s, t, h, f, k1): return Step.advance(s, t, h, f, k1, _evaluate, _certificate, {},
		func(_a, b, _ar, _br, _h):
			b[0] += 1
			return {ok = true, admitted = true, identity = "mutating-gate", normalized_error = 0.0})
	sim.step()
	_check("actual kernel rejects mutating pair gate without publication", sim.tick == 0 and not sim.fault_reason.is_empty() and published[0] == 0
		and before == var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes]))
	sim.free()


func _fixture_angular_momentum(s: PackedFloat64Array) -> PackedFloat64Array:
	# Independent locked-tensor plus axial cross terms, in the frozen body frame.
	return M.add(s.slice(RB.RATE, RB.RATE + 3), M.scale(_p([0, -1, 0]), .02 * s[13] * TAU / 60.0 + .01 * s[14] / RADIUS))


func _two_sided() -> void:
	_gravity=0.0
	_grip=.6
	_rolling=0.0
	_brake=0.0
	var options := {operator_law=Step.TWO_SIDED_LAW}
	var initial := _initial(-.06,_p([3,0,0]))
	var first := _derivative(initial,0.0)
	first.fill(1e50) # valid but stale: the pre-kick MUST replace every k1 channel.
	var before := var_to_bytes([initial,first,options])
	var seen_rates := []
	var seen_certificate := []
	var derivative := func(s,t):
		if t==0.0: seen_rates.append(s[RB.VEL])
		return _derivative(s,t)
	var certificate := func(s,t,h,p):
		if t==0.0: seen_certificate.append(s[RB.VEL])
		return _certificate(s,t,h,p)
	var h:=.004
	var out := Step.advance(initial,0.0,h,derivative,first,_evaluate,certificate,options)
	_check("two-sided actual coupled operator accepts one qualified piece",out.ok and out.integration_receipt.accepted_substeps==1,str(out))
	if out.ok:
		var r:Dictionary=out.integration_receipt
		_check("two-sided receipt has a distinct first-order law",r.law==Step.TWO_SIDED_LAW and r.contact_operator_order==1
			and r.split_method.contains("order1") and r.normal_sampling_method.contains("not_interval_maximum"))
		_check("free interval certificate sees post-first-kick velocity",not seen_certificate.is_empty() and seen_certificate[0]<initial[RB.VEL])
		_check("continuous k1 sees post-first-kick velocity",not seen_rates.is_empty() and seen_rates[0]<initial[RB.VEL])
		# Normal force is vertical in world space. During the free interval,
		# horizontal CM velocity is constant at its first-kick value; the second
		# kick cannot alter position. This oracle catches stale initial k1.
		var x0:=RADIUS+initial[2]
		var expected_x:float=initial[0]+(initial[RB.VEL]-_grip*STIFFNESS*x0*(h*.5)/MASS)*h
		_check("independent horizontal position oracle includes first kick",absf(out.state[0]-expected_x)<1e-11,str([out.state[0],expected_x]))
		_check("both endpoint impulses have separate positive passive losses",r.pre_contact_dissipation_j>0.0 and r.post_contact_dissipation_j>0.0
			and absf(r.tangent_dissipation_j-r.pre_contact_dissipation_j-r.post_contact_dissipation_j)<1e-14)
		# Independent RK4 oscillator amplification: |P(i theta)|^2-1
		# = -theta^6/72 + theta^8/576. The friction halves close exactly;
		# this known conservative RK defect is not missing contact heat.
		var theta2:=STIFFNESS/MASS*h*h
		var theta6:=theta2*theta2*theta2
		var exact_rk_defect:=.5*STIFFNESS*x0*x0*(-theta6/72.0+theta6*theta2/576.0)
		_check("both prescribed works sum once and residual matches analytic RK4 defect",absf(r.prescribed_contact_work_j-r.pre_prescribed_contact_work_j-r.post_prescribed_contact_work_j)<1e-14
			and absf(r.energy_balance_residual_j-exact_rk_defect)<1e-12,str([r.energy_balance_residual_j,exact_rk_defect]))
		_check("boundary samples remain distinct from interval extrema",r.normal_samples_n.size()==2 and r.normal_sample_times_s.size()==2
			and r.quadrature_method=="RK4_algebraic_stage_weights_not_damage_samples")
	_check("two-sided inputs and supplied stale k1 are detached",before==var_to_bytes([initial,first,options]))
	var repeated:=Step.advance(initial,0.0,h,_derivative,PackedFloat64Array(),_evaluate,_certificate,options)
	_check("ignored stale first derivative cannot change complete deterministic output",out.ok and var_to_bytes(out)==var_to_bytes(repeated))
	var ordinary:=_advance(initial,0.0,h)
	var explicit_default:=_advance(initial,0.0,h,{operator_law=Step.LAW,maximum_assembly_resolution_j=-1.0})
	_check("explicit defaults preserve complete default receipt bytes",ordinary.ok and var_to_bytes(ordinary)==var_to_bytes(explicit_default)
		and not ordinary.integration_receipt.has("assembly_resolution"))
	var zero_ceiling:=Step.advance(initial,0.0,h,_derivative,PackedFloat64Array(),_evaluate,_certificate,
		{operator_law=Step.TWO_SIDED_LAW,maximum_assembly_resolution_j=0.0})
	_check("explicit zero ceiling cannot loosen an ordinary strict optimum",zero_ceiling.ok
		and zero_ceiling.integration_receipt.assembly_resolution.accepted_at_resolution==0)
	for bad:Dictionary in [{operator_law="unknown"},{operator_law=3},{maximum_assembly_resolution_j=-.5},
		{maximum_assembly_resolution_j=INF},{maximum_assembly_resolution_j=NAN},{maximum_assembly_resolution_j=true}]:
		var refused:=_advance(initial,0.0,h,bad)
		_check("invalid operator/resolution options refuse without partial publication",not refused.ok and not refused.has("state") and not refused.has("integration_receipt"))
	var selected_failures:Array=[]
	selected_failures.append(_advance(initial,0.0,.2,options))
	selected_failures.append(_advance(initial,0.0,h,{operator_law=Step.TWO_SIDED_LAW,maximum_assembly_resolution_j=-.5}))
	selected_failures.append(Step.advance(initial,0.0,h,Callable(),PackedFloat64Array(),_evaluate,_certificate,options))
	selected_failures.append(Step.advance(initial,0.0,h,_derivative,PackedFloat64Array(),
		func(_s,_t):return {ok=false},_certificate,options))
	selected_failures.append(Step.advance(initial,0.0,h,_derivative,PackedFloat64Array(),_evaluate,_certificate,options,
		func(_a,_b,_ar,_br,_h):return {ok=true,admitted=false,identity="too-strict-selected-path",normalized_error=2.0}))
	for refusal:Dictionary in selected_failures:
		_check("all selected-operator failure seams retain requested law",not refusal.ok and refusal.law==Step.TWO_SIDED_LAW
			and not refusal.has("state") and not refusal.has("integration_receipt"),str(refusal))
	# Finite shaft capture is exercised on BOTH halves: pre-kick captures the
	# initial spin; a smooth internal drive during RK creates a small new spin
	# that the post-kick captures with its own finite capacity and loss.
	_shaft_capture_selected=true
	_shaft_friction_rate=100.0
	_shaft_drive_torque=.01
	var airborne:=_initial(-.8,_zeros(3))
	airborne[13]=.1
	var captured:=Step.advance(airborne,0.0,h,_derivative,PackedFloat64Array(),_evaluate,_certificate,options)
	_check("two-sided finite shaft capture reaches exact zero",captured.ok and captured.state[13]==0.0,str(captured))
	if captured.ok:
		_check("both capture halves retain positive physical loss",captured.integration_receipt.pre_contact_dissipation_j>0.0
			and captured.integration_receipt.post_contact_dissipation_j>0.0)
		_check("drive work and both capture losses close independently",absf(captured.integration_receipt.energy_balance_residual_j)<1e-12
			and captured.integration_receipt.external_work_j>0.0)
	var captured_sim:=_simulation(airborne,Callable(),true)
	captured_sim.model.step_policy=func(s,t,dt,f,k1):return Step.advance(s,t,dt,f,k1,_evaluate,_certificate,options)
	captured_sim.step()
	_check("actual kernel accepts selected two-sided capture",captured_sim.tick==1 and captured_sim.fault_reason.is_empty()
		and captured_sim.continuous[0]==0.0,captured_sim.fault_reason)
	var captured_checkpoint:Dictionary=captured_sim.checkpoint()
	captured_sim.step()
	var captured_expected:=var_to_bytes(captured_sim.checkpoint())
	_check("two-sided captured checkpoint restores",captured_sim.restore_checkpoint(captured_checkpoint))
	captured_sim.step()
	_check("two-sided captured continuation is byte identical",captured_expected==var_to_bytes(captured_sim.checkpoint())
		and captured_sim.tick==2,captured_sim.fault_reason)
	captured_sim.free()
	_shaft_capture_selected=false
	_shaft_friction_rate=0.0
	_shaft_drive_torque=0.0
	# The first halfkick may be computed in a trial, but an interval refusal
	# must roll back all kernel body/spin/work state and publish no events.
	var sim:=_simulation(initial)
	var frame:=var_to_bytes([sim.state,sim.previous,sim.continuous,sim.aux,sim.modes])
	var publications:=[0]
	sim.stepped.connect(func(_a,_b,_c,_d,_e,_f):publications[0]+=1)
	sim.model.step_policy=func(s,t,dt,f,k1):return Step.advance(s,t,dt,f,k1,_evaluate,
		func(_s,_t,_h,_p):return {ok=true,admitted=false,identity="post-kick-interval-refusal"},options)
	sim.step()
	_check("post-first-kick interval refusal is atomic in actual kernel",sim.tick==0 and not sim.fault_reason.is_empty()
		and publications[0]==0 and frame==var_to_bytes([sim.state,sim.previous,sim.continuous,sim.aux,sim.modes]))
	sim.free()
	_gravity=9.80665
	_rolling=.02
	_resolution_passthrough()


func _resolution_passthrough() -> void:
	# Manufactured zero-ODE/frozen-pose mechanics ONLY, to isolate passthrough
	# of the exact retained physical Gram/slip operands. This is not a flight or
	# normal-support model. The invariant ODE has an exact whole-interval proof.
	var file:=FileAccess.open("res://tests/fixtures/ground_traction_rest_symmetric16.bin",FileAccess.READ)
	var raw:Dictionary=bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	var initial:=RB.make_state(_zeros(3),raw.velocity_cm_body,M.q_identity(),raw.stage.velocity.slice(0,3))
	initial.append_array(raw.stage.velocity.slice(3))
	var dt:=1.0/240.0
	for law:String in [Step.LAW,Step.TWO_SIDED_LAW]:
		var evaluate:=func(s,_t):
			var stage:Dictionary=raw.stage.duplicate(true)
			stage.velocity=s.slice(RB.RATE,RB.RATE+3)
			stage.velocity.append_array(s.slice(RB.SIZE))
			var limits:PackedFloat64Array=raw.limits.duplicate()
			for i in limits.size(): limits[i]*=(2.0 if law==Step.TWO_SIDED_LAW else 1.0)/dt
			return {ok=true,format=Step.SAMPLE_FORMAT,fixed_hubs=true,static_ground=true,source_policy="none",
				mass_kg=raw.mass_kg,cg_body_m=_zeros(3),rotor_stage=stage,
				rotor_state_indices=PackedInt64Array([13,14,15,16]),sigma_per_state=_p([1,1,1,1]),
				nonnegative_rotors=PackedInt64Array(),jacobian=raw.jacobian,slip_bias=raw.prescribed_slip_bias,
				limit_rates=limits,groups=raw.groups,contact_ids=PackedStringArray(),normal_load_n=PackedFloat64Array(),
				potential_j=0.0,normal_dissipation_w=0.0,external_power_w=0.0}
		var derivative:=func(s,_t):return _zeros(s.size())
		var invariant:=func(s,_t,h,_p):return {ok=s==initial and h>0.0 and h<=dt,
			admitted=s==initial and h>0.0 and h<=dt,identity="manufactured-zero-ODE-exact-invariant-v1"}
		var strict:=Step.advance(initial,0.0,dt,derivative,PackedFloat64Array(),evaluate,invariant,{operator_law=law})
		_check("exact unresolved assembly preserves default strict refusal: "+law,not strict.ok)
		var qualified:=Step.advance(initial,0.0,dt,derivative,PackedFloat64Array(),evaluate,invariant,
			{operator_law=law,maximum_assembly_resolution_j=1e-12})
		_check("owner ceiling reaches every selected impulse: "+law,qualified.ok,str(qualified))
		if qualified.ok:
			var proof:Dictionary=qualified.integration_receipt.assembly_resolution
			_check("only accepted numerical-resolution proofs are accumulated: "+law,
				proof.accepted_at_resolution==(2 if law==Step.TWO_SIDED_LAW else 1)
				and proof.maximum_derived_gamma_j>0.0 and proof.derived_gamma_sum_j<=2e-12
				and qualified.integration_receipt.tangent_dissipation_j==0.0)


func _capture_passthrough() -> void:
	# Absent and explicitly empty capture both keep the original complete output.
	var normal_initial := _initial(-.08, _p([3, 0, .3]))
	var ordinary := _advance(normal_initial, 0, .004)
	var empty := func(s, t):
		var point := _evaluate(s, t)
		point.capture = {}
		return point
	var explicit_empty := Step.advance(normal_initial, 0, .004, _derivative, PackedFloat64Array(), empty, _certificate)
	_check("absent/empty capture preserve complete default result bytes", ordinary.ok and var_to_bytes(ordinary) == var_to_bytes(explicit_empty))
	_gravity = 0
	_shaft_capture_selected = true
	_shaft_friction_rate = 100.0
	var picked := _initial(-.8, _zeros(3))
	var recovered_negative_roundoff := 0
	for rpm: float in [.1, .2, .3, 1, 2, 3, 7, 11, 30, 100]:
		var initial := _initial(-.8, _zeros(3))
		initial[13] = rpm
		var uncaptured := func(s, t):
			var point := _evaluate(s, t)
			point.erase("capture")
			return point
		var raw := Step.advance(initial, 0, 1.0 / 240.0, _derivative, PackedFloat64Array(), uncaptured, _certificate)
		var out := _advance(initial, 0, 1.0 / 240.0)
		_check("finite shaft capture composes to exact-zero RPM", out.ok and out.state[13] == 0.0, str(out))
		if out.ok:
			var q0 := M.q_normalized(initial.slice(RB.ATT, RB.ATT + 4))
			var q1 := M.q_normalized(out.state.slice(RB.ATT, RB.ATT + 4))
			_check("complete capture conserves world body+shaft+wheel momentum", M.norm(M.sub(M.q_rotate(q1, _fixture_angular_momentum(out.state)), M.q_rotate(q0, _fixture_angular_momentum(initial)))) < 1e-12)
			_check("shaft capture updates body and unbraked wheel with positive finite loss", absf(out.state[RB.RATE + 1]) > 0 and absf(out.state[14]) > 0
				and out.integration_receipt.tangent_dissipation_j > 0 and absf(out.integration_receipt.energy_balance_residual_j) < 1e-12)
		if not raw.ok and raw.status == "unsupported_reverse":
			recovered_negative_roundoff += 1
			picked = initial
	_check("step passthrough resolves actual negative-roundoff domain refusals", recovered_negative_roundoff > 0)
	var sim := _simulation(picked, Callable(), true)
	sim.step()
	_check("strict nonnegative kernel admits finite captured endpoint", sim.tick == 1 and sim.fault_reason.is_empty() and sim.continuous[0] == 0.0, sim.fault_reason)
	var checkpoint: Dictionary = sim.checkpoint()
	_check("captured complete step exports strict valid checkpoint", checkpoint.get("format", "") == Sim.ENDPOINT_CHECKPOINT_FORMAT and checkpoint.continuous[0] == 0.0)
	sim.step()
	var expected := var_to_bytes(sim.checkpoint())
	_check("captured complete-step checkpoint restores", sim.restore_checkpoint(checkpoint))
	sim.step()
	_check("captured complete-step replay is byte-exact", sim.tick == 2 and expected == var_to_bytes(sim.checkpoint()), sim.fault_reason)
	sim.free()
	_shaft_friction_rate = 1e-6
	var insufficient := _initial(-.8, _zeros(3))
	insufficient[13] = 1.0
	var moving := _advance(insufficient, 0, 1.0 / 240.0)
	_check("insufficient positive friction budget preserves moving shaft", moving.ok and moving.state[13] > 0.0 and moving.state[13] < 1.0)
	# A smooth internal negative drive overwhelms finite friction in the free
	# predictor; this is unsupported reverse, not a numerical one-way clutch.
	_shaft_drive_torque = -1.0
	_shaft_friction_rate = .01
	var driven := _initial(-.8, _zeros(3))
	driven[13] = .01
	var rejected := _advance(driven, 0, 1.0 / 240.0)
	_check("finite capture cannot clamp real reverse under insufficient capacity", not rejected.ok and not rejected.has("state") and not rejected.has("integration_receipt"))
	sim = _simulation(driven, Callable(), true)
	var before := var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes])
	var publications := [0]
	sim.stepped.connect(func(_a, _b, _c, _d, _e, _f): publications[0] += 1)
	sim.step()
	_check("reverse breakaway rolls back complete kernel frame without publication", sim.tick == 0 and not sim.fault_reason.is_empty()
		and publications[0] == 0 and before == var_to_bytes([sim.state, sim.previous, sim.continuous, sim.aux, sim.modes]))
	sim.free()
	_shaft_capture_selected = false
	_shaft_friction_rate = 0
	_shaft_drive_torque = 0
	_gravity = 9.80665


func _capture_bindings() -> void:
	_gravity = 0
	_grip = 0
	_rolling = 0
	_shaft_capture_selected = true
	_shaft_friction_rate = 100
	_cull_unloaded_wheel_rows = true
	# Exact undamped plane solution unloads at t=.02, a retained boundary for
	# every admissible power-of-two mesh here; this isolates row-layout binding.
	var omega := sqrt(STIFFNESS / MASS)
	var initial := _initial(-.08, _p([0, 0, -omega * .02 / tan(omega * .02)]))
	initial[13] = 1.0
	var ordinals := []
	var changing_rows := func(s, t):
		var point := _evaluate(s, t)
		ordinals.append(point.capture.impulse_row)
		return point
	var out := Step.advance(initial, 0, .04, _derivative, PackedFloat64Array(), changing_rows, _certificate)
	_check("capture row ordinal may change with loaded contact rows", out.ok and out.state[13] == 0.0 and ordinals.has(4) and ordinals.has(0), str(out))
	_cull_unloaded_wheel_rows = false
	var rest := _initial(-.8, _zeros(3))
	rest[13] = 1.0
	for kind: String in ["wrong_type", "extra", "outside", "wheel_domain", "wrong_row", "target_switch", "disappear", "source_event"]:
		var sample := func(s, t):
			var p := _evaluate(s, t)
			match kind:
				"wrong_type": p.capture = []
				"extra": p.capture.force_clamp = true
				"outside": p.capture.rotor_index = 2
				"wheel_domain":
					p.capture.rotor_index = 1
					for i in 8: p.jacobian[4 * 8 + i] = 1.0 if i == 7 else 0.0
				"wrong_row": p.capture.impulse_row = 0
				"target_switch":
					p.nonnegative_rotors = PackedInt64Array([0, 1])
					if t > 0:
						p.capture.rotor_index = 1
						for i in 8: p.jacobian[4 * 8 + i] = 1.0 if i == 7 else 0.0
				"disappear":
					if t > 0: p.erase("capture")
				"source_event": p.source_events = [{type = "forbidden"}]
			return p
		var rejected := Step.advance(rest, 0, 1.0 / 240.0, _derivative, PackedFloat64Array(), sample, _certificate)
		_check("capture mapping/domain inconsistency fails atomically: " + kind, not rejected.ok and not rejected.has("state") and not rejected.has("integration_receipt"))
	_shaft_capture_selected = false
	_shaft_friction_rate = 0
	_gravity = 9.80665
	_grip = .6
	_rolling = .02
