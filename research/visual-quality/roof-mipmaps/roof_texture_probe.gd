## Read-only probe: imported format, mip count and CPU byte size of the roof material maps.
extends SceneTree

const PATHS := [
	"res://assets/landscape/building-roofs/roof_slates_03_diff_1k.jpg",
	"res://assets/landscape/building-roofs/roof_slates_03_nor_gl_1k.png",
	"res://assets/landscape/building-roofs/roof_slates_03_arm_1k.jpg",
	"res://assets/landscape/building-roofs/clay_roof_tiles_diff_1k.jpg",
	"res://assets/landscape/building-roofs/clay_roof_tiles_nor_gl_1k.png",
	"res://assets/landscape/building-roofs/clay_roof_tiles_arm_1k.jpg",
	"res://assets/landscape/pit-shelter/corrugated_iron_02_diff_2k.jpg",
	"res://assets/landscape/pit-shelter/corrugated_iron_02_nor_gl_2k.png",
	"res://assets/landscape/pit-shelter/corrugated_iron_02_arm_2k.jpg",
]


func _initialize() -> void:
	var rows := []
	var roof_bytes := 0
	for path: String in PATHS:
		var tex := load(path) as Texture2D
		var image := tex.get_image()
		var bytes := image.get_data_size()
		if path.contains("building-roofs"):
			roof_bytes += bytes
		rows.append({path = path, size = [image.get_width(), image.get_height()],
			format = image.get_format(), compressed = image.is_compressed(),
			mipmaps = image.get_mipmap_count(), bytes = bytes})
	print(JSON.stringify({rows = rows, roof_bytes = roof_bytes}, "  ", false))
	quit(0)
