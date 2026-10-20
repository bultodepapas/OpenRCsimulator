extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Airplane := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const Motion := preload("res://aircraft/timber_visual_motion.gd")
const WreckScript := preload("res://render/crash/wreck.gd")
const GroundWheels := preload("res://physics/ground_wheels.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")

var failures := 0
var check_count := 0
var results: Array[Dictionary] = []
var metrics: Dictionary = {}
var report_output_override := ""

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			report_output_override = arg.trim_prefix("--out=")
	_run.call_deferred()

func _check(label: String, ok: bool, detail: String = "") -> void:
	check_count += 1
	results.append({"check": label, "passed": ok, "detail": detail})
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		failures += 1

func _wreck_groups(wreck: Node) -> Array:
	var records: Array = []
	for group: Dictionary in wreck._prepared_groups:
		records.append({
			kind = group.get("kind", ""),
			bounds = str(group.bounds),
			center = str(group.center),
			member_bounds = str(group.get("member_bounds", [])),
		})
	return records

func _same_floats(left: PackedFloat64Array, right: PackedFloat64Array) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true

func _dust_checks(motion: Node, session: Node, compression: PackedFloat64Array) -> void:
	var state: PackedFloat64Array = session.sim.state
	var contacts: Array = session.current_landing_gear().get("contacts", [])
	if contacts.is_empty() or compression.is_empty():
		_check("dust contact fixture exists", false)
		return
	var contact: Dictionary = contacts[0]
	var surfaces_original: PackedFloat64Array = session.ground_surfaces.duplicate()
	var surfaces_test: PackedFloat64Array = surfaces_original.duplicate()
	var steer: float = session.sim.aux[session.AUX_SERVO + 2]
	var frame: Dictionary = GroundWheels.frame(state, contact, steer, surfaces_original,
		PackedFloat64Array(), false, {})
	var position: PackedFloat64Array = frame.get("position", PackedFloat64Array())
	var surface_index := GroundWheels.surface_at(surfaces_original, float(position[0]), float(position[1]))
	var normal_load := float(frame.get("normal_load", 0.0))
	_check("runway wheel has a loaded contact", compression[0] > 0.0 and normal_load >= 2.0,
		"compression=%.4f m load=%.3f N" % [compression[0], normal_load])
	if surface_index < 0 or surface_index + 5 >= surfaces_test.size():
		_check("dust fixture maps to a ground surface", false)
		return
	var original_continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	var first_wheel: int = session.wheel_index()
	var wheel_count: int = session.wheel_count()
	var test_continuous: PackedFloat64Array = original_continuous.duplicate()
	var wheel_relative_speed := float(frame.get("long_speed", 0.0)) + 1.5
	if first_wheel < 0 or first_wheel >= test_continuous.size() or wheel_count <= 0:
		_check("dust fixture finds wheel telemetry", false)
		return
	test_continuous[first_wheel] = wheel_relative_speed
	session.sim.continuous = test_continuous
	surfaces_test[surface_index + 5] = 5.0
	session.ground_surfaces = surfaces_test
	motion._update_contact_dust(state, contacts, compression)
	var emitter: CPUParticles3D = motion._dust_emitters[0]
	_check("real loaded slip on rough ground emits tire dust", emitter.emitting)
	session.ground_surfaces = surfaces_original
	motion._update_contact_dust(state, contacts, compression)
	_check("same slip on paved runway emits no tire dust", not emitter.emitting)
	var airborne_compression := compression.duplicate()
	airborne_compression[0] = 0.0
	motion._update_contact_dust(state, contacts, airborne_compression)
	_check("airborne wheel without compression emits no dust", not emitter.emitting)
	session.sim.continuous = original_continuous
	var telemetry_restored := _same_floats(original_continuous, session.sim.continuous)
	_check("dust fixture restores injected wheel telemetry", telemetry_restored)
	metrics["dust_fixture_telemetry_restored"] = telemetry_restored
	var holds: Dictionary = session.holds
	holds["motion_test"] = true
	session.holds = holds
	motion._update_contact_dust(state, contacts, compression)
	_check("paused session freezes and stops new dust", not emitter.emitting and emitter.speed_scale == 0.0)
	holds.erase("motion_test")
	session.holds = holds
	session.ground_surfaces = surfaces_test
	session.sim.continuous = test_continuous
	session.sim.set_paused(true)
	motion._update_contact_dust(state, contacts, compression)
	var focus_paused: bool = session.holds.is_empty() and session.sim.paused \
		and not emitter.emitting and emitter.speed_scale == 0.0
	_check("focus-style simulation pause freezes dust without a hold", focus_paused)
	metrics["focus_pause_stops_dust"] = focus_paused
	session.sim.set_paused(false)
	session.sim.continuous = original_continuous
	session.ground_surfaces = surfaces_original
	motion._update_contact_dust(state, contacts, compression)

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
	var baseline_wreck := WreckScript.new()
	root.add_child(baseline_wreck)
	_check("baseline wreck prepares before motion observer", baseline_wreck.prepare(airplane.root))
	var baseline_groups := _wreck_groups(baseline_wreck)
	var ground: Node = GroundGear.attach(airplane, session)
	var motion: Node = Motion.attach(airplane, session)
	_check("motion observer attaches", motion != null)
	if motion == null:
		quit(1)
		return
	var attached_wreck := WreckScript.new()
	root.add_child(attached_wreck)
	_check("Wreck prepares after observer attachment at rest", attached_wreck.prepare(airplane.root))
	var attached_groups := _wreck_groups(attached_wreck)
	_check("observer attachment preserves prepared Wreck section bounds and centers",
		attached_groups == baseline_groups)
	var compression: PackedFloat64Array = session.gear_compressions(session.sim.state)
	var main_gear_compression: Array[float] = []
	for leg: Dictionary in motion._legs:
		var index: int = leg.contact_index
		if index >= 0 and index < compression.size():
			main_gear_compression.append(float(compression[index]))
	var state_before: PackedFloat64Array = session.sim.state.duplicate()
	var continuous_before: PackedFloat64Array = session.sim.continuous.duplicate()
	var aux_before: PackedFloat64Array = session.sim.aux.duplicate()
	ground._process(0.0)
	motion._process(0.0)
	var body_unchanged := _same_floats(state_before, session.sim.state)
	var continuous_unchanged := _same_floats(continuous_before, session.sim.continuous)
	var aux_unchanged := _same_floats(aux_before, session.sim.aux)
	var wreck_groups_unchanged := _wreck_groups(attached_wreck) == attached_groups
	_check("motion observers leave simulation state unchanged", body_unchanged)
	_check("motion observers leave continuous state unchanged", continuous_unchanged)
	_check("motion observers leave auxiliary state unchanged", aux_unchanged)
	_check("precomputed Wreck bounds stay fixed while the observer moves gear", wreck_groups_unchanged)
	metrics["simulation_writes"] = {
		"body_state": not body_unchanged,
		"continuous": not continuous_unchanged,
		"auxiliary": not aux_unchanged,
	}
	metrics["wreck_prepared_groups_unchanged"] = wreck_groups_unchanged
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
		if not metrics.has("loaded_hinge_degrees"):
			metrics["loaded_hinge_degrees"] = []
		(metrics["loaded_hinge_degrees"] as Array).append(rad_to_deg(hinge_motion))
	var cable_motion := 0.0
	for surface_index in motion._cable_surfaces.size():
		var original: PackedVector3Array = motion._cable_surfaces[surface_index].vertices
		var current_arrays: Array = motion._cables.mesh.surface_get_arrays(surface_index)
		var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in original.size():
			cable_motion = maxf(cable_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("cross-cables follow the spring legs", cable_motion > 1.0e-5, "%.6f m" % cable_motion)
	metrics["loaded_compression_m"] = Array(compression)
	var suspension: Dictionary = TimberGeometry.DATA.get("landing_gear", {}).get("suspension", {})
	var travel: Dictionary = suspension.get("travel_deg", {}).get("value", {})
	metrics["authored_travel_degrees"] = float(travel.get("value", 0.0))
	metrics["cable_safe_articulation_limit_degrees"] = rad_to_deg(motion._max_travel_rad)
	metrics["cable_vertex_delta_m"] = cable_motion
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
	metrics["spring_vertex_delta_m"] = spring_motion
	_dust_checks(motion, session, compression)
	session.reset()
	var reset_cable_motion := 0.0
	for surface_index in motion._cable_surfaces.size():
		var original: PackedVector3Array = motion._cable_surfaces[surface_index].vertices
		var current_arrays: Array = motion._cables.mesh.surface_get_arrays(surface_index)
		var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in original.size():
			reset_cable_motion = maxf(reset_cable_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("reset restores neutral cable pose", reset_cable_motion < 1.0e-6, "%.6f m" % reset_cable_motion)
	metrics["rest_cable_vertex_delta_m"] = reset_cable_motion
	var reset_spring_motion := 0.0
	for follower: Dictionary in motion._spring_followers:
		for surface_index in follower.surfaces.size():
			var original: PackedVector3Array = follower.surfaces[surface_index].vertices
			var current_arrays: Array = follower.mesh.surface_get_arrays(surface_index)
			var current: PackedVector3Array = current_arrays[Mesh.ARRAY_VERTEX]
			for vertex_index in original.size():
				reset_spring_motion = maxf(reset_spring_motion, original[vertex_index].distance_to(current[vertex_index]))
	_check("reset restores neutral extension springs", reset_spring_motion < 1.0e-6, "%.6f m" % reset_spring_motion)
	metrics["rest_spring_vertex_delta_m"] = reset_spring_motion
	motion._stop_after_crash()
	_check("crash stops visual motion updates", motion._stopped and not motion.is_processing())
	session.reset()
	_check("reset resumes visual motion updates", not motion._stopped and motion.is_processing())
	var transforms_restored := true
	for leg: Dictionary in motion._legs:
		transforms_restored = transforms_restored \
			and (leg.hinge as Node3D).transform.is_equal_approx(leg.hinge_rest) \
			and (leg.wheel as Node3D).position.is_equal_approx(leg.wheel_rest) \
			and (leg.axle as Node3D).transform.is_equal_approx(leg.axle_rest)
	_check("reset restores suspension and axle transforms", transforms_restored)
	_check("reset clears dust emission", not (motion._dust_emitters[0] as CPUParticles3D).emitting)
	_check("reset resumes particle clock", (motion._dust_emitters[0] as CPUParticles3D).speed_scale == 1.0)
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
	attached_wreck.queue_free()
	baseline_wreck.queue_free()
	airplane.root.queue_free()
	session.queue_free()
	await process_frame
	var report := {
		"schema": "timber-visual-motion-runtime-v1",
		"capture": {
			"image": "research/timber/visual-upgrade/timber-gear-motion.png",
			"pose": "full_contact",
			"source": "default-field runway reset; loaded wheel contacts",
			"resolution_px": [1280, 960],
			"camera_position_m": [0.12, -0.18, 0.37],
			"camera_look_at_m": [0.0, -0.125, 0.025],
		},
		"read_only_scope": "GroundGear and TimberVisualMotion render updates",
		"dust_fixture_uses_temporary_wheel_slip_override": true,
		"checks": check_count,
		"failures": failures,
		"results": results,
		"poses": {
			"rest": {"hinge_degrees": [0.0, 0.0], "cable_vertex_delta_m": 0.0,
				"spring_vertex_delta_m": 0.0, "main_gear_wheel_wrapper_compression_m": [0.0, 0.0]},
			"full_contact": {
				"description": "Settled default-field runway pose at evaluator contact compression; suspension arc stays within the 6-degree cable-safe render limit.",
				"main_gear_wheel_wrapper_compression_m": main_gear_compression,
				"main_gear_axle_contact_height_m": main_gear_compression.duplicate(),
				"all_wheel_contact_compression_m": Array(compression),
				"hinge_degrees": metrics.get("loaded_hinge_degrees", []),
				"cable_vertex_delta_m": cable_motion,
				"spring_vertex_delta_m": spring_motion,
				"wheel_spin_radians": [0.0, 0.0],
				"metrics": metrics,
			},
		},
	}
	var report_path := ProjectSettings.globalize_path(report_output_override if not report_output_override.is_empty()
		else "res://../docs/research/timber-integration/TT-20/motion-runtime-checks.json")
	var report_file := FileAccess.open(report_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t") + "\n")
	else:
		failures += 1
		printerr("Could not write runtime motion report: ", report_path)
	print("runtime motion checks finished: %d checks, %d failure(s); report: %s" % [check_count, failures, report_path])
	quit(1 if failures else 0)
