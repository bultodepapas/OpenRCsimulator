# D8b-R2: optional, explicit finite-wing strip-reference polar. No inferred aircraft calibration.
# Both branches store positive angle/lift magnitudes, profile CD and attached fraction.
# The negative-side sign is applied at evaluation; the branches need not be symmetric.
# Shape-preserving cubic interpolation; exact attached and periodic flat-plate continuations.
extends RefCounted
const Timing:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/metrics.gd")

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-hotspot-review/timed/physics/math3d.gd")
const METHOD := "tabulated-wing-v1"
const STRIDE := 4


## Prepare one branch. Inputs have already passed quantity/type validation in AircraftData.
## The values describe uniform geometric incidence, not a measured 2-D section polar.
static func prepare(samples: PackedFloat64Array, side: float, slope: float, offset: float,
		cd0: float, cd90: float, errors: PackedStringArray, label: String) -> Dictionary:
	var n := samples.size() / STRIDE
	if samples.size() % STRIDE != 0 or n < 4 or n > 64:
		errors.append(label + ": expected 4..64 [angle magnitude deg, lift magnitude, profile CD, attached fraction] rows")
		return {}
	var x := PackedFloat64Array()
	var values := PackedFloat64Array()
	for i in n:
		var angle := deg_to_rad(samples[STRIDE*i])
		var cl := samples[STRIDE*i+1]
		var cd := samples[STRIDE*i+2]
		var fraction := samples[STRIDE*i+3]
		if not is_finite(angle) or not is_finite(cl) or not is_finite(cd) or not is_finite(fraction) \
				or angle < deg_to_rad(8.0) or angle > PI/2.0 or cl < 0.0 or cl > 3.0 \
				or cd < 0.0 or cd > 3.0 or fraction < 0.0 or fraction > 1.0:
			errors.append(label + ": nonfinite or out-of-range polar row")
			return {}
		if i > 0 and angle - x[i-1] < 1e-5:
			errors.append(label + ": angles must increase by at least 1e-5 rad")
			return {}
		if i > 0 and fraction > values[(i-1)*3+2]:
			errors.append(label + ": attached fraction must not increase")
			return {}
		x.append(angle)
		values.append_array(PackedFloat64Array([cl, cd, fraction]))
	var first_cl := side * offset + slope * x[0]
	if absf(values[0]-first_cl) > 1e-9 or absf(values[1]-cd0) > 1e-12 or values[2] != 1.0:
		errors.append(label + ": first row must match attached wing CL, profile CD0 and fraction 1")
		return {}
	if x[n-1] != PI/2.0 or absf(values[(n-1)*3]) > 1e-12 \
			or absf(values[(n-1)*3+1]-(cd0+cd90)) > 1e-12 or values[(n-1)*3+2] != 0.0:
		errors.append(label + ": last row must be [90 deg, 0, CD0+CD90, 0]")
		return {}
	var tangents := PackedFloat64Array()
	tangents.resize(n*3)
	for component in 3:
		for i in range(1, n-1):
			var h0 := x[i]-x[i-1]
			var h1 := x[i+1]-x[i]
			var d0 := (values[i*3+component]-values[(i-1)*3+component])/h0
			var d1 := (values[(i+1)*3+component]-values[i*3+component])/h1
			if d0*d1 > 0.0:
				var w0 := 2.0*h1+h0
				var w1 := h1+2.0*h0
				tangents[i*3+component] = (w0+w1)/(w0/d0+w1/d1)
	# Exact C1 boundary slopes, constrained to keep the end intervals monotone.
	tangents[0] = slope
	tangents[(n-1)*3] = -cd90
	for endpoint in [0, n-1]:
		var i: int = 0 if endpoint == 0 else n-2
		var secant := (values[(i+1)*3]-values[i*3])/(x[i+1]-x[i])
		var derivative := tangents[endpoint*3]
		if secant*derivative <= 0.0 or absf(derivative) > 3.0*absf(secant):
			errors.append(label + ": endpoint lift samples cannot support a monotone C1 continuation")
			return {}
	# Endpoint + harmonic interior slopes need the monotonicity-circle constraint too.
	# Reduce only the adjacent interior tangent; endpoint slopes are physical join contracts.
	for i in [0, n-2]:
		var secant := (values[(i+1)*3]-values[i*3])/(x[i+1]-x[i])
		var fixed: int = i if i == 0 else i+1
		var free: int = i+1 if i == 0 else i
		var ratio := tangents[fixed*3]/secant
		var bound := absf(secant)*M.sqrt_(maxf(0.0, 9.0-ratio*ratio))
		tangents[free*3] = signf(tangents[free*3])*minf(absf(tangents[free*3]), bound)
	return {angles = x, values = values, tangents = tangents}


## [CL, profile CD, attached fraction]. Base is the actual induced, coupled strip lift.
## At fraction 1 this preserves the attached map; at 0 it is the explicit separated polar.
static func evaluate(alpha: float, base: float, polar: Dictionary) -> PackedFloat64Array:
	var side := 1.0 if alpha >= 0.0 else -1.0
	var angle := absf(alpha)
	var branch: Dictionary = polar.positive if side > 0.0 else polar.negative
	var x: PackedFloat64Array = branch.angles
	if angle <= x[0]:
		return PackedFloat64Array([base, polar.cd0, 1.0])
	if angle >= PI/2.0:
		var sine := M.sin_(alpha)
		return PackedFloat64Array([0.5*float(polar.cd90)*M.sin_(2.0*alpha),
			float(polar.cd0)+float(polar.cd90)*sine*sine, 0.0])
	var index := 0
	while index+1 < x.size()-1 and angle > x[index+1]:
		index += 1
	var h := x[index+1]-x[index]
	var t := (angle-x[index])/h
	var t2 := t*t
	var t3 := t2*t
	var h00 := 2.0*t3-3.0*t2+1.0
	var h10 := t3-2.0*t2+t
	var h01 := -2.0*t3+3.0*t2
	var h11 := t3-t2
	var v: PackedFloat64Array = branch.values
	var m: PackedFloat64Array = branch.tangents
	var result := PackedFloat64Array()
	for component in 3:
		result.append(h00*v[index*3+component] + h10*h*m[index*3+component] \
			+ h01*v[(index+1)*3+component] + h11*h*m[(index+1)*3+component])
	# Clamps suppress only roundoff of shape-preserving interpolants, never body rates or lift.
	result[1] = maxf(0.0, result[1])
	result[2] = clampf(result[2], 0.0, 1.0)
	var reference: float = polar.offset + polar.slope*alpha
	result[0] = side*result[0] + result[2]*(base-reference)
	return result
