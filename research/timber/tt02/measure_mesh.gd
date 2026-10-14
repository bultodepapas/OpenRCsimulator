# TT-02: measure the Turbo Timber Evolution r2 model as Godot imports it (the runtime asset), never from Blender.
# Writes assets/aircraft/turbo-lumber-evolution/mesh-measurements.json: scene structure, pivot rest transforms,
# per-mesh/per-surface extents and extreme vertices, planform slices of the wing, tail, fin and fuselage, wheel and
# propeller radii. build_geometry.py turns these numbers (plus r2/metadata.json) into geometry.json.
# Run from the repository root after `--import`:
#   "$(app/get-godot.sh)" --headless --path app --script "$PWD/research/timber/tt02/measure_mesh.gd" -- --out=<abs path> [--check]
# --check regenerates the measurements and fails (exit 1) when they differ from the file: the importer or the asset changed.
extends SceneTree

const SCENE_PATH := "res://assets/aircraft/turbo-lumber-evolution/timber.glb"
const PIVOTS := ["aileron_left_hinge", "aileron_right_hinge", "flap_left_hinge", "flap_right_hinge", "elevator_hinge",
	"rudder_hinge", "tailwheel_steer", "tailwheel_axle", "thrust_frame", "propeller_spin", "gear_left_suspension",
	"gear_right_suspension", "wheel_left_axle", "wheel_right_axle"]
## Lenses, glazing and the grey brackets are not the planform outline.
const SKIN_EXCLUDED_MATERIALS := ["glass", "light_red", "light_green", "light_grey", "dark_grey"]
const CONTROL_MESHES := ["aileron_left", "aileron_right", "flap_left", "flap_right", "elevator", "rudder"]
## r2 split the former airframe mesh into independently separable fixed sections.
const WING_FIXED_MESHES := ["fuselage_core", "cowl", "wing_left_fixed", "wing_right_fixed"]
const TAIL_FIXED_MESHES := ["fuselage_core", "stabilizer_fixed", "fin_fixed"]
const FIN_FIXED_MESHES := ["fuselage_core", "fin_fixed"]
const FUSELAGE_FIXED_MESHES := ["fuselage_core", "cowl"]
## Slice bands (root frame, metres). Python decides which stations are clean wing/tail/fin sections from the extents.
const WING_BAND := {axis = 0, lo = Vector3(-INF, 0.04, -0.15), hi = Vector3(INF, 0.24, 0.45), start = 0.0, stop = 0.78, step = 0.01, mirrored = true}
const TAIL_BAND := {axis = 0, lo = Vector3(-INF, -0.09, 0.45), hi = Vector3(INF, 0.03, 0.90), start = 0.0, stop = 0.32, step = 0.01, mirrored = true}
const FIN_BAND := {axis = 1, lo = Vector3(-0.03, -INF, 0.45), hi = Vector3(0.03, INF, 0.90), start = 0.0, stop = 0.34, step = 0.01, mirrored = false}
const FUSELAGE_BAND := {axis = 2, lo = Vector3(-0.09, -0.30, -INF), hi = Vector3(0.09, 0.25, INF), start = -0.30, stop = 0.84, step = 0.02, mirrored = false}

var _root: Node3D
var _faces := {} # mesh name -> {all: PackedVector3Array (root frame, 3 per triangle), skin: PackedVector3Array}


func _initialize() -> void:
	call_deferred("_run")


static func _r(v: float) -> float:
	return ("%.6f" % v).to_float()


static func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


static func _basis(b: Basis) -> Dictionary:
	return {x = _v(b.x), y = _v(b.y), z = _v(b.z)}


func _arg(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.trim_prefix("--%s=" % name)
	return ""


func _has_flag(name: String) -> bool:
	return OS.get_cmdline_user_args().has("--" + name)


func _root_transform_of(node: Node3D) -> Transform3D:
	return _root.global_transform.affine_inverse() * node.global_transform


func _material_name(mi: MeshInstance3D, surface: int) -> String:
	var m := mi.get_active_material(surface)
	return m.resource_name if m != null else ""


func _collect_faces() -> void:
	for node in _root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var t := _root_transform_of(mi)
		var all := PackedVector3Array()
		var skin := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tri := PackedVector3Array()
			if indices.is_empty():
				for v in vertices: tri.append(t * v)
			else:
				for i in indices: tri.append(t * vertices[i])
			all.append_array(tri)
			if not SKIN_EXCLUDED_MATERIALS.has(_material_name(mi, s)): skin.append_array(tri)
		_faces[String(mi.name)] = {all = all, skin = skin}


func _mesh_group(names: Array, kind: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for raw_name in names:
		var faces: Dictionary = _faces[String(raw_name)]
		var points: PackedVector3Array = faces[kind]
		out.append_array(points)
	return out


## Select an exact non-excluded source vertex while retaining the landmark's mesh, axis and x-range definition.
func _vertex_extreme(mesh_names: Array, kind: String, axis: int, sign: float, x_min: float, x_max: float) -> Dictionary:
	var best := -INF
	var point := Vector3.ZERO
	for raw_name in mesh_names:
		var faces: Dictionary = _faces[String(raw_name)]
		var vertices: PackedVector3Array = faces[kind]
		for p in vertices:
			if p.x < x_min or p.x > x_max:
				continue
			var score := p[axis] * sign
			if score > best:
				best = score
				point = p
	return {root = _v(point)}


func _extents(points: PackedVector3Array) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	return {min = _v(lo), max = _v(hi), count = points.size()}


## Extents plus the fore-most (min z) and aft-most (max z) points: leading and trailing edges of a slice.
func _slice_summary(points: PackedVector3Array) -> Dictionary:
	var out := _extents(points)
	var fore := Vector3(0, 0, INF)
	var aft := Vector3(0, 0, -INF)
	for p in points:
		if p.z < fore.z: fore = p
		if p.z > aft.z: aft = p
	out.fore = _v(fore)
	out.aft = _v(aft)
	return out


## Vertex extremes of one surface in the root frame: which vertex reaches each min/max.
func _surface_extremes(mi: MeshInstance3D, s: int) -> Dictionary:
	var t := _root_transform_of(mi)
	var vertices: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
	var out := {}
	for axis in 3:
		for sign in [-1.0, 1.0]:
			var best := -INF
			var best_v := Vector3.ZERO
			var best_local := Vector3.ZERO
			for v in vertices:
				var p := t * v
				if p[axis] * sign > best:
					best = p[axis] * sign
					best_v = p
					best_local = v
			out["%s%s" % ["min" if sign < 0 else "max", ["x", "y", "z"][axis]]] = {root = _v(best_v), local = _v(best_local)}
	return out


## Candidate triangle indices per station along `axis` (stations ascending), one pass over the triangles.
static func _candidates(verts: PackedVector3Array, axis: int, stations: PackedFloat64Array) -> Array:
	var lists: Array = []
	for _s in stations: lists.append(PackedInt32Array())
	for tri in verts.size() / 3:
		var a: float = verts[3 * tri][axis]
		var b: float = verts[3 * tri + 1][axis]
		var c: float = verts[3 * tri + 2][axis]
		var lo := minf(a, minf(b, c))
		var hi := maxf(a, maxf(b, c))
		var i := stations.bsearch(lo)
		while i < stations.size() and stations[i] <= hi:
			lists[i].append(tri)
			i += 1
	return lists


static func _slice_triangle(verts: PackedVector3Array, tri: int, axis: int, x0: float, out: PackedVector3Array) -> void:
	var p := [verts[3 * tri], verts[3 * tri + 1], verts[3 * tri + 2]]
	var d := [p[0][axis] - x0, p[1][axis] - x0, p[2][axis] - x0]
	for i in 3:
		var j := (i + 1) % 3
		if d[i] == 0.0: out.append(p[i])
		if (d[i] < 0.0 and d[j] > 0.0) or (d[i] > 0.0 and d[j] < 0.0):
			out.append((p[i] as Vector3).lerp(p[j], d[i] / (d[i] - d[j])))


static func _in_band(p: Vector3, band: Dictionary) -> bool:
	for axis in 3:
		if axis == band.axis: continue
		if p[axis] < band.lo[axis] or p[axis] > band.hi[axis]: return false
	return true


## Extents of each mesh group's intersection with the band at every station of the band.
func _slices(band: Dictionary, groups: Dictionary) -> Array:
	var stations := PackedFloat64Array()
	var x := float(band.start)
	while x <= float(band.stop) + 1e-9:
		stations.append(_r(x))
		if band.mirrored and x > 0.0: stations.append(_r(-x))
		x += float(band.step)
	stations.sort()
	var candidates := {}
	for name in groups: candidates[name] = _candidates(groups[name], band.axis, stations)
	var rows: Array = []
	for i in stations.size():
		var row := {station = stations[i], groups = {}}
		for name in groups:
			var points := PackedVector3Array()
			var verts: PackedVector3Array = groups[name]
			for tri in candidates[name][i]:
				var cut := PackedVector3Array()
				_slice_triangle(verts, tri, band.axis, stations[i], cut)
				for p in cut:
					if _in_band(p, band): points.append(p)
			if not points.is_empty(): row.groups[name] = _slice_summary(points)
		rows.append(row)
	return rows


func _radial(mi: MeshInstance3D, frame: Node3D) -> Dictionary:
	# Radius about the frame's local +X and extent along it, from the mesh vertices expressed in that frame.
	var t := frame.global_transform.affine_inverse() * mi.global_transform
	var radius := 0.0
	var lo := INF
	var hi := -INF
	var tip := Vector3.ZERO
	for s in mi.mesh.get_surface_count():
		for v in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = t * v
			radius = maxf(radius, sqrt(p.y * p.y + p.z * p.z))
			if p.x > hi:
				hi = p.x
				tip = p
			lo = minf(lo, p.x)
	return {radius = _r(radius), axial_min = _r(lo), axial_max = _r(hi), axial_max_point_frame = _v(tip),
		axial_max_point_root = _v(_root_transform_of(frame) * tip)}


func _run() -> void:
	var out_path := _arg("out")
	if out_path.is_empty() or not out_path.is_absolute_path():
		printerr("Pass --out=<absolute path>")
		quit(2)
		return
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		printerr("Cannot load %s (run --import first)" % SCENE_PATH)
		quit(1)
		return
	_root = scene.instantiate()
	get_root().add_child(_root)
	await process_frame
	_collect_faces()
	var report := {
		format = "openrc-timber-mesh-measurements v1", step = "TT-02", generator = "research/timber/tt02/measure_mesh.gd",
		scene = SCENE_PATH, glb_sha256 = FileAccess.get_sha256(SCENE_PATH),
		godot = Engine.get_version_info().string, units = "m", axes = {right = "+X", up = "+Y", nose = "-Z"},
		frame = "root frame of the imported scene (identity root, datum D0 at the origin)",
	}
	# Scene structure.
	var nodes: Array = []
	for n in _root.find_children("*", "", true, false):
		var row := {name = String(n.name), type = n.get_class(), parent = String(n.get_parent().name)}
		if n is Node3D:
			row.origin = _v((n as Node3D).position)
			row.basis = _basis((n as Node3D).basis)
		nodes.append(row)
	report.scene_root = {name = String(_root.name), type = _root.get_class(), identity = _root.transform.is_equal_approx(Transform3D.IDENTITY), children = _root.get_child_count()}
	report.nodes = nodes
	report.counts = {mesh_instances = _root.find_children("*", "MeshInstance3D", true, false).size(),
		animation_players = _root.find_children("*", "AnimationPlayer", true, false).size(),
		cameras = _root.find_children("*", "Camera3D", true, false).size(), lights = _root.find_children("*", "Light3D", true, false).size()}
	# Pivots: rest transforms in the parent frame and in the root frame; glTF extras as imported.
	var pivots := {}
	for name in PIVOTS:
		var p: Node3D = _root.find_child(name, true, false)
		if p == null:
			pivots[name] = {found = false}
			continue
		var rt := _root_transform_of(p)
		pivots[name] = {found = true, parent = String(p.get_parent().name), origin = _v(p.position), basis = _basis(p.basis),
			quaternion_xyzw = [_r(p.quaternion.x), _r(p.quaternion.y), _r(p.quaternion.z), _r(p.quaternion.w)],
			root_origin = _v(rt.origin), root_axis_x = _v(rt.basis.x), root_axis_y = _v(rt.basis.y), root_axis_z = _v(rt.basis.z),
			extras = p.get_meta("extras", {})}
	report.pivots = pivots
	# Meshes: surfaces, materials, triangles, vertex format and extents.
	var meshes := {}
	var all_points := PackedVector3Array()
	var skin_points := PackedVector3Array()
	var total_surfaces := 0
	var total_triangles := 0
	for node in _root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s)
			var bm := m as BaseMaterial3D
			var fmt: int = mi.mesh.surface_get_format(s)
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			surfaces.append({index = s, material = _material_name(mi, s), material_class = m.get_class() if m else "",
				albedo = [_r(bm.albedo_color.r), _r(bm.albedo_color.g), _r(bm.albedo_color.b), _r(bm.albedo_color.a)] if bm else null,
				emission = bm.emission_enabled if bm else false, transparency = bm.transparency if bm else 0,
				compressed_attributes = (fmt & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0,
				vertices = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				triangles = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3,
				extremes = _surface_extremes(mi, s)})
		total_surfaces += surfaces.size()
		var faces: Dictionary = _faces[String(mi.name)]
		total_triangles += faces.all.size() / 3
		all_points.append_array(faces.all)
		skin_points.append_array(faces.skin)
		meshes[String(mi.name)] = {parent = String(mi.get_parent().name), root_transform = {origin = _v(_root_transform_of(mi).origin), basis = _basis(_root_transform_of(mi).basis)},
			local_identity = mi.transform.is_equal_approx(Transform3D.IDENTITY), surfaces = surfaces, triangles = faces.all.size() / 3,
			extents_root = _extents(faces.all), skin_extents_root = _extents(faces.skin)}
	report.meshes = meshes
	report.totals = {surfaces = total_surfaces, triangles = total_triangles}
	report.extents = {all = _extents(all_points), skin = _extents(skin_points)}
	# Which vertex reaches the forward extent (and the other extremes) over the whole model.
	var extremes := {}
	for key in ["minx", "maxx", "miny", "maxy", "minz", "maxz"]:
		var axis := ["x", "y", "z"].find(key.substr(3))
		var sign := -1.0 if key.begins_with("min") else 1.0
		var best := -INF
		var record := {}
		for name in meshes:
			for s in meshes[name].surfaces:
				var e: Dictionary = s.extremes[key]
				if float(e.root[axis]) * sign > best:
					best = float(e.root[axis]) * sign
					record = {mesh = name, surface = s.index, material = s.material, root = e.root, local = e.local}
		extremes[key] = record
	report.extremes = extremes
	# Radii about their own axles/thrust axis.
	var radial := {}
	for pair in [["wheel_left", "wheel_left_axle"], ["wheel_right", "wheel_right_axle"], ["tailwheel", "tailwheel_axle"], ["propeller_rotor", "thrust_frame"]]:
		radial[pair[0]] = _radial(_root.find_child(pair[0], true, false), _root.find_child(pair[1], true, false))
	report.radial = radial
	# Preserve the old slice definitions by combining only the fixed sections that belong in each band. In particular,
	# fuselage stations exclude the detached wing and tail sections so their roots do not inflate body half-width.
	var wing_skin := _mesh_group(WING_FIXED_MESHES, "skin")
	var tail_skin := _mesh_group(TAIL_FIXED_MESHES, "skin")
	var fin_skin := _mesh_group(FIN_FIXED_MESHES, "skin")
	var fuselage_skin := _mesh_group(FUSELAGE_FIXED_MESHES, "skin")
	var fuselage_all := _mesh_group(FUSELAGE_FIXED_MESHES, "all")
	var wing_groups := {airframe_skin = wing_skin, aileron_left = _faces.aileron_left.all, aileron_right = _faces.aileron_right.all,
		flap_left = _faces.flap_left.all, flap_right = _faces.flap_right.all}
	var tail_groups := {airframe_skin = tail_skin, elevator = _faces.elevator.all}
	var fin_groups := {airframe_skin = fin_skin, rudder = _faces.rudder.all}
	var fuselage_groups := {airframe_skin = fuselage_skin, airframe_all = fuselage_all}
	report.landmarks = {
		left_wingtip = _vertex_extreme(["wing_left_fixed"], "skin", 0, -1.0, -INF, 0.0),
		right_wingtip = _vertex_extreme(["wing_right_fixed"], "skin", 0, 1.0, 0.0, INF),
		wing_root_leading_edge = _vertex_extreme(["wing_right_fixed"], "skin", 2, -1.0, 0.0, 0.003),
	}
	report.slices = {
		wing = {band = _band_json(WING_BAND), rows = _slices(WING_BAND, wing_groups)},
		tail = {band = _band_json(TAIL_BAND), rows = _slices(TAIL_BAND, tail_groups)},
		fin = {band = _band_json(FIN_BAND), rows = _slices(FIN_BAND, fin_groups)},
		fuselage = {band = _band_json(FUSELAGE_BAND), rows = _slices(FUSELAGE_BAND, fuselage_groups)},
	}
	var text := JSON.stringify(report, "  ", true, true) + "\n"
	if _has_flag("check"):
		var stored := FileAccess.get_file_as_string(out_path)
		if stored != text:
			printerr("Timber mesh measurements differ from %s: regenerate (and review) them" % out_path)
			quit(1)
			return
		print("Timber mesh measurements: identical (%d meshes, %d surfaces, %d triangles)" % [meshes.size(), total_surfaces, total_triangles])
	else:
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			printerr("Cannot write %s" % out_path)
			quit(1)
			return
		f.store_string(text)
		f.close()
		print("wrote %s (%d meshes, %d surfaces, %d triangles)" % [out_path, meshes.size(), total_surfaces, total_triangles])
	quit(0)


static func _band_json(band: Dictionary) -> Dictionary:
	var lo: Array = []
	var hi: Array = []
	for axis in 3:
		lo.append(null if band.lo[axis] == -INF else _r(band.lo[axis]))
		hi.append(null if band.hi[axis] == INF else _r(band.hi[axis]))
	return {axis = ["x", "y", "z"][band.axis], lo = lo, hi = hi, start = band.start, stop = band.stop, step = band.step, mirrored = band.mirrored}
