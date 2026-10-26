## Interval-envelope numerical checks. Synthetic coefficients, no aircraft tune.
extends "res://tests/test_normal_compliance.gd"
const Candidate := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/normal_compliance.gd")
var largest_secant_ratio := 0.0
var largest_fd_ratio := 0.0


func _initialize() -> void:
	_known_answers()
	for exponent: int in [1, 2, 3]:
		for onset: float in [0.0, .002, .04]:
			var raw := _raw()
			raw.stop_exponent.value = float(exponent)
			raw.damping_onset.value = onset
			var law := Candidate.prepare(raw)
			_parity(raw, law)
			for interval: Array in [[0.0, 0.0], [0.0, .001], [.0003, .0015], [.002, .019],
				[.019, .021], [.02, .025], [.021, .029], [.03, .04], [.031, .04]]:
				_verify_interval(law, interval[0], interval[1], 3.0)
	_zero_onset()
	_invalid()
	print("NORMAL_INTERVAL_ORACLE ", JSON.stringify({largest_secant_ratio=largest_secant_ratio,largest_fd_ratio=largest_fd_ratio}))
	print("Normal compliance interval: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _known_answers() -> void:
	var raw := _raw()
	raw.stiffness.value = 1500.0
	raw.compression_damping.value = 20.0
	raw.rebound_damping.value = 12.0
	raw.stroke.value = .2
	raw.stop_stiffness.value = 0.0
	var law := Candidate.prepare(raw)
	var broad := C.bounds(law, .05, 3.0)
	var local := Candidate.bounds_interval(law, .04, .05, 3.0)
	_check("same declared rest coefficients remove only matured onset slope", broad.position_derivative_bound_npm == 61500.0
		and local.position_derivative_bound_npm == 1500.0 and local.rate_derivative_bound_nsm == 20.0)
	_check("elastic and damping maxima unchanged", broad.elastic_tangent_bound_npm == local.elastic_tangent_bound_npm
		and broad.rate_derivative_bound_nsm == local.rate_derivative_bound_nsm)
	var crossing := Candidate.bounds_interval(law, .0019, .05, 3.0)
	var touching := Candidate.bounds_interval(law, .002, .05, 3.0)
	_check("base slope retained if any interval crosses onset ramp", crossing.position_derivative_bound_npm == 61500.0)
	_check("base slope zero on closed matured interval starting at onset", touching.position_derivative_bound_npm == 1500.0)
	# Binary-exact boundaries isolate the stop-threshold convention from decimal
	# subtraction rounding; decimal rounding toward an active ramp is conservative.
	raw = _raw()
	raw.damping_onset.value = .125
	raw.stroke.value = .25
	raw.stop_scale.value = .125
	law = Candidate.prepare(raw)
	var below := Candidate.bounds_interval(law, .375 - 1e-8, .5, 3.0)
	var at := Candidate.bounds_interval(law, .375, .5, 3.0)
	_check("stop slope retained below and zero at closed saturation threshold", absf(below.position_derivative_bound_npm
		- at.position_derivative_bound_npm - 2.0 * raw.stop_damping.value / .125 * 3.0) < 1e-10)
	_check("stop and base mature interval retains full damping maximum", at.rate_derivative_bound_nsm == 13.0)
	raw = _raw()
	raw.damping_onset.value = 1e-100
	law = Candidate.prepare(raw)
	_check("mature local interval avoids unused global ramp-overflow term", law.ok
		and not C.bounds(law, .01, 1e300).ok and Candidate.bounds_interval(law, .003, .01, 1e300).ok)


func _parity(raw: Dictionary, law: Dictionary) -> void:
	var old := C.prepare(raw)
	_check("original prepare remains byte identical", var_to_bytes(old) == var_to_bytes(law))
	var same := true
	for x: float in [-.01, 0.0, 1e-12, .001, .002, .019, .02, .021, .03, .04]:
		for v: float in [-3.0, -.1, 0.0, .1, 3.0]:
			if var_to_bytes(C.evaluate(old, x, v)) != var_to_bytes(Candidate.evaluate(law, x, v)): same = false
	_check("all original evaluate fields/default arithmetic remain byte identical", same)
	same = true
	for xmax: float in [0.0, .001, .02, .025, .04]:
		var previous := C.bounds(old, xmax, 3.0)
		if var_to_bytes(previous) != var_to_bytes(Candidate.bounds(law, xmax, 3.0)): same = false
		if var_to_bytes(previous) != var_to_bytes(Candidate.bounds_interval(law, 0.0, xmax, 3.0)): same = false
	_check("old bounds and interval starting at zero are byte identical", same)
	_check("original scalar selector remains byte identical", var_to_bytes(C.scalar_substeps(old, .04, 3.0, 2.0, 1.0/240.0))
		== var_to_bytes(Candidate.scalar_substeps(law, .04, 3.0, 2.0, 1.0/240.0)))


## Independent scalar polynomial/ramp oracle, reading only authored scalars.
## Does not use evaluate's returned derivative fields or Candidate._ramp.
func _force(p: Dictionary, x: float, v: float) -> float:
	if x <= 0.0: return 0.0
	var excess: float = maxf(0.0, x - p.stroke)
	var z: float = excess / p.stop_scale
	var power := z
	for _i in int(p.stop_exponent) - 1: power *= z
	var elastic: float = p.stiffness * x + p.stop_stiffness * p.stop_scale * power
	var base := 1.0
	if p.damping_onset > 0.0 and x < p.damping_onset:
		var t: float = x / p.damping_onset
		base = 2.0*t - t*t
	var stop := 0.0
	if excess >= p.stop_scale: stop = 1.0
	elif excess > 0.0:
		var t: float = excess / p.stop_scale
		stop = 2.0*t - t*t
	var c: float = p.compression_damping if v >= 0.0 else p.rebound_damping
	return maxf(0.0, elastic + (c*base+p.stop_damping*stop)*v)


func _verify_interval(law: Dictionary, xmin: float, xmax: float, vmax: float) -> void:
	var before := var_to_bytes(law)
	var envelope := Candidate.bounds_interval(law, xmin, xmax, vmax)
	_check("finite closed interval bound evaluates", envelope.ok)
	if not envelope.ok: return
	var derivative_safe := true
	var force_matches := true
	var secant_safe := true
	var p: Dictionary = law.values
	var k: float = envelope.position_derivative_bound_npm
	var c: float = envelope.rate_derivative_bound_nsm
	for i in 65:
		var x: float = xmin + (xmax-xmin)*i/64.0
		for v: float in [-vmax, -.2, 0.0, .2, vmax]:
			var sample := C.evaluate(law, x, v)
			force_matches = force_matches and absf(sample.normal_load_n-_force(p,x,v)) <= 1e-10*maxf(1.0, sample.normal_load_n)
			derivative_safe = derivative_safe and absf(sample.load_position_derivative_npm) <= k*(1.0+1e-12) \
				and absf(sample.load_rate_derivative_nsm) <= c*(1.0+1e-12)
			# Finite differences remain INSIDE the declared compression interval.
			if i > 0 and i < 64 and xmax > xmin:
				var eps: float = minf(1e-7, (xmax-xmin)/256.0)
				var fd: float = absf((_force(p,x+eps,v)-_force(p,x-eps,v))/(2.0*eps))
				largest_fd_ratio = maxf(largest_fd_ratio, fd/maxf(k,1e-300))
				derivative_safe = derivative_safe and fd <= k*(1.0+1e-7)+1e-7
			if envelope.continuous_onset:
				var j := (i*37+19)%65
				var other_x: float = xmin+(xmax-xmin)*j/64.0
				var other_v: float = -.73*v
				var actual: float = absf(_force(p,x,v)-_force(p,other_x,other_v))
				var bound: float = k*absf(x-other_x)+c*absf(v-other_v)
				if bound > 0.0: largest_secant_ratio = maxf(largest_secant_ratio, actual/bound)
				secant_safe = secant_safe and actual <= bound*(1.0+1e-12)+1e-10
	_check("independent polynomial force agrees across clipped/onset/stroke branches", force_matches)
	_check("analytic derivative fields AND independent interior finite differences enclosed", derivative_safe)
	_check("independent two-coordinate Lipschitz secants enclosed when onset continuous", secant_safe)
	_check("interval query never mutates prepared law", before == var_to_bytes(law))


func _zero_onset() -> void:
	var raw := _raw()
	raw.damping_onset.value = 0.0
	var law := Candidate.prepare(raw)
	var touching := Candidate.bounds_interval(law, 0.0, .01, 3.0)
	var inside := Candidate.bounds_interval(law, 1e-12, .01, 3.0)
	_check("zero-onset smooth claim requires STRICT positive lower compression", not touching.continuous_onset and inside.continuous_onset)
	var jump: float = absf(_force(law.values,1e-12,3.0)-_force(law.values,0.0,3.0))
	_check("independent zero-onset jump disproves global Lipschitz claim", jump > touching.position_derivative_bound_npm*1e-12+1.0)
	raw.compression_damping.value = 0.0
	raw.rebound_damping.value = 0.0
	law = Candidate.prepare(raw)
	_check("absent base damping makes zero onset continuous", Candidate.bounds_interval(law,0.0,.04,3.0).continuous_onset)


func _invalid() -> void:
	var law := Candidate.prepare(_raw())
	for row: Array in [[-.1,.1,3.0],[.1,.09,3.0],[0.0,.1,-1.0],[NAN,.1,3.0],[0.0,INF,3.0],[0.0,.1,NAN]]:
		_check("invalid finite/order/speed interval refuses", not Candidate.bounds_interval(law,row[0],row[1],row[2]).ok)
	for selector: Variant in [null, [], {}, false, 3.0, "unknown"]:
		var bad := law.duplicate(true)
		bad.law = selector
		_check("invalid law type/selector refuses cleanly", not Candidate.bounds_interval(bad,0.0,.1,3.0).ok)
	_check("malformed prepared result refuses cleanly", not Candidate.bounds_interval({},0.0,.1,3.0).ok)
	_check("actual envelope overflow refuses explicitly", not Candidate.bounds_interval(law,0.0,1e300,1e300).ok)
