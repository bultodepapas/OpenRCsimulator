## Capture current direct-kernel legacy restore bytes before hook promotion.
extends SceneTree
const Sim := preload("res://sim/simulation.gd")
func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var sim := Sim.new()
	if not sim.reset(PackedFloat64Array([0.0, 0.0, -30.0, 10.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])):
		quit(1); return
	var target: Dictionary = sim.checkpoint()
	for i: int in 3: sim.step()
	if not sim.restore_checkpoint(target): quit(1); return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(sim.checkpoint()))
	print("LEGACY_RESTORE_CHECKPOINT_SHA256 ", hash.finish().hex_encode())
	sim.free()
	quit()
