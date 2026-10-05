# Control-linkage closure and lifecycle checks; no changes to flight input.
# Run: godot --headless --path app --script res://aircraft/verify_controls.gd
extends SceneTree

const AirplaneAdapter := preload("res://render/airplane.gd")
const ControlsBuilder := preload("res://aircraft/ugly_stik_controls.gd")
const LINK_TOLERANCE_M := 0.00025
const SURFACE_SWEEPS := {
	"aileron_left": 20.0,
	"aileron_right": 20.0,
	"elevator": 20.0,
	"rudder": 25.0,
}

var _checks := 0
var _failures := 0
var _max_closure := 0.0
var _max_length_error := 0.0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _collect_ids(node: Node, output: Array[int]) -> void:
	output.append(node.get_instance_id())
	for child in node.get_children():
		_collect_ids(child, output)


func _pose_rotations(surface_name := "", degrees := 0.0) -> Dictionary:
	var rotations := {
		"aileron_left": {"x": 0.0, "y": 0.0},
		"aileron_right": {"x": 0.0, "y": 0.0},
		"elevator": {"x": 0.0, "y": 0.0},
		"rudder": {"x": 0.0, "y": 0.0},
	}
	var angle := deg_to_rad(degrees)
	match surface_name:
		"aileron_right": rotations.aileron_right.x = -angle
		"aileron_left": rotations.aileron_left.x = angle
		"elevator": rotations.elevator.x = -angle
		"rudder": rotations.rudder.y = angle
	return rotations


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane: Dictionary = AirplaneAdapter.build()
	var root: Node3D = airplane.root
	var carrier := Node3D.new()
	carrier.name = "transformed_test_carrier"
	carrier.transform = Transform3D(Basis.from_euler(Vector3(0.11, -0.37, 0.22)), Vector3(1.7, -0.4, 2.2))
	get_root().add_child(carrier)
	root.transform = Transform3D(Basis.from_euler(Vector3(-0.24, 0.51, -0.16)), Vector3(-0.6, 0.8, 0.35))
	carrier.add_child(root)
	root.force_update_transform()
	var controls: Dictionary = airplane.controls
	_check("control builder succeeds", controls.get("ok", false), str(controls.get("failures", [])))
	if not controls.get("ok", false):
		print("%d checks, %d failed" % [_checks, _failures])
		quit(1)
	_check("two Jensen aileron servos", controls.servos.has_all(["aileron_left", "aileron_right"]))
	_check("two tail servos", controls.servos.has_all(["elevator", "rudder"]))
	_check("static throttle servo marked unanimated", controls.servos.has("throttle") and not controls.servos.throttle.animated)
	_check("one bellcrank per semispan", controls.mechanisms.aileron_left.kind == "bellcrank" and controls.mechanisms.aileron_right.kind == "bellcrank")
	_check("tail pushrods use direct closure", controls.mechanisms.elevator.kind == "direct" and controls.mechanisms.rudder.kind == "direct")

	var node_ids_before: Array[int] = []
	_collect_ids(root, node_ids_before)
	var neutral_angles: Dictionary = {}
	for mechanism_name in controls.mechanisms:
		neutral_angles[mechanism_name] = {
			"servo": controls.mechanisms[mechanism_name].last_servo_angle,
			"bell": controls.mechanisms[mechanism_name].get("last_bell_angle", 0.0),
			"rods": _rod_lengths(controls.mechanisms[mechanism_name]),
		}
	var initial_audit: Dictionary = ControlsBuilder.audit(controls)
	_check("neutral audit closes", initial_audit.ok, str(initial_audit.failures))
	_check("root really is transformed", root.global_position.distance_to(Vector3.ZERO) > 1.0)
	_check("root-local horn maps through transformed hierarchy", _transformed_horn_matches(root, controls.mechanisms.aileron_left))

	ControlsBuilder.set_maintenance(controls, true)
	_check("maintenance opens internal installation", controls.maintenance_group.visible)
	ControlsBuilder.set_maintenance(controls, false)
	_check("maintenance restores default visibility", not controls.maintenance_group.visible)

	for surface_name in SURFACE_SWEEPS:
		var limit_deg: float = SURFACE_SWEEPS[surface_name]
		for index in range(21):
			var amount := -1.0 + float(index) / 10.0
			AirplaneAdapter.apply_surfaces(airplane, _pose_rotations(surface_name, amount * limit_deg))
			root.force_update_transform()
			var result: Dictionary = ControlsBuilder.audit(controls)
			_max_closure = maxf(_max_closure, float(result.max_closure_error_m))
			_max_length_error = maxf(_max_length_error, float(result.max_length_error_m))
			_check("%s pose %d has continuous closure" % [surface_name, index], result.ok, str(result.failures))
			_check("%s pose %d allocates no nodes" % [surface_name, index], _same_node_ids(root, node_ids_before))
			_check("%s pose %d length within tolerance" % [surface_name, index], float(result.max_length_error_m) <= LINK_TOLERANCE_M, "%.9f m" % result.max_length_error_m)
			if index in [0, 10, 20]:
				_check("%s pose %d endpoint follows transformed hinge" % [surface_name, index], _transformed_horn_matches(root, controls.mechanisms[surface_name]))

	AirplaneAdapter.apply_surfaces(airplane, _pose_rotations())
	root.force_update_transform()
	var restored_audit: Dictionary = ControlsBuilder.audit(controls)
	_check("neutral restored after all sweeps", restored_audit.ok, str(restored_audit.failures))
	for mechanism_name in controls.mechanisms:
		var mechanism: Dictionary = controls.mechanisms[mechanism_name]
		var original: Dictionary = neutral_angles[mechanism_name]
		var servo_delta := absf(wrapf(float(mechanism.last_servo_angle) - float(original.servo), -PI, PI))
		var bell_delta := absf(wrapf(float(mechanism.get("last_bell_angle", 0.0)) - float(original.bell), -PI, PI))
		_check("%s servo branch returns to neutral" % mechanism_name, servo_delta < 1.0e-5, "delta=%.8f rad" % servo_delta)
		if mechanism.kind == "bellcrank":
			_check("%s bellcrank branch returns to neutral" % mechanism_name, bell_delta < 1.0e-5, "delta=%.8f rad" % bell_delta)
		_check("%s neutral rod lengths restore" % mechanism_name, _rod_lengths(mechanism) == original.rods, str(_rod_lengths(mechanism)))
	_check("neutral restore allocates no nodes", _same_node_ids(root, node_ids_before))
	_check("maximum swept closure <= 0.25 mm", _max_closure <= LINK_TOLERANCE_M, "%.9f m" % _max_closure)
	_check("maximum swept rod error <= 0.25 mm", _max_length_error <= LINK_TOLERANCE_M, "%.9f m" % _max_length_error)

	root.free()
	carrier.free()
	print("%d checks, %d failed; max closure %.9f m; max length error %.9f m" % [_checks, _failures, _max_closure, _max_length_error])
	quit(1 if _failures > 0 else 0)


func _rod_lengths(mechanism: Dictionary) -> Array[float]:
	var result: Array[float] = []
	for rod in mechanism.rods:
		result.append(float(rod.current_length_m))
	return result


func _same_node_ids(root: Node3D, expected: Array[int]) -> bool:
	var current: Array[int] = []
	_collect_ids(root, current)
	return current == expected


func _transformed_horn_matches(root: Node3D, mechanism: Dictionary) -> bool:
	var expected_world: Vector3 = mechanism.hinge.to_global(mechanism.horn_local)
	var root_local: Vector3 = mechanism.endpoints_root.get("horn", Vector3.INF)
	var actual_world := root.to_global(root_local)
	return expected_world.distance_to(actual_world) < 0.000001
