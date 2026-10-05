# Ground shadow (D7, L3): the main height cue in RC flying. A soft airplane silhouette projected onto the ground along
# a direction: straight down (the D7 pilot aid, reads height directly) or along the sun (L3: the real shadow's place,
# offset by height / tan(sun elevation)). A planar projected shadow, the classic low-end technique: one draw call, and
# none of Compatibility's problems with engine shadows (sRGB blending of the shadowed light, L3 log).
# Pure helpers (footprint, alpha, silhouette) + a MeshInstance3D to update each frame.
extends RefCounted

const Spec := preload("res://spec.gd")

const SIZE := 128 # silhouette texture, pixels
## Silhouette layout in the quad (u across the span, v from nose 0 to tail 1), from the model's proportions.
const WING_V := Vector2(0.22, 0.45)
const FUSELAGE_U := Vector2(0.46, 0.54)
const STAB := Rect2(0.30, 0.85, 0.40, 0.13)
## The wing's mid-chord sits at this v: the quad is shifted so it lies under the airplane's CG.
const WING_CENTER_V := 0.335


static func create(parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var quad := PlaneMesh.new() # 1 × 1 in the XZ plane; UV u along +X, v along +Z
	quad.size = Vector2(1, 1)
	m.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.6)
	mat.albedo_texture = ImageTexture.create_from_image(silhouette())
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## Ground transform of the shadow quad for an airplane with model basis `b` (nose −Z, right +X) at render
## position `pos`: the span and length axes projected onto the ground along `along` (a unit vector pointing up toward
## the light: Vector3.UP for the vertical pilot aid, the sun direction for the sun shadow), so banking narrows it.
static func footprint(b: Basis, pos: Vector3, span: float, length: float, along := Vector3.UP) -> Transform3D:
	var s := along.normalized()
	s.y = maxf(s.y, 0.05) # a sun on the horizon would cast an infinitely long shadow
	var h: float = Spec.SHADOW.height
	var right := b.x - s * (b.x.y / s.y)
	var aft := b.z - s * (b.z.y / s.y) # model +Z = toward the tail
	var center := pos - s * ((pos.y - h) / s.y)
	var aft_len := aft.length()
	if aft_len > 1e-6:
		center += aft / aft_len * (0.5 - WING_CENTER_V) * length * aft_len
	return Transform3D(Basis(right * span, Vector3.UP, aft * length), center)


## Shadow opacity at a height above ground (m): darkest low down, fading but never vanishing.
static func alpha(height: float) -> float:
	var k := clampf(height / Spec.SHADOW.fade_height, 0.0, 1.0)
	return lerpf(Spec.SHADOW.alpha_low, Spec.SHADOW.alpha_high, k)


## Span (x) and length (z) of a built airplane, from its meshes' bounding boxes in the root's frame.
static func model_extent(root: Node3D) -> Vector2:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := root.global_transform.affine_inverse() * mi.global_transform if mi.is_inside_tree() else _relative(root, mi)
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return Vector2(box.size.x, box.size.z)


static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func update(shadow: MeshInstance3D, b: Basis, pos: Vector3, span: float, length: float, along := Vector3.UP) -> void:
	shadow.transform = footprint(b, pos, span, length, along)
	(shadow.material_override as StandardMaterial3D).albedo_color.a = alpha(pos.y)


## White silhouette with soft edges in the alpha channel (deterministic; a 2-pass box blur).
static func silhouette() -> Image:
	var mask := PackedFloat32Array()
	mask.resize(SIZE * SIZE)
	for j in SIZE:
		var v := (j + 0.5) / SIZE
		for i in SIZE:
			var u := (i + 0.5) / SIZE
			var wing := v >= WING_V.x and v <= WING_V.y and u >= 0.02 and u <= 0.98
			var body := u >= FUSELAGE_U.x and u <= FUSELAGE_U.y and v >= 0.02 and v <= 0.98
			var stab := STAB.has_point(Vector2(u, v))
			mask[j * SIZE + i] = 1.0 if wing or body or stab else 0.0
	for _round in 2:
		mask = _blur(mask)
	var img := Image.create(SIZE, SIZE, true, Image.FORMAT_RGBA8)
	for j in SIZE:
		for i in SIZE:
			img.set_pixel(i, j, Color(1, 1, 1, mask[j * SIZE + i]))
	img.generate_mipmaps()
	return img


static func _blur(m: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(m.size())
	for j in SIZE:
		for i in SIZE:
			var acc := 0.0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					acc += m[clampi(j + dj, 0, SIZE - 1) * SIZE + clampi(i + di, 0, SIZE - 1)]
			out[j * SIZE + i] = acc / 9.0
	return out
