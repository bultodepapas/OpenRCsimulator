## GP-12: opt-in operand-qualified contact assembly resolution.
## Operand-qualified binary64 contact assembly bounds and a DISTINCT
## epsilon-optimality certificate; this never claims strict original KKT.
extends RefCounted

const GC := preload("res://physics/generalized_coordinates.gd")
const M := preload("res://physics/math3d.gd")
const QP := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-gentle-qp-review/source/traction_null.gd")
const EPS := 2.220446049250313e-16
const ETA := M.MIN_NORMAL_FLOAT64*EPS
const LAW := "verified-contact-assembly-objective-resolution-v1"


## Explicit opt-in ONLY. maximum_resolution_j is an owner's upper energy
## budget: it cannot increase the operand-derived uncertainty or certificate.
## Pure QP.solve remains unchanged and strict. Try exact zero to avoid creating
## gratuitous null circulation when strict optimization is unresolvable.
static func solve(a: PackedFloat64Array, v: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, mass_matrix: PackedFloat64Array, jacobian: PackedFloat64Array,
		z: PackedFloat64Array, bias: PackedFloat64Array, responses: PackedFloat64Array,
		maximum_resolution_j: float, iteration_budget: int = QP.MAX_ITERATIONS) -> Dictionary:
	return _solve_core(a,v,limits,groups,mass_matrix,jacobian,z,bias,responses,maximum_resolution_j,iteration_budget,false,{})


## Detached accounting, used by the separate bounded-probe strategy. A proof
## screen can skip costly witnesses; it NEVER substitutes for final admission.
static func _solve_with_work(a:PackedFloat64Array,v:PackedFloat64Array,limits:PackedFloat64Array,groups:Array,
		mass_matrix:PackedFloat64Array,jacobian:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,
		responses:PackedFloat64Array,maximum_resolution_j:float,iteration_budget:int,proof_screen:bool,memo:Dictionary={},allow_unresolved_descent:bool=false)->Dictionary:
	var work:={qp={},range_proposal_calls=0,work_candidate_calls=0,strict_publication_calls=0,assembly_witness_builds=0,assembly_certificates=0}
	var before_builds:=int(memo.get("builds",0))
	var result:=_solve_core(a,v,limits,groups,mass_matrix,jacobian,z,bias,responses,maximum_resolution_j,iteration_budget,proof_screen,work,memo,allow_unresolved_descent)
	work.assembly_witness_requests=work.assembly_witness_builds
	work.assembly_witness_builds=int(memo.get("builds",0))-before_builds
	return {result=result,work=work}


static func _solve_core(a:PackedFloat64Array,v:PackedFloat64Array,limits:PackedFloat64Array,groups:Array,
		mass_matrix:PackedFloat64Array,jacobian:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,
		responses:PackedFloat64Array,maximum_resolution_j:float,iteration_budget:int,proof_screen:bool,account:Dictionary,memo:Dictionary={},allow_unresolved_descent:bool=false)->Dictionary:
	if not is_finite(maximum_resolution_j) or maximum_resolution_j < 0.0:
		return _failure("explicit finite nonnegative owner resolution budget required")
	var strict:Dictionary
	if account.is_empty():strict=QP._solve_for_assembly(a,v,limits,groups,iteration_budget)
	else:
		var packet:=QP._solve_for_assembly_with_work(a,v,limits,groups,iteration_budget,allow_unresolved_descent)
		strict=packet.result
		account.qp=packet.work
	if strict.ok:return strict
	if strict.get("status","")!="nonconverged":return strict
	var assembly:Dictionary={}
	var strict_diagnostic:=strict.duplicate(true)
	strict_diagnostic.erase("numerical_candidate")
	var candidates:Array[PackedFloat64Array]=[]
	var zero:=PackedFloat64Array()
	zero.resize(v.size())
	candidates.append(zero)
	if strict.has("numerical_candidate"):
		var retained:Variant=strict.numerical_candidate.get("normalized_impulse")
		if typeof(retained)==TYPE_PACKED_FLOAT64_ARRAY and retained.size()==v.size() and _finite(retained):
			candidates.append(retained.duplicate())
	var validated:=QP._validate_psd(a,v.size())
	var h:=PackedFloat64Array()
	var b:=PackedFloat64Array()
	var scale:=0.0
	for i in v.size():
		b.append(limits[i]*v[i])
		scale=maxf(scale,absf(b[i]))
		for j in v.size():
			var value:float=validated.correlation[i*v.size()+j] \
				*(limits[i]*validated.diagonal_roots[i])*(limits[j]*validated.diagonal_roots[j])
			h.append(value)
			scale=maxf(scale,absf(value))
	var hs:=h.duplicate()
	var bs:=b.duplicate()
	for i in hs.size():hs[i]/=scale if scale>0.0 else 1.0
	for i in bs.size():bs[i]/=scale if scale>0.0 else 1.0
	if not account.is_empty():account.range_proposal_calls+=1
	var range_trial:=QP._range_proposal(hs,bs,limits,groups)
	if not range_trial.is_empty():candidates.append(range_trial)
	var last_proof:={}
	for choice in candidates.size():
		var method:="minimum_impulse_at_verified_assembly_resolution" if choice==0 else "strict_iterate_at_verified_assembly_resolution"
		if choice==candidates.size()-1 and not range_trial.is_empty():method="rank_range_trial_at_verified_assembly_resolution"
		if not account.is_empty():account.work_candidate_calls+=1
		var work:=QP._work_candidate(validated.matrix,v,limits,groups,h,b,candidates[choice],
			scale if scale>0.0 else 1.0,validated,strict.get("iterations",0),method)
		if not work.ok:continue
		if work.raw_certificate.ok:
			# A proposal may recover ORIGINAL strict acceptance without needing
			# any numerical epsilon budget. The strict publisher rechecks it.
			if not account.is_empty():account.strict_publication_calls+=1
			return QP._publish(validated.matrix,v,limits,groups,h,b,work.normalized_impulse,
				scale if scale>0.0 else 1.0,validated,strict.get("iterations",0),"range_trial_with_original_strict_KKT")
		if proof_screen and (not is_finite(work.duality_gap) or work.duality_gap>maximum_resolution_j):continue
		if assembly.is_empty():
			if not account.is_empty():account.assembly_witness_builds+=1
			assembly=_memo_bounds(memo,a,v,mass_matrix,jacobian,z,bias,responses)
			if not assembly.ok:return assembly
		# This is the FINAL physical impulse AFTER any existing feasibility
		# roundoff projection. Never certify a pre-projection y and publish p'.
		var final_bytes:=var_to_bytes(work.impulse)
		if not account.is_empty():
			account.assembly_certificates+=1
			account.assembly_witness_builds+=1
		var proof:=_certificate_verified(a,v,limits,groups,work.impulse,assembly)
		last_proof=proof
		if not proof.get("ok",false) or proof.assembly_objective_resolution_j>maximum_resolution_j:continue
		if proof.certified_impulse_sha256!=impulse_digest(work.impulse):
			return _failure("final impulse differs from certified physical bytes")
		proof.strict_failure=strict_diagnostic.duplicate(true)
		proof.assembly_resolution_budget_j=maximum_resolution_j
		proof.correlation_error_bound=assembly.correlation_error_bound
		if strict.has("numerical_candidate"):
			proof.failed_candidate_raw_certificate=strict.numerical_candidate.raw_certificate.duplicate(true)
		work.status="converged_at_assembly_resolution"
		work.converged=true
		work.certificate_kind=LAW
		work.strict_kkt_passed=bool(work.raw_certificate.ok)
		work.erase("raw_certificate")
		work.assembly_resolution=proof
		if final_bytes!=var_to_bytes(work.impulse):return _failure("post-certificate impulse mutation")
		return work
	strict_diagnostic.assembly_resolution=last_proof
	strict_diagnostic.assembly_resolution_budget_j=maximum_resolution_j
	return strict_diagnostic


static func impulse_digest(impulse:PackedFloat64Array)->String:
	var hash:=HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK:return ""
	if hash.update(var_to_bytes(impulse))!=OK:return ""
	return hash.finish().hex_encode()


## Independent absolute roundoff bound for the two actual post-slip paths:
## J*fl(z+delta)+bias versus fl(v+A*p). If r_c=M*delta-g and
## r_j=M*x_j-J_j^T, then M*(delta-sum(x_j*p_j))
## = r_c+(g-J^T*p)-sum(r_j*p_j). Each row J_i*M^-1 is the
## transposed verified basis response x_i, since true M is symmetric SPD.
## No vanished result, fixed velocity floor, or unrelated shaft energy sets
## this bound. Numerical work-equivalent uncertainty is sum(|p_i|*bound_i).
static func slip_consistency(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,
		j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,
		p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array)->Dictionary:
	var assembly:=bounds(a,v,mass,j,z,bias,responses)
	if not assembly.ok:return assembly
	return _slip_verified(a,v,mass,j,z,bias,responses,p,g,delta,post,assembly)


static func _slip_verified(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,
		j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,
		p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array,assembly:Dictionary)->Dictionary:
	var n:=v.size()
	var w:=z.size()
	if p.size()!=n or post.size()!=n or g.size()!=w or delta.size()!=w \
		or not _finite(p) or not _finite(post) or not _finite(g) or not _finite(delta):
		return _failure("invalid independent slip operands")
	var combined:=PackedFloat64Array()
	var combined_error:=PackedFloat64Array()
	var column_residual:=PackedFloat64Array()
	var column_error:=PackedFloat64Array()
	column_residual.resize(n*w)
	column_error.resize(n*w)
	var next:=z.duplicate()
	var addition_error:=PackedFloat64Array()
	for i in w:
		var generated:=0.0
		var generated_magnitude:=0.0
		for row in n:
			generated+=j[row*w+i]*p[row]
			generated_magnitude=_add(generated_magnitude,_mul(absf(j[row*w+i]),absf(p[row])))
		if var_to_bytes(generated)!=var_to_bytes(g[i]):return _failure("combined impulse does not match exact declared dot operands")
		var value:float=-g[i]
		var magnitude:=absf(g[i])
		for k in w:
			value+=mass[i*w+k]*delta[k]
			magnitude=_add(magnitude,_mul(absf(mass[i*w+k]),absf(delta[k])))
		if not is_finite(value) or absf(value)>_roundoff(magnitude,16*w+32):
			return _failure("actual combined response is not a qualified backward-stable solve")
		combined.append(value)
		combined_error.append(_add(_roundoff(magnitude,2*w+4),_roundoff(generated_magnitude,2*n+4)))
		next[i]+=delta[i]
		addition_error.append(_roundoff(_add(absf(z[i]),absf(delta[i])),1))
		for row in n:
			value=-j[row*w+i]
			magnitude=absf(j[row*w+i])
			for k in w:
				value+=mass[i*w+k]*responses[row*w+k]
				magnitude=_add(magnitude,_mul(absf(mass[i*w+k]),absf(responses[row*w+k])))
			column_residual[row*w+i]=value
			column_error[row*w+i]=_roundoff(magnitude,2*w+4)
	if not _finite(next) or not _finite(column_residual) or not _finite(column_error):return _failure("slip response residual overflow")
	var superposition:=PackedFloat64Array()
	for i in w:
		var center:=combined[i]
		var magnitude:=absf(center)
		var error:=combined_error[i]
		for row in n:
			center-=column_residual[row*w+i]*p[row]
			magnitude=_add(magnitude,_mul(absf(column_residual[row*w+i]),absf(p[row])))
			error=_add(error,_mul(column_error[row*w+i],absf(p[row])))
		superposition.append(_add(absf(center),_add(error,_roundoff(magnitude,2*n+4))))
	var row_bounds:=PackedFloat64Array()
	var differences:=PackedFloat64Array()
	var references:=PackedFloat64Array()
	var energy_bound:=0.0
	var consistent:=true
	for row in n:
		var predicted:=0.0
		var predicted_magnitude:=0.0
		for other in n:
			var symmetric:float=.5*a[row*n+other]+.5*a[other*n+row]
			predicted+=symmetric*p[other]
			predicted_magnitude=_add(predicted_magnitude,_mul(absf(symmetric),absf(p[other])))
		predicted+=v[row]
		predicted_magnitude=_add(predicted_magnitude,absf(v[row]))
		if var_to_bytes(predicted)!=var_to_bytes(post[row]):return _failure("QP post slip is not bound to original mobility operands")
		var direct:=bias[row]
		var direct_magnitude:=absf(bias[row])
		var reference:=_add(absf(bias[row]),predicted_magnitude)
		var bound:float=assembly.slip_error[row]
		for k in w:
			direct+=j[row*w+k]*next[k]
			direct_magnitude=_add(direct_magnitude,_mul(absf(j[row*w+k]),absf(next[k])))
			reference=_add(reference,_mul(absf(j[row*w+k]),_add(absf(z[k]),absf(delta[k]))))
			bound=_add(bound,_mul(absf(j[row*w+k]),addition_error[k]))
			# x_row^T bounds the exact projected inverse row, preserving the
			# physical sparsity of an external wheel-spin response port.
			bound=_add(bound,_mul(_add(absf(responses[row*w+k]),assembly.response_error[row*w+k]),superposition[k]))
		for other in n:
			var dot_magnitude:=0.0
			for k in w:dot_magnitude=_add(dot_magnitude,_mul(absf(j[row*w+k]),absf(responses[other*w+k])))
			# For scalar p^T A p the antisymmetric part cancels; for a ROW
			# of post slip it does not. Bound against the forward J*x row.
			var dot_error:=_roundoff(dot_magnitude,2*w+4)
			var sym_difference:=_mul(.5,absf(a[row*n+other]-a[other*n+row]))
			var average_error:=_roundoff(_add(absf(a[row*n+other]),absf(a[other*n+row])),8)
			bound=_add(bound,_mul(_add(dot_error,_add(sym_difference,average_error)),absf(p[other])))
		bound=_add(bound,_add(_roundoff(direct_magnitude,2*w+4),_roundoff(predicted_magnitude,2*n+4)))
		var difference:=absf(direct-post[row])
		if not is_finite(difference) or not is_finite(bound) or difference>bound:consistent=false
		row_bounds.append(bound)
		differences.append(difference)
		references.append(reference)
		energy_bound=_add(energy_bound,_mul(absf(p[row]),bound))
	if not _finite(row_bounds) or not _finite(differences) or not is_finite(energy_bound):return _failure("independent slip bound overflow")
	return {ok=consistent,law="verified-binary64-common-mass-post-slip-consistency-v1",
		row_absolute_bounds=row_bounds,row_absolute_differences=differences,uncancelled_operand_references=references,
		work_equivalent_bound_j=energy_bound,scope="post_slip_arithmetic_not_material_calibration_or_passivity_relaxation",
		inverse_witness_residual=assembly.inverse_witness_residual,certified_impulse_sha256=impulse_digest(p)}


static func _gamma(operations: int) -> float:
	# EPS is twice unit roundoff: conservative for separately rounded multiply/add.
	var numerator := float(operations)*EPS
	return _div(numerator,_one_minus(numerator))


# Positive interval arithmetic. Padding EVERY operation prevents an underflowed
# intermediate error bound later being amplified by a large inverse/row unit.
# ETA is IEEE binary64's minimum subnormal, an arithmetic rounding allowance;
# it is not a velocity/force floor. Overflow remains unsupported and refuses.
static func _add(a: float,b: float) -> float:
	if a<0.0 or b<0.0 or not is_finite(a) or not is_finite(b): return INF
	if a==0.0 and b==0.0: return 0.0
	return (a+b)*(1.0+4.0*EPS)+ETA


static func _mul(a: float,b: float) -> float:
	if a<0.0 or b<0.0 or not is_finite(a) or not is_finite(b): return INF
	if a==0.0 or b==0.0: return 0.0
	return (a*b)*(1.0+4.0*EPS)+ETA


static func _div(a: float,b: float) -> float:
	if a<0.0 or b<=0.0 or not is_finite(a) or not is_finite(b): return INF
	if a==0.0: return 0.0
	return (a/b)*(1.0+4.0*EPS)+ETA


static func _one_minus(a: float) -> float:
	if not is_finite(a) or a<0.0 or a>=1.0: return 0.0
	return maxf(0.0,(1.0-a)*(1.0-4.0*EPS)-ETA)


static func _roundoff(magnitude: float,operations: int) -> float:
	if magnitude==0.0: return 0.0
	return _add(_mul(_gamma(operations),magnitude),float(operations)*ETA)


static func _finite(a: PackedFloat64Array) -> bool:
	for v: float in a:
		if not is_finite(v): return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {ok = false, law = LAW, reason = reason}


## A floating Cholesky success alone does not prove true SPD. Construct an
## inverse-L witness Y and bound S=I-LY in BOTH induced norms. Then
## ||L^-1||inf <= ||Y||inf/(1-||S||inf), similarly for norm1.
## Bound E=M-LL^T from actual operands. If
## ||L^-1||inf ||E||inf ||L^-1||1 < 1, the symmetric congruence
## L^-1 M L^-T = I + L^-1 E L^-T has positive eigenvalues.
static func _spd_margin(matrix: PackedFloat64Array,lower: PackedFloat64Array,w: int) -> Dictionary:
	var y := PackedFloat64Array()
	y.resize(w*w)
	for col in w:
		for row in w:
			if not is_finite(lower[row*w+row]) or lower[row*w+row]<=0.0:
				return _failure("positive Cholesky witness diagonal required")
			var value := 1.0 if row==col else 0.0
			for k in row: value-=lower[row*w+k]*y[k*w+col]
			y[row*w+col]=value/lower[row*w+row]
	if not _finite(y): return _failure("inverse-L witness overflow")
	var s := PackedFloat64Array()
	s.resize(w*w)
	var e_norm := 0.0
	for i in w:
		var error_row := 0.0
		for j in w:
			var value := -1.0 if i==j else 0.0
			var magnitude := absf(value)
			var error := matrix[i*w+j]
			var error_magnitude := absf(error)
			for k in w:
				value+=lower[i*w+k]*y[k*w+j]
				magnitude=_add(magnitude,_mul(absf(lower[i*w+k]),absf(y[k*w+j])))
				error-=lower[i*w+k]*lower[j*w+k]
				error_magnitude=_add(error_magnitude,_mul(absf(lower[i*w+k]),absf(lower[j*w+k])))
			s[i*w+j]=_add(absf(value),_roundoff(magnitude,2*w+4))
			error_row=_add(error_row,_add(absf(error),_roundoff(error_magnitude,2*w+4)))
		e_norm=maxf(e_norm,error_row)
	var s_inf := 0.0
	var s_one := 0.0
	var y_inf := 0.0
	var y_one := 0.0
	for i in w:
		var si := 0.0
		var sj := 0.0
		var yi := 0.0
		var yj := 0.0
		for j in w:
			si=_add(si,s[i*w+j])
			sj=_add(sj,s[j*w+i])
			yi=_add(yi,absf(y[i*w+j]))
			yj=_add(yj,absf(y[j*w+i]))
		s_inf=maxf(s_inf,si)
		s_one=maxf(s_one,sj)
		y_inf=maxf(y_inf,yi)
		y_one=maxf(y_one,yj)
	if not is_finite(s_inf) or not is_finite(s_one) or s_inf>=1.0 or s_one>=1.0:
		return _failure("inverse-L witness cannot certify both norms")
	var margin := _mul(_mul(_div(y_inf,_one_minus(s_inf)),e_norm),_div(y_one,_one_minus(s_one)))
	if not is_finite(margin) or margin>=1.0:
		return _failure("true SPD congruence margin is unresolved")
	return {ok=true,congruence_error_bound=margin}


## All operands are mandatory, not caller-supplied error floors. X contains
## row-major response COLUMNS transposed: X[row*width+k]=(M^-1 J_row^T)[k].
## M is the full CM + angular common mass matrix, including every free rotor.
static func bounds(a: PackedFloat64Array, v: PackedFloat64Array, mass_matrix: PackedFloat64Array,
		jacobian: PackedFloat64Array, z: PackedFloat64Array, bias: PackedFloat64Array,
		responses: PackedFloat64Array) -> Dictionary:
	return _bounds_mass(a,v,mass_matrix,jacobian,z,bias,responses,null)

static func _bounds_mass(a:PackedFloat64Array,v:PackedFloat64Array,mass_matrix:PackedFloat64Array,
		jacobian:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,proof:RefCounted)->Dictionary:
	var n := v.size()
	var w := z.size()
	var gradual := ETA
	var one := 1.0
	var eta_bytes := PackedByteArray()
	eta_bytes.resize(8)
	eta_bytes.encode_double(0,ETA)
	if eta_bytes!=PackedByteArray([1,0,0,0,0,0,0,0]) or gradual*one!=ETA \
		or gradual+gradual<=gradual or one+EPS<=one or one+EPS*0.25!=one:
		return _failure("IEEE binary64 gradual-underflow arithmetic required")
	if n < 1 or n > QP.MAX_DIMENSION or w < 1 or w > 70 or a.size() != n*n \
		or mass_matrix.size() != w*w or jacobian.size() != n*w or responses.size() != n*w \
		or bias.size() != n or not _finite(a) or not _finite(v) or not _finite(mass_matrix) \
		or not _finite(jacobian) or not _finite(z) or not _finite(bias) or not _finite(responses):
		return _failure("invalid complete assembly operands")
	var mass_packet:Dictionary
	if proof is FixedMassProof and proof.matches(mass_matrix,w):mass_packet=proof._packet
	else:mass_packet=_mass_prefix(mass_matrix,w)
	if not mass_packet.ok:return mass_packet
	var inverse:PackedFloat64Array=mass_packet.inverse
	var inverse_residual:float=mass_packet.inverse_residual
	var inverse_bound:float=mass_packet.inverse_bound
	var spd:Dictionary=mass_packet.spd

	var response_error := PackedFloat64Array()
	response_error.resize(n*w)
	for j in n:
		var residual_components := PackedFloat64Array()
		var residual_bound := 0.0
		for i in w:
			var value := -jacobian[j*w+i]
			var magnitude := absf(value)
			for k in w:
				var term := mass_matrix[i*w+k] * responses[j*w+k]
				if not is_finite(term): return _failure("response residual overflow")
				value += term
				magnitude = _add(magnitude,_mul(absf(mass_matrix[i*w+k]),absf(responses[j*w+k])))
			# Reject an arbitrary inaccurate response instead of laundering it
			# into a large uncertainty. This gate only QUALIFIES the solve.
			if absf(value) > _roundoff(magnitude,16*w+32):
				return _failure("response does not qualify as a backward-stable solve")
			var component := _add(absf(value),_roundoff(magnitude,2*w+4))
			residual_components.append(component)
			residual_bound = maxf(residual_bound, component)
		for i in w:
			var bound := 0.0
			var row_norm := 0.0
			for k in w:
				bound = _add(bound,_mul(absf(inverse[i*w+k]),residual_components[k]))
				row_norm = _add(row_norm,absf(inverse[i*w+k]))
			# M^-1=X(I-R)^-1, hence |M^-1 r| <= |X||r|
			# + ||X_row||1 ||R||inf/(1-||R||inf) ||r||inf.
			bound = _add(bound,_mul(_div(_mul(row_norm,inverse_residual),_one_minus(inverse_residual)),residual_bound))
			response_error[j*w+i] = bound
	var dv := PackedFloat64Array()
	var da := PackedFloat64Array()
	da.resize(n*n)
	for i in n:
		var assembled := bias[i]
		var v_terms := absf(bias[i])
		for k in w:
			var term := jacobian[i*w+k]*z[k]
			if not is_finite(term) or (jacobian[i*w+k] != 0.0 and z[k] != 0.0 and term == 0.0):
				return _failure("free slip product exceeds normal numeric domain")
			assembled += term
			v_terms = _add(v_terms,_mul(absf(jacobian[i*w+k]),absf(z[k])))
		if assembled != v[i]: return _failure("free slip does not match declared dot operands")
		dv.append(_roundoff(v_terms,2*w+4))
		for j in n:
			var entry := 0.0
			var terms := 0.0
			for k in w:
				var term := jacobian[i*w+k]*responses[j*w+k]
				if not is_finite(term) or (jacobian[i*w+k] != 0.0 and responses[j*w+k] != 0.0 and term == 0.0):
					return _failure("mobility product exceeds normal numeric domain")
				entry += term
				terms = _add(terms,_mul(absf(jacobian[i*w+k]),absf(responses[j*w+k])))
			if entry != a[i*n+j]: return _failure("mobility does not match declared dot operands")
			var solve_error := 0.0
			for k in w: solve_error = _add(solve_error,_mul(absf(jacobian[i*w+k]),response_error[j*w+k]))
			da[i*n+j] = _add(_roundoff(terms,2*w+4),solve_error)
	# The QP uses the symmetric average. Include its arithmetic and every
	# antisymmetric assembly discrepancy in the declared true-Gram interval.
	var sym_error := da.duplicate()
	for i in n:
		for j in n:
			da[i*n+j] = _add(_add(_mul(0.5,sym_error[i*n+j]),_mul(0.5,sym_error[j*n+i])), \
				_add(_mul(0.5,absf(a[i*n+j]-a[j*n+i])), \
				_roundoff(_add(absf(a[i*n+j]),absf(a[j*n+i])),8)))
	if not _finite(da) or not _finite(dv) or not _finite(response_error): return _failure("assembly bound overflow")
	var correlation_error := 0.0
	for i in n:
		for j in n:
			if a[i*n+i] == 0.0 or a[j*n+j] == 0.0:
				if da[i*n+j] != 0.0: return _failure("zero mobility cannot qualify uncertain coupling")
			else:
				if a[i*n+i]<0.0 or a[j*n+j]<0.0:
					return _failure("negative mobility diagonal")
				var relative := _div(_div(da[i*n+j],M.sqrt_(a[i*n+i])*(1.0-4.0*EPS)),M.sqrt_(a[j*n+j])*(1.0-4.0*EPS))
				correlation_error = maxf(correlation_error, relative)
	if not is_finite(correlation_error) or correlation_error > QP.KKT_RELATIVE_TOLERANCE:
		return _failure("relative assembly uncertainty exceeds supported numerical contract")
	return {ok = true, law = LAW, mobility_error = da, slip_error = dv,
		inverse_norm_bound = inverse_bound, inverse_witness_residual = inverse_residual,
		response_error = response_error, correlation_error_bound = correlation_error,
		spd_congruence_error_bound=spd.congruence_error_bound, matrix_dimension = w, row_count = n,
		operands = {a=a.duplicate(),v=v.duplicate(),mass_matrix=mass_matrix.duplicate(),
			jacobian=jacobian.duplicate(),z=z.duplicate(),bias=bias.duplicate(),responses=responses.duplicate()}}


## DISTINCT finite-precision contract. For the true PSD Gram objective, the
## compact feasible dual gap plus interval gradient allowance bounds objective
## suboptimality. Accept only at the independently computed uniform uncertainty
## of that objective over the ORIGINAL compact feasible set. This is neither
## strict KKT success nor a claim that the candidate is an exact optimum.
static func certificate(a: PackedFloat64Array, v: PackedFloat64Array, limits: PackedFloat64Array,
		groups: Array, impulse: PackedFloat64Array, assembly: Dictionary) -> Dictionary:
	var n := v.size()
	if not assembly.get("ok", false) or limits.size() != n or impulse.size() != n:
		return _failure("missing qualified assembly bounds")
	# A dictionary is not an opaque capability. Re-derive, never trust a caller's
	# precomputed uncertainty floats, and bind the exact original A/v bytes.
	var source: Variant = assembly.get("operands")
	if typeof(source) != TYPE_DICTIONARY or source.size()!=7 \
		or not source.has_all(["a","v","mass_matrix","jacobian","z","bias","responses"]):
		return _failure("complete assembly operands required at recertification")
	for value: Variant in source.values():
		if typeof(value)!=TYPE_PACKED_FLOAT64_ARRAY: return _failure("invalid recertification operand type")
	if var_to_bytes(source.a)!=var_to_bytes(a) or var_to_bytes(source.v)!=var_to_bytes(v):
		return _failure("certificate is not bound to original matrix and free slip")
	assembly=bounds(source.a,source.v,source.mass_matrix,source.jacobian,source.z,source.bias,source.responses)
	if not assembly.ok: return assembly
	return _certificate_verified(a,v,limits,groups,impulse,assembly)


static func _certificate_verified(a:PackedFloat64Array,v:PackedFloat64Array,limits:PackedFloat64Array,
		groups:Array,impulse:PackedFloat64Array,assembly:Dictionary)->Dictionary:
	var n:=v.size()
	var verified := QP._validate_psd(a, n)
	if not verified.ok: return verified
	var da: PackedFloat64Array = assembly.mobility_error
	var dv: PackedFloat64Array = assembly.slip_error
	if da.size() != n*n or dv.size() != n or not _finite(limits) or not _finite(impulse):
		return _failure("invalid certificate inputs")
	var gradient := GC.matrix_vector(verified.matrix, impulse, n)
	var uncertainty := 0.0
	var evaluation := 0.0
	var allowance := 0.0
	for i in n:
		if limits[i] < 0.0: return _failure("negative capacity")
		gradient[i] += v[i]
		var dg := dv[i]
		var mag := absf(v[i])
		uncertainty = _add(uncertainty,_mul(limits[i],dv[i]))
		for j in n:
			dg = _add(dg,_mul(da[i*n+j],absf(impulse[j])))
			mag = _add(mag,_mul(absf(verified.matrix[i*n+j]),absf(impulse[j])))
			uncertainty = _add(uncertainty,_mul(_mul(_mul(0.5,limits[i]),da[i*n+j]),limits[j]))
		dg = _add(dg,_roundoff(mag,2*n+4))
		allowance = _add(allowance,_mul(dg,_add(limits[i],absf(impulse[i]))))
	var dual_gap := 0.0
	var seen := PackedByteArray()
	seen.resize(n)
	for group: Variant in groups:
		if typeof(group) != TYPE_PACKED_INT32_ARRAY or group.size() not in [1,2]: return _failure("invalid groups")
		var length := 0.0
		var support := 0.0
		var gp := 0.0
		var gp_magnitude := 0.0
		var support_magnitude := 0.0
		for i: int in group:
			if i < 0 or i >= n or seen[i] != 0: return _failure("invalid group partition")
			seen[i] = 1
			if limits[i] == 0.0:
				if impulse[i] != 0.0: return _failure("zero authority has impulse")
			elif group.size()==1:
				# For a binary64 interval endpoint this comparison is exact; an
				# outward divided/squared upper bound cannot prove equality.
				if absf(impulse[i])>limits[i]:return _failure("original interval capacity exceeded")
			else:
				var ratio := _div(absf(impulse[i]),limits[i])
				length = _add(length,_mul(ratio,ratio))
			support = QP._hypot(support, limits[i]*gradient[i])
			gp += impulse[i]*gradient[i]
			gp_magnitude = _add(gp_magnitude,_mul(absf(impulse[i]),absf(gradient[i])))
			support_magnitude = _add(support_magnitude,_mul(limits[i],absf(gradient[i])))
		if length > 1.0: return _failure("original capacity exceeded")
		dual_gap = _add(dual_gap,maxf(0.0,gp+support))
		evaluation = _add(evaluation,_roundoff(_add(gp_magnitude,support_magnitude),24))
	for i in n:
		if not seen[i]: return _failure("incomplete groups")
	var gap_upper := _add(_add(dual_gap,allowance),evaluation)
	var resolution := uncertainty
	if not is_finite(gap_upper) or not is_finite(resolution): return _failure("certificate overflow")
	var fingerprint:=impulse_digest(impulse)
	if fingerprint.length()!=64:return _failure("exact final impulse byte binding unavailable")
	return {ok = gap_upper <= resolution, law = LAW,
		strict_kkt_claim = false, certificate_contract = "assembled-objective-epsilon-optimality",
		original_dual_gap_j = dual_gap, true_objective_gap_upper_j = gap_upper,
		assembly_objective_resolution_j = resolution,
		gradient_uncertainty_gap_j = allowance, capacities_unchanged = true,
		certified_impulse_sha256=fingerprint}

## Error-free sum under the same verified IEEE binary64 round-to-nearest,
## finite/no-overflow and gradual-underflow contract used by bounds(). The
## returned low part satisfies a+b = high+low as REAL numbers; no state edit.
static func two_sum(a:float,b:float)->PackedFloat64Array:
	if not is_finite(a) or not is_finite(b):return PackedFloat64Array()
	var high:=a+b
	if not is_finite(high):return PackedFloat64Array()
	var bv:=high-a
	var av:=high-bv
	var br:=b-bv
	var ar:=a-av
	var low:=ar+br
	if not _finite(PackedFloat64Array([bv,av,br,ar,low])):return PackedFloat64Array()
	return PackedFloat64Array([high,low])


## A distinct arithmetic consistency certificate, NOT a physical work floor.
## All reported scalars are bound to the actual repeated dot/add path. Original
## caps/QP passivity remain separate. The published next-state energy is also
## bounded independently, including error-free recovered velocity additions.
static func work_consistency(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,
		j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,
		p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array,
		affine_momentum:PackedFloat64Array,objective:float,incremental:float,closure:float)->Dictionary:
	var assembly:=bounds(a,v,mass,j,z,bias,responses)
	if not assembly.ok:return assembly
	return _work_verified(a,v,mass,j,z,bias,responses,p,g,delta,post,affine_momentum,objective,incremental,closure,assembly)


static func _work_verified(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,
		j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,
		p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array,
		affine_momentum:PackedFloat64Array,objective:float,incremental:float,closure:float,assembly:Dictionary)->Dictionary:
	var n:=v.size()
	var w:=z.size()
	if affine_momentum.size()!=w-3 or not _finite(affine_momentum) \
		or not is_finite(objective) or not is_finite(incremental) or not is_finite(closure) or objective>0.0:
		return _failure("invalid work consistency operands or nonpassive QP")
	var slip:=_slip_verified(a,v,mass,j,z,bias,responses,p,g,delta,post,assembly)
	if not slip.get("ok",false):return slip
	var validated:=QP._validate_psd(a,n)
	if not validated.ok:return validated
	var symmetric:PackedFloat64Array=validated.matrix
	var ap:=GC.matrix_vector(symmetric,p,n)
	var qlinear:=0.0
	var qquadratic:=0.0
	var qlinear_mag:=0.0
	var qquadratic_mag:=0.0
	var exact_identity_bound:=0.0
	for row in n:
		qlinear+=v[row]*p[row]
		qquadratic+=.5*p[row]*ap[row]
		qlinear_mag=_add(qlinear_mag,_mul(absf(v[row]),absf(p[row])))
		var rowmag:=0.0
		for other in n:rowmag=_add(rowmag,_mul(absf(symmetric[row*n+other]),absf(p[other])))
		qquadratic_mag=_add(qquadratic_mag,_mul(_mul(.5,absf(p[row])),rowmag))
		exact_identity_bound=_add(exact_identity_bound,_mul(_mul(.5,absf(p[row])),
			_add(slip.row_absolute_bounds[row],assembly.slip_error[row])))
	if var_to_bytes(qlinear+qquadratic)!=var_to_bytes(objective):return _failure("work objective is not bound to original evaluated operands")
	var linear:=GC.dot(z,g,w)
	var quadratic:=.5*GC.dot(g,delta,w)
	var affine:=GC.dot(affine_momentum,delta.slice(3),w-3)
	var bias_work:=-GC.dot(bias,p,n)
	var expected_incremental:=linear+quadratic+affine
	var expected_closure:=expected_incremental-objective-(affine+bias_work)
	if var_to_bytes(expected_incremental)!=var_to_bytes(incremental) or var_to_bytes(expected_closure)!=var_to_bytes(closure):
		return _failure("work receipt is not bound to actual incremental dot/add path")
	var linear_mag:=0.0
	var quadratic_mag:=0.0
	var bias_mag:=0.0
	var mass_work_bound:=0.0
	var next:=z.duplicate()
	var update:=PackedFloat64Array()
	for i in w:
		linear_mag=_add(linear_mag,_mul(absf(z[i]),absf(g[i])))
		quadratic_mag=_add(quadratic_mag,_mul(_mul(.5,absf(g[i])),absf(delta[i])))
		var gm:=0.0
		for row in n:gm=_add(gm,_mul(absf(j[row*w+i]),absf(p[row])))
		exact_identity_bound=_add(exact_identity_bound,_mul(_add(absf(z[i]),_mul(.5,absf(delta[i]))),_roundoff(gm,2*n+4)))
		var residual:float=-g[i]
		var magnitude:=absf(g[i])
		for k in w:
			residual+=mass[i*w+k]*delta[k]
			magnitude=_add(magnitude,_mul(absf(mass[i*w+k]),absf(delta[k])))
		mass_work_bound=_add(mass_work_bound,_mul(_add(absf(z[i]),_mul(.5,absf(delta[i]))),
			_add(absf(residual),_roundoff(magnitude,2*w+4))))
		var sum:=two_sum(z[i],delta[i])
		if sum.size()!=2:return _failure("state addition cannot meet finite TwoSum contract")
		next[i]=sum[0]
		update.append(-sum[1])
	for row in n:bias_mag=_add(bias_mag,_mul(absf(bias[row]),absf(p[row])))
	var direct_error:=_add(_roundoff(linear_mag,2*w+4),_roundoff(quadratic_mag,2*w+6))
	var bias_error:=_roundoff(bias_mag,2*n+4)
	var qp_error:=_add(_add(_roundoff(qlinear_mag,2*n+4),_roundoff(qquadratic_mag,4*n+8)),
		_roundoff(_add(absf(qlinear),absf(qquadratic)),1))
	var outer_magnitude:=_add(_add(absf(linear),absf(quadratic)),
		_add(_mul(2.0,absf(affine)),_add(absf(objective),absf(bias_work))))
	var closure_bound:=_add(exact_identity_bound,_add(qp_error,_add(direct_error,_add(bias_error,_roundoff(outer_magnitude,12)))))
	# Exact actual-state correction: e=next-z-delta (TwoSum low sign),
	# K(next)-K(z+delta)=next^T M e-.5 e^T M e. Include constant carrier
	# affine momentum against e, since prescribed_work used the original delta.
	var me:=GC.matrix_vector(mass,update,w)
	var update_work:=GC.dot(next,me,w)-.5*GC.dot(update,me,w)+GC.dot(affine_momentum,update.slice(3),w-3)
	var update_error:=0.0
	var update_mag:=0.0
	for i in w:
		var rowmag:=0.0
		for k in w:rowmag=_add(rowmag,_mul(absf(mass[i*w+k]),absf(update[k])))
		update_error=_add(update_error,_mul(_add(absf(next[i]),_mul(.5,absf(update[i]))),_roundoff(rowmag,2*w+4)))
		update_mag=_add(update_mag,_mul(_add(absf(next[i]),_mul(.5,absf(update[i]))),absf(me[i])))
		if i>=3:update_mag=_add(update_mag,_mul(absf(affine_momentum[i-3]),absf(update[i])))
	update_error=_add(update_error,_roundoff(update_mag,4*w+12))
	var ideal_relative_work:=linear+quadratic-bias_work
	var relative_error:=_add(direct_error,_add(bias_error,_roundoff(_add(_add(absf(linear),absf(quadratic)),absf(bias_work)),4)))
	var physical_work:=ideal_relative_work+update_work
	var physical_error:=_add(mass_work_bound,_add(relative_error,_add(update_error,
		_roundoff(_add(absf(ideal_relative_work),absf(update_work)),1))))
	physical_error=_add(physical_error,_roundoff(_add(absf(physical_work),physical_error),4))
	var physical_upper:=physical_work+physical_error
	# Charge the full state-addition correction magnitude as well as its error.
	# This keeps genuine tiny positive work distinguishable from algebraic proof.
	var work_charge:=_add(closure_bound,_add(absf(update_work),physical_error))
	if not _finite(PackedFloat64Array([closure_bound,work_charge,physical_work,physical_error,physical_upper,update_work])):
		return _failure("work consistency bound overflow")
	return {ok=absf(closure)<=closure_bound and physical_upper<=0.0,
		law="verified-binary64-common-mass-work-consistency-actual-state-passivity-v1",
		raw_closure_j=closure,closure_absolute_bound_j=closure_bound,work_equivalent_bound_j=work_charge,
		actual_relative_work_j=physical_work,actual_relative_work_error_j=physical_error,
		actual_relative_work_upper_j=physical_upper,state_addition_work_j=update_work,
		state_addition_work_error_j=update_error,mass_response_work_bound_j=mass_work_bound,
		certified_impulse_sha256=impulse_digest(p),state_addition_residual=update,
		scope="arithmetic_consistency_and_nonpositive_actual_state_work_not_a_material_tolerance"}

static func _memo_bounds(memo:Dictionary,a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array)->Dictionary:
	var source:=var_to_bytes([a,v,mass,j,z,bias,responses])
	if memo.has("source") and memo.source==source:return memo.assembly
	# A different operand never hits an old witness. This object is fresh local
	# call-chain data and never returned or accepted by a public API.
	var verified:=_bounds_mass(a,v,mass,j,z,bias,responses,memo.get("mass_proof"))
	memo.source=source
	memo.assembly=verified
	memo.builds=int(memo.get("builds",0))+1
	return verified

static func _solve_local(a:PackedFloat64Array,v:PackedFloat64Array,d:PackedFloat64Array,groups:Array,mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,ceiling:float,budget:int,memo:Dictionary)->Dictionary:
	return _solve_core(a,v,d,groups,mass,j,z,bias,responses,ceiling,budget,false,{},memo)

static func _slip_local(memo:Dictionary,a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array)->Dictionary:
	var verified:=_memo_bounds(memo,a,v,mass,j,z,bias,responses)
	if not verified.ok:return verified
	return _slip_verified(a,v,mass,j,z,bias,responses,p,g,delta,post,verified)

static func _work_local(memo:Dictionary,a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array,affine:PackedFloat64Array,objective:float,incremental:float,closure:float)->Dictionary:
	var verified:=_memo_bounds(memo,a,v,mass,j,z,bias,responses)
	if not verified.ok:return verified
	return _work_verified(a,v,mass,j,z,bias,responses,p,g,delta,post,affine,objective,incremental,closure,verified)


## Opaque locally prepared proof, owned by the trusted read-only model owner.
## Its private packet is never accepted from an arbitrary caller dictionary.
## There is no global cache. A complete matrix-byte/width mismatch recomputes
## the original prefix; all J/z/A/response arithmetic is always recomputed.
class FixedMassProof extends RefCounted:
	var _matrix_bytes:PackedByteArray
	var _width:int=0
	var _packet:Dictionary={}
	func matches(matrix:PackedFloat64Array,w:int)->bool:
		return w==_width and matrix.to_byte_array()==_matrix_bytes and _packet.get("ok",false)

static func prepare_mass(matrix:PackedFloat64Array,w:int)->Dictionary:
	if w<1 or w>70 or matrix.size()!=w*w or not _finite(matrix):return _failure("invalid prepared mass matrix")
	var packet:=_mass_prefix(matrix,w)
	if not packet.ok:return packet
	var proof:=FixedMassProof.new()
	proof._matrix_bytes=matrix.to_byte_array()
	proof._width=w
	proof._packet=packet
	return {ok=true,proof=proof}

static func _mass_prefix(matrix:PackedFloat64Array,w:int)->Dictionary:
	for i in w:
		for j in w:
			if matrix[i*w+j] != matrix[j*w+i]: return _failure("mass matrix is not symmetric")
	var factor := GC.cholesky_factor(matrix, w)
	if not factor.ok: return _failure("mass matrix is not qualified SPD")
	var spd := _spd_margin(matrix,factor.lower,w)
	if not spd.ok: return spd
	# Inverse witness with an explicitly bounded ||I-M X||_infinity. The
	# Neumann-series theorem then bounds the TRUE inverse, not merely X.
	var inverse := PackedFloat64Array()
	inverse.resize(w*w)
	for col in w:
		var rhs := PackedFloat64Array()
		rhs.resize(w)
		rhs[col] = 1.0
		var solved := GC.solve_cholesky(factor.lower, rhs, w)
		if solved.size() != w or not _finite(solved): return _failure("inverse witness failed")
		for row in w: inverse[row*w+col] = solved[row]
	var inverse_norm := 0.0
	var inverse_residual := 0.0
	for i in w:
		var norm_row := 0.0
		var error_row := 0.0
		for j in w:
			norm_row = _add(norm_row,absf(inverse[i*w+j]))
			var value := -1.0 if i == j else 0.0
			var magnitude := absf(value)
			for k in w:
				var term := matrix[i*w+k] * inverse[k*w+j]
				if not is_finite(term): return _failure("inverse product overflow")
				value += term
				magnitude = _add(magnitude,_mul(absf(matrix[i*w+k]),absf(inverse[k*w+j])))
			error_row = _add(error_row,_add(absf(value),_roundoff(magnitude,2*w+4)))
		inverse_norm = maxf(inverse_norm, norm_row)
		inverse_residual = maxf(inverse_residual, error_row)
	if not is_finite(inverse_residual) or inverse_residual >= 1.0:
		return _failure("inverse witness cannot bound true mass inverse")
	var inverse_bound := _div(inverse_norm,_one_minus(inverse_residual))
	return {ok=true,inverse=inverse,inverse_residual=inverse_residual,inverse_bound=inverse_bound,spd=spd}

