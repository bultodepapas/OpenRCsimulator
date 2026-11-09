extends SceneTree
const GroundFeatures := preload("res://scenery/ground_features.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const Scenery := preload("res://scenery/scenery.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Loader := preload("res://scenery/scenery_loader.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Ground := preload("res://render/ground.gd")
const WornGroundMaterial := preload("res://render/worn_ground_material.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	var k := MeshKit.new()
	k.box(Vector3.ONE, Vector3.ZERO, Color.WHITE)
	var start := k.cols.size()
	var poly := PackedVector2Array([Vector2(-3,-4), Vector2(3,-4), Vector2(3,4), Vector2(-3,4)])
	GroundFeatures.patch(k, poly, "gravel", "temperate", 17)
	var intact := true
	for i in start:
		intact = intact and k.cols[i].a == 1.0
	_check("existing cell geometry is not tagged as gravel", intact)
	var tagged := 0
	var feathered := 0
	var valid := true
	for i in range(start, k.cols.size()):
		valid = valid and k.cols[i].a >= 0.5 and k.cols[i].a <= 1.0
		if k.cols[i].a <= 0.501:
			tagged += 1
		elif k.cols[i].a < 0.99:
			feathered += 1
	_check("gravel interior and feathered shoulder carry bounded coverage", valid and tagged > 100 and feathered > 10)
	start = k.cols.size()
	GroundFeatures.track(k, PackedVector2Array([Vector2(10,0), Vector2(20,0)]), 2.0, "dirt", "temperate")
	for i in range(start, k.cols.size()):
		intact = intact and k.cols[i].a == 1.0
	_check("adjacent dirt track remains untagged", intact)
	ShaderClock.register()
	var field := FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var loaded := Loader.load_from(Loader.DEFAULT_PATH, field.field)
	_check("production field and scenery load", field.ok and loaded.ok)
	var node := Scenery.build(field.field, loaded.scenery, {theme = "", quality = "high", audio = false, birds = false})
	var batches := 0
	var cells := 0
	var surfaces_valid := true
	var worn_texture: Texture2D
	for child: Node in node.get_children():
		if child is MeshInstance3D and child.mesh != null and child.mesh.get_surface_count() > 0:
			if str(child.name).begins_with("cell_"):
				cells += 1
			var mat: Material = child.mesh.surface_get_material(0)
			if mat is ShaderMaterial and mat.shader == Scenery.GRAVEL_SHADER:
				worn_texture = mat.get_shader_parameter("worn_albedo") as Texture2D
				batches += 1
				surfaces_valid = surfaces_valid and child.mesh.get_surface_count() == 1
	_check("default scenery retains 60 nonempty cells and reports them accurately", cells == 60 and node.get_meta("stats").cells == cells)
	_check("detail uses existing flat single-surface batches", batches > 0 and surfaces_valid)
	_check("photographic path detail has real imported mipmaps", worn_texture != null
		and worn_texture.get_image().has_mipmaps())
	var detail: ShaderMaterial = node.get_meta(WornGroundMaterial.MATERIAL_META) as ShaderMaterial
	_check("standalone scenery keeps field-turf blending disabled", detail != null
		and detail.get_shader_parameter("field_turf_enabled") != true)
	var ground: ShaderMaterial = Ground.grass_material()
	ground.set_shader_parameter("tile_m", 2.375)
	ground.set_shader_parameter("macro_amp", 0.17)
	ground.set_shader_parameter("pilot_xz", Vector2(19, -7))
	_check("field turf binds to the existing scenery material", WornGroundMaterial.bind(node, ground))
	_check("shoulder shares the scene-owned grass and turf resources",
		detail.get_shader_parameter("grass") == ground.get_shader_parameter("grass")
		and detail.get_shader_parameter("turf_detail") == ground.get_shader_parameter("turf_detail"))
	_check("shoulder receives nondefault scale, macro and pilot values",
		detail.get_shader_parameter("tile_m") == 2.375 and detail.get_shader_parameter("macro_amp") == 0.17
		and detail.get_shader_parameter("pilot_xz") == Vector2(19, -7))
	if RenderingServer.shader_get_parameter_default(ground.shader.get_rid(), "anti_tiling") != null:
		_check("unset source parameters resolve to effective shader defaults",
			detail.get_shader_parameter("anti_tiling") == 1.0 and detail.get_shader_parameter("pilot_pin_m") == 35.0)
	else:
		_check("dummy renderer keeps shared shader defaults implicit",
			detail.get_shader_parameter("anti_tiling") == null and detail.get_shader_parameter("pilot_pin_m") == null)
	print("shoulder defaults: anti_tiling=", detail.get_shader_parameter("anti_tiling"),
		" pilot_pin_m=", detail.get_shader_parameter("pilot_pin_m"))
	_check("missing ground disables the shoulder and releases copied textures", not WornGroundMaterial.bind(node, null)
		and detail.get_shader_parameter("field_turf_enabled") == false
		and detail.get_shader_parameter("grass") == null
		and detail.get_shader_parameter("turf_detail") == null
		and detail.get_shader_parameter("rc_grass_albedo") == null)
	print("gravel flat batches: %d; cells: %d" % [batches, node.get_meta("stats").cells])
	node.free()
	print("landscape gravel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
