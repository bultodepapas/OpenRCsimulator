# V03/V06/V07: generic glow .61 installation, detailed propeller and visible hardware.
# All visual choices are kept separate from shared flight/model geometry.
extends RefCounted

const Geometry := preload("res://aircraft/ugly_stik_geometry.gd")
const Finish := preload("res://aircraft/ugly_stik_finish.gd")
const D: Dictionary = Geometry.DATA

const CASE_COLOR := Color("858d91")
const FIN_COLOR := Color("a3aaad")
const STEEL_COLOR := Color("c0c3c3")
const DARK_METAL_COLOR := Color("51585b")
const BLACK_COLOR := Color("202528")
const MOUNT_COLOR := Color("594632")
const WOOD_COLOR := Color("a98250")
const BAND_COLOR := Color("302d2a")
const FUEL_COLOR := Color("b98245")
const PRESSURE_COLOR := Color("363c3f")
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


static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, width: float, depth: float, plane_normal: Vector3 = Vector3.FORWARD) -> void:
	var axis: Vector3 = (b - a).normalized()
	if axis.length_squared() < 0.5:
		return
	var depth_axis: Vector3 = (plane_normal - axis * plane_normal.dot(axis)).normalized()
	if depth_axis.length_squared() < 0.5:
		depth_axis = _frame(axis)[0]
	var width_axis: Vector3 = depth_axis.cross(axis).normalized()
	var aw: Vector3 = width_axis * width * 0.5
	var ad: Vector3 = depth_axis * depth * 0.5
	var p0: Vector3 = a - aw - ad
	var p1: Vector3 = a + aw - ad
	var p2: Vector3 = a + aw + ad
	var p3: Vector3 = a - aw + ad
	var q0: Vector3 = b - aw - ad
	var q1: Vector3 = b + aw - ad
	var q2: Vector3 = b + aw + ad
	var q3: Vector3 = b - aw + ad
	_quad(st, p0, p1, p2, p3, -axis)
	_quad(st, q1, q0, q3, q2, axis)
	_quad(st, p0, q0, q1, p1, -depth_axis)
	_quad(st, p1, q1, q2, p2, width_axis)
	_quad(st, p2, q2, q3, p3, depth_axis)
	_quad(st, p3, q3, q0, p0, -width_axis)


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


static func _cubic(a: Vector3, b: Vector3, c: Vector3, d: Vector3, steps: int = 10) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var inverse: float = 1.0 - t
		result.append(a * inverse * inverse * inverse + b * 3.0 * inverse * inverse * t + c * 3.0 * inverse * t * t + d * t * t * t)
	return result


static func _add_engine(root: Node3D) -> void:
	var e: Dictionary = D.equipment
	var engine_z: float = (float(e.firewall_z) + float(e.prop_z)) * 0.5
	var shaft_y: float = float(e.shaft_y)
	var blocks: Dictionary = _buckets([
		["cast", CASE_COLOR, "aluminum"],
		["bright", FIN_COLOR, "aluminum"],
		["gold", Color("b88742"), "aluminum"],
		["steel", STEEL_COLOR, "steel"],
		["dark", DARK_METAL_COLOR, "aluminum"],
		["black", BLACK_COLOR, "plastic"],
		["mount", MOUNT_COLOR, "wood"],
		["fuel", FUEL_COLOR, "plastic"],
		["pressure", PRESSURE_COLOR, "plastic"]
	])
	var cast: SurfaceTool = blocks.cast
	var bright: SurfaceTool = blocks.bright
	var gold: SurfaceTool = blocks.gold
	var steel: SurfaceTool = blocks.steel
	var dark: SurfaceTool = blocks.dark
	var black: SurfaceTool = blocks.black
	var mount: SurfaceTool = blocks.mount
	var fuel: SurfaceTool = blocks.fuel
	var pressure: SurfaceTool = blocks.pressure

	# Twin hardwood rails, backplate pads and clamping hardware; all dimensions are visual estimates.
	var rail_front_z: float = engine_z - 0.0375
	var rail_rear_z: float = float(e.firewall_z) + 0.004
	var rail_center_z: float = (rail_front_z + rail_rear_z) * 0.5
	var rail_length: float = rail_rear_z - rail_front_z
	for side in [-1.0, 1.0]:
		_box(mount, Vector3(side * 0.024, shaft_y - 0.025, rail_center_z), Vector3(0.009, 0.012, rail_length))
		_box(steel, Vector3(side * 0.024, shaft_y - 0.018, rail_center_z), Vector3(0.011, 0.003, rail_length + 0.002))
		for z_offset in [-0.031, 0.031]:
			_cylinder(steel, Vector3(side * 0.024, shaft_y - 0.0155, engine_z + z_offset), Vector3(side * 0.024, shaft_y - 0.010, engine_z + z_offset), 0.0025, 0.0025, 6)
			_washer(bright, Vector3(side * 0.024, shaft_y - 0.0145, engine_z + z_offset), Vector3.UP, 0.0042, 0.0021, 0.0008, 10)
		# Rear rail bolts pass into the firewall so the mount has a visible support datum.
		var firewall_bolt: Vector3 = Vector3(side * 0.024, shaft_y - 0.015, float(e.firewall_z) + 0.001)
		_cylinder(steel, firewall_bolt - Vector3(0, 0, 0.004), firewall_bolt + Vector3(0, 0, 0.003), 0.0028, 0.0028, 6)
		_washer(bright, firewall_bolt - Vector3(0, 0, 0.0005), Vector3.FORWARD, 0.0046, 0.0024, 0.0008, 10)
		# Side mounting ear with a visible through-hole, matching the photo's mounting form.
		var ear: Vector3 = Vector3(side * 0.024, shaft_y - 0.011, engine_z + 0.018)
		_box(cast, ear, Vector3(0.014, 0.009, 0.020))
		var hole_axis_start: Vector3 = Vector3(side * 0.024, ear.y, ear.z)
		var hole_axis_end: Vector3 = Vector3(side * 0.032, ear.y, ear.z)
		_cylinder(black, hole_axis_start, hole_axis_end, 0.0022, 0.0022, 10)
		_washer(bright, Vector3(side * 0.0315, ear.y, ear.z), Vector3.RIGHT, 0.0048, 0.0021, 0.001, 12)

	# Rounded cast crankcase, covers and stepped front/rear bearing bosses.
	_ellipsoid(cast, Vector3(0, shaft_y - 0.003, engine_z + 0.003), Vector3(0.0215, 0.0165, 0.031), 12, 24)
	_ellipsoid(dark, Vector3(0.0207, shaft_y - 0.002, engine_z + 0.012), Vector3(0.0022, 0.0115, 0.017), 10, 18)
	_cylinder(bright, Vector3(0, shaft_y, engine_z - 0.040), Vector3(0, shaft_y, engine_z - 0.031), 0.0118, 0.0112, 20)
	_cylinder(cast, Vector3(0, shaft_y, engine_z + 0.028), Vector3(0, shaft_y, engine_z + 0.037), 0.014, 0.012, 20)
	_cylinder(steel, Vector3(0, shaft_y, engine_z - 0.039), Vector3(0, shaft_y, float(e.prop_z) + 0.010), 0.0046, 0.0046, 12)
	_washer(bright, Vector3(0, shaft_y, engine_z + 0.031), Vector3.FORWARD, 0.0145, 0.005, 0.0012, 20)
	for side in [-1.0, 1.0]:
		for z_offset in [-0.014, 0.025]:
			_cylinder(steel, Vector3(side * 0.0208, shaft_y - 0.003, engine_z + z_offset), Vector3(side * 0.0232, shaft_y - 0.003, engine_z + z_offset), 0.0022, 0.0022, 6)

	# Single-cylinder barrel, nine fine silver fins and a flat anodized-gold crown.
	_cylinder(cast, Vector3(0, shaft_y + 0.006, engine_z + 0.010), Vector3(0, shaft_y + 0.035, engine_z + 0.010), 0.0105, 0.0105, 18)
	for i in range(9):
		var fin_y: float = shaft_y + 0.008 + float(i) * 0.00335
		_cylinder(bright, Vector3(0, fin_y - 0.00055, engine_z + 0.010), Vector3(0, fin_y + 0.00055, engine_z + 0.010), 0.0195, 0.0195, 24)
	_cylinder(gold, Vector3(0, shaft_y + 0.037, engine_z + 0.010), Vector3(0, shaft_y + 0.044, engine_z + 0.010), 0.020, 0.020, 24)
	# Short dark reliefs read as axial slots in the finned crown; count and spacing are artistic.
	for i in range(10):
		var angle: float = TAU * float(i) / 10.0
		var slot_x: float = 0.0196 * cos(angle)
		var slot_z: float = engine_z + 0.010 + 0.0196 * sin(angle)
		_cylinder(black, Vector3(slot_x, shaft_y + 0.038, slot_z), Vector3(slot_x, shaft_y + 0.043, slot_z), 0.00045, 0.00045, 6)
	_cylinder(steel, Vector3(0, shaft_y + 0.044, engine_z + 0.010), Vector3(0, shaft_y + 0.049, engine_z + 0.010), 0.0061, 0.0061, 6)
	_cylinder(bright, Vector3(0, shaft_y + 0.049, engine_z + 0.010), Vector3(0, shaft_y + 0.053, engine_z + 0.010), 0.0033, 0.0033, 10)
	_cylinder(black, Vector3(0, shaft_y + 0.053, engine_z + 0.010), Vector3(0, shaft_y + 0.054, engine_z + 0.010), 0.0021, 0.0021, 10)

	# Carburettor rises ahead of the crankcase; its throat tilts toward the propeller and upward.
	var carb_lower := Vector3(0, shaft_y + 0.012, engine_z - 0.010)
	var carb_upper := Vector3(0, shaft_y + 0.027, engine_z - 0.026)
	var intake_axis: Vector3 = (carb_upper - carb_lower).normalized()
	_cylinder(cast, carb_lower, carb_upper, 0.0067, 0.0067, 14)
	var intake_end: Vector3 = carb_upper + intake_axis * 0.005
	_cylinder(bright, carb_upper, intake_end, 0.0067, 0.008, 16)
	_washer(bright, intake_end, intake_axis, 0.008, 0.0045, 0.001, 16)
	_cylinder(black, intake_end - intake_axis * 0.0015, intake_end - intake_axis * 0.0008, 0.0044, 0.0044, 14)
	# Throttle lever tip is exposed for the separate control-linkage pass.
	var throttle_pivot := Vector3(0.006, shaft_y + 0.017, engine_z - 0.013)
	var throttle_tip := Vector3(0.019, shaft_y + 0.031, engine_z - 0.030)
	_cylinder(steel, throttle_pivot - Vector3(0.003, 0, 0), throttle_pivot + Vector3(0.003, 0, 0), 0.0034, 0.0034, 8)
	_bar(bright, throttle_pivot, throttle_tip, 0.003, 0.0018)
	_cylinder(steel, throttle_tip - Vector3(0.0015, 0, 0), throttle_tip + Vector3(0.0015, 0, 0), 0.0018, 0.0018, 6)
	var needle := Vector3(0.029, shaft_y - 0.025, engine_z + 0.044)
	_box(dark, needle, Vector3(0.009, 0.007, 0.014))
	_cylinder(steel, needle + Vector3(0.004, 0, 0), needle + Vector3(0.010, 0, 0), 0.0021, 0.0021, 6)
	_cylinder(black, needle + Vector3(0.010, 0, 0), needle + Vector3(0.013, 0, 0), 0.003, 0.003, 8)
	_cylinder(bright, Vector3(0.008, shaft_y - 0.031, engine_z + 0.022), Vector3(0.010, shaft_y - 0.031, engine_z + 0.022), 0.0022, 0.0022, 10)

	# Longitudinal cast silencer: rounded front cap, ribbed barrel, seam and tapered rear cone.
	var muffler_center := Vector3(0.049, shaft_y - 0.004, engine_z)
	var muffler_nose := Vector3(0.049, shaft_y - 0.004, engine_z - 0.016)
	var muffler_seam_z: float = engine_z + 0.012
	_ellipsoid(cast, muffler_nose, Vector3(0.0105, 0.0105, 0.010), 10, 20)
	_cylinder(cast, Vector3(0.049, shaft_y - 0.004, engine_z - 0.016), Vector3(0.049, shaft_y - 0.004, muffler_seam_z), 0.0105, 0.0105, 22, false)
	_torus(bright, Vector3(0.049, shaft_y - 0.004, muffler_seam_z), Vector3.FORWARD, 0.0105, 0.00065, 28, 6)
	# Six shallow raised ribs run along the exposed barrel, rather than around it as ring bands.
	for rib_index in range(6):
		var rib_y: float = -0.0075 + float(rib_index) * 0.003
		var rib_x_offset: float = sqrt(maxf(0.00011025 - rib_y * rib_y, 0.000001)) + 0.00035
		var rib_a := Vector3(muffler_center.x + rib_x_offset, muffler_center.y + rib_y, engine_z - 0.012)
		var rib_b := Vector3(muffler_center.x + rib_x_offset, muffler_center.y + rib_y, muffler_seam_z - 0.002)
		_bar(bright, rib_a, rib_b, 0.00115, 0.0009, Vector3.RIGHT)

	# A broad rectangular cast neck meets the engine port; the plate carries two visible screws.
	var neck_center := Vector3(0.034, shaft_y + 0.004, engine_z + 0.009)
	_box(cast, neck_center, Vector3(0.024, 0.022, 0.022))
	_box(cast, Vector3(0.021, shaft_y + 0.004, engine_z + 0.009), Vector3(0.004, 0.028, 0.028))
	for bolt_z in [engine_z + 0.001, engine_z + 0.017]:
		var flange_bolt := Vector3(0.0232, shaft_y + 0.004, bolt_z)
		_cylinder(steel, flange_bolt, flange_bolt + Vector3(0.0028, 0, 0), 0.0021, 0.0021, 6)
		_washer(bright, flange_bolt + Vector3(0.002, 0, 0), Vector3.RIGHT, 0.004, 0.0018, 0.0007, 10)
	# Fine transverse ribs mark the raised rectangular neck while leaving the pressure port clear.
	for rib_index in range(5):
		var neck_rib_y: float = shaft_y + 0.006 + float(rib_index) * 0.002
		_bar(bright, Vector3(0.0464, neck_rib_y, engine_z + 0.002), Vector3(0.0464, neck_rib_y, engine_z + 0.015), 0.0012, 0.0009, Vector3.RIGHT)

	# Tapered rear cone and hollow outlet; the outlet endpoint remains at the established gas exit.
	var outlet_start := Vector3(0.056, shaft_y - 0.009, engine_z + 0.030)
	var outlet_end := Vector3(0.064, shaft_y - 0.018, engine_z + 0.041)
	_cylinder(cast, Vector3(0.049, shaft_y - 0.004, muffler_seam_z), outlet_start, 0.0105, 0.0044, 18, false)
	_cylinder(bright, outlet_start - Vector3(0.001, -0.0005, -0.001), outlet_start, 0.0048, 0.0044, 12, false)
	_add_hollow_outlet(bright, black, outlet_start, outlet_end, 0.0042, 0.0029)
	# Pressure fitting is kept at its existing connection point and raised off the shell by its boss.
	_cylinder(bright, Vector3(0.052, shaft_y + 0.006, engine_z + 0.011), Vector3(0.052, shaft_y + 0.010, engine_z + 0.011), 0.0032, 0.0032, 8)
	_washer(steel, Vector3(0.052, shaft_y + 0.008, engine_z + 0.011), Vector3.UP, 0.0045, 0.0026, 0.0012, 10)

	# Two visible, distinct circuits meet fittings at the firewall-facing end of the installation.
	var fuel_firewall := Vector3(0.035, shaft_y - 0.031, float(e.firewall_z) - 0.007)
	var pressure_firewall := Vector3(0.039, shaft_y + 0.002, float(e.firewall_z) - 0.007)
	for fitting in [fuel_firewall, pressure_firewall]:
		_cylinder(bright, fitting - Vector3(0, 0, 0.004), fitting + Vector3(0, 0, 0.008), 0.003, 0.003, 8)
		_washer(steel, fitting - Vector3(0, 0, 0.001), Vector3.FORWARD, 0.0046, 0.0029, 0.001, 8)
	var fuel_to_needle: Array[Vector3] = _cubic(
		fuel_firewall + Vector3(0, 0, -0.001),
		Vector3(0.043, shaft_y - 0.029, engine_z + 0.045),
		Vector3(0.038, shaft_y - 0.025, engine_z + 0.043),
		needle + Vector3(-0.003, 0, 0), 9
	)
	var fuel_to_carb: Array[Vector3] = _cubic(
		needle + Vector3(-0.003, 0.001, -0.002),
		Vector3(0.034, shaft_y - 0.024, engine_z + 0.008),
		Vector3(0.030, shaft_y + 0.013, engine_z - 0.020),
		Vector3(0.008, shaft_y + 0.017, engine_z - 0.013), 12
	)
	_cylinder(bright, Vector3(0.004, shaft_y + 0.017, engine_z - 0.013), Vector3(0.010, shaft_y + 0.017, engine_z - 0.013), 0.0019, 0.0019, 8)
	_sweep_tube(fuel, fuel_to_needle, 0.00115, 7)
	_sweep_tube(fuel, fuel_to_carb, 0.00115, 7)
	var pressure_path: Array[Vector3] = _cubic(
		Vector3(0.052, shaft_y + 0.010, engine_z + 0.011),
		Vector3(0.064, shaft_y + 0.011, engine_z + 0.016),
		Vector3(0.062, shaft_y + 0.010, float(e.firewall_z) - 0.020),
		pressure_firewall, 12
	)
	_sweep_tube(pressure, pressure_path, 0.00105, 7)
	_flush(root, "engine_assembly", blocks)


static func _add_hollow_outlet(outer: SurfaceTool, inner: SurfaceTool, a: Vector3, b: Vector3, outer_radius: float, inner_radius: float) -> void:
	var delta: Vector3 = b - a
	if delta.length() <= 0.0000001:
		return
	var axis: Vector3 = delta.normalized()
	var end_inner: Vector3 = b - axis * 0.009
	_cylinder(outer, a, b, outer_radius, outer_radius * 0.92, 12, false)
	_cylinder(inner, a + axis * 0.0004, end_inner, inner_radius, inner_radius * 0.82, 12, false)
	_washer(outer, b, axis, outer_radius * 0.92, inner_radius * 0.82, 0.001, 12)
	_cylinder(inner, end_inner - axis * 0.0002, end_inner + axis * 0.0003, inner_radius * 0.80, inner_radius * 0.80, 12)


static func _prop_blades(st: SurfaceTool, radius: float) -> void:
	var radial_fractions: Array[float] = [0.10, 0.18, 0.29, 0.41, 0.54, 0.67, 0.79, 0.89, 0.96, 1.0]
	var chord_scales: Array[float] = [0.205, 0.255, 0.285, 0.282, 0.258, 0.222, 0.178, 0.126, 0.075, 0.025]
	var pitch_degrees: Array[float] = [39.0, 36.0, 32.0, 28.0, 23.0, 19.0, 16.0, 14.0, 12.0, 10.0]
	var chord_samples: Array[float] = [0.0, 0.18, 0.42, 0.70, 0.88, 1.0]
	var thickness: Array[float] = [0.0, 0.060, 0.090, 0.075, 0.035, 0.0]
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
		for i in range(radial_fractions.size() - 1):
			var upper_a: Array = upper[i]
			var upper_b: Array = upper[i + 1]
			var lower_a: Array = lower[i]
			var lower_b: Array = lower[i + 1]
			for j in range(chord_samples.size() - 1):
				var leading_to_trailing: Vector3 = (upper_a[j + 1] - upper_a[j]).normalized()
				var outward_span: Vector3 = Vector3(0, sign, 0)
				var surface_normal: Vector3 = leading_to_trailing.cross(outward_span).normalized()
				_quad(st, upper_a[j], upper_b[j], upper_b[j + 1], upper_a[j + 1], surface_normal)
				_quad(st, lower_a[j + 1], lower_b[j + 1], lower_b[j], lower_a[j], -surface_normal)
			# Close the leading edge, trailing edge and blade tip for a readable section silhouette.
			var outer_sign: float = 1.0 if i == radial_fractions.size() - 2 else 0.0
			for j in [0, chord_samples.size() - 1]:
				var desired: Vector3 = Vector3(-1 if j == 0 else 1, 0, 0)
				_quad(st, upper_a[j], upper_b[j], lower_b[j], lower_a[j], desired)
			if outer_sign > 0.0:
				for j in range(chord_samples.size() - 1):
					_quad(st, upper_b[j], upper_b[j + 1], lower_b[j + 1], lower_b[j], Vector3(0, sign, 0))
		# The hidden root closure sits within the metal hub envelope.
		for j in range(chord_samples.size() - 1):
			_quad(st, upper[0][j + 1], upper[0][j], lower[0][j], lower[0][j + 1], Vector3(0, -sign, 0))


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
	var segments: int = 28
	var axis: Vector3 = Vector3.RIGHT
	var frame: Array[Vector3] = _frame(axis)
	var u: Vector3 = frame[0]
	var v: Vector3 = frame[1]
	for i in range(profile.size() - 1):
		var dx: float = profile[i + 1].x - profile[i].x
		var dr: float = profile[i + 1].y - profile[i].y
		for j in range(segments):
			var k: int = (j + 1) % segments
			var angle_a: float = TAU * float(j) / float(segments)
			var angle_b: float = TAU * float(k) / float(segments)
			var ra: Vector3 = (u * cos(angle_a) + v * sin(angle_a)).normalized()
			var rb: Vector3 = (u * cos(angle_b) + v * sin(angle_b)).normalized()
			var a: Vector3 = axis * profile[i].x + ra * profile[i].y
			var b: Vector3 = axis * profile[i + 1].x + ra * profile[i + 1].y
			var c: Vector3 = axis * profile[i + 1].x + rb * profile[i + 1].y
			var d: Vector3 = axis * profile[i].x + rb * profile[i].y
			var outward: Vector3 = (axis * (-dr) + (ra + rb).normalized() * dx).normalized()
			_quad(st, a, b, c, d, outward)


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


static func _add_main_gear(root: Node3D, gear: Dictionary) -> void:
	var e: Dictionary = D.equipment
	var structure: Dictionary = _buckets([
		["steel", STEEL_COLOR, "steel"],
		["aluminum", DARK_METAL_COLOR, "aluminum"],
		["bright", FIN_COLOR, "aluminum"]
	])
	var steel: SurfaceTool = structure.steel
	var aluminum: SurfaceTool = structure.aluminum
	var bright: SurfaceTool = structure.bright
	for side in [-1.0, 1.0]:
		var center: Vector3 = Vector3(side * float(e.main_track) * 0.5, float(e.wheel_y), float(e.main_axle_z))
		var root_z: float = float(e.main_axle_z) - 0.050
		var root_point: Vector3 = Vector3(side * 0.025, _fuselage_height(root_z, false) + 0.004, root_z)
		_bar(steel, root_point, center, 0.014, 0.0034)
		_box(aluminum, Vector3(side * 0.026, root_point.y + 0.003, root_z + 0.002), Vector3(0.027, 0.006, 0.030))
		for z_offset in [-0.009, 0.009]:
			var bolt_pos: Vector3 = Vector3(side * 0.026, root_point.y + 0.0065, root_z + z_offset)
			_cylinder(steel, bolt_pos, bolt_pos + Vector3(0, 0.002, 0), 0.002, 0.002, 6)
			_washer(bright, bolt_pos + Vector3(0, 0.0007, 0), Vector3.UP, 0.0037, 0.0015, 0.0007, 8)
		# Axle sleeve and castellated locknut remain on the fixed gear leg, just inside the rotating wheel.
		var sleeve_x: float = side * (float(e.main_track) * 0.5 - 0.014)
		_cylinder(bright, Vector3(sleeve_x, center.y, center.z), Vector3(sleeve_x + side * 0.006, center.y, center.z), 0.006, 0.006, 12)
		_washer(steel, Vector3(sleeve_x + side * 0.006, center.y, center.z), Vector3.RIGHT, 0.007, 0.0035, 0.0014, 10)
		var label: String = "right" if side > 0.0 else "left"
		var pivot := Node3D.new()
		pivot.name = "wheel_" + label + "_pivot"
		pivot.position = center
		root.add_child(pivot)
		gear[label] = pivot
		_add_wheel(pivot, "gear_" + label, float(e.main_wheel_diameter) * 0.5, 0.024, side)
	_flush(root, "main_gear_structure", structure)


static func _add_nose_gear(root: Node3D, gear: Dictionary) -> void:
	var e: Dictionary = D.equipment
	var y: float = float(e.wheel_y)
	var z: float = float(e.nose_axle_z)
	var nose_position: Vector3 = Vector3(0, y, z)
	var strut: Dictionary = _buckets([
		["steel", STEEL_COLOR, "steel"],
		["aluminum", DARK_METAL_COLOR, "aluminum"],
		["bright", FIN_COLOR, "aluminum"]
	])
	var steel: SurfaceTool = strut.steel
	var aluminum: SurfaceTool = strut.aluminum
	var bright: SurfaceTool = strut.bright
	var start: Vector3 = Vector3(0, _fuselage_height(float(e.firewall_z), false) + 0.012, float(e.firewall_z) + 0.009)
	var end: Vector3 = Vector3(0, y + 0.067, z)
	_sweep_tube(steel, _cubic(start, Vector3(0, start.y - 0.035, start.z + 0.020), Vector3(0, end.y + 0.048, end.z - 0.008), end, 8), 0.0033, 10)
	_cylinder(aluminum, Vector3(0, y + 0.078, z), Vector3(0, y + 0.052, z), 0.0052, 0.0047, 12)
	for x_sign in [-1.0, 1.0]:
		var bolt: Vector3 = Vector3(x_sign * 0.004, start.y + 0.003, start.z)
		_cylinder(steel, bolt, bolt + Vector3(x_sign * 0.001, 0, 0), 0.0021, 0.0021, 6)
		_washer(bright, bolt, Vector3.RIGHT, 0.0038, 0.0015, 0.0008, 8)
	_flush(root, "nose_gear_strut", strut)

	var steering := Node3D.new()
	steering.name = "nose_steering_pivot"
	steering.position = nose_position
	root.add_child(steering)
	gear["steering"] = steering
	var nose_axle := Node3D.new()
	nose_axle.name = "wheel_nose_pivot"
	nose_axle.position = Vector3.ZERO
	steering.add_child(nose_axle)
	gear["nose"] = nose_axle
	_add_wheel(nose_axle, "nosewheel", float(e.nose_wheel_diameter) * 0.5, 0.022, 1.0)

	var fork: Dictionary = _buckets([
		["steel", STEEL_COLOR, "steel"],
		["aluminum", DARK_METAL_COLOR, "aluminum"],
		["bright", FIN_COLOR, "aluminum"]
	])
	var fork_steel: SurfaceTool = fork.steel
	var fork_aluminum: SurfaceTool = fork.aluminum
	var fork_bright: SurfaceTool = fork.bright
	# Coaxial steering stem stays inside the fixed bearing at every yaw angle.
	_cylinder(fork_steel, Vector3(0, 0.047, 0), Vector3(0, 0.075, 0), 0.0033, 0.0033, 12)
	_bar(fork_steel, Vector3(-0.012, 0.055, 0.004), Vector3(0.012, 0.055, 0.004), 0.006, 0.007)
	for side in [-1.0, 1.0]:
		_bar(fork_steel, Vector3(side * 0.012, 0.060, 0.004), Vector3(side * 0.012, -0.003, 0.004), 0.0048, 0.003)
		_cylinder(fork_aluminum, Vector3(side * 0.012, -0.001, -0.002), Vector3(side * 0.012, 0.004, -0.002), 0.004, 0.004, 10)
		_bar(fork_bright, Vector3(0, 0.047, 0.004), Vector3(side * 0.024, 0.048, 0.004), 0.003, 0.002)
		_cylinder(fork_steel, Vector3(side * 0.012, 0.000, -0.002), Vector3(side * 0.012, 0.003, -0.002), 0.0024, 0.0024, 6)
	_flush(steering, "nose_fork_and_steering_arm", fork)


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

	var blades := _surface(WOOD_COLOR, "wood")
	_prop_blades(blades, float(e.prop_diameter) * 0.5)
	_flush(propeller, "propeller_blades", {"wood": blades})
	var hub_buckets: Dictionary = _buckets([
		["aluminum", CASE_COLOR, "aluminum"],
		["steel", STEEL_COLOR, "steel"],
		["dark", DARK_METAL_COLOR, "aluminum"]
	])
	var hub_aluminum: SurfaceTool = hub_buckets.aluminum
	var hub_steel: SurfaceTool = hub_buckets.steel
	var hub_dark: SurfaceTool = hub_buckets.dark
	_cylinder(hub_aluminum, Vector3(0, 0, -0.014), Vector3(0, 0, 0.012), 0.0105, 0.0105, 20)
	_cylinder(hub_aluminum, Vector3(0, 0, 0.008), Vector3(0, 0, 0.012), 0.015, 0.014, 20)
	_washer(hub_steel, Vector3(0, 0, 0.012), Vector3.FORWARD, 0.018, 0.0052, 0.0015, 24)
	_washer(hub_steel, Vector3(0, 0, -0.007), Vector3.FORWARD, 0.017, 0.0052, 0.0012, 24)
	_cylinder(hub_steel, Vector3(0, 0, -0.009), Vector3(0, 0, -0.017), 0.0064, 0.0061, 6)
	_cylinder(hub_dark, Vector3(0, 0, -0.017), Vector3(0, 0, -0.020), 0.0035, 0.0035, 8)
	_flush(propeller, "propeller_hub_washers_nut", hub_buckets)

	_add_engine(root)
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
