## LU-05 secondary wreck contacts. Float64 flight detection remains authoritative; these disposable bodies
## exist only around the crash, on the crash presentation's isolated layer, and are removed on reset.
extends RefCounted
const Frames := preload("res://render/frames.gd")
const WreckScene := preload("res://render/crash/wreck.gd")
const RANGE_M := 65.0
const MAX_BODIES := 160

static func build_near(world: Dictionary, point_ned: PackedFloat64Array) -> Node3D:
	var root := Node3D.new()
	root.name = "SceneryWreckContacts"
	if point_ned.size() != 3:
		return root
	var count := 0
	for proxy: Dictionary in world.get("proxies", []):
		# Leaves do not become solid walls when an aircraft breaks up.
		if str(proxy.get("response_class", "")) == "soft_foliage_impulse":
			continue
		var margin := maxf(float(proxy.get("radius", 0.0)), maxf(float(proxy.get("half_x", 0.0)), float(proxy.get("half_z", 0.0))))
		if absf(float(proxy.north) - point_ned[0]) > RANGE_M + margin or absf(float(proxy.east) - point_ned[1]) > RANGE_M + margin:
			continue
		if count >= MAX_BODIES:
			push_warning("Scenery wreck contact budget reached; farther secondary contacts omitted.")
			break
		var body := StaticBody3D.new()
		body.name = "Obstacle%d" % count
		body.collision_layer = WreckScene.DEBRIS_LAYER
		body.collision_mask = 0
		body.position = Frames.ned_to_render([proxy.north, proxy.east, proxy.down])
		body.rotation.y = -atan2(float(proxy.get("sin_heading", 0.0)), float(proxy.get("cos_heading", 1.0)))
		var material := PhysicsMaterial.new()
		material.friction = 0.7
		material.bounce = 0.04
		body.physics_material_override = material
		var shape := CollisionShape3D.new()
		if proxy.shape == "capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = maxf(0.01, float(proxy.radius))
			capsule.height = 2.0 * (float(proxy.half_length) + capsule.radius)
			shape.shape = capsule
		else:
			var box := BoxShape3D.new()
			box.size = Vector3(float(proxy.half_x) * 2.0, float(proxy.half_down) * 2.0, float(proxy.half_z) * 2.0)
			shape.shape = box
		body.add_child(shape)
		body.set_meta("obstacle_id", proxy.id)
		root.add_child(body)
		count += 1
	root.set_meta("bodies", count)
	return root
