## RCV visual audit 2026-10-15: cross-check the runtime adapter against accepted FRD geometry.
## Headless probe; no physics world or render capture is created.
extends SceneTree

const Model := preload("res://vehicles/ground/mt8_model.gd")
const Frames := preload("res://render/frames.gd")
const DATA_PATH := "res://data/vehicles/ground/mt8_bisonte.json"
const CORNERS := ["FL", "FR", "RL", "RR"]

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var parameters: Dictionary = data.get("parameters", {})
	var cg_height := _quantity(parameters, "cg_height_above_chassis_datum_m")
	var rest_below := _quantity(parameters, "wheel_center_rest_below_chassis_datum_m")
	var arm_length := _quantity(parameters, "arm_length_m")
	var corner_forward: PackedFloat64Array = _quantity_array(parameters, "corner_x_datum_frd_m")
	var corner_right: PackedFloat64Array = _quantity_array(parameters, "corner_y_datum_frd_m")
	_check(data.get("format") == "openrc-ground-vehicle" and corner_forward.size() == 4
		and corner_right.size() == 4, "accepted MT8 data loads with ordered FRD wheel stations")
	if corner_forward.size() != 4 or corner_right.size() != 4:
		quit(1)
		return

	var visual := Model.build()
	_check(bool(visual.get("ok", false)), "bundled visual builds", str(visual.get("error", "")))
	if not bool(visual.get("ok", false)):
		quit(1)
		return
	root.add_child(visual.root)
	await process_frame

	var state := PackedFloat64Array()
	state.resize(31)
	state[6] = 1.0
	state[0] = 14.0
	state[1] = -3.0
	state[2] = -1.2
	var yaw := 0.71
	state[6] = cos(yaw * 0.5)
	state[9] = sin(yaw * 0.5)
	var travel := PackedFloat64Array([-0.061, 0.041, -0.019, 0.047])
	var spin_angle := PackedFloat64Array([0.6, -0.2, 1.1, 2.4])
	for index in 4:
		state[13 + index] = travel[index]
		state[25 + index] = spin_angle[index]
	state[29] = 0.24
	var drawn: bool = Model.draw(visual, state, cg_height)
	_check(drawn, "runtime adapter accepts a finite 31-value physics state")
	if not drawn:
		quit(1)
		return

	var body_basis := Frames.quat_to_render(state.slice(6, 10))
	var cg_world := Frames.ned_to_render([state[0], state[1], state[2]])
	var rendered_cg: Vector3 = visual.root.global_transform * Vector3(0.0, cg_height, 0.0)
	_check(rendered_cg.distance_to(cg_world) < 1.0e-6,
		"body datum offset keeps the model CG on the simulated NED position",
		str(rendered_cg.distance_to(cg_world)))
	var geometry_matches := true
	for index in 4:
		var corner_right_value := corner_right[index]
		var side := signf(corner_right_value)
		var t := clampf(travel[index], -0.07, 0.05)
		var lateral_offset := sqrt(arm_length * arm_length - t * t)
		var right := corner_right_value + side * (lateral_offset - arm_length)
		var forward := corner_forward[index]
		var relative_to_cg := Vector3(right, -(cg_height + rest_below - t), -forward)
		var expected_world := cg_world + body_basis * relative_to_cg
		var node: Node3D = visual.nodes[CORNERS[index] + "_Spin"]
		var actual_world: Vector3 = node.global_position
		geometry_matches = geometry_matches and actual_world.distance_to(expected_world) < 1.0e-5
	_check(geometry_matches,
		"asymmetric wheel travel maps to the accepted FRD stations and CG datum",
		"world wheel centers must agree with physics hub coordinates")

	var steering_matches := true
	for corner in ["FL", "FR"]:
		var steer_node: Node3D = visual.nodes[corner + "_Steer"]
		var forward_axis := steer_node.global_basis * Vector3.FORWARD
		steering_matches = steering_matches and forward_axis.x > 0.1
	_check(steering_matches, "positive physics steer turns both front wheels right in the render frame")
	var spin_matches := true
	for index in 4:
		var spin_node: Node3D = visual.nodes[CORNERS[index] + "_Spin"]
		var tire_top := (spin_node.global_basis * Vector3.UP).normalized()
		var top_motion := tire_top - body_basis * Vector3.UP
		var forward_world := body_basis * Vector3.FORWARD
		spin_matches = spin_matches and top_motion.dot(forward_world) * spin_angle[index] > 0.02
	_check(spin_matches, "signed physics wheel angles roll the tire tread in the matching direction")

	state[13] = 0.055
	state[14] = -0.075
	var overshoot_drawn: bool = Model.draw(visual, state, cg_height)
	var overshoot_reported := bool(visual.get("travel_outside_art", false))
	var front_left_y: float = (visual.nodes["FL_Spin"] as Node3D).global_position.y
	var front_right_y: float = (visual.nodes["FR_Spin"] as Node3D).global_position.y
	_check(overshoot_drawn and overshoot_reported
		and is_equal_approx(front_left_y, (cg_world + body_basis * Vector3(0.0, -(cg_height + rest_below - 0.05), -corner_forward[0])).y)
		and is_equal_approx(front_right_y, (cg_world + body_basis * Vector3(corner_right[1], -(cg_height + rest_below + 0.07), -corner_forward[1])).y),
		"soft-stop overtravel saturates only the art envelope and reports the mismatch")

	print("RCV visual adapter probe: %d checks, %d failures" % [checks, failures])
	visual.root.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _quantity(parameters: Dictionary, key: String) -> float:
	return float(parameters.get(key, {}).get("value", NAN))


func _quantity_array(parameters: Dictionary, key: String) -> PackedFloat64Array:
	var values: Array = parameters.get(key, {}).get("value", [])
	var result := PackedFloat64Array()
	for value in values:
		result.append(float(value))
	return result
