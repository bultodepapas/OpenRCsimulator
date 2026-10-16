## L10c-R1: visual joinery inside the existing collision envelope.
extends RefCounted
const MeshKit = preload("res://scenery/mesh_kit.gd")

static func append(kit: MeshKit, part: Dictionary, index: int) -> void:
	var size: Vector3 = part.size
	var centre: Vector3 = part.base + Vector3.UP * size.y * 0.5
	var color: Color = part.color
	if part.profile == "wood":
		# Opaque shader uses alpha as a stable grain/stain offset, never transparency.
		color.a = float((index * 37) % 101) / 100.0
		var saved := kit.xf
		kit.xf = Transform3D(Basis(Vector3.BACK, -PI * 0.5), centre)
		_prism(kit, Vector3(size.y, size.x - 0.08, size.z), Vector3.ZERO, 0.002, color)
		kit.xf = saved
		for end: float in [-1.0, 1.0]:
			var x := centre.x + end * (size.x * 0.5 - 0.065)
			for side: float in [-1.0, 1.0]:
				# A shallow galvanized splice plate, washer and hexagonal fastener.
				kit.box(Vector3(0.035, 0.038, 0.0015), Vector3(x, centre.y, side * 0.03075), Color("#737b7d"), true)
				kit.xf = Transform3D(Basis(Vector3.RIGHT, side * PI * 0.5), Vector3(x, centre.y, side * 0.0315))
				kit.cylinder(0.008, 0.008, 0.001, 8, Vector3.ZERO, Color("#929b9d"))
				kit.cylinder(0.0055, 0.0055, 0.003, 6, Vector3(0, 0.001, 0), Color("#bac1c0"))
				kit.xf = saved
	else:
		# The body is slightly inset below the wider cap and ground shoe.
		if size.y > 0.03:
			size.x -= 0.006
			size.z -= 0.006
		_prism(kit, size, centre, 0.003, color)


## Eight-sided cross section: real longitudinal bevels catch the sun at grazing angles.
static func _prism(kit: MeshKit, size: Vector3, centre: Vector3, bevel: float, color: Color) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, h.z) * 0.4)
	var section := PackedVector2Array([
		Vector2(h.x - b, -h.z), Vector2(h.x, -h.z + b),
		Vector2(h.x, h.z - b), Vector2(h.x - b, h.z),
		Vector2(-h.x + b, h.z), Vector2(-h.x, h.z - b),
		Vector2(-h.x, -h.z + b), Vector2(-h.x + b, -h.z)])
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
