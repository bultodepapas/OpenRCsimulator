# Records the golden flights (tests/golden/*.json). NOT a test: run it only after a deliberate physics change, and say
# why in the commit message (test_golden.gd fails until the goldens match the new physics).
# Run: godot --headless --path . --script res://tests/record_golden.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Golden := preload("res://tests/golden_flights.gd")


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Golden.DIR))
	for name in Golden.NAMES:
		var g := Golden.record(session, name)
		var f := FileAccess.open(ProjectSettings.globalize_path(Golden.path(name)), FileAccess.WRITE)
		f.store_string(JSON.stringify(g, " ", false, true) + "\n")
		f.close()
		print("recorded %s: %d ticks, %d input changes, %d checkpoints" % [name, g.ticks, g.inputs.size(), g.checkpoints.size()])
	quit()
