extends SceneTree
const Appearance := preload("res://appearance.gd")
func _initialize() -> void:
	var texture := load("res://livery.svg") as Texture2D
	var imported := texture.get_image()
	var runtime := Image.new()
	var error := runtime.load_svg_from_string(Appearance.SVG_SOURCE)
	imported.clear_mipmaps()
	runtime.convert(imported.get_format())
	var equal := error == OK and imported.get_size() == runtime.get_size() and imported.get_data() == runtime.get_data()
	print("SVG editor/runtime raster match: ", equal, " size=", runtime.get_size())
	quit(0 if equal else 1)
