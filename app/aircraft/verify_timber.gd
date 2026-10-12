# TT-03/TT-05 contract checks for the Turbo Timber Evolution imported model (headless; visual preview, not flyable).
# Proves that the scene Godot imports is the frozen r1 asset (hash, counts, pivots, landmarks), that the builder's
# wrappers leave every world transform untouched, and that surfaces, propeller and wheels move in the app's signs with
# witness vertices. Run: godot --headless --path app --script res://aircraft/verify_timber.gd
extends SceneTree

const Commands := preload("res://input/commands.gd")
const Timber := preload("res://aircraft/timber_model.gd")
const TimberGeometry := preload("res://aircraft/timber_geometry.gd")
const GLB_PATH := "res://assets/aircraft/turbo-timber-evolution/timber.glb"
const HINGE_NAMES := ["flap_left", "flap_right", "aileron_left", "aileron_right", "elevator", "rudder"]
## Pivots that the builder moves under an identity wrapper (their parent name changes, their world transform must not).
const WRAPPED := ["propeller_spin", "wheel_left_axle", "wheel_right_axle", "tailwheel_axle", "tailwheel_steer"]
const REST_TOLERANCE := 1e-5 # rad / unit-vector components: metadata quaternions are rounded to 6 decimals
const POSITION_TOLERANCE_M := 2e-6
const LANDMARK_TOLERANCE_M := 0.0005
const MANUAL_SPAN_M := 1.555
const SPAN_TOLERANCE := 0.01
const TEST_DEG := 10.0
const MIN_TRAVEL_M := 0.003 # 10 deg on a 55 mm control chord moves the trailing edge ~9.6 mm
const EXACT_M := 0.000001

var _checks := 0
var _failures := 0
var D: Dictionary = TimberGeometry.DATA


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	call_deferred("_run")


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func _basis_of(b: Dictionary) -> Basis:
	return Basis(_v3(b.x), _v3(b.y), _v3(b.z))


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for m in node.find_children("*", "MeshInstance3D", true, false): out.append(m)
	return out


# Vertex positions in the root frame from the surface arrays: on this import Mesh.get_faces() returns positions
# quantized by the compressed vertex format (up to 28 um off), so metrology reads the arrays.
func _vertices(mesh: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in mesh.mesh.get_surface_count(): out.append_array(mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out


func _all_points(root: Node3D, only := "") -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in _meshes(root):
		if only != "" and String(m.name) != only: continue
		var t := Timber.relative(root, m)
		for v in _vertices(m): out.append(t * v)
	return out


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points: box = box.expand(p)
	return box


# Root-frame position of the aft-most rest vertex of a hinge's mesh, tracked through the current pose.
func _aft_point(root: Node3D, h: Dictionary) -> Vector3:
	var posed_basis: Basis = h.node.basis
	h.node.basis = h.rest
	var mesh := _meshes(h.node)[0]
	var faces := _vertices(mesh)
	var t := Timber.relative(root, mesh)
	var index := 0
	var best := -INF
	for i in faces.size():
		var z := (t * faces[i]).z
		if z > best:
			best = z
			index = i
	h.node.basis = posed_basis
	return Timber.relative(root, mesh) * faces[index]


func _travel(model: Dictionary, surfaces: Dictionary) -> Dictionary:
	var rest := {}
	for key in HINGE_NAMES: rest[key] = _aft_point(model.root, model.hinges[key])
	Timber.apply_surfaces(model, surfaces)
	var moved := {}
	for key in HINGE_NAMES: moved[key] = _aft_point(model.root, model.hinges[key]) - rest[key]
	Timber.apply_surfaces(model, {})
	return moved


func _structure(root: Node3D) -> Array:
	var out := []
	for n in root.find_children("*", "", true, false):
		var row := [String(root.get_path_to(n)), n.get_class()]
		if n is Node3D: row.append((n as Node3D).transform)
		if n is MeshInstance3D: row.append((n as MeshInstance3D).mesh.get_surface_count())
		out.append(row)
	return out


func _run() -> void:
	var model := Timber.build()
	var root: Node3D = model.root
	get_root().add_child(root)
	await process_frame

	# TT-03: identity of the asset and the generated constants.
	_check("visual revision", Timber.VISUAL_REVISION == D.revision and root.get_meta("visual_revision", "") == D.revision, D.revision)
	_check("asset hash on disk = geometry inputs", FileAccess.get_sha256(GLB_PATH) == D.inputs.glb_sha256 and root.get_meta("asset_sha256", "") == D.inputs.glb_sha256)
	_check("catalog id", root.get_meta("aircraft_id", "") == D.catalog_id and model.aircraft_id == D.catalog_id)
	_check("root name", root.name == "airplane")
	_check("not flyable status", String(root.get_meta("status", "")).contains("not flyable"))
	var aircraft_node := root.get_node_or_null(String(D.scene.aircraft_node)) as Node3D
	_check("aircraft node at the datum", aircraft_node != null and aircraft_node.transform == Transform3D.IDENTITY and root.get_child_count() == 1)
	_check("data is the generated geometry", is_same(model.data, D))
	var meshes := _meshes(root)
	var surfaces := 0
	var triangles := 0
	var identity_meshes := true
	for m in meshes:
		surfaces += m.mesh.get_surface_count()
		triangles += m.mesh.get_faces().size() / 3
		identity_meshes = identity_meshes and m.transform == Transform3D.IDENTITY and D.scene.mesh_nodes.has(String(m.name))
		_check("mesh %s surfaces as measured" % m.name, D.scene.mesh_nodes.has(String(m.name)) and m.mesh.get_surface_count() == int(D.scene.mesh_nodes[String(m.name)].surfaces))
	_check("15 meshes, 36 surfaces, 64291 triangles", meshes.size() == 15 and surfaces == 36 and triangles == 64291, "%d/%d/%d" % [meshes.size(), surfaces, triangles])
	_check("meshes identity under their pivots", identity_meshes)
	_check("no animation player, camera or light", root.find_children("*", "AnimationPlayer", true, false).is_empty()
		and root.find_children("*", "Camera3D", true, false).is_empty() and root.find_children("*", "Light3D", true, false).is_empty())
	# Pivots: parents and rest transforms (unwrapped), world transforms (all), glTF extras agree with the constants.
	for name in D.articulations:
		var a: Dictionary = D.articulations[name]
		var node := root.find_child(name, true, false) as Node3D
		_check("%s pivot found" % name, node != null)
		if node == null: continue
		if not WRAPPED.has(name):
			_check("%s parent" % name, node.get_parent().name == String(a.parent), String(node.get_parent().name))
			var rest := _basis_of(a.rest_basis)
			_check("%s rest basis within 1e-5" % name, (node.basis.x - rest.x).length() < REST_TOLERANCE and (node.basis.y - rest.y).length() < REST_TOLERANCE and (node.basis.z - rest.z).length() < REST_TOLERANCE)
			_check("%s rest translation" % name, node.position.distance_to(_v3(a.rest_translation)) < POSITION_TOLERANCE_M)
		var world := Timber.relative(root, node)
		_check("%s world pivot = constants" % name, world.origin.distance_to(_v3(a.pivot)) < POSITION_TOLERANCE_M, str(world.origin))
		_check("%s world axis = constants" % name, (world.basis.x - _v3(a.axis)).length() < REST_TOLERANCE, str(world.basis.x))
		# The whole world basis, wrapped or not: the declared parent's world basis times the imported rest basis.
		var declared_parent := root.find_child(String(a.parent), true, false) as Node3D
		var expected_basis := Timber.relative(root, declared_parent).basis * _basis_of(a.rest_basis)
		_check("%s world basis = declared parent x rest" % name, (world.basis.x - expected_basis.x).length() < REST_TOLERANCE
			and (world.basis.y - expected_basis.y).length() < REST_TOLERANCE and (world.basis.z - expected_basis.z).length() < REST_TOLERANCE, str(world.basis))
		var extras: Dictionary = node.get_meta("extras", {})
		_check("%s glTF extras agree" % name, extras.get("articulation", "") == name and extras.get("positive", "") == String(a.positive)
			and (a.range_deg == null or (absf(float(extras.get("min_deg", NAN)) - float(a.range_deg[0])) < 1e-9 and absf(float(extras.get("max_deg", NAN)) - float(a.range_deg[1])) < 1e-9)), str(extras))
	var thrust := root.find_child("thrust_frame", true, false) as Node3D
	_check("thrust frame fixed at the hub with the thrust axis", thrust != null and thrust.get_parent() == aircraft_node
		and thrust.position.distance_to(_v3(D.thrust.origin.value)) < POSITION_TOLERANCE_M and (thrust.basis.x - _v3(D.thrust.direction.value)).length() < REST_TOLERANCE)

	# Landmarks and dimensions from the live vertices.
	var points := _all_points(root)
	var box := _bounds(points)
	var rotor_points := _all_points(root, "propeller_rotor")
	var rudder_points := _all_points(root, "rudder")
	var spinner_tip := rotor_points[0]
	for p in rotor_points: if p.z < spinner_tip.z: spinner_tip = p
	var rudder_te := rudder_points[0]
	for p in rudder_points: if p.z > rudder_te.z: rudder_te = p
	var live := {left_wingtip = Vector3(box.position.x, 0, 0), right_wingtip = Vector3(box.end.x, 0, 0), nose_spinner_tip = spinner_tip,
		tail_rudder_trailing_edge = rudder_te, propeller_hub = Timber.relative(root, thrust).origin, datum_D0 = Vector3.ZERO,
		left_main_wheel_center = Timber.relative(root, root.find_child("wheel_left_axle", true, false)).origin,
		right_main_wheel_center = Timber.relative(root, root.find_child("wheel_right_axle", true, false)).origin,
		tailwheel_center = Timber.relative(root, root.find_child("tailwheel_axle", true, false)).origin}
	for key in D.landmarks:
		var rec: Dictionary = D.landmarks[key]
		var ok := true
		for axis in rec.compared_axes:
			ok = ok and absf(live[key][int(axis)] - float(rec.measured[int(axis)])) < LANDMARK_TOLERANCE_M and absf(live[key][int(axis)] - float(rec.author[int(axis)])) < LANDMARK_TOLERANCE_M
		_check("landmark %s within 0.5 mm of the measurement and the author" % key, ok, str(live[key]))
	_check("span within 1 %% of the manual 1.555 m", absf(box.size.x / MANUAL_SPAN_M - 1.0) < SPAN_TOLERANCE, "%.4f m" % box.size.x)
	_check("span = measured", absf(box.size.x - float(D.dimensions.span.value)) < 1e-4, "%.6f" % box.size.x)
	_check("length = measured (spinner tip to rudder TE)", absf((rudder_te.z - spinner_tip.z) - float(D.dimensions.length.value)) < 1e-4)
	_check("height = measured", absf(box.size.y - float(D.dimensions.height.value)) < 1e-4)
	_check("forward extent is the spinner tip, not an AABB corner", absf(box.position.z - spinner_tip.z) < 1e-6 and absf(spinner_tip.z - float(D.dimensions.forward_extent_vertex.root[2])) < 1e-6, "%.6f" % box.position.z)
	_check("lateral symmetry", absf(box.position.x + box.end.x) < 1e-5, str(box))
	_check("nose toward -Z", box.position.z < -0.25 and box.end.z > 0.8)
	# Materials: ten imported resources, named as measured, shared by every surface that uses them.
	var materials := {}
	var transparent := 0
	var emissive := 0
	for m in meshes:
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as BaseMaterial3D
			if mat == null: continue
			var key := mat.resource_name
			_check("material %s:%d is one shared resource" % [m.name, s], not materials.has(key) or materials[key] == mat)
			materials[key] = mat
	for key in materials:
		if materials[key].transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: transparent += 1
		if materials[key].emission_enabled: emissive += 1
	_check("ten materials as measured", materials.size() == 10 and materials.keys().all(func(k): return D.scene.materials.has(k)), str(materials.keys()))
	_check("one transparent (glass), two emissive lenses", transparent == 1 and emissive == 2 and materials.has("glass") and materials.glass.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED, "%d/%d" % [transparent, emissive])

	# TT-05: hinge records and apply_surfaces signs on trailing-edge witness vertices.
	_check("hinge keys", model.hinges.size() == HINGE_NAMES.size() and HINGE_NAMES.all(func(k): return model.hinges.has(k)), str(model.hinges.keys()))
	for key in HINGE_NAMES:
		var h: Dictionary = model.hinges[key]
		_check("%s hinge node" % key, h.node is Node3D and h.node.name == Timber.HINGE_NODES[key] and h.node.get_child_count() == 1)
		_check("%s axis is the rest local +X" % key, (h.axis - h.rest.x).length() < 1e-7 and absf(h.axis.length() - 1.0) < 1e-6)
	var rest := {}
	for key in HINGE_NAMES: rest[key] = model.hinges[key].node.transform
	var cases := [["aileron_right", "y", 1.0, ["aileron_right"]], ["aileron_left", "y", 1.0, ["aileron_left"]],
		["elevator", "y", 1.0, ["elevator"]], ["rudder", "x", 1.0, ["rudder"]]]
	for c in cases:
		for sign in [1.0, -1.0]:
			var moved := _travel(model, {c[0]: sign * TEST_DEG})
			for key in HINGE_NAMES:
				var d: Vector3 = moved[key]
				if key in c[3]:
					_check("%s %+.0f deg moves %s TE %s%s" % [c[0], sign * TEST_DEG, key, "+" if sign > 0 else "-", c[1]], d[c[1]] * sign > MIN_TRAVEL_M, str(d))
				else:
					_check("%s leaves %s still" % [c[0], key], d.length() < EXACT_M, str(d))
	var deflections := Commands.surface_deflections_deg({roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.5}, Timber.manual_throws_deg())
	var moved := _travel(model, deflections)
	_check("right roll: right aileron up", moved.aileron_right.y > MIN_TRAVEL_M)
	_check("right roll: left aileron down", moved.aileron_left.y < -MIN_TRAVEL_M)
	_check("pull: elevator up", moved.elevator.y > MIN_TRAVEL_M)
	_check("right yaw: rudder TE right", moved.rudder.x > MIN_TRAVEL_M)
	# Every surface of a moving mesh (horns, markings) follows its hinge; the fixed airframe does not move.
	var airframe := root.find_child("airframe", true, false) as MeshInstance3D
	var airframe_before := Timber.relative(root, airframe)
	Timber.apply_surfaces(model, deflections)
	for key in ["elevator", "rudder"]:
		var h: Dictionary = model.hinges[key]
		var axis: Vector3 = h.axis
		var pivot: Vector3 = h.pivot
		var mesh := _meshes(h.node)[0]
		var posed := Timber.relative(root, mesh)
		var rest_t := Transform3D(h.rest, pivot)
		var applied := deg_to_rad(float(deflections[key]) * float(h.app_sign))
		var all_follow := mesh.mesh.get_surface_count() == int(D.scene.mesh_nodes[String(mesh.name)].surfaces)
		for s in mesh.mesh.get_surface_count():
			# The vertex farthest from the hinge axis (the torsion rod lies on it) must rotate by the applied angle.
			var far := Vector3.ZERO
			var far_r := -1.0
			for v in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = rest_t * v - pivot
				var radial: float = (p - axis * p.dot(axis)).length()
				if radial > far_r:
					far_r = radial
					far = v
			var a: Vector3 = rest_t * far - pivot
			var b: Vector3 = posed * far - pivot
			var turned: float = (a - axis * a.dot(axis)).signed_angle_to(b - axis * b.dot(axis), axis)
			all_follow = all_follow and absf(turned - applied) < 1e-4
		_check("%s: every surface (markings, horn, rod) turns with the hinge" % key, all_follow)
	_check("airframe fixed under deflection", Timber.relative(root, airframe) == airframe_before)
	for key in HINGE_NAMES:
		var h: Dictionary = model.hinges[key]
		_check("%s pivot fixed" % key, h.node.position.distance_to(h.pivot) < EXACT_M)
		_check("%s axis invariant" % key, (h.node.basis.x - h.axis).length() < 1e-6)
	Timber.apply_surfaces(model, Commands.surface_deflections_deg({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}, Timber.manual_throws_deg()))
	for key in HINGE_NAMES:
		_check("%s neutral is rest exactly" % key, model.hinges[key].node.transform == rest[key])
	# Flaps: trailing edge down, clamped to the authored range, untouched by apply_surfaces.
	var flap_rest := _aft_point(root, model.hinges.flap_left)
	Timber.set_flaps(model, 999.0)
	var flap_full := _aft_point(root, model.hinges.flap_left)
	_check("flap TE goes down", flap_full.y < flap_rest.y - MIN_TRAVEL_M)
	var flap_range: Array = model.hinges.flap_right.range_deg
	_check("flap clamped to the authored maximum", model.hinges.flap_right.node.basis.is_equal_approx(
		Basis(model.hinges.flap_right.axis, deg_to_rad(float(flap_range[1]))) * model.hinges.flap_right.rest), str(flap_range))
	Timber.apply_surfaces(model, {})
	_check("apply_surfaces keeps flaps", _aft_point(root, model.hinges.flap_left).distance_to(flap_full) < EXACT_M)
	Timber.set_flaps(model, -30.0)
	_check("flap clamped to zero (rest)", model.hinges.flap_left.node.transform == rest.flap_left)
	# Inspector mapping.
	Timber.apply_controls(model, 1, 1, 1, 30)
	var ac := {}
	for key in HINGE_NAMES: ac[key] = _aft_point(root, model.hinges[key])
	Timber.apply_controls(model, 0, 0, 0, 0)
	for key in ["flap_left", "flap_right", "aileron_left"]:
		_check("apply_controls %s down" % key, ac[key].y < _aft_point(root, model.hinges[key]).y - MIN_TRAVEL_M)
	for key in ["elevator", "aileron_right"]:
		_check("apply_controls %s up" % key, ac[key].y > _aft_point(root, model.hinges[key]).y + MIN_TRAVEL_M)
	_check("apply_controls rudder right", ac.rudder.x > _aft_point(root, model.hinges.rudder).x + MIN_TRAVEL_M)
	for key in HINGE_NAMES:
		_check("apply_controls neutral %s is rest" % key, model.hinges[key].node.transform == rest[key])
	var throws := Timber.manual_throws_deg()
	_check("manual throws are the converted millimetres", absf(throws.aileron - float(D.controls.aileron.high_deg.value)) < 1e-9 and throws.elevator > 10.0 and throws.rudder > 10.0, str(throws))

	# Propeller wrapper: identity exposed node under a mount whose +Z is the thrust axis; the rotor keeps its world
	# transform; rotation.z = +angle turns the blade tip clockwise seen from behind (positive about the thrust direction).
	var propeller: Node3D = model.propeller
	var spin := root.find_child("propeller_spin", true, false) as Node3D
	_check("propeller node", propeller.name == "propeller" and propeller.get_parent().name == "propeller_mount" and propeller.get_parent().get_parent() == thrust)
	_check("propeller rest identity, rotor under it", propeller.transform == Transform3D.IDENTITY and spin.get_parent() == propeller and model.has_propeller and propeller.visible)
	var hub := Timber.relative(root, thrust).origin
	var d := Timber.relative(root, thrust).basis.x
	_check("propeller mount +Z is the thrust axis", (Timber.relative(root, propeller.get_parent()).basis.z - d).length() < 1e-6)
	var rotor := root.find_child("propeller_rotor", true, false) as MeshInstance3D
	var rotor_rest := Timber.relative(root, rotor)
	var tip_local := Vector3.ZERO
	var tip_r := 0.0
	for v in _vertices(rotor):
		var p := rotor_rest * v - hub
		var radial := (p - d * p.dot(d)).length()
		if radial > tip_r:
			tip_r = radial
			tip_local = v
	_check("blade tip radius = measured propeller radius", absf(tip_r - float(D.thrust.propeller_radius.value)) < 1e-4, "%.6f" % tip_r)
	var p0 := rotor_rest * tip_local - hub
	propeller.rotation.z = 0.3
	var p1 := Timber.relative(root, rotor) * tip_local - hub
	var swept := (p0 - d * p0.dot(d)).signed_angle_to(p1 - d * p1.dot(d), d)
	_check("propeller +0.3 rad spins the tip +0.3 rad about the thrust direction (clockwise from behind)", absf(swept - 0.3) < 1e-5, "%.6f" % swept)
	_check("propeller spin keeps the hub and the rotor origin", (Timber.relative(root, rotor).origin - rotor_rest.origin).length() < EXACT_M and Timber.relative(root, thrust).origin.distance_to(hub) < EXACT_M)
	_check("propeller spin leaves the thrust frame and the airframe", Timber.relative(root, thrust).basis.x.distance_to(d) < 1e-7 and Timber.relative(root, airframe) == airframe_before)
	propeller.rotation.z = 0.0
	_check("propeller zero restores the rotor exactly", Timber.relative(root, rotor) == rotor_rest)

	# Gear wrappers: exposed nodes rotate about root-aligned axes through the axle centres (render/ground_gear.gd and
	# render/airplane.gd write gear[*].rotation.x and gear.steering.rotation.y); zero restores the imported transforms.
	for key in ["left", "right", "tail", "steering"]:
		_check("gear %s" % key, model.gear.has(key) and model.gear[key] is Node3D and model.gear[key].transform.basis == Basis.IDENTITY)
	var wheel := root.find_child("wheel_left", true, false) as MeshInstance3D
	var wheel_rest := Timber.relative(root, wheel)
	var axle := root.find_child("wheel_left_axle", true, false) as Node3D
	var axle_rest := Timber.relative(root, axle)
	_check("left wheel spin node sits on the axle centre", Timber.relative(root, model.gear.left).origin.distance_to(_v3(D.landing_gear.wheel_centres.main_left)) < POSITION_TOLERANCE_M)
	var top_local := Vector3.ZERO
	var top_y := -INF
	for v in _vertices(wheel):
		var p := wheel_rest * v
		if p.y > top_y:
			top_y = p.y
			top_local = v
	model.gear.left.rotation.x = -0.4
	var top_moved := Timber.relative(root, wheel) * top_local - wheel_rest * top_local
	_check("wheel rotation.x -0.4 rolls the top forward (ground_gear convention: forward = -X)", top_moved.z < -0.01 and absf(top_moved.x) < 1e-6, str(top_moved))
	_check("wheel spin keeps the axle centre and axis", Timber.relative(root, axle).origin.distance_to(axle_rest.origin) < EXACT_M and (Timber.relative(root, axle).basis.x - axle_rest.basis.x).length() < 1e-6)
	model.gear.left.rotation.x = 0.0
	_check("wheel zero restores the axle exactly", Timber.relative(root, axle) == axle_rest)
	var tail_axle := root.find_child("tailwheel_axle", true, false) as Node3D
	var tail_rest := Timber.relative(root, tail_axle)
	var fork := root.find_child("tailwheel_fork", true, false) as MeshInstance3D
	var fork_rest := Timber.relative(root, fork)
	model.gear.steering.rotation.y = 0.3
	var steered := Timber.relative(root, tail_axle)
	_check("steering +0.3 rad trails the tail wheel to the right (+X) about the steer pivot", steered.origin.x > 0.005 and absf(steered.origin.y - tail_rest.origin.y) < 1e-6, str(steered.origin))
	_check("steering turns the fork and the wheel spin axis together", Timber.relative(root, fork) != fork_rest and absf(steered.basis.x.signed_angle_to(tail_rest.basis.x, Vector3.UP)) > 0.29)
	model.gear.tail.rotation.x = 0.5
	_check("tail wheel spins about the steered axle", Timber.relative(root, tail_axle).origin.distance_to(steered.origin) < EXACT_M and (Timber.relative(root, tail_axle).basis.x - steered.basis.x).length() < 1e-6)
	model.gear.tail.rotation.x = 0.0
	model.gear.steering.rotation.y = 0.0
	_check("steering zero restores the tail wheel exactly", Timber.relative(root, tail_axle) == tail_rest and Timber.relative(root, fork) == fork_rest)

	# Two builds: identical structure, independent nodes, shared mesh and material resources.
	var other := Timber.build()
	get_root().add_child(other.root)
	_check("deterministic double build", _structure(root) == _structure(other.root))
	var other_rest := _aft_point(other.root, other.hinges.aileron_right)
	Timber.apply_surfaces(model, {aileron_right = TEST_DEG, elevator = TEST_DEG})
	Timber.set_flaps(model, 30.0)
	model.propeller.rotation.z = 1.0
	model.gear.steering.rotation.y = 0.2
	_check("instances independent", _aft_point(other.root, other.hinges.aileron_right).distance_to(other_rest) < EXACT_M
		and other.hinges.flap_left.node.transform == rest.flap_left and other.propeller.transform == Transform3D.IDENTITY and other.gear.steering.transform.basis == Basis.IDENTITY)
	_check("instances own their nodes", other.root != root and other.hinges.rudder.node != model.hinges.rudder.node and other.propeller != model.propeller)
	var other_airframe := other.root.find_child("airframe", true, false) as MeshInstance3D
	_check("instances share meshes and materials", other_airframe.mesh == airframe.mesh and other_airframe.get_active_material(0) == airframe.get_active_material(0))
	Timber.apply_surfaces(model, {})
	Timber.set_flaps(model, 0.0)
	model.propeller.rotation.z = 0.0
	model.gear.steering.rotation.y = 0.0

	print("timber preview %s: %d meshes, %d surfaces, %d triangles, extent %.4f x %.4f x %.4f m" % [Timber.VISUAL_REVISION, meshes.size(), surfaces, triangles, box.size.x, box.size.y, box.size.z])
	other.root.free()
	root.free()
	if _failures == 0: print("PASS %d checks" % _checks)
	else: printerr("FAIL %d of %d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)
