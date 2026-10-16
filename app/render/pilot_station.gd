## L10b-R1: rear-open pilot station, fitted timber and powder-coated frame.
## Visual cue only. Envelope and fitting dimensions are artistic estimates.
extends RefCounted
const Frames = preload("res://render/frames.gd")
const Detail = preload("res://render/pilot_station_detail.gd")
const Finish = preload("res://render/pilot_station.gdshader")
const MAPS := {
	"wood_color": preload("res://assets/landscape/pilot-station/Wood050_1K-JPG_Color.jpg"),
	"wood_normal": preload("res://assets/landscape/pilot-station/Wood050_1K-JPG_NormalGL.jpg"),
	"wood_roughness": preload("res://assets/landscape/pilot-station/Wood050_1K-JPG_Roughness.jpg"),
	"concrete_color": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Color.jpg"),
	"concrete_normal": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_NormalGL.jpg"),
	"concrete_roughness": preload("res://assets/landscape/pilot-station/Concrete034_1K-JPG_Roughness.jpg"),
	"metal_normal": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_NormalGL.jpg"),
	"metal_roughness": preload("res://assets/landscape/pilot-station/Metal032_1K-JPG_Roughness.jpg"),
}

static func build(cue: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(cue.id)
	root.position = Frames.ned_to_render([cue.north, cue.east, 0.0])
	var kit := Detail.build(float(cue.width), float(cue.depth), float(cue.height))
	var material := ShaderMaterial.new()
	material.shader = Finish
	for channel: String in MAPS:
		material.set_shader_parameter(channel, MAPS[channel])
	var mesh := MeshInstance3D.new()
	mesh.name = "Station"
	mesh.mesh = kit.to_mesh(material)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	return root
