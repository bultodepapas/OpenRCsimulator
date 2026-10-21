## Timber-only render observer for the authored main-gear pivots and tire contact cues.
## GroundGearMotion owns wheel spin; this component reads its same detached session values,
## articulates only the source gear pivots, and never writes simulation or collision state.
extends Node

const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const Frames := preload("res://render/frames.gd")
const TIRE_DUST_TEXTURE: Texture2D = preload("res://assets/crash/smoke.png")

const AIRCRAFT_ID := "turbo-lumber-evolution"
const CONTACT_TO_GEAR := {"main_left": "left", "main_right": "right"}
const MIN_DUST_NORMAL_LOAD_N := 2.0
const LONGITUDINAL_SLIP_DUST_MPS := 0.75
const LATERAL_SLIP_DUST_MPS := 0.65
const LOOSE_SURFACE_ROLLING_FACTOR := 5.0
const CABLE_CLEARANCE_TRAVEL_DEG := 6.0
const DUST_AMOUNT := 16
const DUST_LIFETIME_S := 0.64

var _session: Node
var _airplane: Dictionary = {}
var _legs: Array[Dictionary] = []
var _dust_emitters: Dictionary = {}
var _cables: MeshInstance3D
var _cable_runtime_mesh: ArrayMesh
var _cable_surfaces: Array[Dictionary] = []
var _cable_links: Array[Dictionary] = []
var _spring_followers: Array[Dictionary] = []
var _last_cable_angles := {"left": 0.0, "right": 0.0}
var _max_travel_rad := 0.0
var _stopped := false


## Attach after GroundGear.attach(); its process priority leaves the shared wheel-spin
## observer first, then this Timber-only observer replaces linear main-wheel travel with
## the source's bounded hinged suspension arc.
static func attach(airplane: Dictionary, session: Node) -> Node:
	if str(airplane.get("aircraft_id", "")) != AIRCRAFT_ID:
		return null
	var root := airplane.get("root") as Node3D
	if root == null or session == null or session.get("sim") == null:
		return null
	var observer := new()
	observer.name = "TimberVisualMotion"
	observer.process_priority = 20
	observer._airplane = airplane
	observer._session = session
	if not observer._configure():
		observer.free()
		return null
	root.add_child(observer)
	if observer._is_source_airframe() and session.has_signal("resetting"):
		session.resetting.connect(observer._on_session_resetting)
	return observer


func _ready() -> void:
	if not _is_source_airframe():
		_disable_detached_copy()


func _configure() -> bool:
	var root: Node3D = _airplane.root
	var landing_gear: Dictionary = TimberGeometry.DATA.get("landing_gear", {})
	var suspension: Dictionary = landing_gear.get("suspension", {})
	var travel: Dictionary = suspension.get("travel_deg", {}).get("value", {})
	var authored_travel_deg := float(travel.get("value", 0.0))
	_max_travel_rad = deg_to_rad(minf(authored_travel_deg, CABLE_CLEARANCE_TRAVEL_DEG))
	if not is_finite(_max_travel_rad) or _max_travel_rad <= 0.0:
		return false
	var axes: Dictionary = suspension.get("axes", {})
	var contacts: Array = _session.current_landing_gear().get("contacts", [])
	if contacts.is_empty():
		return false
	for contact_index in contacts.size():
		var contact: Dictionary = contacts[contact_index]
		var contact_name := str(contact.get("name", ""))
		if not CONTACT_TO_GEAR.has(contact_name):
			continue
		var role: String = CONTACT_TO_GEAR[contact_name]
		var wheel: Node3D = _airplane.get("gear", {}).get(role) as Node3D
		var hinge_name := "gear_left_suspension" if role == "left" else "gear_right_suspension"
		var hinge := root.find_child(hinge_name, true, false) as Node3D
		var axis_value: Variant = axes.get(role, [])
		if wheel == null or hinge == null or not _is_vector3(axis_value):
			continue
		var parent := hinge.get_parent() as Node3D
		if parent == null:
			continue
		var axis_root := Vector3(float(axis_value[0]), float(axis_value[1]), float(axis_value[2])).normalized()
		var axis_world := root.global_basis * axis_root
		var axis_parent := (parent.global_basis.inverse() * axis_world).normalized()
		if axis_root.length_squared() < 0.9 or axis_parent.length_squared() < 0.9:
			continue
		var axle_name := "wheel_left_axle" if role == "left" else "wheel_right_axle"
		var axle := root.find_child(axle_name, true, false) as Node3D
		if axle == null or not hinge.is_ancestor_of(axle):
			continue
		_legs.append({
			"contact_index": contact_index,
			"role": role,
			"contact_name": contact_name,
			"contact": contact,
			"wheel": wheel,
			"wheel_rest": wheel.position,
			"hinge": hinge,
			"hinge_rest": hinge.transform,
			"axle": axle,
			"axle_rest": axle.transform,
			"axis_root": axis_root,
			"axis_parent": axis_parent,
			"pivot_root": root.to_local(hinge.global_position),
			"tip_root": root.to_local(axle.global_position),
			"wheel_radius": float(contact.get("wheel_radius", 0.058)),
		})
		_dust_emitters[contact_index] = _make_dust_emitter(role)
	if _legs.size() != 2:
		return false
	_configure_cable_followers(suspension.get("cable_endpoints", {}), root)
	return true


## The source mesh contains the crossed cable runs and their coil springs. Deform its
## vertices from the authored rest endpoints so each lower attachment follows its leg.
func _configure_cable_followers(endpoints: Variant, root: Node3D) -> void:
	if not endpoints is Dictionary:
		return
	_cables = root.find_child("gear_cables", true, false) as MeshInstance3D
	if _cables == null or _cables.mesh == null:
		return
	var source_mesh := _cables.mesh
	for endpoint_name in ["der", "izq"]:
		var link: Dictionary = endpoints.get(endpoint_name, {})
		var eyelet_value: Variant = link.get("fuselage_eyelet", [])
		var anchor_value: Variant = link.get("anchor_rest", [])
		if not _is_vector3(eyelet_value) or not _is_vector3(anchor_value):
			continue
		var eyelet_root := Vector3(float(eyelet_value[0]), float(eyelet_value[1]), float(eyelet_value[2]))
		var anchor_root := Vector3(float(anchor_value[0]), float(anchor_value[1]), float(anchor_value[2]))
		var role := "left" if anchor_root.x < 0.0 else "right"
		_cable_links.append({
			"endpoint_name": endpoint_name,
			"role": role,
			"eyelet_root": eyelet_root,
			"anchor_root": anchor_root,
			"eyelet_local": _cables.to_local(root.to_global(eyelet_root)),
			"anchor_local": _cables.to_local(root.to_global(anchor_root)),
		})
	if _cable_links.size() != 2:
		_cable_links.clear()
		return
	_cable_runtime_mesh = ArrayMesh.new()
	for surface_index in source_mesh.get_surface_count():
		var arrays: Array = source_mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			_cable_surfaces.clear()
			_cable_links.clear()
			_cable_runtime_mesh = null
			return
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: Array[Vector2] = []
		for vertex: Vector3 in vertices:
			weights.append(_cable_vertex_weight(vertex))
		var primitive: Mesh.PrimitiveType = source_mesh.surface_get_primitive_type(surface_index)
		var material := source_mesh.surface_get_material(surface_index)
		_cable_surfaces.append({
			"primitive": primitive,
			"arrays": arrays.duplicate(true),
			"vertices": vertices.duplicate(),
			"weights": weights,
			"material": material,
		})
		_cable_runtime_mesh.add_surface_from_arrays(primitive, arrays)
		if material != null:
			_cable_runtime_mesh.surface_set_material(surface_index, material)
	if _cable_surfaces.is_empty():
		_cable_links.clear()
		_cable_runtime_mesh = null
		return
	# Duplicate the imported resource so the observer cannot mutate another model instance.
	_cables.mesh = _cable_runtime_mesh
	_configure_coil_followers(root)


func _configure_coil_followers(root: Node3D) -> void:
	_spring_followers.clear()
	for spring in root.find_children("TimberExtensionSpring_*", "MeshInstance3D", true, false):
		var spring_instance := spring as MeshInstance3D
		if spring_instance == null or spring_instance.mesh == null:
			continue
		var endpoint_name := str(spring_instance.name).trim_prefix("TimberExtensionSpring_")
		var link_index := -1
		for index in _cable_links.size():
			if str(_cable_links[index].get("endpoint_name", "")) == endpoint_name:
				link_index = index
				break
		if link_index < 0:
			continue
		var link: Dictionary = _cable_links[link_index]
		var start: Vector3 = spring_instance.to_local(root.to_global(link.eyelet_root))
		var end: Vector3 = spring_instance.to_local(root.to_global(link.anchor_root))
		var source_mesh := spring_instance.mesh
		var runtime_mesh := ArrayMesh.new()
		var surfaces: Array[Dictionary] = []
		for surface_index in source_mesh.get_surface_count():
			var arrays: Array = source_mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_VERTEX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
				surfaces.clear()
				break
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: Array[float] = []
			for vertex: Vector3 in vertices:
				weights.append(_segment_weight(vertex, start, end))
			var primitive: Mesh.PrimitiveType = source_mesh.surface_get_primitive_type(surface_index)
			var material := source_mesh.surface_get_material(surface_index)
			surfaces.append({
				"primitive": primitive,
				"arrays": arrays.duplicate(true),
				"vertices": vertices.duplicate(),
				"weights": weights,
				"material": material,
			})
			runtime_mesh.add_surface_from_arrays(primitive, arrays)
			if material != null:
				runtime_mesh.surface_set_material(surface_index, material)
		if surfaces.is_empty():
			continue
		spring_instance.mesh = runtime_mesh
		_spring_followers.append({
			"node": spring_instance,
			"link_index": link_index,
			"mesh": runtime_mesh,
			"surfaces": surfaces,
		})


func _segment_weight(vertex: Vector3, start: Vector3, end: Vector3) -> float:
	var delta := end - start
	var length_sq := delta.length_squared()
	return 0.0 if length_sq <= 1.0e-10 else clampf((vertex - start).dot(delta) / length_sq, 0.0, 1.0)


func _cable_vertex_weight(vertex: Vector3) -> Vector2:
	var best_index := 0
	var best_t := 0.0
	var best_distance := INF
	for link_index in _cable_links.size():
		var link: Dictionary = _cable_links[link_index]
		var start: Vector3 = link.eyelet_local
		var delta: Vector3 = link.anchor_local - start
		var length_sq := delta.length_squared()
		if length_sq <= 1.0e-10:
			continue
		var t := clampf((vertex - start).dot(delta) / length_sq, 0.0, 1.0)
		var closest := start + delta * t
		var distance_sq := vertex.distance_squared_to(closest)
		if distance_sq < best_distance:
			best_index = link_index
			best_t = t
			best_distance = distance_sq
	return Vector2(float(best_index), best_t)


func _update_cable_followers(angles: Dictionary, root: Node3D) -> void:
	if _cables == null or not is_instance_valid(_cables) or _cable_runtime_mesh == null or _cable_surfaces.is_empty():
		return
	var left_angle := float(angles.get("left", 0.0))
	var right_angle := float(angles.get("right", 0.0))
	if absf(left_angle - float(_last_cable_angles.get("left", 0.0))) < 0.00005 \
		and absf(right_angle - float(_last_cable_angles.get("right", 0.0))) < 0.00005:
		return
	var anchor_deltas_root: Array[Vector3] = []
	for link: Dictionary in _cable_links:
		var role: String = link.role
		var leg: Dictionary = {}
		for candidate: Dictionary in _legs:
			if candidate.role == role:
				leg = candidate
				break
		if leg.is_empty():
			anchor_deltas_root.append(Vector3.ZERO)
			continue
		var axis: Vector3 = leg.axis_root
		var pivot: Vector3 = leg.pivot_root
		var rest_anchor: Vector3 = link.anchor_root
		var rotated_anchor := pivot + Basis(axis, float(angles.get(role, 0.0))) * (rest_anchor - pivot)
		anchor_deltas_root.append(rotated_anchor - rest_anchor)
	var anchor_deltas: Array[Vector3] = []
	for delta_root: Vector3 in anchor_deltas_root:
		anchor_deltas.append(_cables.global_basis.inverse() * root.global_basis * delta_root)
	_cable_runtime_mesh.clear_surfaces()
	for surface_index in _cable_surfaces.size():
		var surface: Dictionary = _cable_surfaces[surface_index]
		var arrays: Array = surface.arrays.duplicate(true)
		var vertices: PackedVector3Array = surface.vertices.duplicate()
		var weights: Array[Vector2] = surface.weights
		for vertex_index in vertices.size():
			var weight: Vector2 = weights[vertex_index]
			var cable_index := clampi(int(weight.x), 0, anchor_deltas.size() - 1)
			vertices[vertex_index] += anchor_deltas[cable_index] * weight.y
		arrays[Mesh.ARRAY_VERTEX] = vertices
		_cable_runtime_mesh.add_surface_from_arrays(surface.primitive, arrays)
		if surface.material != null:
			_cable_runtime_mesh.surface_set_material(surface_index, surface.material)
	for follower: Dictionary in _spring_followers:
		var spring_instance := follower.node as MeshInstance3D
		var spring_mesh := follower.mesh as ArrayMesh
		var link_index: int = follower.link_index
		if not is_instance_valid(spring_instance) or spring_mesh == null or link_index < 0 or link_index >= anchor_deltas_root.size():
			continue
		var local_delta: Vector3 = spring_instance.global_basis.inverse() * root.global_basis * anchor_deltas_root[link_index]
		spring_mesh.clear_surfaces()
		for surface_index in follower.surfaces.size():
			var spring_surface: Dictionary = follower.surfaces[surface_index]
			var spring_arrays: Array = spring_surface.arrays.duplicate(true)
			var spring_vertices: PackedVector3Array = spring_surface.vertices.duplicate()
			var spring_weights: Array[float] = spring_surface.weights
			for vertex_index in spring_vertices.size():
				spring_vertices[vertex_index] += local_delta * spring_weights[vertex_index]
			spring_arrays[Mesh.ARRAY_VERTEX] = spring_vertices
			spring_mesh.add_surface_from_arrays(spring_surface.primitive, spring_arrays)
			if spring_surface.material != null:
				spring_mesh.surface_set_material(surface_index, spring_surface.material)
	_last_cable_angles = {"left": left_angle, "right": right_angle}


func _is_vector3(value: Variant) -> bool:
	return value is Array and value.size() == 3 \
		and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value[1]) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value[2]) in [TYPE_INT, TYPE_FLOAT]


func _make_dust_emitter(role: String) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "TimberTireDust_" + role
	particles.amount = DUST_AMOUNT
	particles.lifetime = DUST_LIFETIME_S
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.direction = Vector3.UP
	particles.spread = 28.0
	particles.initial_velocity_min = 0.12
	particles.initial_velocity_max = 0.34
	particles.gravity = Vector3(0.0, -0.12, 0.0)
	particles.scale_amount_min = 0.12
	particles.scale_amount_max = 0.55
	particles.angular_velocity_min = -18.0
	particles.angular_velocity_max = 18.0
	particles.use_fixed_seed = true
	particles.seed = 7130 if role == "left" else 7131
	particles.color_ramp = _dust_fade()
	var dust_shader := Shader.new()
	dust_shader.code = """
	shader_type spatial;
	render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;
	uniform sampler2D dust_texture : source_color, filter_linear, repeat_disable;
	void vertex() {
		// Shader materials replace StandardMaterial3D's particle billboard mode, so rebuild
		// the quad in view space and retain the per-particle transform scale.
		vec3 center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		float width_scale = length(MODELVIEW_MATRIX[0].xyz);
		float height_scale = length(MODELVIEW_MATRIX[1].xyz);
		VERTEX = center_view + vec3(VERTEX.x * width_scale, VERTEX.y * height_scale, 0.0);
		NORMAL = vec3(0.0, 0.0, 1.0);
	}
	void fragment() {
		vec2 centered_uv = UV * 2.0 - vec2(1.0);
		float radial_fade = 1.0 - smoothstep(0.54, 1.0, length(centered_uv));
		vec4 dust = texture(dust_texture, UV);
		ALBEDO = dust.rgb * COLOR.rgb;
		ALPHA = dust.a * COLOR.a * radial_fade;
	}
	"""
	var material := ShaderMaterial.new()
	material.shader = dust_shader
	material.set_shader_parameter("dust_texture", TIRE_DUST_TEXTURE)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.075, 0.075)
	mesh.material = material
	particles.mesh = mesh
	add_child(particles)
	return particles


func _dust_fade() -> Gradient:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	fade.colors = PackedColorArray([
		Color(0.38, 0.31, 0.23, 0.0),
		Color(0.43, 0.35, 0.25, 0.36),
		Color(0.48, 0.40, 0.30, 0.0),
	])
	return fade


func _process(_delta: float) -> void:
	if _stopped or not is_instance_valid(_session) or _session.sim == null:
		return
	if not _is_source_airframe():
		_disable_detached_copy()
		return
	if not _session.crash.is_empty() or not str(_session.sim.fault_reason).is_empty():
		_stop_after_crash()
		return
	if not _session.aircraft.get("ok", false) or _session.wheel_count() == 0:
		return
	var state: PackedFloat64Array = _session.sim.interpolated(Engine.get_physics_interpolation_fraction())
	var compression: PackedFloat64Array = _session.gear_compressions(state)
	var contacts: Array = _session.current_landing_gear().get("contacts", [])
	if compression.size() != contacts.size():
		return
	var root: Node3D = _airplane.root
	var up_root: Vector3 = root.global_basis.transposed() * Vector3.UP
	var angles_by_role := {"left": 0.0, "right": 0.0}
	for leg: Dictionary in _legs:
		var index: int = leg.contact_index
		if index < 0 or index >= compression.size():
			continue
		var wheel := leg.wheel as Node3D
		var hinge := leg.hinge as Node3D
		if not is_instance_valid(wheel) or not is_instance_valid(hinge):
			continue
		var contact: Dictionary = leg.contact
		var amount := float(compression[index])
		if not is_finite(amount):
			continue
		amount = clampf(amount, 0.0, float(contact.get("max_compression", 0.10)))
		var axis: Vector3 = leg.axis_root
		var arm: Vector3 = leg.tip_root - leg.pivot_root
		var max_height := maxf(0.0, _height_for_angle(axis, arm, _max_travel_rad, up_root))
		var angle := _suspension_angle(leg, minf(amount, max_height), up_root)
		var rest: Transform3D = leg.hinge_rest
		hinge.transform = Transform3D(Basis(leg.axis_parent, angle) * rest.basis, rest.origin)
		var arc_height := maxf(0.0, _height_for_angle(axis, arm, angle, up_root))
		# GroundGearMotion applies world-up compression to the wheel wrapper. The spring
		# hinge carries the leg; a small axle-slide remainder keeps the tire at that same
		# rendered contact height after the authored cable-clearance limit is reached.
		var wheel_up_local: Vector3 = wheel.get_parent().global_basis.inverse() * Vector3.UP
		wheel.position = leg.wheel_rest + wheel_up_local * maxf(0.0, amount - arc_height)
		angles_by_role[leg.role] = angle
	_update_cable_followers(angles_by_role, root)
	_update_contact_dust(state, contacts, compression)


func _suspension_angle(leg: Dictionary, compression_m: float, up_root: Vector3) -> float:
	if compression_m <= 0.0 or up_root.length_squared() < 1.0e-8:
		return 0.0
	var axis: Vector3 = leg.axis_root
	var arm: Vector3 = leg.tip_root - leg.pivot_root
	var max_height := _height_for_angle(axis, arm, _max_travel_rad, up_root)
	if max_height <= 1.0e-6:
		return 0.0
	if compression_m >= max_height:
		return _max_travel_rad
	var low := 0.0
	var high := _max_travel_rad
	for _iteration in 12:
		var middle := 0.5 * (low + high)
		if _height_for_angle(axis, arm, middle, up_root) < compression_m:
			low = middle
		else:
			high = middle
	return 0.5 * (low + high)


func _height_for_angle(axis: Vector3, arm: Vector3, angle: float, up_root: Vector3) -> float:
	return (Basis(axis, angle) * arm - arm).dot(up_root)


func _update_contact_dust(state: PackedFloat64Array, contacts: Array, compression: PackedFloat64Array) -> void:
	var wheel_count: int = _session.wheel_count()
	var first_wheel: int = _session.wheel_index()
	var continuous: PackedFloat64Array = _session.sim.continuous
	if first_wheel < 0 or first_wheel + wheel_count > continuous.size():
		return
	var paused: bool = _session.sim.paused or not _session.holds.is_empty()
	if paused:
		for emitter_value: Variant in _dust_emitters.values():
			var emitter := emitter_value as CPUParticles3D
			if is_instance_valid(emitter):
				emitter.speed_scale = 0.0
				emitter.emitting = false
		return
	var has_compressed_wheel := false
	for amount: float in compression:
		if amount > 0.0:
			has_compressed_wheel = true
			break
	if not has_compressed_wheel:
		for emitter_value: Variant in _dust_emitters.values():
			var emitter := emitter_value as CPUParticles3D
			if is_instance_valid(emitter):
				emitter.speed_scale = 1.0
				emitter.emitting = false
		return
	var steer: float = _session.sim.aux[_session.AUX_SERVO + 2]
	var surfaces: PackedFloat64Array = _session.ground_surfaces
	var lake_value: Variant = _session.get("_lake")
	var lake: Dictionary = lake_value if lake_value is Dictionary else {}
	for leg: Dictionary in _legs:
		var index: int = leg.contact_index
		var emitter := _dust_emitters.get(index) as CPUParticles3D
		if emitter == null or index >= contacts.size() or index >= wheel_count:
			continue
		emitter.speed_scale = 1.0
		var contact: Dictionary = contacts[index]
		var frame: Dictionary = GroundWheels.frame(state, contact, steer, surfaces,
			PackedFloat64Array(), false, lake)
		var slip_speed: float = float(frame.get("long_speed", 0.0)) - float(continuous[first_wheel + index])
		var lateral_speed: float = float(frame.get("side_speed", 0.0))
		var real_contact: bool = float(frame.get("normal_load", 0.0)) >= MIN_DUST_NORMAL_LOAD_N
		var slipping: bool = absf(slip_speed) >= LONGITUDINAL_SLIP_DUST_MPS \
			or absf(lateral_speed) >= LATERAL_SLIP_DUST_MPS
		var loose_surface := _is_loose_surface(surfaces, frame)
		var wheel := leg.wheel as Node3D
		emitter.emitting = real_contact and loose_surface and slipping and compression[index] > 0.0
		if emitter.emitting and is_instance_valid(wheel):
			var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
			var normal: PackedFloat64Array = frame.get("normal", PackedFloat64Array())
			if position.size() == 3 and normal.size() == 3:
				var compression_m := maxf(0.0, float(frame.get("compression", 0.0)))
				var contact_ned := PackedFloat64Array([
					position[0] + normal[0] * compression_m,
					position[1] + normal[1] * compression_m,
					position[2] + normal[2] * compression_m,
				])
				var ground_normal := Frames.ned_to_render(Array(normal)).normalized()
				var heading_ned: PackedFloat64Array = frame.get("heading", PackedFloat64Array())
				var side_ned: PackedFloat64Array = frame.get("side", PackedFloat64Array())
				var rearward := Vector3.ZERO
				if heading_ned.size() == 3:
					rearward = -Frames.ned_to_render(Array(heading_ned)).normalized()
				if side_ned.size() == 3 and absf(lateral_speed) >= LATERAL_SLIP_DUST_MPS:
					rearward += Frames.ned_to_render(Array(side_ned)).normalized() * signf(lateral_speed) * 0.3
				var plume_direction := (ground_normal * 0.82 + rearward.normalized() * 0.58).normalized()
				emitter.direction = plume_direction
				emitter.global_transform = Transform3D(Basis.IDENTITY,
					Frames.ned_to_render(Array(contact_ned)) + ground_normal * 0.004)


func _is_loose_surface(surfaces: PackedFloat64Array, frame: Dictionary) -> bool:
	if surfaces.is_empty():
		return false
	var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
	if position.size() != 3:
		return false
	var surface_index := GroundWheels.surface_at(surfaces, float(position[0]), float(position[1]))
	return surface_index >= 0 and surface_index + 5 < surfaces.size() \
		and surfaces[surface_index + 5] >= LOOSE_SURFACE_ROLLING_FACTOR


func _on_session_resetting() -> void:
	_stopped = false
	set_process(true)
	for leg: Dictionary in _legs:
		var wheel := leg.wheel as Node3D
		var hinge := leg.hinge as Node3D
		var axle := leg.axle as Node3D
		if is_instance_valid(hinge):
			hinge.transform = leg.hinge_rest
		if is_instance_valid(wheel):
			wheel.position = leg.wheel_rest
		if is_instance_valid(axle):
			axle.transform = leg.axle_rest
	for emitter: CPUParticles3D in _dust_emitters.values():
		if is_instance_valid(emitter):
			emitter.emitting = false
			emitter.speed_scale = 1.0
			emitter.restart()
			emitter.emitting = false
	_last_cable_angles = {"left": -999.0, "right": -999.0}
	_update_cable_followers({"left": 0.0, "right": 0.0}, _airplane.root)


func _stop_after_crash() -> void:
	_stopped = true
	set_process(false)
	for emitter: CPUParticles3D in _dust_emitters.values():
		if is_instance_valid(emitter):
			emitter.emitting = false


func _is_source_airframe() -> bool:
	var parent_root := get_parent() as Node3D
	return parent_root != null and parent_root == _airplane.get("root")


func _disable_detached_copy() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	set_process(false)
	var model_root := get_parent() as Node3D
	if model_root != null:
		var cable_copy := model_root.find_child("gear_cables", true, false) as MeshInstance3D
		if cable_copy != null and cable_copy.mesh != null:
			cable_copy.mesh = cable_copy.mesh.duplicate(true)
		for spring in model_root.find_children("TimberExtensionSpring_*", "MeshInstance3D", true, false):
			var spring_copy := spring as MeshInstance3D
			if spring_copy != null and spring_copy.mesh != null:
				spring_copy.mesh = spring_copy.mesh.duplicate(true)
	for child: Node in get_children():
		if child is CPUParticles3D:
			child.emitting = false
			child.speed_scale = 0.0
	_session = null
	_airplane = {}
	_stopped = true
