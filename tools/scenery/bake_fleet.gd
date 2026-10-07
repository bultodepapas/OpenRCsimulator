## SCENERY-PLAN SC-09: bakes the parked fleet. Building the four catalog aircraft through the model teams' builders at
## every field load cost ~550 ms, ~120 k triangles and 72 surfaces (SC-09 measurement), far over the scenery budget.
## This tool snapshots each aircraft read-only (app/scenery/fleet.gd), reduces it with Godot's own LOD generator
## (meshoptimizer) to about TARGET_TRIS, turns materials into triangle colours (flat albedo; texture sampled at the
## triangle's UV centre; the model teams' ShaderMaterials by their lightest colour parameter: white livery, aluminium)
## and writes `openrc-scenery-model v1` JSON next to the other models. Parked props are cosmetic: re-run after a model
## team changes a model.
##   godot --headless --path app --script <repo>/tools/scenery/bake_fleet.gd [-- --check]
extends SceneTree

const Fleet = preload("res://scenery/fleet.gd")
const Models = preload("res://scenery/models.gd")

const TARGET_TRIS := 2200

var _failures := 0


func _initialize() -> void:
	var check := OS.get_cmdline_user_args().has("--check")
	for model_id: String in Models.FLEET:
		var aircraft: String = Models.FLEET[model_id]
		var snap := Fleet.snapshot(aircraft)
		if snap.is_empty():
			_failures += 1
			continue
		var model := _bake(model_id, aircraft, snap.mesh)
		var path := "res://data/scenery/models/%s.json" % model_id
		var text := JSON.stringify(model, "", false) + "\n"
		if check:
			if FileAccess.get_file_as_string(path) != text:
				printerr("FAIL %s differs from a fresh bake (a model team changed the aircraft? re-run the bake)" % path)
				_failures += 1
			else:
				print("ok   %s matches a fresh bake" % path)
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		print("wrote %s: %d triangles, size %s m" % [path, model.triangles.size() / 4, model.size_m])
	quit(1 if _failures > 0 else 0)


func _color(mat: Material, uvs: Variant, i0: int, i1: int, i2: int) -> Color:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		var c := bm.albedo_color
		if bm.albedo_texture and uvs != null:
			var img := bm.albedo_texture.get_image()
			if img:
				if img.is_compressed():
					img.decompress()
				var uv: Vector2 = ((uvs as PackedVector2Array)[i0] + (uvs as PackedVector2Array)[i1] + (uvs as PackedVector2Array)[i2]) / 3.0
				var px := Vector2i(clampi(int(fposmod(uv.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
					clampi(int(fposmod(uv.y, 1.0) * img.get_height()), 0, img.get_height() - 1))
				c *= img.get_pixelv(px)
		return c
	if mat is ShaderMaterial:
		var best := Color(0.75, 0.75, 0.75)
		var best_l := -1.0
		for p: Dictionary in (mat as ShaderMaterial).get_property_list():
			var name := str(p.name)
			if name.begins_with("shader_parameter/") and p.type == TYPE_COLOR:
				var c: Color = (mat as ShaderMaterial).get(name)
				if c.get_luminance() > best_l:
					best_l = c.get_luminance()
					best = c
		return best
	return Color(0.75, 0.75, 0.75)


func _bake(model_id: String, aircraft: String, mesh: ArrayMesh) -> Dictionary:
	var total := 0
	for s in mesh.get_surface_count():
		total += mesh.surface_get_array_index_len(s) / 3 if mesh.surface_get_array_index_len(s) > 0 else mesh.surface_get_array_len(s) / 3
	var ratio := minf(1.0, float(TARGET_TRIS) / maxf(total, 1))
	# The merged snapshot is a plain triangle list; LOD generation needs shared vertices. Keep positions and UVs only
	# (flat normals are recomputed at load), index, then let meshoptimizer build the LOD chain.
	var indexed := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_arrays(s)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = src[Mesh.ARRAY_VERTEX]
		arr[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
		if src[Mesh.ARRAY_INDEX] != null:
			arr[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.index()
		st.generate_normals()
		st.commit(indexed)
		indexed.surface_set_material(indexed.get_surface_count() - 1, mesh.surface_get_material(s))
	var im := ImporterMesh.from_mesh(indexed)
	im.generate_lods(25.0, 60.0, [])
	var tris: Array = [] # [a, b, c, Color]
	for s in im.get_surface_count():
		var arrays := im.get_surface_arrays(s)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(pos.size()))
		var want := int(idx.size() * ratio)
		var best := absi(idx.size() - want)
		for l in im.get_surface_lod_count(s): # the LOD closest to the share of triangles we want
			var lod := im.get_surface_lod_indices(s, l)
			if lod.size() >= 12 and absi(lod.size() - want) < best:
				best = absi(lod.size() - want)
				idx = lod
		var mat := im.get_surface_material(s)
		for t in range(0, idx.size(), 3):
			tris.append([pos[idx[t]], pos[idx[t + 1]], pos[idx[t + 2]], _color(mat, arrays[Mesh.ARRAY_TEX_UV], idx[t], idx[t + 1], idx[t + 2])])
	var box := AABB(tris[0][0], Vector3.ZERO)
	for t: Array in tris:
		for j in 3:
			box = box.expand(t[j])
	var shift := Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	var palette: Array[String] = []
	var positions: Array[int] = []
	var vindex := {}
	var triangles: Array[int] = []
	for t: Array in tris:
		var key := (t[3] as Color).to_html(false) + "ff"
		var pi := palette.find(key)
		if pi < 0:
			palette.append(key)
			pi = palette.size() - 1
		var ids: Array[int] = []
		for j in 3:
			var p: Vector3 = t[j] + shift
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
		format = Models.FORMAT, id = model_id,
		source = {url = "", archive = "", archive_sha256 = "", entry = "res://render/airplane.gd build(\"%s\")" % aircraft,
			author = "OpenRC Simulator model teams", license = "project license (repository)",
			license_evidence = "Built from this repository's own aircraft models (read-only snapshot, scenery SC-09)"},
		transform = "as built (real size, nose −Z), centred, base on y = 0; reduced from %d to ~%d triangles" % [total, TARGET_TRIS],
		size_m = [snappedf(box.size.x, 0.001), snappedf(box.size.y, 0.001), snappedf(box.size.z, 0.001)],
		palette = palette, positions_mm = positions, triangles = triangles,
	}
