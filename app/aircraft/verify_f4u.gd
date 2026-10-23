# F4U-12 contract checks for the F4U Corsair 1/4.5 imported model (headless).
# Proves that the scene Godot imports is the frozen g1.3 asset (hash, counts, section tags, pivots against the delivered
# metadata), that the production registry builds it, and that surfaces, flaps, propeller, sampled gear, oleo compression,
# exhaust anchor and paint slots behave as the session expects. Run: godot --headless --path app --script res://aircraft/verify_f4u.gd
extends SceneTree

const Registry := preload("res://aircraft/model_registry.gd")
const Importer := preload("res://aircraft/imported_model.gd")
const Rig := preload("res://aircraft/retractable_model.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const Geometry := preload("res://aircraft/f4u_corsair_geometry.gd")
const WreckController := preload("res://render/crash/wreck.gd")
const GLB_PATH := "res://assets/aircraft/f4u-corsair-250/f4u_corsair.glb"
const DATA_PATH := "res://data/aircraft/f4u_corsair_250.json"
const ID := "f4u-corsair-250"
const EXPECTED_SHA256 := "c69151b3c96c53ff957d046c53600204598be854c10850e4bdda22ab333f464e"
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


## The imported scene is the frozen delivery: bytes, node set, sections and the counts the author reported.
func _asset() -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(GLB_PATH))
	_check("runtime GLB is the accepted g1.3 aircraft.glb", context.finish().hex_encode() == EXPECTED_SHA256 and Geometry.DATA.inputs.glb_sha256 == EXPECTED_SHA256)
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
	_check("44 meshes, 54 surfaces, 90,861 triangles as delivered", meshes.size() == 44 and surfaces == 54 and triangles == 90861, "%d meshes, %d surfaces, %d triangles" % [meshes.size(), surfaces, triangles])
	_check("every mesh carries a valid openrc_section", untagged.is_empty() and invalid.is_empty(), "untagged %s, invalid %s" % [str(untagged), str(invalid)])
	var worst := 0.0
	for name: String in Geometry.DATA.articulations:
		var record: Dictionary = Geometry.DATA.articulations[name]
		var node := scene.find_child(name, true, false) as Node3D
		if node == null:
			worst = INF
			continue
		worst = maxf(worst, node.position.distance_to(_v(record.rest_translation)))
	_check("all eleven articulation rests match the compiled geometry", worst < 2e-5, "%.2e m" % worst)
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
	var rig: Dictionary = model.gear_retraction
	var worst := 0.0
	for extension: float in [0.0, 0.5, 1.0]:
		Rig.apply(rig, extension)
		for role: String in ["left", "right", "tail"]:
			var path: Array = Geometry.DATA.gear.wheels[role].center_model
			worst = maxf(worst, Importer.relative(root, model.gear[role]).origin.distance_to(_v(path[int(round(extension * (path.size() - 1)))])))
	_check("wheel centres follow the sampled GearRetract stowed, in transit and down", worst < 1e-4, "%.2e m" % worst)
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
		_check("%s physics contact is the rendered wheel bottom (F4U-08)" % role, gap < 2e-6, "%.2e m" % gap)
	airplane.root.free()


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
	var cases := {"left_wing": ["wing_left"], "right_wing": ["wing_right"], "spinner": ["propeller", "engine", "canopy"]}
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
