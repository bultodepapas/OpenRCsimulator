## DR-29/30: FPV quad visual adapter. Poses one body from the activity's single interpolated pose and draws four rotor
## presentations at the PHYSICS hub positions (prepared data, FRD converted to render once), each spun by its
## ACHIEVED shaft speed from telemetry (never the commands) in its own direction, with the shared propeller-blur
## cross-fade (render/propeller_blur.gd: solid blades when stopped or slow, a translucent disc above the blade-passing
## threshold). The default airframe is the supplied ION R5 GLB (Godot axes +Y up, nose −Z,
## right +X; nodes airframe_root, motor_1…4, propeller_1…4, camera_mount; origin = motor-mount centre in the arm-top
## plane). If it cannot be loaded, a deliberately plain LAB FIXTURE of primitive meshes stands in and the OSD says so.
## The supplied ION R5 includes its own bells and blades; those are reparented onto the same RPM-driven pivots.
## Legacy frame-only assets and the lab fixture retain procedural rotors. Rendering never feeds back into physics.
extends RefCounted

const Frames = preload("res://render/frames.gd")
const PropellerBlur = preload("res://render/propeller_blur.gd")
const PropBreak = preload("res://render/crash/prop_break.gd")
## DR-19d: largest wobble (rad) of a damaged prop's disc, reached as its health falls to zero.
const DAMAGE_WOBBLE_RAD := 0.12

const MODEL_PATH := "res://assets/multirotors/ion-r5/ion_r5.glb"
## Prop plane above the frame's arm-top (motor-mount) plane. Estimated; motors are not in the downloaded frame.
const MOTOR_HEIGHT_M := 0.020
const MOTOR_RADIUS_M := 0.0115
## The data's F5146 propeller is tri-blade (rotors[].prop); prepared rotors carry no blade count.
const BLADES := 3
const BLADE_WIDTH_M := 0.013
const BLADE_THICKNESS_M := 0.0025

var root: Node3D
var model: Node3D
var fixture := false
## Why the fixture is shown ("" with the imported frame).
var fallback_reason := ""
var error := ""
var model_path := ""
var complete_rotors := false
## Onboard lens in FRD, metres from CG. Visual mount only: never changes session data/replay identity.
var fpv_mount_frd := PackedFloat64Array()
## Per rotor: {spin (+1 counter-clockwise from above), pivot (propeller node, local +Z = spin axis), base (Basis),
## phase (rad), blur (PropellerBlur node or null), speed (last achieved rad/s)}.
var rotors: Array[Dictionary] = []


## data: the session's prepared multirotor document (rotors[].hub_frd/spin/diameter_m, camera.mount_frd).
## model: the frame scene to load (tests point it at a missing path to exercise the fixture).
## Home's parked preview disables rotor blur: retain the same solid geometry without measuring or building observers.
func build(data: Dictionary, frame_model: String = MODEL_PATH, with_rotor_blur := true) -> bool:
	var prepared_rotors: Variant = data.get("rotors")
	if typeof(prepared_rotors) != TYPE_ARRAY or prepared_rotors.size() != 4:
		error = "FPV quad visual: the prepared data has no four rotors"
		return false
	root = Node3D.new()
	root.name = "Multirotor"
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model_path = frame_model
	model = _load_frame(frame_model, prepared_rotors)
	if model == null:
		fixture = true
		model = _build_fixture(prepared_rotors, data.get("camera", {}))
	root.add_child(model)
	fpv_mount_frd = (data.camera.mount_frd as PackedFloat64Array).duplicate()
	if complete_rotors:
		var mount := model.find_child("camera_mount", true, false) as Node3D
		var at := PropellerBlur.relative(root, mount).origin
		fpv_mount_frd = PackedFloat64Array([-at.z, at.x, -at.y])
	var motor_material: StandardMaterial3D
	if not complete_rotors:
		motor_material = StandardMaterial3D.new()
		motor_material.albedo_color = Color(0.55, 0.57, 0.6)
		motor_material.metallic = 0.6
		motor_material.roughness = 0.4
	for rotor: Dictionary in prepared_rotors:
		rotors.append(_import_rotor(rotor) if complete_rotors else _build_rotor(rotor, motor_material))
	# No cut-radius root: the motor bell ends below the blade plane, and the canopy or a neighbouring rotor must not
	# be mistaken for hub hardware that hides the inner disc.
	if with_rotor_blur:
		for rotor: Dictionary in rotors:
			rotor.blur = PropellerBlur.attach({propeller = rotor.pivot, root = null, has_propeller = true}, null, root)
	return true


## The imported frame placed so the centroid of its propeller_N empties sits MOTOR_HEIGHT_M below the centroid of
## the physics hubs; null (with fallback_reason) when it is missing or lacks the named nodes.
func _load_frame(path: String, prepared_rotors: Array) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		fallback_reason = "frame model not found: " + path
		return null
	var scene := load(path) as PackedScene
	var frame := scene.instantiate() as Node3D if scene != null else null
	if frame == null:
		fallback_reason = "frame model did not load: " + path
		return null
	var empties := model_empties(frame)
	if empties.is_empty():
		frame.free()
		fallback_reason = "frame model lacks airframe_root/propeller_1…4: " + path
		return null
	frame.name = "Model"
	frame.position = frame_offset(prepared_rotors, empties)
	complete_rotors = frame.find_child("ION_R5_body", true, false) != null
	if complete_rotors and not has_complete_rotors(frame):
		complete_rotors = false
		fallback_reason = "ION R5 model lacks its camera, bells or blades: " + path
		frame.free()
		return null
	return frame


## Refuse partial complete-aircraft exports before moving their meshes or positioning the onboard view.
static func has_complete_rotors(frame: Node3D) -> bool:
	if not frame.find_child("camera_mount", true, false) is Node3D:
		return false
	for id in range(1, 5):
		var marker := frame.find_child("propeller_%d" % id, true, false) as Node3D
		if marker == null:
			return false
		for part: String in ["bell", "blades"]:
			var mesh := marker.find_child("ION_R5_%s_%d" % [part, id], true, false) as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				return false
	return true


## Model position (render-body axes, from the CG) that puts the propeller empties' centroid MOTOR_HEIGHT_M below the
## physics hubs' centroid.
static func frame_offset(prepared_rotors: Array, empties: Dictionary) -> Vector3:
	return hub_centroid(prepared_rotors) - Vector3(0.0, MOTOR_HEIGHT_M, 0.0) - (empties.propeller_centroid as Vector3)


## Imported frame empties in the scene root's frame: {propellers: Array[Vector3] (propeller_1…4), propeller_centroid,
## camera_mount (Vector3, or null)}; {} without airframe_root or any propeller_N.
static func model_empties(scene_root: Node3D) -> Dictionary:
	var airframe: Node = scene_root if scene_root.name == "airframe_root" else scene_root.find_child("airframe_root", true, false)
	if airframe == null:
		return {}
	var propellers: Array[Vector3] = []
	var centroid := Vector3.ZERO
	for i in range(1, 5):
		var node := scene_root.find_child("propeller_%d" % i, true, false) as Node3D
		if node == null:
			return {}
		var at := PropellerBlur.relative(scene_root, node).origin
		propellers.append(at)
		centroid += at * 0.25
	var mount := scene_root.find_child("camera_mount", true, false) as Node3D
	return {propellers = propellers, propeller_centroid = centroid,
		camera_mount = PropellerBlur.relative(scene_root, mount).origin if mount != null else null}


## Centroid of the four physics hubs in render-body axes (m from the CG).
static func hub_centroid(prepared_rotors: Array) -> Vector3:
	var sum := Vector3.ZERO
	for rotor: Dictionary in prepared_rotors:
		sum += body_point(rotor.hub_frd)
	return sum / float(maxi(prepared_rotors.size(), 1))


## Render-body position (m) of an FRD offset from the CG.
static func body_point(frd: PackedFloat64Array) -> Vector3:
	return Frames.ned_to_render([frd[0], frd[1], frd[2]])


## The plain laboratory stand-in: centre plate and four arms to the hubs in the arm-top plane, plus a camera block.
func _build_fixture(prepared_rotors: Array, camera_data: Variant) -> Node3D:
	var fixture_root := Node3D.new()
	fixture_root.name = "LabFixture"
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.16, 0.17, 0.18)
	frame_material.roughness = 0.8
	var arm_y := hub_centroid(prepared_rotors).y - MOTOR_HEIGHT_M - 0.003
	var plate := BoxMesh.new()
	plate.size = Vector3(0.05, 0.012, 0.11)
	_mesh(fixture_root, "CentrePlate", plate, frame_material, Transform3D(Basis.IDENTITY, Vector3(0.0, arm_y, 0.0)))
	for rotor: Dictionary in prepared_rotors:
		var hub := body_point(rotor.hub_frd)
		var flat := Vector3(hub.x, 0.0, hub.z)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.016, 0.006, flat.length())
		var along := flat.normalized()
		var basis := Basis(Vector3.UP.cross(along).normalized(), Vector3.UP, along)
		_mesh(fixture_root, "Arm%d" % int(rotor.id), arm, frame_material, Transform3D(basis, Vector3(hub.x * 0.5, arm_y, hub.z * 0.5)))
	if typeof(camera_data) == TYPE_DICTIONARY and typeof(camera_data.get("mount_frd")) == TYPE_PACKED_FLOAT64_ARRAY:
		var block := BoxMesh.new()
		block.size = Vector3(0.019, 0.019, 0.02)
		_mesh(fixture_root, "CameraBlock", block, frame_material, Transform3D(Basis.IDENTITY, body_point(camera_data.mount_frd) + Vector3(0.0, 0.0, 0.012)))
	return fixture_root


static func _mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, at: Transform3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.transform = at
	parent.add_child(instance)
	return instance


## Complete supplied assembly: retain its own handed blades and motor bell, without adding stand-in geometry.
## Convert the imported +Y spin axis to PropellerBlur's local +Z once, preserving every mesh's model-space pose.
func _import_rotor(rotor: Dictionary) -> Dictionary:
	var assembly := model.find_child("propeller_%d" % int(rotor.id), true, false) as Node3D
	var pivot := Node3D.new()
	pivot.name = "Rotor%d" % int(rotor.id)
	var base := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	pivot.transform = Transform3D(base, body_point(rotor.hub_frd))
	root.add_child(pivot)
	# Keep the original mount marker for alignment audits, moving only its meshes to the spinning pivot.
	for child: Node3D in assembly.get_children():
		var at := PropellerBlur.relative(root, child)
		child.owner = null
		assembly.remove_child(child)
		pivot.add_child(child)
		child.transform = pivot.transform.affine_inverse() * at
		# Audit: only the blades break; the motor bell stays (PropBreak hides the whole pivot without this mark).
		if "blades" in str(child.name):
			child.set_meta(PropBreak.BREAKS_META, true)
	return {spin = signf(float(rotor.spin)), pivot = pivot, base = base, phase = 0.0, blur = null, speed = 0.0}


## One rotor view: a fixed motor bell from the arm-top plane up to the prop plane, and a pivot at the physics hub
## whose local +Z is the body up axis (PropellerBlur's spin-axis convention) carrying the solid blades.
func _build_rotor(rotor: Dictionary, motor_material: Material) -> Dictionary:
	var hub := body_point(rotor.hub_frd)
	var bell := CylinderMesh.new()
	bell.top_radius = MOTOR_RADIUS_M
	bell.bottom_radius = MOTOR_RADIUS_M
	bell.height = MOTOR_HEIGHT_M - 0.002
	_mesh(root, "Motor%d" % int(rotor.id), bell, motor_material,
		Transform3D(Basis.IDENTITY, hub - Vector3(0.0, 0.5 * MOTOR_HEIGHT_M + 0.001, 0.0)))
	var pivot := Node3D.new()
	pivot.name = "Rotor%d" % int(rotor.id)
	# local x = body right (render +X), local y = body forward (render −Z), local z = body up (render +Y).
	var base := Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0))
	pivot.transform = Transform3D(base, hub)
	root.add_child(pivot)
	var radius := 0.5 * float(rotor.diameter_m)
	var blade_material := StandardMaterial3D.new()
	blade_material.albedo_color = Color(0.08, 0.08, 0.09)
	blade_material.roughness = 0.6
	for blade in BLADES:
		var instance := MeshInstance3D.new()
		instance.name = "Blade%d" % blade
		instance.mesh = _blade_mesh(radius, blade_material)
		instance.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), TAU * blade / BLADES), Vector3.ZERO)
		pivot.add_child(instance)
	return {spin = signf(float(rotor.spin)), pivot = pivot, base = base, phase = 0.0, blur = null, speed = 0.0}


## A flat blade from near the hub to the tip along local +X (CPU-side arrays so the blur can measure it anywhere).
static func _blade_mesh(radius: float, material: Material) -> ArrayMesh:
	var box := BoxMesh.new()
	var length := radius - 0.006
	box.size = Vector3(length, BLADE_WIDTH_M, BLADE_THICKNESS_M)
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i] += Vector3(0.006 + 0.5 * length, 0.0, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


## pose: the activity's 13-value interpolated body; rotor_speed: achieved shaft speeds (rad/s, telemetry);
## frame_dt: presentation seconds since the last frame (0 while held, so the blades freeze).
func pose(body: PackedFloat64Array, rotor_speed: PackedFloat64Array, frame_dt: float) -> void:
	if root == null:
		return
	root.transform = Transform3D(Frames.quat_to_render(body.slice(6, 10)), Frames.ned_to_render([body[0], body[1], body[2]]))
	for i in rotors.size():
		var rotor: Dictionary = rotors[i]
		var omega := absf(rotor_speed[i]) if i < rotor_speed.size() and is_finite(rotor_speed[i]) else 0.0
		rotor.speed = omega
		rotor.phase = fposmod(float(rotor.phase) + float(rotor.spin) * omega * frame_dt, TAU)
		var pivot: Node3D = rotor.pivot
		var spin_basis := Basis(Vector3(0.0, 0.0, 1.0), float(rotor.phase))
		var health := float(rotor.get("health", 1.0))
		if health < 1.0 and health > 0.0:
			# DR-19d: a chipped prop runs out of balance: its disc wobbles once per turn.
			spin_basis = Basis(Vector3(1.0, 0.0, 0.0), DAMAGE_WOBBLE_RAD * (1.0 - health) * sin(float(rotor.phase))) * spin_basis
		pivot.transform = Transform3D((rotor.base as Basis) * spin_basis, pivot.transform.origin)
		if rotor.blur != null and is_instance_valid(rotor.blur):
			rotor.blur.update(omega * 60.0 / TAU)


## DR-19d: per-prop health from telemetry (1 intact … 0 broken). A broken prop's blades go (render/crash/prop_break.gd,
## which also keeps its blur disc hidden); a restored one (a pad restart) comes back; a damaged one wobbles in pose().
func set_rotor_health(health: PackedFloat64Array) -> void:
	for i in rotors.size():
		var rotor: Dictionary = rotors[i]
		var value := health[i] if i < health.size() and is_finite(health[i]) else 1.0
		rotor.health = value
		var broken: bool = rotor.has("break_records")
		if value <= 0.0 and not broken:
			rotor.break_records = PropBreak.break_blades(rotor.pivot)
		elif value > 0.0 and broken:
			PropBreak.restore(rotor.break_records)
			rotor.erase("break_records")


## Whether rotor `index` is shown broken (its blades removed).
func rotor_broken(index: int) -> bool:
	return rotors[index].has("break_records")


## Blur fraction of a rotor (0 = solid blades, 1 = disc only); -1 without a blur observer.
func blur_fraction(index: int) -> float:
	var blur: Variant = rotors[index].blur
	return float(blur.blur) if blur != null and is_instance_valid(blur) else -1.0
