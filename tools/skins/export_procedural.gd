## Export a verified runtime assembly with the same paint UVs used by ProceduralSkin.prepare.
## Run through tools/godot/run_checked.py with -- <family> <absolute-output.glb>.
extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const ProceduralSkin := preload("res://aircraft/procedural_skin.gd")
const TimberDetails := preload("res://aircraft/timber_visual_details.gd")
const TimberLighting := preload("res://aircraft/timber_visual_lighting.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ProceduralSkin.FAMILIES or not args[1].is_absolute_path() or not args[1].ends_with(".glb"):
		printerr("Usage: export_procedural.gd -- <family> <absolute-output.glb>")
		quit(2)
		return
	var family: String = args[0]
	var described: Dictionary = Registry.describe(family)
	if not described.get("ok", false):
		printerr("Model verification failed: ", described.get("errors", []))
		quit(1)
		return
	var manifest: Dictionary = described.manifest
	var builder := load(str(manifest.builder.script))
	var airplane: Dictionary = builder.call("build", manifest, "") if manifest.version == 2 else builder.call("build")
	var verified: Dictionary = Registry.validate_derived(manifest, airplane)
	if not verified.get("ok", false):
		printerr("Model bindings failed: ", verified.get("errors", []))
		if airplane.get("root") is Node: airplane.root.free()
		quit(1)
		return
	var root: Node3D = airplane.root
	if family == ProceduralSkin.TIMBER:
		if not TimberDetails.apply(root):
			printerr("Timber presentation details could not be prepared.")
			root.free()
			quit(1)
			return
		TimberLighting.apply(root)
	var adapted: Dictionary = ProceduralSkin.prepare(family, root)
	if not adapted.get("ok", false):
		printerr("Paint preparation failed: ", adapted.get("errors", []))
		root.free()
		quit(1)
		return
	if family != ProceduralSkin.STIK: _preview_materials(root, family)
	_owner(root, root)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var code := document.append_from_scene(root, state)
	if code == OK: code = document.write_to_filesystem(state, args[1])
	root.free()
	if code != OK:
		printerr("GLB export failed: ", code)
		quit(1)
		return
	print("EXPORT_OK ", family, " identity=", ProceduralSkin.identity(family), " surfaces=", adapted.surfaces, " path=", args[1])
	quit()


func _preview_materials(root: Node3D, family: String) -> void:
	# A neutral orientation template, not a bake of the procedural stock scheme.
	# The six subtly distinct fields correspond to the projection faces; UV reference
	# lines are emitted separately by the kit generator.
	var image := Image.create_empty(2048, 2048, false, Image.FORMAT_RGBA8)
	var colors := [Color("edf0f2"), Color("dde2e5"), Color("e8ecee"), Color("e2e7ea"), Color("f0f2f3"), Color("d9dfe2")]
	for face in 6:
		var left: int = (face % 3) * 2048 / 3
		var right: int = (face % 3 + 1) * 2048 / 3
		var top: int = (face / 3) * 1024
		image.fill_rect(Rect2i(left, top, right - left, 1024), colors[face])
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	var materials := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if node.mesh == null: continue
		for surface: int in node.mesh.get_surface_count():
			var original: Material = node.get_active_material(surface)
			if original == null or not original.resource_name.begins_with("openrc-paint"): continue
			var key := original.resource_name
			if not materials.has(key):
				var preview := StandardMaterial3D.new()
				preview.resource_name = key
				preview.albedo_texture = texture
				preview.albedo_color = Color.WHITE
				preview.roughness = 0.4
				if original is StandardMaterial3D:
					preview.roughness = original.roughness
					preview.metallic = original.metallic
				elif family == ProceduralSkin.P51:
					preview.metallic = float(original.get_shader_parameter("metallic_value"))
				else:
					preview.roughness = float(original.get_shader_parameter("roughness_value"))
				materials[key] = preview
			node.set_surface_override_material(surface, materials[key])


func _owner(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_owner(child, root)
