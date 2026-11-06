extends SceneTree

const Extra := preload("res://aircraft/extra_300s_model.gd")

func _initialize() -> void:
	call_deferred("run")

func closest(vertices: PackedVector3Array, target: Vector3) -> float:
	var best := INF
	for v in vertices: best = minf(best, v.distance_to(target))
	return best

func run() -> void:
	var model := Extra.build()
	root.add_child(model.root)
	var prop: Node3D = model.propeller
	var blade: MeshInstance3D = prop.get_node("blade_a")
	var vertices: PackedVector3Array = blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var p: Dictionary = Extra.D.propeller
	var r: float = lerpf(p.hub_radius, p.diameter / 2.0, sin(PI / 2.0 * 9.0 / 18.0))
	var chord: float = Extra._table(p.blade.chord_fraction_of_radius, r / (p.diameter / 2.0)) * p.diameter / 2.0
	var beta := atan(float(p.pitch) / (TAU * r))
	var chord_direction := Vector3(0.0, cos(beta), -sin(beta))
	var leading := Vector3(r, 0.0, 0.0) + chord_direction * 0.35 * chord
	var trailing := Vector3(r, 0.0, 0.0) - chord_direction * 0.65 * chord
	var axis := Vector3(0.0, 0.0, -1.0) # positive RPM, render/airplane.gd:149 and main.gd:3175
	var midpoint := 0.5 * (leading + trailing)
	var velocity := axis.cross(midpoint)
	var advancing := (leading - trailing).dot(velocity)
	var leading_error := closest(vertices, leading)
	var trailing_error := closest(vertices, trailing)
	print("BLADE_WITNESS ", JSON.stringify({"radius_m": r, "chord_m": chord, "leading": [leading.x,leading.y,leading.z], "trailing": [trailing.x,trailing.y,trailing.z], "leading_mesh_distance_m": leading_error, "trailing_mesh_distance_m": trailing_error, "positive_rpm_axis": [axis.x,axis.y,axis.z], "angular_velocity_unit_point_velocity": [velocity.x,velocity.y,velocity.z], "leading_minus_trailing_dot_velocity": advancing, "opposite_spin_control": -advancing}))
	var ok := leading_error < 1e-6 and trailing_error < 1e-6 and advancing < 0.0
	model.root.free()
	print("SPIN_PROBE_DONE ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
