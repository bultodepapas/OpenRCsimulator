extends SceneTree

const STEMS := ["stik_assembled", "stik_service", "extra_assembled", "p51_assembled", "avanti_assembled", "timber_assembled"]
const PREFIX := "res://assets/scenery/aircraft/"
var failures := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var pack_path := ProjectSettings.globalize_path("res://fleet.pck")
	if not args.is_empty():
		var packer := PCKPacker.new()
		check(packer.pck_start(pack_path) == OK, "start isolated pack")
		for stem: String in STEMS:
			for extension: String in [".json", ".res"]:
				var name := stem + extension
				check(packer.add_file(PREFIX + name, args[0].path_join(name)) == OK, "pack " + name)
		check(packer.flush() == OK, "flush isolated pack")
		quit(failures)
		return
	check(ProjectSettings.load_resource_pack(pack_path), "mount isolated pack")
	for stem: String in STEMS:
		var path := PREFIX + stem + ".res"
		var mesh := load(path) as ArrayMesh
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(PREFIX + stem + ".json"))
		check(mesh != null and info is Dictionary, "mesh and metadata load " + stem)
		if mesh == null:
			continue
		check(ResourceLoader.get_dependencies(path).is_empty(), "mesh is self-contained " + stem)
		check(absf(mesh.get_aabb().position.y) < 0.002, "grounded visible geometry " + stem)
		for surface: int in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface)
			check(mat != null, "material " + stem + ":" + str(surface))
			if mat == null:
				continue
			for property: Dictionary in mat.get_property_list():
				if int(property.type) != TYPE_OBJECT:
					continue
				var value: Variant = mat.get(str(property.name))
				if value is Texture2D:
					var pixels: Image = value.get_image()
					check(pixels != null and not pixels.is_empty(), "texture " + stem + ":" + str(surface) + ":" + str(property.name))
	print("isolated parked resource pack: %d failures" % failures)
	quit(failures)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL " + label)
