# P5-02 contract checks for the P-51D visual model (headless; no physics). Every expectation is derived from the
# generated geometry (p51d_geometry.gd), never hard-coded, so a rescaled geometry.json keeps the checks valid.
# Run: godot --headless --path app --script res://aircraft/verify_p51.gd   (exit 0 = all checks pass)
# Mutation self-checks (each run on the builder with the original backed up, then restored byte-identical, 2026-10-06):
#   A. wing_frame rotation.z = 0 (no dihedral): "dihedral at the tip" failed (-0.0007 m vs 0.1234 m) and "span"
#      failed (2.8308 m: the panel coordinate is span / cos(dihedral), so the projected span only matches with it).
#   B. aileron mesh parented to the static aileron_frame instead of the hinge: "aileron_* trailing edge down" and
#      "aileron_* sign matches the Stik" failed with zero travel.
#   C. fin/rudder axis map mirrored in z (TE toward the nose): "rudder trailing edge right" failed with x = -0.0004,
#      "rudder sign matches the Stik" and "length" failed.
extends SceneTree

const P51 := preload("res://aircraft/p51d_model.gd")
const Stik := preload("res://aircraft/ugly_stik_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Clearance := preload("res://aircraft/extra_clearance.gd") # generic mesh-pair clearance checker (EX-04), by mesh name
const D: Dictionary = preload("res://aircraft/p51d_geometry.gd").DATA

const SURFACE_NAMES := ["aileron_left", "aileron_right", "elevator", "rudder"]
const SPAN_TOLERANCE_M := 0.01
const LENGTH_TOLERANCE := 0.01
const TEST_ANGLE := 0.3 # rad applied to each hinge

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


# Root-frame vertices of a mesh.
func _vertices(root: Node3D, m: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var t := root.global_transform.affine_inverse() * m.global_transform
	for v in m.mesh.get_faces(): out.append(t * v)
	return out


func _bounds(root: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var box := AABB()
	var first := true
	for m in meshes:
		for v in _vertices(root, m):
			if first:
				box = AABB(v, Vector3.ZERO)
				first = false
			else:
				box = box.expand(v)
	return box


func _hash(root: Node3D) -> int:
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var all := PackedVector3Array()
	for m in meshes: all.append_array(_vertices(root, m))
	return hash(all.to_byte_array())


# Trailing-edge travel of the meshes under a hinge for a rotation vector; returns [travel, others_moved].
func _travel(root: Node3D, airplane: Dictionary, key: String, rotation: Vector3, all_meshes: Array[MeshInstance3D]) -> Array:
	var under: Array[MeshInstance3D] = []
	_meshes(airplane.hinges[key], under)
	var before := {}
	for m in all_meshes: before[m] = _vertices(root, m)
	airplane.hinges[key].rotation = rotation
	var moved := 0
	var travel := Vector3.ZERO
	var aft_z := -INF
	for m in all_meshes:
		var after := _vertices(root, m)
		var b: PackedVector3Array = before[m]
		if under.has(m):
			# Displacement of the point farthest aft in the whole subtree (the trailing edge, not a control horn).
			for i in b.size():
				if b[i].z > aft_z:
					aft_z = b[i].z
					travel = after[i] - b[i]
		elif after != b:
			moved += 1
	airplane.hinges[key].rotation = Vector3.ZERO
	return [travel, moved]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var airplane := P51.build()
	var root: Node3D = airplane.root
	get_root().add_child(root)
	var w: Dictionary = D.wing
	var t: Dictionary = D.tail
	var g: Dictionary = D.gear
	var half: float = w.span / 2.0

	_check("root name", root.name == "airplane")
	_check("propeller node", airplane.propeller is Node3D and airplane.propeller.name == "propeller")
	_check("hinge keys", airplane.hinges.keys().size() == 4 and SURFACE_NAMES.all(func(k): return airplane.hinges.has(k)), str(airplane.hinges.keys()))
	for k in SURFACE_NAMES:
		_check("%s node name" % k, airplane.hinges[k].name == k + "_hinge")
		_check("%s rest pose" % k, airplane.hinges[k].transform.is_equal_approx(Transform3D.IDENTITY))
	for k in ["left", "right", "tail", "steering"]:
		_check("gear %s" % k, airplane.gear.has(k) and airplane.gear[k] is Node3D)
	for k in ["left", "right", "tail"]:
		_check("wheel node name %s" % k, airplane.gear.has(k) and airplane.gear[k].name == "wheel_" + k)
	_check("metadata", root.get_meta("aircraft_id", "") == D.id and String(root.get_meta("visual_revision", "")) == P51.VISUAL_REVISION
		and String(root.get_meta("status", "")).begins_with("experimental"))
	_check("manual throws", P51.manual_throws_deg().keys().size() == 3 and P51.manual_throws_deg().aileron > 0.0)

	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var triangles := 0
	var finite := true
	for m in meshes:
		var faces := m.mesh.get_faces()
		triangles += faces.size() / 3
		_check("mesh %s has faces" % m.name, faces.size() > 0)
		for v in faces:
			if not v.is_finite(): finite = false
		if not m.global_transform.origin.is_finite(): finite = false
	_check("every vertex finite", finite)

	var box := _bounds(root, meshes)
	_check("span", absf(box.size.x - float(w.span)) <= SPAN_TOLERANCE_M, "%.4f m vs %.4f m" % [box.size.x, w.span])
	_check("symmetric", absf(box.position.x + box.end.x) < 0.001, str(box))
	var expected_length: float = absf(float(D.spinner.tip_z)) + float(t.rudder_te_bottom[0])
	_check("length spinner tip to rudder TE", absf(box.size.z / expected_length - 1.0) <= LENGTH_TOLERANCE, "%.4f m vs %.4f m" % [box.size.z, expected_length])
	_check("nose at the spinner tip", absf(box.position.z - float(D.spinner.tip_z)) < 0.003, "%.4f" % box.position.z)

	# Dihedral: mean height of the tip ring versus the root ring of the right wing.
	var tip_sum := Vector3.ZERO
	var tip_n := 0
	var root_sum := Vector3.ZERO
	var root_n := 0
	for m in meshes:
		if m.name == "wing_right_tip":
			for v in _vertices(root, m):
				if v.x > half - 0.0015:
					tip_sum += v
					tip_n += 1
		if m.name == "wing_right_root":
			for v in _vertices(root, m):
				if absf(v.x) < 0.0015:
					root_sum += v
					root_n += 1
	var rise := (tip_sum / maxi(tip_n, 1)).y - (root_sum / maxi(root_n, 1)).y
	var expected_rise := half * tan(deg_to_rad(float(w.dihedral_deg)))
	_check("dihedral at the tip", tip_n > 0 and root_n > 0 and absf(rise / expected_rise - 1.0) <= 0.10, "%.4f m vs %.4f m" % [rise, expected_rise])

	# Aileron hinge axes: swept with the constant-fraction hinge line, pointing toward +X on both sides.
	var hf: float = 1.0 - float(w.aileron_chord_fraction)
	var hz_inner: float = lerpf(w.le_z_root, w.le_z_tip, w.aileron_inner / half) + hf * lerpf(w.root_chord, w.tip_chord, w.aileron_inner / half)
	var hz_outer: float = lerpf(w.le_z_root, w.le_z_tip, w.aileron_outer / half) + hf * lerpf(w.root_chord, w.tip_chord, w.aileron_outer / half)
	var slope: float = (hz_outer - hz_inner) / (w.aileron_outer - w.aileron_inner)
	for side in [["aileron_right", 1.0], ["aileron_left", -1.0]]:
		var axis: Vector3 = (root.global_transform.affine_inverse() * airplane.hinges[side[0]].global_transform).basis.x.normalized()
		_check("%s axis along the swept hinge" % side[0], axis.x > 0.98 and absf(axis.z / axis.x - side[1] * slope) < 0.01 and signf(axis.y) == side[1],
			"%s, expected dz/dx %.4f" % [axis, side[1] * slope])
	var el_axis: Vector3 = (root.global_transform.affine_inverse() * airplane.hinges.elevator.global_transform).basis.x
	# The stab incidence rotates the tail frame about X, which leaves the hinge axis on X.
	_check("elevator axis parallel to X", absf(el_axis.z) < 1e-6 and absf(el_axis.y) < 1e-6, str(el_axis))
	var rud_axis: Vector3 = (root.global_transform.affine_inverse() * airplane.hinges.rudder.global_transform).basis.y
	_check("rudder axis vertical", rud_axis.is_equal_approx(Vector3.UP), str(rud_axis))

	# Motion: +TEST_ANGLE about the hinge's x moves the trailing edge down (ailerons, elevator); about y moves the rudder
	# trailing edge right (+X), as input/commands.gd produces. Nothing outside the hinge subtree may move.
	for k in SURFACE_NAMES:
		var rot := Vector3(0, TEST_ANGLE, 0) if k == "rudder" else Vector3(TEST_ANGLE, 0, 0)
		var result := _travel(root, airplane, k, rot, meshes)
		var travel: Vector3 = result[0]
		if k == "rudder":
			_check("rudder trailing edge right", travel.x > 0.01 and absf(travel.y) < 0.002, str(travel))
		else:
			_check("%s trailing edge down" % k, travel.y < -0.01 and absf(travel.x) < 0.005, str(travel))
		_check("%s moves nothing else" % k, result[1] == 0, "%d other meshes moved" % result[1])
	# Same sense as the Stik for the same hinge rotation.
	var stik := Stik.build()
	get_root().add_child(stik.root)
	var stik_meshes: Array[MeshInstance3D] = []
	_meshes(stik.root, stik_meshes)
	for k in SURFACE_NAMES:
		var rot := Vector3(0, TEST_ANGLE, 0) if k == "rudder" else Vector3(TEST_ANGLE, 0, 0)
		var mine: Vector3 = _travel(root, airplane, k, rot, meshes)[0]
		var theirs: Vector3 = _travel(stik.root, stik, k, rot, stik_meshes)[0]
		var component := "x" if k == "rudder" else "y"
		_check("%s sign matches the Stik" % k, signf(mine[component]) == signf(theirs[component]) and absf(theirs[component]) > 0.003, "p51 %s stik %s" % [mine, theirs])
	stik.root.free()

	# Propeller: data blade count, each blade a mesh, all turning with the propeller node, tip-to-tip = diameter.
	var blades: Array[MeshInstance3D] = []
	for child in airplane.propeller.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("blade_"): blades.append(child)
	_check("blade meshes", blades.size() == int(D.propeller.blades), "%d" % blades.size())
	var prop_box := _bounds(airplane.propeller, blades)
	_check("propeller diameter", absf(prop_box.size.x - float(D.propeller.diameter)) < 0.002 and absf(prop_box.size.y - float(D.propeller.diameter)) < 0.002, str(prop_box.size))
	var before_spin := PackedVector3Array()
	for b in blades: before_spin.append_array(_vertices(root, b))
	airplane.propeller.rotation.z = 0.7
	var after_spin := PackedVector3Array()
	for b in blades: after_spin.append_array(_vertices(root, b))
	airplane.propeller.rotation.z = 0.0
	var spun := before_spin.size() == after_spin.size() and before_spin.size() > 0
	if spun:
		var max_move := 0.0
		for i in before_spin.size(): max_move = maxf(max_move, (after_spin[i] - before_spin[i]).length())
		spun = max_move > 0.1
	_check("blades turn with the propeller node", spun)
	var spinner_min_z := INF
	for m in meshes:
		if m.name == "spinner":
			for v in _vertices(root, m): spinner_min_z = minf(spinner_min_z, v.z)
	_check("spinner tip", absf(spinner_min_z - float(D.spinner.tip_z)) < 0.002, "%.4f" % spinner_min_z)

	# Gear: wheel bottoms at axle - radius, track from the data, nothing but wheels below the main wheels.
	var wheel_bottom: float = float(g.main_axle[1]) - float(g.main_wheel_diameter) / 2.0
	var lowest_other := INF
	var lowest_wheel := INF
	for m in meshes:
		var is_wheel := String(m.name).begins_with("wheel_")
		for v in _vertices(root, m):
			if is_wheel: lowest_wheel = minf(lowest_wheel, v.y)
			else: lowest_other = minf(lowest_other, v.y)
	_check("main wheels touch the lowest point", absf(lowest_wheel - wheel_bottom) < 0.002, "%.4f vs %.4f" % [lowest_wheel, wheel_bottom])
	_check("nothing below the wheels", lowest_other > wheel_bottom, "%.4f" % lowest_other)
	var track: float = airplane.gear.right.position.x - airplane.gear.left.position.x
	_check("track", absf(track - float(g.track)) < 0.002, "%.4f" % track)
	# V06: the leg rakes forward by the data angle, ends at the axle, the strut door stays inboard of the leg,
	# wheels carry spokes, the tail-wheel doors hang below the tail cone.
	for suffix in ["left", "right"]:
		var leg := root.find_child("main_strut_" + suffix, true, false) as MeshInstance3D
		var dir: Vector3 = -(root.global_transform.affine_inverse() * leg.global_transform).basis.y.normalized() # downwards
		if dir.y > 0.0: dir = -dir
		var rake := rad_to_deg(atan2(-dir.z, -dir.y))
		_check("leg rake %s" % suffix, absf(rake - float(g.rake_deg)) < 0.5, "%.2f deg" % rake)
		var half_len: float = (leg.mesh as CylinderMesh).height / 2.0
		var foot: Vector3 = leg.position + dir * half_len
		var axle: Vector3 = airplane.gear[suffix].position
		_check("leg ends at the axle %s" % suffix, absf(foot.z - axle.z) < 0.002 and absf(foot.y - axle.y) < 0.002, "%.4f %.4f" % [foot.z - axle.z, foot.y - axle.y])
		var door: MeshInstance3D = meshes.filter(func(m): return m.name == "gear_door_" + suffix)[0]
		var sgn := 1.0 if suffix == "right" else -1.0
		var door_out := -INF
		for v in _vertices(root, door): door_out = maxf(door_out, v.x * sgn)
		_check("strut door inboard of the leg %s" % suffix, door_out < leg.position.x * sgn - float(g.strut_radius) * 1.5, "%.4f" % door_out)
		var spokes := meshes.filter(func(m): return String(m.name).begins_with("wheel_%s_spoke_" % suffix))
		_check("hub spokes %s" % suffix, spokes.size() == 2 * int(g.hub_spokes), str(spokes.size()))
		var tail_door := meshes.filter(func(m): return m.name == "tail_door_" + suffix)
		var door_low := INF
		if tail_door.size() == 1:
			for v in _vertices(root, tail_door[0]): door_low = minf(door_low, v.y)
		_check("tail-wheel door hangs open %s" % suffix, tail_door.size() == 1 and door_low < P51.skin_y(float(g.tail_axle[0]), 0.0, false) - 0.02, "%.4f" % door_low)
	airplane.gear.steering.rotation.y = 0.4
	_check("tail wheel steers with the pivot", not (root.global_transform.affine_inverse() * airplane.gear.tail.global_transform).basis.x.is_equal_approx(Vector3.RIGHT))
	airplane.gear.steering.rotation.y = 0.0

	# Shapes: scoop depth, fin height, stab span, canopy crown and the pilot under it.
	var lows := {}
	var highs := {}
	for m in meshes:
		var lo := INF
		var hi := -INF
		for v in _vertices(root, m):
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		lows[String(m.name)] = lo
		highs[String(m.name)] = hi
	var scoop_bottom := INF
	for row in D.scoop_stations: scoop_bottom = minf(scoop_bottom, row[2])
	_check("scoop depth", absf(lows.scoop - scoop_bottom) < 0.003, "%.4f vs %.4f" % [lows.scoop, scoop_bottom])
	_check("fin height", absf(highs.fin - float(t.fin_top_y)) < 0.005 and absf(highs.rudder - float(t.fin_top_y)) < 0.01, "%.4f / %.4f" % [highs.fin, highs.rudder])
	var stab_box := _bounds(root, [meshes.filter(func(m): return m.name == "stab")[0]] as Array[MeshInstance3D])
	_check("stab span", absf(stab_box.size.x - 2.0 * float(t.stab_half_span)) < 0.005, "%.4f" % stab_box.size.x)
	# V04: faceted windscreen under the measured canopy line, opaque frames, hood rails, gunsight; the hood keeps the crown.
	var ws_mesh := meshes.filter(func(m): return m.name == "windscreen")
	_check("windscreen present", ws_mesh.size() == 1)
	var ws_over := 0.0
	for vtx in _vertices(root, ws_mesh[0]):
		ws_over = maxf(ws_over, vtx.y - P51.monotone(D.canopy.top, vtx.z))
	_check("windscreen never above the measured canopy line", ws_over <= 0.003, "%.4f" % ws_over)
	for name in ["windscreen_frame_1", "windscreen_frame_2", "windscreen_frame_front", "hood_rail_left", "hood_rail_right", "gunsight"]:
		var found := meshes.filter(func(m): return m.name == name)
		var opaque: bool = found.size() == 1 and (found[0].mesh.surface_get_material(0) as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		_check("%s present and opaque" % name, opaque)
	# V10: gun ports on the leading edge, pitot under the right wing, antenna mast above the deck, trim tabs and tail
	# light on the moving surfaces, navigation lights at the tips.
	var de: Dictionary = D.details
	for side in ["left", "right"]:
		var sgn := 1.0 if side == "right" else -1.0
		for i in 3:
			var port := root.find_child("gun_port_%s_%d" % [side, i], true, false) as MeshInstance3D
			var x: float = sgn * float(de.gun_ports.x[i])
			var le_z: float = (airplane.frames[side] * P51._wing_skin_point(x, 0.0, true, true)).z
			var rear := port.position.z + (port.mesh as CylinderMesh).height / 2.0
			_check("gun port %s %d sits on the leading edge" % [side, i], port != null and absf(rear - 0.01 - le_z) < 0.005 and absf(port.position.x - x) < 0.002, "%.4f vs %.4f" % [rear, le_z])
		var tab := root.find_child("elevator_tab_" + side, true, false)
		_check("elevator tab %s hangs from the elevator hinge" % side, tab != null and tab.get_parent().name == "elevator_hinge")
		var nav := root.find_child("nav_light_" + side, true, false) as MeshInstance3D
		_check("nav light %s at the tip" % side, nav != null and absf(nav.position.x) > float(D.wing.span) / 2.0 - 0.03, "%.4f" % (nav.position.x if nav else 0.0))
	var pitot := root.find_child("pitot_tube", true, false) as MeshInstance3D
	var wing_low: float = (airplane.frames["right"] * P51._wing_skin_point(float(de.pitot.x), float(de.pitot.chord_fraction), false)).y
	_check("pitot under the right wing", pitot != null and pitot.position.x > 0.0 and pitot.position.y < wing_low - 0.02, "%.4f < %.4f" % [pitot.position.y if pitot else 0.0, wing_low])
	var mast := root.find_child("antenna_mast", true, false) as MeshInstance3D
	var mast_top_y: float = mast.position.y + (mast.mesh as CylinderMesh).height / 2.0 * absf(mast.basis.y.y) if mast else 0.0
	_check("antenna mast rises above the deck", mast != null and mast_top_y > P51.profile(mast.position.z, 2) + 0.08, "%.4f" % mast_top_y)
	var rtab := root.find_child("rudder_tab", true, false)
	_check("rudder tab hangs from the rudder hinge", rtab != null and rtab.get_parent().name == "rudder_hinge")
	var tl := root.find_child("tail_light", true, false)
	_check("tail light on the rudder", tl != null and tl.get_parent().name == "rudder_hinge")
	# V05: exhaust stacks stay short (no vertex further than length + 3 mm outboard of the local skin) and sit high on
	# the flank. V07: cuffed blades (max chord 0.18-0.26 r) and the thrust frame dips by the drawing's down thrust.
	var worst_protrusion := 0.0
	var ex: Dictionary = D.exhausts
	for m in meshes:
		if String(m.name).begins_with("exhaust_"):
			for vtx in _vertices(root, m):
				worst_protrusion = maxf(worst_protrusion, absf(vtx.x) - P51.skin_half_width_at(vtx.z, clampf(vtx.y, -0.05, P51.profile(vtx.z, 2))))
	_check("exhaust stacks protrude at most their length", worst_protrusion <= float(ex.length) + 0.003, "%.4f vs %.4f" % [worst_protrusion, ex.length])
	var chord_max := 0.0
	for row in D.propeller.blade.chord_fraction_of_radius: chord_max = maxf(chord_max, row[1])
	_check("cuffed paddle blade: max chord between 0.18 and 0.26 of the radius", chord_max >= 0.18 and chord_max <= 0.26, str(chord_max))
	var thrust_node: Node3D = root.find_child("thrust_frame", true, false)
	var forward: Vector3 = thrust_node.transform.basis * Vector3(0, 0, -1)
	_check("thrust axis dips by the drawing's down thrust", absf(forward.y + sin(deg_to_rad(float(D.propeller.down_thrust_deg)))) < 1e-4, str(forward))
	# V03: scoop duct width = the stations' half-width, gutter slot under the fuselage at the mouth, exit door present, and
	# the carburettor intake restoring the measured cowl line (cowl stations were lowered by the intake's height profile).
	var scoop_mesh: MeshInstance3D = meshes.filter(func(m): return m.name == "scoop")[0]
	var scoop_hw := 0.0
	var mouth_top := -INF
	var z_mouth: float = D.scoop_stations[0][0]
	for vtx in _vertices(root, scoop_mesh):
		scoop_hw = maxf(scoop_hw, absf(vtx.x))
		if absf(vtx.z - z_mouth) < 0.003 and absf(vtx.x) < 0.005: mouth_top = maxf(mouth_top, vtx.y) # duct top on the centreline
	var hw_max := 0.0
	for row in D.scoop_stations: hw_max = maxf(hw_max, row[1])
	_check("scoop duct width = stations' half-width", absf(scoop_hw - hw_max) < 0.003, "%.4f vs %.4f" % [scoop_hw, hw_max])
	var skin_at_mouth: float = P51.skin_y(z_mouth, 0.0, false)
	_check("boundary-layer gutter: duct top at the mouth sits gutter.gap below the fuselage", absf((skin_at_mouth - mouth_top) - float(D.scoop_gutter.gap)) < 0.002, "%.4f vs gap %.4f" % [skin_at_mouth - mouth_top, D.scoop_gutter.gap])
	_check("scoop exit door present", meshes.any(func(m): return m.name == "scoop_exit_door"))
	var intake_mesh: MeshInstance3D = meshes.filter(func(m): return m.name == "carb_intake")[0]
	var intake_top := -INF
	var cowl_top_lowered := -INF
	for vtx in _vertices(root, intake_mesh): intake_top = maxf(intake_top, vtx.y)
	var ci: Dictionary = D.carb_intake
	var best := 0.0
	for k in 101:
		var z := lerpf(float(ci.z0), float(ci.z1), float(k) / 100.0)
		var expected: float = P51.profile(z, 2) + float(ci.height) * P51._intake_profile((z - float(ci.z0)) / (float(ci.z1) - float(ci.z0)))
		best = maxf(best, expected)
	_check("carburettor intake top = lowered cowl + height profile (measured line restored)", absf(intake_top - best) < 0.006, "%.4f vs %.4f" % [intake_top, best])
	# V02: root leading-edge extension (measured), hinge lines untouched by it, tip rounded in plan, root fillets present.
	var root_mesh: MeshInstance3D = meshes.filter(func(m): return m.name == "wing_right_root")[0]
	var root_min_z := INF
	for v in _vertices(root, root_mesh): root_min_z = minf(root_min_z, v.z)
	var ext0: float = D.wing.root_extension[0][1]
	_check("root leading edge extended forward by the measured kink", absf(root_min_z - (float(D.wing.le_z_root) - ext0)) < 0.004, "%.4f vs %.4f" % [root_min_z, float(D.wing.le_z_root) - ext0])
	_check("extension ends inboard of the aileron (hinges untouched)", P51._root_ext(float(D.wing.aileron_inner)) == 0.0 and P51._root_ext(float(D.wing.flap_outer)) == 0.0)
	var tip_plan: Array = P51._tip_plan(float(w.span) / 2.0 - 0.002)
	_check("wing tip rounded in plan", float(tip_plan[1]) < 0.4, str(tip_plan))
	for side in ["left", "right"]:
		var fillet := meshes.filter(func(m): return m.name == "root_fillet_" + side)
		_check("root fillet %s present with faces" % side, fillet.size() == 1 and fillet[0].mesh.get_surface_count() > 0)
	# V01: tail shapes from the measured outlines. Fin LE monotone (no loops), stab tip rounded in plan, elevator horn
	# balance ahead of the hinge at the tip, and clearances of rudder/elevators against their neighbours at the flown
	# throws and at 45 deg (same checker as the Extra, tail pairs only).
	var fin_mesh: MeshInstance3D = meshes.filter(func(m): return m.name == "fin")[0]
	var le_ok := true
	var prev_z := -INF
	for y_step in 12:
		var y := lerpf(lows.fin + 0.01, highs.fin - 0.02, float(y_step) / 11.0)
		var z_min := INF
		for v in _vertices(root, fin_mesh):
			if absf(v.y - y) < 0.004: z_min = minf(z_min, v.z)
		if z_min < prev_z - 0.002: le_ok = false
		if z_min < INF: prev_z = z_min
	_check("fin leading edge sweeps aft monotonically with height", le_ok)
	var tip_corner := 0
	var stab_mesh: MeshInstance3D = meshes.filter(func(m): return m.name == "stab")[0]
	var plan_tip: Array = P51._stab_plan(float(t.stab_half_span) - 0.002)
	var plan_mid: Array = P51._stab_plan(0.5 * float(t.stab_half_span))
	_check("stab tip rounded in plan (tip chord < 40 % of mid chord)", (plan_tip[1] - plan_tip[0]) < 0.4 * (plan_mid[1] - plan_mid[0]), "%.3f vs %.3f" % [plan_tip[1] - plan_tip[0], plan_mid[1] - plan_mid[0]])
	for v in _vertices(root, stab_mesh):
		if absf(v.x) > float(t.stab_half_span) - 0.001 and v.z < plan_tip[0] - 0.01: tip_corner += 1
	_check("no stab vertex ahead of the rounded tip", tip_corner == 0, str(tip_corner))
	var horn_ahead := 0
	var hinge_z_frame := 0.0
	for m in meshes:
		if m.name == "elevator_right":
			for v in _vertices(root, m):
				var s_frac: float = absf(v.x) / float(t.stab_half_span)
				var plan_v: Array = P51._stab_plan(absf(v.x))
				var frac: float = (v.z - plan_v[0]) / (plan_v[1] - plan_v[0])
				if s_frac > float(t.elevator_horn.span_from_fraction) + 0.02 and frac < float(t.elevator_hinge_fraction) - 0.05: horn_ahead += 1
	_check("elevator horn balance reaches ahead of the hinge line at the tip", horn_ahead > 0, str(horn_ahead))
	# Hinge clearances live in verify_p51_clearance.gd (the Extra's checker needs ~5 s per pose and pair on these lofts).
	var fus_max_z := -INF
	for m in meshes:
		if m.name == "fuselage":
			for v in _vertices(root, m): fus_max_z = maxf(fus_max_z, v.z)
	_check("tail cone ends ahead of the rudder hinge", fus_max_z < float(t.rudder_hinge_z) - 0.002, "%.4f vs hinge %.4f" % [fus_max_z, t.rudder_hinge_z])
	var crown := -INF
	for p in D.canopy.top: crown = maxf(crown, p[1])
	_check("canopy crown", absf(highs.canopy - crown) < 0.004, "%.4f vs %.4f" % [highs.canopy, crown])
	var pilot_node: Node3D = root.find_child("pilot", false, false)
	var outside := 0
	var pilot_vertices := 0
	if pilot_node != null:
		var pilot_meshes: Array[MeshInstance3D] = []
		_meshes(pilot_node, pilot_meshes)
		for m in pilot_meshes:
			for v in _vertices(root, m):
				pilot_vertices += 1
				if v.y > P51.monotone(D.canopy.top, v.z) - 0.001 or absf(v.x) > P51.profile(v.z, 1): outside += 1
	_check("pilot inside the canopy", pilot_vertices > 0 and outside == 0, "%d of %d vertices outside" % [outside, pilot_vertices])
	var glass: Material = (root.find_child("canopy", false, false) as MeshInstance3D).mesh.surface_get_material(0)
	_check("canopy transparent", glass is StandardMaterial3D and glass.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and is_equal_approx(glass.albedo_color.a, P51.GLASS_ALPHA))
	var skin: Material = (root.find_child("fuselage", false, false) as MeshInstance3D).mesh.surface_get_material(0)
	_check("natural-metal fuselage", P51.Finish.metallic_of(skin) >= 0.7, "%.2f" % P51.Finish.metallic_of(skin))
	# V08: the finish shader draws every fixed skin (fuselage, wing skins, stab, fin) with its own part; it never reads TIME.
	var finish_parts := {"fuselage": P51.Finish.FUSELAGE, "wing_left_root": P51.Finish.WING, "wing_right_ahead_of_aileron": P51.Finish.WING, "stab": P51.Finish.TAIL_H, "fin": P51.Finish.TAIL_V, "elevator_left": P51.Finish.PLAIN, "aileron_right": P51.Finish.PLAIN}
	for label in finish_parts:
		var mesh := root.find_child(label, true, false) as MeshInstance3D
		var mat: Material = mesh.mesh.surface_get_material(0) if mesh else null
		var ok: bool = mat is ShaderMaterial and int((mat as ShaderMaterial).get_shader_parameter("part")) == finish_parts[label]
		_check("finish part on %s" % label, ok)
	_check("finish shader never reads TIME", not RegEx.create_from_string("(?m)^\\s*[^/\\s].*\\bTIME\\b").search(P51.Finish.SHADER_CODE))
	var rudder_mat: Material = (root.find_child("rudder", true, false) as MeshInstance3D).mesh.surface_get_material(0)
	_check("yellow rudder", rudder_mat is StandardMaterial3D and rudder_mat.albedo_color.is_equal_approx(P51.YELLOW))

	# Deterministic: a second build hashes identically.
	var again := P51.build()
	get_root().add_child(again.root)
	_check("deterministic build", _hash(root) == _hash(again.root))
	again.root.free()

	print("p51 preview: %d meshes, %d triangles, extent %.3f x %.3f x %.3f m" % [meshes.size(), triangles, box.size.x, box.size.y, box.size.z])
	print("verify_p51: %d checks, %d failed%s" % [_checks, _failures, "" if _failures == 0 else " FAIL"])
	root.free()
	quit(1 if _failures > 0 else 0)
