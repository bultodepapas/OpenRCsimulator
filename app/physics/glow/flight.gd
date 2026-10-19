## NITRO flight adapter. All evolving values live in Simulation.continuous.
## Layout: RPM, six lifecycle values, running/reason/opportunities/fires/accumulator,
## mixture command, then shaft/propeller/thrust/chemical work (J).
extends RefCounted
const Life := preload("res://physics/glow/lifecycle.gd")
const Vibration := preload("res://physics/glow/vibration.gd")
const Source := preload("res://physics/glow/source.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
const MassInventory := preload("res://physics/mass_inventory.gd")
const FixedDatumBody := preload("res://physics/fixed_datum_body.gd")
const Blade := preload("res://physics/glow/propeller.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Coupling := preload("res://physics/rotor_coupling.gd")
const Boundary := preload("res://physics/electric_battery_step.gd")
const FuelFeed := preload("res://physics/glow/fuel_feed.gd")
const SIZE := 17
const LAW := "glow-mean-cycle-finite-tank-hub-inflow-v2"
const REASONS := ["", "not_started", "cut", "stall", "fuel_exhausted", "overheat"]
const EVALUATOR_META := &"_glow_prepared_evaluator"
const PROPELLER_EVALUATOR_META := &"_glow_prepared_propeller"
const VIBRATION_EVALUATOR_META := &"_glow_source_vibration"
const EVALUATOR_IDENTITY_META := &"_glow_prepared_identity"

## Session demand may include an injected receiver/throttle fault. Standalone physical fixtures keep raw inputs.
static func _throttle(owner: Node) -> float:
	return owner.propulsion_throttle() if owner.has_method("propulsion_throttle") else owner.sim.inputs[3]

## The failure runtime is a read-only candidate during RK; standalone fixtures have no injection.
static func _injected_cut(owner: Node) -> bool:
	return owner.has_method("failure_power_cut_active") and owner.failure_power_cut_active()

## Real sessions sample the stage body datum; older isolated fixtures provide uniform ambient methods.
static func _environment(owner: Node, body: PackedFloat64Array) -> Dictionary:
	if owner.has_method("environment_at"):
		return owner.environment_at(body)
	var ambient: Dictionary = owner.atmosphere_configuration().duplicate()
	ambient.ok = true
	ambient.rho_kgm3 = owner.air_density()
	ambient.engine_charge_ratio = owner.engine_charge_ratio()
	return ambient

static func valid(values: PackedFloat64Array, install: Dictionary) -> bool:
	var state: Dictionary=unpack(values,install)
	if state.is_empty() or Life.pack_state(state).size()!=6: return false
	if values[1]<0.0 or values[5]<0.0 or values[3]<0.0 or values[3]>1.0 or values[4]<0.0 or values[4]>1.0: return false
	if values[0]<0.0 or values[0]>install.profile.operation.max_rpm or values[1]>install.capacity_fuel_kg or values[12]<0.0 or values[12]>2.8: return false
	if values[6]<0.0 or values[6]>=install.profile.identity.cycle_revolutions or values[9]!=floor(values[9]) or values[10]!=floor(values[10]): return false
	return true

static func unpack(values: PackedFloat64Array, install: Dictionary) -> Dictionary:
	if values.size()<SIZE: return {}
	for v in values:
		if not is_finite(v): return {}
	if values[7] not in [0.0,1.0] or values[8]!=floor(values[8]) or values[8]<0.0 or values[8]>=REASONS.size(): return {}
	var state: Dictionary={family=install.profile.family,cycle_revolutions=install.profile.identity.cycle_revolutions,
		running=values[7]==1.0,stop_reason=REASONS[int(values[8])],opportunity_count=int(values[9]),fire_count=int(values[10]),firing_accumulator=values[11]}
	for i in 6: state[Life.CONTINUOUS_KEYS[i]]=values[i+1]
	return state

static func put_state(values: PackedFloat64Array, state: Dictionary) -> PackedFloat64Array:
	var out: PackedFloat64Array=values.duplicate()
	for i in 6: out[i+1]=state[Life.CONTINUOUS_KEYS[i]]
	out[7]=1.0 if state.running else 0.0
	out[8]=REASONS.find(state.stop_reason)
	out[9]=state.opportunity_count
	out[10]=state.fire_count
	out[11]=state.firing_accumulator
	return out

static func initial(owner: Node, aux: PackedFloat64Array, body: PackedFloat64Array) -> PackedFloat64Array:
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	# A fresh immutable installation evaluator on every reset/reload. This owns no
	# physical state and is excluded from model serialization and checkpoints.
	var prepared: Dictionary=Life.prepare_evaluator(install.profile,install.settings)
	if not prepared.ok:
		if owner.has_meta(EVALUATOR_META): owner.remove_meta(EVALUATOR_META)
		return PackedFloat64Array([NAN])
	var prepared_propeller: Dictionary=Blade.prepare_evaluator(install.propeller)
	if not prepared_propeller.ok:
		if owner.has_meta(PROPELLER_EVALUATOR_META): owner.remove_meta(PROPELLER_EVALUATOR_META)
		return PackedFloat64Array([NAN])
	var prepared_vibration: Dictionary=Vibration.prepare(install.profile)
	if not prepared_vibration.ok:
		if owner.has_meta(VIBRATION_EVALUATOR_META): owner.remove_meta(VIBRATION_EVALUATOR_META)
		return PackedFloat64Array([NAN])
	owner.set_meta(VIBRATION_EVALUATOR_META,prepared_vibration)
	owner.set_meta(PROPELLER_EVALUATOR_META,prepared_propeller.evaluator)
	owner.set_meta(EVALUATOR_META,prepared.evaluator)
	owner.set_meta(EVALUATOR_IDENTITY_META,install.identity.duplicate(true))
	# FUEL-07: the session's start fill of the authored full tank (1 = full).
	var start_fuel: float=owner.start_fuel_kg() if owner.has_method("start_fuel_kg") else install.reference_fuel_kg
	var made: Dictionary=Life.create(install.profile,install.settings,start_fuel,
		install.initial_temperature_k,aux[0],owner.engine_running,install.unusable_fuel_kg)
	if not made.ok: return PackedFloat64Array([NAN])
	var state: Dictionary=made.state
	state.servo_fraction=_throttle(owner)
	state.air_fraction=install.settings.idle_admission+(1.0-install.settings.idle_admission)*state.servo_fraction
	var ambient: Dictionary = _environment(owner, body)
	if not ambient.get("ok", false): return PackedFloat64Array([NAN])
	var point: Dictionary=Source.evaluate(install.profile,aux[0],state.air_fraction,install.profile.operation.nominal_mixture,
		1.225*float(ambient.engine_charge_ratio),owner.engine_running)
	if not point.ok: return PackedFloat64Array([NAN])
	state.fuel_transport_kg_s=point.delivered_fuel_kg_s
	var out:=PackedFloat64Array()
	out.resize(SIZE)
	out[0]=aux[0]
	out[12]=install.profile.operation.nominal_mixture
	if install.has("fuel_feed"):
		# Seed transport from the actual start loads and apparent gravity. The feed
		# factor can differ from the level-flight value used by Source.evaluate above.
		var stage_values: PackedFloat64Array=put_state(out,state)
		for _i in owner.wheel_count(): stage_values.append(0.0)
		var initial_point: Dictionary=point(owner,body,stage_values,0.0)
		print("DEBUG GLOW initial point ", initial_point)
		if not initial_point.get("ok",false): return PackedFloat64Array([NAN])
		var telemetry: Dictionary=initial_point.get("telemetry",{})
		var target: float=float(telemetry.get("fuel_target_kg_s",NAN))
		if not is_finite(target) or target<0.0: return PackedFloat64Array([NAN])
		state.fuel_transport_kg_s=target
	return put_state(out,state)

static func properties(owner: Node, fuel: float) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var install: Dictionary=model.propulsion.glow
	# FUEL-04: the installation's prepared reference; re-prepared only if the model's wet values were replaced.
	var reference: Dictionary=install.get("mass_reference",{})
	if reference.get("reference_mass_kg",NAN)!=float(model.mass_kg) or reference.get("reference_inertia_kgm2",PackedFloat64Array())!=model.inertia:
		reference=FuelMass.prepare(model.mass_kg,model.inertia,install.reference_fuel_kg,
			install.tank_position,install.tank_size,install.capacity_fuel_kg,str(install.fuel_tank.id))
		if not reference.get("ok",false): return {ok=false}
	return MassInventory.evaluate_reference(reference,PackedFloat64Array([maxf(0.0,fuel)]))

static func point(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	var prop: Dictionary=owner.aircraft.model.propulsion
	var install: Dictionary=prop.glow
	var state: Dictionary=unpack(values,install)
	if state.is_empty(): return {ok=false}
	# Negative fuel is the left-limit continuation used only by the bounded exhaustion solver.
	if state.fuel_kg<0.0: state.fuel_kg=1e-30
	if _injected_cut(owner):
		state=Life.cut(state).state
	elif not owner.engine_running: state.running=false
	var air: Dictionary=owner.air_data(body,time_s)
	var ambient: Dictionary=_environment(owner,body)
	if not ambient.get("ok",false): return {ok=false}
	var density: float=ambient.rho_kgm3
	# The state velocity is at the fixed initial wet-CG datum. Apply the same
	# hub lever arm used by the external thrust moment to local inflow. Wind is
	# locally uniform here; this is not a disk-resolved crossflow/wake model.
	var hub_air: PackedFloat64Array=Propulsion.hub_air_velocity(body,air.v_air,prop.offset)
	var local_cooling: float=M.norm(hub_air)
	var rpm: float=maxf(0.0,values[0])
	# Mean propwash contributes local cooling at idle; installation coefficient remains estimated.
	var identity_matches: bool=owner.get_meta(EVALUATOR_IDENTITY_META,{})==install.identity
	var propeller_evaluator: Variant=owner.get_meta(PROPELLER_EVALUATOR_META,null)
	var load: Dictionary
	if propeller_evaluator is Blade.PreparedEvaluator and identity_matches:
		load=Blade.evaluate_prepared(propeller_evaluator,rpm,M.dot(hub_air,prop.axis),density)
	else:
		load=Blade.evaluate(rpm,M.dot(hub_air,prop.axis),density,install.propeller)
	if not load.ok: return {ok=false}
	local_cooling += M.sqrt_(maxf(0.0,load.thrust_n)/(2.0*density*PI*prop.diameter*prop.diameter/4.0))
	# NITRO-05: the feed pressure needs this stage's apparent gravity, so an installation with a fuel_feed block
	# evaluates the airframe loads first (evaluate() then reuses them).
	var feed_factor: float=1.0
	var airframe: Dictionary={}
	var feed: Dictionary={}
	var feed_mass: Dictionary={}
	if install.has("fuel_feed"):
		airframe=_airframe(owner,body,values,air,hub_air,rpm,load,density)
		if airframe.is_empty(): return {ok=false}
		feed_mass=properties(owner,values[1])
		if not feed_mass.ok: return {ok=false}
	var evaluator: Variant=owner.get_meta(EVALUATOR_META,null)
	var evaluation: Dictionary
	if install.has("fuel_feed"):
		var tank_arm: PackedFloat64Array=M.sub(install.tank_position,feed_mass.cg_body_m)
		var omega: PackedFloat64Array=body.slice(RB.RATE,RB.RATE+3)
		var solve: Dictionary=FuelFeed.solve_factor(func(candidate_factor: float) -> Dictionary:
			var candidate_evaluation: Dictionary=_lifecycle_evaluate(install,state,rpm,local_cooling,ambient,
				values[12],candidate_factor,evaluator,identity_matches,owner)
			if not candidate_evaluation.get("ok",false): return {ok=false}
			var candidate_coupling: Dictionary=_stage_coupling(owner,body,values,install,state,
				candidate_evaluation.source,load,airframe,feed_mass,ambient)
			if not candidate_coupling.get("ok",false): return {ok=false}
			var candidate_feed: Dictionary=FuelFeed.evaluate(install.fuel_feed,airframe.external.slice(0,3),
				feed_mass.mass_kg,state.fuel_kg,install.capacity_fuel_kg,install.unusable_fuel_kg,
				state.air_fraction,rpm,install.tank_position,install.tank_size,owner.sim.gravity,
				tank_arm,candidate_coupling.alpha_body,omega)
			if not candidate_feed.get("ok",false): return {ok=false}
			return {ok=true,target_factor=float(candidate_feed.factor),evaluation=candidate_evaluation,
				coupling=candidate_coupling,feed=candidate_feed}
		,1.0)
		if not solve.get("ok",false): return {ok=false,message=str(solve.get("message","fuel feed solve failed"))}
		var solved: Dictionary=solve.payload
		feed_factor=float(solve.factor)
		evaluation=solved.evaluation
		feed=solved.feed
		evaluation.fuel_feed_solver={factor=feed_factor,residual=float(solve.residual),
			evaluations=int(solve.evaluations),iterations=int(solve.iterations)}
	else:
		evaluation=_lifecycle_evaluate(install,state,rpm,local_cooling,ambient,values[12],feed_factor,
			evaluator,identity_matches,owner)
	if not evaluation.ok: return evaluation
	evaluation.air=air
	evaluation.environment=ambient
	evaluation.hub_air_velocity_body_m_s=hub_air
	evaluation.propeller=load
	evaluation.state=state
	if not airframe.is_empty():
		evaluation.airframe=airframe
		evaluation.fuel_feed=feed
		evaluation.mass=feed_mass
	return evaluation


static func _lifecycle_evaluate(install: Dictionary, state: Dictionary, rpm: float, local_cooling: float,
		ambient: Dictionary, mixture: float, feed_factor: float, evaluator: Variant,
		identity_matches: bool, owner: Node) -> Dictionary:
	var dry_density: float=1.225*float(ambient.engine_charge_ratio)
	var ambient_temperature: float=float(ambient.get("temperature_k",288.15))
	if evaluator is Life.PreparedEvaluator and identity_matches:
		return Life.evaluate_prepared(evaluator,state,rpm,_throttle(owner),mixture,dry_density,
			ambient_temperature,local_cooling,feed_factor,install.unusable_fuel_kg)
	# Standalone fixtures may run before initialization; a failed reload can restore a different installation.
	return Life.evaluate(install.profile,install.settings,state,rpm,_throttle(owner),mixture,dry_density,
		ambient_temperature,local_cooling,feed_factor,install.unusable_fuel_kg)


## Exact same-stage engine/rotor/rigid-body response, shared by feed closure and the accepted derivative.
static func _stage_coupling(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array,
		install: Dictionary, state: Dictionary, source: Dictionary, load: Dictionary,
		airframe: Dictionary, mass: Dictionary, ambient: Dictionary) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var prop: Dictionary=model.propulsion
	var external: PackedFloat64Array=airframe.external
	var force: PackedFloat64Array=external.slice(0,3)
	var torque: PackedFloat64Array=M.sub(external.slice(3,6),M.cross(mass.cg_body_m,force))
	var w: PackedFloat64Array=body.slice(RB.RATE,RB.RATE+3)
	var drive: float=float(source.shaft_torque_nm)
	var load_torque: float=float(load.torque_nm)
	var locked: bool=false
	if values[0]<=0.0:
		# Static friction holds a stopped crank while the propeller can break it away in airflow.
		var coast: Dictionary=Source.evaluate(install.profile,0.001,state.air_fraction,values[12],
			1.225*float(ambient.engine_charge_ratio),false)
		if not coast.get("ok",false): return {ok=false}
		var friction: float=-float(coast.shaft_torque_nm)
		var alpha_stopped: PackedFloat64Array=RB.inertia_mul(mass.inverse,
			M.sub(torque,M.cross(w,RB.inertia_mul(mass.inertia,w))))
		var demand: float=-load_torque-float(prop.rotor_inertia)*M.dot(prop.axis,alpha_stopped)
		if values[0]<0.0:
			drive=-friction # Moving left limit, never committed.
		elif demand < -friction:
			return {ok=false} # Reverse rotation exceeds static hold and is outside this installation's domain.
		elif demand<=friction:
			locked=true
			drive=load_torque+float(prop.rotor_inertia)*M.dot(prop.axis,alpha_stopped)
		else:
			drive=-friction
	var rpm: float=maxf(0.0,values[0])
	var response: Dictionary=Coupling.response(w,torque,mass.inertia,mass.inverse,prop.axis,
		float(prop.rotor_inertia),rpm*TAU/60.0,drive-load_torque)
	if not response.get("ok",false): return {ok=false}
	if locked:
		response.spin_acceleration=0.0
		response.reaction=PackedFloat64Array([0.0,0.0,0.0])
	var moment: PackedFloat64Array=M.add(torque,response.reaction)
	var rotor: PackedFloat64Array=M.scale(prop.axis,float(prop.rotor_inertia)*rpm*TAU/60.0)
	var body_derivative: PackedFloat64Array=FixedDatumBody.derivative(body,mass,force,moment,
		owner.sim.gravity,rotor)
	if body_derivative.size()!=RB.SIZE: return {ok=false}
	var alpha_body: PackedFloat64Array=body_derivative.slice(RB.RATE,RB.RATE+3)
	return {ok=true,force=force,torque_cm=torque,moment_cm=moment,response=response,
		rotor_momentum=rotor,body_derivative=body_derivative,alpha_body=alpha_body,
		spin_acceleration=float(response.spin_acceleration),
		locked=locked}


## Aerodynamic, propeller and ground loads on the airframe for one stage: {external (body force and moment about
## the datum), ground (the ground evaluation, for its wheel derivatives)}, or {} when the ground refuses the stage.
static func _airframe(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array, air: Dictionary,
		hub_air: PackedFloat64Array, rpm: float, load: Dictionary, density: float) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var prop: Dictionary=model.propulsion
	var lag: int=owner.downwash_index()
	var propeller_loads: PackedFloat64Array=Propulsion.loads_from_thrust_torque(hub_air,rpm,prop,
		density,load.thrust_n,load.torque_nm)
	var external: PackedFloat64Array=Dynamics.loads_from_air(body,model,owner._deflections(owner.sim.aux),rpm,
		density,air,owner.sim.aux[lag] if lag>=0 else NAN,PackedFloat64Array(),owner._ground_up(body),propeller_loads)
	var ground: Dictionary=owner._ground_evaluation(body,owner.sim.aux,values,air)
	if not ground.get("ok",false): return {}
	for i in ground.loads.size(): external[i]+=ground.loads[i]
	return {external=external,ground=ground}

static func evaluate(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float, owner: Node) -> Dictionary:
	if values.size()!=SIZE+owner.wheel_count(): return {}
	var result: Dictionary=point(owner,body,values,time_s)
	if not result.ok: return {}
	var mass: Dictionary=result.get("mass",{})
	if mass.is_empty(): mass=properties(owner,values[1])
	if not mass.ok: return {}
	var rpm: float=maxf(0.0,values[0])
	var airframe: Dictionary=result.get("airframe",{})
	if airframe.is_empty():
		airframe=_airframe(owner,body,values,result.air,result.hub_air_velocity_body_m_s,rpm,result.propeller,result.environment.rho_kgm3)
	if airframe.is_empty(): return {}
	var ground: Dictionary=airframe.ground
	var coupling: Dictionary=_stage_coupling(owner,body,values,owner.aircraft.model.propulsion.glow,
		result.state,result.source,
		result.propeller,airframe,mass,result.environment)
	if not coupling.get("ok",false): return {}
	var external: PackedFloat64Array=airframe.external
	var response: Dictionary=coupling.response
	var derivative:=PackedFloat64Array()
	derivative.resize(SIZE)
	derivative[0]=coupling.spin_acceleration*60.0/TAU
	for i in 6: derivative[i+1]=result.rates[Life.CONTINUOUS_KEYS[i]]
	derivative[13]=result.source.brake_power_w
	derivative[14]=result.propeller.shaft_power_w
	derivative[15]=result.propeller.thrust_power_w
	derivative[16]=result.source.chemical_power_w
	derivative.append_array(ground.derivative)
	for i in 3: external[i+3]+=response.reaction[i]
	return {loads=external,derivative=derivative,rotor_momentum=coupling.rotor_momentum,
		body_derivative=coupling.body_derivative}

static func project_stop(values: PackedFloat64Array,index: int,owner: Node) -> PackedFloat64Array:
	var out: PackedFloat64Array=values.duplicate()
	var mass: Dictionary=properties(owner,values[RB.SIZE+1])
	if not mass.ok: return PackedFloat64Array([NAN])
	var prop: Dictionary=owner.aircraft.model.propulsion
	var correction: PackedFloat64Array=RB.inertia_mul(mass.inverse,M.scale(prop.axis,prop.rotor_inertia*out[index]*TAU/60.0))
	# Preserve linear momentum as the body rates change about the fixed datum.
	var velocity_correction: PackedFloat64Array=M.cross(correction,mass.cg_body_m)
	for i in 3:
		out[RB.RATE+i]+=correction[i]
		out[RB.VEL+i]-=velocity_correction[i]
	out[index]=0.0
	return out

## SF-04: the accepted result is {state, events}: the bounded rotor-stop and tank-exhaustion boundaries, then
## a `glow_stopped` lifecycle transition with its reason when a running engine stops within the tick.
static func step(combined: PackedFloat64Array,time_s: float,dt: float,derivative: Callable,first: PackedFloat64Array,owner: Node) -> Variant:
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var fuel_index: int=RB.SIZE+1
	if combined.size()<SIZE+RB.SIZE or combined.size()<=fuel_index:
		return PackedFloat64Array([NAN])
	# Boundary.advance is a zero-floor resource integrator. Shift the same physical
	# fuel coordinate by the unusable residue so its exact boundary is still zero.
	# If a restored/start state is already below the residue, pin the effective floor
	# to that amount: it is inert fuel and must neither burn nor be silently raised.
	var fuel_floor: float=minf(maxf(0.0,install.unusable_fuel_kg),combined[fuel_index])
	var shifted: PackedFloat64Array=combined.duplicate()
	shifted[fuel_index]-=fuel_floor
	var floor_derivative: Callable=func(values: PackedFloat64Array,at: float) -> PackedFloat64Array:
		var physical: PackedFloat64Array=values.duplicate()
		physical[fuel_index]+=fuel_floor
		if values[fuel_index]<0.0:
			# Connected left-limit query used only while localizing exhaustion.
			physical[fuel_index]=fuel_floor+1.0e-30
		return derivative.call(physical,at)
	var floor_projection: Callable=func(values: PackedFloat64Array,index: int) -> PackedFloat64Array:
		var physical: PackedFloat64Array=values.duplicate()
		physical[fuel_index]+=fuel_floor
		var projected: PackedFloat64Array=project_stop(physical,index,owner)
		if projected.size()!=values.size(): return projected
		projected[fuel_index]-=fuel_floor
		return projected
	var bounded: Dictionary=Boundary.advance(shifted,time_s,dt,floor_derivative,first,
		RB.SIZE,fuel_index,floor_projection)
	if not bounded.ok: return PackedFloat64Array([NAN])
	bounded.state[fuel_index]+=fuel_floor
	var values: PackedFloat64Array=bounded.state.slice(RB.SIZE)
	var before: Dictionary=unpack(combined.slice(RB.SIZE),install)
	var was_running: bool=bool(before.running)
	if not owner.engine_running:
		before=Life.cut(before).state
	var candidate: Dictionary=unpack(values,install)
	if _injected_cut(owner):
		# Commit the same lifecycle discontinuity as the existing fuel cut, without
		# changing live packed state before the whole simulation tick is accepted.
		before=Life.cut(before).state
		candidate=Life.cut(candidate).state
	var endpoint: Dictionary=point(owner,bounded.state.slice(0,RB.SIZE),values,time_s+dt)
	if not endpoint.ok: return PackedFloat64Array([NAN])
	var evaluator: Variant=owner.get_meta(EVALUATOR_META,null)
	var accepted: Dictionary
	if evaluator is Life.PreparedEvaluator and owner.get_meta(EVALUATOR_IDENTITY_META,{})==install.identity:
		accepted=Life.accepted_prepared(evaluator,before,candidate,dt,combined[RB.SIZE],values[0],
			endpoint.firing_fraction,install.unusable_fuel_kg)
	else:
		accepted=Life.accepted(install.profile,install.settings,before,candidate,dt,combined[RB.SIZE],
			values[0],endpoint.firing_fraction,install.unusable_fuel_kg)
	if not accepted.ok: return PackedFloat64Array([NAN])
	values=put_state(values,accepted.state)
	var out: PackedFloat64Array=bounded.state.slice(0,RB.SIZE)
	out.append_array(values)
	var events: Array[Dictionary]=[]
	var stopped_time: float=time_s+dt
	for event: Dictionary in bounded.events:
		var reported: Dictionary=event.duplicate(true)
		if reported.get("type","")=="battery_exhausted":
			reported.type="fuel_exhausted"
			if reported.has("charge_residual_c"):
				reported.fuel_residual_kg=reported.charge_residual_c
				reported.erase("charge_residual_c")
			stopped_time=float(reported.get("time_s",stopped_time))
		events.append(reported)
	if was_running and not bool(accepted.state.running):
		if str(accepted.state.get("stop_reason",""))=="fuel_exhausted" and before.fuel_kg<=install.unusable_fuel_kg:
			stopped_time=time_s
		events.append({"type":"glow_stopped","reason":str(accepted.state.get("stop_reason","")),"time_s":stopped_time})
	return {"state":out,"events":events}

static func telemetry(owner: Node) -> Dictionary:
	var values: PackedFloat64Array=owner.sim.continuous
	if values.size()<SIZE: return {ok=false}
	var result: Dictionary=point(owner,owner.sim.state,values,owner.sim.time())
	if not result.ok: return result
	var out: Dictionary=result.telemetry.duplicate(true)
	out.merge(result.state,true)
	out.merge(result.source,true)
	out.ok=true
	if result.has("fuel_feed"): out.fuel_feed=result.fuel_feed.duplicate(true)
	if result.has("fuel_feed_solver"): out.fuel_feed_solver=result.fuel_feed_solver.duplicate(true)
	out.rpm=values[0]
	out.running=result.state.running and result.state.fuel_kg>float(
		owner.aircraft.model.propulsion.glow.get("unusable_fuel_kg",0.0))
	out.blade_count=owner.aircraft.model.propulsion.glow.propeller.blades
	out.firing_fraction=result.firing_fraction
	out.propeller=result.propeller
	out.hub_air_velocity_body_m_s=result.hub_air_velocity_body_m_s
	out.mass_properties=properties(owner,values[1])
	# FUEL-01b: the installed blend's own density (profile.gd), so displays never assume a fixed g/mL.
	out.fuel_density_kg_m3=float(owner.aircraft.model.propulsion.glow.profile.fuel.density_kg_m3)
	out.fuel_volume_m3=maxf(0.0,values[1])/out.fuel_density_kg_m3
	out.shaft_work_j=values[13]
	out.propeller_work_j=values[14]
	out.thrust_work_j=values[15]
	out.recommended_max_rpm=minf(owner.aircraft.model.propulsion.glow.profile.operation.recommended_max_rpm,owner.aircraft.model.propulsion.glow.propeller.max_rpm)
	out.above_recommended_rpm=values[0]>out.recommended_max_rpm
	# Source excitation is an observer, never a sampled load on the aircraft. No
	# endpoint shaft acceleration is stored: report constant-speed order estimates
	# explicitly rather than inventing an acceleration or mount transfer function.
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var prepared_vibration: Dictionary=owner.get_meta(VIBRATION_EVALUATOR_META,{})
	if owner.get_meta(EVALUATOR_IDENTITY_META,{})!=install.identity or prepared_vibration.is_empty():
		prepared_vibration=Vibration.prepare(install.profile)
	out.source_vibration=Vibration.evaluate(prepared_vibration,values[6]*TAU,values[0]*TAU/60.0,
		0.0,result.firing_fraction if out.running else 0.0)
	return out
