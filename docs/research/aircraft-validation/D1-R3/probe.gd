# D1-R3 evidence probe: the audit B3 layout and both real gear sections through the loader.
# Run: godot --headless --path app --script <this file>
extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")

func _initialize() -> void:
	for f in ["jensen_ugly_stik_60", "p51d_mustang_120"]:
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/%s.json" % f))
		var r := AD.validate_and_derive(raw)
		print("%s: ok=%s errors=%s" % [f, r.ok, r.errors])
	# Audit B3: contacts (0, -0.18), (1, 0.18), (1, 0) in x_aft/y_right; the Stik CG (0.1209, 0) is inside both
	# coordinate ranges but outside the support triangle.
	var raw2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aircraft/jensen_ugly_stik_60.json"))
	var xy := [[0.0, -0.18], [1.0, 0.18], [1.0, 0.0]]
	for i in 3:
		raw2.landing_gear.contacts[i].position.value[0] = xy[i][0]
		raw2.landing_gear.contacts[i].position.value[1] = xy[i][1]
	var r2 := AD.validate_and_derive(raw2)
	print("audit B3 layout: ok=%s errors=%s" % [r2.ok, r2.errors])
	quit(0)
