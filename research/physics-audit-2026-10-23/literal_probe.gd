extends SceneTree
const MIN_NORMAL_FLOAT64 := 2.2250738585072014e-308
func _initialize() -> void:
	print("literal=", String.num_scientific(MIN_NORMAL_FLOAT64), " pow=", String.num_scientific(pow(2.0,-1022.0)), " quotient=", String.num_scientific(1.0/4.49423283715579e307))
	quit()
