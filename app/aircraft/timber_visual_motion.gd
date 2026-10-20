## Timber-only render observer for the authored main-gear pivots and tire contact cues.
## GroundGearMotion owns wheel spin; this component reads its same detached session values,
## articulates only the source gear pivots, and never writes simulation or collision state.
extends Node

const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")

const AIRCRAFT_ID := "turbo-lumber-evolution"
const CONTACT_TO_GEAR := {"main_left": "left", "main_right": "right"}
const MIN_DUST_NORMAL_LOAD_N := 2.0
const LONGITUDINAL_SLIP_DUST_MPS := 0.75
const LATERAL_SLIP_DUST_MPS := 0.65
const DUST_AMOUNT := 8
const DUST_LIFETIME_S := 0.42

var _session: Node
var _airplane: Dictionary = {}
var _legs: Array[Dictionary] = []
var _dust_emitters: Dictionary = {}
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
	return observer


func _configure() -> bool:
	var root: Node3D = _airplane.root
	var landing_gear: Dictionary = TimberGeometry.DATA.get("landing_gear", {})
	var suspension: Dictionary = landing_gear.get("suspension", {})
	var travel: Dictionary = suspension.get("travel_deg", {}).get("value", {})
	_max_travel_rad = deg_to_rad(float(travel.get("value", 0.0)))
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
		_legs.append({
			"contact_index": contact_index,
			"role": role,
			"contact_name": contact_name,
			"wheel": wheel,
			"wheel_rest": wheel.position,
			"hinge": hinge,
			"hinge_rest": hinge.transform,
			"axis_root": axis_root,
			"axis_parent": axis_parent,
			"pivot_root": root.to_local(hinge.global_position),
			"tip_root": root.to_local(wheel.global_position),
			"wheel_radius": float(contact.get("wheel_radius", 0.058)),
		})
		_dust_emitters[contact_index] = _make_dust_emitter(role)
	return _legs.size() == 2


func _is_vector3(value: Variant) -> bool:
	return value is Array and value.size() == 3 \
		and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value[1]) in [TYPE_INT, TYPE_FLOAT] \
		and typeof(value[2]) in [TYPE_INT, TYPE_FLOAT]


func _make_dust_emitter(role: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "TimberTireDust_" + role
	particles.amount = DUST_AMOUNT
	particles.lifetime = DUST_LIFETIME_S
	particles.fixed_fps = 30
	particles.local_coords = false
	particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 32.0
	process.initial_velocity_min = 0.12
	process.initial_velocity_max = 0.36
	process.gravity = Vector3(0.0, -0.28, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.25
	process.angular_velocity_min = -24.0
	process.angular_velocity_max = 24.0
	process.color_ramp = _dust_fade()
	particles.process_material = process
	var mesh := SphereMesh.new()
	mesh.radius = 0.010
	mesh.height = 0.020
	mesh.radial_segments = 5
	mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.46, 0.40, 0.31, 0.28)
	mesh.material = material
	particles.draw_pass_1 = mesh
	add_child(particles)
	return particles


func _dust_fade() -> GradientTexture1D:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 1.0])
	fade.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.32), Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture1D.new()
	texture.gradient = fade
	return texture


func _process(_delta: float) -> void:
	if _stopped or not is_instance_valid(_session) or _session.sim == null:
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
	var up_root: Vector3 = root.global_basis.inverse() * Vector3.UP
	for leg: Dictionary in _legs:
		var index: int = leg.contact_index
		if index < 0 or index >= compression.size():
			continue
		var wheel := leg.wheel as Node3D
		var hinge := leg.hinge as Node3D
		if not is_instance_valid(wheel) or not is_instance_valid(hinge):
			continue
		var amount := maxf(0.0, float(compression[index]))
		var angle := _suspension_angle(leg, amount, up_root)
		var rest: Transform3D = leg.hinge_rest
		hinge.transform = Transform3D(Basis(leg.axis_parent, angle) * rest.basis, rest.origin)
		# GroundGearMotion translates the axle directly. Restore its captured mount-space
		# origin so the authored hinge carries the wheel and strut together on one arc.
		wheel.position = leg.wheel_rest
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
	var wheel_speeds := continuous.slice(first_wheel, first_wheel + wheel_count)
	var steer: float = _session.sim.aux[_session.AUX_SERVO + 2]
	var surfaces: PackedFloat64Array = _session.ground_surfaces
	var lake_value: Variant = _session.get("_lake")
	var lake: Dictionary = lake_value if lake_value is Dictionary else {}
	for leg: Dictionary in _legs:
		var index: int = leg.contact_index
		var emitter := _dust_emitters.get(index) as GPUParticles3D
		if emitter == null or index >= contacts.size() or index >= wheel_speeds.size():
			continue
		var contact: Dictionary = contacts[index]
		var frame: Dictionary = GroundWheels.frame(state, contact, steer, surfaces,
			PackedFloat64Array(), false, lake)
		var slip_speed: float = float(frame.get("long_speed", 0.0)) - float(wheel_speeds[index])
		var lateral_speed: float = float(frame.get("side_speed", 0.0))
		var real_contact: bool = float(frame.get("normal_load", 0.0)) >= MIN_DUST_NORMAL_LOAD_N
		var slipping: bool = absf(slip_speed) >= LONGITUDINAL_SLIP_DUST_MPS \
			or absf(lateral_speed) >= LATERAL_SLIP_DUST_MPS
		var wheel := leg.wheel as Node3D
		emitter.emitting = real_contact and slipping and compression[index] > 0.0
		if emitter.emitting and is_instance_valid(wheel):
			var contact_point := wheel.global_position - Vector3.UP * float(leg.wheel_radius)
			emitter.global_transform = Transform3D(Basis.IDENTITY, contact_point)


func _stop_after_crash() -> void:
	_stopped = true
	set_process(false)
	for emitter: GPUParticles3D in _dust_emitters.values():
		if is_instance_valid(emitter):
			emitter.emitting = false
