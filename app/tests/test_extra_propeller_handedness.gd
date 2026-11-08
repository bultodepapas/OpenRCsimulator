# E300-06: decode the actual visual mesh; production positive RPM must meet its leading edge first.
extends SceneTree

const Model := preload("res://aircraft/extra_300s_model.gd")
const Geometry := preload("res://aircraft/extra_300s_geometry.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")

var checks := 0
var failures := 0
var minimum_alignment := INF


func check(label: String, passed: bool, detail := "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane: Dictionary = AirplaneBuilder.build(AirplaneBuilder.EXTRA_ID)
	check("accepted Extra visual binding", not airplane.is_empty())
	if airplane.is_empty():
		quit(1)
		return
	root.add_child(airplane.root)
	check("finite glow positive RPM retains production negative shaft rotation", airplane.propeller_spin_sign == -1.0)
	check("stable propeller node and both independent blades", airplane.propeller.name == "propeller" and airplane.propeller.has_node("blade_a") and airplane.propeller.has_node("blade_b"))
	var blade: MeshInstance3D = airplane.propeller.get_node("blade_a")
	var vertices: PackedVector3Array = blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var aligned_area := 0.0
	var total_area := 0.0
	var raw_indices = blade.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var indices := PackedInt32Array() if raw_indices == null else PackedInt32Array(raw_indices)
	if indices.is_empty():
		for i in vertices.size():
			indices.append(i)
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var face: Vector3 = (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		total_area += face.length()
		if face.dot(normals[a] + normals[b] + normals[c]) >= 0.0:
			aligned_area += face.length()
	check("mesh supplies complete triangles and normals", indices.size() % 3 == 0 and normals.size() == vertices.size())
	# The inherited loft has tiny tip/edge triangles whose smooth vertex normals disagree.
	# This gate detects an inverted surface while retaining that existing 0.18 percent area.
	check("clockwise triangles agree with shading normals over 99 percent of blade area", total_area > 0.0 and aligned_area / total_area > 0.99, "area fraction=%.9f" % (aligned_area / total_area))
	var p: Dictionary = Geometry.DATA.propeller
	var tip: float = p.diameter / 2.0
	# Exclude the collapsed tip and buried hub. Endpoints are identified by their authored Z
	# and unsigned Y distances, independently of the expected direction of rotation.
	for station in range(2, 17):
		var radius := lerpf(float(p.hub_radius), tip, sin(PI / 2.0 * station / 18.0))
		var chord := _interpolate(p.blade.chord_fraction_of_radius, radius / tip) * tip
		var pitch_angle := atan(float(p.pitch) / (TAU * radius))
		var leading := _endpoint(vertices, radius, -0.35 * chord * sin(pitch_angle), 0.35 * chord * cos(pitch_angle))
		var trailing := _endpoint(vertices, radius, 0.65 * chord * sin(pitch_angle), 0.65 * chord * cos(pitch_angle))
		check("station %d actual LE/TE found" % station, leading.error < 1e-6 and trailing.error < 1e-6)
		var le: Vector3 = leading.point
		var te: Vector3 = trailing.point
		var section: Vector3 = (le - te).normalized()
		check("station %d preserves pitch and forward leading edge" % station, le.z < te.z and absf((le - te).length() - chord) < 1e-6 and absf(absf(section.z) - sin(pitch_angle)) < 1e-5)
		var forward: Vector3 = section.cross(Vector3.RIGHT).normalized()
		if forward.z > 0.0:
			forward = -forward
		var high := 0.0
		var low := 0.0
		for point: Vector3 in vertices:
			if absf(point.x - radius) < 1e-6:
				var distance := (point - te).dot(forward)
				high = maxf(high, distance)
				low = minf(low, distance)
		check("station %d cambered face remains forward" % station, high > 5.0 * absf(low) and low < 0.0)
		for phase in [0.0, 0.37, 1.81]:
			airplane.propeller.rotation.z = phase
			for label in ["blade_a", "blade_b"]:
				var node: Node3D = airplane.propeller.get_node(label)
				var basis: Basis = node.global_basis
				var motion: Vector3 = (airplane.propeller.global_basis * Vector3(0, 0, airplane.propeller_spin_sign)).cross(basis * (le + te) * 0.5)
				var alignment: float = (basis * (le - te)).dot(motion)
				minimum_alignment = minf(minimum_alignment, alignment)
				check("station %d %s phase %.2f meets LE first; reversed sign fails" % [station, label, phase], alignment > 0.0 and -alignment < 0.0, "alignment=%.9f" % alignment)
	var second: Dictionary = AirplaneBuilder.build(AirplaneBuilder.EXTRA_ID)
	check("independent propeller instances", not second.is_empty() and second.propeller != airplane.propeller and is_zero_approx(second.propeller.rotation.z))
	if not second.is_empty():
		second.root.free()
	airplane.root.free()
	print("Extra propeller handedness: %d checks, %d failures; minimum LE-motion alignment %.9f" % [checks, failures, minimum_alignment])
	quit(1 if failures else 0)


func _endpoint(vertices: PackedVector3Array, radius: float, z: float, unsigned_y: float) -> Dictionary:
	var best := INF
	var selected := Vector3.ZERO
	for point: Vector3 in vertices:
		var error := Vector3(point.x - radius, absf(point.y) - unsigned_y, point.z - z).length()
		if error < best:
			best = error
			selected = point
	return {point = selected, error = best}


func _interpolate(rows: Array, x: float) -> float:
	for i in rows.size() - 1:
		if x <= float(rows[i + 1][0]):
			return lerpf(float(rows[i][1]), float(rows[i + 1][1]), (x - float(rows[i][0])) / (float(rows[i + 1][0]) - float(rows[i][0])))
	return float(rows[-1][1])
