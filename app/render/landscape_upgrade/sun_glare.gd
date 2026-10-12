## LU-04: scene-local optical glare. Opaque depth resolves the disc, including the flown aircraft.
## Uses the actual sky material and exposure, so FW flow and TOD edits cannot leave stale solar inputs.
extends MeshInstance3D

const Options := preload("res://render/landscape_upgrade/options.gd")
const GLARE_SHADER := preload("res://render/landscape_upgrade/sun_glare.gdshader")
var environment: Environment
var intensity := 1.0
var _material: ShaderMaterial

static func attach(parent: Node, env: Environment) -> MeshInstance3D:
	var script: GDScript = load("res://render/landscape_upgrade/sun_glare.gd")
	var node: MeshInstance3D = script.new()
	node.name = "SunGlare"
	node.environment = env
	node.intensity = Options.glare_strength()
	parent.add_child(node)
	return node

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = GLARE_SHADER
	_material.render_priority = 110
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ignore_occlusion_culling = true
	custom_aabb = AABB(Vector3(-100000, -100000, -100000), Vector3(200000, 200000, 200000))
	_process(0.0)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or environment == null or environment.sky == null:
		visible = false
		return
	var sky := environment.sky.sky_material as ShaderMaterial
	if sky == null:
		visible = false
		return
	# The visible solar disc and optical glare share cloud attenuation and apparent position.
	if not sky.get_shader_parameter("disc_cloud_occlusion"):
		sky.set_shader_parameter("disc_cloud_occlusion", true)
	var source: Vector3 = sky.get_shader_parameter("disc_dir") if sky.get_shader_parameter("disc_cloud_occlusion") else sky.get_shader_parameter("sun_dir")
	var disc: float = float(sky.get_shader_parameter("sun_disc"))
	var forward := -camera.global_basis.z
	visible = intensity > 0.0 and disc > 0.0 and source.y > -0.005 and forward.dot(source) > 0.15
	if not visible:
		return
	var size := get_viewport().get_visible_rect().size
	var pixel := camera.unproject_position(camera.global_position + source * 1000.0)
	var uv := pixel / size
	# Lens source just outside the image fades out over 2%; behind-camera projection never contributes.
	var edge := minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
	var edge_fade := smoothstep(-0.02, 0.025, edge)
	var angular_radius: float = float(sky.get_shader_parameter("sun_radius"))
	var radius := tan(angular_radius) / tan(deg_to_rad(camera.fov) * 0.5) * 0.5
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		radius *= size.x / size.y
	_material.set_shader_parameter("sun_uv", uv)
	_material.set_shader_parameter("aspect", size.x / size.y)
	_material.set_shader_parameter("disc_radius", radius)
	_material.set_shader_parameter("far_distance", camera.far)
	_material.set_shader_parameter("strength", intensity * disc * edge_fade * pow(maxf(forward.dot(source), 0.0), 6.0))
	_material.set_shader_parameter("exposure", environment.tonemap_exposure)
	_material.set_shader_parameter("source_dir", source)
	for param: String in ["cloud_scale", "cloud_seed", "cloud_coverage", "cloud_offset", "cluster_strength", "cirrus_strength", "cirrus_coverage"]:
		_material.set_shader_parameter(param, sky.get_shader_parameter(param))
	set_meta("solar_uv", uv)
	set_meta("strength", intensity * disc * edge_fade)
