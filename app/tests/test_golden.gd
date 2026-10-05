# D8a: golden flights replay within tolerance (see tests/golden_flights.gd). A physics change that alters any of them
# fails here; if the change is deliberate, re-record with tests/record_golden.gd and say so in the commit.
# Run: godot --headless --path . --script res://tests/test_golden.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Golden := preload("res://tests/golden_flights.gd")

var _failures := 0


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	for name in Golden.NAMES:
		var text := FileAccess.get_file_as_string(Golden.path(name))
		var g = JSON.parse_string(text) if text != "" else null
		if typeof(g) != TYPE_DICTIONARY:
			printerr("FAIL %s: missing or unreadable golden (%s)" % [name, Golden.path(name)])
			_failures += 1
			continue
		var r := Golden.replay(session, g)
		print(("ok   " if r.ok else "FAIL ") + "golden %s replays (%d ticks): %s" % [name, int(g.ticks), r.message])
		if not r.ok:
			_failures += 1
	print("%d golden flights, %d failed" % [Golden.NAMES.size(), _failures])
	quit(1 if _failures > 0 else 0)
