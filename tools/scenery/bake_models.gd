## SCENERY-PLAN SC-04: converts the few third-party CC0 models the scenery uses into `openrc-scenery-model v1` JSON under
## app/data/scenery/models/ (indexed millimetre integers + a colour palette: deterministic, diffable, exported with the
## data filter, no editor import). Run headless with the app as the project:
##   godot --headless --path app --script <repo>/tools/scenery/bake_models.gd -- --src=<downloads> [--check]
## <downloads> must hold the archives listed in SOURCES with matching SHA-256 (assets/scenery/PROVENANCE.json).
## Steps per model: load (FBX/GLB runtime importers) → skinned meshes posed at their skeleton rest → material colours to
## triangle colours (paint marked with alpha 0) → front turned to −Z by the headlights/heading rule → base on y = 0,
## centred → uniform scale to the catalog length (+ per-model height factor) → flat triangles, mm integers.
extends SceneTree

const Models = preload("res://scenery/models.gd")

var _src := ""
var _check := false
var _failures := 0


func _initialize() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--src="):
			_src = raw.trim_prefix("--src=")
		elif raw == "--check":
			_check = true
	if _src.is_empty():
		printerr("usage: -- --src=<downloads folder> [--check]")
		quit(2)
		return
	var tmp := OS.get_cache_dir().path_join("openrc-scenery-bake")
	DirAccess.make_dir_recursive_absolute(tmp)
	for id: String in Models.CATALOG:
		var spec: Dictionary = Models.CATALOG[id]
		if spec.get("kind", "") == "fleet":
			continue # baked by bake_fleet.gd
		var path := _source_file(spec, tmp)
		if path.is_empty():
			_failures += 1
			continue
		var model := _bake(id, spec, path)
		if model.is_empty():
			_failures += 1
			continue
		var out_path := "res://data/scenery/models/%s.json" % id
		var text := JSON.stringify(model, "", false) + "\n"
		if _check:
			var current := FileAccess.get_file_as_string(out_path)
			if current != text:
				printerr("FAIL %s differs from a fresh bake" % out_path)
				_failures += 1
			else:
				print("ok   %s matches a fresh bake" % out_path)
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/scenery/models"))
			var f := FileAccess.open(out_path, FileAccess.WRITE)
			f.store_string(text)
			f.close()
			print("wrote %s: %d triangles, size %s m" % [out_path, model.triangles.size() / 4, model.size_m])
	quit(1 if _failures > 0 else 0)


func _sha256(path: String) -> String:
	return FileAccess.get_sha256(path)


## Unpacks (zip entries) or copies the source into the temp folder after checking the archive's SHA-256.
func _source_file(spec: Dictionary, tmp: String) -> String:
	var archive := _src.path_join(str(spec.archive))
	if not FileAccess.file_exists(archive):
		printerr("FAIL missing download %s" % archive)
		return ""
	var sha := _sha256(archive)
	if sha != str(spec.archive_sha256):
		printerr("FAIL %s SHA-256 %s, expected %s" % [archive, sha, spec.archive_sha256])
		return ""
	if str(spec.entry).is_empty():
		return archive
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		printerr("FAIL cannot open %s" % archive)
		return ""
	var bytes := zip.read_file(str(spec.entry))
	zip.close()
	if bytes.is_empty():
		printerr("FAIL %s has no entry %s" % [archive, spec.entry])
		return ""
	var out := tmp.path_join(str(spec.entry).get_file())
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return out


func _bake(id: String, spec: Dictionary, path: String) -> Dictionary:
	var fbx := path.get_extension().to_lower() == "fbx"
	var doc: GLTFDocument = FBXDocument.new() if fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if fbx else GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		printerr("FAIL cannot import %s" % path)
		return {}
	var scene := doc.generate_scene(state)
	var tris: Array = [] # [Vector3 a, b, c, Color, is_paint]
	_collect(scene, scene, Transform3D.IDENTITY, tris, str(spec.get("paint_material", "")))
	scene.free()
	if tris.is_empty():
		printerr("FAIL %s: no triangles" % id)
		return {}
	# Orientation: lay the longest horizontal axis along Z, put the front at −Z.
	var box := _bounds(tris)
	var turn := Basis.IDENTITY
	if box.size.x > box.size.z:
		turn = Basis(Vector3.UP, PI / 2.0)
	tris = _transform(tris, Transform3D(turn, Vector3.ZERO))
	var front_z := _front_z(tris, spec)
	if front_z > 0.0:
		tris = _transform(tris, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	box = _bounds(tris)
	var target: Vector3 = spec.size
	var k := target.z / box.size.z
	var ky := k * float(spec.get("height_factor", 1.0))
	var centre := box.get_center()
	tris = _transform(tris, Transform3D(Basis.from_scale(Vector3(k, ky, k)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(-centre.x, -box.position.y, -centre.z)))
	box = _bounds(tris)
	tris = _reduce(tris, int(spec.get("max_tris", 0)))
	# Index and quantise.
	var palette: Array[String] = []
	var positions: Array[int] = []
	var vindex := {}
	var triangles: Array[int] = []
	for t: Array in tris:
		var c: Color = t[3]
		var key := Color(c.r, c.g, c.b, 0.0 if t[4] else 1.0).to_html(true)
		var pi := palette.find(key)
		if pi < 0:
			palette.append(key)
			pi = palette.size() - 1
		var ids: Array[int] = []
		for j in 3:
			var p: Vector3 = t[j]
			var q := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
			if not vindex.has(q):
				vindex[q] = positions.size() / 3
				positions.append_array([q.x, q.y, q.z])
			ids.append(vindex[q])
		if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
			continue
		var qa := Vector3(positions[ids[0] * 3], positions[ids[0] * 3 + 1], positions[ids[0] * 3 + 2])
		var qb := Vector3(positions[ids[1] * 3], positions[ids[1] * 3 + 1], positions[ids[1] * 3 + 2])
		var qc := Vector3(positions[ids[2] * 3], positions[ids[2] * 3 + 1], positions[ids[2] * 3 + 2])
		if (qb - qa).cross(qc - qa).length() < 2.0: # < 1 mm²: a sliver left by quantising or reducing
			continue
		triangles.append_array([ids[0], ids[1], ids[2], pi])
	return {
		format = Models.FORMAT, id = id,
		source = {url = spec.url, archive = spec.archive, archive_sha256 = spec.archive_sha256, entry = spec.entry,
			author = spec.author, license = spec.license, license_evidence = spec.license_evidence},
		transform = "front −Z, centred, base on y = 0; uniform scale to %.2f m long, height factor %.2f" % [target.z, float(spec.get("height_factor", 1.0))],
		size_m = [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)],
		palette = palette, positions_mm = positions, triangles = triangles,
	}


## Collects world-space triangles. Skinned meshes are posed at the skeleton rest (bind → rest), so a rig whose bind space
## is rotated (the sheep) comes out standing.
func _collect(node: Node, scene: Node, parent_xf: Transform3D, tris: Array, paint_material: String) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var skeleton: Skeleton3D = null
		if mi.skin and not mi.skeleton.is_empty():
			skeleton = mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skel_xf := Transform3D.IDENTITY
		if skeleton:
			skel_xf = _global_xf(skeleton)
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			var col := mat.albedo_color if mat else Color(0.8, 0.8, 0.8)
			var is_paint := mat != null and paint_material != "" and mat.resource_name == paint_material and node.name == scene.name
			if mat and paint_material == "*body" and s == 0 and not str(node.name).contains("Wheel"):
				is_paint = true
			var a := mi.mesh.surface_get_arrays(s)
			var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			if skeleton and a[Mesh.ARRAY_BONES] != null:
				pos = _skin_rest(pos, a[Mesh.ARRAY_BONES], a[Mesh.ARRAY_WEIGHTS], mi.skin, skeleton, skel_xf)
			else:
				pos = xf * pos
			var idx: Variant = a[Mesh.ARRAY_INDEX]
			var order: PackedInt32Array = idx if idx != null else PackedInt32Array(range(pos.size()))
			for i in range(0, order.size(), 3):
				tris.append([pos[order[i]], pos[order[i + 1]], pos[order[i + 2]], col, is_paint])
	for c in node.get_children():
		_collect(c, scene, xf, tris, paint_material)


func _global_xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur := n
	while cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _skin_rest(pos: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, skin: Skin, skeleton: Skeleton3D, skel_xf: Transform3D) -> PackedVector3Array:
	var per := bones.size() / pos.size()
	var mats: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(b))
		mats.append(skel_xf * skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(b))
	var out := PackedVector3Array()
	out.resize(pos.size())
	for v in pos.size():
		var acc := Vector3.ZERO
		var wsum := 0.0
		for j in per:
			var w := weights[v * per + j]
			if w > 0.0:
				acc += (mats[bones[v * per + j]] * pos[v]) * w
				wsum += w
		out[v] = acc / wsum if wsum > 0.0 else skel_xf * pos[v]
	return out


## Reduces a triangle soup to about `target` triangles with Godot's LOD generator (meshoptimizer), one surface per
## colour so colour borders survive. 0 keeps everything.
func _reduce(tris: Array, target: int) -> Array:
	if target <= 0 or tris.size() <= target:
		return tris
	var by_color := {}
	for t: Array in tris:
		var key := "%s|%s" % [(t[3] as Color).to_html(true), t[4]]
		if not by_color.has(key):
			by_color[key] = []
		(by_color[key] as Array).append(t)
	var mesh := ArrayMesh.new()
	var keys := by_color.keys()
	keys.sort()
	for key: String in keys:
		var list: Array = by_color[key]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for t: Array in list:
			for j in 3:
				st.add_vertex(t[j])
		st.index()
		st.generate_normals()
		st.commit(mesh)
	var im := ImporterMesh.from_mesh(mesh)
	im.generate_lods(25.0, 60.0, [])
	var ratio := float(target) / tris.size()
	var out: Array = []
	for s in im.get_surface_count():
		var arrays := im.get_surface_arrays(s)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var want := int(idx.size() * ratio)
		var best := absi(idx.size() - want)
		for l in im.get_surface_lod_count(s): # the LOD closest to the share of triangles we want
			var lod := im.get_surface_lod_indices(s, l)
			if lod.size() >= 12 and absi(lod.size() - want) < best:
				best = absi(lod.size() - want)
				idx = lod
		var first: Array = by_color[keys[s]][0]
		for t in range(0, idx.size(), 3):
			out.append([pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]], first[3], first[4]])
	return out


func _bounds(tris: Array) -> AABB:
	var box := AABB(tris[0][0], Vector3.ZERO)
	for t: Array in tris:
		for j in 3:
			box = box.expand(t[j])
	return box


func _transform(tris: Array, t: Transform3D) -> Array:
	var flip := t.basis.determinant() < 0.0
	var out: Array = []
	for tri: Array in tris:
		if flip:
			out.append([t * tri[0], t * tri[2], t * tri[1], tri[3], tri[4]])
		else:
			out.append([t * tri[0], t * tri[1], t * tri[2], tri[3], tri[4]])
	return out


## Which end is the front: cars by their headlight colour (#d1955a), animals by the heavier half (the head and neck).
func _front_z(tris: Array, spec: Dictionary) -> float:
	var front_color := str(spec.get("front_color", ""))
	var sum := 0.0
	var n := 0
	for t: Array in tris:
		var c: Color = t[3]
		if not front_color.is_empty() and c.to_html(false) == front_color:
			sum += (t[0].z + t[1].z + t[2].z) / 3.0
			n += 1
	if n > 0:
		return sum / n
	var box := _bounds(tris)
	var top := 0.0
	var count := 0
	for t: Array in tris: # the head sits high at one end: the mean z of the top 15 % of vertices
		for j in 3:
			var p: Vector3 = t[j]
			if p.y > box.position.y + box.size.y * 0.85:
				top += p.z
				count += 1
	return top / maxf(count, 1)
