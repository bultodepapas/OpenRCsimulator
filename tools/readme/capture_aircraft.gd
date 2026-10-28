# Documentation-only studio renders of catalog models, not flight captures.
# Use a fresh absolute --out-dir; --stills-only skips animation frames.
# --aircraft=ID may be repeated or contain comma-separated IDs.
extends SceneTree

const Builder = preload("res://render/airplane.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const MT8 = preload("res://vehicles/ground/mt8_model.gd")
const Monster = preload("res://vehicles/ground/monster_car_2_model.gd")

const FRAME_COUNT: int = 72
const STILL_SIZE: Vector2i = Vector2i(1920, 1080)
const TOUR_SIZE: Vector2i = Vector2i(800, 450)
const BACKGROUND: Color = Color("111820")
const GROUND_IDS = ["mt8-bisonte", "monster-car-2"]
const STILL_FRACTION: float = 0.76 # 12% margin on each side.
const TOUR_FRACTION: float = 0.60 # Extra space for the tour's title and status.

var output: String = ""
var world: Node3D
var camera: Camera3D
var title: Label
var status: Label


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stills_only: bool = false
	var filtered: bool = false
	var requested: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir=") and output.is_empty():
			output = arg.trim_prefix("--out-dir=")
		elif arg == "--stills-only":
			stills_only = true
		elif arg.begins_with("--aircraft="):
			filtered = true
			var value: String = arg.trim_prefix("--aircraft=")
			if value.is_empty():
				push_error("Empty --aircraft selection")
				quit(1)
				return
			for item: String in value.split(",", true):
				var id: String = item.strip_edges()
				if id.is_empty():
					push_error("Empty ID in --aircraft selection")
					quit(1)
					return
				if not requested.has(id):
					requested.append(id)
		else:
			push_error("Unknown or repeated argument: " + arg)
			quit(1)
			return
	if output.is_empty() or not output.is_absolute_path():
		push_error("Provide an absolute --out-dir")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Studio captures require a rendered display")
		quit(1)
		return

	# Catalog order starts with the trainer. Add the separate ground-vehicle activity.
	var available: PackedStringArray = Catalog.flyable_ids()
	for id: String in GROUND_IDS:
		available.append(id)
	for id: String in requested:
		if not available.has(id):
			push_error("Unknown or unavailable vehicle: " + id)
			quit(1)
			return
	var selected: PackedStringArray = []
	for id: String in available:
		if not filtered or requested.has(id):
			selected.append(id)
	if selected.is_empty():
		push_error("No vehicles selected")
		quit(1)
		return
	if DirAccess.dir_exists_absolute(output):
		var existing: DirAccess = DirAccess.open(output)
		if existing == null or not existing.get_files().is_empty() or not existing.get_directories().is_empty():
			push_error("Use a fresh, empty --out-dir")
			quit(1)
			return
	elif DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create --out-dir")
		quit(1)
		return
	if not stills_only and DirAccess.make_dir_recursive_absolute(output.path_join("frames")) != OK:
		push_error("Cannot create animation frame directory")
		quit(1)
		return

	var source_start: Dictionary = _source_identity()
	if source_start.is_empty():
		push_error("Cannot record Git source identity")
		quit(1)
		return
	root.size = STILL_SIZE
	world = Node3D.new()
	root.add_child(world)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8c8c8")
	environment.ambient_light_energy = 0.45
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	_add_light(Vector3(-47, -32, -9), 0.90)
	_add_light(Vector3(-24, 145, 12), 0.38)
	_add_light(Vector3(48, -28, 0), 0.40)
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	world.add_child(camera)
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	title = Label.new()
	status = Label.new()
	canvas.add_child(title)
	canvas.add_child(status)

	var vehicles: Array[Dictionary] = []
	var global_frame: int = 0
	for id: String in selected:
		var entry: Dictionary = Catalog.entry(id)
		var model: Dictionary
		if id in GROUND_IDS:
			entry = {"id": id, "name": "Bisonte MT8" if id == "mt8-bisonte" else "MONSTER CAR 2", "status": "experimental"}
			model = MT8.build() if id == "mt8-bisonte" else Monster.build()
		else:
			model = Builder.build(id)
		if not model.get("root") is Node3D:
			push_error("Cannot build studio vehicle: " + id)
			quit(1)
			return
		var airplane: Node3D = model.root
		world.add_child(airplane)
		var bounds: AABB = _bounds(airplane, Transform3D.IDENTITY)
		var center: Vector3 = bounds.get_center()
		var extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if not is_finite(extent) or extent <= 0.0:
			push_error("Vehicle has no finite visible bounds: " + id)
			quit(1)
			return
		var vertices: Array[Vector3] = []
		var mesh_corners: Array[Vector3] = []
		_collect_geometry(airplane, Transform3D.IDENTITY, vertices, mesh_corners)
		if vertices.is_empty() or mesh_corners.is_empty():
			push_error("Vehicle has no visible mesh geometry: " + id)
			quit(1)
			return
		title.visible = false
		status.visible = false
		root.size = STILL_SIZE
		_aim(center, vertices, -42.0, STILL_FRACTION)
		var still: String = "%s.png" % id
		if not await _save(output.path_join(still), STILL_SIZE):
			quit(1)
			return
		var still_hash: String = FileAccess.get_sha256(output.path_join(still))
		if still_hash.is_empty():
			push_error("Cannot hash still: " + id)
			quit(1)
			return
		if not stills_only:
			root.size = TOUR_SIZE
			title.text = str(entry.name)
			title.position = Vector2(22, 17)
			title.add_theme_font_size_override("font_size", 26)
			title.add_theme_color_override("font_color", Color("f3f6f8"))
			status.text = {"flyable": "FLYABLE · flight model under evaluation", "experimental": "EXPERIMENTAL · physical validation pending", "preview": "VISUAL PREVIEW · Fly disabled"}.get(str(entry.status), str(entry.status))
			status.position = Vector2(22, 53)
			status.add_theme_font_size_override("font_size", 15)
			status.add_theme_color_override("font_color", Color("a9bac9"))
			title.visible = true
			status.visible = true
			for frame: int in range(FRAME_COUNT):
				var angle: float = -42.0 + 360.0 * float(frame) / float(FRAME_COUNT)
				_aim(center, mesh_corners, angle, TOUR_FRACTION)
				if not await _save(output.path_join("frames/%03d.png" % global_frame), TOUR_SIZE):
					quit(1)
					return
				global_frame += 1
		var data_path: String = str(entry.get("data", ""))
		vehicles.append({
			"id": id, "name": str(entry.name), "status": str(entry.status),
			"visual_family": str(entry.get("visual_family", id)),
			"model_manifest_sha256": str(model.get("model_manifest_sha256", "")),
			"aircraft_data_sha256": FileAccess.get_sha256(data_path) if not data_path.is_empty() else "",
			"bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z],
				"size": [bounds.size.x, bounds.size.y, bounds.size.z]},
			"still": still, "still_sha256": still_hash, "frames": 0 if stills_only else FRAME_COUNT
		})
		airplane.queue_free()
		await process_frame

	var source_end: Dictionary = _source_identity()
	if source_end.is_empty():
		push_error("Cannot record final Git source identity")
		quit(1)
		return
	var file: FileAccess = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write render manifest")
		quit(1)
		return
	file.store_string(JSON.stringify({
		"format": "openrc-readme-renders v2",
		"captured_utc": Time.get_datetime_string_from_system(true, false) + "Z",
		"engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"source_start": source_start, "source_end": source_end,
		"source_changed_during_capture": source_start != source_end,
		"purpose": "Studio model presentation; not gameplay or flight validation",
		"background": "#111820", "stills_size": [STILL_SIZE.x, STILL_SIZE.y],
		"tour_size": [TOUR_SIZE.x, TOUR_SIZE.y], "frame_count": global_frame,
		"vehicles": vehicles
	}, "\t") + "\n")
	file.close()
	print("README_RENDER_OK: %d vehicles, %d animation frames" % [vehicles.size(), global_frame])
	quit(0)


# Git identifies tracked changes in the capture-relevant trees. Untracked paths are
# listed in status, but their contents are not covered by the tracked diff hash.
func _source_identity() -> Dictionary:
	var repo: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var head: Array = []
	var state: Array = []
	var diff: Array = []
	if OS.execute("git", ["-C", repo, "rev-parse", "HEAD"], head, true) != 0:
		return {}
	if OS.execute("git", ["-C", repo, "status", "--porcelain=v1", "--untracked-files=all", "--", "app", "assets", "tools/readme"], state, true) != 0:
		return {}
	if OS.execute("git", ["-C", repo, "diff", "--binary", "--no-ext-diff", "HEAD", "--", "app", "assets", "tools/readme"], diff, true) != 0:
		return {}
	var commit: String = str(head[0]).strip_edges()
	if commit.is_empty():
		return {}
	var status_text: String = str(state[0]) if not state.is_empty() else ""
	var diff_text: String = str(diff[0]) if not diff.is_empty() else ""
	return {
		"commit": commit, "scope": ["app", "assets", "tools/readme"],
		"worktree_status": status_text, "tracked_diff_sha256": diff_text.sha256_text(),
		"untracked_contents_hashed": false,
		"capture_tool_sha256": FileAccess.get_sha256(repo.path_join("tools/readme/capture_aircraft.gd")),
		"catalog_sha256": FileAccess.get_sha256("res://app_state/aircraft_catalog.gd"),
		"builder_sha256": FileAccess.get_sha256("res://render/airplane.gd")
	}


func _add_light(angles: Vector3, energy: float) -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_energy = energy
	world.add_child(light)


func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform
	var result: AABB = AABB()
	if node is MeshInstance3D and node.visible and node.mesh != null:
		result = transform * node.get_aabb()
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			var child_bounds: AABB = _bounds(child, transform)
			if child_bounds.size.length_squared() > 0.0:
				result = child_bounds if result.size.length_squared() == 0.0 else result.merge(child_bounds)
	return result


func _collect_geometry(node: Node3D, parent_transform: Transform3D, vertices: Array[Vector3], mesh_corners: Array[Vector3]) -> void:
	var transform: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D and node.visible and node.mesh != null:
		var corners: Array[Vector3] = []
		for corner: int in range(8):
			corners.append(transform * node.get_aabb().get_endpoint(corner))
		mesh_corners.append_array(corners)
		var start_count: int = vertices.size()
		for surface: int in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					vertices.append(transform * vertex)
		# A mesh without readable vertices still gets a conservative bounding box.
		if vertices.size() == start_count:
			vertices.append_array(corners)
	for child: Node in node.get_children():
		if child is Node3D and child.visible:
			_collect_geometry(child, transform, vertices, mesh_corners)


# Fit the projected geometry, rather than scaling by the longest world axis.
# Intersect the allowable camera-centre intervals for every vertex. This keeps
# each point inside the requested fraction of both axes, including perspective.
func _aim(center: Vector3, points: Array[Vector3], azimuth: float, fraction: float) -> void:
	var az: float = deg_to_rad(azimuth)
	var elevation: float = deg_to_rad(22.0)
	var outward: Vector3 = Vector3(sin(az) * cos(elevation), sin(elevation), -cos(az) * cos(elevation)).normalized()
	var right: Vector3 = Vector3.UP.cross(outward).normalized()
	var up: Vector3 = outward.cross(right).normalized()
	var vertical: float = tan(deg_to_rad(camera.fov) * 0.5) * fraction
	var horizontal: float = vertical * float(STILL_SIZE.x) / float(STILL_SIZE.y)
	var max_right: float = -INF
	var min_right: float = INF
	var max_up: float = -INF
	var min_up: float = INF
	var max_depth: float = -INF
	for point: Vector3 in points:
		var relative: Vector3 = point - center
		var x: float = relative.dot(right)
		var y: float = relative.dot(up)
		var depth: float = relative.dot(outward)
		max_right = maxf(max_right, x + horizontal * depth)
		min_right = minf(min_right, x - horizontal * depth)
		max_up = maxf(max_up, y + vertical * depth)
		min_up = minf(min_up, y - vertical * depth)
		max_depth = maxf(max_depth, depth)
	var distance: float = maxf((max_right - min_right) / (2.0 * horizontal), (max_up - min_up) / (2.0 * vertical))
	distance = maxf(distance, max_depth + camera.near + 0.01)
	var target: Vector3 = center + right * (max_right + min_right) * 0.5 + up * (max_up + min_up) * 0.5
	camera.look_at_from_position(target + outward * distance, target)


func _save(path: String, expected: Vector2i) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.get_size() != expected:
		push_error("Unexpected capture dimensions for " + path)
		return false
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("Cannot save %s: %s" % [path, error_string(error)])
		return false
	return true
