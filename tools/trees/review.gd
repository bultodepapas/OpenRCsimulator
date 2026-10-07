# Run with Godot --path app --script <absolute tools/trees/review.gd> -- <output dir>
extends SceneTree
const Loader = preload("res://data/field_loader.gd")
const Field = preload("res://render/field.gd")
const Trees = preload("res://render/treeline.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Clock = preload("res://render/shader_clock.gd")
const HASH_COLUMNS: int = 32
const HASH_VIEW_WIDTH_PX: int = 1280
const HASH_VIEW_HEIGHT_PX: int = 1080
var viewport: SubViewport
var camera: Camera3D
var grove: Node3D
var out: String
var report: Dictionary = {format = "openrc-l7-forest-review v1", views = [], hash_samples = []}
var failed: bool = false

func _initialize() -> void:
	call_deferred("run")

func settle() -> void:
	for _frame: int in 4:
		await process_frame
		await RenderingServer.frame_post_draw

func counts() -> Dictionary:
	var result: Dictionary = {}
	for kind: int in [RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]:
		result["visible" if kind == 0 else "shadow"] = RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(), kind, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return result

func view(label: String, position: Vector3, target: Vector3, up: Vector3 = Vector3.UP) -> void:
	camera.look_at_from_position(position, target, up)
	grove.visible = false
	await settle()
	var base: Dictionary = counts()
	grove.visible = true
	await settle()
	var actual: Dictionary = counts()
	var draws: int = actual.visible - base.visible
	var shadows: int = actual.shadow - base.shadow
	failed = failed or draws < 0 or draws > 24 or shadows != 0
	var path: String = out.path_join(label + ".png")
	failed = failed or viewport.get_texture().get_image().save_png(path) != OK
	report.views.append({id = label, baseline = base, trees = actual, vegetation_visible_draws = draws, vegetation_shadow_draws = shadows, sha256 = FileAccess.get_sha256(path)})

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	Clock.register()
	Clock.update(1.5)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage: Node3D = Node3D.new()
	viewport.add_child(stage)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Atmosphere.environment()
	Atmosphere.update_clouds(world.environment, 1.5)
	stage.add_child(world)
	var sun: DirectionalLight3D = Atmosphere.create_sun(stage)
	var loaded: Dictionary = Loader.load_from()
	if not loaded.ok:
		printerr(loaded.errors)
		quit(1)
		return
	var field: Node3D = Field.build(loaded.field)
	stage.add_child(field)
	grove = field.get_node("treeline")
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 25000.0
	stage.add_child(camera)
	camera.current = true
	for az: int in [0, 90, 180, 270]:
		for elevation: int in [0, 10]:
			var direction: Vector3 = Vector3(sin(deg_to_rad(az)) * cos(deg_to_rad(elevation)), sin(deg_to_rad(elevation)), -cos(deg_to_rad(az)) * cos(deg_to_rad(elevation)))
			var eye: Vector3 = Vector3(0, 1.7, 0)
			await view("az%03d-el%02d" % [az, elevation], eye, eye + direction)
	for az: int in [30, 210]:
		camera.fov = 20.0
		await view("gap%03d" % az, Vector3(0, 1.7, 0), Vector3(sin(deg_to_rad(az)) * 400, 1.7, -cos(deg_to_rad(az)) * 400))
	camera.fov = 70.0
	await view("overhead", Vector3(0, 1400, 0), Vector3.ZERO, Vector3.FORWARD)
	failed = failed or report.views[-1].vegetation_visible_draws != 8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2000.0
	await view("engine-shadow-audit", Vector3(0, 1.7, 0), Vector3(0, 1.7, -1))
	stage.free()
	await hash_probe(loaded.field.objects[0].positions)
	report.adapter = RenderingServer.get_video_adapter_name()
	report.api = RenderingServer.get_video_adapter_api_version()
	report.godot = Engine.get_version_info().string
	report.field_sha256 = FileAccess.get_sha256(Loader.DEFAULT_PATH)
	report.complete = not failed
	var file: FileAccess = FileAccess.open(out.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true) + "\n")
	file.close()
	viewport.free()
	print("L7 GPU review complete: ", not failed)
	quit(1 if failed else 0)

func hash_probe(positions: Array) -> void:
	# Use the exact shared shader function with the actual MultiMesh float32 custom-data path.
	var rows: int = int(ceil(float(positions.size()) / float(HASH_COLUMNS)))
	viewport.size = Vector2i(HASH_VIEW_WIDTH_PX, HASH_VIEW_HEIGHT_PX)
	var stage: Node3D = Node3D.new()
	viewport.add_child(stage)
	var shader: Shader = Shader.new()
	shader.code = 'shader_type spatial; render_mode unshaded;\n#include "res://render/tree_identity.gdshaderinc"\nvarying flat uint bits;\nvoid vertex(){vec3 id=tree_identity(tree_position(INSTANCE_CUSTOM));bits=uint(id.x)|(uint(round(id.y*1024.0))<<2u)|(uint(round(id.z*4096.0))<<17u); }\nvoid fragment(){uint bit=uint(min(int(UV.x*8.0),7)+min(int(UV.y*4.0),3)*8); ALBEDO=vec3(float((bits>>bit)&1u));}'
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = material
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = positions.size()
	for index: int in positions.size():
		var column: int = index % HASH_COLUMNS
		var row: int = int(index / HASH_COLUMNS)
		var cell_y: float = float(rows - 1) * 0.5 - float(row)
		mm.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(float(column) - 15.5, cell_y, 0.0)))
		var point: Array = positions[index]
		mm.set_instance_custom_data(index, Trees.packed_position(point[0], point[1]))
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = mm
	stage.add_child(instance)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(rows + 4) # One metre cells with four rows of vertical margin.
	stage.add_child(camera)
	camera.position = Vector3(0, 0, 10)
	camera.current = true
	await settle()
	var picture: Image = viewport.get_texture().get_image()
	failed = failed or picture.save_png(out.path_join("hash-probe.png")) != OK
	var pixels_per_cell: float = float(HASH_VIEW_HEIGHT_PX) / camera.size
	for index: int in positions.size():
		var p: Array = positions[index]
		var expected: Dictionary = Trees.identity(p[0], p[1])
		var bits: int = 0
		for bit: int in 32:
			var column: int = index % HASH_COLUMNS
			var row: int = int(index / HASH_COLUMNS)
			var cell_left: float = float(HASH_VIEW_WIDTH_PX) * 0.5 + (float(column) - 16.0) * pixels_per_cell
			var cell_top: float = float(HASH_VIEW_HEIGHT_PX) * 0.5 + (float(row) - float(rows) * 0.5) * pixels_per_cell
			var x: int = int(floor(cell_left + (float(bit % 8) + 0.5) * pixels_per_cell / 8.0))
			var y: int = int(floor(cell_top + (float(bit / 8) + 0.5) * pixels_per_cell / 4.0))
			if picture.get_pixel(x, y).r > 0.5:
				bits |= 1 << bit
		var species: int = bits & 3
		var height_error: float = absf(float((bits >> 2) & 32767) / 1024.0 - float(expected.height))
		var yaw_error: float = absf(float((bits >> 17) & 32767) / 4096.0 - float(expected.yaw))
		failed = failed or species != int(expected.species) or height_error > 1.0 / 1024.0 or yaw_error > 1.0 / 4096.0
		var zone: String = "near" if Vector2(p[0], p[1]).length() <= 600.0 else "far"
		report.hash_samples.append({north = p[0], east = p[1], zone = zone,
			species_matches = species == int(expected.species), height_error_m = height_error, yaw_error_rad = yaw_error})
	stage.free()
