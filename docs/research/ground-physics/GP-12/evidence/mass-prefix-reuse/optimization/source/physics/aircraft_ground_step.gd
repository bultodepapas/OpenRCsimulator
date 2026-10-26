## Bounded fixed-hub contact operator. Default: RK4 normal/free flow followed by one
## simultaneous mobility-metric tangent/brake/rolling impulse. Overall order ONE.
## Owner supplies a whole-piece certificate; local modal admission is not one.
extends RefCounted

const RK := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/integrator.gd")
const RB := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rigid_body.gd")
const RC := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rotor_coupling.gd")
const Impulse := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_impulse.gd")
const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")
const LAW := "fixed-hub-rk4-normal-endpoint-impulse-lie-v1"
const TWO_SIDED_LAW := "fixed-hub-half-impulse-rk4-normal-half-impulse-v1"
const SAMPLE_FORMAT := "openrc-aircraft-ground-step-sample v1"
const RECEIPT_FORMAT := "openrc-aircraft-ground-integration v1"
const MAX_SUBSTEPS := 16
const MAX_CONTACTS := 16
const MAX_STATE_SIZE := 256


## evaluate(s,t) returns SAMPLE_FORMAT, mass_kg,cg_body_m,rotor_stage,
## rotor_state_indices:int64[N],sigma_per_state:float64[N],nonnegative_rotors:int64[],
## jacobian,slip_bias,limit_rates,groups,contact_ids,normal_load_n,potential_j,
## normal_dissipation_w,external_power_w, fixed_hubs/static_ground=true,
## source_policy="none". potential_j is ALL recoverable nonkinetic energy,
## external_power_w excludes conservative forces and normal dissipation.
## Optional capture={rotor_index:int,impulse_row:int} names the same finite
## internal friction row as GroundImpulse. The rotor must be declared
## nonnegative; its row ordinal may change as physical wheel rows load/unload.
## certificate(s,t,h,sample)->{ok,admitted,identity:String}; its owner certifies
## the WHOLE free interval, including entry/geometry and constitutive envelopes.
## The initial slice supports no source events, moving hubs or carrier motion.
## Optional error_gate(coarse_state,fine_state,coarse_receipt,fine_receipt,dt)
## returns EXACTLY {ok,admitted,identity,normalized_error}. Inputs are read-only;
## compare COMPLETE first-order split paths, in owner-declared physical scales.
## Only the finer 2n path can publish. No Richardson/15 or fourth-order claim.
## options.operator_law selects LAW (default Lie) or TWO_SIDED_LAW. Both declare
## order ONE: the frozen finite-QP friction map is not a self-adjoint exact flow.
## Two-sided uses half impulse / freshly evaluated RK4 / half impulse; the whole
## free interval certificate sees the post-first-impulse velocities. Boundary
## normal samples are never asserted to be interval or halfkick maxima.
## maximum_assembly_resolution_j defaults -1 (strict); any >=0 value explicitly
## enables the assembly-resolution contract and is a PER-QP energy ceiling.
## The owner allocates its tick budget over at most 2*16 accepted solves, e.g.
## tick_budget/32. Discarded attempts publish no proof or work. The accepted
## opt-in receipt retains outward sums of actual Gamma/objective-gap bounds.
## Optional normal_loss_policy(s,t,h,sample)->EXACT {ok,eligible,identity} is
## trusted OWNER authority, like derivative/certificate, not receipt metadata.
## It runs after the actual prekick and must bind/revalidate its actual evaluator,
## fixed mechanics/provider and interval source/brake/external-wrench exclusions.
## Generic Step cannot authenticate captured closures. Eligible samples provide
## normal_support_potential_j>=0 and a stable normal_support_identity; all actual
## RK normal evaluations and endpoint loads must be zero. Heat is the per-piece
## support-potential decrease (no gravity/clamp), before piece-energy admission.
## Otherwise RK heat is unchanged. Opted-in receipts explicitly record every
## piece method/loss/residual; an absent policy preserves legacy receipt bytes.
static func advance(initial: PackedFloat64Array, time_s: float, dt: float,
		derivative: Callable, first: PackedFloat64Array, evaluate: Callable,
		certificate: Callable, options: Dictionary = {}, error_gate: Callable = Callable(),
		normal_loss_policy: Callable = Callable(),mass_proof:RefCounted=null) -> Dictionary:
	var settings := _settings(options)
	if not settings.ok: return _operator_failure(settings,options)
	if not _state(initial) or not is_finite(time_s) or time_s < 0.0 or not is_finite(dt) \
		or dt <= 0.0 or dt > 1.0 or not is_finite(time_s + dt) or time_s + dt <= time_s \
		or not derivative.is_valid() or not evaluate.is_valid() or not certificate.is_valid() \
		or (not first.is_empty() and (first.size() != initial.size() or not _finite(first))):
		return _operator_failure(_failure("invalid bounded state, time or callbacks"),settings)
	if not normal_loss_policy.is_null() and (not normal_loss_policy.is_valid() or normal_loss_policy.get_argument_count()!=4):
		return _operator_failure(_failure("normal loss policy requires exactly four arguments", "invalid_normal_loss_policy"),settings)
	var policy_pin:Dictionary={}
	var start := _sample(evaluate, initial, time_s)
	if not start.ok: return _operator_failure(start,settings)
	if not _domain(initial, start): return _operator_failure(_failure("initial reverse rotor state is unsupported", "unsupported_reverse"),settings)
	var count := 1
	var coarse := {}
	var had_admissible := false
	var gate_identity := ""
	for attempt in 5:
		if count > settings.max_substeps: break
		var trial := _attempt(initial, time_s, dt, derivative, first, evaluate, certificate, start, count, settings,normal_loss_policy,policy_pin,mass_proof)
		if settings.operator_law!=LAW and not trial.ok: trial.law=settings.operator_law
		if trial.ok:
			had_admissible = true
			if not error_gate.is_valid(): return trial
			if not coarse.is_empty():
				var judged := _error_control(error_gate, coarse, trial, dt)
				if not judged.ok: return _operator_failure(judged,settings)
				if not gate_identity.is_empty() and gate_identity != judged.identity:
					return _operator_failure(_failure("error gate identity changed between complete-path pairs", "invalid_error_gate"),settings)
				gate_identity = judged.identity
				if judged.admitted:
					trial.integration_receipt.error_control = {
						method = "complete_first_order_split_n_2n_no_Richardson",
						coarse_substeps = coarse.integration_receipt.accepted_substeps, fine_substeps = count,
						identity = judged.identity, normalized_error = judged.normalized_error}
					return trial
			coarse = trial
		else:
			if trial.status != "refine": return trial
			# The next candidate must be compared to its actual n/2 predecessor,
			# never a nonadjacent or physically unadmitted abandoned trajectory.
			coarse = {}
		count *= 2
	if error_gate.is_valid() and had_admissible:
		return _operator_failure(_failure("complete split n/2n accuracy needs a finer path beyond the budget", "error_control_exhausted"),settings)
	return _operator_failure(_failure("whole-piece certificate or work accuracy exceeds the 16-piece budget", "admission_exhausted"),settings)



static func _operator_failure(result: Dictionary,options: Dictionary) -> Dictionary:
	var selected:Variant=options.get("operator_law",LAW)
	if not result.get("ok",false) and typeof(selected)==TYPE_STRING and selected==TWO_SIDED_LAW:
		result.law=TWO_SIDED_LAW
	return result


static func _error_control(gate: Callable, coarse: Dictionary, fine: Dictionary, dt: float) -> Dictionary:
	var a: PackedFloat64Array = coarse.state.duplicate()
	var b: PackedFloat64Array = fine.state.duplicate()
	var ar: Dictionary = coarse.integration_receipt.duplicate(true)
	var br: Dictionary = fine.integration_receipt.duplicate(true)
	var seal := var_to_bytes([a, b, ar, br])
	var judged: Variant = gate.call(a, b, ar, br, dt)
	if seal != var_to_bytes([a, b, ar, br]):
		return _failure("error gate mutated its read-only comparison inputs", "invalid_error_gate")
	if not judged is Dictionary or judged.size() != 4 or not judged.has_all(["ok", "admitted", "identity", "normalized_error"]) \
		or typeof(judged.ok) != TYPE_BOOL or typeof(judged.admitted) != TYPE_BOOL \
		or typeof(judged.identity) != TYPE_STRING or judged.identity.is_empty() or judged.identity.length() > 256 \
		or not _number(judged.normalized_error) or judged.normalized_error < 0.0 \
		or (judged.admitted and judged.normalized_error > 1.0):
		return _failure("malformed complete-path error gate result", "invalid_error_gate")
	if not judged.ok: return _failure("complete-path error gate refused its domain", "unsupported_error_gate")
	return judged


static func _attempt(initial: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		first: PackedFloat64Array, evaluate: Callable, certificate: Callable,
		start: Dictionary, count: int, settings: Dictionary,normal_loss_policy:Callable=Callable(),policy_pin:Dictionary={},mass_proof:RefCounted=null) -> Dictionary:
	if settings.operator_law==TWO_SIDED_LAW:
		return _operator_failure(_attempt_two_sided(initial,time_s,dt,derivative,first,evaluate,certificate,start,count,settings,normal_loss_policy,policy_pin,mass_proof),settings)
	var state := initial.duplicate()
	var sample := start
	var h := dt / count
	var times := PackedFloat64Array([time_s])
	var normal_samples: Array = [start.normal_load_n.duplicate()]
	var peaks: PackedFloat64Array = start.normal_load_n.duplicate()
	var peak_times := PackedFloat64Array()
	peak_times.resize(peaks.size())
	peak_times.fill(time_s)
	var loss_pieces:Array=[]
	var normal_loss := 0.0
	var external_work := 0.0
	var tangent_loss := 0.0
	var prescribed_work := 0.0
	var resolution_stats := _resolution_stats(settings)
	var largest_piece_residual := 0.0
	var impulse_absolute_sum := 0.0
	var certificate_ids := PackedStringArray()
	var initial_energy := _energy(initial, start)
	for piece in count:
		var at := time_s + piece * h
		var certified: Variant = certificate.call(state.duplicate(), at, h, sample.duplicate(true))
		if not certified is Dictionary or typeof(certified.get("ok")) != TYPE_BOOL \
			or typeof(certified.get("admitted")) != TYPE_BOOL or typeof(certified.get("identity")) != TYPE_STRING \
			or certified.identity.is_empty() or certified.identity.length() > 256:
			return _failure("malformed whole-piece certificate")
		if not certified.ok: return _failure("whole-piece certificate is unsupported", "unsupported_certificate")
		if not certified.admitted: return _failure("whole-piece refinement required", "refine")
		if not certificate_ids.has(certified.identity): certificate_ids.append(certified.identity)
		var loss_policy:=_loss_policy(normal_loss_policy,state,at,h,sample,policy_pin)
		if not loss_policy.ok:return loss_policy
		if loss_policy.eligible and not _loss_same_potential(sample,sample):return _failure("prekick changed support potential or identity","invalid_normal_loss_policy")
		# These are RK algebraic evaluations ONLY. Store quadrature power, never
		# damage maxima. A rejected attempt discards every sample and integral.
		var quadrature: Array = [PackedFloat64Array([sample.normal_dissipation_w, sample.external_power_w])]
		var zero_samples:={count=0}
		if loss_policy.eligible:
			if not _loss_zero_sample(sample,sample):return _failure("eligible initial normal sample is loaded or malformed","invalid_normal_loss_policy")
			zero_samples.count=1
		var tracker := {ok = true, reason = ""}
		var tracked := func(values: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
			if not _state(values):
				tracker.ok = false
				tracker.reason = "invalid algebraic stage state"
				return _zeros(initial.size())
			var point := _sample(evaluate, values, stage_t)
			if not point.ok or not _same_binding(start, point):
				tracker.ok = false
				tracker.reason = "stage snapshot refused or changed the fixed binding"
				return _zeros(initial.size())
			if loss_policy.eligible:
				if not _loss_zero_sample(sample,point):
					tracker.ok=false;tracker.reason="qualified RK normal sample is loaded or binding changed";return _zeros(initial.size())
				zero_samples.count+=1
			quadrature.append(PackedFloat64Array([point.normal_dissipation_w, point.external_power_w]))
			var raw: Variant = derivative.call(values.duplicate(), stage_t)
			if typeof(raw) != TYPE_PACKED_FLOAT64_ARRAY or raw.size() != initial.size() or not _finite(raw):
				tracker.ok = false
				tracker.reason = "malformed continuous derivative"
				return _zeros(initial.size())
			return raw
		var raw_k1: Variant = first if piece == 0 and not first.is_empty() else derivative.call(state.duplicate(), at)
		if typeof(raw_k1) != TYPE_PACKED_FLOAT64_ARRAY or raw_k1.size() != initial.size() or not _finite(raw_k1):
			return _failure("malformed initial continuous derivative")
		if loss_policy.eligible and piece==0 and not first.is_empty():
			var verified_k1:Variant=derivative.call(state.duplicate(),at)
			if typeof(verified_k1)!=TYPE_PACKED_FLOAT64_ARRAY or verified_k1!=raw_k1:return _failure("qualified owner k1 disagrees with supplied derivative","invalid_normal_loss_policy")
		var k1: PackedFloat64Array = raw_k1
		var candidate := RK.rk4_step_at(state, at, h, tracked, k1)
		if not tracker.ok or quadrature.size() != 4 or not _state(candidate):
			return _failure("normal/free RK interval failed: " + str(tracker.reason))
		var before_impulse := _sample(evaluate, candidate, at + h)
		if not before_impulse.ok or not _same_binding(start, before_impulse):
			return _failure("controlled contact sample refused or changed binding")
		var velocity_cm := M.add(candidate.slice(RB.VEL, RB.VEL + 3), M.cross(candidate.slice(RB.RATE, RB.RATE + 3), before_impulse.cg_body_m))
		var limits: PackedFloat64Array = before_impulse.limit_rates.duplicate()
		for i in limits.size():
			limits[i] *= h
			if before_impulse.limit_rates[i] > 0.0 and limits[i] == 0.0:
				return _failure("impulse time scaling underflow")
		var applied := Impulse.apply(before_impulse.rotor_stage, before_impulse.mass_kg, velocity_cm,
			before_impulse.jacobian, before_impulse.slip_bias, limits, before_impulse.groups, settings.qp_iterations,
			before_impulse.get("capture", {}), settings.maximum_assembly_resolution_j,mass_proof)
		if not applied.ok: return _failure("simultaneous contact impulse refused: " + str(applied.get("reason", "invalid")), "traction_rejected")
		if not _record_resolution(resolution_stats,applied): return _failure("assembly resolution diagnostic overflow")
		var next := candidate.duplicate()
		var datum_velocity := M.sub(applied.velocity_cm_body, M.cross(applied.omega, before_impulse.cg_body_m))
		# Empty rows preserve signed-zero state bytes, as the common adapter does.
		if not limits.is_empty():
			for axis in 3:
				next[RB.VEL + axis] = datum_velocity[axis]
				next[RB.RATE + axis] = applied.omega[axis]
			for i in applied.spin.size(): next[before_impulse.rotor_state_indices[i]] = applied.spin[i] / before_impulse.sigma_per_state[i]
		if not _state(next) or not _domain(next, before_impulse):
			return _failure("contact operator demands unsupported reverse motion", "unsupported_reverse")
		var accepted := _sample(evaluate, next, at + h)
		if not accepted.ok or not _same_binding(start, accepted): return _failure("accepted endpoint snapshot refused")
		var potential_change: float = accepted.potential_j - before_impulse.potential_j
		if absf(potential_change) > 1e-12 * maxf(1.0, maxf(absf(accepted.potential_j), absf(before_impulse.potential_j))):
			return _failure("velocity-only impulse changed recoverable potential")
		var piece_normal: float = h / 6.0 * (quadrature[0][0] + 2 * quadrature[1][0] + 2 * quadrature[2][0] + quadrature[3][0])
		if loss_policy.eligible:
			if not _loss_zero_sample(sample,before_impulse) or not _loss_same_potential(before_impulse,accepted):return _failure("qualified endpoint/potential binding changed","invalid_normal_loss_policy")
			piece_normal=sample.normal_support_potential_j-before_impulse.normal_support_potential_j
			if not is_finite(piece_normal) or piece_normal<0.0:return _failure("qualified support potential increased; no heat clamp","invalid_normal_loss_policy")
		var piece_work: float = h / 6.0 * (quadrature[0][1] + 2 * quadrature[1][1] + 2 * quadrature[2][1] + quadrature[3][1])
		var before_energy := _energy(state, sample)
		var after_energy := _energy(next, accepted)
		var residual: float = after_energy - before_energy + piece_normal + applied.dissipated_energy - piece_work - applied.total_prescribed_work
		var scale: float = maxf(absf(before_energy), maxf(absf(after_energy), absf(piece_work) + absf(applied.total_prescribed_work)))
		if not _finite(PackedFloat64Array([residual, before_energy, after_energy, piece_normal, piece_work])):
			return _failure("normal/contact work overflow")
		if absf(residual) > settings.energy_absolute_tolerance_j + settings.energy_relative_tolerance * scale:
			return _failure("normal/contact work accuracy requires refinement", "refine")
		if normal_loss_policy.is_valid():
			var entry:={method="unloaded_support_potential_difference_v1" if loss_policy.eligible else "RK4_normal_power_v1",normal_dissipation_j=piece_normal,energy_residual_j=residual}
			if loss_policy.eligible:
				entry.merge({start_support_potential_j=sample.normal_support_potential_j,end_support_potential_j=before_impulse.normal_support_potential_j,support_identity=sample.normal_support_identity,zero_force_rk_samples=zero_samples.count})
			loss_pieces.append(entry)
		largest_piece_residual = maxf(largest_piece_residual, absf(residual))
		normal_loss += piece_normal
		external_work += piece_work
		tangent_loss += applied.dissipated_energy
		prescribed_work += applied.total_prescribed_work
		for value: float in applied.impulse: impulse_absolute_sum += absf(value)
		state = next
		sample = accepted
		times.append(at + h)
		normal_samples.append(accepted.normal_load_n.duplicate())
		for i in peaks.size():
			if accepted.normal_load_n[i] > peaks[i]:
				peaks[i] = accepted.normal_load_n[i]
				peak_times[i] = at + h
	var final_energy := _energy(state, sample)
	if not _finite(PackedFloat64Array([initial_energy, final_energy, normal_loss, external_work, tangent_loss, prescribed_work, impulse_absolute_sum])):
		return _failure("accepted work accumulation overflow")
	var result := {ok = true, status = "accepted", state = state, events = [], integration_receipt = {
		format = RECEIPT_FORMAT, law = LAW, contact_operator_order = 1, accepted_substeps = count,
		contact_ids = start.contact_ids.duplicate(), normal_sample_times_s = times, normal_samples_n = normal_samples,
		normal_sampling_method = "accepted_substep_start_and_end_states_not_interval_maximum",
		sampled_peak_normal_n = peaks, sampled_peak_times_s = peak_times,
		quadrature_method = "RK4_algebraic_stage_weights_not_damage_samples", certificate_identities = certificate_ids,
		normal_dissipation_j = normal_loss, external_work_j = external_work, tangent_dissipation_j = tangent_loss,
		prescribed_contact_work_j = prescribed_work, absolute_impulse_sum = impulse_absolute_sum,
		initial_mechanical_energy_j = initial_energy, final_mechanical_energy_j = final_energy,
		energy_balance_residual_j = final_energy - initial_energy + normal_loss + tangent_loss - external_work - prescribed_work,
		maximum_piece_energy_residual_j = largest_piece_residual}}
	if normal_loss_policy.is_valid():
		result.integration_receipt.quadrature_method="RK4_external_work_piecewise_normal_loss_v1"
		result.integration_receipt.normal_loss_policy={format="openrc-normal-loss-policy-receipt v1",identity=policy_pin.identity,pieces=loss_pieces}
	if not resolution_stats.is_empty(): result.integration_receipt.assembly_resolution=resolution_stats
	return result


static func _attempt_two_sided(initial: PackedFloat64Array, time_s: float, dt: float, derivative: Callable,
		_first: PackedFloat64Array, evaluate: Callable, certificate: Callable,
		start: Dictionary, count: int, settings: Dictionary,normal_loss_policy:Callable=Callable(),policy_pin:Dictionary={},mass_proof:RefCounted=null) -> Dictionary:
	var state := initial.duplicate()
	var sample := start
	var h := dt / count
	var times := PackedFloat64Array([time_s])
	var normal_samples: Array = [start.normal_load_n.duplicate()]
	var peaks: PackedFloat64Array = start.normal_load_n.duplicate()
	var peak_times := PackedFloat64Array()
	peak_times.resize(peaks.size())
	peak_times.fill(time_s)
	var loss_pieces:Array=[]
	var normal_loss := 0.0
	var external_work := 0.0
	var tangent_loss := 0.0
	var prescribed_work := 0.0
	var pre_loss := 0.0
	var post_loss := 0.0
	var pre_work := 0.0
	var post_work := 0.0
	var resolution_stats := _resolution_stats(settings)
	var largest_piece_residual := 0.0
	var impulse_absolute_sum := 0.0
	var certificate_ids := PackedStringArray()
	var initial_energy := _energy(initial, start)
	for piece in count:
		var at := time_s + piece * h
		var before_energy := _energy(state, sample)
		var pre := _half_impulse(state, sample, at, 0.5 * h, evaluate, start, settings,mass_proof)
		if not pre.ok: return pre
		var kicked: PackedFloat64Array = pre.state
		var kicked_sample: Dictionary = pre.sample
		var certified: Variant = certificate.call(kicked.duplicate(), at, h, kicked_sample.duplicate(true))
		if not certified is Dictionary or typeof(certified.get("ok")) != TYPE_BOOL \
			or typeof(certified.get("admitted")) != TYPE_BOOL or typeof(certified.get("identity")) != TYPE_STRING \
			or certified.identity.is_empty() or certified.identity.length() > 256:
			return _failure("malformed whole-piece certificate")
		if not certified.ok: return _failure("whole-piece certificate is unsupported", "unsupported_certificate")
		if not certified.admitted: return _failure("whole-piece refinement required", "refine")
		if not certificate_ids.has(certified.identity): certificate_ids.append(certified.identity)
		var loss_policy:=_loss_policy(normal_loss_policy,kicked,at,h,kicked_sample,policy_pin)
		if not loss_policy.ok:return loss_policy
		if loss_policy.eligible and not _loss_same_potential(sample,kicked_sample):return _failure("prekick changed support potential or identity","invalid_normal_loss_policy")
		# The preimpulse changes body/spin velocities. Caller k1 is stale even on
		# piece0; recompute both force snapshot and derivative after the halfkick.
		var quadrature: Array = [PackedFloat64Array([kicked_sample.normal_dissipation_w, kicked_sample.external_power_w])]
		var zero_samples:={count=0}
		if loss_policy.eligible:
			if not _loss_zero_sample(kicked_sample,kicked_sample):return _failure("eligible initial normal sample is loaded or malformed","invalid_normal_loss_policy")
			zero_samples.count=1
		var tracker := {ok = true, reason = ""}
		var tracked := func(values: PackedFloat64Array, stage_t: float) -> PackedFloat64Array:
			if not _state(values):
				tracker.ok = false
				tracker.reason = "invalid algebraic stage state"
				return _zeros(initial.size())
			var point := _sample(evaluate, values, stage_t)
			if not point.ok or not _same_binding(start, point):
				tracker.ok = false
				tracker.reason = "stage snapshot refused or changed fixed binding"
				return _zeros(initial.size())
			if loss_policy.eligible:
				if not _loss_zero_sample(kicked_sample,point):
					tracker.ok=false;tracker.reason="qualified RK normal sample is loaded or binding changed";return _zeros(initial.size())
				zero_samples.count+=1
			quadrature.append(PackedFloat64Array([point.normal_dissipation_w, point.external_power_w]))
			var raw: Variant = derivative.call(values.duplicate(), stage_t)
			if typeof(raw) != TYPE_PACKED_FLOAT64_ARRAY or raw.size() != initial.size() or not _finite(raw):
				tracker.ok = false
				tracker.reason = "malformed continuous derivative"
				return _zeros(initial.size())
			return raw
		var first: Variant = derivative.call(kicked.duplicate(), at)
		if typeof(first) != TYPE_PACKED_FLOAT64_ARRAY or first.size() != initial.size() or not _finite(first):
			return _failure("malformed recomputed preimpulse k1")
		var candidate := RK.rk4_step_at(kicked, at, h, tracked, first)
		if not tracker.ok or quadrature.size() != 4 or not _state(candidate):
			return _failure("normal/free RK interval failed: " + str(tracker.reason))
		var after_flow := _sample(evaluate, candidate, at + h)
		if not after_flow.ok or not _same_binding(start, after_flow): return _failure("controlled endpoint snapshot refused")
		var post := _half_impulse(candidate, after_flow, at + h, 0.5 * h, evaluate, start, settings,mass_proof)
		if not post.ok: return post
		var next: PackedFloat64Array = post.state
		var accepted: Dictionary = post.sample
		var piece_normal: float = h / 6.0 * (quadrature[0][0] + 2 * quadrature[1][0] + 2 * quadrature[2][0] + quadrature[3][0])
		if loss_policy.eligible:
			if not _loss_zero_sample(kicked_sample,after_flow) or not _loss_same_potential(after_flow,accepted):return _failure("qualified endpoint/potential binding changed","invalid_normal_loss_policy")
			piece_normal=kicked_sample.normal_support_potential_j-after_flow.normal_support_potential_j
			if not is_finite(piece_normal) or piece_normal<0.0:return _failure("qualified support potential increased; no heat clamp","invalid_normal_loss_policy")
		var piece_work: float = h / 6.0 * (quadrature[0][1] + 2 * quadrature[1][1] + 2 * quadrature[2][1] + quadrature[3][1])
		var after_energy := _energy(next, accepted)
		var loss: float = pre.loss + post.loss
		var work: float = pre.work + post.work
		var residual: float = after_energy - before_energy + piece_normal + loss - piece_work - work
		var scale: float = maxf(absf(before_energy), maxf(absf(after_energy), absf(piece_work) + absf(work)))
		if not _finite(PackedFloat64Array([residual, before_energy, after_energy, piece_normal, piece_work])):
			return _failure("normal/contact work overflow")
		if absf(residual) > settings.energy_absolute_tolerance_j + settings.energy_relative_tolerance * scale:
			return _failure("normal/contact work accuracy requires refinement", "refine")
		if normal_loss_policy.is_valid():
			var entry:={method="unloaded_support_potential_difference_v1" if loss_policy.eligible else "RK4_normal_power_v1",normal_dissipation_j=piece_normal,energy_residual_j=residual}
			if loss_policy.eligible:
				entry.merge({start_support_potential_j=kicked_sample.normal_support_potential_j,end_support_potential_j=after_flow.normal_support_potential_j,support_identity=kicked_sample.normal_support_identity,zero_force_rk_samples=zero_samples.count})
			loss_pieces.append(entry)
		largest_piece_residual = maxf(largest_piece_residual, absf(residual))
		normal_loss += piece_normal
		external_work += piece_work
		tangent_loss += loss
		prescribed_work += work
		pre_loss+=pre.loss
		post_loss+=post.loss
		pre_work+=pre.work
		post_work+=post.work
		if not _record_resolution(resolution_stats,pre.applied) or not _record_resolution(resolution_stats,post.applied):
			return _failure("assembly resolution diagnostic overflow")
		impulse_absolute_sum += pre.impulse_absolute_sum + post.impulse_absolute_sum
		state = next
		sample = accepted
		times.append(at + h)
		normal_samples.append(accepted.normal_load_n.duplicate())
		for i in peaks.size():
			if accepted.normal_load_n[i] > peaks[i]:
				peaks[i] = accepted.normal_load_n[i]
				peak_times[i] = at + h
	var final_energy := _energy(state, sample)
	if not _finite(PackedFloat64Array([initial_energy, final_energy, normal_loss, external_work, tangent_loss, prescribed_work, impulse_absolute_sum])):
		return _failure("accepted work accumulation overflow")
	var result := {ok = true, status = "accepted", state = state, events = [], integration_receipt = {
		format = RECEIPT_FORMAT, law = TWO_SIDED_LAW, contact_operator_order = 1, accepted_substeps = count,
		contact_ids = start.contact_ids.duplicate(), normal_sample_times_s = times, normal_samples_n = normal_samples,
		normal_sampling_method = "accepted_substep_start_and_end_states_not_interval_maximum",
		sampled_peak_normal_n = peaks, sampled_peak_times_s = peak_times,
		quadrature_method = "RK4_algebraic_stage_weights_not_damage_samples", certificate_identities = certificate_ids,
		normal_dissipation_j = normal_loss, external_work_j = external_work, tangent_dissipation_j = tangent_loss,
		prescribed_contact_work_j = prescribed_work, absolute_impulse_sum = impulse_absolute_sum,
		initial_mechanical_energy_j = initial_energy, final_mechanical_energy_j = final_energy,
		energy_balance_residual_j = final_energy - initial_energy + normal_loss + tangent_loss - external_work - prescribed_work,
		maximum_piece_energy_residual_j = largest_piece_residual,
		pre_contact_dissipation_j=pre_loss,post_contact_dissipation_j=post_loss,
		pre_prescribed_contact_work_j=pre_work,post_prescribed_contact_work_j=post_work,
		split_method="two_sided_half_impulses_recomputed_k1_order1"}}
	if normal_loss_policy.is_valid():
		result.integration_receipt.quadrature_method="RK4_external_work_piecewise_normal_loss_v1"
		result.integration_receipt.normal_loss_policy={format="openrc-normal-loss-policy-receipt v1",identity=policy_pin.identity,pieces=loss_pieces}
	if not resolution_stats.is_empty(): result.integration_receipt.assembly_resolution=resolution_stats
	return result


static func _half_impulse(state: PackedFloat64Array, sample: Dictionary, at: float, half_h: float,
		evaluate: Callable, start: Dictionary, settings: Dictionary,mass_proof:RefCounted=null) -> Dictionary:
	var velocity_cm := M.add(state.slice(RB.VEL, RB.VEL + 3), M.cross(state.slice(RB.RATE, RB.RATE + 3), sample.cg_body_m))
	var limits: PackedFloat64Array = sample.limit_rates.duplicate()
	for i in limits.size():
		limits[i] *= half_h
		if sample.limit_rates[i] > 0.0 and limits[i] == 0.0: return _failure("half impulse scaling underflow")
	var applied := Impulse.apply(sample.rotor_stage, sample.mass_kg, velocity_cm, sample.jacobian, sample.slip_bias,
		limits, sample.groups, settings.qp_iterations, sample.get("capture",{}), settings.maximum_assembly_resolution_j,mass_proof)
	if not applied.ok: return _failure("half contact impulse refused: " + str(applied.get("reason", "invalid")), "traction_rejected")
	var next := state.duplicate()
	if not limits.is_empty():
		var datum_velocity := M.sub(applied.velocity_cm_body, M.cross(applied.omega, sample.cg_body_m))
		for axis in 3:
			next[RB.VEL + axis] = datum_velocity[axis]
			next[RB.RATE + axis] = applied.omega[axis]
		for i in applied.spin.size(): next[sample.rotor_state_indices[i]] = applied.spin[i] / sample.sigma_per_state[i]
	if not _state(next) or not _domain(next, sample): return _failure("unsupported reverse motion after halfkick", "unsupported_reverse")
	var after := _sample(evaluate, next, at)
	if not after.ok or not _same_binding(start, after): return _failure("post-halfkick snapshot refused")
	if absf(after.potential_j - sample.potential_j) > 1e-12 * maxf(1.0, maxf(absf(after.potential_j), absf(sample.potential_j))):
		return _failure("velocity halfkick changed recoverable potential")
	var magnitude := 0.0
	for impulse: float in applied.impulse: magnitude += absf(impulse)
	return {ok = true, state = next, sample = after, loss = applied.dissipated_energy,
		work = applied.total_prescribed_work, impulse_absolute_sum = magnitude, applied=applied}


static func _sample(evaluate: Callable, state: PackedFloat64Array, at: float) -> Dictionary:
	var raw: Variant = evaluate.call(state.duplicate(), at)
	if not raw is Dictionary or typeof(raw.get("ok")) != TYPE_BOOL or not raw.ok or raw.get("format", "") != SAMPLE_FORMAT:
		return _failure("malformed stage sample")
	var s: Dictionary = raw
	if typeof(s.get("fixed_hubs")) != TYPE_BOOL or typeof(s.get("static_ground")) != TYPE_BOOL \
		or not s.fixed_hubs or not s.static_ground or s.get("source_policy") != "none" \
		or (s.has("source_events") and (not s.source_events is Array or not s.source_events.is_empty())):
		return _failure("source events, moving hubs or nonstatic ground are unsupported", "unsupported_domain")
	if not _number(s.get("mass_kg")) or s.mass_kg <= 0 or not _vector(s.get("cg_body_m")) \
		or typeof(s.get("rotor_stage")) != TYPE_DICTIONARY \
		or typeof(s.get("rotor_state_indices")) != TYPE_PACKED_INT64_ARRAY \
		or typeof(s.get("sigma_per_state")) != TYPE_PACKED_FLOAT64_ARRAY \
		or typeof(s.get("nonnegative_rotors")) != TYPE_PACKED_INT64_ARRAY:
		return _failure("malformed mechanical stage layout")
	var valid := Impulse._stage(s.rotor_stage)
	if not valid.ok: return _failure("invalid or held common rotor stage", "unsupported_rotor")
	var count: int = s.rotor_stage.axial.size()
	if s.rotor_state_indices.size() != count or s.sigma_per_state.size() != count or not _finite(s.sigma_per_state):
		return _failure("rotor unit conversion dimensions disagree")
	for value: float in s.rotor_stage.carrier_rates:
		if value != 0.0: return _failure("prescribed carrier motion requires separate qualification", "unsupported_domain")
	var seen := {}
	for i in count:
		var index: int = s.rotor_state_indices[i]
		if index < RB.SIZE or index >= state.size() or seen.has(index) or s.sigma_per_state[i] <= 0 \
			or absf(s.rotor_stage.velocity[3 + i] - state[index] * s.sigma_per_state[i]) > 1e-12 * maxf(1.0, absf(s.rotor_stage.velocity[3 + i])):
			return _failure("rotor stage is stale or conversion is invalid")
		seen[index] = true
	for i in 3:
		if s.rotor_stage.velocity[i] != state[RB.RATE + i]: return _failure("body rate differs from common rotor stage")
	seen = {}
	for index: int in s.nonnegative_rotors:
		if index < 0 or index >= count or seen.has(index): return _failure("invalid reverse-domain declaration")
		seen[index] = true
	for key: String in ["jacobian", "slip_bias", "limit_rates", "normal_load_n"]:
		if typeof(s.get(key)) != TYPE_PACKED_FLOAT64_ARRAY or not _finite(s[key]): return _failure("nonfinite row/contact data")
	var rows: int = s.slip_bias.size()
	if rows > Impulse.MAX_ROWS or s.jacobian.size() != rows * (6 + count) or s.limit_rates.size() != rows \
		or typeof(s.get("groups")) != TYPE_ARRAY or s.groups.size() > rows or (rows == 0 and not s.groups.is_empty()) \
		or typeof(s.get("contact_ids")) != TYPE_PACKED_STRING_ARRAY or s.contact_ids.size() > MAX_CONTACTS \
		or s.normal_load_n.size() != s.contact_ids.size(): return _failure("invalid row/contact dimensions")
	for value: float in s.limit_rates:
		if value < 0: return _failure("negative impulse-rate limit")
	for value: float in s.slip_bias:
		if value != 0.0: return _failure("prescribed support/carrier slip needs separate qualification", "unsupported_domain")
	if s.has("capture"):
		if typeof(s.capture) != TYPE_DICTIONARY: return _failure("capture must be an explicit mapping", "invalid_capture")
		if not s.capture.is_empty():
			var mapping := Impulse._capture_mapping(s.capture, count, s.jacobian, s.slip_bias, s.groups)
			if not mapping.ok: return _failure(str(mapping.reason), "invalid_capture")
			if not s.nonnegative_rotors.has(s.capture.rotor_index):
				return _failure("capture rotor must match a declared nonnegative shaft domain", "invalid_capture")
	seen = {}
	for id: String in s.contact_ids:
		if id.is_empty() or id.length() > 128 or seen.has(id): return _failure("invalid contact identity")
		seen[id] = true
	for load: float in s.normal_load_n:
		if load < 0: return _failure("negative normal support load")
	for key: String in ["potential_j", "normal_dissipation_w", "external_power_w"]:
		if not _number(s.get(key)): return _failure("invalid normal/free work sample")
	if s.normal_dissipation_w < 0: return _failure("negative normal dissipation")
	return s


static func _resolution_stats(settings: Dictionary) -> Dictionary:
	if settings.maximum_assembly_resolution_j<0.0:return {}
	return {maximum_assembly_resolution_j=settings.maximum_assembly_resolution_j,ceiling_scope="per_impulse_qp_not_tick",
		accepted_at_resolution=0,accepted_slip_roundoff=0,accepted_work_roundoff=0,maximum_derived_gamma_j=0.0,derived_gamma_sum_j=0.0,
		objective_gap_upper_sum_j=0.0,slip_work_equivalent_sum_j=0.0,work_consistency_sum_j=0.0,combined_contact_uncertainty_sum_j=0.0}


static func _record_resolution(stats:Dictionary,applied:Dictionary)->bool:
	if stats.is_empty():return true
	var gamma:=0.0
	var gap:=0.0
	var slip:=0.0
	var work:=0.0
	if applied.qp.has("assembly_resolution"):
		var proof:Dictionary=applied.qp.assembly_resolution
		if not proof.get("ok",false) or not _number(proof.get("assembly_objective_resolution_j")) \
			or not _number(proof.get("true_objective_gap_upper_j")) or proof.true_objective_gap_upper_j<0.0 \
			or proof.true_objective_gap_upper_j>proof.assembly_objective_resolution_j:return false
		gamma=proof.assembly_objective_resolution_j
		gap=proof.true_objective_gap_upper_j
		stats.accepted_at_resolution+=1
	if applied.has("slip_roundoff"):
		var proof:Dictionary=applied.slip_roundoff
		if not proof.get("ok",false) or not _number(proof.get("work_equivalent_bound_j")) \
			or proof.work_equivalent_bound_j<0.0 \
			or proof.certified_impulse_sha256!=Impulse.AR.impulse_digest(applied.impulse):return false
		slip=proof.work_equivalent_bound_j
		stats.accepted_slip_roundoff+=1
	if applied.has("work_roundoff"):
		var proof:Dictionary=applied.work_roundoff
		if not proof.get("ok",false) or not _number(proof.get("work_equivalent_bound_j")) \
			or proof.work_equivalent_bound_j<0.0 or not _number(proof.get("actual_relative_work_upper_j")) \
			or proof.actual_relative_work_upper_j>0.0 \
			or proof.certified_impulse_sha256!=Impulse.AR.impulse_digest(applied.impulse):return false
		work=proof.work_equivalent_bound_j
		stats.accepted_work_roundoff+=1
	var combined:=Impulse.AR._add(Impulse.AR._add(gamma,slip),work)
	if not is_finite(combined) or combined>stats.maximum_assembly_resolution_j:return false
	stats.maximum_derived_gamma_j=maxf(stats.maximum_derived_gamma_j,gamma)
	stats.derived_gamma_sum_j=Impulse.AR._add(stats.derived_gamma_sum_j,gamma)
	stats.objective_gap_upper_sum_j=Impulse.AR._add(stats.objective_gap_upper_sum_j,gap)
	stats.slip_work_equivalent_sum_j=Impulse.AR._add(stats.slip_work_equivalent_sum_j,slip)
	stats.work_consistency_sum_j=Impulse.AR._add(stats.work_consistency_sum_j,work)
	stats.combined_contact_uncertainty_sum_j=Impulse.AR._add(stats.combined_contact_uncertainty_sum_j,combined)
	return _number(stats.derived_gamma_sum_j) and _number(stats.objective_gap_upper_sum_j) \
		and _number(stats.slip_work_equivalent_sum_j) and _number(stats.work_consistency_sum_j) and _number(stats.combined_contact_uncertainty_sum_j)


static func _same_binding(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["mass_kg", "cg_body_m", "rotor_state_indices", "sigma_per_state", "nonnegative_rotors", "contact_ids"]:
		if a[key] != b[key]: return false
	for key: String in ["carrier", "axial", "transverse", "axes", "matrix", "system_identity"]:
		if a.rotor_stage[key] != b.rotor_stage[key]: return false
	var ac: Dictionary = a.get("capture", {})
	var bc: Dictionary = b.get("capture", {})
	if ac.is_empty() != bc.is_empty(): return false
	# Capture belongs to one physical rotor. Its scalar row index is local to
	# the current contact set and is validated afresh, not a permanent binding.
	if not ac.is_empty() and ac.rotor_index != bc.rotor_index: return false
	return true


static func _energy(state: PackedFloat64Array, sample: Dictionary) -> float:
	var velocity := M.add(state.slice(RB.VEL, RB.VEL + 3), M.cross(state.slice(RB.RATE, RB.RATE + 3), sample.cg_body_m))
	return .5 * sample.mass_kg * M.dot(velocity, velocity) + RC._stage_energy(sample.rotor_stage, sample.rotor_stage.velocity) + sample.potential_j


static func _domain(state: PackedFloat64Array, sample: Dictionary) -> bool:
	for index: int in sample.nonnegative_rotors:
		if state[sample.rotor_state_indices[index]] < 0.0: return false
	return true


static func _settings(options: Dictionary) -> Dictionary:
	var out := {ok = true, max_substeps = MAX_SUBSTEPS, qp_iterations = 1024,
		energy_absolute_tolerance_j = 1e-7, energy_relative_tolerance = 1e-7,
		operator_law=LAW,maximum_assembly_resolution_j=-1.0}
	for key: Variant in options:
		if key not in ["max_substeps", "qp_iterations", "energy_absolute_tolerance_j", "energy_relative_tolerance", "operator_law", "maximum_assembly_resolution_j"]:
			return _failure("unsupported step option")
		out[key] = options[key]
	if typeof(out.max_substeps) != TYPE_INT or out.max_substeps not in [1, 2, 4, 8, 16] \
		or typeof(out.qp_iterations) != TYPE_INT or out.qp_iterations < 1 or out.qp_iterations > 1024:
		return _failure("invalid refinement/traction budget")
	if typeof(out.operator_law)!=TYPE_STRING or out.operator_law not in [LAW,TWO_SIDED_LAW] \
		or not _number(out.maximum_assembly_resolution_j) \
		or (out.maximum_assembly_resolution_j<0.0 and out.maximum_assembly_resolution_j!=-1.0):
		return _failure("invalid operator or assembly resolution ceiling")
	for key: String in ["energy_absolute_tolerance_j", "energy_relative_tolerance"]:
		if not _number(out[key]) or out[key] < 0 or out[key] > 1e-2: return _failure("invalid work accuracy tolerance")
	return out


static func _state(s: PackedFloat64Array) -> bool:
	if s.size() < RB.SIZE or s.size() > MAX_STATE_SIZE or not _finite(s): return false
	var norm := 0.0
	for i in 4: norm += s[RB.ATT + i] * s[RB.ATT + i]
	return is_finite(norm) and norm > 1e-24


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value))


static func _vector(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_FLOAT64_ARRAY and value.size() == 3 and _finite(value)


static func _finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value): return false
	return true


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	return out


static func _failure(reason: String, status := "invalid") -> Dictionary:
	return {ok = false, status = status, reason = reason, law = LAW}


## Trusted owner authority, like derivative/certificate. Receipt data cannot
## activate this policy. Captured source/config binding is the OWNER's duty.
static func _loss_policy(policy:Callable,state:PackedFloat64Array,at:float,h:float,sample:Dictionary,pin:Dictionary)->Dictionary:
	if policy.is_null():return {ok=true,eligible=false,identity=""}
	if not policy.is_valid() or policy.get_argument_count()!=4:return _failure("normal loss policy requires exactly four arguments","invalid_normal_loss_policy")
	var a:=state.duplicate()
	var b:=sample.duplicate(true)
	var before:=var_to_bytes([a,b])
	var raw:Variant=policy.call(a,at,h,b)
	if before!=var_to_bytes([a,b]):return _failure("normal loss policy mutated read-only inputs","invalid_normal_loss_policy")
	if not raw is Dictionary or raw.size()!=3 or not raw.has_all(["ok","eligible","identity"]) \
		or typeof(raw.ok)!=TYPE_BOOL or typeof(raw.eligible)!=TYPE_BOOL or typeof(raw.identity)!=TYPE_STRING \
		or raw.identity.is_empty() or raw.identity.length()>256:
		return _failure("malformed normal loss policy result","invalid_normal_loss_policy")
	if not raw.ok:return _failure("normal loss owner refused its binding/domain","unsupported_normal_loss_policy")
	if pin.has("identity") and pin.identity!=raw.identity:return _failure("normal loss policy identity changed","invalid_normal_loss_policy")
	pin.identity=raw.identity
	return raw.duplicate(true)


static func _loss_support(sample:Dictionary)->bool:
	return _number(sample.get("normal_support_potential_j")) and sample.normal_support_potential_j>=0.0 \
		and typeof(sample.get("normal_support_identity"))==TYPE_STRING and not sample.normal_support_identity.is_empty() and sample.normal_support_identity.length()<=256


static func _loss_same_potential(a:Dictionary,b:Dictionary)->bool:
	return _loss_support(a) and _loss_support(b) and a.normal_support_identity==b.normal_support_identity \
		and a.normal_support_potential_j==b.normal_support_potential_j


static func _loss_zero_sample(a:Dictionary,b:Dictionary)->bool:
	if not _loss_support(a) or not _loss_support(b) or a.normal_support_identity!=b.normal_support_identity:return false
	for load:float in b.normal_load_n:
		if load!=0.0:return false
	return true
