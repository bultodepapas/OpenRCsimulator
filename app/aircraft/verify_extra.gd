# EX-02 contract checks for the Extra 300S .60 visual preview (headless; no physics).
# Run: godot --headless --path app --script res://aircraft/verify_extra.gd
extends SceneTree

const Commands := preload("res://input/commands.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Extra := preload("res://aircraft/extra_300s_model.gd")
const Geometry := preload("res://aircraft/extra_300s_geometry.gd")
const Finish := preload("res://aircraft/extra_300s_finish.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd")

const SURFACE_NAMES := ["aileron_left", "aileron_right", "elevator", "rudder"]
const KIT_SPAN_M := 64.0 * 0.0254 # plan title block, 64 in
const KIT_LENGTH_M := 54.25 * 0.0254 # plan title block, 54-1/4 in (spinner tip to rudder TE assumed)
const SPAN_TOLERANCE_M := 0.008 # tip block edge read at +/-6 px plus 0.5 % paper/scan allowance
const LENGTH_TOLERANCE := 0.01 # reserved length check measured +0.67 % in EX-01
const MINIMUM_GAP_M := 0.0005 # moving surfaces at the manual high rates (measured 1.75 mm, 2026-10-06)
const BEVEL_TEST_DEG := 45.0 # common 3D rate: beveled hinges must still clear their fixed neighbours
const BEVEL_PAIRS := ["rudder/fin", "elevator_right/stab", "elevator_left/stab", "aileron_right/wing_right_ahead_of_aileron",
	"aileron_left/wing_left_ahead_of_aileron", "aileron_right/wing_right_root", "aileron_right/wing_right_tip"]

var _checks := 0
var _failures := 0


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: out.append(node)
	for child in node.get_children(): _meshes(child, out)


func _bounds(root: Node3D) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var box := AABB()
	var first := true
	for m in meshes:
		var t := root.global_transform.affine_inverse() * m.global_transform
		var b := t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# Global-frame vertices of a mesh, for motion checks.
func _vertices(m: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in m.mesh.get_faces(): out.append(m.global_transform * v)
	return out


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane := Extra.build()
	var root: Node3D = airplane.root
	get_root().add_child(root)
	_check("root name", root.name == "airplane")
	_check("propeller node", airplane.propeller is Node3D and airplane.propeller.name == "propeller")
	_check("hinge keys", airplane.hinges.keys().size() == 4 and SURFACE_NAMES.all(func(k): return airplane.hinges.has(k)), str(airplane.hinges.keys()))
	for k in SURFACE_NAMES:
		_check("%s node name" % k, airplane.hinges[k].name == k + "_hinge")
		_check("%s rest pose" % k, airplane.hinges[k].transform.is_equal_approx(Transform3D.IDENTITY))
	for k in ["left", "right", "tail", "steering"]:
		_check("gear %s" % k, airplane.gear.has(k) and airplane.gear[k] is Node3D)
	_check("metadata", root.get_meta("aircraft_id", "") == Geometry.DATA.id and String(root.get_meta("status", "")).begins_with("flyable (experimental)"))

	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var triangles := 0
	for m in meshes:
		var faces := m.mesh.get_faces().size() / 3
		triangles += faces
		_check("mesh %s has faces" % m.name, faces > 0)
		var t := m.global_transform
		_check("mesh %s finite" % m.name, t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite())
	var box := _bounds(root)
	_check("span", absf(box.size.x - KIT_SPAN_M) <= SPAN_TOLERANCE_M, "%.4f m vs %.4f m" % [box.size.x, KIT_SPAN_M])
	# The longitudinal extent includes nothing ahead of the spinner tip or aft of the rudder TE.
	var length := box.end.z - box.position.z
	_check("length", absf(length / KIT_LENGTH_M - 1.0) <= LENGTH_TOLERANCE, "%.4f m vs %.4f m" % [length, KIT_LENGTH_M])
	_check("symmetric", absf(box.position.x + box.end.x) < 0.001, str(box))
	# Wing tips alone carry the span: ailerons must end inboard of them.
	var tips := AABB()
	for m in meshes:
		if String(m.name).ends_with("_tip"):
			var b := root.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			tips = b if tips.size == Vector3.ZERO else tips.merge(b)
	_check("span at the tip panels", absf(tips.size.x - KIT_SPAN_M) <= SPAN_TOLERANCE_M, "%.4f m" % tips.size.x)
	_check("tip panels define the span", absf(tips.size.x - box.size.x) < 0.0005, "tips %.4f vs all %.4f" % [tips.size.x, box.size.x])

	# Aileron hinge axes run parallel to the trailing edge (sweep in plan), pointing toward +X on both sides.
	var w: Dictionary = Geometry.DATA.wing
	var half: float = w.span / 2.0
	var te_slope: float = ((w.le_z_tip + w.tip_chord) - (w.le_z_root + w.root_chord)) / half
	for side in [["aileron_right", 1.0], ["aileron_left", -1.0]]:
		var axis: Vector3 = airplane.hinges[side[0]].global_transform.basis.x.normalized()
		var expected := Vector3(1.0, 0.0, side[1] * te_slope).normalized()
		_check("%s axis along TE" % side[0], axis.dot(expected) > 0.99999, "%s vs %s" % [axis, expected])

	# Same command, same sense of motion as the Stik: compare trailing-edge travel of every surface.
	var stik: Dictionary = AirplaneBuilder.build()
	get_root().add_child(stik.root)
	var command := {roll = 1.0, pitch = 1.0, yaw = 1.0, throttle = 0.5}
	var rotations := Commands.hinge_rotations(command)
	var travel := {}
	for model in [["extra", airplane], ["stik", stik]]:
		var surfaces := {}
		for k in SURFACE_NAMES:
			var meshes_k: Array[MeshInstance3D] = []
			_meshes(model[1].hinges[k], meshes_k)
			var before := PackedVector3Array()
			for m in meshes_k: before.append_array(_vertices(m))
			for s in SURFACE_NAMES: model[1].hinges[s].rotation = Vector3.ZERO
			model[1].hinges[k].rotation = Vector3(rotations[k].x, rotations[k].y, 0)
			var after := PackedVector3Array()
			for m in meshes_k: after.append_array(_vertices(m))
			model[1].hinges[k].rotation = Vector3.ZERO
			if before.is_empty():
				# A runtime error would stop a headless run in the debugger; record the failure instead.
				_check("%s %s has geometry" % [model[0], k], false)
				surfaces[k] = Vector3.ZERO
				continue
			# Displacement of the point farthest aft (the trailing edge).
			var aft := 0
			for i in before.size():
				if before[i].z > before[aft].z: aft = i
			surfaces[k] = after[aft] - before[aft]
		travel[model[0]] = surfaces
	for k in SURFACE_NAMES:
		var e: Vector3 = travel.extra[k]
		var s: Vector3 = travel.stik[k]
		var component := "x" if k == "rudder" else "y"
		_check("%s sign matches Stik" % k, signf(e[component]) == signf(s[component]) and absf(e[component]) > 0.005, "extra %s stik %s" % [e, s])

	# Static-frame/hinge separation: after a deflection, rest pose restores bit-identical transforms.
	var frame: Node3D = airplane.hinges.aileron_right.get_parent()
	var frame_before := frame.global_transform
	AirplaneBuilder.apply_surfaces(airplane, rotations)
	_check("aileron frame unchanged by command", frame.global_transform.is_equal_approx(frame_before))
	AirplaneBuilder.apply_surfaces(airplane, Commands.hinge_rotations({roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}))
	for k in SURFACE_NAMES:
		_check("%s back to rest" % k, airplane.hinges[k].transform.is_equal_approx(Transform3D.IDENTITY))

	# Procedural finish (EX-10a): each painted part carries its shared material and model-space UVs.
	var expected_parts := {"fuselage": Finish.FUSELAGE, "wing_right_root": Finish.WING, "wing_left_tip": Finish.WING,
		"aileron_right": Finish.AILERON, "aileron_left": Finish.AILERON, "stab": Finish.HORIZONTAL_TAIL,
		"elevator_right": Finish.HORIZONTAL_TAIL, "fin": Finish.VERTICAL_TAIL, "rudder": Finish.VERTICAL_TAIL}
	for m in meshes:
		if not expected_parts.has(String(m.name)): continue
		var mat := m.mesh.surface_get_material(0)
		_check("%s finish material" % m.name, mat is ShaderMaterial and int(mat.get_shader_parameter("part")) == expected_parts[String(m.name)])
		var arrays := m.mesh.surface_get_arrays(0)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		_check("%s has model-space UVs" % m.name, uv.size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	_check("builder red = appearance red", Extra.RED.is_equal_approx(Color(Finish.A.colors.red)))
	_check("finish never reads TIME", not Finish.SHADER_CODE.contains("TIME"))
	# Propeller: tip-to-tip span of the blades in the propeller frame equals the data diameter.
	var prop_box := AABB()
	for blade in airplane.propeller.get_children():
		if blade is MeshInstance3D:
			var b: AABB = blade.transform * blade.get_aabb()
			prop_box = b if prop_box.size == Vector3.ZERO else prop_box.merge(b)
	_check("propeller diameter", absf(prop_box.size.x - float(Geometry.DATA.propeller.diameter)) < 0.002, "%.4f m" % prop_box.size.x)
	# Pilot inside the canopy: every pilot vertex below the measured canopy line and inside the skin's width.
	var pilot_node: Node3D = root.find_child("pilot", false, false)
	var outside := 0
	var pilot_vertices := 0
	if pilot_node != null:
		var pilot_meshes: Array[MeshInstance3D] = []
		_meshes(pilot_node, pilot_meshes)
		for m in pilot_meshes:
			for v in _vertices(m):
				pilot_vertices += 1
				var local := root.global_transform.affine_inverse() * v
				var crown := Extra.monotone(Geometry.DATA.canopy.top, local.z)
				if local.y > crown - 0.001 or absf(local.x) > Extra.profile(local.z, 1): outside += 1
	_check("pilot inside the canopy", pilot_vertices > 0 and outside == 0, "%d of %d vertices outside" % [outside, pilot_vertices])
	var glass: Material = (root.find_child("canopy", false, false) as MeshInstance3D).mesh.surface_get_material(0)
	var alpha: float = Finish.A.canopy.alpha
	_check("canopy transparency from appearance.json", (glass as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(glass.albedo_color.a, alpha) if alpha < 1.0 else true)
	# EX-04: articulation clearances on the posed model (Extra-specific pairs and the manual p43 throws).
	var throws := Extra.manual_throws_deg()
	var clear := Clearance.run(airplane, throws)
	_check("no penetration at the manual high rates", clear.ok, str(clear.failures))
	_check("moving-surface gap >= %.1f mm" % (MINIMUM_GAP_M * 1000.0), clear.minimum_gap_m >= MINIMUM_GAP_M, "%.2f mm" % (clear.minimum_gap_m * 1000.0))
	var bevel := Clearance.run(airplane, {aileron = BEVEL_TEST_DEG, elevator = BEVEL_TEST_DEG, rudder = BEVEL_TEST_DEG}, BEVEL_PAIRS)
	_check("beveled hinges clear at %.0f deg" % BEVEL_TEST_DEG, bevel.ok and bevel.minimum_gap_m >= MINIMUM_GAP_M,
		"%s, min gap %.2f mm" % [str(bevel.failures), bevel.minimum_gap_m * 1000.0])
	var rudder_limit := Clearance.rudder_limit_deg(airplane)
	_check("elevator relief leaves >= 5 deg beyond the manual rudder throw", rudder_limit >= float(throws.rudder) + 5.0, "%.1f deg" % rudder_limit)
	print("clearance: min gap %.2f mm at manual throws %s; rudder limited to %.1f deg by the elevator relief" % [clear.minimum_gap_m * 1000.0, throws, rudder_limit])
	print("extra preview: %d meshes, %d triangles, extent %.3f x %.3f x %.3f m" % [meshes.size(), triangles, box.size.x, box.size.y, box.size.z])
	print("verify_extra: %d checks, %d failures%s" % [_checks, _failures, "" if _failures == 0 else " FAIL"])
	stik.root.free()
	root.free()
	quit(1 if _failures > 0 else 0)
