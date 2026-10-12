## Original procedural temperate club vegetation. Static trunks and most crowns remain
## cell-batched; one small per-instance crown/tip mesh gets bounded sim_clock wind motion.
extends RefCounted

const MeshKit = preload("res://scenery/mesh_kit.gd")
const Palette = preload("res://scenery/palette.gd")
const LEAF_LIGHT := Vector3(-0.46, 0.82, -0.32)


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
	# A small irregular core joins horizontal canopy lobes. The old two deep ellipsoids read as
	# one oversized ball; these flattened masses leave visible air and branch structure between layers.
	var lower_size := Vector3(4.35, 2.35, 4.10)
	var upper_size := Vector3(3.20, 2.85, 3.05)
	var crown_offset := Vector3(0.30, 0, -0.20)
	if habit == 1: # upright, one dominant leader
		lower_size = Vector3(3.85, 2.90, 4.15)
		upper_size = Vector3(3.05, 3.65, 3.15)
		crown_offset = Vector3(-0.45, 0, 0.20)
	elif habit == 2: # spreading, off-centre crown
		lower_size = Vector3(4.80, 2.25, 4.55)
		upper_size = Vector3(3.55, 2.65, 3.20)
		crown_offset = Vector3(0.55, 0, 0.30)
	_leaf_mass(k, lean + Vector3(0, 5.65, 0), lower_size, leaf.lerp(dark, 0.30), light, dark,
		seed, 14, 7, 0.0, 0.025, 0.0, 0.11)
	_leaf_mass(k, lean + crown_offset + Vector3(0, height - upper_size.y * 0.5, 0),
		upper_size, leaf, light, dark, seed + 11, 14, 7, 0.0, 0.025, 0.0, 0.09)
	# Stagger flattened lobes around the branches. Their height layers and uneven radial reach make
	# the outer crown read as overlapping foliage rather than a round ball with little balls attached.
	var lobe_count := 8 + habit
	for i in lobe_count:
		var a := TAU * float(i) / float(lobe_count) + (Palette.hash01(seed, i, 101) - 0.5) * 0.20
		var radial := Vector3(cos(a), 0.0, sin(a))
		var layer := i % 3
		var radius := 1.35 + 0.95 * Palette.hash01(seed, i, 102)
		var layer_y: float = [5.25, 6.10, 6.90][layer]
		var y: float = layer_y + 0.32 * (Palette.hash01(seed, i, 103) - 0.5)
		if habit == 1:
			y += 0.22
			radius *= 0.90
		elif habit == 2:
			y -= 0.08
			radius += 0.08
		var radial_size := 1.80 + 0.50 * Palette.hash01(seed, i, 104)
		var height_size := 0.88 + 0.34 * Palette.hash01(seed, i, 105)
		var breadth := 1.45 + 0.46 * Palette.hash01(seed, i, 106)
		var size := Vector3(radial_size, height_size, breadth)
		var center := lean + crown_offset * 0.35 + radial * radius + Vector3(0.0, y, 0.0)
		var tint := leaf.lerp(light, 0.10 + 0.22 * Palette.hash01(seed, i, 107))
		_leaf_mass(k, center, size, tint, light, dark, seed + i + 20, 10, 5, -a, 0.02, 0.0, 0.08)
	var tips := MeshKit.new()
	var pivot := Vector3(0, trunk_h, 0)
	for i in 4:
		var a := TAU * (float(i) / 4.0 + Palette.hash01(seed, i, 20) * 0.14)
		var start := Vector3(cos(a) * 1.9, 6.1, sin(a) * 1.9)
		var end := Vector3(cos(a) * 2.78, 6.2 + 0.9 * Palette.hash01(seed, i, 22), sin(a) * 2.78)
		tips.beam(start - pivot, end - pivot, 0.045, trunk)
		_leaf_mass(tips, end - pivot, Vector3(1.65, 0.92, 1.22), leaf.lerp(light, 0.32), light, dark,
			seed + i + 31, 9, 5, a, 0.02, 0.0, 0.10)
	return [{kind = "crown", motion_mode = 3, kit = tips, pivot = pivot, axis = Vector3.UP,
		rate = _rate(seed, 24), phase = Palette.hash01(seed, 25)}]


static func bush(k: MeshKit, seed: int, theme: String) -> Array:
	var leaf: Color = Palette.veg("hedge", theme)
	var light: Color = Palette.veg("hedge_light", theme)
	var dark: Color = leaf.darkened(0.22)
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
		_leaf_mass(k, tip + Vector3(0.0, 0.06, 0.0), Vector3(size, 0.46 + size * 0.20, size),
			tint, light, dark, seed + i + 10, 7, 4, angle, 0.08, 0.08)
	_leaf_mass(k, Vector3(0.0, 0.48, 0.0), Vector3(0.76, 0.56, 0.72), leaf, light, dark,
		seed + 41, 8, 4, 0.0, 0.07, 0.1)

	var tips := MeshKit.new()
	var pivot := Vector3.ZERO
	for i in 3:
		var angle := TAU * (float(i) / 3.0 + Palette.hash01(seed, i, 42) * 0.16)
		var start := Vector3(cos(angle) * 0.28, 0.36, sin(angle) * 0.28)
		var end := Vector3(cos(angle) * 0.70, 0.65 + 0.08 * Palette.hash01(seed, i, 43), sin(angle) * 0.70)
		tips.beam(start, end, 0.025, bark)
		_leaf_mass(tips, end, Vector3(0.43, 0.32, 0.43), light, light, dark,
			seed + i + 51, 7, 4, angle, 0.035, 0.08)
	return [{kind = "bush_tips", motion_mode = 3, kit = tips, pivot = pivot, axis = Vector3.UP,
		rate = _rate(seed, 45), phase = Palette.hash01(seed, 46)}]


static func _rate(seed: int, salt: int) -> float:
	# The shader clock wraps every 1024 seconds; integer ticks keep the cycle seamless.
	return float(64 + posmod(seed + salt, 33)) / 1024.0


## A softly shaded ellipsoid assembled into the caller's existing cell mesh. The shared vertex normals and
## interpolated colour field remove the hard band-to-band facets without another material or draw.
static func _leaf_mass(k: MeshKit, center: Vector3, size: Vector3, base: Color, light: Color, dark: Color,
		seed: int, segments: int, bands: int, yaw := 0.0, jitter := 0.05, flat_bottom := 0.0, lobing := 0.0) -> void:
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var rotation := Basis(Vector3.UP, yaw)
	var phase := TAU * Palette.hash01(seed, 72)
	var lobe_count := 2 + posmod(seed, 3)
	for band in bands + 1:
		var phi := -PI * 0.5 + PI * float(band) / float(bands)
		var vertical := sin(phi) * 0.5
		if flat_bottom > 0.0:
			vertical = maxf(vertical, -0.5 + flat_bottom)
		var radius := cos(phi)
		var ring := PackedVector3Array()
		var normal_ring := PackedVector3Array()
		for point in segments:
			var a := TAU * (float(point) + 0.5 * float(band % 2)) / float(segments)
			a += TAU * Palette.hash01(seed, 71)
			var broad_wave := 0.62 * sin(float(lobe_count) * a + phase) \
				+ 0.38 * sin(float(lobe_count + 2) * a - phase * 0.7)
			var radial := 1.0
			if band > 0 and band < bands:
				radial = 1.0 - jitter + jitter * 2.0 * Palette.hash01(seed + 31, band * 97 + point * 13 + 7)
			radial *= 1.0 + lobing * broad_wave
			var wave_height := lobing * 0.18 * broad_wave * radius
			var local := Vector3(cos(a) * radius * radial * size.x * 0.5,
				vertical * size.y + wave_height * size.y, sin(a) * radius * radial * size.z * 0.5)
			ring.append(center + rotation * local)
			normal_ring.append(Vector3.ZERO)
		rings.append(ring)
		normals.append(normal_ring)
	# Derive interpolated normals from the actual lobed surface instead of the undeformed ellipsoid.
	# This keeps light and vertex-colour gradients aligned on the crown's flatter shoulders.
	for band in bands + 1:
		var lower_band: int = maxi(band - 1, 0)
		var upper_band: int = mini(band + 1, bands)
		var ring: PackedVector3Array = rings[band]
		for point in segments:
			var previous: int = posmod(point - 1, segments)
			var following: int = (point + 1) % segments
			var tangent_band: Vector3 = rings[upper_band][point] - rings[lower_band][point]
			var tangent_angle: Vector3 = ring[following] - ring[previous]
			var normal := tangent_band.cross(tangent_angle)
			var outward := ring[point] - center
			if normal.length_squared() < 1e-10:
				normal = rotation * (Vector3.UP if band == bands else Vector3.DOWN)
			elif normal.dot(outward) < 0.0:
				normal = -normal
			if flat_bottom > 0.0 and band == 0:
				normal = rotation * Vector3.DOWN
			normals[band][point] = normal.normalized()
	for band in bands:
		var low: PackedVector3Array = rings[band]
		var high: PackedVector3Array = rings[band + 1]
		var low_normals: PackedVector3Array = normals[band]
		var high_normals: PackedVector3Array = normals[band + 1]
		for point in segments:
			var next := (point + 1) % segments
			if band == 0:
				_smooth_triangle(k, low[point], high[point], high[next], low_normals[point], high_normals[point], high_normals[next], base, light, dark)
			elif band == bands - 1:
				_smooth_triangle(k, low[point], high[point], low[next], low_normals[point], high_normals[point], low_normals[next], base, light, dark)
			else:
				_smooth_triangle(k, low[point], high[point], high[next], low_normals[point], high_normals[point], high_normals[next], base, light, dark)
				_smooth_triangle(k, low[point], high[next], low[next], low_normals[point], high_normals[next], low_normals[next], base, light, dark)


static func _smooth_triangle(k: MeshKit, a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3,
		normal_b: Vector3, normal_c: Vector3, base: Color, light: Color, dark: Color) -> void:
	var start := k.verts.size()
	k.tri(a, b, c, base)
	if k.verts.size() != start + 3:
		return
	var normal_xf: Basis = k.xf.basis.inverse().transposed()
	var ordered_normals: Array[Vector3] = [normal_a, normal_c, normal_b]
	if k.xf.basis.determinant() < 0.0:
		ordered_normals = [normal_a, normal_b, normal_c]
	for i in 3:
		var normal: Vector3 = (normal_xf * ordered_normals[i]).normalized()
		k.norms[start + i] = normal
		k.cols[start + i] = _leaf_colour(base, light, dark, normal)


static func _leaf_colour(base: Color, light: Color, dark: Color, normal: Vector3) -> Color:
	var colour := base.lerp(dark, maxf(0.0, -normal.y) * 0.16)
	colour = colour.lerp(light, maxf(0.0, normal.y) * 0.13)
	var directional := normal.dot(LEAF_LIGHT)
	if directional > 0.0:
		colour = colour.lerp(light, directional * 0.14)
	else:
		colour = colour.lerp(dark, -directional * 0.10)
	return colour
