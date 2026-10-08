# DATA-2: exact legacy-grid preservation; independent dense oracle and fallback cases.
extends SceneTree
const Aero = preload("res://physics/aero.gd")
const Solver = preload("res://physics/aircraft_data.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 270204
	# Include both sides, non-unimodal blends and a flat-plate maximum inside the grid.
	for i in 256:
		var aero: Dictionary = {CL0 = rng.randf_range(-0.5, 0.5), CLa = rng.randf_range(0.1, 100.0)}
		var width: float = deg_to_rad(rng.randf_range(1.0, 30.0))
		var start: float = rng.randf_range(0.0, 1.6)
		var cd90: float = rng.randf_range(0.5, 2.5)
		for sign in [1.0, -1.0]:
			check("sampled extreme %d side %s" % [i, sign], Solver._blend_extreme(aero, cd90, width, start, sign) == _reference_extreme(aero, cd90, width, start, sign))
	for start in [-0.1, 0.0, PI / 4.0, PI / 2.0, 5.0]:
		for slope in [0.0, -1.0, 0.01, 100.0]:
			for sign in [1.0, -1.0]:
				var aero: Dictionary = {CL0 = 0.2, CLa = slope}
				check("boundary/fallback", Solver._blend_extreme(aero, 2.5, 0.2, start, sign) == _reference_extreme(aero, 2.5, 0.2, start, sign))
	for i in 16:
		var aero: Dictionary = {CL0 = rng.randf_range(-0.3, 0.3), CLa = rng.randf_range(1.0, 12.0)}
		var cd90: float = rng.randf_range(0.5, 2.5)
		var width: float = deg_to_rad(rng.randf_range(1.0, 30.0))
		var sign: float = 1.0 if i % 2 == 0 else -1.0
		var target: float = sign * rng.randf_range(cd90 * 0.5 + 0.05, 3.0)
		check("solved start %d" % i, Solver._solve_stall_start(aero, cd90, width, target, sign) == _reference_solve(aero, cd90, width, target, sign))
	# Below the roundoff cushion no interval prunes: exercise maximum stack depth.
	for sign in [1.0, -1.0]:
		var tiny: Dictionary = {CL0 = 0.0, CLa = 1e-20}
		check("unpruned grid stack capacity", Solver._blend_extreme(tiny, 1e-20, 0.2, 0.2, sign) == _reference_extreme(tiny, 1e-20, 0.2, 0.2, sign))
	# Function must not alter caller data (repeated loads/rejected reloads use the same coefficients).
	var aero: Dictionary = {CL0 = 0.1, CLa = 5.0}
	var before: Dictionary = aero.duplicate(true)
	Solver._solve_stall_start(aero, 1.2, 0.2, 1.1, 1.0)
	check("pure solve", before == aero)
	print("DATA-2: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)

static func _reference_solve(aero: Dictionary, cd90: float, width: float, target: float, sign: float) -> float:
	var lo := 0.0
	var hi := (target - float(aero.CL0)) / float(aero.CLa) * sign # where the linear lift alone reaches the target
	for i in 60:
		var mid := 0.5 * (lo + hi)
		if _reference_extreme(aero, cd90, width, mid, sign) * sign < target * sign:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


static func _reference_extreme(aero: Dictionary, cd90: float, width: float, start: float, sign: float) -> float:
	var env := { a1 = start, a2 = start + width, n1 = start, n2 = start + width, b1 = 1.0, b2 = 2.0, CD90 = cd90 }
	var best := 0.0
	for k in 801: # 0.01·width steps across the blend, plus its edges
		var alpha := sign * (start + width * (float(k) / 800.0) * 1.25)
		var cl := Aero.lift_alpha(alpha, aero, env)
		if cl * sign > best * sign:
			best = cl
	return best

