## Full three-wheel/shaft pipeline on a static plane. Installed P51 hardware,
## explicitly synthetic normal/aggregate/material data; no fleet calibration.
extends "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/stage_fixture.gd"
const Traction := preload("res://physics/aircraft_ground_traction.gd")
const Step := preload("res://physics/aircraft_ground_step.gd")
const Admission := preload("res://physics/normal_contact_admission.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const Accuracy := preload("res://physics/aircraft_ground_accuracy.gd")
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

func _initialize() -> void:
	_fixture()
	_prepare_composition()
	if failed:
		quit(1)
		return
	_prepare_quality()
	if failed:
		quit(1)
		return
	var only:=OS.get_cmdline_user_args()
	if only.is_empty() or only.has("--only-drop"):
		_drop_case(0.25, 180)
		_drop_case(1.2, 180)
	if only.is_empty() or only.has("--only-lift"): _lift_brake_replay()
	if only.is_empty() or only.has("--only-refinement"): _refinement()
	if only.is_empty() or only.has("--only-rest"): _rest()
	print("Aircraft ground composition: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

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

func _energy(sim: Node) -> float:
	var state := _combined(sim)
	return Step._energy(state, _snapshot(state, sim.time()))

func _diagnose(sim: Node) -> void:
	if sim.fault_reason.is_empty(): return
	var attempted := Step.advance(_combined(sim), sim.time(), sim.dt(), _derivative, PackedFloat64Array(), _snapshot, _certificate, _options(), _error_gate)
	print("COMPOSITION_REFUSAL at=", sim.time(), " reason=", attempted)
	var state:=_combined(sim)
	var data:={state=state,time_s=sim.time(),dt=sim.dt(),quality=quality,options=_options(),
		lift_start=lift_start,lift_duration=lift_duration,lift_ratio=lift_ratio,brake_start=brake_start}
	var path:="C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-composition-draft/failure-"+str(sim.tick)+"-"+var_to_bytes(state).hex_encode().sha256_text().left(12)+".bin"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(var_to_bytes(data))
	file.close()

func _drop_case(speed: float, ticks: int) -> void:
	lift_ratio = 0.0
	brake_start = 100.0
	var initial := _initial(-0.28, 3.0, speed, 0.0)
	var sim := _new_sim(initial)
	var seen: Array = []
	sim.events_located.connect(func(_tick, events):
		for event: Dictionary in events: seen.append(event.type))
	var initial_energy := _energy(sim)
	var max_compression := 0.0
	var rebound := false
	for tick in ticks:
		sim.step()
		if not sim.fault_reason.is_empty(): break
		var point := _snapshot(_combined(sim), sim.time())
		for contact: Dictionary in point.physical.ground.contacts:
			if contact.geometry_evaluated: max_compression = maxf(max_compression, -contact.gap_m)
		rebound = rebound or (sim.modes[1] == 1 and sim.state[RB.VEL + 2] < -0.1)
	check("gentle/harder full-pipeline drop accepts every tick", sim.tick == ticks and sim.fault_reason.is_empty(), "v=%s tick=%s fault=%s" % [speed, sim.tick, sim.fault_reason])
	_diagnose(sim)
	check("drop touches all three hardware wheels and spins each", sim.aux[7] == 3.0 and sim.continuous[1] > 0.1 and sim.continuous[2] > 0.1 and sim.continuous[3] > 0.1)
	check("normal contact rebounds without terminal state", seen.has("composition_touchdown") and rebound and max_compression > 0.01 and max_compression < X_MAX)
	var balance: float = _energy(sim) + sim.aux[0] + sim.aux[1] - sim.aux[2] - initial_energy
	check("drop independent mechanical work balance closes", absf(balance) < 2.0e-4, str(balance))
	check("drop uses conditional admission and paired bounded paths", sim.aux[8] <= 16.0 and sim.aux[8] >= 4.0 and sim.aux[6] <= 1.0)
	print("composition drop v=", speed, " ticks=", sim.tick, " xpeak=", max_compression, " heat=", sim.aux[0] + sim.aux[1], " work_error=", balance)
	sim.free()

func _lift_brake_replay() -> void:
	lift_start = 0.2
	lift_duration = 1.5
	lift_ratio = 1.4
	brake_start = 0.1
	var sag: float = live.mass_kg * GRAVITY / 4500.0
	var sim := _new_sim(_initial(-0.2 + sag, 3.0, 0.0, 3.0))
	var initial_energy := _energy(sim)
	var sum_before := 0.0
	var sum_after := 0.0
	var capacity_before := 0.0
	var capacity_after := 0.0
	var last_loaded_n := INF
	var unloaded := false
	var saw_partial := false
	var braked_speed := 3.0
	var checkpoint := {}
	for tick in 480:
		sim.step()
		if not sim.fault_reason.is_empty(): break
		var point := _snapshot(_combined(sim), sim.time())
		var rolling := 0.0
		for i in point.rows.labels.size():
			if point.rows.labels[i].kind == "rolling_moment": rolling += point.rows.limit_rates[i]
		if tick >= 30 and tick < 50:
			sum_before += sim.aux[5]
			capacity_before += rolling
		if tick >= 280 and tick < 300:
			sum_after += sim.aux[5]
			capacity_after += rolling
		if sim.modes[0] > 0: last_loaded_n = sim.aux[5]
		if sim.modes[0] > 0 and sim.modes[0] < 3: saw_partial = true
		if sim.modes[1] == 1 and sim.modes[0] == 0: unloaded = true
		if tick == 45: braked_speed = sim.state[RB.VEL]
		if tick == 100: checkpoint = sim.checkpoint()
	check("loaded braking/lift ramp accepts full tape", sim.tick == 480 and sim.fault_reason.is_empty(), "tick=%s %s" % [sim.tick, sim.fault_reason])
	_diagnose(sim)
	check("loaded installed brakes reduce speed and publish passive loss", braked_speed < 3.0 and sim.aux[1] > 0.0)
	check("applied lift progressively reduces normal load and rolling capacity", sum_after < 0.7 * sum_before and capacity_after < 0.7 * capacity_before \
		and sum_before > 0.0 and capacity_before > 0.0)
	check("natural final contact unloads after partial contact without lift switch", saw_partial and unloaded and last_loaded_n < 0.1 * live.mass_kg * GRAVITY)
	var balance: float = _energy(sim) + sim.aux[0] + sim.aux[1] - sim.aux[2] - initial_energy
	check("CM lift work and gravity potential close nonconservative balance", absf(balance) < 3.0e-4 and absf(sim.aux[2]) > 0.01, str(balance))
	if not checkpoint.is_empty():
		check("full-pipeline checkpoint restores", sim.restore_checkpoint(checkpoint))
		for i in 20: sim.step()
		var expected := var_to_bytes(sim.checkpoint())
		check("second restore succeeds", sim.restore_checkpoint(checkpoint))
		for i in 20: sim.step()
		check("full-pipeline checkpoint continuation is byte-identical", expected == var_to_bytes(sim.checkpoint()))
		var before: Dictionary = sim.checkpoint()
		var state_before: PackedFloat64Array = sim.state.duplicate()
		var aux_before: PackedFloat64Array = sim.aux.duplicate()
		var modes_before: PackedInt64Array = sim.modes.duplicate()
		var values_before: PackedFloat64Array = sim.continuous.duplicate()
		var phantom := [0]
		sim.events_located.connect(func(_tick, _events): phantom[0] += 1)
		reject_endpoint = true
		sim.step()
		reject_endpoint = false
		check("endpoint refusal rolls back composed impulses/work/modes/body", sim.tick == before.tick and sim.state == state_before and sim.aux == aux_before \
			and sim.modes == modes_before and sim.continuous == values_before and not sim.fault_reason.is_empty())
		check("rejected composed path publishes no phantom events", phantom[0] == 0)
	print("composition lift: ticks=", sim.tick, " Nbefore=", sum_before / 20.0, " Nafter=", sum_after / 20.0,
		" last_N=", last_loaded_n, " capacity_before=", capacity_before / 20.0, " capacity_after=", capacity_after / 20.0, " work_error=", balance)
	sim.free()

func _refinement() -> void:
	lift_ratio = 0.0
	brake_start = 100.0
	var saved := Engine.physics_ticks_per_second
	var ends: Array[PackedFloat64Array] = []
	for hz: int in [240, 480, 960]:
		Engine.physics_ticks_per_second = hz
		var sim := _new_sim(_initial(-0.19, 3.0, 0.5, 0.0))
		for i in hz / 10:
			sim.step()
			if not sim.fault_reason.is_empty(): break
		check("physical-tape refinement run remains admitted", sim.tick == hz / 10 and sim.fault_reason.is_empty(), str(hz) + " " + sim.fault_reason)
		_diagnose(sim)
		ends.append(_combined(sim))
		sim.free()
	Engine.physics_ticks_per_second = saved
	var coarse := 0.0
	var fine := 0.0
	for i in range(3, 17):
		coarse = maxf(coarse, absf(ends[0][i] - ends[2][i]))
		fine = maxf(fine, absf(ends[1][i] - ends[2][i]))
	check("complete split pipeline refines in state error", fine < coarse and coarse > 0.0, "coarse=%s fine=%s" % [coarse, fine])


func _rest() -> void:
	lift_ratio=0.0
	brake_start=100.0
	var sag:float=live.mass_kg*GRAVITY/4500.0
	var sim:=_new_sim(_initial(-.2+sag,0.0,0.0,0.0))
	var e0:=_energy(sim)
	var maximum_drift:=0.0
	var maximum_positive_tick_j:=0.0
	var previous_accounted:=e0
	var rest:={}
	var hz:=Engine.physics_ticks_per_second
	for tick in 10*hz:
		sim.step()
		if not sim.fault_reason.is_empty():break
		var accounted:float=_energy(sim)+sim.aux[0]+sim.aux[1]
		maximum_positive_tick_j=maxf(maximum_positive_tick_j,accounted-previous_accounted)
		previous_accounted=accounted
		maximum_drift=maxf(maximum_drift,absf(accounted-e0))
		if tick==6*hz-1:
			var state:=_combined(sim)
			var point:=_snapshot(state,sim.time())
			var q:=M.q_normalized(state.slice(RB.ATT,RB.ATT+4))
			var force:=M.add(M.q_rotate(q,point.physical.loads.slice(0,3)),M.v3(0,0,live.mass_kg*GRAVITY))
			var moment:=M.sub(point.physical.loads.slice(3),M.cross(live.cg_body_m,point.physical.loads.slice(0,3)))
			var cmv:=M.add(state.slice(RB.VEL,RB.VEL+3),M.cross(state.slice(RB.RATE),live.cg_body_m))
			rest={speed_mps=M.norm(cmv),rate_radps=M.norm(state.slice(RB.RATE)),force_residual_n=M.norm(force),moment_residual_nm=M.norm(moment)}
		if tick%hz==hz-1:print("COMPOSITION_REST_PROGRESS t=",sim.time()," drift_J=",maximum_drift," resolution_count=",sim.aux[11])
	check("actual three-wheel rest completes ten-second tape",sim.tick==10*hz and sim.fault_reason.is_empty(),sim.fault_reason)
	_diagnose(sim)
	if not rest.is_empty():
		check("six-second physical rest meets speed and rate gates",rest.speed_mps<1e-4 and rest.rate_radps<1e-4,str(rest))
		check("six-second physical rest balances force and moment",rest.force_residual_n<1e-6*live.mass_kg*GRAVITY
			and rest.moment_residual_nm<1e-6*live.mass_kg*GRAVITY*.9,str(rest))
	check("closed static-support work has bounded maximum and endpoint drift",maximum_drift/maxf(1.0,absf(e0))<1e-6
		and absf(previous_accounted-e0)/maxf(1.0,absf(e0))<1e-6,str(maximum_drift))
	check("static support has no unexplained positive per-tick work",maximum_positive_tick_j<1e-6,str(maximum_positive_tick_j))
	check("accepted tick assembly proofs stay within owner work allocation",sim.aux[12]<=TICK_ASSEMBLY_BUDGET_J)
	print("COMPOSITION_REST ",JSON.stringify({tick=sim.tick,rest_at6s=rest,max_drift_j=maximum_drift,
		max_positive_tick_j=maximum_positive_tick_j,contact_numerical_certificate_sum_j=sim.aux[10],assembly_count=sim.aux[11]},"",true,true))
	sim.free()
