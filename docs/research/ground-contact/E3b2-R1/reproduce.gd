extends SceneTree
const GS = preload("res://physics/ground_start.gd")
func _initialize() -> void:
	for r in [PackedFloat64Array([NAN, 0.0]), PackedFloat64Array([0.0, NAN]), PackedFloat64Array()]:
		var result: Dictionary = GS._newton(func(_x: PackedFloat64Array) -> PackedFloat64Array: return r, PackedFloat64Array([0.0, 0.0]))
		print("residual=", r, " result=", result)
	print("nonfinite initial pose: ", GS._newton(func(_x: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array([0.0]), PackedFloat64Array([NAN])))
	print("overflow linear solve: ", GS._linear_solve(PackedFloat64Array([1e-299]), PackedFloat64Array([1e308]), 1))
	quit(0)
