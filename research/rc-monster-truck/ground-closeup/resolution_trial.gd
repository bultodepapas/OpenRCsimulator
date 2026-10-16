## Visual-only 4K source-map comparison. Uncompressed diagnostic textures, not a GPU-cost comparison.
extends "capture.gd"

func _apply_variant(activity) -> Dictionary:
	var result := super._apply_variant(activity)
	var source_root := ProjectSettings.globalize_path("res://../assets/landscape/rc-ground/source/")
	var files := {
		"rc_dirt_albedo": "dirt/dirt_diff_4k.jpg",
		"rc_dirt_normal": "dirt/dirt_nor_gl_4k.jpg",
		"rc_dirt_roughness": "dirt/dirt_rough_4k.jpg",
		"rc_grass_albedo": "ambientcg/Grass001_4K-JPG_Color.jpg",
		"rc_grass_normal": "ambientcg/Grass001_4K-JPG_NormalGL.jpg",
		"rc_grass_roughness": "ambientcg/Grass001_4K-JPG_Roughness.jpg",
	}
	var maps := {}
	var identities := {}
	for parameter: String in files:
		var path: String = source_root + str(files[parameter])
		var image := Image.load_from_file(path)
		if image == null or image.get_width() != 4096:
			return {"ok": false, "error": "Missing 4K source map: " + path}
		image.generate_mipmaps(parameter.ends_with("normal"))
		maps[parameter] = ImageTexture.create_from_image(image)
		identities[files[parameter]] = FileAccess.get_sha256(path)
	for node: Node in _walk(activity):
		if not node is MeshInstance3D or node.mesh == null: continue
		for surface_index in node.mesh.get_surface_count():
			var material := node.get_active_material(surface_index) as ShaderMaterial
			if material == null or material.shader.resource_path != "res://render/ground.gdshader": continue
			for parameter: String in maps: material.set_shader_parameter(parameter, maps[parameter])
	result["diagnostic_4k_uncompressed"] = identities
	return result
