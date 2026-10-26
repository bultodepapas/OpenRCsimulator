extends SceneTree
const Effects = preload("res://render/crash/effects.gd")
const Wreck = preload("res://render/crash/wreck.gd")
const Warmup = preload("res://render/crash/shader_warmup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok: failures += 1
	print(("ok " if ok else "FAIL ") + label)

func _run() -> void:
	var owner_node := Node3D.new()
	root.add_child(owner_node)
	var sun := DirectionalLight3D.new()
	owner_node.add_child(sun)
	var camera := Camera3D.new()
	owner_node.add_child(camera)
	camera.position = Vector3(3, 4, 5)
	camera.fov = 47
	camera.current = true
	var camera_pose := camera.global_transform
	var fx := Effects.new()
	owner_node.add_child(fx)
	fx.prepare()
	var wreck := Wreck.new()
	owner_node.add_child(wreck)
	var original_children := owner_node.get_child_count()
	var original_buses := AudioServer.bus_count
	var before := _pool_state(fx, wreck)
	for repeat in 2:
		var result := Warmup.prepare(owner_node, fx, wreck._shadows[0], sun)
		_check("warmup backend gate %d" % repeat, result.drawn == (DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "gl_compatibility"))
		_check("warmup leaves live pools and seeds untouched %d" % repeat, before == _pool_state(fx, wreck))
		_check("warmup removes temporary nodes and owns no audio %d" % repeat, owner_node.get_child_count() == original_children and AudioServer.bus_count == original_buses)
		_check("warmup preserves the active flight camera %d" % repeat, root.get_camera_3d() == camera and camera.global_transform == camera_pose and camera.fov == 47)
	fx.start(Vector3.ZERO, Vector3(12, -20, 0), {"class": 0}, 0, false, Vector3.ZERO)
	_check("C0 starts no particle draw", fx.emitters.all(func(p): return not p.visible and not p.emitting))
	fx.start(Vector3.ZERO, Vector3(12, -20, 0), {"class": 4, "severity": 1.0, "surface": "grass"}, 0, false, Vector3.ZERO)
	_check("grass impact starts dust", fx.dust.visible and fx.dust.emitting)
	_check("no unrelated flash sparks touch or blade particles", [fx.fireball, fx.sparks, fx.touch_dust, fx.blade_chips].all(func(p): return not p.visible and not p.emitting))
	_check("no premature fire or vent", [fx.flame, fx.smoke, fx.vent].all(func(p): return not p.visible and not p.emitting))
	fx.apply_energy({"vent_delay_s": 5.0, "vent_s": 20.0, "flare": true})
	_check("delayed vent stays hidden until due", not fx.vent.visible)
	for i in 101: fx.update(0.05, false)
	_check("delayed vent and flare start when due", fx.vent.visible and fx.vent.emitting and fx.flame.visible and fx.flame.emitting)
	for i in 405: fx.update(0.05, false)
	_check("ended vent and flare retain visible particles to fade", fx.vent.visible and not fx.vent.emitting and fx.flame.visible and not fx.flame.emitting)
	fx.reset()
	_check("reset hides and stops every emitter", fx.emitters.all(func(p): return not p.visible and not p.emitting))
	fx.start(Vector3.ZERO, Vector3(12, -20, 0), {"class": 4, "severity": 1.0, "tank_ruptured": true}, 1.0, true, Vector3.ZERO)
	_check("hot fuel fire still starts immediately", fx.flame.visible and fx.flame.emitting and fx.smoke.visible and fx.smoke.emitting)
	for i in 580: fx.update(0.05, false)
	_check("extinguished fuel fire leaves its last particles visible to fade", fx.flame.visible and not fx.flame.emitting and fx.smoke.visible and not fx.smoke.emitting)
	owner_node.free()
	await process_frame
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _pool_state(fx: Node, wreck: Node) -> Array:
	var state: Array = [fx.stats(), fx.fragments.multimesh.visible_instance_count, fx._rng.state, fx.fragments.multimesh.get_instance_transform(0)]
	for p: CPUParticles3D in fx.emitters:
		state.append([p.get_instance_id(), p.transform, p.visible, p.emitting, p.seed, p.mesh.get_rid(), p.speed_scale])
	for mark: MeshInstance3D in fx.marks:
		state.append([mark.visible, mark.transform, mark.material_override.get_instance_id()])
	for decal: Decal in fx.mark_decals:
		state.append([decal.visible, decal.transform, decal.modulate])
	for body: RigidBody3D in wreck._bodies:
		state.append([body.get_instance_id(), body.transform, body.freeze, body.visible, body.collision_layer, body.collision_mask])
	return state
