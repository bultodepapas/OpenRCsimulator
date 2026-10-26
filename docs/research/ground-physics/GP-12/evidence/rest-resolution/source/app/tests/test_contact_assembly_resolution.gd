extends SceneTree
const R := preload("res://physics/contact_assembly_resolution.gd")
const Q := preload("res://physics/ground_traction.gd")
const I := preload("res://physics/aircraft_ground_impulse.gd")
var checks := 0
var failures := 0

func check(label: String, condition: bool, detail: Variant = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func operands(raw: Dictionary) -> Dictionary:
	var z: PackedFloat64Array = raw.velocity_cm_body.duplicate()
	z.append_array(raw.stage.velocity)
	var w := z.size()
	var count: int = raw.stage.axial.size()
	var mass := PackedFloat64Array()
	mass.resize(w*w)
	for i in 3: mass[i*w+i] = raw.mass_kg
	for i in w-3:
		for j in w-3: mass[(3+i)*w+3+j] = raw.stage.matrix[i*(w-3)+j]
	var valid := I._stage(raw.stage)
	var responses := PackedFloat64Array()
	for row in raw.free_slip.size():
		responses.append_array(I._response(valid.factor, count, raw.mass_kg, raw.jacobian.slice(row*w,(row+1)*w)))
	return {z=z,mass=mass,responses=responses}

func solve(raw: Dictionary, o: Dictionary, budget: float = 1e-12) -> Dictionary:
	return R.solve(raw.mobility,raw.free_slip,raw.limits,raw.groups,o.mass,raw.jacobian,
		o.z,raw.prescribed_slip_bias,o.responses,budget)

func _maxabs(a: PackedFloat64Array) -> float:
	var value := 0.0
	for x: float in a: value=maxf(value,absf(x))
	return value

func _initialize() -> void:
	var file := FileAccess.open("res://tests/fixtures/ground_traction_rest_symmetric16.bin", FileAccess.READ)
	var raw: Dictionary = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	var o := operands(raw)
	var eta := PackedByteArray([1,0,0,0,0,0,0,0]).decode_double(0)
	check("outward multiplication covers gradual underflow",R._mul(eta,0.5)>=eta)
	check("positive bound underflow cannot be amplified from a lost zero",
		R._mul(R._mul(1e-250,1e-250),1e300)>=1e-200)
	check("outward overflow refuses finite proof",not is_finite(R._mul(1e300,1e300)))
	check("invalid bound operands cannot be hidden by multiplication by zero",not is_finite(R._mul(INF,0.0)))
	check("downward complement remains below exact dyadic subtraction",R._one_minus(0.5)<0.5)
	check("explicit inverse-L witness verifies true SPD",R._spd_margin(PackedFloat64Array([2.0,0.0,0.0,3.0]),
		PackedFloat64Array([1.4142135623730951,0.0,0.0,1.7320508075688772]),2).ok)
	check("floating factor plus nonsingularity cannot fake true SPD",not R._spd_margin(
		PackedFloat64Array([1.0,2.0,2.0,1.0]),PackedFloat64Array([1.0,0.0,0.0,1.0]),2).ok)
	var before := var_to_bytes([raw,o])
	var assembly := R.bounds(raw.mobility,raw.free_slip,o.mass,raw.jacobian,o.z,raw.prescribed_slip_bias,o.responses)
	check("actual exact binary complete physical assembly qualifies", assembly.ok,assembly)
	if not assembly.ok:
		quit(1)
		return
	var zero := PackedFloat64Array()
	zero.resize(raw.free_slip.size())
	var proof := R.certificate(raw.mobility,raw.free_slip,raw.limits,raw.groups,zero,assembly)
	check("true PSD zero objective gap fits derived resolution",proof.ok,proof)
	check("derived numerical resolution remains tiny and positive",proof.assembly_objective_resolution_j>0 and proof.assembly_objective_resolution_j<1e-15,proof)
	var result := solve(raw,o)
	check("exact Sym16 lossless result accepted distinctly",result.ok and result.status=="converged_at_assembly_resolution",result)
	var publication_proof := proof.duplicate(true)
	publication_proof.assembly_resolution_budget_j=1e-12
	var altered := zero.duplicate()
	altered[0]=1e-20
	check("private publisher refuses a different nonzero candidate before projection",not Q._publish(raw.mobility,
		raw.free_slip,raw.limits,raw.groups,PackedFloat64Array(),PackedFloat64Array(),altered,1.0,{},0,
		"unsupported_candidate",publication_proof).ok)
	publication_proof.assembly_resolution_budget_j=INF
	check("private publisher refuses nonfinite bounds before publication",not Q._publish(raw.mobility,
		raw.free_slip,raw.limits,raw.groups,PackedFloat64Array(),PackedFloat64Array(),zero,1.0,{},0,
		"unsupported_overflow",publication_proof).ok)
	if result.ok:
		check("never claims strict original KKT success",not result.strict_kkt_passed and result.kkt_residual_scaled>result.kkt_tolerance_scaled)
		check("smallest feasible reaction does not invent null circulation",result.impulse==zero and result.dissipation==0.0 and result.objective==0.0)
	check("strict pure API still refuses unresolved rest",not Q.solve(raw.mobility,raw.free_slip,raw.limits,raw.groups).ok)
	check("owner ceiling below derived bound refuses",not solve(raw,o,proof.assembly_objective_resolution_j*0.5).ok)
	check("zero owner ceiling cannot become a floor",not solve(raw,o,0.0).ok)
	check("negative budget refuses",not solve(raw,o,-1.0).ok)
	check("infinite budget refuses",not solve(raw,o,INF).ok)
	check("all input bytes detached",var_to_bytes([raw,o])==before)
	var actual_impulse := I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,
		raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups,1024,{},1e-12)
	check("actual Impulse opt-in accepts original rest fixture",actual_impulse.ok,actual_impulse)
	if actual_impulse.ok:
		check("original independent mass/slip/work certificates unchanged",actual_impulse.mass_solve_relative_residual==0.0
			and actual_impulse.energy_balance_residual==0.0 and actual_impulse.slip_relative_residual<=1e-10)
		check("lossless state keeps physical velocity and spins",_maxabs(actual_impulse.delta_velocity_cm_body)==0.0
			and _maxabs(actual_impulse.delta_omega)==0.0 and _maxabs(actual_impulse.delta_spin)==0.0
			and actual_impulse.dissipated_energy==0.0)
		var recert := I._recertify(actual_impulse.qp,raw.mobility,raw.prescribed_slip_bias,
			o.z,raw.jacobian,raw.limits,raw.groups,zero,assembly)
		check("capture recertification reuses identical qualified contract",recert.ok
			and not recert.strict_kkt_passed and recert.assembly_resolution.ok,recert)
		var invalid := zero.duplicate()
		invalid[0]=raw.limits[0]*2.0
		check("capture cannot use resolution to exceed original capacity",not I._recertify(actual_impulse.qp,
			raw.mobility,raw.prescribed_slip_bias,o.z,raw.jacobian,raw.limits,raw.groups,invalid,assembly).ok)
	check("actual Impulse absent opt-in remains strict",not I.apply(raw.stage,raw.mass_kg,raw.velocity_cm_body,
		raw.jacobian,raw.prescribed_slip_bias,raw.limits,raw.groups).ok)
	for scale: float in [0.0,1e-12,1e-6,0.01,0.25,0.5,1.0]:
		var scaled := raw.duplicate(true)
		var so := operands(scaled)
		for i in so.z.size(): so.z[i]*=scale
		for row in scaled.free_slip.size():
			var value: float = scaled.prescribed_slip_bias[row]
			for j in so.z.size(): value+=scaled.jacobian[row*so.z.size()+j]*so.z[j]
			scaled.free_slip[row]=value
		var sr := solve(scaled,so)
		check("0..1 exact velocity scale accepts with no gratuitous reaction: "+str(scale),sr.ok and _maxabs(sr.impulse)==0.0,sr)
	# Genuine nontrivial longitudinal motion must NOT fit a roundoff certificate
	# at zero impulse, even with an arbitrarily large owner ceiling.
	for speed: float in [0.001,0.1,1.0]:
		var moving := raw.duplicate(true)
		var mo := operands(moving)
		mo.z.fill(0.0)
		mo.z[0]=speed
		for row in moving.free_slip.size():
			var value: float = moving.prescribed_slip_bias[row]
			for j in mo.z.size(): value+=moving.jacobian[row*mo.z.size()+j]*mo.z[j]
			moving.free_slip[row]=value
		var bound := R.bounds(moving.mobility,moving.free_slip,mo.mass,moving.jacobian,mo.z,moving.prescribed_slip_bias,mo.responses)
		var bad := R.certificate(moving.mobility,moving.free_slip,moving.limits,moving.groups,zero,bound)
		check("motion cannot be masked by assembly resolution: "+str(speed),not bad.ok and bad.true_objective_gap_upper_j>bad.assembly_objective_resolution_j,bad)
		var actual := solve(moving,mo,1e100)
		check("actual moving solver either reacts or refuses: "+str(speed),not actual.ok or actual.impulse!=zero,actual)
		var reaction := 0.0
		if actual.ok:
			for row in moving.free_slip.size(): reaction+=moving.jacobian[row*mo.z.size()]*actual.impulse[row]
		check("genuine translation resolves passive opposing reaction: "+str(speed),actual.ok
			and reaction<0.0 and actual.dissipation>0.0,actual)
	var corrupt := o.duplicate(true)
	corrupt.responses[0]*=1.01
	check("fabricated inaccurate response cannot inflate Γ",not solve(raw,corrupt).ok)
	corrupt=o.duplicate(true)
	corrupt.z[0]+=0.1
	check("mismatched slip operands refuse",not solve(raw,corrupt).ok)
	corrupt=o.duplicate(true)
	corrupt.mass[0]=0.0
	check("nonSPD mass cannot claim true PSD proof",not solve(raw,corrupt).ok)
	var fake := assembly.duplicate(true)
	fake.mobility_error.fill(1e100)
	fake.slip_error.fill(1e100)
	var rederived := R.certificate(raw.mobility,raw.free_slip,raw.limits,raw.groups,zero,fake)
	check("fabricated uncertainty floats are rederived, not trusted",rederived.ok
		and rederived.assembly_objective_resolution_j==proof.assembly_objective_resolution_j)
	fake=assembly.duplicate(true)
	fake.operands.a[0]*=2.0
	check("source identity mutation refuses original binding",not R.certificate(raw.mobility,raw.free_slip,
		raw.limits,raw.groups,zero,fake).ok)
	# A nearly singular SPD mass may be positive, yet its assembly cannot claim
	# our 1e-10 relative numeric contract. It must refuse, not inflate Γ.
	var bad_mass := PackedFloat64Array([1.0,1.0-1e-10,1.0-1e-10,1.0])
	var bad_factor := Q.GC.cholesky_factor(bad_mass,2)
	var response := PackedFloat64Array()
	for row in 2:
		var rhs := PackedFloat64Array([1.0 if row==0 else 0.0,1.0 if row==1 else 0.0])
		response.append_array(Q.GC.solve_cholesky(bad_factor.lower,rhs,2))
	var bad_a := PackedFloat64Array([response[0],response[2],response[1],response[3]])
	var unsupported := R.bounds(bad_a,PackedFloat64Array([0.0,0.0]),bad_mass,
		PackedFloat64Array([1.0,0.0,0.0,1.0]),PackedFloat64Array([0.0,0.0]),
		PackedFloat64Array([0.0,0.0]),response)
	check("ill-conditioned context cannot launder a materially unresolved bound",not unsupported.ok,unsupported)
	check("immutable ETA matches exact IEEE minimum-subnormal bytes",R.ETA==eta and R.ETA>0.0)
	var overflow_proof := R.certificate(raw.mobility,raw.free_slip,
		PackedFloat64Array([1e300,1e300,1e300,1e300,1e300,1e300,1e300,1e300,1e300]),
		raw.groups,zero,assembly)
	check("derived energy uncertainty overflow refuses",not overflow_proof.ok,overflow_proof)
	# Row-unit changes preserve the physical objective and the owner's ceiling.
	for unit: float in [0.001,1000.0]:
		var rowscaled := raw.duplicate(true)
		var ro := operands(rowscaled)
		for row in rowscaled.free_slip.size():
			var factor := unit if row%3==0 else 1.0
			rowscaled.limits[row]/=factor
			for k in ro.z.size():
				rowscaled.jacobian[row*ro.z.size()+k]*=factor
				ro.responses[row*ro.z.size()+k]*=factor
		for i in rowscaled.free_slip.size():
			var value: float = rowscaled.prescribed_slip_bias[i]
			for k in ro.z.size(): value+=rowscaled.jacobian[i*ro.z.size()+k]*ro.z[k]
			rowscaled.free_slip[i]=value
			for j in rowscaled.free_slip.size():
				value=0.0
				for k in ro.z.size(): value+=rowscaled.jacobian[i*ro.z.size()+k]*ro.responses[j*ro.z.size()+k]
				rowscaled.mobility[i*rowscaled.free_slip.size()+j]=value
		var rr := solve(rowscaled,ro)
		check("row units do not create a velocity floor: "+str(unit),rr.ok and _maxabs(rr.impulse)==0.0,rr)
	var final_assembly := R.bounds(raw.mobility,raw.free_slip,o.mass,raw.jacobian,o.z,raw.prescribed_slip_bias,o.responses)
	var retained := {proof=R.certificate(raw.mobility,raw.free_slip,raw.limits,raw.groups,zero,final_assembly),
		correlation_error_bound=final_assembly.correlation_error_bound,
		spd_congruence_error_bound=final_assembly.spd_congruence_error_bound,
		inverse_witness_residual=final_assembly.inverse_witness_residual,
		inverse_norm_bound=final_assembly.inverse_norm_bound,
		mobility_error=final_assembly.mobility_error,slip_error=final_assembly.slip_error}
	print("ASSEMBLY_PROOF ",JSON.stringify(retained.proof,"",true,true)," corr=",final_assembly.correlation_error_bound)
	print("GP-12 assembly resolution: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
