## CAM-FPV-02a: verify the nose view against the assembled aircraft and all stock paints.
extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const Mounts := preload("res://render/camera/fpv_stock_mounts.gd")
const Paint := preload("res://render/vehicle_paint.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAIL ", label)
		failures += 1


## In the level lens frame every pixel ray points into -Z. Putting every mesh's entire box
## behind the eye establishes clearance at the edges too, independently of near clipping.
func _check_clearance(model_root: Node3D, mount: Transform3D, label: String) -> void:
	var eye_from_model := mount.affine_inverse()
	var min_depth := INF
	var limiting_mesh := ""
	for node: Node in model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		var eye_from_part := eye_from_model * PropellerBlur.relative(model_root, part)
		var bounds := eye_from_part * part.mesh.get_aabb()
		if bounds.position.z < min_depth:
			min_depth = bounds.position.z
			limiting_mesh = str(part.name)
	_check(is_finite(min_depth) and min_depth > 0.010,
		"%s: full forward half-space clears aircraft by >10 mm (closest %s, %.5f m)" % [label, limiting_mesh, min_depth])


func _run() -> void:
	var airplane := Airplane.build(Mounts.BASIC_STIK)
	var front := Mounts.front(airplane)
	_check(not front.is_empty(), "stock Ugly Stik has a nose view")
	if not front.is_empty():
		var model_root: Node3D = airplane.root
		var propeller: Node3D = airplane.propeller
		var mount: Transform3D = front.mount
		# Even the outer corners at both joint stops face away from the airframe.
		# A square viewport is the widest vertical field among the supported landscape displays.
		var stops: Vector2 = front.look_limits_deg
		for yaw: float in [-stops.x, stops.x]:
			for pitch: float in [-stops.y, stops.y]:
				var axes := Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
				for x: float in [-1.0, 1.0]:
					for y: float in [-1.0, 1.0]:
						_check((axes * Vector3(x, y, -1.0)).z < 0.0, "gimbal stop retains forward clearance")
		_check(front.id == "front" and front.provenance == "derived", "stable mount identity")
		_check(mount.basis == Basis.IDENTITY and is_equal_approx(front.hfov_deg, 90.0)
			and is_equal_approx(front.near_m, 0.03), "level rectilinear optics")
		_check(is_equal_approx(mount.origin.x, propeller.position.x) and is_equal_approx(mount.origin.y, propeller.position.y),
			"eye lies on the built propeller shaft axis")
		for skin: Dictionary in Paint.choices(Mounts.BASIC_STIK):
			var painted := Paint.apply(model_root, Mounts.BASIC_STIK, str(skin.id))
			_check(painted.ok, "apply stock paint %s" % skin.id)
			_check_clearance(model_root, mount, str(skin.id))
		propeller.rotation.z = 1.3
		_check((Mounts.front(airplane).mount as Transform3D).is_equal_approx(mount), "spinning prop leaves mount fixed")
		_check_clearance(model_root, mount, "rotated propeller")
		# Test the optical half-space using the blur disc actually generated at high RPM.
		var measured := PropellerBlur.profile(propeller)
		_check(not measured.is_empty(), "the installed propeller supplies a blur profile")
		if not measured.is_empty():
			_check(propeller.position.z + float(measured.plane_z) - mount.origin.z > 0.010, "blur disc behind eye")
		var changed: Dictionary = airplane.duplicate()
		for key: String in ["aircraft_id", "visual_family", "model_manifest_sha256"]:
			changed[key] = "other"
			_check(Mounts.front(changed).is_empty(), "unadmitted %s" % key)
			changed[key] = airplane[key]
	_check(Mounts.front({}).is_empty(), "unbound visual has no view")
	if airplane.get("root") is Node:
		airplane.root.free()
	print("Stock FPV nose mount: %d failed" % failures)
	quit(1 if failures else 0)
