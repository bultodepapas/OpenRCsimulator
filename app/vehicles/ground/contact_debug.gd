## Read-only physical contact/CG overlay, independent of authored collision meshes.
extends MeshInstance3D
const Frames = preload("res://render/frames.gd")
var lines := ImmediateMesh.new()

func _init() -> void:
	mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func update_snapshot(state: PackedFloat64Array, model: Dictionary, telemetry: Dictionary, road: Callable = Callable()) -> void:
	lines.clear_surfaces()
	if not visible or state.size() != 31:
		return
	var body := Frames.quat_to_render(state.slice(6, 10))
	global_transform = Transform3D(body, Frames.ned_to_render([state[0], state[1], state[2]]))
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(-axis * 0.025, axis * 0.025, Color.YELLOW)
	var loads = telemetry.get("wheel_load_n", [0, 0, 0, 0])
	var wall_contact = telemetry.get("wheel_wall_in_contact", PackedByteArray())
	for i in 4:
		var travel: float = state[13 + i]
		var arm: float = model.arm_length_m
		var lateral: float = model.corner_y_m[i] + signf(model.corner_y_m[i]) * (sqrt(maxf(0, arm * arm - travel * travel)) - arm)
		var down: float = model.cg_height_above_chassis_datum_m + model.wheel_center_rest_below_chassis_datum_m - travel
		var hub := Vector3(lateral, -down, -model.corner_x_m[i])
		var normal: Vector3 = body.inverse() * Vector3.UP
		if road.is_valid():
			var world_hub: Vector3 = global_transform * hub
			var sample: Dictionary = road.call(-world_hub.z, world_hub.x)
			var ned: PackedFloat64Array = sample.normal_ned
			normal = body.inverse() * Vector3(ned[1], -ned[2], -ned[0])
		var contact: Vector3 = hub - normal * model.tire_radius_m
		_line(contact, contact + normal * minf(loads[i] * 0.006, 0.7), Color("74efcd"))
		_circle(hub, model.tire_radius_m, Color("ff654d") if i < wall_contact.size() and wall_contact[i] else Color("7d9296"))
	var centers: PackedFloat64Array = model.hull_probe_centers_frd_m
	var radii: PackedFloat64Array = model.hull_probe_radii_m
	var active = telemetry.get("hull_in_contact", [])
	for i in radii.size():
		var center := Vector3(centers[3 * i + 1], -centers[3 * i + 2], -centers[3 * i])
		_circle(center, radii[i], Color("ff654d") if i < active.size() and active[i] else Color("798795"))
	lines.surface_end()

func _circle(center: Vector3, radius: float, color: Color) -> void:
	for axis in 3:
		for i in 16:
			var a := float(i) * TAU / 16.0
			var b := float(i + 1) * TAU / 16.0
			var p := Vector3(cos(a) * radius, sin(a) * radius, 0)
			var q := Vector3(cos(b) * radius, sin(b) * radius, 0)
			if axis == 1:
				p = Vector3(p.x, 0, p.y)
				q = Vector3(q.x, 0, q.y)
			elif axis == 2:
				p = Vector3(0, p.x, p.y)
				q = Vector3(0, q.x, q.y)
			_line(center + p, center + q, color)

func _line(a: Vector3, b: Vector3, color: Color) -> void:
	lines.surface_set_color(color)
	lines.surface_add_vertex(a)
	lines.surface_set_color(color)
	lines.surface_add_vertex(b)
