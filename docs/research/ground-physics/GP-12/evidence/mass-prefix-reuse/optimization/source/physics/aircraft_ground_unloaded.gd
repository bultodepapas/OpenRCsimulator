## Qualified zero-normal-force reference slice; no source or integrator owner.
## The TRUSTED evaluator owner must first prove its ACTUAL source/brake/external
## wrench law remains absent over the entire interval. Snapshot zeros and receipt
## metadata cannot establish that precondition. This helper binds fixed mechanical
## configuration and proves the unloaded free-reference branch only.
extends RefCounted
const Stage:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/aircraft_ground_stage.gd")
const Datum:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/fixed_datum_body.gd")
const Support:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/ground_support.gd")
const Rotor:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rotor_coupling.gd")
const Normal:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/normal_compliance.gd")
const Ring:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/wheel_geometry.gd")
const Admission:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/normal_contact_admission.gd")
const AR:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/contact_assembly_resolution.gd")
const RB:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/rigid_body.gd")
const GC:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/generalized_coordinates.gd")
const M:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")
const FORMAT:="openrc-aircraft-ground-unloaded-binding v1"
const LAW:="fixed-CM-free-spin-plane-unloaded-reference-v1"
const KEYS:=["ground_stage","properties","provider","motion","gravity","minimum_kappa","owner_dynamics_identity"]
## Same nondegenerate raw-stage convention as Simulation; avoid a preload cycle.
const MIN_STAGE_QNORM_SQ:=1e-24

static func prepare(config:Dictionary)->Dictionary:
	if config.size()!=KEYS.size() or not config.has_all(KEYS):return _failure("explicit complete owner configuration required")
	if not config.ground_stage is Dictionary or typeof(config.ground_stage.get("law"))!=TYPE_STRING \
		or not config.ground_stage.get("normal") is Dictionary or typeof(config.ground_stage.normal.get("law"))!=TYPE_STRING \
		or not config.ground_stage.get("rotor_system") is Dictionary or typeof(config.ground_stage.rotor_system.get("law"))!=TYPE_STRING \
		or not Stage._prepared_shape(config.ground_stage) \
		or not config.properties is Dictionary or not Datum._coupled_properties_valid(config.properties) \
		or not config.provider is Dictionary or not config.motion is Array \
		or typeof(config.gravity) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(config.gravity) or config.gravity<0.0 \
		or typeof(config.minimum_kappa) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(config.minimum_kappa) \
		or config.minimum_kappa<Ring.MIN_AXLE_PROJECTION or config.minimum_kappa>1.0 \
		or typeof(config.owner_dynamics_identity)!=TYPE_STRING or config.owner_dynamics_identity.is_empty() or config.owner_dynamics_identity.length()>256:
		return _failure("invalid fixed owner configuration")
	var provider:Dictionary=config.provider
	if typeof(provider.get("format"))!=TYPE_STRING or typeof(provider.get("geometry_law"))!=TYPE_STRING \
		or provider.format!=Support.FORMAT or provider.geometry_law!=Support.LEGACY \
		or typeof(provider.get("surfaces"))!=TYPE_PACKED_FLOAT64_ARRAY or not provider.surfaces.is_empty() \
		or not provider.get("regions") is Array:return _failure("only explicit immutable flat legacy provider is qualified")
	var rebuilt:=Support.prepare_legacy(PackedFloat64Array(),provider.regions)
	if var_to_bytes(rebuilt)!=var_to_bytes(provider):return _failure("provider identity/configuration differs")
	var supports:Array=config.ground_stage.normal.supports
	if config.motion.size()!=supports.size():return _failure("fixed motion layout differs")
	for i in supports.size():
		var support:Variant=supports[i]
		if not support is Dictionary or typeof(support.get("contact_id"))!=TYPE_STRING \
			or not Stage._finite_shape(support.get("hub_body"),3) or not Stage._finite_shape(support.get("axle_body"),3) \
			or typeof(support.get("radius_m")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(support.radius_m) \
			or support.radius_m<Ring.MIN_RADIUS_M or support.radius_m>Ring.MAX_RADIUS_M \
			or not support.get("normal") is Dictionary or not support.normal.get("provenance") is Dictionary:
			return _failure("malformed compiled normal support")
		var normal:=Normal.prepare(support.normal.provenance)
		if not normal.ok or var_to_bytes(normal)!=var_to_bytes(support.normal):return _failure("compiled normal law differs from provenance")
		var row:Variant=config.motion[i]
		if not row is Dictionary or typeof(row.get("contact_id"))!=TYPE_STRING or row.contact_id!=supports[i].contact_id \
			or not Stage._finite_shape(row.get("hub_body"),3) or not Stage._finite_shape(row.get("axle_body"),3) \
			or row.get("hub_body")!=supports[i].hub_body or row.get("axle_body")!=supports[i].axle_body:
			return _failure("fixed hub/axle configuration differs")
		for key:String in ["carrier_rate_body","carrier_accel_body"]:
			if not Stage._finite_shape(row.get(key),3):return _failure("invalid carrier motion")
			for value:float in row[key]:
				if value!=0.0:return _failure("moving axes/carriers are not qualified")
	var system:Dictionary=config.ground_stage.rotor_system
	var carrier:=Rotor._carrier_remainder(config.properties.inertia,system.axial,system.transverse,system.reference_axes)
	var assembled:=Rotor._assemble(carrier,system.axial,system.transverse,system.reference_axes)
	if not assembled.ok:return _failure("live constant rotor matrix cannot be assembled")
	var detached:=config.duplicate(true)
	return {ok=true,format=FORMAT,law=LAW,identity=_identity(detached),config=detached,expected_matrix=assembled.matrix,expected_carrier=carrier}


## No source-free bool parameter: the owner that invokes this function must bind
## its real evaluator and prove the unforced interval, as documented above.
## Passing current configuration permits detection of captured-resource mutation.
static func qualify(binding:Dictionary,current:Dictionary,state:PackedFloat64Array,h:float,point:Dictionary)->Dictionary:
	if typeof(binding.get("format"))!=TYPE_STRING or typeof(binding.get("law"))!=TYPE_STRING \
		or binding.format!=FORMAT or binding.law!=LAW or not binding.get("config") is Dictionary \
		or typeof(binding.get("identity"))!=TYPE_STRING or _identity(binding.config)!=binding.identity \
		or var_to_bytes(binding.config)!=var_to_bytes(current):return _failure("sealed owner configuration changed")
	var checked:=prepare(current)
	if not checked.ok:return _failure("owner configuration is malformed")
	if not Stage._finite_shape(binding.get("expected_matrix"),checked.expected_matrix.size()) or not Stage._finite_shape(binding.get("expected_carrier"),6) \
		or checked.identity!=binding.identity or checked.expected_matrix!=binding.expected_matrix or checked.expected_carrier!=binding.expected_carrier:
		return _failure("owner binding is malformed or stale")
	if not Stage._finite_shape(state,state.size()) or state.size()<RB.SIZE or state.size()>256 or not is_finite(h) or h<=0.0 or h>1.0:
		return _failure("invalid bounded state/interval")
	var qnorm:=0.0
	for i in 4:qnorm+=state[RB.ATT+i]*state[RB.ATT+i]
	if not is_finite(qnorm) or qnorm<=MIN_STAGE_QNORM_SQ:return _failure("nondegenerate stage quaternion required")
	if typeof(point.get("ok"))!=TYPE_BOOL or not point.ok \
		or typeof(point.get("mass_kg")) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(point.mass_kg) \
		or not Stage._finite_shape(point.get("cg_body_m"),3) \
		or point.mass_kg!=current.properties.mass_kg or point.cg_body_m!=current.properties.cg_body_m \
		or not point.get("rotor_stage") is Dictionary:return _failure("live mass/CG/stage does not match owner binding")
	var valid:=Rotor._validate_stage(point.rotor_stage)
	if not valid.ok or point.rotor_stage.matrix!=binding.expected_matrix or point.rotor_stage.carrier!=binding.expected_carrier \
		or point.rotor_stage.axes!=current.ground_stage.rotor_system.reference_axes:return _failure("live rotor matrix/axis binding differs")
	for i in 3:
		if point.rotor_stage.velocity[i]!=state[RB.RATE+i]:return _failure("live angular state differs")
	var proof:=_reference(current,state,h,point)
	return {ok=true,eligible=proof.ok,identity=binding.identity,reference_proof=proof}


static func _reference(config:Dictionary,state:PackedFloat64Array,h:float,point:Dictionary)->Dictionary:
	if typeof(point.get("limit_rates"))!=TYPE_PACKED_FLOAT64_ARRAY or not point.limit_rates.is_empty():return _failure("not empty initial impulse map")
	if not point.get("physical") is Dictionary or not Stage._finite_shape(point.physical.get("loads"),6):return _failure("actual mechanical load evidence missing")
	for value:float in point.physical.loads:
		if value!=0.0:return _failure("actual initial wrench is not zero")
	if typeof(point.get("normal_load_n"))!=TYPE_PACKED_FLOAT64_ARRAY:return _failure("normal load evidence missing")
	for value:float in point.normal_load_n:
		if value!=0.0:return _failure("actual initial normal load is not zero")
	if typeof(point.rotor_stage.get("generalized_rhs"))!=TYPE_PACKED_FLOAT64_ARRAY:return _failure("source row evidence missing")
	for value:float in point.rotor_stage.generalized_rhs.slice(3):
		if value!=0.0:return _failure("actual local source torque is not zero")
	var rotor:Dictionary=point.rotor_stage
	for value:float in rotor.carrier_rates:
		if value!=0.0:return {ok=false,reason="moving carrier"}
	if typeof(rotor.get("hold_indices"))!=TYPE_PACKED_INT64_ARRAY or not rotor.hold_indices.is_empty():return {ok=false,reason="held rotor"}
	var omega:=state.slice(RB.RATE,RB.RATE+3)
	# Work from the actual symmetric full matrix, not ideal unit-axis algebra.
	# The exact matrix-entry Schur complement is bracketed by this rounded3x3
	# center plus a symmetric entrywise assembly error. No spin energy subtracts.
	var n:int=rotor.axial.size()+3
	var schur:=PackedFloat64Array();schur.resize(9)
	var errors:=PackedFloat64Array();errors.resize(9)
	for i in 3:
		for j in range(i,3):
			var value:float=rotor.matrix[i*n+j]
			var terms:float=absf(value)
			for k in rotor.axial.size():
				var d:float=rotor.matrix[(3+k)*n+3+k]
				if d<=0.0:return {ok=false,reason="invalid free-spin diagonal"}
				var left:float=rotor.matrix[i*n+3+k]
				var right:float=rotor.matrix[j*n+3+k]
				value-=left*right/d
				terms=AR._add(terms,AR._div(AR._mul(absf(left),absf(right)),d))
			schur[i*3+j]=value;schur[j*3+i]=value
			var error:=AR._roundoff(terms,4*rotor.axial.size()+8)
			errors[i*3+j]=error;errors[j*3+i]=error
	var schur_error:=0.0
	for i in 3:schur_error=maxf(schur_error,AR._add(AR._add(errors[i*3],errors[i*3+1]),errors[i*3+2]))
	var compact:=PackedFloat64Array([schur[0],schur[4],schur[8],schur[1],schur[2],schur[5]])
	var factor:=GC.cholesky_factor(schur,3)
	if not factor.ok:return {ok=false,reason="Schur center Cholesky refused"}
	var spd:=AR._spd_margin(schur,factor.lower,3)
	if not spd.ok:return {ok=false,reason="Schur center congruence SPD proof refused"}
	var inverse_proof:=Admission._carrier_lower_bound(compact)
	if not inverse_proof.ok:return {ok=false,reason="no positive Schur center lower bound"}
	var beta:float=inverse_proof.beta-schur_error-AR._roundoff(inverse_proof.beta+schur_error,8)
	if beta<=0.0:return {ok=false,reason="true Schur lower bound does not close"}
	var product:=RB.inertia_mul(compact,omega)
	var energy2:=M.dot(omega,product)
	var magnitude:=0.0
	for i in 3:magnitude=AR._add(magnitude,AR._mul(absf(omega[i]),absf(product[i])))
	# Include the scalar products used by inertia_mul, including cross terms.
	var carrier_size:=absf(compact[0])+absf(compact[1])+absf(compact[2])+2.0*(absf(compact[3])+absf(compact[4])+absf(compact[5]))
	var omega_sq:=0.0
	for value:float in omega:omega_sq=AR._add(omega_sq,AR._mul(absf(value),absf(value)))
	var arithmetic:=AR._roundoff(AR._mul(carrier_size,omega_sq),64)
	energy2=AR._add(AR._add(maxf(0.0,energy2),arithmetic),AR._mul(schur_error,omega_sq))
	var hgyro:=M.v3(0,0,0)
	for i in rotor.axial.size():
		var d:float=rotor.matrix[(3+i)*n+3+i]
		var ell:float=d*rotor.velocity[3+i]
		for k in 3:ell+=rotor.matrix[(3+i)*n+k]*omega[k]
		for k in 3:hgyro[k]+=rotor.matrix[k*n+3+i]/d*ell
	var omega_upper:=AR._add(M.sqrt_(AR._div(energy2,beta))*(1.0+4.0*AR.EPS),AR.ETA)
	var q:=M.q_normalized(state.slice(RB.ATT,RB.ATT+4))
	var cmv:=M.add(state.slice(RB.VEL,RB.VEL+3),M.cross(omega,config.properties.cg_body_m))
	var normal_velocity:=M.dot(M.v3(0,0,-1),M.q_rotate(q,cmv))
	var common_lower:float=normal_velocity-config.gravity*h
	var velocity_operands:=AR._add(M.norm(state.slice(RB.VEL,RB.VEL+3)),AR._mul(M.norm(omega),M.norm(config.properties.cg_body_m)))
	common_lower-=AR._roundoff(velocity_operands,256)
	var supports:Array=[]
	for support:Dictionary in config.ground_stage.normal.supports:
		var arm:=M.sub(support.hub_body,config.properties.cg_body_m)
		var arm_operands:=AR._add(M.norm(support.hub_body),M.norm(config.properties.cg_body_m))
		var lever:=AR._add(AR._add(M.norm(arm),AR._roundoff(arm_operands,32)),support.radius_m)
		var rate_lower:float=common_lower-AR._mul(lever,omega_upper)
		rate_lower-=AR._roundoff(absf(normal_velocity)+config.gravity*h+lever*omega_upper,128)
		if rate_lower<=0.0:return {ok=false,reason="strict outward gap-speed bound does not close",rate_lower=rate_lower}
		var hub:=M.add(state.slice(0,3),M.q_rotate(q,support.hub_body))
		var axis:=M.q_rotate(q,support.axle_body)
		var geo:=Ring.plane(hub,axis,support.radius_m,M.v3(0,0,0),M.v3(0,0,-1))
		if not geo.ok:return {ok=false,reason="state plane geometry refused"}
		var kappa:=M.sqrt_(maxf(0.0,1.0-axis[2]*axis[2]))
		var kappa_lower:float=kappa-AR._mul(h,omega_upper)-AR._roundoff(kappa+h*omega_upper,64)
		if kappa_lower<config.minimum_kappa:return {ok=false,reason="protected kappa cannot close"}
		var gap_operand:=AR._add(AR._add(M.norm(state.slice(0,3)),M.norm(support.hub_body)),support.radius_m)
		var gap_error:float=geo.residual_m+AR._roundoff(gap_operand,256)
		var xmax:float=maxf(0.0,-geo.signed_gap_m+gap_error)
		var p:Dictionary=support.normal.values
		if xmax>p.stroke:return {ok=false,reason="progressive stop is outside unloaded slice"}
		var coefficient_upper:=0.0
		if xmax>0.0:
			var ramp:float=Normal._ramp(xmax,p.damping_onset)[0]
			coefficient_upper=p.stiffness-p.rebound_damping*ramp/xmax*rate_lower
			coefficient_upper+=AR._roundoff(p.stiffness+absf(p.rebound_damping*ramp/xmax*rate_lower),128)
			if coefficient_upper>=0.0:return {ok=false,reason="rebound clipping cannot be proved",coefficient_upper=coefficient_upper}
		supports.append({contact_id=support.contact_id,gap_m=geo.signed_gap_m,xmax=xmax,gap_rate_lower=rate_lower,
			trial_force_per_compression_upper=coefficient_upper,kappa_lower=kappa_lower,
			event_free=geo.signed_gap_m>gap_error,at_most_one_gap_root=true})
	return {ok=true,exact_reference_flow_admitted=true,floating_rk_admitted=false,
		scope="source_free_fixed_mass_fixed_body_axes_plane_unloaded_reference_flow_only",
		reduced_rotational_energy_times_two_upper=energy2,schur_beta=beta,schur_error_bound=schur_error,
		omega_upper=omega_upper,gyro_momentum_body=hgyro,supports=supports,schur_center=compact}

static func _identity(config:Dictionary)->String:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(LAW.to_utf8_buffer())
	hash.update(var_to_bytes(config))
	return hash.finish().hex_encode()

static func _failure(reason:String)->Dictionary:
	return {ok=false,reason=reason,law=LAW}
