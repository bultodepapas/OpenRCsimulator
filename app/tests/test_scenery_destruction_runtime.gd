## CR-17a: actual production scene -> accepted tick -> damage signal -> mesh -> checkpoint -> reset.
## One synthetic CG probe isolates the integration from the aircraft's sparse hull coverage.
extends SceneTree
const Flight := preload("res://main.gd")
const RB := preload("res://physics/rigid_body.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	OS.set_environment("OPENRC_SCENERY_AUDIO", "off")
	call_deferred("_run")

func _run() -> void:
	var flight := Flight.new()
	root.add_child(flight)
	await process_frame
	flight.set_process(false)
	flight.session.set_physics_process(false)
	flight.session.sim.set_physics_process(false)
	flight.session.input_enabled = false
	var world: Dictionary = flight.session.collision_world()
	var target := {}
	for proxy: Dictionary in world.get("proxies", []):
		if str(proxy.id).begins_with("fence:fence-north:") and proxy.part == "wire":
			target = proxy
			break
	_check("production scene has wire fence and destruction controller", not target.is_empty() and flight._scenery_damage_director != null)
	if target.is_empty():
		flight.free()
		quit(1)
		return
	flight.session.aircraft.model.crash_hull = PackedFloat64Array([0,0,0])
	var controller = flight._scenery_damage_director
	var source: MeshInstance3D = null
	for candidate: MeshInstance3D in controller._sources:
		for item: Dictionary in candidate.get_meta("damage_ranges", []):
			if item.id == target.damage_id:
				source = candidate
	_check("same contact ID identifies batched visible wire", source != null)
	var original: Mesh = source.mesh
	var start := RB.make_state(PackedFloat64Array([target.north - 0.03, target.east, target.down]),
		PackedFloat64Array([80,0,0]), PackedFloat64Array([1,0,0,0]), PackedFloat64Array([0,0,0]))
	flight.session.sim.state = start.duplicate()
	flight.session.sim.previous = start.duplicate()
	flight.session.sim.set_paused(false)
	flight.session.sim.step()
	var damage: Dictionary = flight.session.scenery_damage()
	_check("accepted flight tick breaks the actual wire", damage.has(target.damage_id) and damage[target.damage_id].state == "broken")
	_check("signal removes wire geometry in the production scene", source.mesh != original and source.mesh.surface_get_array_len(0) < original.surface_get_array_len(0))
	_check("signal creates torn ends in the production controller", controller._groups.size() == 1 and controller._groups[0].root.get_child_count() > 0)
	flight._process(1.0 / 60.0)
	var checkpoint: Dictionary = flight.session.checkpoint()
	_check("full production inventory accepts its damaged checkpoint", flight.session.restore_checkpoint(checkpoint) and flight.session.scenery_damage() == damage)
	_check("restore preserves the local geometry gap", source.mesh != original)
	flight.session.reset()
	_check("restart heals collision, geometry and aftermath", flight.session.scenery_damage().is_empty() and source.mesh == original and controller._groups.is_empty())
	flight.free()
	await physics_frame
	await process_frame
	print("scenery destruction runtime: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
