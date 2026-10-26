## Capture an existing legacy reset's exact checkpoint before production changes.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var sim := Sim.new()
	var initial := PackedFloat64Array([9.0, 0.0, -30.0, 10.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	if not sim.reset(initial): quit(1); return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(sim.checkpoint()))
	print("DEFAULT_RESET_CHECKPOINT_SHA256 ", hash.finish().hex_encode())
	sim.free()
	quit()
