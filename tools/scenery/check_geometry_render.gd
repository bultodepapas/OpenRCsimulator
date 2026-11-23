## Compare the production planted hedge with its original square card on the same renderer.
extends SceneTree

const Hedge := preload("res://scenery/imported_hedge.gd")
const TILE := 192
const MIN_FOLIAGE_PIXELS := 64
# Allow one alpha-test boundary sample and two 8-bit levels of interpolation rounding.
const MAX_MASK_DIFFERENCE := 1
const MAX_CHANNEL_DIFFERENCE := 2
const ATLAS := "res://assets/landscape/vegetation/impostors/bush_common_flowers_4view"
const SHADER_PATH := "res://assets/landscape/vegetation/impostors/bush_common_4view.gdshader"
const FRAME_COLORS := [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]

var _viewport: SubViewport
var _camera: Camera3D
var _cards: MultiMeshInstance3D
var _batch: MultiMesh
var _candidate_mesh: Mesh
var _candidate_bounds: AABB
var _quad: QuadMesh
var _reference_bounds: AABB
var _origin: Vector3
var _span: float
var _yaw: float


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].begins_with("--out="):
		printerr("Expected --out=/absolute/new/directory")
		quit(2)
		return
	var out := args[0].trim_prefix("--out=")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_video_adapter_name().is_empty():
		printerr("Hedge geometry comparison requires a rendering display")
		quit(2)
		return
	if not out.is_absolute_path() or DirAccess.make_dir_absolute(out) != OK:
		printerr("Hedge output must be a new directory inside an existing parent: ", out)
		quit(2)
		return
	if not _build_scene():
		printerr("Expected one production planted hedge card with a valid square atlas frame")
		quit(1)
		return

	var reference_sheet := Image.create_empty(TILE * 2, TILE * 5, false, Image.FORMAT_RGBA8)
	var candidate_sheet := Image.create_empty(TILE * 2, TILE * 5, false, Image.FORMAT_RGBA8)
	var cropped_image: Image
	var culled_image: Image
	var negative := {}
	var culling_negative := {}
	var case_ids := PackedStringArray()
	var cases: Array[Dictionary] = []
	var production_material := _cards.material_override as ShaderMaterial
	var label_material := production_material.duplicate() as ShaderMaterial
	var label_atlas := Image.create_empty(64, 16, false, Image.FORMAT_RGBA8)
	for frame_index in 4:
		label_atlas.fill_rect(Rect2i(frame_index * 16, 0, 16, 16), FRAME_COLORS[frame_index])
	label_material.set_shader_parameter("impostor_atlas", ImageTexture.create_from_image(label_atlas))
	var passed := true
	for index in 10:
		var frame := index / 2 if index < 8 else 0
		var high := index % 2 == 1 if index < 8 else true
		var edge := "" if index < 8 else ("left" if index == 8 else "right")
		var id := "frame%d-%s" % [frame, "high" if high else "low"] if edge.is_empty() else "edge-" + edge
		_aim(frame, high, edge)
		var reference := await _capture(_quad, _reference_bounds)
		var candidate := await _capture(_candidate_mesh, _candidate_bounds)
		if reference == null or candidate == null:
			printerr("Missing hedge viewport image for ", id)
			quit(1)
			return
		var row := _compare(reference, candidate, edge)
		row.merge({id = id, frame = frame, elevation_degrees = 62 if high else 8, edge = edge})
		# A frame-labelled atlas on the same shader detects even a cyclic permutation of four distinct views.
		_cards.material_override = label_material
		var labelled := await _capture(_quad, _reference_bounds)
		_cards.material_override = production_material
		row.observed_frame = _read_frame(labelled, row.reference_probe_pixel)
		row.passed = row.passed and row.observed_frame == frame
		case_ids.append(id)
		cases.append(row)
		passed = passed and row.passed
		var sheet_offset := Vector2i(index % 2, index / 2) * TILE
		reference_sheet.blit_rect(reference, Rect2i(0, 0, TILE, TILE), sheet_offset)
		candidate_sheet.blit_rect(candidate, Rect2i(0, 0, TILE, TILE), sheet_offset)
		if index == 0:
			cropped_image = await _capture(_cropped_quad(), _reference_bounds)
			if cropped_image == null:
				quit(1)
				return
			negative = _compare(reference, cropped_image, "")
			negative.id = "cropped-card"
			negative.rejected = not negative.passed and negative.lost_reference_pixels >= MIN_FOLIAGE_PIXELS
			passed = passed and negative.rejected
		if edge == "left":
			# This box is wholly outside the frustum while the visible canopy still intersects it.
			var radius := _span * 0.005
			var tiny := AABB(_origin - Vector3.ONE * radius, Vector3.ONE * (radius * 2.0))
			culled_image = await _capture(_candidate_mesh, tiny)
			if culled_image == null:
				quit(1)
				return
			culling_negative = _compare(reference, culled_image, edge)
			culling_negative.id = "undersized-aabb"
			culling_negative.case_id = id
			culling_negative.rejected = not culling_negative.passed and culling_negative.candidate_pixels == 0 \
				and culling_negative.lost_reference_pixels >= MIN_FOLIAGE_PIXELS
			passed = passed and culling_negative.rejected

	var images := {}
	for entry in [["reference.png", reference_sheet], ["candidate.png", candidate_sheet],
			["cropped.png", cropped_image], ["culled.png", culled_image]]:
		var target := out.path_join(str(entry[0]))
		var picture: Image = entry[1]
		if picture.save_png(target) != OK:
			printerr("Could not save ", target)
			quit(1)
			return
		images[entry[0]] = FileAccess.get_sha256(target)
	var sources := {"tools/scenery/check_geometry_render.gd": FileAccess.get_sha256(get_script().resource_path)}
	for resource_path: String in ["res://scenery/imported_hedge.gd", SHADER_PATH, ATLAS + ".png", ATLAS + ".png.import", ATLAS + ".json"]:
		sources["app/" + resource_path.trim_prefix("res://")] = FileAccess.get_sha256(resource_path)
	for hash_value: String in sources.values():
		passed = passed and hash_value.length() == 64
	var report := {format = "openrc-hedge-render-v1", passed = passed, case_ids = case_ids, cases = cases,
		negative = negative, culling_negative = culling_negative, images = images, sources_sha256 = sources,
		engine = Engine.get_version_info().string,
		material = {shader = production_material.shader.resource_path,
			atlas = production_material.get_shader_parameter("impostor_atlas").resource_path,
			atlas_frames = production_material.get_shader_parameter("atlas_frames"),
			alpha_cutoff = production_material.get_shader_parameter("alpha_cutoff")},
		renderer = RenderingServer.get_current_rendering_method(), adapter = RenderingServer.get_video_adapter_name(),
		tile_pixels = TILE, max_mask_difference = MAX_MASK_DIFFERENCE, max_common_channel_difference = MAX_CHANNEL_DIFFERENCE}
	var file := FileAccess.open(out.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		printerr("Could not write hedge geometry summary")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	if passed:
		print("HEDGE_GEOMETRY_RENDER verdict=pass cases=10 negative=2")
	else:
		printerr("Hedge geometry comparison failed. See ", out.path_join("summary.json"))
	quit(0 if passed else 1)


func _build_scene() -> bool:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(TILE, TILE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var points: Array[Vector2] = [Vector2.ZERO, Vector2(0.4, 0.0)]
	var hedge := Hedge.build(points, 1.6, 0.0, 31, "high", false, true)
	_viewport.add_child(hedge)
	_cards = hedge.get_node_or_null("Bush_Common_Flowers_4View") as MultiMeshInstance3D
	if _cards == null or _cards.multimesh.instance_count != 1 or not _cards.material_override is ShaderMaterial:
		return false
	var material := _cards.material_override as ShaderMaterial
	var atlas := material.get_shader_parameter("impostor_atlas") as Texture2D
	var cutoff: Variant = material.get_shader_parameter("alpha_cutoff")
	if material.shader == null or material.shader.resource_path != SHADER_PATH or atlas == null \
			or atlas.resource_path != ATLAS + ".png" or material.get_shader_parameter("atlas_frames") != 4.0 \
			or typeof(cutoff) != TYPE_FLOAT or not is_equal_approx(float(cutoff), 0.32):
		printerr("Production hedge shader, bound atlas or sampling parameters differ from the source fixture")
		return false
	_batch = _cards.multimesh
	_candidate_mesh = _batch.mesh
	_candidate_bounds = _batch.custom_aabb
	if _candidate_mesh.get_surface_count() != 1 or _candidate_mesh.surface_get_array_len(0) != 3:
		return false
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(ATLAS + ".json"))
	if not manifest is Dictionary or manifest.get("frame_world_size_m", []).size() != 2:
		return false
	var frame_size := float(manifest.frame_world_size_m[0])
	if frame_size <= 0.0 or frame_size != float(manifest.frame_world_size_m[1]):
		return false
	_quad = QuadMesh.new()
	_quad.size = Vector2.ONE * frame_size
	# CPU placement records drive the production instance transform and custom-data yaw.
	var placements: Array = hedge.get_meta("cpu_placements")
	if placements.size() != 1:
		return false
	var transform: Transform3D = placements[0].transform
	_span = frame_size * transform.basis.x.length()
	_origin = transform.origin
	_yaw = float(placements[0].yaw_rad)
	# Keep the independently constructed reference visible even if the candidate bounds are wrong.
	_reference_bounds = AABB(_origin - Vector3.ONE * _span * 4.0, Vector3.ONE * _span * 8.0)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.current = true
	_camera.set_orthogonal(_span * 1.15, 0.05, _span * 30.0)
	return _span > 0.0


func _aim(frame: int, high: bool, edge: String) -> void:
	# The production shader rounds -(atan(z,x) + instance_yaw) to the nearest atlas quarter.
	var azimuth := -frame * PI * 0.5 - _yaw
	var elevation := deg_to_rad(62.0 if high else 8.0)
	var direction := Vector3(cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation))
	_camera.position = _origin + direction * _span * 8.0
	_camera.look_at(_origin)
	if not edge.is_empty():
		# Keep part of the foliage visible while its centre and the deliberately tiny box are outside.
		var shift := _camera.size * 0.5 + _span * 0.12
		_camera.position += _camera.basis.x * shift * (1.0 if edge == "left" else -1.0)


func _capture(mesh: Mesh, bounds: AABB) -> Image:
	_batch.mesh = mesh
	_batch.custom_aabb = bounds
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	if image == null or image.get_size() != Vector2i(TILE, TILE):
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _cropped_quad() -> ArrayMesh:
	# Keep the original position-to-UV map and physically remove the right half of the card.
	var arrays := _quad.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in uvs.size():
		uvs[i].x *= 0.5
		vertices[i].x = (uvs[i].x - 0.5) * _quad.size.x
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _read_frame(image: Image, pixel: int) -> int:
	if image == null or pixel < 0:
		return -1
	var color := image.get_pixel(pixel % TILE, pixel / TILE)
	var rgb := Vector3(color.r, color.g, color.b)
	if color.a == 0.0 or rgb.is_zero_approx():
		return -1
	var observed := rgb.normalized()
	for i in 4:
		var label: Color = FRAME_COLORS[i]
		if observed.distance_to(Vector3(label.r, label.g, label.b).normalized()) < 0.1:
			return i
	return -1


static func _compare(reference: Image, candidate: Image, edge: String) -> Dictionary:
	var a := reference.get_data()
	var b := candidate.get_data()
	var reference_pixels := 0
	var candidate_pixels := 0
	var lost := 0
	var added := 0
	var border_pixels := 0
	var greatest := 0
	var probe_pixel := -1
	for i in range(0, a.size(), 4):
		var ref_visible := a[i + 3] > 0
		var new_visible := b[i + 3] > 0
		if ref_visible:
			if probe_pixel == -1:
				probe_pixel = i / 4
			reference_pixels += 1
			var x := (i / 4) % TILE
			if (edge == "left" and x == 0) or (edge == "right" and x == TILE - 1):
				border_pixels += 1
		if new_visible:
			candidate_pixels += 1
		if ref_visible and new_visible:
			for channel in 4:
				greatest = maxi(greatest, absi(int(a[i + channel]) - int(b[i + channel])))
		elif ref_visible:
			lost += 1
		elif new_visible:
			added += 1
	var passed := reference_pixels >= MIN_FOLIAGE_PIXELS and candidate_pixels >= MIN_FOLIAGE_PIXELS \
		and (edge.is_empty() or border_pixels > MAX_MASK_DIFFERENCE) \
		and lost + added <= MAX_MASK_DIFFERENCE and greatest <= MAX_CHANNEL_DIFFERENCE
	return {reference_pixels = reference_pixels, candidate_pixels = candidate_pixels, reference_border_pixels = border_pixels,
		reference_probe_pixel = probe_pixel, lost_reference_pixels = lost, added_pixels = added,
		max_common_channel_difference = greatest, passed = passed}
