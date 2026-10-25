# F4U-12 contract checks for the F4U Corsair 1/4.5 imported model (headless).
# Proves that the scene Godot imports is the frozen g2.2 asset (hash, counts, section tags, pivots against the delivered
# metadata), that the production registry builds it, and that surfaces, flaps, propeller, sampled gear, oleo compression,
# exhaust anchor, paint slots, wing fold, canopy and tailhook behave as the session expects. Run: godot --headless --path app --script res://aircraft/verify_f4u.gd
extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const Importer := preload("res://aircraft/imported_model.gd")
const Manifest := preload("res://aircraft/model_manifest.gd")
const Rig := preload("res://aircraft/retractable_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Geometry := preload("res://aircraft/f4u_corsair_geometry.gd")
const WreckController := preload("res://render/crash/wreck.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const GearPhysics := preload("res://physics/retractable_gear.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const Math64 := preload("res://physics/math3d.gd")
const Hull := preload("res://physics/hull_contact.gd")
const ContactContract := preload("res://physics/aircraft_contact_contract.gd")
const ContactEvents := preload("res://sim/aircraft_contact_events.gd")
const Impact := preload("res://physics/impact_snapshot.gd")
const GLB_PATH := "res://assets/aircraft/f4u-corsair-250/f4u_corsair.glb"
const DATA_PATH := "res://data/aircraft/f4u_corsair_250.json"
const ID := "f4u-corsair-250"
const EXPECTED_SHA256 := "9fa3b86a9b33cdc16eefde328b347bb8af2c4191684f4c7db922acf7ba2c0851"
const SECTIONS := ["core", "wing_left", "wing_right", "wing_center", "horizontal_tail", "vertical_tail", "engine", "propeller", "gear", "canopy"]
var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else " (" + detail + ")"))


func _extreme(root: Node3D, mesh: MeshInstance3D, direction: Vector3) -> Vector3:
	var xf := Importer.relative(root, mesh)
	var best := Vector3.ZERO
	var score := -INF
	for surface in mesh.mesh.get_surface_count():
		for v: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var p := xf * v
			if p.dot(direction) > score:
				score = p.dot(direction)
				best = p
	return best


func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_asset()
	_built_model()
	_presentation()
	await _crash_release()
	print("F4U-12 Corsair imported model %s: %d checks, %d failures" % [Geometry.DATA.revision, checks, failures])
	print("PASS F4U-12 %d checks" % checks if failures == 0 else "FAIL F4U-12 %d of %d checks" % [failures, checks])
	quit(1 if failures else 0)


## F4U-17: each outer panel (panel, aileron, outer flap) folds in place about R59's hinge; the runtime rotation must
## carry R59's spread navigation lamp to Blender's own folded evaluation of it, and controls must ride on the panel.
func _fold_checks(model: Dictionary) -> void:
	var folds: Dictionary = model.get("folds", {})
	_check("two fold groups of three outer-panel nodes each", folds.size() == 2 and folds.values().all(func(f: Dictionary) -> bool: return f.members.size() == 3))
	if folds.size() != 2: return
	var worst := 0.0
	for side: String in ["left", "right"]:
		var record: Dictionary = Geometry.DATA.folds[side]
		Importer.apply_folds(model, {"wing_fold_" + side: 1.0})
		var fold: Dictionary = folds["wing_fold_" + side]
		worst = maxf(worst, (fold.transform * _v(record.check_lamp_spread)).distance_to(_v(record.check_lamp_folded)))
	_check("full fold (112 deg) carries each navigation lamp to R59's folded evaluation", worst < 1e-5, "%.7f m" % worst)
	var left: Dictionary = folds.wing_fold_left
	Importer.apply_folds(model, {"wing_fold_left": 0.12, "wing_fold_right": 0.12})
	var released: float = left.degrees
	Importer.apply_folds(model, {"wing_fold_left": 0.53, "wing_fold_right": 0.53})
	_check("the locks release over the first 12 %, then the panel turns linearly", released == 0.0 and absf(left.degrees - 56.0) < 1e-6, "%.3f, %.3f deg" % [released, left.degrees])
	Importer.apply_folds(model, {"wing_fold_left": 1.0, "wing_fold_right": 1.0})
	var aileron: Dictionary = model.hinges.aileron_left
	Importer.apply_surfaces(model, {"aileron_left": 10.0})
	var on_panel: bool = (left.transform.affine_inverse() * aileron.node.transform).is_equal_approx(Transform3D(aileron.unfolded_basis, aileron.pivot))
	Importer.apply_folds(model, {"wing_fold_left": 0.0, "wing_fold_right": 0.0})
	var unfolded: bool = aileron.node.transform.is_equal_approx(Transform3D(aileron.unfolded_basis, aileron.pivot))
	Importer.apply_surfaces(model, {})
	var rest_error := 0.0
	for fold: Dictionary in folds.values():
		for member: Dictionary in fold.members:
			rest_error = maxf(rest_error, (member.node.transform.origin - member.rest.origin).length())
			for axis in 3:
				rest_error = maxf(rest_error, (member.node.transform.basis[axis] - member.rest.basis[axis]).length())
	_check("an aileron deflected while folded rides on its panel and keeps its deflection when spread", on_panel and unfolded)
	_check("spreading with neutral controls restores every outer-panel node to its delivered rest", rest_error < 1e-6, "%.8f" % rest_error)


## F4U-21: the canopy slides and the tailhook turns in place by R59's laws, and both return exactly to rest.
func _mechanism_checks(model: Dictionary, manifest: Dictionary) -> void:
	var mechanisms: Dictionary = model.get("mechanisms", {})
	var names := func(key: String) -> Array:
		var found := []
		for part: Dictionary in mechanisms.get(key, {}).get("parts", []):
			for member: Dictionary in part.members: found.append(str(member.node.name))
		return found
	_check("the canopy moves its frame and glass, the tailhook its hook", mechanisms.size() == 2
		and names.call("canopy") == ["canopy_frame", "canopy_glass"] and names.call("tailhook") == ["core_details"], str(mechanisms.keys()))
	if mechanisms.size() != 2: return
	var glass: Dictionary = mechanisms.canopy.parts[0].members[1]
	Importer.apply_mechanisms(model, {"canopy": 0.5})
	var half: Vector3 = glass.node.transform.origin - glass.rest.origin
	Importer.apply_mechanisms(model, {"canopy": 1.0})
	var slide: Vector3 = glass.node.transform.origin - glass.rest.origin
	# R59: 0.70 m aft and 0.0385 m down at full size, 1:4.5.
	_check("the open canopy slides 0.1558 m aft and slightly down without turning, half way at 0.5",
		absf(slide.length() - Vector2(0.70, 0.0385).length() / 4.5) < 1e-6 and slide.z > 0.15 and slide.y < 0.0
		and glass.node.basis.is_equal_approx(glass.rest.basis) and half.is_equal_approx(slide * 0.5), str(slide))
	var hook: MeshInstance3D = mechanisms.tailhook.parts[0].members[0].node
	var pivot: Vector3 = mechanisms.tailhook.parts[0].pivot
	var tip := _extreme(model.root, hook, Vector3(0, 0, 1))
	Importer.apply_mechanisms(model, {"tailhook": 1.0})
	var lowered: Vector3 = hook.transform * (mechanisms.tailhook.parts[0].members[0].rest.affine_inverse() * tip)
	var angle := rad_to_deg((tip - pivot).angle_to(lowered - pivot))
	_check("the lowered tailhook turns 45 deg about R59's pivot and its tip goes down", absf(angle - 45.0) < 1e-3 and lowered.y < tip.y - 0.1,
		"%.4f deg, tip %.3f -> %.3f m" % [angle, tip.y, lowered.y])
	var part: Dictionary = mechanisms.tailhook.parts[0]
	var floor_y: float = part.ground_point.y - 0.15
	var on_floor := Importer.ground_limited_fraction(model, "tailhook", 1.0, Transform3D.IDENTITY, func(_x: float, _z: float) -> float: return floor_y)
	var resting: Vector3 = Importer._part_motion(part, on_floor) * part.ground_point
	var in_air := Importer.ground_limited_fraction(model, "tailhook", 1.0, Transform3D.IDENTITY, func(_x: float, _z: float) -> float: return -10.0)
	var unknown := Importer.ground_limited_fraction(model, "tailhook", 1.0, Transform3D.IDENTITY, func(_x: float, _z: float) -> float: return NAN)
	_check("a lowered hook stops with its tip on the ground, and lowers fully over open or unknown ground",
		on_floor > 0.0 and on_floor < 1.0 and absf(resting.y - floor_y) < 1e-5 and in_air == 1.0 and unknown == 1.0,
		"state %.3f, tip %.6f m above the ground" % [on_floor, resting.y - floor_y])
	Importer.apply_mechanisms(model, {"canopy": 0.0, "tailhook": 0.0})
	var at_rest: bool = mechanisms.values().all(func(m: Dictionary) -> bool:
		return m.parts.all(func(p: Dictionary) -> bool: return p.members.all(func(e: Dictionary) -> bool: return e.node.transform == e.rest)))
	_check("closing and raising restore every part exactly to its delivered rest", at_rest)
	var renamed: Dictionary = manifest.duplicate(true)
	renamed.construction.mechanisms[0].key = "parachute"
	var refused := Manifest.validate(renamed)
	_check("the contract refuses an unknown mechanism key", not refused.ok and str(refused.errors).contains("mechanism key"), str(refused.errors))
	var data: Dictionary = Geometry.DATA.duplicate(true)
	data.mechanisms.tailhook.parts[0].members = ["aileron_left_hinge"]
	var built := Importer.build_scene((load(GLB_PATH) as PackedScene).instantiate(), data, manifest)
	_check("the builder refuses a mechanism member that a control hinge already moves", not built.ok
		and str(built.errors).contains("already moves with a hinge"), str(built.errors))


## The imported scene is the frozen delivery: bytes, node set, sections and the counts the author reported.
func _asset() -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(GLB_PATH))
	_check("runtime GLB is the accepted g2.2 aircraft.glb", context.finish().hex_encode() == EXPECTED_SHA256 and Geometry.DATA.inputs.glb_sha256 == EXPECTED_SHA256)
	var scene: Node3D = (load(GLB_PATH) as PackedScene).instantiate()
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var surfaces := 0
	var untagged := []
	var invalid := []
	for mesh: MeshInstance3D in meshes:
		surfaces += mesh.mesh.get_surface_count()
		for s in mesh.mesh.get_surface_count():
			triangles += int(mesh.mesh.surface_get_array_index_len(s) / 3)
		var section := str((mesh.get_meta("extras", {}) as Dictionary).get("openrc_section", "")) if mesh.has_meta("extras") else ""
		if section.is_empty(): untagged.append(mesh.name)
		elif not SECTIONS.has(section): invalid.append(mesh.name)
	_check("46 meshes, 57 surfaces, 337,664 triangles as delivered", meshes.size() == 46 and surfaces == 57 and triangles == 337664, "%d meshes, %d surfaces, %d triangles" % [meshes.size(), surfaces, triangles])
	_check("every mesh carries a valid openrc_section", untagged.is_empty() and invalid.is_empty(), "untagged %s, invalid %s" % [str(untagged), str(invalid)])
	var worst := 0.0
	for name: String in Geometry.DATA.articulations:
		var record: Dictionary = Geometry.DATA.articulations[name]
		var node := scene.find_child(name, true, false) as Node3D
		if node == null:
			worst = INF
			continue
		worst = maxf(worst, node.position.distance_to(_v(record.rest_translation)))
	_check("all eleven articulation rests match the compiled geometry", worst < 2e-5, "%.7f m" % worst)
	scene.free()


func _built_model() -> void:
	var described := Registry.describe(ID)
	_check("registry accepts the checked-in manifest", described.ok, str(described.get("errors", [])))
	if not described.ok: return
	var built := Importer.build_checked(described.manifest)
	_check("shared importer builds the scene", built.ok, str(built.errors))
	if not built.ok: return
	var model: Dictionary = built.model
	var root: Node3D = model.root
	var derived := Registry.validate_derived(described.manifest, model)
	_check("registry accepts the built model (hinges, rotor, gear, asset, crash sections)", derived.ok, str(derived.get("errors", [])))
	_check("ten control hinges, three flap panels per side", model.hinges.size() == 10)
	var aft := Vector3(0, 0, 1)
	for role: String in ["aileron_left", "aileron_right", "elevator", "rudder"]:
		var surface: MeshInstance3D = model.hinges[role].node.get_child(0)
		var before := _extreme(root, surface, aft)
		Importer.apply_surfaces(model, {role: 10.0})
		var moved := _extreme(root, surface, aft) - before
		Importer.apply_surfaces(model, {})
		var sense := moved.x if role == "rudder" else moved.y
		_check("%s +10 app degrees moves the trailing edge %s and returns" % [role, "right" if role == "rudder" else "up"],
			sense > 0.005 and _extreme(root, surface, aft).is_equal_approx(before), "%.4f m" % sense)
	var angle := func() -> float: return rad_to_deg(model.hinges.flap_left_1.rest.y.angle_to(model.hinges.flap_left_1.node.basis.y))
	Importer.set_flaps(model, 30.0)
	var at_30: float = angle.call()
	var drops := []
	for key: String in ["flap_left_1", "flap_left_2", "flap_left_3", "flap_right_1", "flap_right_2", "flap_right_3"]:
		var mesh: MeshInstance3D = model.hinges[key].node.get_child(0)
		drops.append(Importer.relative(root, mesh).origin.y)
	Importer.set_flaps(model, 80.0)
	var at_80: float = angle.call()
	Importer.set_flaps(model, 0.0)
	_check("flap hinges turn 30.000 deg for 30 and clamp at the 50 deg envelope", absf(at_30 - 30.0) < 0.01 and absf(at_80 - 50.0) < 0.01, "%.3f, %.3f" % [at_30, at_80])
	# The hinge ranges are the author's clearance sweep (g1.3; g2.1 keeps the same ranges, its sampled sweep of 138 control
	# poses is clear); the flown throws must stay inside them.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var throws: Dictionary = data.controls.max_throw
	var outside := []
	for role: String in ["aileron_left", "aileron_right", "elevator", "rudder", "flap_left_1"]:
		var limit: float = float(data.flaps.max_angle_deg.value) if role.begins_with("flap") else float(throws[role.get_slice("_", 0)].value)
		var low: float = 0.0 if role.begins_with("flap") else -limit
		if low < float(model.hinges[role].range_deg[0]) or limit > float(model.hinges[role].range_deg[1]):
			outside.append(role)
	_check("full throws (13.5, 11.2, 25.9 deg) and 30 deg flaps lie inside the swept clearance envelopes", outside.is_empty(), str(outside))
	_fold_checks(model)
	_mechanism_checks(model, described.manifest)
	var rig: Dictionary = model.gear_retraction
	var worst := 0.0
	for extension: float in [0.0, 0.5, 1.0]:
		Rig.apply(rig, extension)
		for role: String in ["left", "right", "tail"]:
			var path: Array = Geometry.DATA.gear.wheels[role].center_model
			worst = maxf(worst, Importer.relative(root, model.gear[role]).origin.distance_to(_v(path[int(round(extension * (path.size() - 1)))])))
	_check("wheel centres follow the sampled GearRetract stowed, in transit and down", worst < 1e-4, "%.7f m" % worst)
	Rig.apply(rig, 1.0)
	var down_y := Importer.relative(root, model.gear.left).origin.y
	var slider: Node3D = rig.compression.left
	slider.position = rig.rest.left.origin + Importer.relative(root, slider.get_parent()).basis.inverse() * Vector3.UP * 0.01
	_check("0.01 m of oleo compression raises the main wheel 0.01 m from the down sample", absf(Importer.relative(root, model.gear.left).origin.y - down_y - 0.01) < 1e-5)
	root.free()


## The catalog presentation: physical propeller size, exhaust anchor, paint slots and contacts against the physics data.
func _presentation() -> void:
	var airplane := AirplaneBuilder.build(ID)
	_check("render/airplane.gd builds the catalog aircraft", not airplane.is_empty())
	if airplane.is_empty(): return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var physical: float = float(data.propulsion.propeller.diameter.value)
	_check("the visual propeller is drawn at the physical 30 in diameter", absf(float(airplane.get("propeller_diameter_m", 0.0)) - physical) < 1e-9
		and is_equal_approx(airplane.propeller.scale.x, physical / float(Geometry.DATA.thrust.propeller_diameter.value)), "%.4f m" % physical)
	var exhausts: Array = airplane.get("exhausts", [])
	_check("one gasoline exhaust anchor at the left middle stack", exhausts.size() == 1 and str(exhausts[0].get("kind", "")) == "glow_prop"
		and (exhausts[0].position as Vector3).distance_to(_v(Geometry.DATA.exhausts[0].position)) < 1e-9)
	var slots: Dictionary = airplane.get("customization_bindings", {})
	_check("four paint slots, one registration slot and the smoke slots resolve", slots.get("paint_slots", []).size() == 4
		and slots.get("marking_slots", []).size() == 1 and slots.get("smoke_slots", []).size() >= 4, str(slots.keys()))
	for contact: Dictionary in data.landing_gear.contacts:
		var role: String = str(contact.name).trim_prefix("main_")
		var p: Array = Geometry.DATA.gear.wheels[role].contact_model[-1]
		var gap := Vector3(p[2], p[0], p[1]).distance_to(_v(contact.position.value))
		_check("%s physics contact is the rendered wheel bottom (F4U-08)" % role, gap < 2e-6, "%.7f m" % gap)
	_contact_sweep(airplane)
	_crash_contacts(airplane)
	airplane.root.free()


## F4U-08-R1: independently measure the imported tyre at all 101 samples and
## their midpoints. A stowed main wheel is horizontal: subtracting its radius
## from its centre used to put the contact 64 mm below the actual tyre.
func _contact_sweep(airplane: Dictionary) -> void:
	var loaded := AircraftData.load_file(DATA_PATH)
	_check("contact sweep loads the production physics", loaded.ok)
	if not loaded.ok: return
	var model: Dictionary = loaded.model
	var gear: Dictionary = model.landing_gear
	for index in gear.contacts.size():
		var role := str(gear.contacts[index].name).trim_prefix("main_")
		var mesh := airplane.root.find_child("gear_wheel_" + role, true, false) as MeshInstance3D
		_check(role + " contact sweep finds the imported tyre", mesh != null)
		if mesh == null: continue
		var worst := 0.0
		var clear_above := true
		var detects_touch := true
		for step in 201:
			var extension := float(step) / 200.0
			Rig.apply(airplane.gear_retraction, extension)
			var bottom := _extreme(airplane.root, mesh, Vector3.DOWN).y
			var posed := GearPhysics.pose(gear, extension)
			var contact: Dictionary = posed.contacts[index]
			var physics_y: float = model.cg_le[2] - contact.position[2]
			worst = maxf(worst, absf(bottom - physics_y))
			if step == 200: continue # downlocked suspension admits compression
			# Isolate this support from the hull and other wheels. Test the real
			# collision law 2 mm on each side of the measured mesh bottom.
			var isolated := posed.duplicate()
			isolated.contacts = [contact]
			var state := PackedFloat64Array()
			state.resize(RB.SIZE)
			state[RB.ATT] = 1.0
			state[RB.POS + 2] = bottom - model.cg_le[2] - 0.002
			clear_above = clear_above and not Ground.collapsed(state, isolated)
			state[RB.POS + 2] += 0.004
			detects_touch = detects_touch and Ground.collapsed(state, isolated)
		_check(role + " contact follows tyre bottom across 201 retract poses", worst < 0.001, "worst %.4f mm" % (1000.0 * worst))
		_check(role + " unlocked gear does not hit before its tyre reaches ground", clear_above)
		_check(role + " unlocked tyre contact still triggers the collision law", detects_touch)
	Rig.apply(airplane.gear_retraction, 1.0)


## F4U-11-R1: check the authored probes against imported vertices and the actual
## contact/event pipeline. Local support checks isolate a struck part; the three
## cardinal crash cases below use the whole hull, including the propeller probes.
func _crash_contacts(airplane: Dictionary) -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var model: Dictionary = AircraftData.load_file(DATA_PATH).model
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../assets/aircraft/f4u-corsair-250/crash-geometry.json"))
	var bindings := ContactContract.describe(model, true)
	_check("crash contacts bind to stable physical identities", bindings.ok)
	for probe: Dictionary in source.probes:
		var index: int = raw.crash_hull_ids.find(probe.id)
		_check(str(probe.id) + " exists with its impact label", index >= 0 and raw.crash_hull_components[index] == probe.component)
		if index < 0: continue
		var le: Array = raw.crash_hull.value[index]
		var point := Vector3(le[1], le[2], le[0])
		var direction := Vector3(probe.direction_le[1], probe.direction_le[2], probe.direction_le[0]).normalized()
		var mesh := airplane.root.find_child(str(probe.mesh), true, false) as MeshInstance3D
		var nearest := INF
		var transform := Importer.relative(airplane.root, mesh)
		for surface in mesh.mesh.get_surface_count():
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				nearest = minf(nearest, point.distance_to(transform * vertex))
		_check(str(probe.id) + " lies on its rendered structure", nearest < 2e-6, "%.6f mm" % (nearest * 1000.0))
		var extreme := _extreme(airplane.root, mesh, direction)
		_check(str(probe.id) + " reaches the measured support plane", absf((extreme - point).dot(direction)) < 2e-6)
		var body_direction := PackedFloat64Array([-probe.direction_le[0], probe.direction_le[1], -probe.direction_le[2]])
		body_direction = Math64.scale(body_direction, 1.0 / Math64.norm(body_direction))
		var attitude := Math64.q_from_euler(0.0, -asin(body_direction[0]), atan2(body_direction[1], body_direction[2]))
		var body: PackedFloat64Array = model.crash_hull.slice(3 * index, 3 * index + 3)
		var before := RB.make_state(Math64.v3(0, 0, -Math64.q_rotate(attitude, body)[2] - 0.001),
			Math64.q_rotate(Math64.q_conj(attitude), Math64.v3(0, 0, 20)), attitude, Math64.v3(0, 0, 0))
		var after := before.duplicate()
		after[RB.POS + 2] += 0.002
		var isolated := Hull.prepare(body, model.mass_kg, model.inertia)
		_check(str(probe.id) + " stays clear above its surface", Hull.terminal(before, before, isolated).index == -1)
		var hit := Hull.terminal(before, after, isolated)
		_check(str(probe.id) + " detects a hard crossing", hit.index == 0 and hit.rule == "impact")
		var snapshot := Impact.hull_point(after, 1, model.crash_hull, index, before, "impact")
		var event := ContactEvents.impact_event(snapshot, bindings, "normal")
		_check(str(probe.id) + " survives impact serialization", event.get("contact_id") == probe.id)
	var prepared := Hull.prepare(model.crash_hull, model.mass_kg, model.inertia)
	for probe_id: String in ["probe_wing_left_tip", "probe_wing_right_tip", "probe_tail_cone"]:
		var index: int = raw.crash_hull_ids.find(probe_id)
		if index < 0: continue
		var attitude := Math64.q_from_euler(0.0, PI / 2 if probe_id == "probe_tail_cone" else 0.0,
			-PI / 2 if probe_id == "probe_wing_left_tip" else PI / 2 if probe_id == "probe_wing_right_tip" else 0.0)
		var body: PackedFloat64Array = model.crash_hull.slice(3 * index, 3 * index + 3)
		var before := RB.make_state(Math64.v3(0, 0, -Math64.q_rotate(attitude, body)[2] - 0.001),
			Math64.q_rotate(Math64.q_conj(attitude), Math64.v3(0, 0, 20)), attitude, Math64.v3(0, 0, 0))
		var after := before.duplicate()
		after[RB.POS + 2] += 0.002
		_check(probe_id + " wins the whole-aircraft impact", Hull.terminal(before, after, prepared).index == index)


## F4U-11: the wreck twin exposes all ten sections; a C3 hit naming one wing releases only that outer panel (with its
## aileron and outer flap, which share its section), a nose hit releases propeller, engine and canopy.
func _crash_release() -> void:
	var airplane := AirplaneBuilder.build(ID)
	var model_root: Node3D = airplane.root
	root.add_child(model_root)
	await process_frame
	model_root.visible = false
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	_check("the wreck prepares a mesh twin", wreck.prepare(model_root))
	var groups: Array = wreck.get_stats().fragment_groups
	_check("the wreck exposes all ten crash sections", SECTIONS.all(func(section: String) -> bool: return groups.has(section)), str(groups))
	var pose := Transform3D(Basis.IDENTITY, Vector3(0.0, 20.0, 0.0))
	var cases := {"left_wing": ["wing_left"], "right_wing": ["wing_right"], "spinner": ["propeller", "engine", "canopy"],
		"left_wing_root": ["wing_center", "wing_left"], "right_wing_root": ["wing_center", "wing_right"]}
	for component: String in cases:
		wreck.start(pose, Vector3(0.0, -10.0, -1.0), Vector3(0.3, 0.5, -0.2),
			{"class": "C3", "mass_kg": 21.5, "cg_model": Vector3(0.0, -0.06, 0.15), "normal_speed_mps": 12.0, "component": component, "seed": 7})
		var detached := []
		for group: Dictionary in wreck._groups:
			if bool(group.get("detached", false)):
				detached.append(String(group.kind))
		detached.sort()
		var expected: Array = cases[component].duplicate()
		expected.sort()
		_check("a C3 %s hit releases exactly %s" % [component, str(expected)], detached == expected, str(detached))
		wreck.reset()
	wreck.free()
	model_root.free()
	await process_frame
