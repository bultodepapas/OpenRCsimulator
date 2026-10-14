## NITRO flight adapter. All evolving values live in Simulation.continuous.
## Layout: RPM, six lifecycle values, running/reason/opportunities/fires/accumulator,
## mixture command, then shaft/propeller/thrust/chemical work (J).
extends RefCounted
const Life := preload("res://physics/glow/lifecycle.gd")
const Vibration := preload("res://physics/glow/vibration.gd")
const Source := preload("res://physics/glow/source.gd")
const FuelMass := preload("res://physics/glow/fuel_mass.gd")
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

static func valid(values: PackedFloat64Array, install: Dictionary) -> bool:
	var state: Dictionary=unpack(values,install)
	if state.is_empty() or Life.pack_state(state).size()!=6: return false
	if values[1]<0.0 or values[5]<0.0 or values[3]<0.0 or values[3]>1.0 or values[4]<0.0 or values[4]>1.0: return false
	if values[0]<0.0 or values[0]>install.profile.operation.max_rpm or values[1]>install.initial_fuel_kg or values[12]<0.0 or values[12]>2.8: return false
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

static func initial(owner: Node, aux: PackedFloat64Array) -> PackedFloat64Array:
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
	var made: Dictionary=Life.create(install.profile,install.settings,install.initial_fuel_kg,
		install.initial_temperature_k,aux[0],owner.engine_running)
	if not made.ok: return PackedFloat64Array([NAN])
	var state: Dictionary=made.state
	state.servo_fraction=owner.sim.inputs[3]
	state.air_fraction=install.settings.idle_admission+(1.0-install.settings.idle_admission)*state.servo_fraction
	var point: Dictionary=Source.evaluate(install.profile,aux[0],state.air_fraction,install.profile.operation.nominal_mixture,
		1.225*owner.engine_charge_ratio(),owner.engine_running)
	if not point.ok: return PackedFloat64Array([NAN])
	state.fuel_transport_kg_s=point.delivered_fuel_kg_s
	var out:=PackedFloat64Array()
	out.resize(SIZE)
	out[0]=aux[0]
	out[12]=install.profile.operation.nominal_mixture
	return put_state(out,state)

static func properties(owner: Node, fuel: float) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var install: Dictionary=model.propulsion.glow
	return FuelMass.evaluate(model.mass_kg,model.inertia,install.initial_fuel_kg,maxf(0.0,fuel),install.tank_position,install.tank_size)

static func point(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	var prop: Dictionary=owner.aircraft.model.propulsion
	var install: Dictionary=prop.glow
	var state: Dictionary=unpack(values,install)
	if state.is_empty(): return {ok=false}
	# Negative fuel is the left-limit continuation used only by the bounded exhaustion solver.
	if state.fuel_kg<0.0: state.fuel_kg=1e-30
	if not owner.engine_running: state.running=false
	var air: Dictionary=owner.air_data(body,time_s)
	var ambient: Dictionary=owner.atmosphere_configuration()
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
		load=Blade.evaluate_prepared(propeller_evaluator,rpm,M.dot(hub_air,prop.axis),owner.air_density())
	else:
		load=Blade.evaluate(rpm,M.dot(hub_air,prop.axis),owner.air_density(),install.propeller)
	if not load.ok: return {ok=false}
	local_cooling += M.sqrt_(maxf(0.0,load.thrust_n)/(2.0*owner.air_density()*PI*prop.diameter*prop.diameter/4.0))
	# NITRO-05: the feed pressure needs this stage's apparent gravity, so an installation with a fuel_feed block
	# evaluates the airframe loads first (evaluate() then reuses them).
	var feed_factor: float=1.0
	var airframe: Dictionary={}
	var feed: Dictionary={}
	if install.has("fuel_feed"):
		airframe=_airframe(owner,body,values,air,hub_air,rpm,load)
		if airframe.is_empty(): return {ok=false}
		var mass: Dictionary=properties(owner,values[1])
		if not mass.ok: return {ok=false}
		feed=FuelFeed.evaluate(install.fuel_feed,airframe.external.slice(0,3),mass.mass_kg,
			clampf(state.fuel_kg/install.initial_fuel_kg,0.0,1.0),clampf(state.air_fraction,0.0,1.0),rpm,
			install.tank_position,install.tank_size,owner.sim.gravity)
		feed_factor=feed.factor
	var evaluator: Variant=owner.get_meta(EVALUATOR_META,null)
	var evaluation: Dictionary
	if evaluator is Life.PreparedEvaluator and identity_matches:
		evaluation=Life.evaluate_prepared(evaluator,state,rpm,owner.sim.inputs[3],values[12],
			1.225*owner.engine_charge_ratio(),float(ambient.get("temperature_k",288.15)),local_cooling,feed_factor)
	else:
		# Standalone fixtures may run before initialization; a failed reload can
		# restore a different installation. Both use the fully validated path.
		evaluation=Life.evaluate(install.profile,install.settings,state,rpm,owner.sim.inputs[3],values[12],
			1.225*owner.engine_charge_ratio(),float(ambient.get("temperature_k",288.15)),local_cooling,feed_factor)
	if not evaluation.ok: return evaluation
	evaluation.air=air
	evaluation.hub_air_velocity_body_m_s=hub_air
	evaluation.propeller=load
	evaluation.state=state
	if not airframe.is_empty():
		evaluation.airframe=airframe
		evaluation.fuel_feed=feed
	return evaluation


## Aerodynamic, propeller and ground loads on the airframe for one stage: {external (body force and moment about
## the datum), ground (the ground evaluation, for its wheel derivatives)}, or {} when the ground refuses the stage.
static func _airframe(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array, air: Dictionary,
		hub_air: PackedFloat64Array, rpm: float, load: Dictionary) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var prop: Dictionary=model.propulsion
	var lag: int=owner.downwash_index()
	var propeller_loads: PackedFloat64Array=Propulsion.loads_from_thrust_torque(hub_air,rpm,prop,
		owner.air_density(),load.thrust_n,load.torque_nm)
	var external: PackedFloat64Array=Dynamics.loads_from_air(body,model,owner._deflections(owner.sim.aux),rpm,
		owner.air_density(),air,owner.sim.aux[lag] if lag>=0 else NAN,PackedFloat64Array(),owner._ground_up(body),propeller_loads)
	var ground: Dictionary=owner._ground_evaluation(body,owner.sim.aux,values)
	if not ground.get("ok",false): return {}
	for i in ground.loads.size(): external[i]+=ground.loads[i]
	return {external=external,ground=ground}

static func evaluate(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float, owner: Node) -> Dictionary:
	if values.size()!=SIZE+owner.wheel_count(): return {}
	var result: Dictionary=point(owner,body,values,time_s)
	if not result.ok: return {}
	var model: Dictionary=owner.aircraft.model
	var prop: Dictionary=model.propulsion
	var mass: Dictionary=properties(owner,values[1])
	if not mass.ok: return {}
	var rpm: float=maxf(0.0,values[0])
	var airframe: Dictionary=result.get("airframe",{})
	if airframe.is_empty():
		airframe=_airframe(owner,body,values,result.air,result.hub_air_velocity_body_m_s,rpm,result.propeller)
	if airframe.is_empty(): return {}
	var external: PackedFloat64Array=airframe.external
	var ground: Dictionary=airframe.ground
	var force: PackedFloat64Array=external.slice(0,3)
	var torque: PackedFloat64Array=M.sub(external.slice(3,6),M.cross(mass.cg_body_m,force))
	var w: PackedFloat64Array=body.slice(RB.RATE,RB.RATE+3)
	var drive: float=result.source.shaft_torque_nm
	var load: float=result.propeller.torque_nm
	var locked: bool=false
	if values[0]<=0.0:
		# Static friction holds a stopped crank while the propeller can break it away in airflow.
		var coast: Dictionary=Source.evaluate(prop.glow.profile,0.001,result.state.air_fraction,values[12],1.225*owner.engine_charge_ratio(),false)
		if not coast.ok: return {}
		var friction: float=-coast.shaft_torque_nm
		var alpha: PackedFloat64Array=RB.inertia_mul(mass.inverse,M.sub(torque,M.cross(w,RB.inertia_mul(mass.inertia,w))))
		var demand: float=-load-prop.rotor_inertia*M.dot(prop.axis,alpha)
		if values[0]<0.0:
			drive=-friction # moving left limit, never committed
		elif demand < -friction:
			return {} # reverse rotation exceeds static hold and is outside this installation's domain
		elif demand<=friction:
			locked=true
			drive=load+prop.rotor_inertia*M.dot(prop.axis,alpha)
		else: drive=-friction
	var response: Dictionary=Coupling.response(w,torque,mass.inertia,mass.inverse,prop.axis,prop.rotor_inertia,
		rpm*TAU/60.0,drive-load)
	if not response.ok: return {}
	if locked:
		response.spin_acceleration=0.0
		response.reaction=PackedFloat64Array([0.,0.,0.])
	var moment: PackedFloat64Array=M.add(torque,response.reaction)
	var rotor: PackedFloat64Array=M.scale(prop.axis,prop.rotor_inertia*rpm*TAU/60.0)
	var body_rate: PackedFloat64Array=FuelMass.datum_derivative(body,mass,force,moment,owner.sim.gravity,rotor)
	var derivative:=PackedFloat64Array()
	derivative.resize(SIZE)
	derivative[0]=response.spin_acceleration*60.0/TAU
	for i in 6: derivative[i+1]=result.rates[Life.CONTINUOUS_KEYS[i]]
	derivative[13]=result.source.brake_power_w
	derivative[14]=result.propeller.shaft_power_w
	derivative[15]=result.propeller.thrust_power_w
	derivative[16]=result.source.chemical_power_w
	derivative.append_array(ground.derivative)
	for i in 3: external[i+3]+=response.reaction[i]
	return {loads=external,derivative=derivative,rotor_momentum=rotor,body_derivative=body_rate}

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

static func step(combined: PackedFloat64Array,time_s: float,dt: float,derivative: Callable,first: PackedFloat64Array,owner: Node) -> PackedFloat64Array:
	var bounded: Dictionary=Boundary.advance(combined,time_s,dt,derivative,first,RB.SIZE,RB.SIZE+1,project_stop.bind(owner))
	if not bounded.ok: return PackedFloat64Array([NAN])
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var values: PackedFloat64Array=bounded.state.slice(RB.SIZE)
	var before: Dictionary=unpack(combined.slice(RB.SIZE),install)
	if not owner.engine_running:
		before=Life.cut(before).state
	var candidate: Dictionary=unpack(values,install)
	var endpoint: Dictionary=point(owner,bounded.state.slice(0,RB.SIZE),values,time_s+dt)
	if not endpoint.ok: return PackedFloat64Array([NAN])
	var evaluator: Variant=owner.get_meta(EVALUATOR_META,null)
	var accepted: Dictionary
	if evaluator is Life.PreparedEvaluator and owner.get_meta(EVALUATOR_IDENTITY_META,{})==install.identity:
		accepted=Life.accepted_prepared(evaluator,before,candidate,dt,combined[RB.SIZE],values[0],endpoint.firing_fraction)
	else:
		accepted=Life.accepted(install.profile,install.settings,before,candidate,dt,combined[RB.SIZE],values[0],endpoint.firing_fraction)
	if not accepted.ok: return PackedFloat64Array([NAN])
	values=put_state(values,accepted.state)
	var out: PackedFloat64Array=bounded.state.slice(0,RB.SIZE)
	out.append_array(values)
	return out

static func telemetry(owner: Node) -> Dictionary:
	var values: PackedFloat64Array=owner.sim.continuous
	if values.size()<SIZE: return {ok=false}
	var result: Dictionary=point(owner,owner.sim.state,values,owner.sim.time())
	if not result.ok: return result
	var out: Dictionary=result.telemetry.duplicate(true)
	out.merge(result.state,true)
	out.merge(result.source,true)
	out.ok=true
	if result.has("fuel_feed"): out.fuel_feed=result.fuel_feed.duplicate()
	out.rpm=values[0]
	out.running=result.state.running and result.state.fuel_kg>0.0
	out.blade_count=owner.aircraft.model.propulsion.glow.propeller.blades
	out.firing_fraction=result.firing_fraction
	out.propeller=result.propeller
	out.hub_air_velocity_body_m_s=result.hub_air_velocity_body_m_s
	out.mass_properties=properties(owner,values[1])
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
