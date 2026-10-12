## Original procedural temperate club vegetation. Static trunks and most crowns remain
## cell-batched; one small per-instance crown/tip mesh gets bounded sim_clock wind motion.
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")


static func shade_tree(k: MeshKit, seed: int, theme: String) -> Array:
	# LU-08: three crown habits share the existing conservative collision envelope.
	# Botanical scale and colours are art estimates; no external mesh/texture dependency.
	var habit := int(Palette.hash01(seed, 3) * 3.0)
	var height := 9.25 + 0.75 * Palette.hash01(seed, 1)
	var trunk_h := 3.1 + 0.45 * Palette.hash01(seed, 2)
	var trunk := Palette.col("trunk")
	var leaf := Palette.veg("leaf", theme).lerp(Palette.veg("leaf_light", theme), 0.12)
	var light := Palette.veg("leaf_light", theme)
	var dark := Palette.veg("leaf_dark", theme)
	var lean := Vector3(0.42 * (Palette.hash01(seed, 4) - 0.5), 0.0,
		0.42 * (Palette.hash01(seed, 5) - 0.5))
	k.cylinder(0.34, 0.19, trunk_h, 9, Vector3.ZERO, trunk)
	k.cylinder(0.36, 0.31, 0.20, 8, Vector3.ZERO, trunk.darkened(0.08), true, trunk.darkened(0.18))
	# Root flares ground the trunk without adding props around the parking spaces.
	for i in 5:
		var a := TAU * (float(i) / 5.0 + 0.09 * Palette.hash01(seed, i, 6))
		k.beam(Vector3(0, 0.32, 0), Vector3(cos(a) * 0.48, 0.06, sin(a) * 0.48), 0.13, trunk)
	var limbs := 4 + habit
	for i in limbs:
		var a := TAU * (float(i) / limbs + 0.08 * Palette.hash01(seed, i, 7))
		var reach := 1.3 + 0.75 * Palette.hash01(seed, i, 8)
		var start := Vector3(0, trunk_h * (0.64 + 0.15 * Palette.hash01(seed, i, 9)), 0)
		var end := lean + Vector3(cos(a) * reach, 5.2 + 1.4 * Palette.hash01(seed, i, 10), sin(a) * reach)
		var elbow := start.lerp(end, 0.55) + lean
		k.beam(start, elbow, 0.19, trunk)
		k.beam(elbow, end, 0.12, trunk.lightened(0.04))
		# Forks terminate within foliage, avoiding bare spikes and detached crown islands.
		var fork := end + Vector3(cos(a + 0.48) * 0.65, 0.75, sin(a + 0.48) * 0.65)
		k.beam(end, fork, 0.065, trunk.lightened(0.05))
	# Connected lower, middle and upper masses produce a tree rather than a ring of balls.
	var lower_size := Vector3(5.5, 3.65, 5.2)
	var upper_size := Vector3(3.65, 3.9, 3.5)
	var crown_offset := Vector3(0.30, 0, -0.20)
	if habit == 1: # upright, one dominant leader
		lower_size = Vector3(4.6, 4.3, 4.8)
		upper_size = Vector3(3.25, 4.4, 3.35)
		crown_offset = Vector3(-0.45, 0, 0.20)
	elif habit == 2: # spreading, off-centre crown
		lower_size = Vector3(5.7, 3.1, 5.25)
		upper_size = Vector3(4.05, 3.7, 3.6)
		crown_offset = Vector3(0.55, 0, 0.30)
	k.ellipsoid(lean + Vector3(0, 5.65, 0), lower_size, leaf.lerp(dark, 0.30), seed, 9, 5)
	k.ellipsoid(lean + crown_offset + Vector3(0, height - upper_size.y * 0.5, 0),
		upper_size, leaf, seed + 11, 9, 5)
	for i in 10:
		var a := TAU * (float(i) / 10.0 + 0.07 * Palette.hash01(seed, i, 11))
		var radius := 1.75 + 0.42 * Palette.hash01(seed, i, 12)
		if habit == 1:
			radius *= 0.88
		var y := 5.45 + 1.65 * Palette.hash01(seed, i, 13)
		var size := 2.20 + 0.55 * Palette.hash01(seed, i, 14)
		var center := lean + Vector3(cos(a) * radius, y, sin(a) * radius)
		var tint := leaf.lerp(light, 0.12 + 0.28 * Palette.hash01(seed, i, 15))
		k.ellipsoid(center, Vector3(size, size * (0.94 + 0.22 * habit), size * 0.94), tint, seed + i + 20, 7, 4)
		# Smaller overlapping sprays break up the large planar crown silhouette.
		var spray := center + Vector3(cos(a) * 0.60, 0.70, sin(a) * 0.60)
		k.ellipsoid(spray, Vector3(1.35, 1.5, 1.3), tint.lerp(light, 0.12), seed + i + 40, 6, 3)
	var tips := MeshKit.new()
	var pivot := Vector3(0, trunk_h, 0)
	for i in 4:
		var a := TAU * (float(i) / 4.0 + Palette.hash01(seed, i, 20) * 0.14)
		var start := Vector3(cos(a) * 2.0, 6.1, sin(a) * 2.0)
		var end := Vector3(cos(a) * 3.05, 6.2 + 0.9 * Palette.hash01(seed, i, 22), sin(a) * 3.05)
		tips.beam(start - pivot, end - pivot, 0.045, trunk)
		tips.ellipsoid(end - pivot, Vector3(1.4, 1.55, 1.4), leaf.lerp(light, 0.32), seed + i + 31, 7, 4)
	return [{kind = "crown", motion_mode = 3, kit = tips, pivot = pivot, axis = Vector3.UP,
		rate = _rate(seed, 24), phase = Palette.hash01(seed, 25)}]


static func bush(k: MeshKit, seed: int, theme: String) -> Array:
	var leaf: Color = Palette.veg("hedge", theme)
	var light: Color = Palette.veg("hedge_light", theme)
	var bark: Color = Palette.col("trunk").darkened(0.12)
	# Low stems fan from the base, rather than reading as three freestanding spheres.
	k.cylinder(0.08, 0.055, 0.34, 6, Vector3(0.0, 0.0, 0.0), bark)
	for i in 5:
		var angle := TAU * (float(i) / 5.0 + Palette.hash01(seed, i, 31) * 0.10)
		var r: float = 0.45 + 0.14 * Palette.hash01(seed, i, 32)
		var tip := Vector3(cos(angle) * r, 0.42 + 0.22 * Palette.hash01(seed, i, 33), sin(angle) * r)
		k.beam(Vector3(0.0, 0.16, 0.0), tip, 0.035, bark)
		var size: float = 0.62 + 0.10 * Palette.hash01(seed, i, 34)
		var tint := leaf.lerp(light, 0.12 + 0.45 * Palette.hash01(seed, i, 35))
		k.ellipsoid(tip + Vector3(0.0, 0.06, 0.0), Vector3(size, 0.46 + size * 0.20, size),
			tint, seed + i + 10, 7, 3, 0.08)
	k.ellipsoid(Vector3(0.0, 0.48, 0.0), Vector3(0.76, 0.56, 0.72), leaf, seed + 41, 8, 3, 0.1)

	var tips := MeshKit.new()
	var pivot := Vector3.ZERO
	for i in 3:
		var angle := TAU * (float(i) / 3.0 + Palette.hash01(seed, i, 42) * 0.16)
		var start := Vector3(cos(angle) * 0.28, 0.36, sin(angle) * 0.28)
		var end := Vector3(cos(angle) * 0.70, 0.65 + 0.08 * Palette.hash01(seed, i, 43), sin(angle) * 0.70)
		tips.beam(start, end, 0.025, bark)
		tips.ellipsoid(end, Vector3(0.43, 0.32, 0.43), light, seed + i + 51, 6, 3, 0.08)
	return [{kind = "bush_tips", motion_mode = 3, kit = tips, pivot = pivot, axis = Vector3.UP,
		rate = _rate(seed, 45), phase = Palette.hash01(seed, 46)}]


static func _rate(seed: int, salt: int) -> float:
	# The shader clock wraps every 1024 seconds; integer ticks keep the cycle seamless.
	return float(64 + posmod(seed + salt, 33)) / 1024.0
