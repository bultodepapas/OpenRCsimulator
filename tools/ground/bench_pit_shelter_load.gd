extends SceneTree

const Scenery = preload("res://scenery/scenery.gd")

func _initialize() -> void:
	var files := [
		"res://assets/landscape/pit-shelter/corrugated_iron_02_diff_2k.jpg",
		"res://assets/landscape/pit-shelter/corrugated_iron_02_nor_gl_2k.png",
		"res://assets/landscape/pit-shelter/corrugated_iron_02_arm_2k.jpg",
		"res://assets/landscape/flightline/Wood049_1K-JPG_Color.jpg",
		"res://assets/landscape/flightline/Wood049_1K-JPG_NormalGL.jpg",
		"res://assets/landscape/flightline/Wood049_1K-JPG_Roughness.jpg",
	]
	var resources: Array[Resource] = []
	for file: String in files:
		var started := Time.get_ticks_usec()
		var resource: Resource = load(file)
		if resource == null:
			push_error("Missing shelter texture: " + file)
			quit(1)
			return
		resources.append(resource)
		print(file.get_file(), ": ", float(Time.get_ticks_usec() - started) / 1000.0, " ms")
	var started := Time.get_ticks_usec()
	var material := Scenery.pit_shelter_material()
	print("material with cached textures: ", float(Time.get_ticks_usec() - started) / 1000.0, " ms ", material != null)
	quit()
