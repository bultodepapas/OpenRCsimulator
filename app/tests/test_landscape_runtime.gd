## LU-06: actual production flight, scenery CCD, wreck contacts, pause and repeated reset.
extends SceneTree
const Flight := preload("res://main.gd")
const Frames := preload("res://render/frames.gd")
const RB := preload("res://physics/rigid_body.gd")
const WreckScene := preload("res://render/crash/wreck.gd")
var failures := 0
var checks := 0
var out := ""

func _initialize() -> void:
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
	else:
		print("ok ", label)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var flight := Flight.new()
	root.add_child(flight)
	await process_frame
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	var world: Dictionary = flight.session.collision_world()
	check("production flight installs a nonempty collision world", world.get("proxies", []).size() > 3000)
	var identity: String = world.get("identity", "")
	var evidence := {cases = {}, engine = Engine.get_version_info(), checks = 0, failures = 0}
	for kind: String in ["vehicle", "building", "tree_trunk", "lamp", "parked_aircraft"]:
		flight.session.reset()
		var target := {}
		for proxy: Dictionary in world.get("proxies", []):
			if proxy.kind != kind:
				continue
			if kind == "building" and proxy.part != "pavilion":
				continue
			if kind == "lamp" and proxy.part != "flood_pole":
				continue
			if kind == "parked_aircraft" and not "p51d" in str(proxy.id):
				continue
			target = proxy
			break
		check("production inventory includes " + kind, not target.is_empty())
		if target.is_empty():
			continue
		var height := maxf(0.65, -float(target.down))
		# Aim through the gap between shelter posts at the parked P-51's wing.
		var east_offset := -1.1 if kind == "parked_aircraft" else 0.0
		var north_offset := 4.0 if kind == "parked_aircraft" else -10.0
		var attitude := PackedFloat64Array([0.0,0.0,0.0,1.0]) if kind == "parked_aircraft" else PackedFloat64Array([1.0,0.0,0.0,0.0])
		var start := RB.make_state(PackedFloat64Array([float(target.north)+north_offset, float(target.east)+east_offset, -height]),
			PackedFloat64Array([80.0, 0.0, 0.0]), attitude, PackedFloat64Array([0.0,0.0,0.0]))
		flight.session.sim.state = start.duplicate()
		flight.session.sim.previous = start.duplicate()
		flight.session.sim.set_paused(false)
		for tick in 100:
			flight.session.sim.step()
			if not flight.session.crash.is_empty():
				break
		var impact: RefCounted = flight.session.crash.get("impact")
		check("80 m/s real aircraft reaches scenery crash: " + kind, impact != null and impact.trigger == "scenery")
		if impact == null or impact.trigger != "scenery":
			continue
		check("contact is with requested object type: " + kind, impact.obstacle_kind == kind)
		flight._process(1.0/60.0)
		var director = flight._crash_director
		check("scenery starts existing crash director: " + kind, director != null and director.active)
		var bodies: Node = director.get_node_or_null("SceneryWreckContacts")
		check("secondary contacts are present and bounded: " + kind, bodies != null and bodies.get_child_count() > 0 and bodies.get_child_count() <= 160)
		check("wall/tree normal reaches severity report: " + kind, director.report.get("surface", "") == impact.obstacle_kind and director.report.get("obstacle_id", "") == impact.obstacle_id)
		check("impact presentation preserves altitude: " + kind, absf(director._impact_point.y + impact.point_ned[2]) < 0.0001)
		await physics_frame
		var center := Frames.ned_to_render([target.north, target.east, target.down])
		var query := PhysicsRayQueryParameters3D.create(center+Vector3(0,0,10), center-Vector3(0,0,10), WreckScene.DEBRIS_LAYER)
		var hit := flight.get_world_3d().direct_space_state.intersect_ray(query)
		check("engine secondary collision shapes answer ray query: " + kind, not hit.is_empty())
		flight.session.hold("landscape-test")
		flight._process(0.0)
		var age: float = director._age
		flight._process(0.5)
		check("pause holds crash effect age: " + kind, director._age == age)
		flight.session.release("landscape-test")
		if not out.is_empty() and DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(out)
			flight._camera.position = director._impact_point + Vector3(5,3.2,6)
			flight._camera.look_at(director._impact_point + Vector3.UP*0.3)
			flight._camera.fov = 58
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("collision_"+kind+".png"))
		evidence.cases[kind] = {obstacle = impact.obstacle_id, normal_speed_mps = impact.normal_speed_mps,
			contact_height_m = -impact.point_ned[2], collision_bodies = bodies.get_child_count(),
			impact_fraction = impact.time_fraction, severity = director.report.get("class"), trace_tick = impact.tick}
		flight.session.reset()
		check("reset removes scenery contacts and restores aircraft: " + kind, director.get_node_or_null("SceneryWreckContacts") == null and not director.active and flight._airplane.root.visible)
		check("reset clears contact state and retains world identity: " + kind, flight.session.crash.is_empty() and flight.session.last_scenery_event() == null and flight.session.collision_world().identity == identity)
	flight.free()
	evidence.checks = checks
	evidence.failures = failures
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		FileAccess.open(out.path_join("runtime.json"), FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
