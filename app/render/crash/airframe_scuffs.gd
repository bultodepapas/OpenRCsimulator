# US-V12: scuffs on the airframe where a soft hull contact touched the field and the flight went on (E3d1): grass
# stain on mown turf, soil on rough ground, abraded film on the runway. Compatibility has no Decal node, so each scuff
# is a small transparent mesh fitted onto the struck surface. A ray from below the contact finds the lowest visible
# airframe surface above it; a grid of points along the slide is projected onto the nearby airframe triangles (a
# scuff may straddle two wing panels). The scuff is a child of the struck mesh, so it moves with hinged surfaces. Presentation only; cleared on restart.
# CR-22c-R1: prepared local-space BVHs keep triangle scans out of the contact frame.
extends RefCounted

const MAX_SCUFFS := 24
## The ray starts this far below the contact and reaches this far above it (m).
const RAY_BELOW_M := 0.04
const RAY_REACH_M := 0.16
## A contact past the airframe's edge retries this much closer to the centre (m).
const RETRY_INWARD_M: Array[float] = [0.0, 0.015, 0.03, 0.05]
## Lift off the surface against depth fighting (m), and the grid laid over it.
const LIFT_M := 0.0006
const GRID_U := 6
const GRID_V := 3
const SCUFF_META := "airframe_scuff"
## TriangleMesh snaps vertices at 0.0001 of its input units; millimetres keep that well below a micrometre here.
const MM := 1000.0
## Field surface (render/crash/director.gd surface_at) → stain colour; estimates.
const COLORS := {
	"mown": Color(0.25, 0.33, 0.12),
	"rough": Color(0.33, 0.27, 0.17),
	"runway": Color(0.72, 0.71, 0.68),
}
## Ancestors whose meshes are not airframe skin.
const SKIP_PARTS: Array[String] = ["propeller", "gear", "wheel"]
## A mesh carrying this meta (true) is never scuffed: bare engines and other hardware that is not covering or paint.
## US-V13: the Stik's imported O.S. 61 (about 140k triangles) would otherwise dominate the BVH preparation.
const SKIP_META := "airframe_scuff_skip"

var marks: Array[MeshInstance3D] = []
var _serial := 0
## Resource identity is the key: aircraft panels can share a mesh while keeping independent live transforms.
var _bvh_by_mesh: Dictionary = {}
## Watchers bind only an ObjectID, avoiding a Resource -> Callable -> same Resource reference cycle.
var _mesh_watchers: Dictionary = {}
var _prepared_root_id := 0
static var _texture: ImageTexture
static var _materials: Dictionary = {}


## Prepare only eligible meshes owned by this selected aircraft. Hidden panels are included in the cache so a later
## visibility change is reflected immediately by add()/surface_hit() without rebuilding their BVHs in flight.
func prepare(root: Node3D) -> void:
	_disconnect_all_mesh_watchers()
	_bvh_by_mesh.clear()
	_prepared_root_id = root.get_instance_id() if is_instance_valid(root) else 0
	if not is_instance_valid(root):
		return
	# Generate the procedural texture before the first soft contact.
	material("mown")
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null or not _airframe(mi, root):
			continue
		_cache_mesh(mi.mesh)


## Marks the airframe under `root` where a contact touched at world `point`, sliding with world `velocity`, with
## `strength` 0..1 on `surface`. Returns the scuff, or null when no airframe surface lies over the contact.
func add(root: Node3D, point: Vector3, velocity: Vector3, strength: float, surface: String) -> MeshInstance3D:
	if not is_instance_valid(root):
		return null
	if _prepared_root_id != root.get_instance_id():
		prepare(root)
	var candidates := _candidate_entries(root, _bvh_by_mesh, self)
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
	# Keep the old nearby-panel broadphase, but retain candidates instead of materializing every nearby triangle.
	var radius := 0.6 * length + width
	var nearby: Array[Dictionary] = []
	for candidate in candidates:
		if candidate.world_aabb.grow(radius).has_point(hit.point):
			nearby.append(candidate)
	var to_local: Transform3D = hit.inverse
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
	var mark_mesh := ArrayMesh.new()
	mark_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var scuff := MeshInstance3D.new()
	scuff.name = "airframe_scuff_%d" % _serial
	_serial += 1
	scuff.mesh = mark_mesh
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


## Removes every scuff (restart). Prepared mesh BVHs intentionally survive this operation.
func clear() -> void:
	for scuff in marks:
		if is_instance_valid(scuff):
			scuff.get_parent().remove_child(scuff)
			scuff.free()
	marks.clear()


## The lowest visible airframe surface over world `point`: {node, point, normal (world, facing the ground)} or {}.
## This compatibility entry point uses a short-lived cache; the runtime instance uses prepare() and retains its cache.
static func surface_hit(root: Node3D, point: Vector3) -> Dictionary:
	if not is_instance_valid(root):
		return {}
	var temporary_cache: Dictionary = {}
	var candidates := _candidate_entries(root, temporary_cache)
	var hit := _surface_hit(candidates, root, point)
	if hit.is_empty():
		return {}
	# Keep the original public result shape; the cached inverse is an add() implementation detail.
	return {"node": hit.node, "point": hit.point, "normal": hit.normal}


func _cache_mesh(mesh: Mesh) -> TriangleMesh:
	if _bvh_by_mesh.has(mesh):
		return _bvh_by_mesh[mesh] as TriangleMesh
	var bvh := _build_bvh(mesh)
	if bvh != null:
		_bvh_by_mesh[mesh] = bvh
		_watch_mesh(mesh)
	return bvh


func _watch_mesh(mesh: Mesh) -> void:
	var mesh_id := mesh.get_instance_id()
	if _mesh_watchers.has(mesh_id):
		return
	var callback := Callable(self, "_on_mesh_changed").bind(mesh_id)
	mesh.changed.connect(callback)
	_mesh_watchers[mesh_id] = {"mesh": mesh, "callback": callback}


func _on_mesh_changed(mesh_id: int) -> void:
	var watch: Dictionary = _mesh_watchers.get(mesh_id, {})
	var mesh: Mesh = watch.get("mesh") as Mesh
	if mesh != null:
		# Rebuilt lazily on the next query, before a stale BVH can be used.
		_bvh_by_mesh.erase(mesh)


func _disconnect_all_mesh_watchers() -> void:
	for mesh_id in _mesh_watchers.keys():
		_disconnect_mesh_watcher(int(mesh_id))
	_mesh_watchers.clear()


func _disconnect_mesh_watcher(mesh_id: int) -> void:
	var watch: Dictionary = _mesh_watchers.get(mesh_id, {})
	var mesh: Mesh = watch.get("mesh") as Mesh
	var callback: Callable = watch.get("callback", Callable())
	if mesh != null and callback.is_valid() and mesh.changed.is_connected(callback):
		mesh.changed.disconnect(callback)
	_mesh_watchers.erase(mesh_id)


func _prune_mesh_cache(present: Dictionary) -> void:
	for mesh_id in _mesh_watchers.keys():
		var watch: Dictionary = _mesh_watchers[mesh_id]
		var mesh: Mesh = watch.mesh as Mesh
		if mesh == null or not present.has(mesh):
			if mesh != null:
				_bvh_by_mesh.erase(mesh)
			_disconnect_mesh_watcher(int(mesh_id))


## Visible candidate transforms are sampled once per add(), then reused across all 18 grid-point casts.
## `cache_owner` is null for the static compatibility API and the scuff instance for runtime cache/watch management.
static func _candidate_entries(root: Node3D, cache: Dictionary, cache_owner: Object = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var present: Dictionary = {}
	for item in root.find_children("*", "MeshInstance3D", true, false):
		var mi := item as MeshInstance3D
		if mi.mesh == null or not _airframe(mi, root):
			continue
		present[mi.mesh] = true
		if not mi.is_visible_in_tree():
			continue
		var bvh := cache.get(mi.mesh) as TriangleMesh
		if bvh == null:
			bvh = _build_bvh(mi.mesh)
			if bvh != null:
				cache[mi.mesh] = bvh
				if cache_owner != null:
					cache_owner.call("_watch_mesh", mi.mesh)
		if bvh == null:
			continue
		var transform := mi.global_transform
		var local_aabb := mi.get_aabb()
		out.append({
			"node": mi,
			"bvh": bvh,
			"transform": transform,
			"inverse": transform.affine_inverse(),
			"basis": transform.basis,
			"local_aabb": local_aabb,
			"world_aabb": transform * local_aabb,
		})
	if cache_owner != null:
		cache_owner.call("_prune_mesh_cache", present)
	return out


static func _build_bvh(mesh: Mesh) -> TriangleMesh:
	var faces := mesh.get_faces()
	if faces.is_empty():
		return null
	for i in faces.size():
		faces[i] = faces[i] * MM
	var bvh := TriangleMesh.new()
	return bvh if bvh.create_from_faces(faces) else null


static func _surface_hit(candidates: Array[Dictionary], root: Node3D, point: Vector3) -> Dictionary:
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
	if mi.has_meta(SCUFF_META) or mi.has_meta("crash_no_bounds") or mi.get_meta(SKIP_META, false) \
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


static func _ray_up(candidates: Array[Dictionary], from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for candidate in candidates:
		var inverse: Transform3D = candidate.inverse
		var a: Vector3 = inverse * from
		var b: Vector3 = inverse * to
		var box: AABB = candidate.local_aabb.grow(0.002)
		if not (box.has_point(a) or box.has_point(b) or box.intersects_segment(a, b) != null):
			continue
		var result: Dictionary = (candidate.bvh as TriangleMesh).intersect_segment(a * MM, b * MM)
		if result.is_empty():
			continue
		var world: Vector3 = candidate.transform * ((result.position as Vector3) / MM)
		var t := world.distance_to(from)
		if t >= best_t:
			continue
		var normal: Vector3 = (candidate.basis * (result.normal as Vector3)).normalized()
		if normal.dot(from - world) < 0.0:
			normal = -normal
		best_t = t
		best = {
			"node": candidate.node,
			"point": world,
			"normal": normal,
			"inverse": candidate.inverse,
		}
	return best


## `p` on the skin: project along `n`; if a point passes a panel edge, move halfway toward the centre until it lands.
static func _onto_skin(candidates: Array[Dictionary], p: Vector3, center: Vector3, n: Vector3) -> Vector3:
	var q := p
	for attempt in 6:
		var hit := _project(candidates, q, n)
		if not hit.is_empty():
			return hit.point
		q = q.lerp(center, 0.5)
	return center


## Cast the same finite skin projection as before. TriangleMesh returns the nearest hit along each candidate segment;
## compare those hits in world space to preserve nearest-panel selection across independent live transforms.
static func _project(candidates: Array[Dictionary], p: Vector3, n: Vector3) -> Dictionary:
	return _cast_segment(candidates, p + n * 0.03, p - n * 0.03)


static func _cast_segment(candidates: Array[Dictionary], from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var best_t := INF
	for candidate in candidates:
		var inverse: Transform3D = candidate.inverse
		var a: Vector3 = inverse * from
		var b: Vector3 = inverse * to
		var box: AABB = candidate.local_aabb
		if not (box.has_point(a) or box.has_point(b) or box.intersects_segment(a, b) != null):
			continue
		var result: Dictionary = (candidate.bvh as TriangleMesh).intersect_segment(a * MM, b * MM)
		if result.is_empty():
			continue
		var world: Vector3 = candidate.transform * ((result.position as Vector3) / MM)
		var t := world.distance_to(from)
		if t >= best_t:
			continue
		var normal: Vector3 = (candidate.basis * (result.normal as Vector3)).normalized()
		if normal.dot(from - world) < 0.0:
			normal = -normal
		best_t = t
		best = {"node": candidate.node, "point": world, "normal": normal}
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
