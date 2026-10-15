## Paired kernel regression using identical quantized controls and initial state.
## This deliberately isolates the integrator from the closed-loop driver and Session.
extends SceneTree
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Field := preload("res://data/field_loader.gd")
const Airfield := preload("res://physics/ground_vehicle/airfield_course.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var reference = load(args[0])
	reference.set_backend_override_for_tests("gdscript_reference")
	Vehicle.set_backend_override_for_tests("gdscript_reference")
	var data := Data.load_default()
	var built := Airfield.build(Field.load_from())
	if not data.get("ok", false) or not built.get("ok", false):
		quit(1)
		return
	var road := func(n: float, e: float) -> Dictionary: return Airfield.sample(built.course, n, e)
	var input := FileAccess.open(args[1], FileAccess.READ)
	var header := input.get_csv_line()
	var first := input.get_csv_line()
	var initial := PackedFloat64Array()
	for name in Vehicle.STATE_LAYOUT:
		initial.append(float(first[header.find("state_" + name)]))
	var old_state := initial.duplicate()
	var new_state := initial.duplicate()
	var maximum := PackedFloat64Array()
	maximum.resize(Vehicle.STATE_SIZE)
	var ticks := 0
	var complete := true
	var controls_bytes := PackedByteArray()
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() != header.size(): continue
		var control := {"throttle": float(row[header.find("throttle")]), "steering": float(row[header.find("steering")]),
			"brake": float(row[header.find("brake")]), "reverse": false}
		controls_bytes.append_array(PackedFloat64Array([control.throttle,control.steering,control.brake,0.0]).to_byte_array())
		old_state = reference.step(old_state, data.model, control, 1.0/240.0, road)
		new_state = Vehicle.step(new_state, data.model, control, 1.0/240.0, road)
		if old_state.size() != Vehicle.STATE_SIZE or new_state.size() != Vehicle.STATE_SIZE:
			complete = false
			break
		for channel in Vehicle.STATE_SIZE:
			complete = complete and is_finite(old_state[channel]) and is_finite(new_state[channel])
			maximum[channel] = maxf(maximum[channel], absf(new_state[channel] - old_state[channel]))
		ticks += 1
		if not complete: break
	input.close()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(controls_bytes)
	var report := {"complete":complete,"ticks":ticks,"reference_solver":reference.SOLVER_VERSION,"candidate_solver":Vehicle.SOLVER_VERSION,
		"backend":"gdscript_reference for both kernels", "controls_sha256":hashing.finish().hex_encode(),
		"initial_state":Array(initial),"state_layout":Vehicle.STATE_LAYOUT,"max_absolute_channel_difference":Array(maximum),
		"reference_final":Array(old_state),"candidate_final":Array(new_state),"physical_validation":false,
		"scope":"Same 9-decimal CSV controls; same first CSV state; bare kernels, no damage or driver feedback. Baseline circuit had zero damage."}
	var output := FileAccess.open(args[2], FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t")+"\n")
	output.close()
	print("PAIR ",JSON.stringify({"complete":complete,"ticks":ticks,"max_position_axis_difference_m":maxf(maximum[0],maxf(maximum[1],maximum[2]))}))
	quit(0 if complete else 1)
