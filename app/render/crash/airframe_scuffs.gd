# US-V12: scuffs on the airframe where a soft hull contact touched the field and the flight went on (E3d1): grass
# stain on mown turf, soil on rough ground, abraded film on the runway. Compatibility has no Decal node, so each scuff
# is a small transparent mesh fitted onto the struck surface. A ray from below the contact finds the lowest visible
# airframe surface above it; a grid of points along the slide is projected onto the nearby airframe triangles (a
# scuff may straddle two wing panels). The scuff is a child of the struck mesh, so it moves with hinged surfaces. Presentation only; cleared on restart.
extends RefCounted

const MAX_SCUFFS := 24
## The ray starts this far below the contact and reaches this far above it (m).
const RAY_BELOW_M := 0.04
const RAY_REACH_M := 0.16
## A contact past the airframe's edge (a hull point on a rounded tip) retries this much closer to the centre (m).
const RETRY_INWARD_M: Array[float] = [0.0, 0.015, 0.03, 0.05]
## Lift off the surface against depth fighting (m), and the grid laid over it.
const LIFT_M := 0.0006
const GRID_U := 6
const GRID_V := 3
const SCUFF_META := "airframe_scuff"
## Geometry3D's fixed epsilon is too coarse in metres; intersections run in millimetres.
const MM := 1000.0
## Field surface (render/crash/director.gd surface_at) → stain colour; estimates.
const COLORS := {
	"mown": Color(0.25, 0.33, 0.12),
	"rough": Color(0.33, 0.27, 0.17),
	"runway": Color(0.72, 0.71, 0.68),
}
## Ancestors whose meshes are not airframe skin.
const SKIP_PARTS: Array[String] = ["propeller", "gear", "wheel"]

var marks: Array[MeshInstance3D] = []
var _serial := 0
static var _texture: ImageTexture
static var _materials: Dictionary = {}


## Marks the airframe under `root` where a contact touched at world `point`, sliding with world `velocity`, with
## `strength` 0..1 on `surface`. Returns the scuff, or null when no airframe surface lies over the contact.
func add(root: Node3D, point: Vector3, velocity: Vector3, strength: float, surface: String) -> MeshInstance3D:
	var candidates := _candidates(root)
	var hit := _surface_hit(candidates, root, point)
	if hit.is_empty():
		return null
	var node: MeshInstance3D = hit.node
	var n: Vector3 = hit.normal
	var level := clampf(strength, 0.0, 1.0)
	var slide := Vector3(velocity.x, 0.0, velocity.z)
	var along := slide - n * slide.dot(n)
	if along.length() < 0.2:
		along = node.global_basis.z - n * node.global_basis.z.dot(n)
	along = along.normalized()
	var across := n.cross(along).normalized()
	var length := clampf(0.035 + 0.09 * level + 0.004 * slide.length(), 0.035, 0.18)
	var width := 0.022 + 0.03 * level
	var nearby := _nearby_triangles(candidates, hit.point, 0.6 * length + width)
	var to_local := node.global_transform.affine_inverse()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var local_normal := (to_local.basis * n).normalized()
	for j in GRID_V:
		for i in GRID_U:
			var u := float(i) / (GRID_U - 1)
			var v := float(j) / (GRID_V - 1)
			var p: Vector3 = hit.point + along * (u - 0.5) * length + across * (v - 0.5) * width
			p = _onto_skin(nearby, p, hit.point, n) + n * LIFT_M
			vertices.append(to_local * p)
			normals.append(local_normal)
			uvs.append(Vector2(u, v))
	var indices := PackedInt32Array()
	for j in GRID_V - 1:
		for i in GRID_U - 1:
			var a := j * GRID_U + i
			var b := a + 1
			var c := a + GRID_U
			var d := c + 1
			# Front faces wind clockwise seen from the outward normal (Godot).
			var flip := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(local_normal) > 0.0
			indices.append_array([a, c, b, b, c, d] if flip else [a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var scuff := MeshInstance3D.new()
	scuff.name = "airframe_scuff_%d" % _serial
	_serial += 1
	scuff.mesh = mesh
	scuff.material_override = material(surface)
	scuff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scuff.set_meta(SCUFF_META, surface)
	node.add_child(scuff)
	marks.append(scuff)
	if marks.size() > MAX_SCUFFS:
		var oldest: MeshInstance3D = marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	return scuff


## Removes every scuff (restart).
func clear() -> void:
	for scuff in marks:
		if is_instance_valid(scuff):
			scuff.get_parent().remove_child(scuff)
			scuff.free()
	marks.clear()


## The lowest visible airframe surface over world `point`: {node, point, normal (world, facing the ground)} or {}.
static func surface_hit(root: Node3D, point: Vector3) -> Dictionary:
	return _surface_hit(_candidates(root), root, point)


## Visible airframe-skin meshes under `root`.
static func _candidates(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and _airframe(mi, root):
			out.append(mi)
	return out


static func _surface_hit(candidates: Array[MeshInstance3D], root: Node3D, point: Vector3) -> Dictionary:
	var inward := root.global_position - point
	inward.y = 0.0
	inward = inward.normalized() if inward.length() > 1e-6 else Vector3.ZERO
	for shift in RETRY_INWARD_M:
		var base := point + inward * shift
		var hit := _ray_up(candidates, base + Vector3.DOWN * RAY_BELOW_M, base + Vector3.UP * RAY_REACH_M)
		if not hit.is_empty():
			return hit
	return {}


static func _airframe(mi: MeshInstance3D, root: Node3D) -> bool:
	if mi.has_meta(SCUFF_META) or mi.has_meta("crash_no_bounds") \
			or (mi.material_override is BaseMaterial3D and (mi.material_override as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
		return false
	var cursor: Node = mi
	while cursor != null and cursor != root:
		var label := String(cursor.name).to_lower()
		for part in SKIP_PARTS:
			if label.contains(part):
				return false
		cursor = cursor.get_parent()
	return true


static func _ray_up(candidates: Array[MeshInstance3D], from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for mi in candidates:
		var inv := mi.global_transform.affine_inverse()
		var a := inv * from
		var b := inv * to
		var box := mi.get_aabb().grow(0.002)
		if not (box.has_point(a) or box.has_point(b) or box.intersects_segment(a, b) != null):
			continue
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var p: Variant = Geometry3D.segment_intersects_triangle(a * MM, b * MM, faces[i] * MM, faces[i + 1] * MM, faces[i + 2] * MM)
			if p == null:
				continue
			var world: Vector3 = mi.global_transform * ((p as Vector3) / MM)
			var t := world.distance_to(from)
			if t >= best_t:
				continue
			var normal: Vector3 = (mi.global_basis * (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])).normalized()
			if normal.dot(from - world) < 0.0:
				normal = -normal
			best_t = t
			best = {node = mi, point = world, normal = normal}
	return best


## Airframe triangles (world) whose bounding box comes within `radius` of world `center` (a large panel triangle can
## hold the centre with every corner far away).
static func _nearby_triangles(candidates: Array[MeshInstance3D], center: Vector3, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for node in candidates:
		var t := node.global_transform
		if not (t * node.get_aabb()).grow(radius).has_point(center):
			continue
		var faces := node.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := t * faces[i]
			var b := t * faces[i + 1]
			var c := t * faces[i + 2]
			if AABB(a, Vector3.ZERO).expand(b).expand(c).grow(radius).has_point(center):
				out.append_array([a, b, c])
	return out


## `p` on the skin: projected along `n`; a point past the skin's edge (ahead of a leading edge, beyond a tip) moves
## halfway toward `center` until it lands, so the scuff narrows at an edge instead of floating past it.
static func _onto_skin(triangles: PackedVector3Array, p: Vector3, center: Vector3, n: Vector3) -> Vector3:
	var q := p
	for attempt in 6:
		var hit: Variant = _project(triangles, q, n)
		if hit != null:
			return hit
		q = q.lerp(center, 0.5)
	return center


## `p` moved along `n` onto the nearest of `triangles` (world), or null where no triangle lies within 3 cm.
static func _project(triangles: PackedVector3Array, p: Vector3, n: Vector3) -> Variant:
	var from := (p + n * 0.03) * MM
	var to := (p - n * 0.03) * MM
	var best: Variant = null
	var best_t := INF
	for i in range(0, triangles.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, triangles[i] * MM, triangles[i + 1] * MM, triangles[i + 2] * MM)
		if hit == null:
			continue
		var t := (hit as Vector3).distance_to(from)
		if t < best_t:
			best_t = t
			best = (hit as Vector3) / MM
	return best


static func material(surface: String) -> StandardMaterial3D:
	var key := surface if COLORS.has(surface) else "rough"
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.resource_name = "airframe-scuff-" + key
	mat.albedo_color = COLORS[key]
	mat.albedo_texture = texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.95
	mat.metallic_specular = 0.2
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = mat
	return mat


## White streaked blot: alpha fades toward an elliptic edge, streaks run along U (the slide), and the stain thins
## toward the end where the contact left the ground.
static func texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var w := 128
	var h := 48
	var image := Image.create(w, h, true, Image.FORMAT_RGBA8)
	for y in h:
		var v := (y + 0.5) / h * 2.0 - 1.0
		var streak := 0.45 + 0.55 * _hash(y, 7)
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var edge := 1.0 - smoothstep(0.45, 1.0, sqrt(u * u + v * v))
			var thin := lerpf(1.0, 0.4, (u + 1.0) * 0.5)
			var grain := 0.7 + 0.3 * _hash(x, y)
			image.set_pixel(x, y, Color(1, 1, 1, clampf(0.9 * edge * streak * thin * grain, 0.0, 1.0)))
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h ^ (h >> 16)) / float(0x7fffffff)
