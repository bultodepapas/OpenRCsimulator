## SC-01(d): scenery technique probe and style bake-off (SCENERY-PLAN). Runs only inside a scratch copy of app/
## made by run.sh (git archive HEAD), never inside app/. Cases: merge, depth, ground, style. Each writes PNGs and
## result.json into --out. Real renderer required (xvfb + opengl3): render counters read 0 under --headless.
extends SceneTree

const Atmosphere = preload("res://render/atmosphere.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")

const EYE := 1.7
const DEPTH_STEPS := 16777216.0 # 2^24: D24 depth buffer (report 04)

var args: Dictionary = {}
var out_dir := ""
var results: Dictionary = {}
var world: Node3D
var camera: Camera3D


func _initialize() -> void:
	for raw: String in OS.get_cmdline_user_args():
		var kv := raw.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	out_dir = str(args.get("out", "/tmp/sc01"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	ShaderClock.register()
	ShaderClock.update(1.5)
	_run.call_deferred()


func _run() -> void:
	var case_name := str(args.get("case", ""))
	results = {case = case_name, godot = Engine.get_version_info().string, adapter = RenderingServer.get_video_adapter_name(),
		resolution = [root.size.x, root.size.y]}
	match case_name:
		"merge": await _case_merge()
		"depth": await _case_depth()
		"ground": await _case_ground()
		"style": await _case_style()
		_:
			push_error("unknown --case")
			quit(2)
			return
	var file := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  ", true))
	file.close()
	print("SC01 DONE ", case_name)
	quit(0)


# ---------- scene helpers ----------

func _new_world(production_env: bool, field_objects: bool = true) -> void:
	if world:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	root.add_child(world)
	if production_env:
		var we := WorldEnvironment.new()
		we.environment = Atmosphere.environment()
		world.add_child(we)
		var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
		var field: Dictionary = loaded.field
		if not field_objects:
			field = field.duplicate(true)
			field.objects = []
		world.add_child(FieldBuilder.build(field))
		Atmosphere.create_sun(world)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true


func _env_black() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	world.add_child(we)


func _shot(name: String) -> Dictionary:
	for _i in int(args.get("settle", "2")):
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	var active := root.get_camera_3d()
	return {
		active_camera_is_probe_camera = active == camera,
		camera_origin = [snappedf(camera.global_position.x, 0.01), snappedf(camera.global_position.y, 0.01), snappedf(camera.global_position.z, 0.01)],
		draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		objects = Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	}


func _look(from: Vector3, to: Vector3) -> void:
	camera.look_at_from_position(from, to, Vector3.UP)


static func _unshaded(color: Color, fog: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.disable_fog = not fog
	return m


static func _lit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


# ---------- asset loading and merging ----------

## Loads a GLB/glTF/FBX at runtime. Returns [{mesh, xform}] relative to the file's root.
func _load_parts(path: String) -> Array:
	var is_fbx := path.get_extension().to_lower() == "fbx"
	var doc: GLTFDocument = FBXDocument.new() if is_fbx else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if is_fbx else GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("load failed %s (%d)" % [path, err])
		return []
	var scene := doc.generate_scene(state)
	var parts: Array = []
	_collect(scene, Transform3D.IDENTITY, parts)
	scene.free()
	return parts


func _collect(node: Node, parent_xf: Transform3D, parts: Array) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mi.material_override:
			mesh = mesh.duplicate()
			for s in mesh.get_surface_count():
				mesh.surface_set_material(s, mi.material_override)
		parts.append({mesh = mesh, xform = xf})
	elif node is ImporterMeshInstance3D and (node as ImporterMeshInstance3D).mesh:
		parts.append({mesh = (node as ImporterMeshInstance3D).mesh.get_mesh(), xform = xf})
	for child in node.get_children():
		_collect(child, xf, parts)


static func _parts_aabb(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for p: Dictionary in parts:
		var b: AABB = (p.xform as Transform3D) * (p.mesh as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Scales parts so that the given axis ("length": max horizontal, "height") equals target metres, base on y = 0.
static func _normalize(parts: Array, axis: String, target: float) -> Array:
	var box := _parts_aabb(parts)
	var size := box.size
	var current: float = size.y if axis == "height" else maxf(size.x, size.z)
	var k := target / maxf(current, 1e-6)
	# Long side along local -Z (forward), centred on x/z, base on the ground.
	var turn := Basis.IDENTITY if size.z >= size.x or axis == "height" else Basis(Vector3.UP, PI / 2.0)
	var centre := box.get_center()
	var shift := Transform3D(Basis.IDENTITY, Vector3(-centre.x, -box.position.y, -centre.z))
	var fit := Transform3D(turn.scaled(Vector3(k, k, k)), Vector3.ZERO) * shift
	var out_parts: Array = []
	for p: Dictionary in parts:
		out_parts.append({mesh = p.mesh, xform = fit * (p.xform as Transform3D)})
	return out_parts


static func _place(parts: Array, at: Vector3, yaw_deg: float, mirror: bool = false) -> Array:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	if mirror:
		basis = basis * Basis.from_scale(Vector3(-1, 1, 1))
	var xf := Transform3D(basis, at)
	var placed: Array = []
	for p: Dictionary in parts:
		placed.append({mesh = p.mesh, xform = xf * (p.xform as Transform3D)})
	return placed


func _add_separate(parts: Array, parent: Node3D) -> int:
	var n := 0
	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = p.mesh
		mi.transform = p.xform
		parent.add_child(mi)
		n += (p.mesh as Mesh).get_surface_count()
	return n


## dedupe merges surfaces with the same *name* and format and keeps the first one's material, so unnamed primitive
## surfaces or reused names ("White") would take a wrong material. by_material renames each surface after its
## material resource first, so only surfaces that really share a material are joined.
static func _merge_importer(parts: Array, by_material: bool = false) -> ArrayMesh:
	var meshes: Array[ImporterMesh] = []
	var xforms: Array[Transform3D] = []
	for p: Dictionary in parts:
		var im := ImporterMesh.from_mesh(p.mesh)
		if by_material:
			for s in im.get_surface_count():
				var mat: Material = im.get_surface_material(s)
				im.set_surface_name(s, "m%d" % (mat.get_instance_id() if mat else 0))
		meshes.append(im)
		xforms.append(p.xform)
	return ImporterMesh.merge_importer_meshes(meshes, xforms, true).get_mesh()


## One SurfaceTool per material resource; append_from per surface (no winding fix under negative scale).
static func _merge_surfacetool(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for p: Dictionary in parts:
		var mesh: Mesh = p.mesh
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if not tools.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[mat] = st
			(tools[mat] as SurfaceTool).append_from(mesh, s, p.xform)
	var result := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.commit(result)
		result.surface_set_material(result.get_surface_count() - 1, mat)
	return result


static func _triangles(parts: Array) -> int:
	var n := 0
	for p: Dictionary in parts:
		var mesh: Mesh = p.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			n += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


# ---------- case: merge ----------

func _case_merge() -> void:
	var dir := str(args.assets).path_join("kenney-car")
	var models := ["sedan", "suv", "hatchback-sports", "delivery", "police", "taxi", "sedan-sports", "suv-luxury"]
	var lib: Array = []
	for m: String in models:
		lib.append(_normalize(_load_parts(dir.path_join(m + ".glb")), "length", 4.4))
	# A 40-car park: 4 rows × 10, 2.6 m bays; every 9th car mirrored (negative scale) to expose winding.
	var parts: Array = []
	var mirrored := 0
	for i in 40:
		var row := i / 10
		var col := i % 10
		var mirror := i % 9 == 4
		mirrored += int(mirror)
		parts.append_array(_place(lib[i % lib.size()], Vector3(-11.7 + col * 2.6, 0, -60.0 - row * 7.0), 0.0, mirror))
	results.cars = 40
	results.mirrored_cars = mirrored
	results.parts = parts.size()
	results.triangles = _triangles(parts)
	var view_from := Vector3(0, 12, -20)
	var view_to := Vector3(0, 0, -70)
	var variants := {}
	# separate
	await _new_world(true, false)
	_look(view_from, view_to)
	var holder := Node3D.new()
	world.add_child(holder)
	var surfaces := _add_separate(parts, holder)
	var base := await _shot("merge-none")
	holder.queue_free()
	await process_frame
	var empty := await _shot("merge-empty")
	variants.separate = {surfaces = surfaces, shot = base}
	variants.empty = {shot = empty}
	# ImporterMesh
	var t0 := Time.get_ticks_usec()
	var merged_i := _merge_importer(parts)
	var t_i := Time.get_ticks_usec() - t0
	var mi := MeshInstance3D.new()
	mi.mesh = merged_i
	world.add_child(mi)
	variants.importer = {build_ms = t_i / 1000.0, surfaces = merged_i.get_surface_count(), shot = await _shot("merge-importer")}
	mi.queue_free()
	await process_frame
	# SurfaceTool
	t0 = Time.get_ticks_usec()
	var merged_s := _merge_surfacetool(parts)
	var t_s := Time.get_ticks_usec() - t0
	var ms := MeshInstance3D.new()
	ms.mesh = merged_s
	world.add_child(ms)
	variants.surfacetool = {build_ms = t_s / 1000.0, surfaces = merged_s.get_surface_count(), shot = await _shot("merge-surfacetool")}
	ms.queue_free()
	await process_frame
	# Palette case: every Kenney car samples the same colormap, so one shared material stands in for the atlas.
	var shared: Material = (parts[0].mesh as Mesh).surface_get_material(0)
	var shared_parts: Array = []
	for p: Dictionary in parts:
		var m: Mesh = (p.mesh as Mesh).duplicate()
		for s in m.get_surface_count():
			m.surface_set_material(s, shared)
		shared_parts.append({mesh = m, xform = p.xform})
	t0 = Time.get_ticks_usec()
	var merged_p := _merge_surfacetool(shared_parts)
	var t_p := Time.get_ticks_usec() - t0
	var mp := MeshInstance3D.new()
	mp.mesh = merged_p
	world.add_child(mp)
	variants.surfacetool_shared = {build_ms = t_p / 1000.0, surfaces = merged_p.get_surface_count(), shot = await _shot("merge-shared")}
	mp.queue_free()
	results.variants = variants
	results.vertex_colour_trap = _vertex_colour_trap()


## Merges a mesh without COLOR with one that has red COLOR; reports the colour the first mesh's vertices receive.
static func _vertex_colour_trap() -> Dictionary:
	var plain := BoxMesh.new()
	var plain_arrays := plain.get_mesh_arrays()
	var a := ArrayMesh.new()
	a.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plain_arrays)
	var coloured_arrays := plain.get_mesh_arrays()
	var cols := PackedColorArray()
	cols.resize((coloured_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	cols.fill(Color.RED)
	coloured_arrays[Mesh.ARRAY_COLOR] = cols
	var b := ArrayMesh.new()
	b.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coloured_arrays)
	var n_plain := (plain_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var report := {}
	for order: String in ["plain_first", "coloured_first"]:
		var first: ArrayMesh = a if order == "plain_first" else b
		var second: ArrayMesh = b if order == "plain_first" else a
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(first, 0, Transform3D.IDENTITY)
		st.append_from(second, 0, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
		var merged := st.commit_to_arrays()
		var c: Variant = merged[Mesh.ARRAY_COLOR]
		var plain_range := range(0, n_plain) if order == "plain_first" else range(n_plain, 2 * n_plain)
		var colours := {}
		if c == null:
			colours["<no COLOR array>"] = n_plain
		else:
			for i: int in plain_range:
				var key := str((c as PackedColorArray)[i])
				colours[key] = int(colours.get(key, 0)) + 1
		report["surfacetool_" + order] = colours
	var im := ImporterMesh.merge_importer_meshes([ImporterMesh.from_mesh(a), ImporterMesh.from_mesh(b)] as Array[ImporterMesh],
		[Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0))] as Array[Transform3D], true)
	var im_mesh := im.get_mesh()
	var surf := []
	for s in im_mesh.get_surface_count():
		var arr := im_mesh.surface_get_arrays(s)
		var cc: Variant = arr[Mesh.ARRAY_COLOR]
		var hist := {}
		if cc == null:
			hist["<no COLOR array>"] = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		else:
			for col: Color in cc:
				hist[str(col)] = int(hist.get(str(col), 0)) + 1
		surf.append(hist)
	report.importer_surfaces = surf
	return report


# ---------- case: depth (turbine z-fighting) ----------

func _turbine(d: float, sep: float, parent: Node3D, show_tower: bool, show_blades: bool) -> void:
	var tower_mat := _unshaded(Color(1, 0, 0))
	var blade_mat := _unshaded(Color(1, 1, 1))
	if show_tower:
		var tower := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.5
		cyl.bottom_radius = 2.2
		cyl.height = 90.0
		cyl.radial_segments = 16
		cyl.material = tower_mat
		tower.mesh = cyl
		tower.position = Vector3(0, 45, -d)
		parent.add_child(tower)
	if show_blades:
		for k in 3:
			var blade := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(2.5, 50.0, 0.6)
			box.material = blade_mat
			blade.mesh = box
			var a := deg_to_rad(180.0 + 120.0 * k) # one blade straight down, across the tower
			var hub := Vector3(0, 90, -d + sep)
			blade.transform = Transform3D(Basis(Vector3(0, 0, 1), a), hub + Basis(Vector3(0, 0, 1), a) * Vector3(0, 25, 0))
			parent.add_child(blade)


func _case_depth() -> void:
	root.msaa_3d = Viewport.MSAA_DISABLED
	# (a) Depth resolution on this renderer: a white square in front of a red one, gap s, facing the camera.
	var planes: Array = []
	for d: float in [500.0, 1500.0, 2500.0, 5000.0]:
		for near: float in [0.1, 0.5, 1.0]:
			await _new_world(false)
			_env_black()
			camera.near = near
			camera.fov = 20.7
			_look(Vector3(0, EYE, 0), Vector3(0, EYE, -d))
			var row := {distance_m = d, near_m = near, depth_step_at_d_m = d * d / (near * DEPTH_STEPS), shots = {}}
			for gap: float in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
				var holder := Node3D.new()
				world.add_child(holder)
				for layer: int in 2:
					var q := MeshInstance3D.new()
					var quad := QuadMesh.new()
					quad.size = Vector2(d * 0.05, d * 0.05)
					quad.material = _unshaded(Color(1, 1, 1) if layer == 0 else Color(1, 0, 0))
					q.mesh = quad
					q.position = Vector3(0, EYE, -d + (0.0 if layer == 0 else -gap))
					holder.add_child(q)
				var tag := "plane-d%d-n%s-g%s" % [int(d), str(near), str(gap)]
				await _shot(tag)
				row.shots[str(gap)] = tag
				holder.queue_free()
				await process_frame
			planes.append(row)
	results.planes = planes
	# (b) Turbine: blade straight down across the tower, gap between blade and tower axis swept.
	var rows: Array = []
	for d: float in [1500.0, 2500.0, 5000.0]:
		for near: float in [0.1, 0.5]:
			for sep: float in [3.0, 6.0, 12.0]:
				var row := {distance_m = d, near_m = near, fov_deg = 20.7, separation_m = sep,
					depth_step_at_d_m = d * d / (near * DEPTH_STEPS)}
				for layer: String in ["tower", "blades", "both"]:
					await _new_world(false)
					_env_black()
					camera.near = near
					camera.fov = 20.7
					_turbine(d, sep, world, layer != "blades", layer != "tower")
					var frames: Array = []
					for j in 6: # masks are rendered for every jittered frame too, so they register exactly
						var jitter := 0.00005 * j
						_look(Vector3(0, EYE, 0), Vector3(sin(jitter) * d, 70.0, -d))
						var tag := "depth-d%d-n%s-s%s-%s-%d" % [int(d), str(near), str(sep), layer, j]
						frames.append(tag)
						await _shot(tag)
					row[layer] = frames
				rows.append(row)
	results.rows = rows


# ---------- case: ground (contact-shadow quads) ----------

func _shadow_quad(size: float, lift: float, at: Vector3, blend_mul: bool) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if blend_mul:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		mat.albedo_color = Color(0.5, 0.5, 0.5, 1.0)
	else:
		mat.albedo_color = Color(0, 0, 0, 0.5)
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = at + Vector3(0, lift, 0)
	return mi


func _case_ground() -> void:
	var az := deg_to_rad(20.0) # clear of the runway (north 9–21 m)
	var rows: Array = []
	var heights: Array = [1.7, 10.0, 30.0, 100.0]
	if args.has("heights"):
		heights = Array(str(args.heights).split(",")).map(func(x: String) -> float: return float(x))
	for h: float in heights:
		for d: float in [40.0, 180.0, 400.0]:
			var at := Frames.ned_to_render([d * cos(az), d * sin(az), 0.0])
			var range_m := sqrt(d * d + h * h)
			var dh_lift := 3.0 * range_m * h / (0.1 * DEPTH_STEPS)
			var d2_lift := 3.0 * range_m * range_m / (0.1 * DEPTH_STEPS)
			var row := {height_m = h, distance_m = d, quad_m = 20.0, lift_dh_m = dh_lift, lift_d2_m = d2_lift, shots = {}}
			await _new_world(true, false)
			_look(Vector3(0, h, 0), at)
			row.shots.ref = "ground-h%d-d%d-ref" % [int(h), int(d)]
			row.ref_shot = await _shot(row.shots.ref)
			row.debug = {forward = str(-camera.global_basis.z), runway_px = str(camera.unproject_position(Vector3(5, 0, -15))), quad_px = str(camera.unproject_position(at)), at = str(at)}
			for lift_name: String in ["0.002", "0.005", "0.02", "0.1", "dh", "d2"]:
				var lift: float = dh_lift if lift_name == "dh" else (d2_lift if lift_name == "d2" else float(lift_name))
				var q := _shadow_quad(20.0, lift, at, false)
				world.add_child(q)
				var tag := "ground-h%d-d%d-lift%s" % [int(h), int(d), lift_name]
				await _shot(tag)
				row.shots[lift_name] = tag
				q.queue_free()
				await process_frame
			# Quad corners projected (inner 50 %) for the analysis window.
			var corners: Array = []
			for c: Vector2 in [Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)]:
				var p := camera.unproject_position(at + Vector3(c.x, 0, c.y))
				corners.append([p.x, p.y])
			row.window_px = corners
			rows.append(row)
	results.rows = rows
	# Fog check: alpha-mix vs blend_mul against the expected L_g − 0.5·T·G (linear tonemap, 100 m up).
	var fog_rows: Array = []
	for d: float in [400.0, 2000.0]:
		var at := Frames.ned_to_render([d * cos(az), d * sin(az), 0.0])
		var size := d * 0.1
		var row := {distance_m = d, height_m = 100.0, quad_m = size, transmittance = Atmosphere.transmittance(sqrt(d * d + 1e4))}
		for variant: String in ["ref", "nofog", "mix", "mul"]:
			await _new_world(true, false)
			var env: Environment = (world.get_child(0) as WorldEnvironment).environment
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
			if variant == "nofog":
				env.fog_enabled = false
			_look(Vector3(0, 100, 0), at)
			if variant == "mix" or variant == "mul":
				world.add_child(_shadow_quad(size, 0.5, at, variant == "mul"))
			var tag := "fog-d%d-%s" % [int(d), variant]
			await _shot(tag)
			row[variant] = tag
		var corners: Array = []
		for c: Vector2 in [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(0.25, 0.25), Vector2(-0.25, 0.25)]:
			var p := camera.unproject_position(at + Vector3(c.x * size, 0, c.y * size))
			corners.append([p.x, p.y])
		row.window_px = corners
		fog_rows.append(row)
	results.fog = fog_rows


# ---------- case: style (bake-off) ----------

func _box(size: Vector3, at: Vector3, mat: Material, yaw_deg: float = 0.0) -> Dictionary:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return {mesh = m, xform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), at)}


## Our own blockouts in palette colours (estimated sizes from report 03).
func _shelter(at: Vector3) -> Array:
	var post := _lit(Color("#6b5a48"))
	var roof := _lit(Color("#b9c0c4"))
	var table := _lit(Color("#8a7660"))
	var parts: Array = []
	for i in 9:
		for side: float in [-1.8, 1.8]:
			parts.append(_box(Vector3(0.15, 3.0, 0.15), at + Vector3(-14.0 + i * 3.5, 1.5, side), post))
	var r := _box(Vector3(29.0, 0.12, 4.6), at + Vector3(0, 3.15, 0), roof)
	r.xform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(4.0)), at + Vector3(0, 3.15, 0))
	parts.append(r)
	for i in 6:
		parts.append(_box(Vector3(2.4, 0.06, 0.8), at + Vector3(-11.0 + i * 4.4, 0.78, -0.6), table))
		parts.append(_box(Vector3(0.08, 0.75, 0.6), at + Vector3(-12.1 + i * 4.4, 0.37, -0.6), table))
		parts.append(_box(Vector3(0.08, 0.75, 0.6), at + Vector3(-9.9 + i * 4.4, 0.37, -0.6), table))
	return parts


func _pavilion(at: Vector3) -> Array:
	var white := _lit(Color("#e8e6df"))
	var roof := _lit(Color("#7d8a90"))
	var parts: Array = [_box(Vector3(9.0, 2.7, 6.0), at + Vector3(0, 1.35, 0), white)]
	var hip := CylinderMesh.new()
	hip.top_radius = 0.6
	hip.bottom_radius = 1.0
	hip.height = 1.0
	hip.radial_segments = 4
	hip.rings = 1
	hip.material = roof
	# A 4-sided frustum scaled to a 10 × 7 m hip roof, 1.8 m high.
	parts.append({mesh = hip, xform = Transform3D(Basis(Vector3.UP, PI / 4.0).scaled(Vector3(7.1, 1.8, 4.95)), at + Vector3(0, 2.7 + 0.9, 0))})
	return parts


func _bale(at: Vector3, yaw: float) -> Dictionary:
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 0.6
	c.height = 1.2
	c.radial_segments = 16
	c.material = _lit(Color("#c9b27a"))
	return {mesh = c, xform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI / 2.0), at + Vector3(0, 0.6, 0))}


func _case_style() -> void:
	var a := str(args.assets)
	var q := a.path_join("quaternius-cars")
	var pp := a.path_join("polypizza")
	var k := a.path_join("kenney-car")
	var trees := str(args.repo).path_join("assets/landscape/trees/source")
	var lib := {
		q_car1 = _normalize(_load_parts(q.path_join("NormalCar1.fbx")), "length", 4.4),
		q_car2 = _normalize(_load_parts(q.path_join("NormalCar2.fbx")), "length", 4.5),
		q_suv = _normalize(_load_parts(q.path_join("SUV.fbx")), "length", 4.7),
		q_sport = _normalize(_load_parts(q.path_join("SportsCar.fbx")), "length", 4.3),
		q_pickup = _normalize(_load_parts(pp.path_join("qn4grQgHm8.glb")), "length", 5.3),
		k_sedan = _normalize(_load_parts(k.path_join("sedan.glb")), "length", 4.4),
		k_suv = _normalize(_load_parts(k.path_join("suv.glb")), "length", 4.7),
		k_van = _normalize(_load_parts(k.path_join("delivery.glb")), "length", 5.2),
		cow = _normalize(_load_parts(pp.path_join("5XSc2Fka3F.glb")), "length", 2.4),
		sheep = _normalize(_load_parts(pp.path_join("C39AUXUUes.glb")), "length", 1.3),
		man = _normalize(_load_parts(pp.path_join("HMnuH5geEG.glb")), "height", 1.78),
		barn = _normalize(_load_parts(pp.path_join("vSqQNA7ez6.glb")), "height", 9.0),
		silo = _normalize(_load_parts(pp.path_join("5GhLrv5Ce3.glb")), "height", 14.0),
		church = _normalize(_load_parts(pp.path_join("GHzPfvoyzX.glb")), "height", 22.0),
		pylon = _normalize(_load_parts(pp.path_join("Xfb0lAPvnh.glb")), "height", 30.0),
		hedge = _normalize(_load_parts(pp.path_join("df8uCl1YpK.glb")), "height", 1.6),
		fence = _normalize(_load_parts(pp.path_join("e02PFKKhbr.glb")), "height", 1.1),
		bench = _normalize(_load_parts(pp.path_join("jLxjFxFRpw.glb")), "length", 1.8),
		gascan = _normalize(_load_parts(pp.path_join("eS1OXGo51c.glb")), "height", 0.35),
		tree1 = _normalize(_load_parts(trees.path_join("CommonTree_1.gltf")), "height", 14.0),
		tree3 = _normalize(_load_parts(trees.path_join("CommonTree_3.gltf")), "height", 17.0),
	}
	var sizes := {}
	for key: String in lib:
		var box := _parts_aabb(lib[key])
		sizes[key] = {size_m = [snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)], parts = (lib[key] as Array).size(), triangles = _triangles(lib[key])}
	results.library = sizes
	# Composition 1: the club, laid out as the plan's `photo` profile (NED metres → render).
	var club: Array = []
	var p := func(n: float, e: float) -> Vector3: return Frames.ned_to_render([n, e, 0.0])
	club.append_array(_shelter(p.call(-18.5, -30.0)))
	club.append_array(_shelter(p.call(-18.5, 30.0)))
	club.append_array(_pavilion(p.call(-20.0, 0.0)))
	var cars := ["q_car1", "q_suv", "q_car2", "q_sport", "q_car1", "q_suv", "q_car2"]
	for i in cars.size():
		club.append_array(_place(lib[cars[i]], p.call(-38.0, -8.0 + i * 2.6), 180.0 + float(i % 3 - 1)))
	club.append_array(_place(lib.q_pickup, p.call(-37.0, -18.0), 160.0))
	for i in 5:
		club.append_array(_place(lib.tree1 if i % 2 == 0 else lib.tree3, p.call(-50.0 - (i % 2) * 4.0, -14.0 + i * 7.0), i * 70.0))
	for i in 4:
		club.append_array(_place(lib.man, p.call(-24.0, -6.0 + i * 3.3), 180.0 + i * 25.0))
		club.append_array(_place(lib.bench, p.call(-25.5, -6.0 + i * 3.3), 0.0))
	club.append_array(_place(lib.gascan, p.call(-17.0, -31.0), 30.0))
	for i in 12:
		club.append_array(_place(lib.fence, p.call(-60.0, -30.0 + i * 5.9), 90.0))
	# Composition 2: the countryside in front, in the flight box and beyond.
	var country: Array = []
	for i in 9:
		country.append(_bale(p.call(80.0 + (i % 3) * 25.0, 60.0 + (i / 3) * 30.0), float(i) * 0.7))
	for i in 20:
		country.append_array(_place(lib.hedge, p.call(240.0, -100.0 + i * 10.0), 90.0))
	country.append_array(_place(lib.barn, p.call(520.0, 260.0), 200.0))
	country.append_array(_place(lib.silo, p.call(530.0, 275.0), 0.0))
	for i in 5:
		country.append_array(_place(lib.cow if i < 3 else lib.sheep, p.call(330.0 + i * 6.0, 330.0 + (i % 2) * 5.0), i * 50.0))
	country.append_array(_place(lib.church, p.call(1800.0, -600.0), 0.0))
	for i in 4:
		country.append_array(_place(lib.pylon, p.call(1200.0, -1500.0 + i * 350.0), 90.0))
	# Composition 3: a style line-up for side-by-side comparison, lit with the sun behind the camera.
	var lineup: Array = []
	var order := ["q_car1", "k_sedan", "q_suv", "k_suv", "q_pickup", "k_van", "man", "cow", "sheep", "bench", "tree1"]
	var lineup_origin: Vector3 = p.call(60.0, 120.0)
	for i in order.size():
		lineup.append_array(_place(lib[order[i]], lineup_origin + Vector3(-27.0 + i * 5.5, 0, 0), 90.0))
	lineup.append(_bale(lineup_origin + Vector3(34.0, 0, 0), 0.0))
	results.counts = {club_parts = club.size(), club_triangles = _triangles(club), country_parts = country.size(),
		country_triangles = _triangles(country)}
	var views := {
		club_pilot = [Vector3(0, EYE, 0), p.call(-25.0, 0.0), 50.0],
		club_photo = [p.call(25.0, 70.0) + Vector3(0, 55, 0), p.call(-25.0, 0.0), 40.0],
		club_runway = [p.call(15.0, -20.0) + Vector3(0, EYE, 0), p.call(-30.0, 5.0), 50.0],
		country_pilot = [Vector3(0, EYE, 0), p.call(300.0, 60.0) + Vector3(0, 8, 0), 50.0],
		country_zoom = [Vector3(0, EYE, 0), p.call(500.0, 230.0) + Vector3(0, 10, 0), 20.7],
		lineup_20 = [lineup_origin + Vector3(-14, EYE, 14), lineup_origin, 50.0],
		lineup_60 = [lineup_origin + Vector3(-42, EYE, 42), lineup_origin, 50.0],
		lineup_150 = [lineup_origin + Vector3(-106, EYE, 106), lineup_origin, 20.7],
	}
	var shots := {}
	for mode: String in ["separate", "merged"]:
		await _new_world(true, true)
		if mode == "separate":
			var holder := Node3D.new()
			world.add_child(holder)
			_add_separate(club + country + lineup, holder)
		else:
			var t0 := Time.get_ticks_usec()
			var zones: Array = [club, country, lineup]
			for zone: Array in zones:
				var mi := MeshInstance3D.new()
				mi.mesh = _merge_importer(zone, true)
				world.add_child(mi)
			results.merge_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
			var surf := []
			for c in world.get_children():
				if c is MeshInstance3D and c.get_parent() == world and (c as MeshInstance3D).mesh is ArrayMesh:
					surf.append((c as MeshInstance3D).mesh.get_surface_count())
			results.merged_zone_surfaces = surf
		for v: String in views:
			var spec: Array = views[v]
			camera.fov = spec[2]
			_look(spec[0], spec[1])
			shots["%s-%s" % [v, mode]] = await _shot("style-%s-%s" % [v, mode])
	# Empty-field twins for the scenery-only counter deltas.
	await _new_world(true, true)
	for v: String in views:
		var spec: Array = views[v]
		camera.fov = spec[2]
		_look(spec[0], spec[1])
		shots["%s-empty" % v] = await _shot("style-%s-empty" % v)
	results.shots = shots
