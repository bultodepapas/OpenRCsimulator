## NITRO flight adapter. All evolving values live in Simulation.continuous.
## Layout: RPM, six lifecycle values, running/reason/opportunities/fires/accumulator,
## mixture, shaft/propeller/thrust/chemical work, separate line fuel (kg), serialized source mode.
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
const ResourceStep := preload("res://physics/resource_event_step.gd")
const FuelFeed := preload("res://physics/glow/fuel_feed.gd")
const Carb := preload("res://physics/glow/carburetor.gd")
const LEGACY_SIZE := 17
const LINE_FUEL_INDEX := 17
const SOURCE_MODE_INDEX := 18
const SIZE := 19
const MODE_STARVED := 0
const MODE_MAIN_TANK := 1
const MODE_FEED_LINE := 2
## Fixed-point passes and tolerance for the initial needled fuel-transport seed (fuel_feed installations).
const SEED_PASSES := 8
const SEED_TOLERANCE := 1.0e-15
const LAW := "glow-mean-cycle-carburettor-v4"
const CONTINUOUS_LAYOUT: String = "rpm; fuel kg, temperature K, servo, throttle opening, fuel transport kg/s, crank revolutions; running, reason, opportunities, fires, firing accumulator; mixture; shaft/prop/thrust/chemical work J; feed-line liquid mass kg; fuel source mode (0 starved, 1 main tank, 2 pre-primed line)"
const REASONS := ["", "not_started", "cut", "stall", "fuel_exhausted", "overheat", "fuel_starved"]
const EVALUATOR_META := &"_glow_prepared_evaluator"
const PROPELLER_EVALUATOR_META := &"_glow_prepared_propeller"
const VIBRATION_EVALUATOR_META := &"_glow_source_vibration"
const EVALUATOR_IDENTITY_META := &"_glow_prepared_identity"

## NITRO-06: the charge per cycle the carburettor admits at this barrel opening and speed, relative to wide open.
static func admission_at(install: Dictionary, opening: float, rpm: float) -> float:
	return Carb.admission(opening, rpm, Source.breathing(install.profile, rpm),
		float(install.profile.parameters.displacement_m3), float(install.profile.identity.cycle_revolutions),
		float(install.throttle_capacity_m3_s))

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
	if values.size() < SIZE:
		return false
	var state: Dictionary=unpack(values,install)
	if state.is_empty() or Life.pack_state(state).size()!=6: return false
	if values[1]<0.0 or values[5]<0.0 or values[3]<0.0 or values[3]>1.0 or values[4]<0.0 or values[4]>1.0: return false
	if values[0]<0.0 or values[0]>install.profile.operation.max_rpm or values[1]>install.total_capacity_kg or values[12]<0.0 or values[12]>2.8: return false
	var line: Dictionary=install.get("feed_line",{})
	var line_fuel: float=values[LINE_FUEL_INDEX]
	var main_fuel: float=values[1]-line_fuel
	if not is_finite(line_fuel) or line_fuel<0.0 or line_fuel>float(line.get("capacity_kg",0.0)) \
			or main_fuel<0.0 or main_fuel>install.capacity_fuel_kg or values[SOURCE_MODE_INDEX]!=floor(values[SOURCE_MODE_INDEX]) \
			or values[SOURCE_MODE_INDEX]<MODE_STARVED or values[SOURCE_MODE_INDEX]>MODE_FEED_LINE: return false
	# Accepted states retain the main tank's unusable residue in every source mode.
	# Subtracting a separately stored line can lose a few float64 rounding steps.
	var residue_roundoff: float=FuelMass.CAPACITY_ROUNDING_EPSILONS*FuelMass.FLOAT64_EPSILON \
		* maxf(absf(values[1]),absf(line_fuel)) if not line.is_empty() else 0.0
	if main_fuel<install.unusable_fuel_kg and install.unusable_fuel_kg-main_fuel>residue_roundoff: return false
	if line.is_empty() and (line_fuel!=0.0 or values[SOURCE_MODE_INDEX]==MODE_FEED_LINE): return false
	if values[SOURCE_MODE_INDEX]==MODE_FEED_LINE and line_fuel<=0.0: return false
	var source_mode: int=int(values[SOURCE_MODE_INDEX])
	if source_mode==MODE_MAIN_TANK and main_fuel<=install.unusable_fuel_kg: return false
	if source_mode==MODE_STARVED and bool(state.running): return false
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
	# FUEL-07: selected fill applies only to the main tank. An authored feed line is separately
	# pre-primed to its reference mass and is never silently scaled by the tank fill selector.
	var start_main: float=owner.start_fuel_kg() if owner.has_method("start_fuel_kg") else install.reference_fuel_kg
	var line: Dictionary=install.get("feed_line",{})
	var start_line: float=float(line.get("reference_mass_kg",0.0))
	var has_line: bool=not line.is_empty()
	var lifecycle_floor: float=0.0 if has_line else install.unusable_fuel_kg
	var made: Dictionary=Life.create(install.profile,install.settings,start_main+start_line,
		install.initial_temperature_k,aux[0],owner.engine_running,lifecycle_floor)
	if not made.ok: return PackedFloat64Array([NAN])
	var state: Dictionary=made.state
	state.servo_fraction=_throttle(owner)
	state.air_fraction=Carb.opening(state.servo_fraction,float(install.throttle_idle_offset),float(install.throttle_travel_exponent))
	var ambient: Dictionary = _environment(owner, body)
	if not ambient.get("ok", false): return PackedFloat64Array([NAN])
	var point: Dictionary=Source.evaluate(install.profile,aux[0],admission_at(install,state.air_fraction,aux[0]),install.profile.operation.nominal_mixture,
		1.225*float(ambient.engine_charge_ratio),owner.engine_running)
	if not point.ok: return PackedFloat64Array([NAN])
	state.fuel_transport_kg_s=point.delivered_fuel_kg_s
	var out:=PackedFloat64Array()
	out.resize(SIZE)
	out[0]=aux[0]
	out[LINE_FUEL_INDEX]=start_line
	var mode: int=MODE_MAIN_TANK if start_main>install.unusable_fuel_kg else MODE_STARVED
	if has_line and mode==MODE_STARVED and start_line>0.0:
		mode=MODE_FEED_LINE
	elif mode==MODE_STARVED and bool(state.running):
		state=_stop_for_fuel(state,"fuel_exhausted")
	out[SOURCE_MODE_INDEX]=float(mode)
	out[12]=install.profile.operation.nominal_mixture
	if install.has("fuel_feed"):
		# Seed transport from the actual start loads and apparent gravity. The feed
		# factor can differ from the level-flight value used by Source.evaluate above.
		var stage_values: PackedFloat64Array=put_state(out,state)
		for _i in owner.wheel_count(): stage_values.append(0.0)
		var initial_point: Dictionary=point(owner,body,stage_values,0.0)
		if not initial_point.get("ok",false): return PackedFloat64Array([NAN])
		if bool(install.get("has_pickup_position",false)) and mode==MODE_MAIN_TANK \
				and not bool(initial_point.get("fuel_feed",{}).get("pickup_wet",true)):
			if has_line and start_line>0.0:
				mode=MODE_FEED_LINE
			else:
				mode=MODE_STARVED
				if bool(state.running):
					state=_stop_for_fuel(state,"fuel_starved")
			out[SOURCE_MODE_INDEX]=float(mode)
			stage_values=put_state(out,state)
			for _i in owner.wheel_count(): stage_values.append(0.0)
			initial_point=point(owner,body,stage_values,0.0)
			if not initial_point.get("ok",false): return PackedFloat64Array([NAN])
		var telemetry: Dictionary=initial_point.get("telemetry",{})
		var target: float=float(telemetry.get("fuel_target_kg_s",NAN))
		if not is_finite(target) or target<0.0: return PackedFloat64Array([NAN])
		# The needled target itself depends on the transport through the actual mixture, the shaft torque and the
		# apparent gravity at the tank; settle that fixed point (it converges in one or two passes) so the first
		# stage starts with a zero transport rate.
		for _pass in SEED_PASSES:
			state.fuel_transport_kg_s=target
			stage_values=put_state(out,state)
			for _i in owner.wheel_count(): stage_values.append(0.0)
			initial_point=point(owner,body,stage_values,0.0)
			if not initial_point.get("ok",false): return PackedFloat64Array([NAN])
			var settled: float=float(initial_point.get("telemetry",{}).get("fuel_target_kg_s",NAN))
			if not is_finite(settled) or settled<0.0: return PackedFloat64Array([NAN])
			var moved: bool=absf(settled-target)>SEED_TOLERANCE*maxf(1.0,absf(target))
			target=settled
			if not moved: break
		state.fuel_transport_kg_s=target
	return put_state(out,state)

static func properties(owner: Node, fuel: float, line_fuel: float = 0.0) -> Dictionary:
	var model: Dictionary=owner.aircraft.model
	var install: Dictionary=model.propulsion.glow
	# FUEL-04: fixed wet-CG datum, with line and main liquid as separate resources when authored.
	var reference: Dictionary=install.get("mass_reference",{})
	if reference.get("reference_mass_kg",NAN)!=float(model.mass_kg) or reference.get("reference_inertia_kgm2",PackedFloat64Array())!=model.inertia:
		if install.has("feed_line"):
			reference=_prepare_resources(install,model)
		else:
			reference=FuelMass.prepare(model.mass_kg,model.inertia,install.reference_fuel_kg,
				install.tank_position,install.tank_size,install.capacity_fuel_kg,str(install.fuel_tank.id))
		if not reference.get("ok",false): return {ok=false}
	var main_fuel: float=fuel-line_fuel
	if not is_finite(fuel) or not is_finite(line_fuel): return {ok=false}
	if install.has("feed_line"):
		return FuelMass.evaluate_resources(reference,PackedFloat64Array([
			clampf(main_fuel,0.0,install.capacity_fuel_kg),
			clampf(line_fuel,0.0,install.feed_line.capacity_kg)]))
	if absf(line_fuel)>1.0e-15: return {ok=false}
	return MassInventory.evaluate_reference(reference,PackedFloat64Array([clampf(fuel,0.0,install.capacity_fuel_kg)]))


## Session-facing store sample. Accepted values are checked strictly; stage callers use clamped properties only.
static func mass_context(owner: Node, values: PackedFloat64Array) -> Dictionary:
	if values.size()<SIZE: return {ok=false}
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var total: float=values[1]
	var line_fuel: float=values[LINE_FUEL_INDEX]
	var main_fuel: float=total-line_fuel
	var line: Dictionary=install.get("feed_line",{})
	if not valid(values,install) or not is_finite(total) or not is_finite(line_fuel) or total<0.0 or line_fuel<0.0 \
			or line_fuel>float(line.get("capacity_kg",0.0)) or main_fuel<0.0 or main_fuel>install.capacity_fuel_kg \
			or total>install.total_capacity_kg or (line.is_empty() and line_fuel!=0.0):
		return {ok=false}
	var properties_result: Dictionary=properties(owner,total,line_fuel)
	if not properties_result.get("ok",false): return {ok=false}
	var tank: Dictionary=install.fuel_tank.duplicate(true)
	var stores: Array=[tank]
	var remaining: Dictionary={str(tank.id):main_fuel}
	if not line.is_empty():
		var line_store: Dictionary=install.feed_line.sample_store.duplicate(true)
		stores.append(line_store)
		remaining[str(line_store.id)]=line_fuel
	return {ok=true,properties=properties_result,tanks=stores,remaining=remaining,
		main_fuel_kg=main_fuel,line_fuel_kg=line_fuel,total_fuel_kg=total,
		source_mode=int(values[SOURCE_MODE_INDEX])}


static func _prepare_resources(install: Dictionary, model: Dictionary) -> Dictionary:
	if not install.has("feed_line"):
		return FuelMass.prepare(model.mass_kg,model.inertia,install.reference_fuel_kg,
			install.tank_position,install.tank_size,install.capacity_fuel_kg,str(install.fuel_tank.id))
	var line: Dictionary=install.feed_line
	return FuelMass.prepare_resources(model.mass_kg,model.inertia,[
		{id=str(install.fuel_tank.id),reference_mass_kg=install.reference_fuel_kg,
			capacity_mass_kg=install.capacity_fuel_kg,center_body_m=install.tank_position,size_body_m=install.tank_size},
		{id=str(line.liquid_inventory_id),reference_mass_kg=line.reference_mass_kg,
			capacity_mass_kg=line.capacity_kg,center_body_m=line.position,size_body_m=line.size},
	])


static func _stage_mass_context(owner: Node, values: PackedFloat64Array) -> Dictionary:
	if values.size()<SIZE or not is_finite(values[1]) or not is_finite(values[LINE_FUEL_INDEX]):
		return {ok=false}
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var line: Dictionary=install.get("feed_line",{})
	# Preserve the inactive resource across a left-limit boundary trial. In line
	# mode, a slightly negative line value is only the event locator overshoot;
	# subtracting that raw value keeps the main-tank mass constant before clipping.
	var raw_line_fuel: float=values[LINE_FUEL_INDEX]
	var line_fuel: float=clampf(raw_line_fuel,0.0,float(line.get("capacity_kg",0.0)))
	var main_fuel: float=clampf(values[1]-raw_line_fuel,0.0,install.capacity_fuel_kg)
	var total: float=main_fuel+line_fuel
	var properties_result: Dictionary=properties(owner,total,line_fuel)
	if not properties_result.get("ok",false): return {ok=false}
	return {ok=true,properties=properties_result,main_fuel_kg=main_fuel,
		line_fuel_kg=line_fuel,total_fuel_kg=total}


static func _stop_for_fuel(state: Dictionary, reason: String) -> Dictionary:
	var next: Dictionary=state.duplicate(true)
	next.running=false
	next.stop_reason=reason
	next.fuel_transport_kg_s=0.0
	return next


static func _pickup_surface_sample(owner: Node, combined: PackedFloat64Array, time_s: float) -> Dictionary:
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	if not bool(install.get("has_pickup_position",false)) or not install.has("fuel_feed"):
		return {ok=true,defined=false,margin_m=NAN}
	var body: PackedFloat64Array=combined.slice(0,RB.SIZE)
	var values: PackedFloat64Array=combined.slice(RB.SIZE)
	var result: Dictionary=point(owner,body,values,time_s)
	if not result.get("ok",false): return {ok=false,defined=false,margin_m=NAN}
	var feed: Dictionary=result.get("fuel_feed",{})
	if feed.is_empty() or not feed.get("g_eff") is PackedFloat64Array:
		return {ok=true,defined=false,margin_m=NAN}
	var margin: float=FuelFeed.pickup_margin_m(feed.g_eff,float(feed.get("fill_fraction",NAN)),
		install.pickup_position,install.tank_position,install.tank_size)
	return {ok=true,defined=is_finite(margin),margin_m=margin}


static func _transition_source(combined: PackedFloat64Array, owner: Node, mode: int,
		reason: String = "", total_override: float = NAN, line_override: float = NAN) -> PackedFloat64Array:
	var out: PackedFloat64Array=combined.duplicate()
	var values: PackedFloat64Array=out.slice(RB.SIZE)
	if is_finite(total_override): values[1]=total_override
	if is_finite(line_override): values[LINE_FUEL_INDEX]=line_override
	values[SOURCE_MODE_INDEX]=float(mode)
	if not reason.is_empty():
		var install: Dictionary=owner.aircraft.model.propulsion.glow
		var state: Dictionary=unpack(values,install)
		if state.is_empty(): return PackedFloat64Array([NAN])
		values=put_state(values,_stop_for_fuel(state,reason))
	for index: int in values.size(): out[RB.SIZE+index]=values[index]
	return out


static func _resource_events(owner: Node) -> Array:
	var install: Dictionary=owner.aircraft.model.propulsion.glow
	var line: Dictionary=install.get("feed_line",{})
	var events: Array=[]
	events.append({
		id="rotor_stop",type="rotor_stop",sense="falling",surface_unit="rpm",priority=0,
		surface=func(state: PackedFloat64Array,_at: float) -> float: return state[RB.SIZE],
		transition=func(state: PackedFloat64Array,_at: float) -> Dictionary:
			return {ok=true,state=project_stop(state,RB.SIZE,owner),event={rpm_residual=0.0}},
	})
	events.append({
		id="main_tank_unusable",type="fuel_tank_unusable",sense="falling",surface_unit="kg",priority=10,
		enabled=func(state: PackedFloat64Array,_at: float) -> bool:
			return int(state[RB.SIZE+SOURCE_MODE_INDEX])==MODE_MAIN_TANK,
		surface=func(state: PackedFloat64Array,_at: float) -> float:
			return state[RB.SIZE+1]-state[RB.SIZE+LINE_FUEL_INDEX]-install.unusable_fuel_kg,
		transition=func(state: PackedFloat64Array,_at: float) -> Dictionary:
			var line_mass: float=maxf(0.0,state[RB.SIZE+LINE_FUEL_INDEX])
			var main_id: String=str(install.fuel_tank.id)
			if not line.is_empty() and line_mass>0.0:
				var total: float=line_mass+install.unusable_fuel_kg
				return {ok=true,state=_transition_source(state,owner,MODE_FEED_LINE,"",total),
					event={type="fuel_tank_unusable",resource="main_tank",resource_id=main_id,
						fuel_residual_kg=install.unusable_fuel_kg,main_fuel_residual_kg=install.unusable_fuel_kg}}
			var total: float=line_mass+install.unusable_fuel_kg
			return {ok=true,state=_transition_source(state,owner,MODE_STARVED,"fuel_exhausted",total),
				event={type="fuel_exhausted",reason="fuel_exhausted",resource="main_tank",resource_id=main_id,
					fuel_residual_kg=install.unusable_fuel_kg,main_fuel_residual_kg=install.unusable_fuel_kg}}
	})
	if not line.is_empty():
		events.append({
			id="feed_line_empty",type="fuel_line_empty",sense="falling",surface_unit="kg",priority=11,
			enabled=func(state: PackedFloat64Array,_at: float) -> bool:
				return int(state[RB.SIZE+SOURCE_MODE_INDEX])==MODE_FEED_LINE,
			surface=func(state: PackedFloat64Array,_at: float) -> float:
				return state[RB.SIZE+LINE_FUEL_INDEX],
			transition=func(state: PackedFloat64Array,at: float) -> Dictionary:
				var total: float=maxf(0.0,state[RB.SIZE+1])
				var line_mass: float=maxf(0.0,state[RB.SIZE+LINE_FUEL_INDEX])
				var main_mass: float=maxf(0.0,total-line_mass)
				var can_use_main: bool=main_mass>install.unusable_fuel_kg
				if can_use_main and bool(install.get("has_pickup_position",false)):
					var sample: Dictionary=_pickup_surface_sample(owner,state,at)
					if not sample.get("ok",false): return {ok=false}
					can_use_main=bool(sample.get("defined",false)) and float(sample.margin_m)>=0.0
				var next_mode: int=MODE_MAIN_TANK if can_use_main else MODE_STARVED
				var reason: String="" if can_use_main else ("fuel_exhausted" if main_mass<=install.unusable_fuel_kg else "fuel_starved")
				var event_type: String="fuel_line_empty" if can_use_main else reason
				return {ok=true,state=_transition_source(state,owner,next_mode,reason,main_mass,0.0),
					event={type=event_type,reason=reason,resource="feed_line",resource_id=str(line.liquid_inventory_id),
						fuel_residual_kg=line_mass,line_fuel_residual_kg=line_mass,main_fuel_kg=main_mass}}
		})
	if bool(install.get("has_pickup_position",false)) and install.has("fuel_feed"):
		events.append({
			id="pickup_lost",type="fuel_pickup_lost",sense="falling",surface_unit="m",priority=20,
			enabled=func(state: PackedFloat64Array,at: float) -> bool:
			return int(state[RB.SIZE+SOURCE_MODE_INDEX])==MODE_MAIN_TANK,
			surface=func(state: PackedFloat64Array,at: float) -> float:
				var sample: Dictionary=_pickup_surface_sample(owner,state,at)
				if not sample.get("ok",false): return NAN
				return float(sample.margin_m) if sample.get("defined",false) else 1.0,
			transition=func(state: PackedFloat64Array,at: float) -> Dictionary:
				var line_mass: float=maxf(0.0,state[RB.SIZE+LINE_FUEL_INDEX])
				var main_mass: float=maxf(0.0,state[RB.SIZE+1]-line_mass)
				if not line.is_empty() and line_mass>0.0:
					return {ok=true,state=_transition_source(state,owner,MODE_FEED_LINE),
						event={type="fuel_pickup_lost",resource="main_tank",resource_id=str(install.fuel_tank.id),
							fuel_residual_kg=main_mass,line_fuel_kg=line_mass}}
				return {ok=true,state=_transition_source(state,owner,MODE_STARVED,"fuel_starved"),
					event={type="fuel_starved",reason="fuel_starved",resource="main_tank",resource_id=str(install.fuel_tank.id),
						fuel_residual_kg=main_mass}}
		})
		events.append({
			id="pickup_recovered",type="fuel_pickup_recovered",sense="rising",surface_unit="m",priority=15,
			enabled=func(state: PackedFloat64Array,at: float) -> bool:
				if int(state[RB.SIZE+SOURCE_MODE_INDEX])==MODE_MAIN_TANK \
						or state[RB.SIZE+1]-state[RB.SIZE+LINE_FUEL_INDEX]<=install.unusable_fuel_kg: return false
				return true,
			surface=func(state: PackedFloat64Array,at: float) -> float:
				var sample: Dictionary=_pickup_surface_sample(owner,state,at)
				if not sample.get("ok",false): return NAN
				return float(sample.margin_m) if sample.get("defined",false) else -1.0,
			transition=func(state: PackedFloat64Array,_at: float) -> Dictionary:
				var main_mass: float=maxf(0.0,state[RB.SIZE+1]-state[RB.SIZE+LINE_FUEL_INDEX])
				return {ok=true,state=_transition_source(state,owner,MODE_MAIN_TANK),
					event={type="fuel_pickup_recovered",resource="main_tank",resource_id=str(install.fuel_tank.id),
						fuel_residual_kg=main_mass}}
		})
	return events

static func point(owner: Node, body: PackedFloat64Array, values: PackedFloat64Array, time_s: float,
		include_stage_coupling: bool = false) -> Dictionary:
	var prop: Dictionary=owner.aircraft.model.propulsion
	var install: Dictionary=prop.glow
	var state: Dictionary=unpack(values,install)
	if state.is_empty(): return {ok=false}
	var mode: int=int(values[SOURCE_MODE_INDEX])
	var main_fuel: float=values[1]-values[LINE_FUEL_INDEX]
	var line_fuel: float=values[LINE_FUEL_INDEX]
	# Negative total/resource amounts occur only on the connected left-limit trial used to
	# locate an exact boundary. Mass properties clamp to the physical boundary; the source
	# mode continues to provide its pre-boundary flow until the event transition is accepted.
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
	var stage_coupling: Dictionary={}
	var mass_context: Dictionary=_stage_mass_context(owner,values)
	if not mass_context.get("ok",false): return {ok=false}
	feed_mass=mass_context.properties
	main_fuel=float(mass_context.main_fuel_kg)
	line_fuel=float(mass_context.line_fuel_kg)
	if mode==MODE_MAIN_TANK and not install.has("feed_line") and main_fuel<=install.unusable_fuel_kg:
		# Keep the connected left-limit source active while localizing the fixed tank residue.
		state.fuel_kg=install.unusable_fuel_kg+1.0e-30
	var lifecycle_floor: float=0.0 if install.has("feed_line") else install.unusable_fuel_kg
	if install.has("fuel_feed"):
		airframe=_airframe(owner,body,values,air,hub_air,rpm,load,density)
		if airframe.is_empty(): return {ok=false}
	var evaluator: Variant=owner.get_meta(EVALUATOR_META,null)
	var evaluation: Dictionary
	if install.has("fuel_feed") and mode==MODE_MAIN_TANK:
		var tank_arm: PackedFloat64Array=M.sub(install.tank_position,feed_mass.cg_body_m)
		var omega: PackedFloat64Array=body.slice(RB.RATE,RB.RATE+3)
		var pickup: PackedFloat64Array=install.get("pickup_position",PackedFloat64Array()) \
			if mode==MODE_MAIN_TANK else PackedFloat64Array()
		var solve_fuel: float=maxf(main_fuel,install.unusable_fuel_kg+1.0e-30)
		var solve_admission: float=admission_at(install,state.air_fraction,rpm)
		var feed_context: Dictionary=FuelFeed.prepare_factor_context(install.fuel_feed,solve_fuel,
			install.capacity_fuel_kg,install.unusable_fuel_kg,solve_admission,rpm,
			install.tank_position,install.tank_size)
		if not feed_context.get("ok",false): return {ok=false}
		var feed_force_body: PackedFloat64Array=airframe.external.slice(0,3)
		var solve: Dictionary=FuelFeed.solve_factor(func(candidate_factor: float) -> Dictionary:
			var candidate_evaluation: Dictionary=_lifecycle_evaluate(install,state,rpm,local_cooling,ambient,
				values[12],candidate_factor,evaluator,identity_matches,owner,lifecycle_floor)
			if not candidate_evaluation.get("ok",false): return {ok=false}
			var candidate_coupling: Dictionary=_stage_coupling(owner,body,values,install,state,
				candidate_evaluation.source,load,airframe,feed_mass,ambient)
			if not candidate_coupling.get("ok",false): return {ok=false}
			var target_factor: float=FuelFeed.factor_for_stage(feed_context,feed_force_body,feed_mass.mass_kg,
				tank_arm,candidate_coupling.alpha_body,omega,pickup)
			if not is_finite(target_factor): return {ok=false}
			return {ok=true,target_factor=target_factor,evaluation=candidate_evaluation,
				coupling=candidate_coupling}
		,1.0)
		if not solve.get("ok",false): return {ok=false,message=str(solve.get("message","fuel feed solve failed"))}
		var solved: Dictionary=solve.payload
		feed_factor=float(solve.factor)
		evaluation=solved.evaluation
		stage_coupling=solved.coupling
		feed=FuelFeed.evaluate(install.fuel_feed,feed_force_body,feed_mass.mass_kg,solve_fuel,
			install.capacity_fuel_kg,install.unusable_fuel_kg,solve_admission,rpm,install.tank_position,
			install.tank_size,tank_arm,stage_coupling.alpha_body,omega,pickup)
		if not feed.get("ok",false): return {ok=false}
		evaluation.fuel_feed_solver={factor=feed_factor,residual=float(solve.residual),
			evaluations=int(solve.evaluations),iterations=int(solve.iterations)}
	else:
		if mode==MODE_STARVED:
			feed_factor=0.0
		evaluation=_lifecycle_evaluate(install,state,rpm,local_cooling,ambient,values[12],feed_factor,
			evaluator,identity_matches,owner,lifecycle_floor)
	if not evaluation.ok: return evaluation
	if install.has("fuel_feed") and mode!=MODE_MAIN_TANK:
		var coupling_for_pickup: Dictionary=_stage_coupling(owner,body,values,install,state,
			evaluation.source,load,airframe,feed_mass,ambient)
		if not coupling_for_pickup.get("ok",false): return {ok=false}
		stage_coupling=coupling_for_pickup
		var tank_arm_for_pickup: PackedFloat64Array=M.sub(install.tank_position,feed_mass.cg_body_m)
		var pickup_for_sample: PackedFloat64Array=install.get("pickup_position",PackedFloat64Array())
		pickup_for_sample=PackedFloat64Array()
		feed=FuelFeed.evaluate(install.fuel_feed,airframe.external.slice(0,3),feed_mass.mass_kg,
			maxf(main_fuel,0.0),install.capacity_fuel_kg,install.unusable_fuel_kg,
			admission_at(install,state.air_fraction,rpm),rpm,install.tank_position,install.tank_size,tank_arm_for_pickup,
			coupling_for_pickup.alpha_body,body.slice(RB.RATE,RB.RATE+3),pickup_for_sample)
		if not feed.get("ok",false): return {ok=false}
		feed.main_tank_pressure_factor=float(feed.factor)
		feed.active_source_mode=mode
		feed.active_factor=1.0 if mode==MODE_FEED_LINE else 0.0
		feed.factor=float(feed.active_factor)
		feed.active_source="preprimed_line" if mode==MODE_FEED_LINE else "starved"
		if bool(install.get("has_pickup_position",false)):
			var margin: float=FuelFeed.pickup_margin_m(feed.g_eff,feed.fill_fraction,
				install.pickup_position,install.tank_position,install.tank_size)
			feed.pickup_margin_m=margin
			feed.pickup_surface_defined=is_finite(margin)
			feed.pickup_wet=is_finite(margin) and margin>=0.0
	elif not feed.is_empty():
		feed.active_source_mode=mode
		feed.active_factor=feed_factor
		feed.active_source="main_tank"
	evaluation.air=air
	evaluation.environment=ambient
	evaluation.hub_air_velocity_body_m_s=hub_air
	evaluation.propeller=load
	evaluation.state=state
	if not airframe.is_empty():
		evaluation.airframe=airframe
		if not feed.is_empty():
			evaluation.fuel_feed=feed
		evaluation.mass=feed_mass
	# The derivative path needs the exact coupling that already closed feed pressure.
	# Keep this internal payload out of the public point() result used by observers.
	if include_stage_coupling and not stage_coupling.is_empty():
		evaluation["_stage_coupling"]=stage_coupling
	return evaluation


static func _lifecycle_evaluate(install: Dictionary, state: Dictionary, rpm: float, local_cooling: float,
		ambient: Dictionary, mixture: float, feed_factor: float, evaluator: Variant,
		identity_matches: bool, owner: Node, unusable_floor: float) -> Dictionary:
	var dry_density: float=1.225*float(ambient.engine_charge_ratio)
	var ambient_temperature: float=float(ambient.get("temperature_k",288.15))
	if evaluator is Life.PreparedEvaluator and identity_matches:
		return Life.evaluate_prepared(evaluator,state,rpm,_throttle(owner),mixture,dry_density,
			ambient_temperature,local_cooling,feed_factor,unusable_floor)
	# Standalone fixtures may run before initialization; a failed reload can restore a different installation.
	return Life.evaluate(install.profile,install.settings,state,rpm,_throttle(owner),mixture,dry_density,
		ambient_temperature,local_cooling,feed_factor,unusable_floor)


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
		var coast: Dictionary=Source.evaluate(install.profile,0.001,admission_at(install,state.air_fraction,0.001),values[12],
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
		density,air,owner.sim.aux[lag] if lag>=0 else NAN,PackedFloat64Array(),owner._ground_up(body),propeller_loads,
		PackedFloat64Array([load.thrust_n,load.torque_nm])) # EX-14c: the wake carries this stage's thrust and torque
	var ground: Dictionary=owner._ground_evaluation(body,owner.sim.aux,values,air)
	if not ground.get("ok",false): return {}
	for i in ground.loads.size(): external[i]+=ground.loads[i]
	return {external=external,ground=ground}

static func evaluate(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float, owner: Node) -> Dictionary:
	if values.size()!=SIZE+owner.wheel_count(): return {}
	var result: Dictionary=point(owner,body,values,time_s,true)
	if not result.ok: return {}
	var mass: Dictionary=result.get("mass",{})
	if mass.is_empty(): mass=properties(owner,values[1],values[LINE_FUEL_INDEX])
	if not mass.ok: return {}
	var rpm: float=maxf(0.0,values[0])
	var airframe: Dictionary=result.get("airframe",{})
	if airframe.is_empty():
		airframe=_airframe(owner,body,values,result.air,result.hub_air_velocity_body_m_s,rpm,result.propeller,result.environment.rho_kgm3)
	if airframe.is_empty(): return {}
	var ground: Dictionary=airframe.ground
	var coupling: Dictionary=result.get("_stage_coupling",{})
	if coupling.is_empty():
		coupling=_stage_coupling(owner,body,values,owner.aircraft.model.propulsion.glow,
			result.state,result.source,result.propeller,airframe,mass,result.environment)
	if not coupling.get("ok",false): return {}
	var external: PackedFloat64Array=airframe.external
	var response: Dictionary=coupling.response
	var derivative:=PackedFloat64Array()
	derivative.resize(SIZE)
	derivative[0]=coupling.spin_acceleration*60.0/TAU
	for i in 6: derivative[i+1]=result.rates[Life.CONTINUOUS_KEYS[i]]
	if int(values[SOURCE_MODE_INDEX])==MODE_FEED_LINE:
		derivative[LINE_FUEL_INDEX]=derivative[1]
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
	var mass: Dictionary=properties(owner,values[RB.SIZE+1],values[RB.SIZE+LINE_FUEL_INDEX])
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
	if combined.size()<SIZE+RB.SIZE:
		return PackedFloat64Array([NAN])
	var bounded: Dictionary=ResourceStep.advance(combined,time_s,dt,derivative,first,_resource_events(owner))
	if not bounded.ok: return PackedFloat64Array([NAN])
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
			endpoint.firing_fraction,0.0)
	else:
		accepted=Life.accepted(install.profile,install.settings,before,candidate,dt,combined[RB.SIZE],
			values[0],endpoint.firing_fraction,0.0)
	if not accepted.ok: return PackedFloat64Array([NAN])
	var accepted_state: Dictionary=accepted.state
	var terminal_fuel_reason: String=""
	for event_value: Dictionary in bounded.events:
		if str(event_value.get("type","")) in ["fuel_exhausted","fuel_starved"]:
			terminal_fuel_reason=str(event_value.get("reason",event_value.get("type","")))
	if not terminal_fuel_reason.is_empty():
		accepted_state=_stop_for_fuel(accepted_state,terminal_fuel_reason)
	values=put_state(values,accepted_state)
	var out: PackedFloat64Array=bounded.state.slice(0,RB.SIZE)
	out.append_array(values)
	var events: Array[Dictionary]=[]
	var stopped_time: float=time_s+dt
	for event: Dictionary in bounded.events:
		var reported: Dictionary=event.duplicate(true)
		if reported.get("type","")=="rotor_stop":
			reported.type="glow_rotor_stopped"
		if reported.get("type","") in ["fuel_exhausted","fuel_starved"]:
			stopped_time=float(reported.get("time_s",stopped_time))
		events.append(reported)
	if was_running and not bool(accepted_state.running):
		var stop_reason: String=str(accepted_state.get("stop_reason",""))
		if stop_reason in ["fuel_exhausted","fuel_starved"]:
			for event_value: Dictionary in bounded.events:
				if str(event_value.get("reason",""))==stop_reason:
					stopped_time=float(event_value.get("time_s",stopped_time))
					break
		events.append({"type":"glow_stopped","reason":stop_reason,"time_s":stopped_time})
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
	var context: Dictionary=mass_context(owner,values)
	if not context.get("ok",false): return {ok=false,message="Glow fuel mass context is invalid"}
	out.mass_properties=context.properties
	# FUEL-01b: the installed blend's own density (profile.gd), so displays never assume a fixed g/mL.
	out.fuel_density_kg_m3=float(owner.aircraft.model.propulsion.glow.profile.fuel.density_kg_m3)
	out.fuel_volume_m3=maxf(0.0,values[1])/out.fuel_density_kg_m3
	out.main_fuel_kg=context.main_fuel_kg
	out.line_fuel_kg=context.line_fuel_kg
	out.feed_line_fuel_kg=context.line_fuel_kg
	out.total_fuel_kg=context.total_fuel_kg
	out.fuel_source_mode=context.source_mode
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
