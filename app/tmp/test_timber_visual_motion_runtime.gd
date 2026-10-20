extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Motion := preload("res://aircraft/timber_visual_motion.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool, detail: String = "") -> void:
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		failures += 1

func _run() -> void:
	var entry: Dictionary = Catalog.entry("turbo-lumber-evolution")
	var session: Node = Session.new()
	session.input_enabled = false
	session.setup(str(entry.data))
	_check("session setup", session.sim != null and session.is_flyable(), str(session.start_error))
	root.add_child(session)
	var field_result: Dictionary = FieldLoader.load_from()
	_check("default field loaded", field_result.ok, str(field_result.errors))
	_check("field assigned", session.set_field(field_result.field))
	session.start_choice = Session.START_RUNWAY
	session.reset()
	_check("runway pose is flyable", session.is_flyable(), str(session.start_error))
	var airplane: Dictionary = Airplane.build("turbo-lumber-evolution")
	root.add_child(airplane.root)
	var ground: Node = GroundGear.attach(airplane, session)
	var motion: Node = Motion.attach(airplane, session)
	_check("motion observer attaches", motion != null)
	if motion == null:
		quit(1)
		return
	var compression: PackedFloat64Array = session.gear_compressions(session.sim.state)
	ground._process(0.0)
	motion._process(0.0)
	_check("both main gear contacts are compressed", compression.size() >= 2 and compression[0] > 0.0 and compression[1] > 0.0,
		str(compression))
	for leg: Dictionary in motion._legs:
		var wheel: Node3D = leg.wheel
		var axle: Node3D = leg.axle
		var root_axis: Vector3 = motion._airplane.root.global_basis.transposed() * Vector3.UP
		var displacement: Vector3 = motion._airplane.root.to_local(axle.global_position) - leg.tip_root
		var projected_height: float = displacement.dot(root_axis)
		var expected: float = float(compression[leg.contact_index])
		_check("%s axle preserves contact height" % leg.role, absf(projected_height - expected) < 1e-5,
			"render %.6f m; evaluator %.6f m" % [projected_height, expected])
		_check("%s wheel spin angle is unchanged" % leg.role, absf(wheel.rotation.x) < 1e-7,
			str(wheel.rotation.x))
		var hinge_delta: Basis = leg.hinge.transform.basis * leg.hinge_rest.basis.inverse()
		var hinge_motion: float = hinge_delta.get_euler().length()
		_check("%s spring leg articulates inside cable limit" % leg.role,
			hinge_motion > 1.0e-4 and hinge_motion <= deg_to_rad(6.01), str(rad_to_deg(hinge_motion)))
	var cable_motion := 0.0
	for surface_index in motion._cable_surfaces.size():
		var original: PackedVector3Array = motion._cable_surfaces[surface_index].vertices
		var current_arrays: Array = motion._cables.mesh.surface_get_arrays(surface_index)
		var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in original.size():
			cable_motion = maxf(cable_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("cross-cables follow the spring legs", cable_motion > 1.0e-5, "%.6f m" % cable_motion)
	_check("cross-cable resource is a private ArrayMesh", motion._cables.mesh is ArrayMesh)
	_check("both added extension springs have followers", motion._spring_followers.size() == 2,
		"%d follower(s)" % motion._spring_followers.size())
	var spring_motion := 0.0
	for follower: Dictionary in motion._spring_followers:
		for surface_index in follower.surfaces.size():
			var original: PackedVector3Array = follower.surfaces[surface_index].vertices
			var current_arrays: Array = follower.mesh.surface_get_arrays(surface_index)
			var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
			for vertex_index in original.size():
				spring_motion = maxf(spring_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("extension spring coils follow the spring legs", spring_motion > 1.0e-5, "%.6f m" % spring_motion)
	session.reset()
	var reset_cable_motion := 0.0
	for surface_index in motion._cable_surfaces.size():
		var original: PackedVector3Array = motion._cable_surfaces[surface_index].vertices
		var current_arrays: Array = motion._cables.mesh.surface_get_arrays(surface_index)
		var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in original.size():
			reset_cable_motion = maxf(reset_cable_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("reset restores neutral cable pose", reset_cable_motion < 1.0e-6, "%.6f m" % reset_cable_motion)
	var reset_spring_motion := 0.0
	for follower: Dictionary in motion._spring_followers:
		for surface_index in follower.surfaces.size():
			var original: PackedVector3Array = follower.surfaces[surface_index].vertices
			var current_arrays: Array = follower.mesh.surface_get_arrays(surface_index)
			var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
			for vertex_index in original.size():
				reset_spring_motion = maxf(reset_spring_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("reset restores neutral extension springs", reset_spring_motion < 1.0e-6, "%.6f m" % reset_spring_motion)
	var twin := airplane.root.duplicate() as Node3D
	root.add_child(twin)
	var twin_motion := twin.get_node_or_null("TimberVisualMotion")
	var twin_cables := twin.find_child("gear_cables", true, false) as MeshInstance3D
	var twin_springs := twin.find_children("TimberExtensionSpring_*", "MeshInstance3D", true, false)
	_check("Wreck-style copy disables the observer", twin_motion != null and twin_motion.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("Wreck-style copy drops its session reference", twin_motion != null and twin_motion._session == null)
	_check("Wreck-style copy owns an independent cable mesh", twin_cables != null and twin_cables.mesh != motion._cables.mesh)
	var spring_resources_independent: bool = twin_springs.size() == motion._spring_followers.size()
	for follower: Dictionary in motion._spring_followers:
		var matching: MeshInstance3D = twin.find_child(str(follower.node.name), true, false) as MeshInstance3D
		spring_resources_independent = spring_resources_independent and matching != null and matching.mesh != follower.mesh
	_check("Wreck-style copy owns independent spring meshes", spring_resources_independent)
	twin.queue_free()
	airplane.root.queue_free()
	session.queue_free()
	await process_frame
	print("runtime motion checks finished: %d failure(s)" % failures)
	quit(1 if failures else 0)
