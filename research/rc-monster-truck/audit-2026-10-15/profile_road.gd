## Bounded cost/call-count audit using accepted dry and water poses.
extends SceneTree
const Session := preload("res://sim/ground_vehicle/session.gd")
const Field := preload("res://data/field_loader.gd")
const Lake := preload("res://data/lake_loader.gd")
const Airfield := preload("res://physics/ground_vehicle/airfield_course.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var session = Session.new()
	root.add_child(session)
	if not session.prepare_airfield(Field.load_from(), {}, Lake.load_from().lake):
		printerr(session.load_error)
		quit(1)
		return
	var course: Dictionary = session.course_snapshot()
	var model: Dictionary = session.model_snapshot()
	var receipt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/research/rc-monster-truck/RCV-water/entry-final/water-entry.json"))
	var poses := {"runway": session.state_snapshot()}
	for key in ["mud", "shallow", "deep"]:
		poses[key] = PackedFloat64Array(receipt.phases[key].state)
	for label: String in poses:
		var state: PackedFloat64Array = poses[label]
		var road := func(n: float, e: float) -> Dictionary: return Airfield.sample(course, n, e)
		var count := {"calls": 0, "us": 0, "unique": {}}
		var counted := func(n: float, e: float) -> Dictionary:
			var begin := Time.get_ticks_usec()
			var surface: Dictionary = road.call(n, e)
			count.us += Time.get_ticks_usec() - begin
			count.calls += 1
			count.unique[PackedFloat64Array([n,e]).to_byte_array().hex_encode()] = true
			return surface
		var controls := {"throttle": 0.2, "steering": 0.1, "brake": 0.0, "reverse": false}
		var sample := Vehicle.step(state, model, controls, 1.0/240.0, counted)
		if sample.size() != 31:
			printerr("Invalid probe step ",label)
			quit(1)
			return
		var begin := Time.get_ticks_usec()
		for iteration in 40: Vehicle.step(state, model, controls, 1.0/240.0, road)
		var step_us := float(Time.get_ticks_usec()-begin)/40.0
		begin = Time.get_ticks_usec()
		for iteration in 40: Vehicle.telemetry(state, model, road, controls)
		print("PROFILE ", JSON.stringify({"pose":label,"step_mean_us":step_us,"telemetry_mean_us":float(Time.get_ticks_usec()-begin)/40.0,"road_calls_per_step":count.calls,"road_us_per_step":count.us,"unique_road_points":count.unique.size(),"backend":Vehicle.backend_identity()}))
	session.free()
	quit()
