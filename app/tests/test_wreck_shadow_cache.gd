extends SceneTree

# CR-22c-R2: cached shadows survive pooled wreck lifecycle changes.
const WreckScript = preload("res://render/crash/wreck.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var wreck := WreckScript.new()
	root.add_child(wreck)
	await process_frame
	var body: RigidBody3D = wreck._bodies[0]
	var shape: BoxShape3D = wreck._shape_nodes[0].shape as BoxShape3D
	var shadow: MeshInstance3D = wreck._shadows[0]
	var material: ShaderMaterial = wreck._shadow_materials[0]

	body.freeze = true
	body.visible = true
	body.global_transform = Transform3D(Basis.IDENTITY, Vector3(2.0, 2.0, -3.0))
	wreck._update_contact_shadow(0)
	_check("first visible body projects a floor shadow", shadow.visible and is_equal_approx(shadow.global_position.y, 0.012))
	_check("projection caches exact body transform and box size",
		wreck._shadow_cache_valid[0] == 1
		and wreck._shadow_cache_transforms[0] == body.global_transform
		and wreck._shadow_cache_shape_sizes[0] == shape.size)
	var first_shadow_transform := shadow.global_transform
	var first_opacity: float = float(material.get_shader_parameter("opacity"))
	wreck._update_contact_shadow(0)
	_check("unchanged inputs retain the same projected shadow output",
		shadow.global_transform == first_shadow_transform
		and float(material.get_shader_parameter("opacity")) == first_opacity)

	# A frozen body can still be teleported by a reset/release or editor-side reposition.
	var teleported := Transform3D(Basis.from_euler(Vector3(0.0, 0.25, 0.0)), Vector3(4.0, 1.5, 6.0))
	body.sleeping = true
	body.global_transform = teleported
	wreck._update_contact_shadow(0)
	_check("sleeping frozen teleport refreshes the shadow",
		wreck._shadow_cache_transforms[0] == body.global_transform
		and shadow.global_position.is_equal_approx(Vector3(4.0, 0.012, 6.0)))

	var before_size := shape.size
	var before_width := shadow.global_transform.basis.get_scale().x
	shape.size += Vector3(0.5, 0.0, 0.0)
	wreck._update_contact_shadow(0)
	_check("box size change refreshes the projection",
		wreck._shadow_cache_shape_sizes[0] == shape.size
		and shadow.global_transform.basis.get_scale().x > before_width)
	shape.size = before_size
	wreck._update_contact_shadow(0)

	wreck.global_transform = Transform3D(Basis.IDENTITY, Vector3(8.0, 0.0, -4.0))
	var world_body_transform: Transform3D = body.global_transform
	wreck._update_contact_shadow(0)
	_check("root transform changes are seen through body global transform",
		wreck._shadow_cache_transforms[0] == world_body_transform
		and shadow.global_position.is_equal_approx(Vector3(world_body_transform.origin.x, 0.012, world_body_transform.origin.z)))

	body.visible = false
	wreck._update_contact_shadow(0)
	_check("hidden body hides its shadow and invalidates its cache",
		not shadow.visible and wreck._shadow_cache_valid[0] == 0)
	# Re-showing the slot must project again even if its transform is unchanged.
	body.visible = true
	wreck._update_contact_shadow(0)
	_check("re-shown body repopulates the cache", shadow.visible and wreck._shadow_cache_valid[0] == 1)

	wreck.reset()
	_check("reset hides every pooled shadow and clears every cache slot", _pool_shadow_cache_clear(wreck))

	# prepare() must also invalidate a fresh projection while rebuilding pool shapes.
	body.visible = true
	wreck._update_contact_shadow(0)
	var airplane := Node3D.new()
	root.add_child(airplane)
	await process_frame
	var prepared: bool = wreck.prepare(airplane)
	_check("empty test airframe prepares", prepared)
	_check("prepare leaves shadows hidden and cache invalid", _pool_shadow_cache_clear(wreck))

	print("%d checks, %d failures" % [checks, failures])
	wreck.free()
	airplane.free()
	quit(1 if failures else 0)


func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("ok " if passed else "FAIL ") + label)


func _pool_shadow_cache_clear(wreck: Node) -> bool:
	for shadow: MeshInstance3D in wreck._shadows:
		if shadow.visible:
			return false
	for valid in wreck._shadow_cache_valid:
		if int(valid) != 0:
			return false
	return true
