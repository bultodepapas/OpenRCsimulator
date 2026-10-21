## Per-subsystem drawn cost of the production world in the postcard views.
## For each view it renders the complete world, then the world without one subsystem at a time, and
## without the sun's shadow pass. Cost(subsystem) = complete - without(subsystem); Compatibility's
## total counters include shadow-pass work, so the difference covers visible and shadow draws. It also
## records each subsystem's full-detail source triangles (the quantity the scenery tests cap).
## llvmpipe counts are renderer-independent CPU-side submissions after culling and mesh LOD; they are
## not GPU timings. Run through tools/scenery/attribute_views.sh.
##   xvfb-run -a godot --path app --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 \
##     --script <abs>/tools/scenery/attribute_views.gd -- --out=<new dir> [--views=a,b] [--t=1.5]
extends SceneTree

const FieldLoader = preload("res://data/field_loader.gd")
const World = preload("res://render/world/world.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const Postcards = preload("res://scenery/postcards.gd")
const Population = preload("res://scenery/population.gd")

const FORMAT := "openrc-view-attribution v1"
const SCENERY_PATTERNS := {"cell_": "scenery_cells", "shadows_": "scenery_contact_shadows",
	"ImportedHedge_": "scenery_hedges", "PitShelter_": "scenery_pit_shelters"}

var _args := {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		_args[pair[0]] = pair[1] if pair.size() > 1 else "on"
	_run.call_deferred()


func _run() -> void:
	var out := str(_args.get("out", ""))
	if out.is_empty() or DisplayServer.get_name() == "headless":
		printerr("--out and a real Compatibility framebuffer are required")
		quit(1)
		return
	if DirAccess.dir_exists_absolute(out) and not DirAccess.get_files_at(out).is_empty():
		printerr("--out must be new or empty")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	ShaderClock.register()
	ShaderClock.update(float(_args.get("t", "1.5")))
	var world := Node3D.new()
	root.add_child(world)
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	if not loaded.ok:
		printerr("field invalid")
		quit(1)
		return
	var built: Dictionary = World.build(world, loaded.field)
	var field_node: Node3D = built.field
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 21000.0
	world.add_child(camera)
	camera.current = true
	var groups := _groups(world, field_node, camera)
	var suns: Array[Node] = world.find_children("*", "DirectionalLight3D", true, false)
	var report := {
		format = FORMAT, renderer = RenderingServer.get_current_rendering_method(),
		adapter = RenderingServer.get_video_adapter_name(), godot = Engine.get_version_info().string,
		viewport = [root.get_visible_rect().size.x, root.get_visible_rect().size.y],
		mesh_lod_threshold = root.get_viewport().mesh_lod_threshold,
		field_sha256 = FileAccess.get_sha256(FieldLoader.DEFAULT_PATH),
		scenery_sha256 = FileAccess.get_sha256("res://data/scenery/default.json"),
		groups = {}, views = {},
	}
	for name: String in groups:
		report.groups[name] = _geometry(groups[name])
		report.groups[name]["nodes"] = (groups[name] as Array).size()
	var wanted: Array = Postcards.names()
	if _args.has("views"):
		wanted = str(_args.views).split(",")
	for view_name: String in wanted:
		var view: Dictionary = Postcards.VIEWS.get(view_name, {})
		if view.is_empty():
			printerr("Unknown view: ", view_name)
			quit(1)
			return
		camera.fov = view.fov
		camera.look_at_from_position(Frames.ned_to_render(view.eye), Frames.ned_to_render(view.at), Vector3.UP)
		var row := {complete = await _measure(), without = {}}
		if not report.has("memory"):
			# Godot's renderer estimates after the first complete frame; not vendor-measured residency.
			report["memory"] = {
				texture_bytes = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
				buffer_bytes = int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
				video_bytes = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
			}
		for sun: DirectionalLight3D in suns:
			sun.shadow_enabled = false
		row["without_sun_shadows"] = await _measure()
		for sun: DirectionalLight3D in suns:
			sun.shadow_enabled = true
		for name: String in groups:
			var hidden: Array[Node3D] = []
			for node: Node3D in groups[name]:
				if node.visible:
					node.visible = false
					hidden.append(node)
			row.without[name] = await _measure()
			for node: Node3D in hidden:
				node.visible = true
		row["complete_repeat"] = await _measure()
		report.views[view_name] = row
		print("ATTRIBUTED ", view_name)
	var file := FileAccess.open(out.path_join("attribution.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true) + "\n")
	file.close()
	print("ATTRIBUTION DONE ", out)
	quit(0)


## Named, disjoint subsystems: scenery children, other field layers and world-level lights/props.
func _groups(world: Node3D, field_node: Node3D, camera: Camera3D) -> Dictionary:
	var groups := {}
	for child: Node in world.get_children():
		if child == field_node or child == camera or not child is Node3D or child is DirectionalLight3D:
			continue
		if child is GeometryInstance3D or not (child as Node3D).find_children("*", "GeometryInstance3D", true, false).is_empty():
			_add(groups, "world_" + str(child.name).trim_prefix("@").get_slice("@", 0), child as Node3D)
	for child: Node in field_node.get_children():
		if str(child.name) == "Scenery":
			for scenery_child: Node in child.get_children():
				if not scenery_child is Node3D:
					continue
				var key := "scenery_" + str(scenery_child.name)
				for prefix: String in SCENERY_PATTERNS:
					if str(scenery_child.name).begins_with(prefix):
						key = SCENERY_PATTERNS[prefix]
				_add(groups, key, scenery_child as Node3D)
		elif child is Node3D:
			_add(groups, "field_" + str(child.name), child as Node3D)
		else:
			for grandchild: Node in child.get_children():
				if grandchild is Node3D:
					_add(groups, "field_" + str(child.name), grandchild as Node3D)
	return groups


func _add(groups: Dictionary, key: String, node: Node3D) -> void:
	if not groups.has(key):
		groups[key] = [] as Array[Node3D]
	(groups[key] as Array[Node3D]).append(node)


func _measure() -> Dictionary:
	for _index in 3:
		await RenderingServer.frame_post_draw
	return {
		draws = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		objects = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	}


## Full-detail triangles of every visible mesh/MultiMesh under the group (MultiMesh: visible
## instances), split by whether the mesh carries generated LODs, plus real-time shadow casters.
func _geometry(nodes: Array) -> Dictionary:
	var result := {source_triangles = 0, lod_triangles = 0, full_detail_triangles = 0, shadow_caster_triangles = 0,
		full_detail_meshes_over_5000 = []}
	for node: Node in nodes:
		var stack: Array[Node] = [node]
		while not stack.is_empty():
			var current: Node = stack.pop_back()
			stack.append_array(current.get_children())
			if not current is GeometryInstance3D or not (current as GeometryInstance3D).is_visible_in_tree():
				continue
			var mesh: Mesh = null
			var count := 1
			if current is MeshInstance3D:
				mesh = (current as MeshInstance3D).mesh
			elif current is MultiMeshInstance3D and (current as MultiMeshInstance3D).multimesh != null:
				var multimesh := (current as MultiMeshInstance3D).multimesh
				mesh = multimesh.mesh
				count = multimesh.instance_count if multimesh.visible_instance_count < 0 else multimesh.visible_instance_count
			if mesh == null:
				continue
			var triangles := count * Population.triangles(mesh)
			result.source_triangles += triangles
			if _has_lods(mesh):
				result.lod_triangles += triangles
			else:
				result.full_detail_triangles += triangles
				if triangles > 5000:
					(result.full_detail_meshes_over_5000 as Array).append("%s:%d" % [current.name, triangles])
			if (current as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				result.shadow_caster_triangles += triangles
	return result


func _has_lods(mesh: Mesh) -> bool:
	if not mesh is ArrayMesh or mesh.get_surface_count() == 0:
		return false
	return not (RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []) as Array).is_empty()
