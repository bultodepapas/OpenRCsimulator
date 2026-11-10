# BL-09: three-way articulation parity for every blimp skin. The Blender inventory (assets/aircraft/rc-blimp-5m/
# geometry.json, measured from the delivered .blend by export_blender.py) records the rotor slipstream axis at 0/45/90
# (and 120) degrees of vector travel. The imported GLB posed by the visual adapter and the physics thrust direction of
# the stage law must both match it, and the posed rotor hubs must sit where the physics applies thrust.
extends SceneTree

const Visual := preload("res://vehicles/airship/airship_visual.gd")
const Catalog := preload("res://vehicles/airship/airship_catalog.gd")
const Data := preload("res://physics/airship/airship_data.gd")
const Dynamics := preload("res://physics/airship/airship_dynamics.gd")

const GEOMETRY := "res://../assets/aircraft/rc-blimp-5m/geometry.json"
const AXIS_TOLERANCE := 1e-3
const HUB_TOLERANCE_M := 2e-3

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


## Godot render axes (nose -Z, right +X, up +Y) to body FRD.
static func _frd(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([-v.z, v.x, -v.y])


static func _distance(a: PackedFloat64Array, b: Array) -> float:
	return sqrt(pow(a[0] - float(b[0]), 2.0) + pow(a[1] - float(b[1]), 2.0) + pow(a[2] - float(b[2]), 2.0))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var geometry_path := ProjectSettings.globalize_path("res://").path_join("../assets/aircraft/rc-blimp-5m/geometry.json").simplify_path()
	var geometry: Variant = JSON.parse_string(FileAccess.get_file_as_string(geometry_path))
	var loaded := Data.load_file("res://data/airships/rc-blimp-5m.json")
	_check("Blender inventory and generated data load", typeof(geometry) == TYPE_DICTIONARY and loaded.ok, geometry_path)
	if typeof(geometry) != TYPE_DICTIONARY or not loaded.ok:
		_finish()
		return
	var derived := Data.derive(loaded.data, 1.225, 9.80665, 0.08)
	var model: Dictionary = derived.model
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/airships/rc-blimp-5m.json"))
	var presentation: Dictionary = raw.presentation
	var vectors: Dictionary = geometry.vectors
	var rest := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for skin_id: String in Catalog.SKIN_IDS:
		var visual := Visual.new()
		_check("%s: GLB builds with every binding" % skin_id, visual.build(presentation, skin_id), str(visual.error))
		if visual.root == null:
			continue
		root.add_child(visual.root)
		var worst_axis := 0.0
		var worst_hub := 0.0
		var worst_physics := 0.0
		for vector_key: String in ["port", "starboard", "stern"]:
			var spec: Dictionary = vectors[vector_key]
			var vector_index := ["port", "starboard", "stern"].find(vector_key)
			var rotor_key := "rotor_" + str(spec.rotor)
			var binding: Dictionary = presentation.bindings[rotor_key]
			var rotor_index := -1
			for i in model.rotors.size():
				if int(model.rotors[i].vector) == vector_index:
					rotor_index = i
			for angle_key: String in spec.rotor_axis_at:
				var angle := deg_to_rad(float(angle_key))
				var continuous := PackedFloat64Array()
				continuous.resize(Data.CONTINUOUS_SIZE)
				continuous[Data.VECTOR + vector_index] = angle
				visual.pose(rest, continuous, 0.0)
				var node := visual.root.find_child(str(binding.node), true, false) as Node3D
				var local := Vector3(binding.local_axis[0], binding.local_axis[1], binding.local_axis[2])
				var spin := _frd((node.global_basis * local).normalized())
				var truth: Array = spec.rotor_axis_at[angle_key]
				worst_axis = maxf(worst_axis, _distance(spin, truth))
				# Physics: thrust on the vehicle is opposite the slipstream axis; the hub follows the same pivot.
				var rotor: Dictionary = model.rotors[rotor_index]
				var vec: Dictionary = model.vectors[vector_index]
				var moved := Dynamics._rotate_axis_and_hub(rotor.thrust_axis, rotor.hub, vec.pivot, vec.axis, angle)
				worst_physics = maxf(worst_physics, _distance(moved.slice(0, 3), [-float(truth[0]), -float(truth[1]), -float(truth[2])]))
				worst_hub = maxf(worst_hub, _distance(_frd(node.global_position), Array(moved.slice(3, 6))))
		_check("%s: posed GLB rotor axes match the Blender inventory at every vector angle" % skin_id, worst_axis < AXIS_TOLERANCE, str(worst_axis))
		_check("%s: physics thrust directions match the Blender inventory" % skin_id, worst_physics < AXIS_TOLERANCE, str(worst_physics))
		_check("%s: posed rotor hubs sit where the physics applies thrust" % skin_id, worst_hub < HUB_TOLERANCE_M, str(worst_hub) + " m")
		# Stable hinge names (AGENTS.md): every inventory node exists in the GLB.
		var missing: Array = []
		for item: Dictionary in geometry.glb_nodes:
			if visual.root.find_child(str(item.name), true, false) == null and str(item.name) != "airship":
				missing.append(item.name)
		_check("%s: every inventoried GLB node exists" % skin_id, missing.is_empty(), str(missing))
		visual.root.free()
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
