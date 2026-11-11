# DR-07 (foundation slice): bounded four-rotor allocator, FPV/03 §2 and FPV/05 PHY-01, CTRL-02, CTRL-03. Known
# answers: the computed sign oracle [4, .08, .04, .008] ↔ [.5, 1.1, 1.3, 1.1] N; each matrix column equals the moment
# multirotor/rotor.gd produces (the plant, not the allocator's own algebra, is the oracle); saturation at the box
# corners; the airmode collective rise of FPV/03's example; production active set = 81-set reference on 2000 seeded
# random problems; results always inside the box; byte determinism; geometry refusals. Synthetic arithmetic only.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const Rotor := preload("res://physics/multirotor/rotor.gd")
const Plant := preload("res://physics/multirotor/plant.gd")
const Allocator := preload("res://physics/multirotor/allocator.gd")
const LP := preload("res://tests/law_properties.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_sign_oracle()
	_plant_columns()
	_in_box()
	_saturation()
	_airmode()
	_reference_agreement()
	_determinism()
	_refusals()
	_timing()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _oracle_rotors() -> Array:
	return [
		{ hub_frd = PackedFloat64Array([-0.1, 0.1, 0.0]), spin = -1.0 },
		{ hub_frd = PackedFloat64Array([0.1, 0.1, 0.0]), spin = 1.0 },
		{ hub_frd = PackedFloat64Array([-0.1, -0.1, 0.0]), spin = 1.0 },
		{ hub_frd = PackedFloat64Array([0.1, -0.1, 0.0]), spin = -1.0 },
	]


func _oracle(scales := PackedFloat64Array([4.0, 0.4, 0.4, 0.04]), weights := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])) -> Dictionary:
	return Allocator.prepare(_oracle_rotors(), PackedFloat64Array([0.01, 0.01, 0.01, 0.01]), scales, weights)


func _uniform(value: float) -> PackedFloat64Array:
	return PackedFloat64Array([value, value, value, value])


func _max_abs_diff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var worst := 0.0
	for k in a.size():
		worst = maxf(worst, absf(a[k] - b[k]))
	return worst


func _inside(f: PackedFloat64Array, lo: PackedFloat64Array, hi: PackedFloat64Array) -> bool:
	for i in 4:
		if not (f[i] >= lo[i] and f[i] <= hi[i]):
			return false
	return true


func _sign_oracle() -> void:
	var p: Dictionary = _oracle()
	_check("the FPV/03 oracle geometry prepares", p.ok, str(p.get("errors", "")))
	var f := PackedFloat64Array([0.5, 1.1, 1.3, 1.1])
	var w := PackedFloat64Array([4.0, 0.08, 0.04, 0.008])
	var produced: PackedFloat64Array = Allocator.wrench_of(p, f)
	_check("B·[.5, 1.1, 1.3, 1.1] = [4, .08, .04, .008] (1e-12): FPV/03's yaw column +s·κ holds", _max_abs_diff(produced, w) < 1e-12, str(produced))
	var r: Dictionary = Allocator.allocate(p, w, _uniform(0.0), _uniform(10.0))
	_check("allocate([4, .08, .04, .008]) = [.5, 1.1, 1.3, 1.1] (1e-12), unsaturated, no iterations",
		r.ok and _max_abs_diff(r.thrusts, f) < 1e-12 and not r.saturated and r.iterations == 0, str(r.get("thrusts", "")))
	var b: PackedFloat64Array = p.b
	_check("matrix layout: row collective ones, roll −y, pitch +x, yaw spin·κ", b[0] == 1.0 and b[4] == -0.1 and b[5] == -0.1 and b[6] == 0.1
		and b[8] == -0.1 and b[9] == 0.1 and b[12] == -0.01 and b[13] == 0.01 and b[14] == 0.01 and b[15] == -0.01, str(b))


## Every matrix column must equal what the plant's rotor law produces for that rotor alone (zero air velocity, zero
## rates, zero rotor acceleration), so the allocator predicts the plant rather than its own algebra.
func _plant_columns() -> void:
	var data: Dictionary = Plant.research_quad()
	var rotor: Dictionary = data.rotor
	var kappa: float = float(rotor.torque_coefficient_n_m_s2) / float(rotor.thrust_coefficient_n_s2)
	var rotors: Array = []
	var lift := [0.013, -0.007, 0.021, -0.017] # hub z offsets: no moment arm for a force along z
	for i in 4:
		var hub: PackedFloat64Array = data.rotors[i].hub_frd.duplicate()
		hub[2] = lift[i]
		rotors.append({ hub_frd = hub, spin = float(data.rotors[i].spin) })
	var p: Dictionary = Allocator.prepare(rotors, _uniform(kappa), PackedFloat64Array([33.0, 1.0, 1.0, 0.1]), _uniform(1.0))
	_check("the research quad geometry prepares", p.ok, str(p.get("errors", "")))
	var zero := M.v3(0.0, 0.0, 0.0)
	var names := ["rear-right CW", "front-right CCW", "rear-left CCW", "front-left CW"]
	var total_moment := M.v3(0.0, 0.0, 0.0)
	var total_thrust := 0.0
	var mixed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		var test_thrust := 2.0 + 0.5 * i
		var omega: float = sqrt(test_thrust / float(rotor.thrust_coefficient_n_s2))
		var loads: Dictionary = Rotor.loads(omega, float(rotors[i].spin), rotors[i].hub_frd, zero, zero, 0.0, rotor)
		var thrust: float = loads.thrust
		var f := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		f[i] = thrust
		mixed[i] = thrust
		var w: PackedFloat64Array = Allocator.wrench_of(p, f)
		var m: PackedFloat64Array = loads.moment
		var plant_w := PackedFloat64Array([-float(loads.force[2]), m[0], m[1], m[2]])
		var signs_match: bool = signf(w[1]) == signf(m[0]) and signf(w[2]) == signf(m[1]) and signf(w[3]) == signf(m[2]) \
			and m[0] != 0.0 and m[1] != 0.0 and m[2] != 0.0
		_check("rotor %d (%s): more thrust moves roll/pitch/yaw exactly as rotor.gd does (1e-12)" % [i + 1, names[i]],
			signs_match and _max_abs_diff(w, plant_w) < 1e-12, "alloc %s plant %s" % [str(w), str(plant_w)])
		total_moment = M.add(total_moment, m)
		total_thrust += thrust
	var w_mixed: PackedFloat64Array = Allocator.wrench_of(p, mixed)
	_check("four rotors together: B·f equals the summed plant loads (1e-12)",
		_max_abs_diff(w_mixed, PackedFloat64Array([total_thrust, total_moment[0], total_moment[1], total_moment[2]])) < 1e-12)
	# Plant sign contracts of test_dr_multirotor_kernel.gd, restated on the matrix.
	var right: PackedFloat64Array = Allocator.wrench_of(p, PackedFloat64Array([1.0, 1.0, 0.0, 0.0]))
	var front: PackedFloat64Array = Allocator.wrench_of(p, PackedFloat64Array([0.0, 1.0, 0.0, 1.0]))
	var ccw: PackedFloat64Array = Allocator.wrench_of(p, PackedFloat64Array([0.0, 1.0, 1.0, 0.0]))
	_check("right pair rolls left, front pair pitches up, CCW pair yaws clockwise (positive r)",
		right[1] < 0.0 and front[2] > 0.0 and ccw[3] > 0.0 and absf(right[2]) < 1e-15 and absf(ccw[1]) < 1e-15)


func _in_box() -> void:
	var p: Dictionary = _oracle()
	var w := PackedFloat64Array([6.0, -0.05, 0.03, -0.012])
	var r: Dictionary = Allocator.allocate(p, w, _uniform(0.2), _uniform(4.0))
	_check("in-box request: unsaturated, objective ≈ 0 (< 1e-24) and wrench = request (1e-12)",
		r.ok and not r.saturated and r.objective < 1e-24 and _max_abs_diff(r.wrench, w) < 1e-12 and _inside(r.thrusts, _uniform(0.2), _uniform(4.0)),
		"objective %s" % LP.sci(r.objective))


func _saturation() -> void:
	var p: Dictionary = _oracle()
	var high: Dictionary = Allocator.allocate(p, PackedFloat64Array([10.0, 0.0, 0.0, 0.0]), _uniform(0.0), _uniform(2.0))
	_check("collective above 4·f_max: every rotor exactly at f_max, wrench [8, 0, 0, 0], saturated",
		high.ok and high.saturated and high.thrusts == _uniform(2.0) and high.wrench == PackedFloat64Array([8.0, 0.0, 0.0, 0.0]), str(high.thrusts))
	var low: Dictionary = Allocator.allocate(p, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), _uniform(0.3), _uniform(2.0))
	_check("zero request above an idle floor: every rotor exactly at f_min, saturated",
		low.ok and low.saturated and low.thrusts == _uniform(0.3), str(low.thrusts))
	var yaw: Dictionary = Allocator.allocate(p, PackedFloat64Array([4.0, 0.0, 0.0, 0.5]), _uniform(0.0), _uniform(2.0))
	_check("yaw beyond authority: the CCW pair at f_max, the CW pair at 0, yaw = 0.04 N·m, collective and roll/pitch kept",
		yaw.ok and yaw.saturated and yaw.thrusts == PackedFloat64Array([0.0, 2.0, 2.0, 0.0]) and absf(yaw.wrench[3] - 0.04) < 1e-15
		and absf(yaw.wrench[0] - 4.0) < 1e-15 and absf(yaw.wrench[1]) < 1e-15 and absf(yaw.wrench[2]) < 1e-15, str(yaw.wrench))
	var fixed_lo := PackedFloat64Array([0.7, 1.2, 0.4, 0.9])
	var all_fixed: Dictionary = Allocator.allocate(p, PackedFloat64Array([4.0, 0.08, 0.04, 0.008]), fixed_lo, fixed_lo)
	_check("degenerate f_min == f_max on every rotor returns the bounds exactly", all_fixed.ok and all_fixed.thrusts == fixed_lo, str(all_fixed.thrusts))
	var one_lo := PackedFloat64Array([0.7, 0.0, 0.0, 0.0])
	var one_hi := PackedFloat64Array([0.7, 5.0, 5.0, 5.0])
	var w_one := PackedFloat64Array([4.0, 0.08, 0.04, 0.008])
	var one: Dictionary = Allocator.allocate(p, w_one, one_lo, one_hi)
	var one_ref: Dictionary = Allocator.allocate_reference(p, w_one, one_lo, one_hi)
	_check("one degenerate rotor stays at its bound and matches the reference (1e-12)",
		one.ok and one.thrusts[0] == 0.7 and one.saturated and _max_abs_diff(one.thrusts, one_ref.thrusts) < 1e-12, str(one.thrusts))
	for case: Array in [[high, [10.0, 0.0, 0.0, 0.0], 0.0, 2.0], [low, [0.0, 0.0, 0.0, 0.0], 0.3, 2.0], [yaw, [4.0, 0.0, 0.0, 0.5], 0.0, 2.0]]:
		var ref: Dictionary = Allocator.allocate_reference(p, PackedFloat64Array(case[1]), _uniform(case[2]), _uniform(case[3]))
		_check("saturated corner %s matches the 81-set reference exactly" % str(case[1]),
			ref.ok and ref.thrusts == case[0].thrusts and ref.saturated == case[0].saturated)


## FPV/03 §2 airmode example: corrections [-.2, -.2, +.2, +.2] at collective .02 per motor in [.05, 1]. With moment
## rows weighted 1e4 above collective, the weighted solution is [.05, .05, a, a] with the closed form below and tends
## to FPV/03's lexicographic answer [.05, .05, .45, .45] (collective raised to .25 per motor).
func _airmode() -> void:
	var scales := PackedFloat64Array([1.0, 0.1, 0.1, 0.01])
	var weights := PackedFloat64Array([1.0e-3, 1.0, 1.0, 1.0])
	var p: Dictionary = _oracle(scales, weights)
	# Requested per-motor thrusts .02 + [-.2, -.2, .2, .2] give this wrench.
	var w: PackedFloat64Array = Allocator.wrench_of(p, PackedFloat64Array([-0.18, -0.18, 0.22, 0.22]))
	var r: Dictionary = Allocator.allocate(p, w, _uniform(0.05), _uniform(1.0))
	var wc: float = weights[0] / scales[0]
	var wr: float = weights[1] / scales[1]
	var a: float = (0.018 * wr * wr - 0.04 * wc * wc) / (4.0 * wc * wc + 0.04 * wr * wr)
	var expected := PackedFloat64Array([0.05, 0.05, a, a])
	var mean: float = (r.thrusts[0] + r.thrusts[1] + r.thrusts[2] + r.thrusts[3]) / 4.0
	_check("airmode: low-side rotors at the idle floor, high side at the weighted closed form (1e-12)",
		r.ok and r.saturated and _max_abs_diff(r.thrusts, expected) < 1e-12, "%s vs a = %.12f" % [str(r.thrusts), a])
	_check("airmode: collective rises from .08 N to ≈ 1.0 N to keep the roll moment, ≈ FPV/03's [.05, .05, .45, .45] (1e-5)",
		r.wrench[0] > 0.9 and absf(mean - 0.25) < 1e-5 and _max_abs_diff(r.thrusts, PackedFloat64Array([0.05, 0.05, 0.45, 0.45])) < 1e-5
		and absf(r.wrench[1] - w[1]) < 1e-5, "collective %.9f roll %.9f of %.9f" % [r.wrench[0], r.wrench[1], w[1]])


func _random_case(rng: RandomNumberGenerator) -> Dictionary:
	var half: float = rng.randf_range(0.05, 0.15)
	var spins := [-1.0, 1.0, 1.0, -1.0]
	var signs_x := [-1.0, 1.0, -1.0, 1.0]
	var signs_y := [1.0, 1.0, -1.0, -1.0]
	var rotors: Array = []
	var kappa := PackedFloat64Array()
	for i in 4:
		rotors.append({ hub_frd = PackedFloat64Array([signs_x[i] * half * rng.randf_range(0.7, 1.3),
			signs_y[i] * half * rng.randf_range(0.7, 1.3), rng.randf_range(-0.02, 0.02)]), spin = spins[i] })
		kappa.append(rng.randf_range(0.005, 0.03))
	var fm: float = rng.randf_range(2.0, 15.0)
	var scales := PackedFloat64Array([4.0 * fm, fm * half, fm * half, fm * 0.015])
	var weights := PackedFloat64Array()
	for _r in 4:
		weights.append(rng.randf_range(0.2, 5.0))
	var f_min := PackedFloat64Array()
	var f_max := PackedFloat64Array()
	for i in 4:
		var lo: float = rng.randf_range(0.0, 0.2 * fm)
		f_min.append(lo)
		f_max.append(lo if rng.randf() < 0.05 else rng.randf_range(lo + 0.05 * fm, fm))
	var sum_max: float = f_max[0] + f_max[1] + f_max[2] + f_max[3]
	# Roughly a third of the requests are small enough to fit the box; the rest saturate in assorted ways.
	var reach: float = 0.1 if rng.randf() < 0.4 else 2.0
	var collective: float = rng.randf_range(0.3, 0.7) * sum_max if reach < 1.0 else rng.randf_range(0.0, 1.2 * sum_max)
	var w := PackedFloat64Array([collective, rng.randf_range(-reach, reach) * fm * half,
		rng.randf_range(-reach, reach) * fm * half, rng.randf_range(-1.5 * reach, 1.5 * reach) * fm * 0.015])
	return { prepared = Allocator.prepare(rotors, kappa, scales, weights), w = w, f_min = f_min, f_max = f_max, fm = fm }


func _reference_agreement() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var prepared_ok := true
	var all_ok := true
	var inside := true
	var worst_thrust := 0.0
	var worst_objective := 0.0
	var worst_floor := 0.0
	var not_worse := true
	var saturated := 0
	var fallbacks := 0
	var max_iterations := 0
	var saturation_flags_agree := true
	for _case in 2000:
		var c: Dictionary = _random_case(rng)
		if not c.prepared.ok:
			prepared_ok = false
			continue
		var prod: Dictionary = Allocator.allocate(c.prepared, c.w, c.f_min, c.f_max)
		var ref: Dictionary = Allocator.allocate_reference(c.prepared, c.w, c.f_min, c.f_max)
		if not prod.ok or not ref.ok:
			all_ok = false
			continue
		inside = inside and _inside(prod.thrusts, c.f_min, c.f_max) and _inside(ref.thrusts, c.f_min, c.f_max)
		worst_thrust = maxf(worst_thrust, _max_abs_diff(prod.thrusts, ref.thrusts) / float(c.fm))
		var diff: float = absf(float(prod.objective) - float(ref.objective))
		# The objective is dimensionless (rows divided by their scales). Below 1e-20 both values are rounding
		# residue of an exactly attainable request (~1e-31), where a relative comparison has no meaning.
		if float(ref.objective) > 1e-20:
			worst_objective = maxf(worst_objective, diff / float(ref.objective))
		else:
			worst_floor = maxf(worst_floor, diff)
		not_worse = not_worse and float(prod.objective) <= float(ref.objective) * (1.0 + 1e-12) + 1e-24
		saturation_flags_agree = saturation_flags_agree and prod.saturated == ref.saturated
		saturated += 1 if prod.saturated else 0
		fallbacks += 1 if prod.fallback else 0
		max_iterations = maxi(max_iterations, int(prod.iterations))
	_check("2000 seeded random geometries prepare and both solvers succeed", prepared_ok and all_ok)
	_check("production = reference thrusts (< 1e-9 of the thrust scale)", worst_thrust < 1e-9, LP.sci(worst_thrust))
	_check("production = reference objective (< 1e-12 relative above 1e-20; < 1e-24 absolute below)",
		worst_objective < 1e-12 and worst_floor < 1e-24, "relative %s floor %s" % [LP.sci(worst_objective), LP.sci(worst_floor)])
	_check("production objective never exceeds the reference minimum (1e-12 relative + 1e-24)", not_worse)
	_check("every result of both solvers lies inside the box", inside)
	_check("saturation flags agree", saturation_flags_agree)
	_check("random set exercises saturation without hitting the iteration cap", saturated > 500 and fallbacks == 0,
		"saturated %d of 2000, fallbacks %d, max iterations %d" % [saturated, fallbacks, max_iterations])


func _determinism() -> void:
	var p: Dictionary = _oracle()
	var w := PackedFloat64Array([7.5, 0.3, -0.2, 0.02])
	var lo := PackedFloat64Array([0.1, 0.2, 0.1, 0.3])
	var hi := PackedFloat64Array([2.0, 2.5, 1.8, 2.2])
	var a: Dictionary = Allocator.allocate(p, w, lo, hi)
	var b: Dictionary = Allocator.allocate(p, w, lo, hi)
	var ra: Dictionary = Allocator.allocate_reference(p, w, lo, hi)
	var rb: Dictionary = Allocator.allocate_reference(p, w, lo, hi)
	_check("same call twice gives identical bytes (production and reference)",
		a.saturated and var_to_bytes(a) == var_to_bytes(b) and var_to_bytes(ra) == var_to_bytes(rb))
	var p2: Dictionary = _oracle()
	_check("prepare is deterministic", var_to_bytes(p) == var_to_bytes(p2))


func _refusals() -> void:
	var kappa := _uniform(0.01)
	var scales := PackedFloat64Array([4.0, 0.4, 0.4, 0.04])
	var weights := _uniform(1.0)
	var coincident: Array = []
	for i in 4:
		coincident.append({ hub_frd = PackedFloat64Array([0.1, 0.1, 0.0]), spin = [-1.0, 1.0, 1.0, -1.0][i] })
	var same_spin: Array = _oracle_rotors()
	for rotor: Dictionary in same_spin:
		rotor.spin = 1.0
	var collinear: Array = _oracle_rotors()
	collinear[0].hub_frd = PackedFloat64Array([-0.1, 0.0, 0.0])
	collinear[1].hub_frd = PackedFloat64Array([0.1, 0.0, 0.0])
	collinear[2].hub_frd = PackedFloat64Array([-0.2, 0.0, 0.0])
	collinear[3].hub_frd = PackedFloat64Array([0.2, 0.0, 0.0])
	var nan_hub: Array = _oracle_rotors()
	nan_hub[2].hub_frd = PackedFloat64Array([NAN, 0.1, 0.0])
	var bad_spin: Array = _oracle_rotors()
	bad_spin[1].spin = 0.5
	var cases := [
		["coincident hubs (rank deficient)", Allocator.prepare(coincident, kappa, scales, weights)],
		["all-same spins (rank deficient)", Allocator.prepare(same_spin, kappa, scales, weights)],
		["hubs on one line (no roll authority)", Allocator.prepare(collinear, kappa, scales, weights)],
		["a zero scale", Allocator.prepare(_oracle_rotors(), kappa, PackedFloat64Array([4.0, 0.0, 0.4, 0.04]), weights)],
		["a negative weight", Allocator.prepare(_oracle_rotors(), kappa, scales, PackedFloat64Array([1.0, 1.0, -1.0, 1.0]))],
		["a non-finite hub", Allocator.prepare(nan_hub, kappa, scales, weights)],
		["a spin other than ±1", Allocator.prepare(bad_spin, kappa, scales, weights)],
		["three rotors", Allocator.prepare(_oracle_rotors().slice(0, 3), kappa, scales, weights)],
	]
	for case: Array in cases:
		_check("prepare refuses %s" % case[0], not case[1].ok and not case[1].errors.is_empty(), str(case[1].errors))
	var p: Dictionary = _oracle()
	var bad_bounds: Dictionary = Allocator.allocate(p, PackedFloat64Array([4.0, 0.0, 0.0, 0.0]), _uniform(2.0), _uniform(1.0))
	var bad_request: Dictionary = Allocator.allocate(p, PackedFloat64Array([NAN, 0.0, 0.0, 0.0]), _uniform(0.0), _uniform(1.0))
	var negative: Dictionary = Allocator.allocate(p, PackedFloat64Array([-1.0, 0.0, 0.0, 0.0]), _uniform(0.0), _uniform(1.0))
	var unprepared: Dictionary = Allocator.allocate({ ok = false }, PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), _uniform(0.0), _uniform(1.0))
	_check("allocate refuses f_min > f_max, a non-finite request, negative thrust and an unprepared allocator",
		not bad_bounds.ok and not bad_request.ok and not negative.ok and not unprepared.ok)


func _timing() -> void:
	var p: Dictionary = _oracle()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var requests: Array[PackedFloat64Array] = []
	for k in 64:
		# About half in-box (the common case), half saturated.
		var spread: float = 0.3 if k % 2 == 0 else 3.0
		requests.append(PackedFloat64Array([rng.randf_range(2.0, 7.0), rng.randf_range(-0.1, 0.1) * spread,
			rng.randf_range(-0.1, 0.1) * spread, rng.randf_range(-0.01, 0.01) * spread]))
	var lo := _uniform(0.1)
	var hi := _uniform(2.5)
	var saturated := 0
	var start: int = Time.get_ticks_usec()
	for k in 20000:
		var r: Dictionary = Allocator.allocate(p, requests[k % 64], lo, hi)
		saturated += 1 if r.saturated else 0
	var elapsed: int = Time.get_ticks_usec() - start
	print("info allocate cost: %.3f us/call mean over 20000 calls (%d saturated)" % [float(elapsed) / 20000.0, saturated])
	start = Time.get_ticks_usec()
	for k in 2000:
		var even: Dictionary = Allocator.allocate(p, requests[(2 * k) % 64], lo, hi)
		saturated += 1 if even.saturated else 0
	var in_box: float = float(Time.get_ticks_usec() - start) / 2000.0
	start = Time.get_ticks_usec()
	for k in 2000:
		var odd: Dictionary = Allocator.allocate(p, requests[(2 * k + 1) % 64], lo, hi)
		saturated += 1 if odd.saturated else 0
	var mixed_odd: float = float(Time.get_ticks_usec() - start) / 2000.0
	print("info allocate cost split: %.3f us (even, mostly in-box) / %.3f us (odd, mostly saturated)" % [in_box, mixed_odd])
