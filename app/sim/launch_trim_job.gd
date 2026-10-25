## Pure numeric entry point for the detached launch-trim worker.
## Arguments are produced from the cache's object-free var_to_bytes round trip on the main thread.
extends RefCounted

const CruiseTrim := preload("res://physics/cruise_trim.gd")


static func solve(arguments: Array) -> Dictionary:
	return CruiseTrim.solve_level_at_throttle(
		float(arguments[0]), float(arguments[1]), float(arguments[2]), arguments[3],
		float(arguments[4]), arguments[5], float(arguments[6]), float(arguments[7]), float(arguments[8]))
