# V03/V06/V07: glow .61 installation (US-V13: the owner's O.S. 61 SF model), detailed propeller and visible hardware.
# All visual choices are kept separate from shared flight/model geometry.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const GearFlex := preload("res://aircraft/ugly_stik_gear_flex.gd")
const D: Dictionary = Geometry.DATA

const CASE_COLOR := Color("858d91")
const FIN_COLOR := Color("a3aaad")
const STEEL_COLOR := Color("c0c3c3")
const DARK_METAL_COLOR := Color("51585b")
const WOOD_COLOR := Color("a98250")
const BAND_COLOR := Color("302d2a")
const RUBBER_COLOR := Color("202124")
const TIRE_LINE_COLOR := Color("292b2e")


static func _material(color: Color, profile: String, double_sided: bool = false) -> StandardMaterial3D:
	var mat: StandardMaterial3D = Finish.material(color, profile)
	if not double_sided:
		return mat
	var local_mat := mat.duplicate() as StandardMaterial3D
	local_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return local_mat


static func _surface(color: Color, profile: String, double_sided: bool = false) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material(color, profile, double_sided))
	return st


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal: Vector3 = outward.normalized()
	var p1: Vector3 = b
	var p2: Vector3 = c
	if (p1 - a).cross(p2 - a).dot(normal) > 0.0:
		p1 = c
		p2 = b
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(p1)
	st.set_normal(normal)
	st.add_vertex(p2)


static func _smooth_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var p1: Vector3 = b
	var p2: Vector3 = c
	var n1: Vector3 = nb
	var n2: Vector3 = nc
	var face: Vector3 = (b - a).cross(c - a)
	if face.dot(na + nb + nc) > 0.0:
		p1 = c
		p2 = b
		n1 = nc
		n2 = nb
	st.set_normal(na.normalized())
	st.add_vertex(a)
	st.set_normal(n1.normalized())
	st.add_vertex(p1)
	st.set_normal(n2.normalized())
	st.add_vertex(p2)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_triangle(st, a, b, c, outward)
	_triangle(st, a, c, d, outward)


static func _smooth_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	_smooth_triangle(st, a, b, c, na, nb, nc)
	_smooth_triangle(st, a, c, d, na, nc, nd)


static func _buckets(specs: Array) -> Dictionary:
	var result: Dictionary = {}
	for spec in specs:
		var key: String = String(spec[0])
		var color: Color = spec[1]
		var profile: String = String(spec[2])
		var double_sided: bool = bool(spec[3]) if spec.size() > 3 else false
		result[key] = _surface(color, profile, double_sided)
	return result


static func _flush(parent: Node3D, label: String, buckets: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in buckets.keys():
		var st: SurfaceTool = buckets[key] as SurfaceTool
		var vertices: Variant = st.commit_to_arrays()[Mesh.ARRAY_VERTEX]
		if vertices == null or vertices.is_empty():
			continue
		st.commit(mesh)
	if mesh.get_surface_count() == 0:
		return null
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


static func _frame(axis_value: Vector3) -> Array[Vector3]:
	var axis: Vector3 = axis_value.normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.82 else Vector3.UP
	var u: Vector3 = axis.cross(reference).normalized()
	var v: Vector3 = axis.cross(u).normalized()
	return [u, v, axis]


static func _cylinder(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float, segments: int, caps: bool = true) -> void:
	var delta: Vector3 = b - a
	var length: float = delta.length()
	if length <= 0.0000001:
		return
	var axis: Vector3 = delta / length
	var frame: Array[Vector3] = _frame(axis)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		var radial: Vector3 = (u * cos(angle) + v * sin(angle)).normalized()
		ring_a.append(a + radial * radius_a)
		ring_b.append(b + radial * radius_b)
	for i in range(segments):
		var j: int = (i + 1) % segments
		var outward: Vector3 = ((ring_a[i] - a).normalized() + (ring_a[j] - a).normalized() + (ring_b[i] - b).normalized() + (ring_b[j] - b).normalized()).normalized()
		_quad(st, ring_a[i], ring_b[i], ring_b[j], ring_a[j], outward)
	if caps:
		for i in range(segments):
			var j: int = (i + 1) % segments
			_triangle(st, a, ring_a[j], ring_a[i], -axis)
			_triangle(st, b, ring_b[i], ring_b[j], axis)


static func _washer(st: SurfaceTool, center: Vector3, axis_value: Vector3, outer_radius: float, inner_radius: float, thickness: float, segments: int = 20) -> void:
	var axis: Vector3 = axis_value.normalized()
	var frame: Array[Vector3] = _frame(axis)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	var a: Vector3 = center - axis * thickness * 0.5
	var b: Vector3 = center + axis * thickness * 0.5
	for i in range(segments):
		var j: int = (i + 1) % segments
		var angle_a: float = TAU * float(i) / float(segments)
		var angle_b: float = TAU * float(j) / float(segments)
		var ra: Vector3 = (u * cos(angle_a) + v * sin(angle_a)).normalized()
		var rb: Vector3 = (u * cos(angle_b) + v * sin(angle_b)).normalized()
		var outer_a: Vector3 = center + axis * (-thickness * 0.5) + ra * outer_radius
		var outer_b: Vector3 = center + axis * (thickness * 0.5) + ra * outer_radius
		var outer_c: Vector3 = center + axis * (thickness * 0.5) + rb * outer_radius
		var outer_d: Vector3 = center + axis * (-thickness * 0.5) + rb * outer_radius
		var inner_a: Vector3 = center + axis * (-thickness * 0.5) + ra * inner_radius
		var inner_b: Vector3 = center + axis * (thickness * 0.5) + ra * inner_radius
		var inner_c: Vector3 = center + axis * (thickness * 0.5) + rb * inner_radius
		var inner_d: Vector3 = center + axis * (-thickness * 0.5) + rb * inner_radius
		_quad(st, outer_a, outer_b, outer_c, outer_d, (ra + rb).normalized())
		_quad(st, inner_a, inner_b, inner_c, inner_d, -(ra + rb).normalized())
		_quad(st, outer_a, outer_d, inner_d, inner_a, -axis)
		_quad(st, outer_b, inner_b, inner_c, outer_c, axis)


static func _torus(st: SurfaceTool, center: Vector3, axis_value: Vector3, major_radius: float, tube_radius: float, major_segments: int = 24, minor_segments: int = 6) -> void:
	var axis: Vector3 = axis_value.normalized()
	var frame: Array[Vector3] = _frame(axis)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	for i in range(major_segments):
		var i_next: int = (i + 1) % major_segments
		var phi0: float = TAU * float(i) / float(major_segments)
		var phi1: float = TAU * float(i_next) / float(major_segments)
		var radial0: Vector3 = (u * cos(phi0) + v * sin(phi0)).normalized()
		var radial1: Vector3 = (u * cos(phi1) + v * sin(phi1)).normalized()
		for j in range(minor_segments):
			var j_next: int = (j + 1) % minor_segments
			var theta0: float = TAU * float(j) / float(minor_segments)
			var theta1: float = TAU * float(j_next) / float(minor_segments)
			var n00: Vector3 = (radial0 * cos(theta0) + axis * sin(theta0)).normalized()
			var n10: Vector3 = (radial1 * cos(theta0) + axis * sin(theta0)).normalized()
			var n11: Vector3 = (radial1 * cos(theta1) + axis * sin(theta1)).normalized()
			var n01: Vector3 = (radial0 * cos(theta1) + axis * sin(theta1)).normalized()
			var p00: Vector3 = center + radial0 * (major_radius + tube_radius * cos(theta0)) + axis * tube_radius * sin(theta0)
			var p10: Vector3 = center + radial1 * (major_radius + tube_radius * cos(theta0)) + axis * tube_radius * sin(theta0)
			var p11: Vector3 = center + radial1 * (major_radius + tube_radius * cos(theta1)) + axis * tube_radius * sin(theta1)
			var p01: Vector3 = center + radial0 * (major_radius + tube_radius * cos(theta1)) + axis * tube_radius * sin(theta1)
			_smooth_quad(st, p00, p10, p11, p01, n00, n10, n11, n01)


static func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h: Vector3 = size * 0.5
	var p: Array[Vector3] = [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z)
	]
	_quad(st, p[0], p[1], p[2], p[3], Vector3(0, 0, -1))
	_quad(st, p[5], p[4], p[7], p[6], Vector3(0, 0, 1))
	_quad(st, p[4], p[0], p[3], p[7], Vector3(-1, 0, 0))
	_quad(st, p[1], p[5], p[6], p[2], Vector3(1, 0, 0))
	_quad(st, p[3], p[2], p[6], p[7], Vector3(0, 1, 0))
	_quad(st, p[4], p[5], p[1], p[0], Vector3(0, -1, 0))


static func _ellipsoid(st: SurfaceTool, center: Vector3, radii: Vector3, latitude_steps: int = 12, longitude_steps: int = 20) -> void:
	var points: Array = []
	var normals: Array = []
	for i in range(latitude_steps + 1):
		var latitude: float = -PI * 0.5 + PI * float(i) / float(latitude_steps)
		var ring: Array[Vector3] = []
		var normal_ring: Array[Vector3] = []
		for j in range(longitude_steps):
			var longitude: float = TAU * float(j) / float(longitude_steps)
			var unit: Vector3 = Vector3(cos(latitude) * cos(longitude), sin(latitude), cos(latitude) * sin(longitude))
			var point: Vector3 = center + Vector3(unit.x * radii.x, unit.y * radii.y, unit.z * radii.z)
			var normal: Vector3 = Vector3(unit.x / radii.x, unit.y / radii.y, unit.z / radii.z).normalized()
			ring.append(point)
			normal_ring.append(normal)
		points.append(ring)
		normals.append(normal_ring)
	for i in range(latitude_steps):
		var ring_a: Array = points[i]
		var ring_b: Array = points[i + 1]
		var normal_a: Array = normals[i]
		var normal_b: Array = normals[i + 1]
		for j in range(longitude_steps):
			var k: int = (j + 1) % longitude_steps
			_smooth_quad(st, ring_a[j], ring_b[j], ring_b[k], ring_a[k], normal_a[j], normal_b[j], normal_b[k], normal_a[k])


static func _sweep_tube(st: SurfaceTool, path: Array[Vector3], radius: float, ring_segments: int = 8, cap_ends: bool = true) -> void:
	if path.size() < 2:
		return
	var rings: Array = []
	var normals: Array = []
	for i in range(path.size()):
		var tangent: Vector3
		if i == 0:
			tangent = (path[1] - path[0]).normalized()
		elif i == path.size() - 1:
			tangent = (path[i] - path[i - 1]).normalized()
		else:
			tangent = (path[i + 1] - path[i - 1]).normalized()
		var frame: Array[Vector3] = _frame(tangent)
		var ring: Array[Vector3] = []
		var ring_normals: Array[Vector3] = []
		for j in range(ring_segments):
			var angle: float = TAU * float(j) / float(ring_segments)
			var normal: Vector3 = (frame[0] * cos(angle) + frame[1] * sin(angle)).normalized()
			ring.append(path[i] + normal * radius)
			ring_normals.append(normal)
		rings.append(ring)
		normals.append(ring_normals)
	for i in range(path.size() - 1):
		var ring_a: Array = rings[i]
		var ring_b: Array = rings[i + 1]
		var normal_a: Array = normals[i]
		var normal_b: Array = normals[i + 1]
		for j in range(ring_segments):
			var k: int = (j + 1) % ring_segments
			_smooth_quad(st, ring_a[j], ring_b[j], ring_b[k], ring_a[k], normal_a[j], normal_b[j], normal_b[k], normal_a[k])
	if cap_ends:
		var start_tangent: Vector3 = (path[1] - path[0]).normalized()
		var end_tangent: Vector3 = (path[path.size() - 1] - path[path.size() - 2]).normalized()
		for i in range(ring_segments):
			var j: int = (i + 1) % ring_segments
			_triangle(st, path[0], rings[0][j], rings[0][i], -start_tangent)
			_triangle(st, path[path.size() - 1], rings.back()[i], rings.back()[j], end_tangent)


# Lathe tooling (wheels). (axial distance, radius) profiles preserve sharp machined
# shoulders while sharing radial normals; counterbores run back down the inside.
static func _turned(st: SurfaceTool, center: Vector3, axis: Vector3, profile: Array, segments := 48, smooth_profile := false) -> void:
	var frame := _frame(axis)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	var direction := axis.normalized()
	for k in range(profile.size() - 1):
		var a: Vector2 = profile[k]
		var b: Vector2 = profile[k + 1]
		var tangent := b - a
		if tangent.length_squared() < 1e-16: continue
		for i in range(segments):
			var phi0 := TAU * i / segments
			var phi1 := TAU * (i + 1) / segments
			var r0 := u * cos(phi0) + v * sin(phi0)
			var r1 := u * cos(phi1) + v * sin(phi1)
			var ta := tangent.normalized()
			var tb := ta
			if smooth_profile and k > 0: ta = (ta + (a - Vector2(profile[k - 1])).normalized()).normalized()
			if smooth_profile and k + 2 < profile.size(): tb = (tb + (Vector2(profile[k + 2]) - b).normalized()).normalized()
			var na0 := (r0 * ta.x - direction * ta.y).normalized()
			var na1 := (r1 * ta.x - direction * ta.y).normalized()
			var nb0 := (r0 * tb.x - direction * tb.y).normalized()
			var nb1 := (r1 * tb.x - direction * tb.y).normalized()
			_smooth_quad(st, center + direction * a.x + r0 * a.y, center + direction * b.x + r0 * b.y, center + direction * b.x + r1 * b.y, center + direction * a.x + r1 * a.y, na0, nb0, nb1, na1)


# US-V13: the owner's O.S. 61 SF Special Edition, modelled in Blender and bundled by
# assets/aircraft/ugly-stik-60/engine/build_engine.py on its O.S. 905 radial mount with silicone fuel and pressure lines.
# The GLB frame is the crank axis at the drive-hub face; its empties name the lever tip, intake bore and silencer outlet.
const ENGINE_SCENE := preload("res://assets/aircraft/ugly-stik-60/os61_engine.glb")
const ENGINE_REVISION := "os-61sf-se-blender-v1"
# Silencer outlet tube bore (engine-build.json outlet_bore_radius_m, probed in Blender).
const ENGINE_OUTLET_BORE_M := 0.0042
# Faces of the wooden propeller hub about the propeller node (the blade roots near the axis of _prop_blades are 19.6 mm
# thick) and the hub radius, which covers the blade roots that start at 10 % of the tip radius. The radial mount seats
# on F1, so the drive hub sits 6.0 mm inside the wooden hub: the bound propeller position (prop_z, the physics hub) is
# 6.4 mm aft of where this mount would put a hub of the delivered 14.3 mm seat.
const PROP_HUB_HALF_THICKNESS := 0.0098
const PROP_HUB_RADIUS := 0.016
# The delivered carburettor lever hangs below its barrel on the exhaust (+X) side. Pull to open: the barrel turns
# about -X as the throttle opens, so the ball link moves aft.
const THROTTLE_SIDE := 1.0
const THROTTLE_OPENING := -1.0
# US-V18b: the gas servo stands in the servo tray and drives the lever through a cable in a tube (Jensen sheet 1), which
# crosses F1 at equipment.servo_tray.throttle_f1: outboard of the radial mount, below the pressure-line grommet and
# inside the 1/4 in sides. Controls build the linkage.

static var _engine_anchors: Dictionary = {}


## Crank axis at the drive-hub face, in model space, with the mount flange's back face on F1.
static func engine_origin() -> Vector3:
	var e: Dictionary = D.equipment
	return Vector3(0, float(e.shaft_y), float(e.firewall_z) - engine_anchor("engine_firewall_face").z)


## Engine-frame position of a GLB node (lever pivot, anchors); read once from the imported scene.
static func engine_anchor(node_name: String) -> Vector3:
	if _engine_anchors.is_empty():
		var scene := ENGINE_SCENE.instantiate()
		for child in scene.get_children():
			_engine_anchors[String(child.name)] = (child as Node3D).position
		scene.free()
	return _engine_anchors[node_name]


# Carburettor barrel axis point and lever ball link at the delivered (half-throttle) pose, model space.
static func throttle_arm_pivot() -> Vector3:
	return engine_origin() + engine_anchor("engine_throttle_arm")


static func throttle_arm_tip() -> Vector3:
	return engine_origin() + engine_anchor("engine_throttle_arm_tip")


static func _adopt(scene: Node, node_name: String, parent: Node3D, position: Vector3, label := "") -> MeshInstance3D:
	var part := scene.get_node(node_name) as MeshInstance3D
	scene.remove_child(part)
	part.owner = null
	part.name = label if not label.is_empty() else node_name
	part.transform = Transform3D(Basis.IDENTITY, position)
	parent.add_child(part)
	return part


static func _add_engine(root: Node3D, propeller: Node3D) -> void:
	var origin := engine_origin()
	var scene := ENGINE_SCENE.instantiate()
	var assembly := _adopt(scene, "engine_assembly", root, origin)
	assembly.set_meta("airframe_scuff_skip", true) # bare metal, not covering (render/crash/airframe_scuffs.gd)
	# Crank nose, drive hub, washer and nut turn with the propeller; the washer closes on the wooden hub's front face.
	_adopt(scene, "engine_drive_rear", propeller, Vector3(0, 0, origin.z - propeller.position.z))
	_adopt(scene, "engine_drive_front", propeller, Vector3(0, 0, -PROP_HUB_HALF_THICKNESS - engine_anchor("engine_washer_face").z))
	# US-V09c: the lever turns with the carburettor barrel about +X; the controls pass drives its hinge.
	var hinge := Node3D.new()
	hinge.name = "carburetor_throttle_arm_hinge"
	hinge.position = throttle_arm_pivot()
	root.add_child(hinge)
	_adopt(scene, "engine_throttle_arm", hinge, Vector3.ZERO, "carburetor_throttle_arm").set_meta("airframe_scuff_skip", true)
	scene.free()
	assembly.set_meta("intake_mouth", origin + engine_anchor("engine_intake_mouth"))
	assembly.set_meta("intake_axis", (engine_anchor("engine_intake_mouth") - engine_anchor("engine_intake_inner")).normalized())
	# SM-01: the optional exhaust interface sits at the silencer's outlet tube. Coordinates are model-local; this is a
	# glow-oil trace and an optional presentation pump.
	var outlet: Vector3 = origin + engine_anchor("engine_exhaust_outlet")
	root.set_meta("exhausts", [{position = outlet, direction = (engine_anchor("engine_exhaust_outlet") - engine_anchor("engine_exhaust_upstream")).normalized(),
		radius_m = ENGINE_OUTLET_BORE_M, kind = "glow_prop", pump = true}])
	root.set_meta("engine_revision", ENGINE_REVISION)


## Blade planform and section of the propeller: stations as shares of the tip radius, chord as a share of the radius,
## blade angle, and the section's chordwise samples and thickness (share of the chord).
const BLADE_FRACTIONS: Array[float] = [0.10, 0.18, 0.29, 0.41, 0.54, 0.67, 0.79, 0.89, 0.96, 1.0]
const BLADE_CHORDS: Array[float] = [0.205, 0.255, 0.285, 0.282, 0.258, 0.222, 0.178, 0.126, 0.075, 0.025]
const BLADE_PITCH_DEG: Array[float] = [39.0, 36.0, 32.0, 28.0, 23.0, 19.0, 16.0, 14.0, 12.0, 10.0]
const BLADE_CHORD_SAMPLES: Array[float] = [0.0, 0.18, 0.42, 0.70, 0.88, 1.0]
const BLADE_THICKNESS: Array[float] = [0.0, 0.060, 0.090, 0.075, 0.035, 0.0]


static func _prop_blades(st: SurfaceTool, radius: float) -> void:
	var radial_fractions := BLADE_FRACTIONS
	var chord_scales := BLADE_CHORDS
	var pitch_degrees := BLADE_PITCH_DEG
	var chord_samples := BLADE_CHORD_SAMPLES
	var thickness := BLADE_THICKNESS
	for sign in [-1.0, 1.0]:
		var upper: Array = []
		var lower: Array = []
		for i in range(radial_fractions.size()):
			var fraction: float = radial_fractions[i]
			var chord: float = radius * chord_scales[i]
			var theta: float = deg_to_rad(pitch_degrees[i])
			var chord_axis: Vector3 = Vector3(cos(theta), 0, -sign * sin(theta))
			var normal_axis: Vector3 = Vector3(sin(theta), 0, sign * cos(theta))
			var sweep: float = radius * (0.018 * fraction * fraction - 0.004)
			var center: Vector3 = Vector3(sweep, sign * radius * fraction, 0)
			var upper_station: Array[Vector3] = []
			var lower_station: Array[Vector3] = []
			for j in range(chord_samples.size()):
				var u: float = chord_samples[j]
				var chord_offset: float = (u - 0.5) * chord
				var camber: float = chord * 0.018 * sin(PI * u)
				var half_thickness: float = chord * thickness[j] * 0.5
				upper_station.append(center + chord_axis * chord_offset + normal_axis * (camber + half_thickness))
				lower_station.append(center + chord_axis * chord_offset + normal_axis * (camber - half_thickness))
			upper.append(upper_station)
			lower.append(lower_station)
		# US-V09d grain UV: U runs tip to tip through the hub (one blank), V across the chord on both faces.
		# V is the absolute chord offset (widest chord = 0..1), so straight grain runs out at the edges toward the tip.
		var widest: float = chord_scales.max()
		var uv := func(i: int, j: int) -> Vector2: return Vector2(0.5 + sign * 0.5 * radial_fractions[i], 0.5 + (chord_samples[j] - 0.5) * chord_scales[i] / widest)
		for i in range(radial_fractions.size() - 1):
			var upper_a: Array = upper[i]
			var upper_b: Array = upper[i + 1]
			var lower_a: Array = lower[i]
			var lower_b: Array = lower[i + 1]
			for j in range(chord_samples.size() - 1):
				var leading_to_trailing: Vector3 = (upper_a[j + 1] - upper_a[j]).normalized()
				var outward_span: Vector3 = Vector3(0, sign, 0)
				var surface_normal: Vector3 = leading_to_trailing.cross(outward_span).normalized()
				_uv_quad(st, [upper_a[j], upper_b[j], upper_b[j + 1], upper_a[j + 1]], [uv.call(i, j), uv.call(i + 1, j), uv.call(i + 1, j + 1), uv.call(i, j + 1)], surface_normal)
				_uv_quad(st, [lower_a[j + 1], lower_b[j + 1], lower_b[j], lower_a[j]], [uv.call(i, j + 1), uv.call(i + 1, j + 1), uv.call(i + 1, j), uv.call(i, j)], -surface_normal)
			# Close the leading edge, trailing edge and blade tip for a readable section silhouette.
			var outer_sign: float = 1.0 if i == radial_fractions.size() - 2 else 0.0
			for j in [0, chord_samples.size() - 1]:
				var desired: Vector3 = Vector3(-1 if j == 0 else 1, 0, 0)
				_uv_quad(st, [upper_a[j], upper_b[j], lower_b[j], lower_a[j]], [uv.call(i, j), uv.call(i + 1, j), uv.call(i + 1, j), uv.call(i, j)], desired)
			if outer_sign > 0.0:
				for j in range(chord_samples.size() - 1):
					_uv_quad(st, [upper_b[j], upper_b[j + 1], lower_b[j + 1], lower_b[j]], [uv.call(i + 1, j), uv.call(i + 1, j + 1), uv.call(i + 1, j + 1), uv.call(i + 1, j)], Vector3(0, sign, 0))
		# The hidden root closure sits within the metal hub envelope.
		for j in range(chord_samples.size() - 1):
			_uv_quad(st, [upper[0][j + 1], upper[0][j], lower[0][j], lower[0][j + 1]], [uv.call(0, j + 1), uv.call(0, j), uv.call(0, j), uv.call(0, j + 1)], Vector3(0, -sign, 0))


## US-V11: a wooden propeller that strikes the ground snaps near the hub. Each blade keeps a stub to its own break
## station (share of the tip radius); the break runs obliquely across the chord (the grain tears at a slant) with a
## little roughness, and short slivers stand out along the grain; the fresh fracture shows pale, unvarnished wood.
## Seeded presentation estimates, not a fracture model.
const PROP_BREAK_FRACTIONS := {-1.0: 0.27, 1.0: 0.21}
const PROP_BREAK_SLANT := 0.09
const PROP_BREAK_ROUGH := 0.008
const PROP_BREAK_RAGGED := PROP_BREAK_SLANT * 0.5 + PROP_BREAK_ROUGH
const PROP_SLIVERS := 5
const PROP_BREAK_SEED := 61
const FRESH_WOOD_COLOR := Color("d8bd8f")


## One section point pair [upper, lower] of blade `sign` at a radius share and chord sample j (the blades' own law).
static func _blade_section(radius: float, sign: float, fraction: float, j: int) -> Array:
	var k := 0
	while k < BLADE_FRACTIONS.size() - 2 and fraction >= BLADE_FRACTIONS[k + 1]:
		k += 1
	var t := clampf((fraction - BLADE_FRACTIONS[k]) / (BLADE_FRACTIONS[k + 1] - BLADE_FRACTIONS[k]), 0.0, 1.0)
	var chord: float = radius * lerpf(BLADE_CHORDS[k], BLADE_CHORDS[k + 1], t)
	var theta: float = deg_to_rad(lerpf(BLADE_PITCH_DEG[k], BLADE_PITCH_DEG[k + 1], t))
	var chord_axis := Vector3(cos(theta), 0, -sign * sin(theta))
	var normal_axis := Vector3(sin(theta), 0, sign * cos(theta))
	var center := Vector3(radius * (0.018 * fraction * fraction - 0.004), sign * radius * fraction, 0)
	var u: float = BLADE_CHORD_SAMPLES[j]
	var offset: float = (u - 0.5) * chord
	var camber: float = chord * 0.018 * sin(PI * u)
	var half: float = chord * BLADE_THICKNESS[j] * 0.5
	return [center + chord_axis * offset + normal_axis * (camber + half), center + chord_axis * offset + normal_axis * (camber - half)]


## The broken blades: varnished stubs on `wood` (blade UVs), the fracture and slivers on `fresh` (flat normals).
static func _prop_stubs(wood: SurfaceTool, fresh: SurfaceTool, radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PROP_BREAK_SEED
	var widest: float = BLADE_CHORDS.max()
	var samples := BLADE_CHORD_SAMPLES.size()
	for sign: float in [-1.0, 1.0]:
		var cut: float = PROP_BREAK_FRACTIONS[sign]
		var slant := rng.randf_range(-PROP_BREAK_SLANT, PROP_BREAK_SLANT)
		var ends: Array[float] = []
		for j in samples:
			ends.append(cut + slant * (BLADE_CHORD_SAMPLES[j] - 0.5) + rng.randf_range(-PROP_BREAK_ROUGH, PROP_BREAK_ROUGH))
		var stations: Array[float] = []
		for f in BLADE_FRACTIONS:
			if f < cut - PROP_BREAK_RAGGED - 0.01:
				stations.append(f)
		stations.append(-1.0) # the ragged end
		var upper: Array = []
		var lower: Array = []
		for f in stations:
			var u_row: Array = []
			var l_row: Array = []
			for j in samples:
				var pair := _blade_section(radius, sign, ends[j] if f < 0.0 else f, j)
				u_row.append(pair[0])
				l_row.append(pair[1])
			upper.append(u_row)
			lower.append(l_row)
		var uv := func(i: int, j: int) -> Vector2:
			var f: float = ends[j] if stations[i] < 0.0 else stations[i]
			var chord := lerpf(BLADE_CHORDS[0], BLADE_CHORDS[1], clampf((f - BLADE_FRACTIONS[0]) / (BLADE_FRACTIONS[1] - BLADE_FRACTIONS[0]), 0.0, 1.0))
			return Vector2(0.5 + sign * 0.5 * f, 0.5 + (BLADE_CHORD_SAMPLES[j] - 0.5) * chord / widest)
		for i in range(stations.size() - 1):
			for j in range(samples - 1):
				var n: Vector3 = (upper[i][j + 1] - upper[i][j]).normalized().cross(Vector3(0, sign, 0)).normalized()
				_uv_quad(wood, [upper[i][j], upper[i + 1][j], upper[i + 1][j + 1], upper[i][j + 1]], [uv.call(i, j), uv.call(i + 1, j), uv.call(i + 1, j + 1), uv.call(i, j + 1)], n)
				_uv_quad(wood, [lower[i][j + 1], lower[i + 1][j + 1], lower[i + 1][j], lower[i][j]], [uv.call(i, j + 1), uv.call(i + 1, j + 1), uv.call(i + 1, j), uv.call(i, j)], -n)
		# Fracture face across the ragged end.
		var last := stations.size() - 1
		for j in range(samples - 1):
			_triangle(fresh, upper[last][j], upper[last][j + 1], lower[last][j + 1], Vector3(0, sign, 0))
			_triangle(fresh, upper[last][j], lower[last][j + 1], lower[last][j], Vector3(0, sign, 0))
		# Slivers: thin wedges peeling off the faces along the grain (spanwise), each from a point of the break.
		for k in PROP_SLIVERS:
			var j := rng.randi_range(1, samples - 3)
			var top := rng.randf() < 0.5
			var row: Array = upper[last] if top else lower[last]
			var root_a: Vector3 = row[j]
			var root_b: Vector3 = row[j].lerp(row[j + 1], rng.randf_range(0.2, 0.45))
			var out := Vector3(0, sign, 0)
			var lift: Vector3 = (upper[last][j] - lower[last][j]).normalized() * (1.0 if top else -1.0)
			var tip: Vector3 = root_a.lerp(root_b, rng.randf_range(0.3, 0.7)) + out * rng.randf_range(0.004, 0.014) + lift * rng.randf_range(0.0003, 0.0015)
			var under: Vector3 = root_a.lerp(root_b, 0.5) - lift * 0.0008
			_triangle(fresh, root_a, root_b, tip, lift)
			_triangle(fresh, root_a, tip, under, (root_a - root_b).normalized())
			_triangle(fresh, root_b, under, tip, (root_b - root_a).normalized())


# Quad with per-vertex UVs; winding follows `outward` like _triangle (normals are regenerated afterwards).
static func _uv_quad(st: SurfaceTool, points: Array, uvs: Array, outward: Vector3) -> void:
	for tri in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = points[tri[0]]
		var b: Vector3 = points[tri[1]]
		var c: Vector3 = points[tri[2]]
		var order := [tri[0], tri[1], tri[2]]
		if (b - a).cross(c - a).dot(outward) > 0.0: order = [tri[0], tri[2], tri[1]]
		for k in order:
			st.set_normal(outward.normalized())
			st.set_uv(uvs[k])
			st.add_vertex(points[k])


static func _wheel_lathe(st: SurfaceTool, radius: float, width: float) -> void:
	var half_width: float = width * 0.5
	var profile: Array[Vector2] = [
		Vector2(-half_width, 0.010), Vector2(-half_width, radius * 0.77),
		Vector2(-half_width * 0.83, radius * 0.90), Vector2(-half_width * 0.56, radius * 0.98),
		Vector2(-half_width * 0.25, radius), Vector2(half_width * 0.25, radius),
		Vector2(half_width * 0.56, radius * 0.98), Vector2(half_width * 0.83, radius * 0.90),
		Vector2(half_width, radius * 0.77), Vector2(half_width, 0.010),
		Vector2(-half_width, 0.010)
	]
	# US-V09a: smooth lathe normals (a moulded tyre has no facets); the hidden bore keeps its inward normal.
	_turned(st, Vector3.ZERO, Vector3.RIGHT, profile, 40, true)


static func _add_wheel(parent: Node3D, label: String, radius: float, width: float, outer_sign: float) -> MeshInstance3D:
	var buckets: Dictionary = _buckets([
		["rubber", RUBBER_COLOR, "rubber"],
		["sidewall", TIRE_LINE_COLOR, "rubber"],
		["aluminum", CASE_COLOR, "aluminum"],
		["steel", STEEL_COLOR, "steel"]
	])
	var tire: SurfaceTool = buckets.rubber
	var sidewall: SurfaceTool = buckets.sidewall
	var aluminum: SurfaceTool = buckets.aluminum
	var steel: SurfaceTool = buckets.steel
	_wheel_lathe(tire, radius, width)
	var hub_width: float = width + 0.002
	_cylinder(aluminum, Vector3(-hub_width * 0.5, 0, 0), Vector3(hub_width * 0.5, 0, 0), radius * 0.29, radius * 0.29, 20)
	_cylinder(aluminum, Vector3(outer_sign * width * 0.47, 0, 0), Vector3(outer_sign * (width * 0.55), 0, 0), radius * 0.43, radius * 0.37, 20)
	_washer(aluminum, Vector3(outer_sign * (width * 0.55), 0, 0), Vector3.RIGHT, radius * 0.35, radius * 0.17, 0.0012, 20)
	_torus(sidewall, Vector3(outer_sign * width * 0.40, 0, 0), Vector3.RIGHT, radius * 0.72, maxf(radius * 0.014, 0.00045), 24, 6)
	var bolt_radius: float = radius * 0.25
	for i in range(6):
		var angle: float = TAU * float(i) / 6.0
		var pos: Vector3 = Vector3(outer_sign * (width * 0.55), bolt_radius * cos(angle), bolt_radius * sin(angle))
		_cylinder(steel, pos, pos + Vector3(outer_sign * 0.0016, 0, 0), maxf(radius * 0.052, 0.0014), maxf(radius * 0.052, 0.0014), 6)
	_cylinder(steel, Vector3(outer_sign * (width * 0.55), 0, 0), Vector3(outer_sign * (width * 0.55 + 0.0018), 0, 0), radius * 0.12, radius * 0.12, 6)
	return _flush(parent, label, buckets)


# US-V14: Jensen sheet 1 draws the main gear as a 0.090 in 2024-T3 aluminium plate (equipment.main_strap): a flat centre
# bolted under the fuselage, then a leg each side tapering from the full root width to the axle. The plate's plane holds
# the fore-aft axis, so it reads wide from the side and thin from the front. The axles stay the physics contacts, so the
# legs rake aft from the drawn root to them.
static func _strap_leg(st: SurfaceTool, root: Vector3, tip: Vector3, front: Vector2, rear: Vector2, thickness: float) -> void:
	# front / rear: z of the plate's leading and trailing edges at the root (x) and at the tip (y).
	var along := Vector3(tip.x - root.x, tip.y - root.y, 0.0).normalized()
	var offset := along.cross(Vector3.BACK).normalized() * (thickness * 0.5)
	var rings: Array = []
	for k in GearFlex.LEG_SEGMENTS + 1: # US-V10: interior rings let the leg take the bending shape (GearFlex)
		var s := float(k) / GearFlex.LEG_SEGMENTS
		var p := root.lerp(tip, s)
		var leading := Vector3(p.x, p.y, lerpf(front.x, front.y, s))
		var trailing := Vector3(p.x, p.y, lerpf(rear.x, rear.y, s))
		rings.append([leading + offset, trailing + offset, trailing - offset, leading - offset])
	for k in GearFlex.LEG_SEGMENTS:
		var a: Array = rings[k]
		var b: Array = rings[k + 1]
		var centre: Vector3 = (a[0] + a[2] + b[0] + b[2]) * 0.25
		for i in 4:
			var j := (i + 1) % 4
			_quad(st, a[i], a[j], b[j], b[i], (a[i] + a[j] + b[i] + b[j]) * 0.25 - centre)
	for cap in [[rings[0], -along], [rings[GearFlex.LEG_SEGMENTS], along]]:
		var ring: Array = cap[0]
		_quad(st, ring[0], ring[1], ring[2], ring[3], cap[1])


static func _add_main_gear(root: Node3D, gear: Dictionary) -> void:
	var e: Dictionary = D.equipment
	var strap: Dictionary = e.main_strap
	var structure: Dictionary = _buckets([
		["steel", STEEL_COLOR, "steel"],
		["bright", FIN_COLOR, "aluminum"]
	])
	var steel: SurfaceTool = structure.steel
	var bright: SurfaceTool = structure.bright
	var thickness := float(strap.thickness)
	var root_front := float(strap.root_front_z)
	var root_rear := float(strap.root_rear_z)
	var root_z := (root_front + root_rear) * 0.5
	var root_y := _fuselage_height(root_z, false) - thickness * 0.5
	var half_span := float(strap.root_half_span)
	var axle_z := float(e.main_axle_z)
	var axle_half := float(strap.axle_width) * 0.5
	# Flat centre under the fuselage bottom, held by four bolts with washers.
	_box(bright, Vector3(0, root_y, root_z), Vector3(half_span * 2.0, thickness, root_rear - root_front))
	for x in [-0.012, 0.012]:
		for z in [root_front + 0.015, root_rear - 0.015]:
			var bolt := Vector3(x, root_y - thickness * 0.5, z)
			_washer(bright, bolt - Vector3(0, 0.0004, 0), Vector3.UP, 0.0042, 0.0018, 0.0008, 10)
			_cylinder(steel, bolt - Vector3(0, 0.0008, 0), bolt - Vector3(0, 0.0034, 0), 0.0032, 0.0032, 6)
	for side in [-1.0, 1.0]:
		var center: Vector3 = Vector3(side * float(e.main_track) * 0.5, float(e.wheel_y), axle_z)
		var sleeve_x: float = side * (float(e.main_track) * 0.5 - 0.014)
		# The axle passes through the plate just inboard of its sleeve; the plate ends 4 mm past it along the leg.
		var leg_root := Vector3(side * half_span, root_y, root_z)
		var leg_tip := Vector3(sleeve_x - side * (0.003 + thickness * 0.5), center.y, axle_z)
		leg_tip += Vector3(leg_tip.x - leg_root.x, leg_tip.y - leg_root.y, 0.0).normalized() * 0.004
		_strap_leg(bright, leg_root, leg_tip, Vector2(root_front, axle_z - axle_half), Vector2(root_rear, axle_z + axle_half), thickness)
		# Axle sleeve and castellated locknut remain on the fixed gear leg, just inside the rotating wheel.
		_cylinder(bright, Vector3(sleeve_x - side * 0.004, center.y, center.z), Vector3(sleeve_x + side * 0.006, center.y, center.z), 0.006, 0.006, 12)
		_washer(steel, Vector3(sleeve_x + side * 0.006, center.y, center.z), Vector3.RIGHT, 0.007, 0.0035, 0.0014, 10)
		var label: String = "right" if side > 0.0 else "left"
		var pivot := Node3D.new()
		pivot.name = "wheel_" + label + "_pivot"
		pivot.position = center
		pivot.set_meta("crash_section", "wheel") # CR-09f: a wheel can pop off its axle in a destroying crash
		root.add_child(pivot)
		gear[label] = pivot
		_add_wheel(pivot, "gear_" + label, float(e.main_wheel_diameter) * 0.5, 0.024, side)
	var main := _flush(root, "main_gear_structure", structure)
	var legs: Array = []
	for side in [-1.0, 1.0]:
		legs.append({root = Vector3(side * half_span, root_y, root_z),
			tip = Vector3(side * float(e.main_track) * 0.5, float(e.wheel_y), axle_z), side = side, rigid_radius = 0.02})
	main.set_meta("flex_legs", legs)


# US-V10b: sprung, steerable wire nose gear (Jensen sheet 1: 5/32 in wire through nylon bearings just aft of F1, torsion
# coil below the fuselage, single-sided wheel; the owner's reference photo 2026-10-13 adds the compression spring and
# collar between the bearing and the coil). The whole wire turns about its own axis, so the steering pivot sits on the
# wire and the wheel hangs 17 mm to its side, centred on the physics contact. Proportions are estimates.
const NOSE_WIRE_RADIUS := 0.002
const NOSE_WHEEL_OFFSET := 0.017
const NOSE_SPRING_LENGTH := 0.055
const NOSE_SPRING_TURNS := 9
const NOSE_SPRING_WIRE := 0.0006
const NOSE_SPRING_RADIUS := 0.0045
const NOSE_COIL_RADIUS := 0.007
const NOSE_COIL_SHIFT := -0.0045 # the coil steps away from the wheel

static func _add_nose_gear(root: Node3D, gear: Dictionary) -> void:
	var e: Dictionary = D.equipment
	var y: float = float(e.wheel_y)
	var z: float = float(e.nose_axle_z)
	var steering := Node3D.new()
	steering.name = "nose_steering_pivot"
	steering.position = Vector3(-NOSE_WHEEL_OFFSET, y, z)
	# CR-09e: in a crash the whole nose leg (bearing, spring, wire, wheel) tears out as one part.
	steering.set_meta("crash_section", "gear")
	root.add_child(steering)
	gear["steering"] = steering
	var nose_axle := Node3D.new()
	nose_axle.name = "wheel_nose_pivot"
	nose_axle.position = Vector3(NOSE_WHEEL_OFFSET, 0, 0)
	nose_axle.set_meta("crash_section", "wheel")
	steering.add_child(nose_axle)
	gear["nose"] = nose_axle
	_add_wheel(nose_axle, "nosewheel", float(e.nose_wheel_diameter) * 0.5, 0.022, 1.0)

	# Heights in the steering frame (origin on the wire axis at axle height).
	var exit_y: float = _fuselage_height(z, false) - y
	var bearing_bottom := exit_y - 0.006
	var collar_top := bearing_bottom - NOSE_SPRING_LENGTH
	var coil_y := collar_top - 0.006 - NOSE_COIL_RADIUS - 0.004

	# Fixed: the nylon bearing where the wire leaves the fuselage (coaxial, so steering does not show).
	var bearing: Dictionary = _buckets([["nylon", Color("e9e4d8"), "plastic"]])
	_cylinder(bearing.nylon, Vector3(0, exit_y + 0.001, 0), Vector3(0, bearing_bottom, 0), 0.0055, 0.0055, 20)
	_flush(steering, "nose_bearing", bearing)

	# Compression spring between bearing and collar: built at free length downward from its top, scaled by GearFlex.
	var spring_node := Node3D.new()
	spring_node.name = "nose_spring_mount"
	spring_node.position = Vector3(0, bearing_bottom, 0)
	spring_node.set_meta("free_length_m", NOSE_SPRING_LENGTH)
	steering.add_child(spring_node)
	var spring: Dictionary = _buckets([["steel", STEEL_COLOR, "steel"]])
	var helix: Array[Vector3] = []
	var steps := NOSE_SPRING_TURNS * 16
	for k in steps + 1:
		var a := TAU * NOSE_SPRING_TURNS * float(k) / steps
		helix.append(Vector3(NOSE_SPRING_RADIUS * cos(a), -NOSE_SPRING_LENGTH * float(k) / steps, NOSE_SPRING_RADIUS * sin(a)))
	_sweep_tube(spring.steel, helix, NOSE_SPRING_WIRE, 6)
	_flush(spring_node, "nose_spring", spring)

	# Sliding wire: top inside the fuselage, collar, torsion coil, leg and axle stub; GearFlex lifts and bends it.
	var slider := Node3D.new()
	slider.name = "nose_strut_slider"
	steering.add_child(slider)
	var strut: Dictionary = _buckets([["steel", STEEL_COLOR, "steel"], ["dark", DARK_METAL_COLOR, "aluminum"]])
	var wire: Array[Vector3] = [Vector3(0, exit_y + 0.030, 0), Vector3(0, coil_y, 0)]
	_sweep_tube(strut.steel, wire, NOSE_WIRE_RADIUS, 10)
	# Torsion coil: one turn, tangent to the vertical wire at its front point (the wire runs down into it and leaves
	# downward again), centred aft of the wire, stepping NOSE_COIL_SHIFT sideways per turn.
	var coil: Array[Vector3] = []
	var coil_steps := 40
	for k in coil_steps + 1:
		var a := TAU * float(k) / coil_steps
		coil.append(Vector3(NOSE_COIL_SHIFT * a / TAU, coil_y - NOSE_COIL_RADIUS * sin(a), NOSE_COIL_RADIUS * (1.0 - cos(a))))
	_sweep_tube(strut.steel, coil, NOSE_WIRE_RADIUS, 10)
	var leg_x := NOSE_COIL_SHIFT
	# Leg down to the axle bend, then the stub through the hub and an outboard wheel collar.
	var leg: Array[Vector3] = []
	for k in GearFlex.LEG_SEGMENTS + 1:
		leg.append(Vector3(leg_x, lerpf(coil_y, 0.006, float(k) / GearFlex.LEG_SEGMENTS), 0))
	leg.append_array([Vector3(leg_x + 0.003, 0, 0), Vector3(NOSE_WHEEL_OFFSET + 0.014, 0, 0)])
	_sweep_tube(strut.steel, leg, NOSE_WIRE_RADIUS, 10)
	_cylinder(strut.dark, Vector3(0, collar_top, 0), Vector3(0, collar_top - 0.006, 0), 0.0042, 0.0042, 16)
	_cylinder(strut.steel, Vector3(0.004, collar_top - 0.003, 0), Vector3(0.0055, collar_top - 0.003, 0), 0.0011, 0.0011, 6)
	_cylinder(strut.dark, Vector3(NOSE_WHEEL_OFFSET + 0.0125, 0, 0), Vector3(NOSE_WHEEL_OFFSET + 0.0165, 0, 0), 0.0045, 0.0045, 14)
	var strut_mesh := _flush(slider, "nose_gear_strut", strut)
	# Below the coil (measured from the coil's lowest point, so the loop itself never deforms) the leg bows aft once
	# the spring is solid (GearFlex column mode).
	strut_mesh.set_meta("flex_leg", {root = Vector3(leg_x, coil_y - NOSE_COIL_RADIUS - NOSE_WIRE_RADIUS, 0), tip = Vector3(leg_x, 0, 0), side = 0.0, rigid_radius = 0.008, column = true, bow_axis = Vector3.BACK})
	slider.set_meta("spring_travel_m", NOSE_SPRING_LENGTH - (NOSE_SPRING_TURNS + 1) * 2.0 * NOSE_SPRING_WIRE)
	# US-V10: legs bend (main) and the nose wire telescopes into its spring (GearFlex).
	var main := root.find_child("main_gear_structure", false, false) as MeshInstance3D
	GearFlex.attach(root, gear, main, main.get_meta("flex_legs"), strut_mesh, strut_mesh.get_meta("flex_leg"), slider, spring_node)


static func _fuselage_height(z: float, top: bool) -> float:
	var stations: Array = D.fuselage_stations
	var column: int = 2 if top else 3
	for i in range(stations.size() - 1):
		var first: Array = stations[i]
		var second: Array = stations[i + 1]
		if z <= float(second[0]):
			var fraction: float = clampf((z - float(first[0])) / (float(second[0]) - float(first[0])), 0.0, 1.0)
			return lerpf(float(first[column]), float(second[column]), fraction)
	return float(stations.back()[column])


static func build(root: Node3D, gear: Dictionary) -> Node3D:
	var e: Dictionary = D.equipment
	var propeller := Node3D.new()
	propeller.name = "propeller"
	propeller.position = Vector3(0, float(e.shaft_y), float(e.prop_z))
	root.add_child(propeller)

	var blades := SurfaceTool.new()
	blades.begin(Mesh.PRIMITIVE_TRIANGLES)
	blades.set_material(Finish.propeller_wood(WOOD_COLOR))
	_prop_blades(blades, float(e.prop_diameter) * 0.5)
	# US-V09a: one smooth group per blade surface; the zero-thickness leading and trailing edges round off.
	blades.generate_normals()
	var blade_node := _flush(propeller, "propeller_blades", {"wood": blades})
	# US-V11: a prop strike hides the blades and shows the broken stubs (render/crash/director.gd).
	blade_node.set_meta("prop_strike_breaks", true)
	var stub_wood := SurfaceTool.new()
	stub_wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	stub_wood.set_material(Finish.propeller_wood(WOOD_COLOR))
	var stub_fresh := _surface(FRESH_WOOD_COLOR, "wood")
	_prop_stubs(stub_wood, stub_fresh, float(e.prop_diameter) * 0.5)
	stub_wood.generate_normals()
	var stubs := _flush(propeller, "propeller_stubs", {"wood": stub_wood, "fresh": stub_fresh})
	stubs.visible = false
	stubs.set_meta("prop_strike_reveal", true)
	# US-V13: the wooden hub between the engine's drive hub and washer; it also hides the blade root closures.
	var hub := _surface(WOOD_COLOR, "varnished_wood")
	_cylinder(hub, Vector3(0, 0, -PROP_HUB_HALF_THICKNESS), Vector3(0, 0, PROP_HUB_HALF_THICKNESS), PROP_HUB_RADIUS, PROP_HUB_RADIUS, 24)
	_flush(propeller, "propeller_hub", {"wood": hub})
	_add_engine(root, propeller)
	_add_main_gear(root, gear)
	_add_nose_gear(root, gear)
	return propeller


static func _retainer_surface_path(st: SurfaceTool, path: Array[Vector3], width: float, thickness: float) -> void:
	if path.size() < 3:
		return
	var points: Array[Vector3] = path.duplicate()
	if points[0].distance_to(points.back()) > 0.000001:
		points.append(points[0])
	var sides: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in range(points.size()):
		var previous: Vector3 = points[(i - 1 + points.size()) % points.size()]
		var next: Vector3 = points[(i + 1) % points.size()]
		var tangent: Vector3 = (next - previous).normalized()
		var side: Vector3 = Vector3.RIGHT - tangent * tangent.dot(Vector3.RIGHT)
		if side.length_squared() < 0.08:
			side = Vector3.UP.cross(tangent)
		side = side.normalized()
		sides.append(side)
		normals.append(tangent.cross(side).normalized())
	var half_width: float = width * 0.5
	var half_thickness: float = thickness * 0.5
	for i in range(points.size() - 1):
		var j: int = i + 1
		var a_left: Vector3 = points[i] + sides[i] * half_width + normals[i] * half_thickness
		var a_right: Vector3 = points[i] - sides[i] * half_width + normals[i] * half_thickness
		var b_right: Vector3 = points[j] - sides[j] * half_width + normals[j] * half_thickness
		var b_left: Vector3 = points[j] + sides[j] * half_width + normals[j] * half_thickness
		var face_normal: Vector3 = (normals[i] + normals[j]).normalized()
		_quad(st, a_left, a_right, b_right, b_left, face_normal)
		var a_under_left: Vector3 = points[i] + sides[i] * half_width - normals[i] * half_thickness
		var a_under_right: Vector3 = points[i] - sides[i] * half_width - normals[i] * half_thickness
		var b_under_right: Vector3 = points[j] - sides[j] * half_width - normals[j] * half_thickness
		var b_under_left: Vector3 = points[j] + sides[j] * half_width - normals[j] * half_thickness
		_quad(st, a_under_right, a_under_left, b_under_left, b_under_right, -face_normal)
		_quad(st, a_left, b_left, b_under_left, a_under_left, sides[i])
		_quad(st, a_right, a_under_right, b_under_right, b_right, -sides[i])


static func _wing_retainer_loop(front_x: float, rear_x: float, front_z: float, front_y: float, rear_z: float, rear_y: float, upper: Array, wing: Dictionary, return_offset: float, outbound_layer: float, return_layer: float) -> Array[Vector3]:
	var path: Array[Vector3] = []
	var front_radius: float = 0.0034
	var rear_radius: float = 0.0034
	var chord: float = float(wing.chord)
	var leading_z: float = float(wing.leading_z)
	var root_y: float = float(wing.root_y)
	var dihedral: float = tan(deg_to_rad(float(wing.dihedral_deg)))
	var wrap_radius: float = front_radius + 0.00025
	path.append(Vector3(front_x, front_y + wrap_radius + outbound_layer, front_z))
	for sample in upper:
		var u: float = float(sample[0])
		var x: float = lerpf(front_x, rear_x, u)
		var crossing_layer: float = outbound_layer * pow(sin(PI * u), 4.0)
		var y: float = root_y + float(sample[1]) * chord + absf(x) * dihedral + 0.001 + crossing_layer
		path.append(Vector3(x, y, leading_z + u * chord))
	path.append(Vector3(rear_x, rear_y + wrap_radius + outbound_layer, rear_z))
	# Turn fully around the aft dowel; shift across its axis to form the return strand.
	for step in range(1, 13):
		var t: float = float(step) / 12.0
		var angle: float = TAU * t
		var x: float = rear_x + return_offset * t
		var layer: float = lerpf(outbound_layer, return_layer, t)
		var radius: float = rear_radius + 0.00025 + layer
		path.append(Vector3(x, rear_y + radius * cos(angle), rear_z + radius * sin(angle)))
	# The return stays on the upper airfoil surface, offset sideways and slightly above the outgoing run.
	for i in range(upper.size() - 1, -1, -1):
		var sample: Array = upper[i]
		var u: float = float(sample[0])
		var side_offset: float = return_offset * (1.0 - 2.0 * u)
		var x: float = lerpf(front_x, rear_x, u) + side_offset
		var crossing_layer: float = return_layer * pow(sin(PI * u), 4.0)
		var y: float = root_y + float(sample[1]) * chord + absf(x) * dihedral + 0.001 + crossing_layer
		path.append(Vector3(x, y, leading_z + u * chord))
	path.append(Vector3(front_x + return_offset, front_y + wrap_radius + return_layer, front_z))
	# Close around the forward dowel, with the outside of both turns kept beyond the fuselage sides.
	for step in range(1, 13):
		var t: float = float(step) / 12.0
		var angle: float = TAU * t
		var x: float = front_x + return_offset * (1.0 - t)
		var layer: float = lerpf(return_layer, outbound_layer, t)
		var radius: float = front_radius + 0.00025 + layer
		path.append(Vector3(x, front_y + radius * cos(angle), front_z - radius * sin(angle)))
	return path


static func retainers(root: Node3D) -> void:
	var wing: Dictionary = D.wing
	var front_z: float = float(wing.leading_z) - 0.018
	var rear_z: float = float(wing.leading_z) + float(wing.chord) + 0.015
	var front_y: float = _fuselage_height(front_z, true) - 0.008
	var rear_y: float = _fuselage_height(rear_z, true) - 0.008
	var dowel_buckets: Dictionary = _buckets([
		["wood", WOOD_COLOR, "wood"],
		["steel", STEEL_COLOR, "steel"]
	])
	var dowel_wood: SurfaceTool = dowel_buckets.wood
	var dowel_steel: SurfaceTool = dowel_buckets.steel
	for datum in [[front_z, front_y], [rear_z, rear_y]]:
		var z: float = float(datum[0])
		var y: float = float(datum[1])
		_cylinder(dowel_wood, Vector3(-0.066, y, z), Vector3(0.066, y, z), 0.0027, 0.0027, 14)
		for side in [-1.0, 1.0]:
			var collar: Vector3 = Vector3(side * 0.060, y, z)
			_washer(dowel_steel, collar, Vector3.RIGHT, 0.0039, 0.0025, 0.0010, 10)
			_cylinder(dowel_steel, collar + Vector3(side * 0.0008, 0, 0), collar + Vector3(side * 0.0018, 0, 0), 0.0024, 0.0024, 6)
	_flush(root, "wing_mount_dowels_and_end_caps", dowel_buckets)

	var band_material: StandardMaterial3D = _material(BAND_COLOR, "rubber", true)
	var band_surface := SurfaceTool.new()
	band_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	band_surface.set_material(band_material)
	var upper: Array = []
	var section: Array = wing.section
	var trailing_index: int = -1
	for i in range(section.size()):
		var point: Array = section[i]
		if is_equal_approx(float(point[0]), 1.0):
			trailing_index = i
			break
	if trailing_index < 1:
		push_error("Wing section has no trailing-edge station for the #64 retainers")
		return
	for i in range(trailing_index + 1):
		upper.append(section[i])
	# Fourteen closed, flat-profile loops: seven on each crossing diagonal.
	for direction in [-1.0, 1.0]:
		for i in range(7):
			var fraction: float = float(i) / 6.0
			var front_x: float = direction * lerpf(0.052, 0.063, fraction)
			var rear_x: float = -front_x
			var lane_layer: float = float(i) * 0.00035
			var family_layer: float = 0.000175 if direction < 0.0 else 0.0
			var outbound_layer: float = lane_layer + family_layer
			var return_layer: float = outbound_layer + 0.00035
			var return_offset: float = direction * 0.0018
			var loop_path: Array[Vector3] = _wing_retainer_loop(front_x, rear_x, front_z, front_y, rear_z, rear_y, upper, wing, return_offset, outbound_layer, return_layer)
			_retainer_surface_path(band_surface, loop_path, 0.0019, 0.00034)
	var band_mesh := ArrayMesh.new()
	band_surface.commit(band_mesh)
	var band_instance := MeshInstance3D.new()
	band_instance.name = "wing_retainers"
	band_instance.mesh = band_mesh
	root.add_child(band_instance)
