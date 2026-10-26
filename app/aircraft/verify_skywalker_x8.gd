# X8-02 contract checks for the Skywalker X8 r4 imported model (headless).
# Proves that the scene Godot imports is the frozen r4 asset (hash, counts, section tags, pivots against the compiled
# geometry), that the production model registry builds both skins by visual family (no catalog entry yet), and that the
# elevons, propeller, static camera doors, default-skin paint targets and independent instances behave as the session
# expects. Run: python3 tools/godot/run_checked.py --timeout 120 -- "$(app/get-godot.sh)" --headless --path app --script res://aircraft/verify_skywalker_x8.gd
extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const Importer := preload("res://aircraft/imported_model.gd")
const Geometry := preload("res://aircraft/skywalker_x8_geometry.gd")
const FAMILY := "skywalker-x8"
const GLB_PATH := "res://assets/aircraft/skywalker-x8/skywalker_x8.glb"
const CUSTOMIZATION_SOURCE := "res://../assets/aircraft/customization-bindings.json"
const EXPECTED_SHA256 := "3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac"
const SECTIONS := ["core", "canopy", "wing_left", "wing_right", "engine", "propeller"]
const DOORS := ["camera_door_left_hinge", "camera_door_right_hinge"]
# Full-stick deflections of the delivery's default mix (metadata ranges), app convention: + = trailing edge up.
const PITCH_DEG := 19.47
const ROLL_DEG := 23.26
const TE_UP_STOP := 26.76 # delivery -26.76 (trailing edge up)
const TE_DOWN_STOP := 26.85 # delivery +26.85 (trailing edge down)
var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _initialize() -> void:
	_asset()
	var described := Registry.describe(FAMILY)
	_check("registry accepts the checked-in skywalker-x8 manifest", described.ok, str(described.get("errors", [])))
	if described.ok:
		_skins(described.manifest)
		_controls(described.manifest)
		_instances(described.manifest)
	print("X8-02 Skywalker X8 imported model %s: %d checks, %d failures" % [Geometry.DATA.revision, checks, failures])
	print("PASS X8-02 %d checks" % checks if failures == 0 else "FAIL X8-02 %d of %d checks" % [failures, checks])
	quit(1 if failures else 0)


func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


## Mean model-frame position of a mesh's aftmost vertices (its trailing edge, a 2 mm strip).
func _trailing_edge(root: Node3D, mesh: MeshInstance3D) -> Vector3:
	var xf := Importer.relative(root, mesh)
	var points: Array[Vector3] = []
	for surface in mesh.mesh.get_surface_count():
		for v: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			points.append(xf * v)
	var aft := -INF
	for p in points: aft = maxf(aft, p.z)
	var sum := Vector3.ZERO
	var count := 0
	for p in points:
		if p.z >= aft - 0.002:
			sum += p
			count += 1
	return sum / float(count)


## The imported scene is the frozen delivery: bytes, node set, sections and the counts the author reported.
func _asset() -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(GLB_PATH))
	_check("runtime GLB is the accepted r4 aircraft.glb (abisal)", context.finish().hex_encode() == EXPECTED_SHA256 and Geometry.DATA.inputs.glb_sha256 == EXPECTED_SHA256)
	var scene: Node3D = (load(GLB_PATH) as PackedScene).instantiate()
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var surfaces := 0
	var wrong := []
	for mesh: MeshInstance3D in meshes:
		surfaces += mesh.mesh.get_surface_count()
		for s in mesh.mesh.get_surface_count():
			triangles += int(mesh.mesh.surface_get_array_index_len(s) / 3)
		var section := str((mesh.get_meta("extras", {}) as Dictionary).get("openrc_section", ""))
		if not SECTIONS.has(section) or section != str(Geometry.DATA.sections.get(str(mesh.name), "")): wrong.append(mesh.name)
	_check("11 meshes, 24 surfaces, 38,504 triangles as delivered", meshes.size() == 11 and surfaces == 24 and triangles == 38504
		and triangles == int(Geometry.DATA.dimensions.triangles), "%d meshes, %d surfaces, %d triangles" % [meshes.size(), surfaces, triangles])
	_check("every mesh carries the delivered openrc_section", wrong.is_empty(), str(wrong))
	var worst := 0.0
	var records: Dictionary = Geometry.DATA.articulations.merged(Geometry.DATA.unbound_pivots)
	records.thrust_frame = Geometry.DATA.thrust
	for name: String in records:
		var node := scene.find_child(name, true, false) as Node3D
		if node == null or str(node.get_parent().name) != str(records[name].parent):
			worst = INF
			continue
		worst = maxf(worst, node.position.distance_to(_v(records[name].rest_translation)))
		for axis in 3:
			worst = maxf(worst, node.basis[axis].distance_to(_v(records[name].rest_basis["xyz"[axis]])))
	_check("elevon, door, propeller and thrust-frame rests match the compiled geometry", worst < 2e-5, "%.7f" % worst)
	scene.free()


## Both skins build through the registry by family; each carries its own GLB identity and the default's airframe.
func _skins(manifest: Dictionary) -> void:
	var ids: Array = manifest.liveries.map(func(record: Dictionary) -> String: return str(record.id))
	_check("two skins, abisal (default) then bolido", ids == ["abisal", "bolido"] and manifest.liveries[0].path == manifest.asset.path)
	var paint := _paint_targets()
	for id: String in ids:
		var selected := Registry.livery(manifest, id)
		_check(id + ": registry verifies its GLB and sidecar", selected.ok, str(selected.get("errors", [])))
		if not selected.ok: continue
		var built := Importer.build_checked(manifest, id)
		_check(id + ": shared importer builds the scene", built.ok, str(built.errors))
		if not built.ok: continue
		var model: Dictionary = built.model
		var root: Node3D = model.root
		var derived := Registry.validate_derived(manifest, model)
		_check(id + ": registry accepts the built model (hinges, rotor, asset, crash sections)", derived.ok, str(derived.get("errors", [])))
		_check(id + ": root carries the skin, its GLB hash and the family", root.name == "airplane" and model.livery == id
			and str(root.get_meta("asset_sha256", "")) == str(selected.livery.sha256) and str(root.get_meta("aircraft_id", "")) == FAMILY)
		var names := ["SkywalkerX8", "fuselage_core", "bay_equipment", "canopy_hatch", "wing_left_fixed", "wing_right_fixed", "motor_mount",
			"elevon_left_hinge", "elevon_left", "elevon_right_hinge", "elevon_right", "camera_door_left_hinge", "camera_door_left",
			"camera_door_right_hinge", "camera_door_right", "thrust_frame", "propeller_mount", "propeller", "propeller_spin", "propeller_rotor"]
		var missing := names.filter(func(n: String) -> bool: return root.find_children(n, "", true, false).size() != 1)
		_check(id + ": every delivered node and the generated propeller wrapper exist once", missing.is_empty(), str(missing))
		_check(id + ": two control hinges, no gear, no folds or mechanisms", model.hinges.keys() == ["elevon_left", "elevon_right"]
			and model.gear.is_empty() and model.folds.is_empty() and model.mechanisms.is_empty())
		if id == "abisal":
			var bad := []
			for target: Dictionary in paint:
				var mesh := root.get_node_or_null(str(target.node_path)) as MeshInstance3D
				var material: Material = mesh.get_active_material(int(target.surface)) if mesh != null and int(target.surface) < mesh.mesh.get_surface_count() else null
				if material == null or str(material.resource_name) != "x8_livery": bad.append(target.node_path)
			_check("abisal: the eight Workshop paint targets are the x8_livery surfaces", paint.size() == 8 and bad.is_empty(), str(bad))
		root.free()


func _paint_targets() -> Array:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(CUSTOMIZATION_SOURCE))
	var targets := []
	if source is Dictionary:
		for family: Dictionary in source.get("families", []):
			if family.visual_family == FAMILY:
				for slot: Dictionary in family.paint_slots: targets.append_array(slot.targets)
	return targets


## Elevons, propeller and doors on the default skin.
func _controls(manifest: Dictionary) -> void:
	var built := Importer.build_checked(manifest)
	if not built.ok: return
	var model: Dictionary = built.model
	var root: Node3D = model.root
	var left: Dictionary = model.hinges.elevon_left
	var right: Dictionary = model.hinges.elevon_right
	_check("elevon app sign is -1 (delivery + is trailing edge down)", left.app_sign == -1.0 and right.app_sign == -1.0
		and left.positive == "trailing edge down" and right.positive == "trailing edge down")
	var mesh_l := root.find_child("elevon_left", true, false) as MeshInstance3D
	var mesh_r := root.find_child("elevon_right", true, false) as MeshInstance3D
	var rest_l := _trailing_edge(root, mesh_l)
	var rest_r := _trailing_edge(root, mesh_r)
	var doors := {}
	for name: String in DOORS:
		doors[name] = (root.find_child(name, true, false) as Node3D).transform
	Importer.apply_surfaces(model, {aileron_right = 0.0, aileron_left = 0.0, elevator = 0.0, rudder = 0.0})
	_check("neutral surfaces leave both elevons exactly at rest", left.node.basis == left.rest and right.node.basis == right.rest
		and _trailing_edge(root, mesh_l) == rest_l and _trailing_edge(root, mesh_r) == rest_r)
	# [label, elevator, aileron_right, aileron_left, expected right, expected left] (app degrees, trailing edge up)
	var cases := [
		["pitch up (full stick)", PITCH_DEG, 0.0, 0.0, PITCH_DEG, PITCH_DEG],
		["pitch down (full stick)", -PITCH_DEG, 0.0, 0.0, -PITCH_DEG, -PITCH_DEG],
		["roll right (full stick)", 0.0, ROLL_DEG, -ROLL_DEG, ROLL_DEG, -ROLL_DEG],
		["roll left (full stick)", 0.0, -ROLL_DEG, ROLL_DEG, -ROLL_DEG, ROLL_DEG],
		["combined, right at the trailing-edge-up stop", 0.5 * (TE_UP_STOP - 6.0), 0.5 * (TE_UP_STOP + 6.0), -0.5 * (TE_UP_STOP + 6.0), TE_UP_STOP, -6.0],
		["combined, left at the trailing-edge-down stop", 0.5 * (4.0 - TE_DOWN_STOP), 0.5 * (4.0 + TE_DOWN_STOP), -0.5 * (4.0 + TE_DOWN_STOP), 4.0, -TE_DOWN_STOP],
	]
	var clearance: Array = Geometry.DATA.articulations.elevon_left_hinge.clearance_deg
	for item: Array in cases:
		Importer.apply_surfaces(model, {elevator = item[1], aileron_right = item[2], aileron_left = item[3], rudder = 0.0})
		var turned_r := _turned(right)
		var turned_l := _turned(left)
		var rise_r := _trailing_edge(root, mesh_r).y - rest_r.y
		var rise_l := _trailing_edge(root, mesh_l).y - rest_l.y
		# A trailing edge up (app +) pose raises that trailing edge; delivery angle = -app stays inside the clearance.
		var ok: bool = absf(turned_r - absf(item[4])) < 1e-3 and absf(turned_l - absf(item[5])) < 1e-3 \
			and signf(rise_r) == signf(item[4]) and signf(rise_l) == signf(item[5]) \
			and -float(item[4]) > float(clearance[0]) and -float(item[4]) < float(clearance[1]) \
			and -float(item[5]) > float(clearance[0]) and -float(item[5]) < float(clearance[1])
		_check("%s: right %.2f, left %.2f deg trailing edge up" % [item[0], item[4], item[5]], ok,
			"turned %.3f/%.3f deg, trailing edge rise %.4f/%.4f m" % [turned_r, turned_l, rise_r, rise_l])
	Importer.apply_surfaces(model, {aileron_right = 0.0, aileron_left = 0.0, elevator = PITCH_DEG, rudder = 0.0})
	_check("a pitch-up command raises both trailing edges", _trailing_edge(root, mesh_l).y > rest_l.y + 0.01 and _trailing_edge(root, mesh_r).y > rest_r.y + 0.01)
	Importer.apply_surfaces(model, {})
	_check("returning to neutral restores the delivered rest exactly", left.node.basis == left.rest and right.node.basis == right.rest)
	var static_doors := true
	for name: String in DOORS:
		static_doors = static_doors and (root.find_child(name, true, false) as Node3D).transform == doors[name]
	var bound := false
	for control: Dictionary in manifest.bindings.controls.values():
		for hinge: Dictionary in control.hinges: bound = bound or DOORS.has(str(hinge.node))
	_check("camera doors stay static and unbound through every pose", static_doors and not bound)

	# Pusher propeller: the public wrapper spins about the thrust axis through the hub, aft of the wing.
	var propeller: Node3D = model.propeller
	var spin := root.find_child("propeller_spin", true, false) as Node3D
	var frame := Importer.relative(root, propeller)
	var hub := _v(Geometry.DATA.thrust.rest_translation)
	_check("propeller wrapper sits at the hub with its Z on the thrust axis (nose, -Z)", model.has_propeller and propeller.is_ancestor_of(spin)
		and frame.origin.distance_to(hub) < 1e-6 and absf(frame.basis.z.normalized().dot(Vector3(0, 0, -1))) > 0.99999, str(frame))
	var rotor := root.find_child("propeller_rotor", true, false) as MeshInstance3D
	var blade := Importer.relative(root, rotor) * rotor.mesh.get_aabb().get_center()
	propeller.rotation.z = PI / 2.0
	var turned := Importer.relative(root, rotor) * rotor.mesh.get_aabb().get_center()
	propeller.rotation.z = 0.0
	_check("spinning the propeller keeps the rotor on its hub (thrust-axis spin)", absf(blade.z - turned.z) < 1e-5
		and absf(Vector2(blade.x - hub.x, blade.y - hub.y).length() - Vector2(turned.x - hub.x, turned.y - hub.y).length()) < 1e-5)
	_check("the rotor is aft of the wing root leading edge (pusher)", hub.z > 0.5 and blade.z > 0.5)
	root.free()


## Independent instances: distinct pivots sharing immutable mesh resources; posing one leaves the other at rest.
func _instances(manifest: Dictionary) -> void:
	var first := Importer.build_checked(manifest)
	var second := Importer.build_checked(manifest)
	if not first.ok or not second.ok:
		_check("two independent instances build", false)
		return
	var a: Dictionary = first.model
	var b: Dictionary = second.model
	Importer.apply_surfaces(a, {elevator = 12.0, aileron_right = 5.0, aileron_left = -5.0})
	a.propeller.rotation.z = 1.0
	var mesh_a := a.root.find_child("elevon_left", true, false) as MeshInstance3D
	var mesh_b := b.root.find_child("elevon_left", true, false) as MeshInstance3D
	_check("two instances own distinct roots and hinge pivots", a.root != b.root and a.hinges.elevon_left.node != b.hinges.elevon_left.node)
	_check("posing one instance leaves the other at rest", b.hinges.elevon_left.node.basis == b.hinges.elevon_left.rest
		and b.hinges.elevon_right.node.basis == b.hinges.elevon_right.rest and b.propeller.rotation.z == 0.0)
	_check("instances share the immutable imported mesh", mesh_a.mesh == mesh_b.mesh)
	a.root.free()
	b.root.free()


## The hinge's turn from rest in degrees (rotation about its own axis).
func _turned(hinge: Dictionary) -> float:
	return rad_to_deg((hinge.rest.inverse() * hinge.node.basis).get_rotation_quaternion().get_angle())
