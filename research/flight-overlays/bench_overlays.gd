# HUD-12: per-frame CPU cost of the flight overlays in a live flight scene (snapshot + refresh, as main.gd calls them).
# Run from app/: "$(./get-godot.sh)" --headless --path . --audio-driver Dummy --script "$PWD/../research/flight-overlays/bench_overlays.gd"
# Prints mean and p95 over 1200 frames per preset, and the 10 Hz refresh frames separately. Wall-clock: machine-specific.
extends SceneTree
func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	for preset in ["pilot", "full"]:
		var flight: Node = load("res://main.tscn").instantiate()
		flight.overlays_enabled = true
		flight.overlay_settings = { preset = preset }
		root.add_child(flight)
		for i in 30:
			await process_frame
		var overlays = flight.get("_overlays")
		var OM = load("res://render/overlays/overlay_manager.gd")
		var all := PackedFloat64Array()
		var refresh := PackedFloat64Array()
		for i in 1200:
			var t0 := Time.get_ticks_usec()
			var due: bool = overlays.tick(1.0 / 60.0)
			if due:
				overlays.refresh_numbers(flight.call("_overlay_snapshot"))
			overlays.refresh_sticks(OM.sticks(flight.session))
			var dt := float(Time.get_ticks_usec() - t0)
			all.append(dt)
			if due:
				refresh.append(dt)
			await process_frame
		all.sort(); refresh.sort()
		var mean := 0.0
		for v in all: mean += v
		print("BENCH %s frames=%d mean=%.0f us p95=%.0f us | refresh frames=%d median=%.0f us max=%.0f us" % [preset, all.size(), mean / all.size(), all[int(0.95 * all.size())], refresh.size(), refresh[refresh.size() / 2], refresh[-1]])
		flight.queue_free()
		await process_frame
	quit()
