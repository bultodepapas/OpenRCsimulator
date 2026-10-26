## Interval-envelope numerical checks. Synthetic coefficients, no aircraft tune.
extends "res://tests/test_normal_compliance.gd"
const Candidate := preload("res://physics/normal_compliance.gd")
# Complete original API Variant-byte/hex SHA256 captures, BEFORE this addition.
# Order: exponent1/2/3, each onset0/.002/.04; columns prepare/evaluate/bounds/scalar.
const LEGACY_FUNCTION_HEX_HASHES := [
 [
  "dc138fb711cef2bf2680b5ad9974c4fa244bb26e9921413a9fe694ba84d2c1ee",
  "ba0c7c430f4c8c9fca73bc90560065caecd5eda09d97176903ab9f9923937039",
  "b79904beb1fa5dade8ac67942c0b73edc675538be731bdd69b86553ac72aac00",
  "f1d3bf8a3667a09c63c4bac7bcc55d9329bbe902642fc5297b75df0b88109057"
 ],
 [
  "66db1559ffd1c914083bcb11cf490c1fed6588edbb44fa50eb1d187e6dfee6d4",
  "a12b78a38af3813691c5e3622158ad4893528af76f42ba6f77336cbc227bc929",
  "4a99d71c7e9dd4b5a31560ba63b1e1c9cfe93baefa9f1af185dcbe83357d2a52",
  "173c11344d39dd0071b3f5a4442e7c1791dbf9d19910ed4082e6e9c457e62eba"
 ],
 [
  "035d21345e95dca50a051a51e19b3ce578b57cde12adc81b5380a35934ae1c00",
  "f6b1f9090b003826a29f62548d4daa45645b400c0ca4da12a8d2999b86321023",
  "197bd4b0a2f0d6002c76056f8b4566b623b9a4f693fc4e5708cdd8eda9f326ef",
  "6b74a68b757b11c7fac392de14e389b02e35bb1c07245a0d4fb63511ff8491c6"
 ],
 [
  "b7bf8f6c7e3d388dc14a5154d607fbf9959d145cf2015d80a22d5b0e0ed9b4d2",
  "3d2e594bbfb2fff679802381d1607596c3567e00896191962aea145ab76bb8d1",
  "efb45ed35da5a8209afc5c7671e2f475ec9bc7c88b6b2b6966a52e13833ca9f3",
  "f1d3bf8a3667a09c63c4bac7bcc55d9329bbe902642fc5297b75df0b88109057"
 ],
 [
  "b23083269c11257b7c29c4f569ee1cac69af12143d6c856d28c1bb9c2b05e1d0",
  "b2fb17bbd0a12dc19158d99b51a5939ab4302660e753c1e2737c6def031f177c",
  "65b69d0114a73b1339b3861ca6708221ccda4cc0a6037c88aa88d798b83d045c",
  "f3d7085e2df66541aef879efb2e65bcaf0f3eb312c6df7b43aa5047c27a2190e"
 ],
 [
  "fe4c68e5adae3bb04026abd3155a02e732d4999becccc8e6ec9dab09abcf9cb1",
  "b44e82d8c25d8c80d23dfaf0bef21a0a92f9907a294615afd1eb5daaf314eb37",
  "28258e7b7a7d5492cbe2c120210389dd11f9d9aed1f8843d217a3771d560ec2f",
  "ad6ebbac9f70eb4940dd3614b703f90526b02147bc78c53c123079ce472f8b4e"
 ],
 [
  "cc7833a044d22b066ab0b1880ef99fb5a00d5c345625b9532d4efb236c6224df",
  "479e568b56a8b076e61bbc5498086f1dee81617a269a97ab8721f50e64bb3896",
  "87dd7e242dde5980776748ca71e857c8f291bb4c8843d78de25691758e7151a0",
  "f1d3bf8a3667a09c63c4bac7bcc55d9329bbe902642fc5297b75df0b88109057"
 ],
 [
  "7ce3cee3018604597036bd05c5ff1aebe2f9a28e18bcfd931ddc056a0d51486d",
  "95ed62df64291f8a959d6adef14c3e3953ec72dd0f529c49897be066f27839ae",
  "df8f398affe3ee0208bf4a94a5929831a73986e55867aec4f420b49e2262b2b2",
  "19edce6f7ddc92f53ad93b9dddf4a898e103f0d1faa12f58ce3834fdae377f5c"
 ],
 [
  "e0613784b6f70fe2f473be0d9505c7b6df9fe01ef71e2f49bd1fc2a84376f161",
  "8278e0a6bc92df57a6397e7e7525e4a2fc07a4b4399dcd3372237b310abed30d",
  "949af566dbcee1a78cb91563962db3d72b60a5e2d1229914f1a75a47526db3fc",
  "6b3b241503c2f9500358d95c170fa96fbc8343d9de23c4694bc8c4ac22bdf897"
 ]
]
var legacy_fixture_index := 0
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
			_parity(law)
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


func _parity(law: Dictionary) -> void:
	var expected: Array = LEGACY_FUNCTION_HEX_HASHES[legacy_fixture_index]
	legacy_fixture_index += 1
	_check("original prepare complete bytes match frozen pre-addition capture", var_to_bytes(law).hex_encode().sha256_text() == expected[0])
	var samples: Array = []
	for x: float in [-.01, 0.0, 1e-12, .001, .002, .019, .02, .021, .03, .04]:
		for v: float in [-3.0, -.1, 0.0, .1, 3.0]: samples.append(Candidate.evaluate(law,x,v))
	_check("original evaluate complete bytes match frozen pre-addition capture", var_to_bytes(samples).hex_encode().sha256_text() == expected[1])
	var previous: Array = []
	var same := true
	for xmax: float in [0.0, .001, .02, .025, .04]:
		var bound := Candidate.bounds(law,xmax,3.0)
		previous.append(bound)
		if var_to_bytes(bound) != var_to_bytes(Candidate.bounds_interval(law,0.0,xmax,3.0)): same = false
	_check("old bound bytes frozen and new interval starting at zero matches", same and var_to_bytes(previous).hex_encode().sha256_text() == expected[2])
	_check("original scalar selector complete bytes match frozen capture", var_to_bytes(Candidate.scalar_substeps(law,.04,3.0,2.0,1.0/240.0)).hex_encode().sha256_text() == expected[3])


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
	_check("missing prepared success/law selector refuses cleanly", not Candidate.bounds_interval({},0.0,.1,3.0).ok)
	_check("actual envelope overflow refuses explicitly", not Candidate.bounds_interval(law,0.0,1e300,1e300).ok)
