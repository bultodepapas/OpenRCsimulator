extends RefCounted
## Fixed-eye flight presentation for the versioned manual calibrations.

const Frames := preload("res://render/frames.gd")
const Panorama := preload("res://landscapes/phoenix_flight.gdshader")


static func build(field: Dictionary, calibration: Dictionary, images: Array) -> Node3D:
	var site := Node3D.new()
	site.name = "Field"
	var photo := MeshInstance3D.new()
	photo.name = "ImportedPanorama"
	var shell := SphereMesh.new()
	shell.radius = 8192.0
	shell.height = shell.radius * 2.0
	shell.radial_segments = 24
	shell.rings = 12
	photo.mesh = shell
	photo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = Panorama
	for index in images.size():
		material.set_shader_parameter("panel_%d" % (index + 1), ImageTexture.create_from_image(images[index]))
	material.set_shader_parameter("panorama_yaw", deg_to_rad(float(calibration.yaw_deg)))
	photo.material_override = material
	photo.position = Frames.ned_to_render([field.pilot.north, field.pilot.east,
		field.pilot.down - field.pilot.eye_height])
	site.add_child(photo)
	return site
