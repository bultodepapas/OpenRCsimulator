## CAM-FPV-02: exercise the installed stock models, including hidden configurations and the X99 alias.
extends SceneTree

const Airplane := preload("res://render/airplane.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Mounts := preload("res://render/camera/fpv_stock_mounts.gd")
const Paint := preload("res://render/vehicle_paint.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")
const Retraction := preload("res://aircraft/retractable_model.gd")
const ExtraGeometry := preload("res://aircraft/extra_300s_geometry.gd")
const MustangGeometry := preload("res://aircraft/p51d_geometry.gd")
const HingePoses := preload("res://physics/control_surfaces.gd")

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if not condition:
		printerr("FAIL ", label)
		failures += 1


## Every vertex of every drawn triangle is in its transformed mesh box. Proving the whole
## model is behind the eye clears all forward rays without relying on depth clipping.
func _check_clearance(model: Node3D, eye_z: float, label: String) -> void:
	var nearest := INF
	var limiting_mesh := ""
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		var bounds := PropellerBlur.relative(model, part) * part.mesh.get_aabb()
		if bounds.position.z < nearest:
			nearest = bounds.position.z
			limiting_mesh = str(part.name)
	var gap := nearest - eye_z
	_check(is_finite(gap) and gap > 0.010 and gap < 0.080,
		"%s: virtual lens close to and clear of nose (%s, %.5f m)" % [label, limiting_mesh, gap])


## The minimum model Z of a point rotated around the local propeller shaft is the
## shaft centre at its axial station minus its radial projection along model Z.
func _swept_z(shaft: Transform3D, radius: float, axial: float) -> float:
	return shaft.origin.z + axial * shaft.basis.z.z - radius * Vector2(shaft.basis.x.z, shaft.basis.y.z).length()


func _check_swept_prop(airplane: Dictionary, eye_z: float, label: String) -> void:
	var prop: Node3D = airplane.propeller
	var shaft := PropellerBlur.relative(airplane.root, prop)
	var nearest := INF
	for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null:
			continue
		var box := part.mesh.get_aabb()
		var in_prop := PropellerBlur.relative(prop, part)
		for i in 8:
			var point := in_prop * box.get_endpoint(i)
			nearest = minf(nearest, _swept_z(shaft, Vector2(point.x, point.y).length(), point.z))
	_check(is_finite(nearest) and nearest - eye_z > 0.010, label + ": entire installed propeller revolution clears the lens")
	var blur := PropellerBlur.profile(prop)
	_check(not blur.is_empty(), label + ": installed blades yield a blur disc")
	if not blur.is_empty():
		_check(_swept_z(shaft, blur.radius, blur.plane_z) - eye_z > 0.010, label + ": complete blur disc clears the lens")


func _check_look(front: Dictionary, label: String) -> void:
	var stops: Vector2 = front.look_limits_deg
	_check(stops == Vector2(12, 8), label + ": both look axes are available")
	# Square is the widest vertical FOV among supported landscape displays. The extrema
	# of model Z on our small yaw/pitch intervals occur at these outside edges.
	var edge := tan(deg_to_rad(float(front.hfov_deg)) * 0.5)
	for yaw: float in [-stops.x, stops.x]:
		for pitch: float in [-stops.y, stops.y]:
			var axes := Basis(Vector3.UP, deg_to_rad(-yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
			for x: float in [-edge, edge]:
				for y: float in [-edge, edge]:
					_check((axes * Vector3(x, y, -1.0)).z < 0.0, label + ": corner ray at joint stop clears aircraft")


## Cross-check the companion against the builder or authoring landmark in three dimensions.
func _check_station(airplane: Dictionary, mount: Transform3D) -> void:
	var model: Node3D = airplane.root
	var shaft := PropellerBlur.relative(model, airplane.propeller)
	var reference: Vector3
	match airplane.visual_family:
		Mounts.BASIC_STIK, "stik-electric-6s":
			reference = shaft.origin
		"gp-extra-300s-60", "p51d-mustang-120":
			var spinner: Dictionary = ExtraGeometry.DATA.spinner if airplane.visual_family == "gp-extra-300s-60" else MustangGeometry.DATA.spinner
			var frame := model.find_child("thrust_frame", true, false) as Node3D
			reference = PropellerBlur.relative(model, frame) * Vector3(0.0, 0.0, spinner.tip_z - spinner.back_z)
		"f4u-corsair-250":
			# Shaft centre, foremost point of the spinning mesh (in model space).
			var rotor := model.find_child("propeller_rotor", true, false) as MeshInstance3D
			var box := PropellerBlur.relative(model, rotor) * rotor.mesh.get_aabb()
			reference = Vector3(shaft.origin.x, shaft.origin.y, box.position.z)
		"sebart-avanti-s-a200-p100rx":
			# The measured collision probe is presentation geometry data; it need not be a rendered node.
			for probe: Dictionary in airplane.data.collision_probes:
				if probe.id == "probe_nose_tip":
					reference = Vector3(probe.model_position[0], probe.model_position[1], probe.model_position[2])
					break
		"turbo-lumber-evolution", "moonrunner-x99", "skywalker-x8":
			var vertex: Array = airplane.data.landmarks.nose_spinner_tip.measured if airplane.visual_family == "turbo-lumber-evolution" else airplane.data.landmarks.nose_tip.model_m
			reference = Vector3(vertex[0], vertex[1], vertex[2])
	_check(mount.origin.distance_to(reference + Vector3.FORWARD * 0.040) < 0.001,
		str(airplane.aircraft_id) + ": virtual lens sits 40 mm forward of its structural landmark")


func _check_articulation(airplane: Dictionary, mount: Transform3D, id: String) -> void:
	var model: Node3D = airplane.root
	var builder: Script = airplane._model_builder
	for q: float in [0.0, 0.5, 1.0]:
		var degrees := lerpf(-15.0, 15.0, q)
		var rotations := HingePoses.hinge_rotations_from_surfaces({
			aileron_left = -degrees, aileron_right = degrees, elevator = degrees, rudder = -degrees})
		Airplane.apply_surfaces(airplane, rotations)
		Airplane.apply_flaps(airplane, 30.0 * q)
		Airplane.apply_gear(airplane, {left = q, right = q, nose = q, tail = q}, degrees * PI / 180.0)
		for group: String in ["folds", "mechanisms"]:
			var pose := {}
			for key: String in airplane.get(group, {}):
				pose[key] = q
			if group == "folds":
				Airplane.apply_folds(airplane, pose)
			else:
				Airplane.apply_mechanisms(airplane, pose)
		if not airplane.get("gear_retraction", {}).is_empty():
			Retraction.apply(airplane.gear_retraction, q)
		elif builder.has_method("set_gear"):
			builder.call("set_gear", airplane, q)
		(airplane.propeller as Node3D).rotation.z = 1.3 * q
		_check_clearance(model, mount.origin.z, "%s moving installation %.1f" % [id, q])
		_check((Mounts.front(airplane).mount as Transform3D).is_equal_approx(mount), id + ": mount stays bolted to structure")


func _check_liveries(airplane: Dictionary, eye_z: float) -> void:
	var manifest: Dictionary = airplane.model_manifest
	for livery: Dictionary in manifest.get("liveries", []):
		if livery.path == manifest.asset.path:
			continue # The default installation was built above.
		var asset := load(str(livery.path)) as PackedScene
		_check(asset != null, str(livery.id) + ": stock livery loads")
		if asset != null:
			var model := asset.instantiate() as Node3D
			_check_clearance(model, eye_z, "%s/%s" % [airplane.aircraft_id, livery.id])
			model.free()


func _check_installation(id: String) -> void:
	var airplane := Airplane.build(id)
	if airplane.is_empty():
		_check(false, id + ": stock visual builds")
		return
	var model: Node3D = airplane.root
	var front := Mounts.front(airplane)
	if front.is_empty():
		_check(false, id + ": stock nose is installed")
		model.free()
		return
	var mount: Transform3D = front.mount
	_check(front.id == "front" and front.provenance == "derived", id + ": stable mount identity")
	_check(mount.basis == Basis.IDENTITY and is_equal_approx(front.hfov_deg, 90.0) and is_equal_approx(front.near_m, 0.03),
		id + ": level rectilinear optics")
	_check_station(airplane, mount)
	_check_clearance(model, mount.origin.z, id)
	_check_look(front, id)
	if id == Mounts.BASIC_STIK:
		for skin: Dictionary in Paint.choices(id):
			var painted := Paint.apply(model, id, str(skin.id))
			_check(painted.ok, "apply stock paint " + str(skin.id))
			_check_clearance(model, mount.origin.z, str(skin.id))
	if airplane.get("has_propeller", true):
		_check_swept_prop(airplane, mount.origin.z, id)
		if id in ["stik-glow-55ax-2t", "stik-glow-fs64v-4t", "stik-electric-6s"]:
			# The two glow models ship alternate APC 13x6 installations. Also exercise
			# diameter changes on the electric builder at the same size.
			_check(Airplane.apply_propeller_diameter(airplane, 0.3302), id + ": install 13-inch blades")
			_check_swept_prop(airplane, mount.origin.z, id + " 13-inch")
	else:
		_check(id == "sebart-avanti-s-a200-p100rx", id + ": rotorless Vantage Jet installation")
	_check_articulation(airplane, mount, id)
	_check_liveries(airplane, mount.origin.z)
	var changed := airplane.duplicate()
	for key: String in ["aircraft_id", "visual_family", "model_manifest_sha256"]:
		changed[key] = "other"
		_check(Mounts.front(changed).is_empty(), id + ": refuses unadmitted " + key)
		changed[key] = airplane[key]
	model.free()


func _run() -> void:
	var ids := Catalog.airplane_flyable_ids()
	_check(ids.size() == 11 and ids.has("moonrunner-x99") and not ids.has("skywalker-x8"), "11 distinct catalog airplane configurations")
	for id: String in ids:
		_check_installation(id)
	_check(Catalog.canonical_id("skywalker-x8") == "moonrunner-x99" and Catalog.visual_family("skywalker-x8") == "skywalker-x8",
		"legacy flight ID resolves to the X99 and still supports its separately admitted historical visual")
	_check_installation("skywalker-x8")
	_check(Mounts.front({}).is_empty(), "unbound visual has no view")
	print("Stock FPV nose mount: %d failed" % failures)
	quit(1 if failures else 0)
