## L10b-R1: fitted joinery; dimensions are visual estimates inside the original footprint.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")
const FRAME := Color(0.08, 0.16, 0.20)
const INOX := Color(0.8, 0.8, 0.8)
const RUBBER := Color(0.01, 0.01, 0.01)
const CONCRETE := Color(0, 0, 1)

static func build(width: float, depth: float, height: float) -> MeshKit:
	var kit := MeshKit.new()
	# The slab keeps the full original envelope; every anchor plate is inset.
	_box(kit, Vector3(width, 0.025, depth), Vector3(0, 0.0125, 0), 0.004, CONCRETE)
	var x := width * 0.5 - 0.035
	var z := depth * 0.5 - 0.035
	var corners := [Vector3(-x, 0, z), Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z)]
	for p: Vector3 in corners:
		_box(kit, Vector3(0.066, 0.006, 0.066), p + Vector3.UP * 0.028, 0.003, FRAME)
		_box(kit, Vector3(0.04, height - 0.037, 0.04), p + Vector3.UP * ((height + 0.025) * 0.5 - 0.006), 0.003, FRAME)
		_box(kit, Vector3(0.043, 0.012, 0.043), p + Vector3.UP * (height - 0.006), 0.003, RUBBER)
		for dx: float in [-0.025, 0.025]:
			for dz: float in [-0.025, 0.025]:
				_bolt(kit, p + Vector3(dx, 0.031, dz), Vector3.UP, 0.004)
	for side in 3:
		var a: Vector3 = corners[side]
		var b: Vector3 = corners[side + 1]
		var front := side == 1
		var direction := (b - a).normalized()
		var normal := Vector3.FORWARD if front else (Vector3.LEFT if side == 0 else Vector3.RIGHT)
		var length := a.distance_to(b) - 0.04
		var middle := (a + b) * 0.5
		var rail_size := Vector3(length, 0.04, 0.04) if front else Vector3(0.04, 0.04, length)
		_box(kit, rail_size, middle + Vector3.UP * (height - 0.032), 0.004, FRAME)
		for row in 4:
			var y := lerpf(0.13, height - 0.13, float(row) / 3.0)
			var centre := middle + Vector3.UP * y
			# Blue stores the grain direction while red varies the board's finish.
			var color := Color(0.62 + float((row * 7 + side * 3) % 11) * 0.018, 0.40, 0.12 if front else 0.28)
			var size := Vector3(length, 0.07, 0.018) if front else Vector3(0.018, 0.07, length)
			_box(kit, size, centre, 0.002, color)
			for end: float in [-1.0, 1.0]:
				var attachment := centre + direction * end * (length * 0.5 - 0.021)
				# Powder-coated end clips wrap each timber board; retain open gaps.
				var clip_size := Vector3(0.028, 0.052, 0.021) if front else Vector3(0.021, 0.052, 0.028)
				_box(kit, clip_size, attachment, 0.0015, FRAME)
				for face: float in [-1.0, 1.0]:
					_bolt(kit, attachment + normal * face * 0.011, normal * face, 0.004)
		# Two restrained reflective bands mark the rear entrance posts.
		if side != 1:
			var rear: Vector3 = a if side == 0 else b
			var strip := Vector3(0.001, 0.035, 0.025)
			_box(kit, strip, rear + normal * 0.0203 + Vector3.UP * (height - 0.09), 0.0001, INOX)
	# A low ribbed anti-slip entrance strip, not a rail across the rear opening.
	for rib in 4:
		_box(kit, Vector3(width - 0.18, 0.002, 0.006), Vector3(0, 0.026, depth * 0.5 - 0.07 - rib * 0.009), 0.0005, RUBBER)
	return kit


static func _bolt(kit: MeshKit, origin: Vector3, normal: Vector3, radius: float) -> void:
	var axis := Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD
	var tangent := normal.cross(axis).normalized()
	var saved := kit.xf
	kit.xf = Transform3D(Basis(tangent, normal, tangent.cross(normal)), origin)
	kit.cylinder(radius * 1.35, radius * 1.35, 0.001, 8, Vector3.ZERO, INOX)
	kit.cylinder(radius, radius, 0.002, 6, Vector3.UP * 0.001, INOX)
	kit.xf = saved


## Four octagonal rings round all twelve edges; flat end faces close the mesh.
static func _box(kit: MeshKit, size: Vector3, centre: Vector3, bevel: float, color: Color) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.4)
	var rings: Array[PackedVector3Array] = []
	for r in 4:
		var inset := b if r == 0 or r == 3 else 0.0
		var hx := h.x - inset
		var hz := h.z - inset
		var edge := minf(b, minf(hx, hz) * 0.4)
		var y: float = [-h.y, -h.y + b, h.y - b, h.y][r]
		var ring := PackedVector3Array()
		for p: Vector2 in [Vector2(hx-edge,-hz),Vector2(hx,-hz+edge),Vector2(hx,hz-edge),Vector2(hx-edge,hz),Vector2(-hx+edge,hz),Vector2(-hx,hz-edge),Vector2(-hx,-hz+edge),Vector2(-hx+edge,-hz)]:
			ring.append(centre + Vector3(p.x, y, p.y))
		rings.append(ring)
	for r in 3:
		for i in 8:
			var j := (i + 1) % 8
			kit.quad(rings[r][i], rings[r+1][i], rings[r+1][j], rings[r][j], color)
	kit.poly(rings[0], color)
	var top := rings[3]
	top.reverse()
	kit.poly(top, color)
