extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Model := preload("res://audio/ground_audio_model.gd")
func _initialize() -> void:
	var session := Session.new()
	session.input_enabled = false
	session.setup()
	var field := {"id": "material-test", "surfaces": [{"id": "runway", "type": "runway",
		"center_north": session.sim.state[0], "center_east": session.sim.state[1],
		"width_north_south": 100.0, "length_east_west": 100.0}]}
	var installed := session.set_field(field)
	var rows := Model.snapshot_contacts(session, field)
	var sample := session.environment.sample_support(session.sim.state.slice(0, 3), PackedFloat64Array([0, 0, 0]), session.sim.time())
	var reproduced: bool = installed and not rows.is_empty() and sample.material_id == "maintained_turf" \
		and rows.all(func(c: Dictionary) -> bool: return c.surface == "hard")
	print("Turf-as-pavement defect reproduced: ", reproduced)
	session.free()
	quit(0 if reproduced else 1)
