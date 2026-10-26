extends SceneTree
const Audio := preload("res://audio/ground_audio.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var a := Audio.new()
	a.configure(root, &"Master")
	var rows := []
	var c := {id = "main", position = Vector3(1.0, 2.0, 3.0), normal_force_n = 0.0,
		reference_load_n = 10.0, approach_speed_mps = 2.0, rolling_speed_mps = 3.0, surface = "grass"}
	for tick in 100:
		c.normal_force_n = 20.0 if tick >= 50 else 0.0
		c.approach_speed_mps = 0.0 if tick >= 50 else 2.0
		c.surface = "grass" if tick < 70 else "hard"
		a.update_contacts(tick, tick >= 85 and tick < 90, [c], .3, 1.0 / 60.0, Vector3.ZERO, 240.0)
		rows.append([a._slots[0].state.duplicate(true), a._slots[0].layer_gain.duplicate(),
			a._slots[0].impact_gain, a.touchdown_events])
	print("LEGACY_GROUND_TRACE_SHA256 ", var_to_bytes(rows).hex_encode().sha256_text())
	a.free()
	print("Legacy ground trace complete")
	quit()
