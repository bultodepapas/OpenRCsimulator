## L10c-R3: fitted timber, galvanized rail saddles and formed post caps.
## Every fitting stays inside its parent's damage range and the original cue envelope.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")

# The low green channel tags newly fitted zinc hardware in the shared shader.
const STEEL := Color(0.25, 0.15, 0.40)
const STEEL_EDGE := Color(0.33, 0.15, 0.48)
const BOLT := Color(0.43, 0.15, 0.56)


static func append(kit: MeshKit, part: Dictionary, index: int) -> void:
	var size: Vector3 = part.size
	var centre: Vector3 = part.base + Vector3.UP * size.y * 0.5
	if part.profile == "wood":
		# Red selects timber in the shared material and varies its weathering per board.
		var timber := Color(0.72 + 0.18 * float((index * 37) % 101) / 100.0, 0.46, 0.28)
		var saved := kit.xf
		kit.xf = Transform3D(Basis(Vector3.BACK, -PI * 0.5), centre)
		_timber(kit, Vector3(size.y, size.x - 0.092, size.z), timber, index)
		kit.xf = saved
		for end: float in [-1.0, 1.0]:
			_rail_saddle(kit, centre, size.x, end)
	elif size.y <= 0.03 and part.base.y > 0.1:
		_post_cap(kit, centre, size, part.color)
	else:
		# The buried shoe is full width; the steel tube fits just inside its lip.
		if size.y > 0.03:
			size.x -= 0.006
			size.z -= 0.006
		_prism(kit, size, centre, 0.003, part.color)


## A timber has eight actual bevel faces and a slight, deterministic bow between its cut ends.
## The 6 mm end clearance exposes the cut and gives the saddle a plausible bearing gap.
static func _timber(kit: MeshKit, size: Vector3, color: Color, index: int) -> void:
	var h := size * 0.5
	var bevel := 0.0025
	var section := _section(h.x, h.z, bevel)
	var bow_x := (float(index % 7) - 3.0) * 0.0005
	var bow_z := (float(index % 5) - 2.0) * 0.0008
	var rings: Array[PackedVector3Array] = []
	for station: int in 3:
		var t := float(station) / 2.0
		var crown := sin(t * PI)
		var ring := PackedVector3Array()
		for p: Vector2 in section:
			ring.append(Vector3(p.x + bow_x * crown, lerpf(-h.y, h.y, t), p.y + bow_z * crown))
		rings.append(ring)
	for station: int in 2:
		for side: int in 8:
			var next := (side + 1) % 8
			kit.quad(rings[station][side], rings[station + 1][side],
				rings[station + 1][next], rings[station][next], color)
	kit.poly(rings[0], color.darkened(0.12))
	var far_end := rings[2].duplicate()
	far_end.reverse()
	kit.poly(far_end, color.darkened(0.12))


## A folded U saddle bears the timber's underside and cheeks, then meets the post face.
## The runway face gets a domed carriage-bolt head; the back carries its washer and nut.
static func _rail_saddle(kit: MeshKit, centre: Vector3, span: float, end: float) -> void:
	var cut_x := centre.x + end * (span * 0.5 - 0.046)
	var cheek_x := cut_x - end * 0.055
	var post_face_x := cut_x + end * 0.006
	kit.box(Vector3(0.002, 0.052, 0.066), Vector3(post_face_x, centre.y, 0.0), STEEL, true)
	kit.box(Vector3(0.12, 0.002, 0.064), Vector3(cheek_x, centre.y - 0.026, 0.0), STEEL_EDGE, true)
	for side: float in [-1.0, 1.0]:
		kit.box(Vector3(0.12, 0.040, 0.002), Vector3(cheek_x, centre.y, side * 0.031), STEEL, true)
		var saved := kit.xf
		var bolt_x := cut_x - end * 0.070
		kit.xf = Transform3D(Basis(Vector3.RIGHT, side * PI * 0.5),
			Vector3(bolt_x, centre.y, side * 0.032))
		kit.cylinder(0.009, 0.009, 0.0013, 10, Vector3.ZERO, STEEL_EDGE)
		if side > 0.0:
			kit.cylinder(0.0072, 0.0025, 0.0034, 10, Vector3(0, 0.0013, 0), BOLT)
		else:
			kit.cylinder(0.0065, 0.0065, 0.0034, 6, Vector3(0, 0.0013, 0), BOLT)
		kit.xf = saved


## Pressed galvanized cap: 12 mm skirt, narrow gasket seam and a shallow four-way crown.
## The complete cap retains the nominal 80 mm footprint and 20 mm height.
static func _post_cap(kit: MeshKit, centre: Vector3, size: Vector3, color: Color) -> void:
	var bottom := centre.y - size.y * 0.5
	kit.box(Vector3(size.x, 0.0015, size.z), Vector3(centre.x, bottom + 0.00075, centre.z),
		Color("#424b4b"), true)
	_prism(kit, Vector3(size.x, 0.011, size.z),
		Vector3(centre.x, bottom + 0.007, centre.z), 0.0015, color)
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		lower.append(Vector3(centre.x + corner.x * size.x * 0.5, bottom + 0.0125,
			centre.z + corner.y * size.z * 0.5))
		upper.append(Vector3(centre.x + corner.x * (size.x * 0.5 - 0.008), bottom + size.y,
			centre.z + corner.y * (size.z * 0.5 - 0.008)))
	kit.quad(lower[3], lower[2], upper[2], upper[3], color.lightened(0.035))
	kit.quad(lower[1], lower[0], upper[0], upper[1], color.darkened(0.03))
	kit.quad(lower[2], lower[1], upper[1], upper[2], color)
	kit.quad(lower[0], lower[3], upper[3], upper[0], color)
	kit.quad(upper[3], upper[2], upper[1], upper[0], color.lightened(0.08))


static func _section(half_x: float, half_z: float, bevel: float) -> PackedVector2Array:
	var b := minf(bevel, minf(half_x, half_z) * 0.4)
	return PackedVector2Array([
		Vector2(half_x - b, -half_z), Vector2(half_x, -half_z + b),
		Vector2(half_x, half_z - b), Vector2(half_x - b, half_z),
		Vector2(-half_x + b, half_z), Vector2(-half_x, half_z - b),
		Vector2(-half_x, -half_z + b), Vector2(-half_x + b, -half_z)])


static func _prism(kit: MeshKit, size: Vector3, centre: Vector3, bevel: float, color: Color) -> void:
	var h := size * 0.5
	var section := _section(h.x, h.z, bevel)
	var low := PackedVector3Array()
	var high := PackedVector3Array()
	for p: Vector2 in section:
		low.append(centre + Vector3(p.x, -h.y, p.y))
		high.append(centre + Vector3(p.x, h.y, p.y))
	for i in 8:
		var j := (i + 1) % 8
		kit.quad(low[i], high[i], high[j], low[j], color)
	kit.poly(low, color)
	high.reverse()
	kit.poly(high, color)
