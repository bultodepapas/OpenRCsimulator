## Moving windsock coverage in the existing flat-ground projection system.
## The visible material and mask share GPU deformation; no mesh rebuild or clock.
extends "res://render/projected_shadow.gd"

const SockMask = preload("res://render/windsock_shadow_mask.gdshader")
const Clock = preload("res://render/shader_clock.gd")
const DIMENSION_UNIFORMS := ["length_m", "throat_diameter_m", "tail_diameter_m", "basket_height_m", "arm_m"]
const POSE_UNIFORMS := ["centerline_points", "basket_yaw_rad", "inflation"]
const PROJECTION_UNIFORMS := ["aircraft_basis", "light_direction", "frame_center", "frame_size"]
## Below this inflation, flutter is micrometre-scale (1 µm on the default sleeve).
const FLUTTER_INFLATION_EPSILON: float = 0.0001
var _fabric_material: ShaderMaterial
var _moving_materials: Array[ShaderMaterial] = []
var _pose_signature: Array = []
var _projection_signature: Array = []


func setup(model: Node3D, shape: Dictionary, resolution: int = 512, antialias: int = Viewport.MSAA_DISABLED) -> void:
	super.setup(model, shape, resolution, antialias)
	receiver.name = "SoftWindsockShadow"
	var fabric := model.get_node("Fabric") as MeshInstance3D
	var basket := model.get_node("Basket") as MeshInstance3D
	_fabric_material = fabric.mesh.surface_get_material(0) as ShaderMaterial
	_add_proxy(fabric.mesh, true, false)
	_add_proxy(basket.mesh, false, true)
	triangle_count += fabric.mesh.get_faces().size() / 3 + basket.mesh.get_faces().size() / 3
	# main/Home have uploaded the current centreline and shared clock by this point.
	process_priority = 80
	set_process(true)


func _add_proxy(mesh: Mesh, fabric: bool, basket: bool) -> void:
	var proxy := MeshInstance3D.new()
	proxy.mesh = mesh
	proxy.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SockMask
	material.set_shader_parameter("deform_fabric", fabric)
	material.set_shader_parameter("turn_with_basket", basket)
	for parameter: String in DIMENSION_UNIFORMS:
		material.set_shader_parameter(parameter, _fabric_material.get_shader_parameter(parameter))
	proxy.material_override = material
	viewport.add_child(proxy)
	_moving_materials.append(material)


func _process(_delta: float) -> void:
	if not _last_request.is_empty() and bool(_last_request[3]):
		refresh(_last_request[0], _last_request[1], _last_request[2], _last_request[3])


func refresh(height: float, direction: Vector3, opacity: float, shown: bool) -> void:
	if is_instance_valid(source) and _fabric_material != null and shown:
		var signature: Array = []
		for parameter: String in POSE_UNIFORMS:
			signature.append(_fabric_material.get_shader_parameter(parameter))
		# Exponential deflation approaches zero asymptotically. Do not keep drawing
		# invisible flutter or subpixel settling after the wind has calmed.
		signature.append(Clock.last_clock if float(signature[2]) > FLUTTER_INFLATION_EPSILON else 0.0)
		var current_bounds: AABB = source.get_meta("visual_bounds", bounds)
		if not _same_pose(signature, current_bounds):
			for material: ShaderMaterial in _moving_materials:
				for index: int in POSE_UNIFORMS.size():
					material.set_shader_parameter(POSE_UNIFORMS[index], signature[index])
			bounds = current_bounds
			_pose_signature = signature
			_last_signature.clear()
	super.refresh(height, direction, opacity, shown)
	if receiver.visible and _last_signature != _projection_signature:
		for material: ShaderMaterial in _moving_materials:
			for parameter: String in PROJECTION_UNIFORMS:
				material.set_shader_parameter(parameter, mask_material.get_shader_parameter(parameter))
		_projection_signature = _last_signature.duplicate()


func _same_pose(signature: Array, current_bounds: AABB) -> bool:
	if _pose_signature.size() != 4 or not current_bounds.is_equal_approx(bounds):
		return false
	if not is_equal_approx(float(signature[1]), float(_pose_signature[1])) \
			or not is_equal_approx(float(signature[2]), float(_pose_signature[2])) \
			or signature[3] != _pose_signature[3]:
		return false
	var points: PackedVector3Array = signature[0]
	var previous: PackedVector3Array = _pose_signature[0]
	if points.size() != previous.size():
		return false
	for index: int in points.size():
		if not points[index].is_equal_approx(previous[index]):
			return false
	return true
