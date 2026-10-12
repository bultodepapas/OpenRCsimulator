## Original procedural temperate club vegetation. Static trunks and most crowns remain
## cell-batched; one small per-instance crown/tip mesh gets bounded sim_clock wind motion.
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")


static func shade_tree(k: MeshKit, seed: int, theme: String) -> Array:
	var height: float = 9.35 + 0.95 * Palette.hash01(seed, 1)
	var trunk_h: float = height * (0.355 + 0.025 * Palette.hash01(seed, 2))
	var trunk: Color = Palette.col("trunk")
	var leaf: Color = Palette.veg("leaf", theme)
	var light: Color = Palette.veg("leaf_light", theme)
	var dark: Color = Palette.veg("leaf_dark", theme)
	var crown_shape := int(Palette.hash01(seed, 3) * 3.0)

	# A tapering, gently irregular trunk and visible first-order limbs.
	k.cylinder(0.34, 0.19, trunk_h, 9, Vector3.ZERO, trunk)
	k.cylinder(0.36, 0.31, 0.20, 8, Vector3.ZERO, trunk.darkened(0.08), true, trunk.darkened(0.18))
	var limb_count := 5
	for i in limb_count:
		var angle := TAU * (float(i) / limb_count + Palette.hash01(seed, i, 4) * 0.12)
		var start_y: float = trunk_h * (0.62 + 0.16 * Palette.hash01(seed, i, 5))
		var start := Vector3(0.0, start_y, 0.0)
		var reach: float = 1.45 + 0.50 * Palette.hash01(seed, i, 6)
		var end := Vector3(cos(angle) * reach, trunk_h + 1.35 + 0.55 * Palette.hash01(seed, i, 7), sin(angle) * reach)
		var mid := start.lerp(end, 0.62) + Vector3(0.0, 0.12, 0.0)
		k.beam(start, mid, 0.17, trunk)
		k.beam(mid, end, 0.105, trunk.lightened(0.04))
		var outer := Vector3(cos(angle) * (reach + 1.0), end.y + 0.35, sin(angle) * (reach + 1.0))
		k.beam(end, outer, 0.065, trunk.lightened(0.06))

	# Break the old continuous dome into overlapping, differently sized masses. The
	# three crown recipes keep a recognizable broadleaf silhouette without cloning one tree.
	var core_size := Vector3(5.0, 3.65, 5.0)
	if crown_shape == 1:
		core_size = Vector3(4.8, 4.3, 4.8) # taller crown
	elif crown_shape == 2:
		core_size = Vector3(5.3, 3.1, 4.7) # low spreading crown
	var core_y: float = trunk_h + 2.55 + 0.20 * Palette.hash01(seed, 8)
	k.ellipsoid(Vector3(0.0, core_y, 0.0), core_size, leaf.lerp(dark, 0.28), seed, 9, 4)
	var lobes := 7
	for i in lobes:
		var angle := TAU * (float(i) / lobes + Palette.hash01(seed, i, 9) * 0.10)
		var radius: float = 1.75 + 0.45 * Palette.hash01(seed, i, 10)
		var y: float = trunk_h + 2.3 + 1.0 * Palette.hash01(seed, i, 11)
		var width: float = 2.55 + 0.55 * Palette.hash01(seed, i, 12)
		var depth: float = width * (0.82 + 0.22 * Palette.hash01(seed, i, 13))
		var tint := leaf.lerp(light, 0.18 + 0.55 * Palette.hash01(seed, i, 14))
		k.ellipsoid(Vector3(cos(angle) * radius, y, sin(angle) * radius),
			Vector3(width, width * 0.77, depth), tint, seed + i + 1, 8, 3)
	var crest := Vector3(0.35 * (Palette.hash01(seed, 15) - 0.5), height - 1.2, -0.25)
	k.ellipsoid(crest, Vector3(2.6, 2.2, 2.5), light.lerp(leaf, 0.28), seed + 23, 8, 3)

	# Flexible outer twigs and leaves sit in one small mesh. Their absolute positions
	# are stored relative to the crown pivot; the renderer supplies the placement transform.
	var tips := MeshKit.new()
	var pivot := Vector3(0.0, trunk_h, 0.0)
	for i in 4:
		var angle := TAU * (float(i) / 4.0 + Palette.hash01(seed, i, 20) * 0.14)
		var start := Vector3(cos(angle) * 1.85, trunk_h + 2.8, sin(angle) * 1.85)
		var end := Vector3(cos(angle) * (3.05 + 0.22 * Palette.hash01(seed, i, 21)),
			trunk_h + 3.25 + 0.55 * Palette.hash01(seed, i, 22),
			sin(angle) * (3.05 + 0.22 * Palette.hash01(seed, i, 21)))
		tips.beam(start - pivot, end - pivot, 0.07, trunk.lightened(0.05))
		tips.ellipsoid(end - pivot, Vector3(1.45, 1.15, 1.45),
			leaf.lerp(light, 0.35 + 0.35 * Palette.hash01(seed, i, 23)), seed + i + 31, 7, 3)
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
