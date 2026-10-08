extends SceneTree
const Reference = preload("reference.gd")
const Candidate = preload("res://physics/aircraft_data.gd")
func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 204702
	var count: int = 0
	var mismatches: int = 0
	var max_error: float = 0.0
	var ref_us: int = 0
	var candidate_us: int = 0
	for i in 1000:
		var aero: Dictionary = {CL0 = rng.randf_range(-0.3, 0.3), CLa = rng.randf_range(0.3, 12.0)}
		var cd90: float = rng.randf_range(0.5, 2.5)
		var width: float = deg_to_rad(rng.randf_range(1.0, 30.0))
		var sign: float = 1.0 if i % 2 == 0 else -1.0
		var target: float = sign * rng.randf_range(maxf(0.35, cd90 * 0.5 + 0.01), 3.0)
		var begin: int = Time.get_ticks_usec()
		var before: float = Reference._solve_stall_start(aero, cd90, width, target, sign)
		ref_us += Time.get_ticks_usec() - begin
		begin = Time.get_ticks_usec()
		var after: float = Candidate._solve_stall_start(aero, cd90, width, target, sign)
		candidate_us += Time.get_ticks_usec() - begin
		count += 1
		max_error = maxf(max_error, absf(after - before))
		if after != before:
			mismatches += 1
			printerr("MISMATCH ", i, " ", before, " ", after)
		if i % 100 == 99:
			print(JSON.stringify({cases = count, mismatches = mismatches, max_error_rad = max_error, reference_us = ref_us, candidate_us = candidate_us}))
	quit(0 if mismatches == 0 else 1)
