## GP-12: opt-in operand-qualified contact assembly resolution.
## Operand-qualified binary64 contact assembly bounds and a DISTINCT
## epsilon-optimality certificate; this never claims strict original KKT.
extends RefCounted

const GC := preload("res://physics/generalized_coordinates.gd")
const M := preload("res://physics/math3d.gd")
const QP := preload("res://physics/ground_traction.gd")
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
	if not is_finite(maximum_resolution_j) or maximum_resolution_j < 0.0:
		return _failure("explicit finite nonnegative owner resolution budget required")
	var strict := QP.solve(a, v, limits, groups, iteration_budget)
	if strict.ok: return strict
	if strict.get("status", "") != "nonconverged": return strict
	var assembly := bounds(a, v, mass_matrix, jacobian, z, bias, responses)
	if not assembly.ok: return assembly
	var zero := PackedFloat64Array()
	zero.resize(v.size())
	var resolved := certificate(a, v, limits, groups, zero, assembly)
	if not resolved.ok or resolved.assembly_objective_resolution_j > maximum_resolution_j:
		strict.assembly_resolution = resolved
		strict.assembly_resolution_budget_j = maximum_resolution_j
		return strict
	var validated := QP._validate_psd(a, v.size())
	var h := PackedFloat64Array()
	var b := PackedFloat64Array()
	var scale := 0.0
	for i in v.size():
		b.append(limits[i]*v[i])
		scale = maxf(scale, absf(b[i]))
		for j in v.size():
			var value: float = validated.correlation[i*v.size()+j] \
				*(limits[i]*validated.diagonal_roots[i])*(limits[j]*validated.diagonal_roots[j])
			h.append(value)
			scale = maxf(scale, absf(value))
	resolved.strict_failure = strict.duplicate(true)
	resolved.assembly_resolution_budget_j = maximum_resolution_j
	resolved.correlation_error_bound = assembly.correlation_error_bound
	return QP._publish(validated.matrix, v, limits, groups, h, b, zero,
		scale if scale > 0.0 else 1.0, validated, strict.get("iterations",0),
		"minimum_impulse_at_verified_assembly_resolution", resolved)


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
	for i in w:
		for j in w:
			if mass_matrix[i*w+j] != mass_matrix[j*w+i]: return _failure("mass matrix is not symmetric")
	var factor := GC.cholesky_factor(mass_matrix, w)
	if not factor.ok: return _failure("mass matrix is not qualified SPD")
	var spd := _spd_margin(mass_matrix,factor.lower,w)
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
				var term := mass_matrix[i*w+k] * inverse[k*w+j]
				if not is_finite(term): return _failure("inverse product overflow")
				value += term
				magnitude = _add(magnitude,_mul(absf(mass_matrix[i*w+k]),absf(inverse[k*w+j])))
			error_row = _add(error_row,_add(absf(value),_roundoff(magnitude,2*w+4)))
		inverse_norm = maxf(inverse_norm, norm_row)
		inverse_residual = maxf(inverse_residual, error_row)
	if not is_finite(inverse_residual) or inverse_residual >= 1.0:
		return _failure("inverse witness cannot bound true mass inverse")
	var inverse_bound := _div(inverse_norm,_one_minus(inverse_residual))
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
	return {ok = gap_upper <= resolution, law = LAW,
		strict_kkt_claim = false, certificate_contract = "assembled-objective-epsilon-optimality",
		original_dual_gap_j = dual_gap, true_objective_gap_upper_j = gap_upper,
		assembly_objective_resolution_j = resolution,
		gradient_uncertainty_gap_j = allowance, capacities_unchanged = true}
