## Installed hardware; synthetic normal/material experiment, no fleet calibration.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/tests/test_aircraft_ground_stage.gd"
const Traction := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_traction.gd")
const Step := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_step.gd")
const Admission := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/normal_contact_admission.gd")
const Rotor := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/rotor_coupling.gd")
const Accuracy := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_accuracy.gd")
const GRAVITY := 9.80665
const X_MAX := 0.18
const GAP_SPEED_MAX := 3.0
const CM_NORMAL_SPEED_MAX := 3.0
const OMEGA_MAX := 5.0
const RIM_MAX := 15.0
const KAPPA_MIN := 0.5
var traction: Dictionary
var lift_start := 100.0
var lift_duration := 1.5
var lift_ratio := 0.0
var brake_start := 100.0
var reject_endpoint := false
var quality: Dictionary
var selected_law := Step.TWO_SIDED_LAW
const WORK_ABSOLUTE_J := 1e-6
const TICK_ASSEMBLY_BUDGET_J := WORK_ABSOLUTE_J*1e-5

func _options() -> Dictionary:
	return {operator_law=selected_law,maximum_assembly_resolution_j=TICK_ASSEMBLY_BUDGET_J/32.0}

func _prepare_composition() -> void:
	# The fixture's authored geometry is explicitly synthetic. Balance the three
	# fixed hub x arms for a neutral, symmetric initial support distribution.
	var authored := authored_profile.duplicate(true)
	var x := [-0.3, -0.3, 0.6]
	for i in 3: authored.supports[i].hub_le.value[0] = model.cg_le[0] - x[i]
	var resolved := Profile.resolve(authored, model)
	check("symmetric composition fixture resolves without launch admission", resolved.ok and not resolved.launch_available)
	if not resolved.ok: return
	profile = resolved.profile
	model = resolved.model
	prepared = Stage.prepare(profile, model)
	motion.clear()
	for support: Dictionary in prepared.normal.supports:
		motion.append({contact_id = support.contact_id, hub_body = support.hub_body.duplicate(), axle_body = support.axle_body.duplicate(),
			carrier_rate_body = M.v3(0.0, 0.0, 0.0), carrier_accel_body = M.v3(0.0, 0.0, 0.0)})
	var material := {format = Traction.MATERIAL_FORMAT, law = Traction.MATERIAL_LAW, material_id = "dry_pavement",
		longitudinal_friction = _q(0.7, "1"), lateral_friction = _q(0.5, "1"), rolling_resistance = _q(0.02, "1")}
	traction = Traction.prepare(prepared, model, [material])
	check("real three-wheel traction binds selected hardware/material", prepared.ok and traction.ok, str(traction))
	check("two installed main brakes remain available with unbraked tail", traction.hardware[0].brake_torque_nm > 0.0 \
		and traction.hardware[1].brake_torque_nm > 0.0 and traction.hardware[2].brake_torque_nm == 0.0)

func _initial(down: float, forward: float, vertical: float, rims: float) -> PackedFloat64Array:
	var state := RB.make_state(M.v3(0.0, 0.0, down), M.v3(forward, 0.0, vertical), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	state.append_array(PackedFloat64Array([1400.0, rims, rims, rims]))
	return state

func _lift(at: float) -> float:
	return live.mass_kg * GRAVITY * lift_ratio * clampf((at - lift_start) / lift_duration, 0.0, 1.0)

func _snapshot(state: PackedFloat64Array, at: float) -> Dictionary:
	var body := state.slice(0, RB.SIZE)
	var q := M.q_normalized(body.slice(RB.ATT, RB.ATT + 4))
	var velocity_cm := M.add(body.slice(RB.VEL, RB.VEL + 3), M.cross(body.slice(RB.RATE), live.cg_body_m))
	if absf(M.q_rotate(q,velocity_cm)[2])>CM_NORMAL_SPEED_MAX or M.norm(body.slice(RB.RATE))>OMEGA_MAX \
		or absf(state[13]*TAU/60.0)>260.0:
		return {ok=false,reason="algebraic stage left declared CM-speed/rate envelope"}
	for i in 3:
		if absf(state[14+i])>RIM_MAX:return {ok=false,reason="algebraic rim envelope"}
		var axis:=M.q_rotate(q,prepared.normal.supports[i].axle_body)
		if 1.0-axis[2]*axis[2]<KAPPA_MIN*KAPPA_MIN:return {ok=false,reason="algebraic kappa envelope"}
	var force := M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, -_lift(at)))
	var external := force.duplicate()
	external.append_array(M.cross(live.cg_body_m, force))
	var physical := Stage.evaluate(prepared, body, state.slice(14, 17), state[13], motion, provider, at, live, GRAVITY,
		external, M.v3(0.0, 0.0, 0.0), 0.0)
	if not physical.ok: return {ok = false, reason = "stage " + str(physical)}
	for contact:Dictionary in physical.ground.contacts:
		if contact.geometry_evaluated and (-contact.gap_m>X_MAX or absf(contact.gap_rate_mps)>GAP_SPEED_MAX):
			return {ok=false,reason="algebraic stage compression/gap-speed envelope"}
	var brake := 0.7 if at >= brake_start else 0.0
	var rows := Traction.evaluate(traction, body, live.cg_body_m, physical.ground, PackedFloat64Array([brake, brake, 0.0]))
	if not rows.ok: return {ok = false, reason = "traction " + str(rows)}
	var normal_loads := PackedFloat64Array()
	var ids := PackedStringArray()
	for contact: Dictionary in physical.ground.contacts:
		normal_loads.append(contact.normal_load_n)
		ids.append(contact.contact_id)
	var derivative: PackedFloat64Array = physical.body_derivative.duplicate()
	derivative.append(physical.shaft_rpm_rate)
	derivative.append_array(physical.wheel_rim_rates)
	var cm_position := M.add(body.slice(0, 3), M.q_rotate(q, live.cg_body_m))
	return {ok = true, format = Step.SAMPLE_FORMAT, fixed_hubs = true, static_ground = true, source_policy = "none",
		mass_kg = live.mass_kg, cg_body_m = live.cg_body_m, rotor_stage = physical.rotor.stage,
		rotor_state_indices = PackedInt64Array([13, 14, 15, 16]),
		sigma_per_state = PackedFloat64Array([TAU / 60.0, 1.0 / prepared.radii_m[0], 1.0 / prepared.radii_m[1], 1.0 / prepared.radii_m[2]]),
		nonnegative_rotors = PackedInt64Array([0]), jacobian = rows.jacobian, slip_bias = rows.bias,
		limit_rates = rows.limit_rates, groups = rows.groups, contact_ids = ids, normal_load_n = normal_loads,
		potential_j = physical.ground.potential_j - live.mass_kg * GRAVITY * cm_position[2],
		normal_dissipation_w = physical.ground.dissipation_w, external_power_w = M.dot(force, velocity_cm),
		physical = physical, rows = rows, derivative = derivative, loads = physical.loads}

func _derivative(state: PackedFloat64Array, at: float) -> PackedFloat64Array:
	var point := _snapshot(state, at)
	return point.derivative if point.ok else PackedFloat64Array([NAN])

## Conditional fixed-live-mass plane envelope, protected at every RK sample by
## _snapshot/_certificate and paired-path error checking. This is numerical
## qualification of this bounded experiment, not a universal continuous proof.
func _certificate(state: PackedFloat64Array, _at: float, h: float, point: Dictionary) -> Dictionary:
	var identity := "composition-plane-X.18-V3-Omega5-kappa.5-v1"
	var q := M.q_normalized(state.slice(RB.ATT, RB.ATT + 4))
	var velocity_cm := M.add(state.slice(RB.VEL, RB.VEL + 3), M.cross(state.slice(RB.RATE), live.cg_body_m))
	var vertical_speed: float = absf(M.q_rotate(q, velocity_cm)[2])
	var omega := M.norm(state.slice(RB.RATE))
	if vertical_speed > CM_NORMAL_SPEED_MAX or omega > OMEGA_MAX or absf(state[13] * TAU / 60.0) > 260.0:
		return {ok = false, admitted = false, identity = identity}
	var contacts: Array = []
	for i in 3:
		if absf(state[14 + i]) > RIM_MAX: return {ok = false, admitted = false, identity = identity}
		var support: Dictionary = prepared.normal.supports[i]
		var hub := M.add(state.slice(0, 3), M.q_rotate(q, support.hub_body))
		var arm := M.norm(M.sub(support.hub_body, live.cg_body_m))
		var swept := Admission.swept_clearance(-hub[2] - support.radius_m, CM_NORMAL_SPEED_MAX + OMEGA_MAX * arm, h)
		if swept.ok and swept.proved_separated: continue
		var axis := M.q_rotate(q, support.axle_body)
		var kappa := sqrt(maxf(0.0, 1.0 - axis[2] * axis[2]))
		if kappa - h * OMEGA_MAX < KAPPA_MIN: return {ok = true, admitted = false, identity = identity}
		var record: Dictionary = point.physical.ground.contacts[i]
		if record.geometry_evaluated:
			if -record.gap_m + h * GAP_SPEED_MAX > X_MAX or absf(record.gap_rate_mps) > GAP_SPEED_MAX:
				return {ok = true, admitted = false, identity = identity}
		var bound := Normal.bounds(support.normal, X_MAX, GAP_SPEED_MAX)
		var elastic := Normal.evaluate(support.normal, X_MAX, 0.0)
		contacts.append({hub_body = support.hub_body, radius_m = support.radius_m,
			kbar = bound.position_derivative_bound_npm, cbar = bound.rate_derivative_bound_nsm,
			normal_load_bound_n = elastic.elastic_force_n + bound.rate_derivative_bound_nsm * GAP_SPEED_MAX, kappa_min = KAPPA_MIN})
	if contacts.is_empty(): return {ok = true, admitted = true, identity = identity}
	var admission := Admission.plane_envelope(live.mass_kg, live.cg_body_m, point.rotor_stage, contacts, h, 1)
	return {ok = admission.ok or admission.get("status") == "budget_exceeded", admitted = admission.ok, identity = identity}

func _error_gate(coarse: PackedFloat64Array, fine: PackedFloat64Array, cr: Dictionary, fr: Dictionary, dt: float) -> Dictionary:
	var judged:=Accuracy.diagnose(quality,coarse,fine,cr,fr,dt)
	if not judged.admitted and fr.accepted_substeps==16:
		print("COMPOSITION_GATE_REFUSAL ",JSON.stringify(judged,"",true,true))
	return {ok=judged.ok,admitted=judged.admitted,identity=judged.identity,normalized_error=judged.normalized_error}

func _nq(value:float,unit:String)->Dictionary:
	return {value=value,unit=unit,kind="estimated",source="Explicit three-wheel numerical experiment quality, not physical calibration"}

func _tol(absolute:float,relative:float,floor_value:float,unit:String,sources:Array=[])->Dictionary:
	var value:={absolute=_nq(absolute,unit),relative=_nq(relative,"1"),floor=_nq(floor_value,unit)}
	if not sources.is_empty():value.scale_sources=sources.duplicate()
	return value

func _prepare_quality()->void:
	var ids:=PackedStringArray()
	var blocks:Array=[{id="shaft",indices=PackedInt64Array([13]),unit="rpm"}]
	var tolerances:={shaft=_tol(.01,0.0,1e-12,"rad/s")}
	for i in 3:
		var id:String=prepared.normal.supports[i].contact_id
		ids.append(id)
		blocks.append({id="rim:"+id,indices=PackedInt64Array([14+i]),unit="m/s"})
		# Retained same-input Sym16 vs128 evidence is below0.11%; original
		# absolute-only1mm oracle remains retained as a stricter failed oracle.
		tolerances["rim:"+id]=_tol(.001,.005,.01,"m/s")
	var layout:={format=Accuracy.LAYOUT_FORMAT,identity=prepared.identity,state_layout_id="composition-three-wheels-shaft-frozen-P51-v2",
		state_size=17,continuous_start=13,cg_body_m=live.cg_body_m.duplicate(),blocks=blocks,
		contact_ids=ids,step_law=selected_law,operator_order=1}
	var raw:={format=Accuracy.FORMAT,quality_name="three-wheel-symmetric-0.5percent-plus1mm-rim-v1",
		source="Bounded same-input numerical experiment; quality choices qualified by retained64/128 reference, no fleet validation",
		body={position=_tol(1e-6,0.0,.001,"m"),velocity_cm=_tol(.001,0.0,.01,"m/s"),
			attitude=_tol(1e-5,0.0,1.0,"rad"),angular_rate=_tol(.0002,0.0,.01,"rad/s")},
		continuous=tolerances,normal_peak=_tol(.01,.02,.1,"N"),time_tolerance=_nq(1e-9,"s"),
		work={external_work_j=_tol(WORK_ABSOLUTE_J,.005,1e-12,"J",["external_work_j"]),
			tangent_dissipation_j=_tol(WORK_ABSOLUTE_J,.005,1e-12,"J",["tangent_dissipation_j","external_work_j"]),
			normal_dissipation_j=_tol(WORK_ABSOLUTE_J,.005,1e-12,"J",["normal_dissipation_j"]),
			prescribed_contact_work_j=_tol(WORK_ABSOLUTE_J,.005,1e-12,"J",["prescribed_contact_work_j"])}}
	quality=Accuracy.prepare(raw,layout)
	check("actual selected operator/live CG/complete SI quality binds",quality.ok,str(quality))

func _new_sim(initial: PackedFloat64Array) -> Node:
	var vehicle := Model.new()
	vehicle.aux_size = 13
	vehicle.modes_size = 2
	vehicle.continuous_size = 4
	vehicle.state_layout_identity = "composition-v2:"+(selected_law+quality.identity).sha256_text()
	vehicle.stage = func(body, values, at):
		var combined: PackedFloat64Array = body.duplicate()
		combined.append_array(values)
		var point := _snapshot(combined, at)
		if not point.ok: return {}
		return {loads = point.loads, derivative = point.derivative.slice(RB.SIZE), rotor_momentum = M.v3(0.0, 0.0, 0.0), body_derivative = point.derivative.slice(0, RB.SIZE)}
	vehicle.step_policy = func(state, at, dt, f, first): return Step.advance(state, at, dt, f, first, _snapshot, _certificate, _options(), _error_gate)
	vehicle.endpoint_transition = func(_previous, candidate, context):
		if context.body_filtered or not context.has("integration_receipt"): return {}
		var receipt: Dictionary = context.integration_receipt
		candidate.aux[0] += receipt.normal_dissipation_j
		candidate.aux[1] += receipt.tangent_dissipation_j
		candidate.aux[2] += receipt.external_work_j
		candidate.aux[3] = maxf(candidate.aux[3], absf(receipt.energy_balance_residual_j))
		candidate.aux[4] = receipt.accepted_substeps
		candidate.aux[5] = 0.0
		var loaded := 0
		for load_n: float in receipt.normal_samples_n[-1]:
			candidate.aux[5] += load_n
			if load_n > 0.0: loaded += 1
		candidate.aux[6] = receipt.error_control.normalized_error
		candidate.aux[7] = maxf(candidate.aux[7], loaded)
		candidate.aux[8] = maxf(candidate.aux[8], receipt.accepted_substeps)
		candidate.aux[9] = maxf(candidate.aux[9], candidate.aux[5])
		if receipt.has("assembly_resolution"):
			var proof:Dictionary=receipt.assembly_resolution
			var uncertainty:float=proof.combined_contact_uncertainty_sum_j
			if uncertainty>TICK_ASSEMBLY_BUDGET_J:return {}
			candidate.aux[10]+=uncertainty
			candidate.aux[11]+=proof.accepted_at_resolution
			candidate.aux[12]=maxf(candidate.aux[12],uncertainty)
		candidate.events = []
		if candidate.modes[0] == 0 and loaded > 0:
			candidate.events.append({type = "composition_touchdown", time_s = context.time_s})
			candidate.modes[1] = 1
		elif candidate.modes[0] > 0 and loaded == 0:
			candidate.events.append({type = "composition_last_contact_unloaded", time_s = context.time_s})
		candidate.modes[0] = loaded
		return {} if reject_endpoint else candidate
	var sim := Sim.new()
	sim.mass = live.mass_kg
	sim.inertia = live.inertia.duplicate()
	sim.gravity = GRAVITY
	sim.aux = PackedFloat64Array()
	sim.aux.resize(13)
	sim.modes = PackedInt64Array([0, 0])
	sim.continuous = initial.slice(RB.SIZE)
	check("composed VehicleModel installs and resets", sim.set_model(vehicle) and sim.reset(initial.slice(0, RB.SIZE)))
	return sim

func _combined(sim: Node) -> PackedFloat64Array:
	var state: PackedFloat64Array = sim.state.duplicate()
	state.append_array(sim.continuous)
	return state

const Candidate:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_step.gd")
const Quality:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_accuracy.gd")
const Unloaded:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-capacity-production/review-v1/frozen/app/physics/aircraft_ground_unloaded.gd")
var binding:Dictionary
var source_seal:PackedByteArray
func _source()->Array:return [lift_start,lift_duration,lift_ratio,brake_start,selected_law]
func _config()->Dictionary:
	return {ground_stage=prepared,properties=live,provider=provider,motion=motion,gravity=GRAVITY,minimum_kappa=KAPPA_MIN,owner_dynamics_identity=var_to_bytes(_source()).hex_encode().sha256_text()}
func _bind()->void:
	source_seal=var_to_bytes(_source())
	binding=Unloaded.prepare(_config())
	check("actual owner fixed mechanical/source configuration binds",binding.ok,str(binding))
func _sample_policy(state:PackedFloat64Array,at:float)->Dictionary:
	# Revalidate captures at every actual evaluation, not just policy invocation.
	if source_seal!=var_to_bytes(_source()) or var_to_bytes(binding.config)!=var_to_bytes(_config()):return {ok=false,reason="owner captured evaluator configuration changed"}
	var sample:=_snapshot(state,at)
	if sample.ok:
		sample.normal_support_potential_j=sample.physical.ground.potential_j
		sample.normal_support_identity=binding.identity
	return sample
func _policy(state:PackedFloat64Array,at:float,h:float,point:Dictionary)->Dictionary:
	# This closure owns the ACTUAL evaluator above: Stage with fixed hubs/plane,
	# only declared lift ramp and prescribed brakes, no aero/motor/heat feedback.
	# Configuration mutation is refused even when instantaneous loads still zero.
	if source_seal!=var_to_bytes(_source()):return {ok=false,eligible=false,identity=binding.identity}
	if at+h>=brake_start or (lift_ratio!=0.0 and at+h>=lift_start):return {ok=true,eligible=false,identity=binding.identity}
	var result:=Unloaded.qualify(binding,_config(),state,h,point)
	return {ok=result.ok,eligible=result.get("eligible",false),identity=binding.identity}
func _gate(a:PackedFloat64Array,b:PackedFloat64Array,ar:Dictionary,br:Dictionary,h:float)->Dictionary:
	var result:=Quality.diagnose(quality,a,b,ar,br,h)
	return {ok=result.ok,admitted=result.admitted,identity=result.identity,normalized_error=result.normalized_error}
func _read(name:String)->Dictionary:
	var f:=FileAccess.open("res://tests/fixtures/"+name,FileAccess.READ)
	var raw:Dictionary=bytes_to_var(f.get_buffer(f.get_length()));f.close()
	lift_start=raw.lift_start;lift_duration=raw.lift_duration;lift_ratio=raw.lift_ratio;brake_start=raw.brake_start
	_bind()
	return raw
func _attempt(raw:Dictionary,count:int,policy:Callable)->Dictionary:
	var initial:=_sample_policy(raw.state,raw.time_s)
	if not initial.ok:return initial
	return Candidate._attempt(raw.state,raw.time_s,raw.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,initial,count,Candidate._settings(raw.options),policy,{})
func _kernel(raw:Dictionary)->void:
	var sim:=_new_sim(raw.state)
	sim.model.step_policy=func(state,at,h,f,k1):return Candidate.advance(state,at,h,f,k1,_sample_policy,_certificate,_options(),_gate,_policy)
	sim.model.state_layout_identity+="/normal-loss:"+binding.identity
	check("policy owner layout reset validates",sim.reset(raw.state.slice(0,RB.SIZE)))
	var original:Dictionary=sim.checkpoint()
	original.tick=roundi(raw.time_s/raw.dt)
	check("candidate kernel restores exact retained clock",sim.restore_checkpoint(original))
	var emissions:={n=0}
	sim.stepped.connect(func(_a,_b,_c,_d,_e,_f):emissions.n+=1)
	sim.step()
	check("kernel accepts actual policy complete step",sim.tick==original.tick+1 and sim.fault_reason.is_empty(),sim.fault_reason)
	check("only accepted step publishes and accumulates heat",emissions.n==1 and sim.aux[0]>0.0)
	var final:=var_to_bytes(sim.checkpoint())
	check("kernel checkpoint restores for exact continuation",sim.restore_checkpoint(original))
	sim.step()
	check("kernel continued policy checkpoint bytes match",final==var_to_bytes(sim.checkpoint()))
	check("rollback baseline restores",sim.restore_checkpoint(original))
	var before:=var_to_bytes([sim.state,sim.previous,sim.continuous,sim.aux,sim.modes,sim.inputs,sim.last_loads])
	var before_emissions:int=emissions.n
	reject_endpoint=true
	sim.step()
	reject_endpoint=false
	check("endpoint refusal rolls back full accepted frame",sim.tick==original.tick and before==var_to_bytes([sim.state,sim.previous,sim.continuous,sim.aux,sim.modes,sim.inputs,sim.last_loads]))
	check("discarded policy heat/events do not publish",emissions.n==before_emissions and not sim.fault_reason.is_empty())
	sim.free()
func _initialize()->void:
	_fixture();_prepare_composition();_prepare_quality()
	var gentle:=_read("ground_unloaded_gentle.bin")
	var paths:Array=[]
	for count in [8,16]:
		var original:=Step._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,_sample_policy(gentle.state,gentle.time_s),count,Step._settings(gentle.options))
		var unchanged:=_attempt(gentle,count,Callable())
		check("default complete output byte parity n="+str(count),var_to_bytes(unchanged)==var_to_bytes(original))
		var candidate:=_attempt(gentle,count,_policy)
		check("qualified policy candidate accepted",candidate.ok,str(candidate))
		if not candidate.ok:quit(1);return
		check("qualified body/spin state bytes unchanged",var_to_bytes(candidate.state)==var_to_bytes(original.state))
		check("all piece residuals recomputed under corrected method",candidate.integration_receipt.maximum_piece_energy_residual_j<1e-10)
		paths.append(candidate)
	var pair:=Quality.diagnose(quality,paths[0].state,paths[1].state,paths[0].integration_receipt,paths[1].integration_receipt,gentle.dt)
	check("raw complete gate passes unchanged physical quality",pair.ok and pair.admitted,str(pair))
	var result:=Candidate.advance(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,gentle.options,_gate,_policy)
	check("public advance accepts only complete finer path",result.ok and result.integration_receipt.accepted_substeps==16,str(result))
	var wrong_arity:=func()->Dictionary:return {ok=true,eligible=true,identity=binding.identity}
	var arity_refusal:=Candidate.advance(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,gentle.options,Callable(),wrong_arity)
	check("valid wrong-arity policy refuses before call",not arity_refusal.ok and arity_refusal.status=="invalid_normal_loss_policy")
	var target:=Node.new()
	var freed:=Callable(target,"get_name")
	target.free()
	check("freed optional policy refuses safely",not Candidate.advance(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),_sample_policy,_certificate,gentle.options,Callable(),freed).ok)
	var with_bound:=func(_s,_t,_h,_p,id)->Dictionary:return {ok=true,eligible=false,identity=id}
	check("bound callable with effective arity4 remains valid",_attempt(gentle,8,with_bound.bind(binding.identity)).ok)
	var lie_settings:=Candidate._settings(gentle.options)
	lie_settings.operator_law=Candidate.LAW
	var first:=_derivative(gentle.state,gentle.time_s)
	var lie:=Candidate._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,first,_sample_policy,_certificate,_sample_policy(gentle.state,gentle.time_s),8,lie_settings,_policy,{})
	check("Lie identity-prekick path supports trusted heat policy",lie.ok,str(lie))
	first[RB.VEL]+=.001
	var stale:=Candidate._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,first,_sample_policy,_certificate,_sample_policy(gentle.state,gentle.time_s),8,lie_settings,_policy,{})
	check("eligible policy rejects stale supplied Lie k1",not stale.ok and stale.status=="invalid_normal_loss_policy",str(stale))
	_kernel(gentle)
	for bad:Variant in [null,true,[],{},3,3.2]:
		var receipt:Dictionary=paths[1].integration_receipt.duplicate(true)
		receipt.normal_loss_policy.format=bad
		check("typed policy format refuses safely",not Quality.diagnose(quality,paths[0].state,paths[1].state,paths[0].integration_receipt,receipt,gentle.dt).ok)
		receipt=paths[1].integration_receipt.duplicate(true)
		receipt.normal_loss_policy.pieces[0].normal_dissipation_j=bad
		check("typed piece loss refuses safely",not Quality.diagnose(quality,paths[0].state,paths[1].state,paths[0].integration_receipt,receipt,gentle.dt).ok)
		var config:Dictionary=_config().duplicate(true)
		config.provider.format=bad
		check("typed provider format refuses safely",not Unloaded.prepare(config).ok)
		config=_config().duplicate(true);config.provider.geometry_law=bad
		check("typed provider law refuses safely",not Unloaded.prepare(config).ok)
		config=_config().duplicate(true);config.motion[0].contact_id=bad
		check("typed motion contact identity refuses safely",not Unloaded.prepare(config).ok)
		var broken:Dictionary=binding.duplicate(true);broken.format=bad
		check("typed binding format refuses safely",not Unloaded.qualify(broken,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
		broken=binding.duplicate(true);broken.law=bad
		check("typed binding law refuses safely",not Unloaded.qualify(broken,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
		var point:=_sample_policy(gentle.state,gentle.time_s)
		point.mass_kg=bad
		check("typed live mass refuses safely",not Unloaded.qualify(binding,_config(),gentle.state,gentle.dt,point).ok)
		point=_sample_policy(gentle.state,gentle.time_s);point.cg_body_m=bad
		check("typed live CG refuses safely",not Unloaded.qualify(binding,_config(),gentle.state,gentle.dt,point).ok)
		config=_config().duplicate(true);config.motion[0].hub_body=bad
		check("typed fixed hub refuses safely",not Unloaded.prepare(config).ok)
		config=_config().duplicate(true);config.motion[0].axle_body=bad
		check("typed fixed axle refuses safely",not Unloaded.prepare(config).ok)
		broken=binding.duplicate(true);broken.expected_matrix=bad
		check("typed expected matrix refuses safely",not Unloaded.qualify(broken,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
		broken=binding.duplicate(true);broken.expected_carrier=bad
		check("typed expected carrier refuses safely",not Unloaded.qualify(broken,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
	var mutated:=func(state:PackedFloat64Array,_at:float,_h:float,_s:Dictionary)->Dictionary:
		state[0]+=1.0
		return {ok=true,eligible=true,identity=binding.identity}
	var refused:=_attempt(gentle,8,mutated)
	check("policy input mutation refuses",not refused.ok and refused.status=="invalid_normal_loss_policy",str(refused))
	var malformed:=func(_state,_at,_h,_s)->Dictionary:return {ok=true,eligible=1,identity=binding.identity}
	check("malformed policy refuses",not _attempt(gentle,8,malformed).ok)
	var unsupported:=func(_state,_at,_h,_s)->Dictionary:return {ok=false,eligible=false,identity=binding.identity}
	check("owner refusal refuses whole attempt",not _attempt(gentle,8,unsupported).ok)
	var identity_count:={n=0}
	var unstable:=func(_state,_at,_h,_s)->Dictionary:
		identity_count.n+=1
		return {ok=true,eligible=false,identity=str(identity_count.n)}
	check("changing owner identity refuses",not _attempt(gentle,8,unstable).ok)
	var declined:=func(_state,_at,_h,_s)->Dictionary:return {ok=true,eligible=false,identity=binding.identity}
	var declined_result:=_attempt(gentle,8,declined)
	var default_result:=_attempt(gentle,8,Callable())
	declined_result.integration_receipt.erase("normal_loss_policy")
	declined_result.integration_receipt.quadrature_method="RK4_algebraic_stage_weights_not_damage_samples"
	check("declining policy preserves complete numeric/default output",var_to_bytes(declined_result)==var_to_bytes(default_result))
	var changed_sample:=func(state,at):
		var sample:=_sample_policy(state,at)
		if at>gentle.time_s:sample.normal_support_identity="changed"
		return sample
	var refused_identity:=Candidate._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),changed_sample,_certificate,changed_sample.call(gentle.state,gentle.time_s),8,Candidate._settings(gentle.options),_policy,{})
	check("mid-RK support identity mutation refuses",not refused_identity.ok and not refused_identity.has("state"))
	var hidden_loaded:=func(state,at):
		var sample:=_sample_policy(state,at)
		if at>gentle.time_s:sample.normal_load_n[2]=.01
		return sample
	var refused_load:=Candidate._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),hidden_loaded,_certificate,hidden_loaded.call(gentle.state,gentle.time_s),8,Candidate._settings(gentle.options),_policy,{})
	check("actual loaded RK evaluation contradicts and refuses qualification",not refused_load.ok and not refused_load.has("state"))
	var saved_material:String=provider.regions[0].material_id
	var mutate_capture:=func(state,at):
		if at>gentle.time_s:provider.regions[0].material_id="mid-RK-mutation"
		return _sample_policy(state,at)
	var initial_sample:=_sample_policy(gentle.state,gentle.time_s)
	var mid_refusal:=Candidate._attempt(gentle.state,gentle.time_s,gentle.dt,_derivative,PackedFloat64Array(),mutate_capture,_certificate,initial_sample,8,Candidate._settings(gentle.options),_policy,{})
	check("owner catches captured provider mutation during actual RK",not mid_refusal.ok and not mid_refusal.has("state"))
	provider.regions[0].material_id=saved_material
	var old_mass:float=live.mass_kg;live.mass_kg+=.01
	check("captured live mass mutation refuses helper binding",not Unloaded.qualify(binding,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
	live.mass_kg=old_mass
	var old_region:String=provider.regions[0].material_id;provider.regions[0].material_id="changed"
	check("captured provider mutation refuses helper binding",not Unloaded.qualify(binding,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
	provider.regions[0].material_id=old_region
	var old_hub:float=motion[0].hub_body[0];motion[0].hub_body[0]+=.001
	check("captured fixed motion mutation refuses helper binding",not Unloaded.qualify(binding,_config(),gentle.state,gentle.dt,_sample_policy(gentle.state,gentle.time_s)).ok)
	motion[0].hub_body[0]=old_hub
	lift_ratio=.01
	check("captured future source configuration mutation refuses",not _attempt(gentle,8,_policy).ok)
	lift_ratio=gentle.lift_ratio
	var hard:=_read("ground_unloaded_hard.bin")
	var hard_paths:Array=[]
	for count in [8,16]:
		var candidate:=_attempt(hard,count,_policy)
		var unchanged:=_attempt(hard,count,Callable())
		check("mixed loaded/unloaded policy keeps state bytes",candidate.ok and unchanged.ok and var_to_bytes(candidate.state)==var_to_bytes(unchanged.state),str(candidate))
		if not candidate.ok:quit(1);return
		var methods:={}
		for piece:Dictionary in candidate.integration_receipt.normal_loss_policy.pieces:methods[piece.method]=true
		check("loaded and qualified pieces use distinct recorded methods",methods.size()==2,str(methods))
		hard_paths.append(candidate)
	var hard_pair:=Quality.diagnose(quality,hard_paths[0].state,hard_paths[1].state,hard_paths[0].integration_receipt,hard_paths[1].integration_receipt,hard.dt)
	check("hard tangent raw failure is preserved",hard_pair.ok and not hard_pair.admitted,str(hard_pair))
	print("Unloaded policy: %d checks, %d failed"%[checks,failed])
	quit(1 if failed else 0)
