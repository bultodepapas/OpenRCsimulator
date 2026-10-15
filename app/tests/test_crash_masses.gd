## CR-09d1: wreck sections carry the aircraft's real inventory mass and centre of mass instead of fixed shares.
extends SceneTree

const WreckController = preload("res://render/crash/wreck.gd")
const Director = preload("res://render/crash/director.gd")
const AirplaneBuilder = preload("res://render/airplane.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Frames = preload("res://render/frames.gd")
const MainScene = preload("res://main.tscn")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_units()
	await _floor()
	await _aircraft("jensen-das-ugly-stik-60", "engine O.S. MAX-61FX", "engine", ["nose gear and 2.75 in wheel", "main gear and 3 in wheels"])
	await _aircraft("turbo-lumber-evolution", "800 Kv motor", "engine", ["main gear and wheels", "tailwheel and fork"])
	await _production()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))


## The production crash path hands the inventory to the wreck: a real crash through main.tscn uses inventory masses.
func _production() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("accident_reports_enabled", false) # Wreck mass fixture has no economic archive.
	main.set("aircraft_id", "jensen-das-ugly-stik-60")
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var director: Variant = main.get("_crash_director")
	session.input_enabled = false
	session.set_physics_process(false)
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest := -INF
	for i in range(0, hull.size(), 3):
		deepest = maxf(deepest, M.q_rotate(RB._att(s), hull.slice(i, i + 3))[2])
	s[RB.POS + 2] = -deepest + 0.001
	var v_body := M.q_rotate(M.q_conj(RB._att(s)), PackedFloat64Array([0.0, 0.0, 20.0]))
	for k in 3:
		s[RB.VEL + k] = v_body[k]
		s[RB.RATE + k] = 0.0
	var before := s.duplicate()
	before[RB.POS + 2] -= 0.05
	session.sim.state = s
	session.sim.previous = before
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	director.update(session.sim.dt())
	_check("production crash hands the inventory to the wreck", director.active and (director.report.get("inventory_boxes", []) as Array).size() == 20)
	_check("production wreck uses inventory section masses", not director.wreck._section_masses.is_empty())
	main.queue_free()
	await process_frame
	await process_frame


func _units() -> void:
	var bounds := AABB(Vector3(0, 0, 0), Vector3(1, 1, 1))
	_check("a box half inside a section puts half its mass there", is_equal_approx(WreckController._overlap_fraction(Vector3(1.0, 0.5, 0.5), Vector3(1, 0.2, 0.2), bounds), 0.5))
	_check("a box fully inside puts all of it there", is_equal_approx(WreckController._overlap_fraction(Vector3(0.5, 0.5, 0.5), Vector3(0.2, 0.2, 0.2), bounds), 1.0))
	_check("a point item counts when inside, not when outside", WreckController._overlap_fraction(Vector3(0.5, 0.5, 0.5), Vector3.ZERO, bounds) == 1.0
		and WreckController._overlap_fraction(Vector3(1.5, 0.5, 0.5), Vector3.ZERO, bounds) == 0.0)
	_check("a thin skin's region is thickened, a bulky part's barely", is_equal_approx(WreckController._inventory_region(AABB(Vector3.ZERO, Vector3(1, 0.002, 1))).size.y, WreckController.INVENTORY_MIN_THICKNESS_M)
		and is_equal_approx(WreckController._inventory_region(AABB(Vector3.ZERO, Vector3(1, 0.5, 1))).size.y, 0.5 + 2.0 * WreckController.INVENTORY_MARGIN_M))


## A section that no inventory item reaches still gets the floor mass, taken from the core: the total never changes.
func _floor() -> void:
	var airplane := Node3D.new()
	airplane.name = "airplane"
	var body := MeshInstance3D.new()
	body.name = "airframe"
	body.mesh = BoxMesh.new()
	airplane.add_child(body)
	var tail := Node3D.new()
	tail.name = "tail_frame"
	tail.position = Vector3(0, 0, 3.0)
	var stab := MeshInstance3D.new()
	stab.mesh = BoxMesh.new()
	tail.add_child(stab)
	airplane.add_child(tail)
	root.add_child(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(airplane)
	wreck.start(Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), Vector3(0, -10, 0), Vector3.ZERO, {"class": 4, "mass_kg": 1.0, "seed": 1,
		"inventory_boxes": [{mass = 1.0, center = Vector3.ZERO, size = Vector3(0.2, 0.2, 0.2)}]})
	wreck._process(0.5)
	var masses := {}
	var total := 0.0
	for i in wreck._groups.size():
		if wreck._bodies[i].visible:
			masses[String(wreck._groups[i].kind)] = wreck._bodies[i].mass
			total += wreck._bodies[i].mass
	_check("a section without items gets the floor mass from the core", is_equal_approx(float(masses.get("horizontal_tail", 0.0)), WreckController.MIN_SECTION_MASS_KG)
		and is_equal_approx(total, 1.0), str(masses))
	wreck.free()
	airplane.free()


func _aircraft(id: String, engine_item: String, engine_kind: String, gear_items: Array = []) -> void:
	var path := str(Catalog.entry(id).data)
	var model: Dictionary = AircraftData.load_file(path).model
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var datum := AirplaneBuilder.datum(id)
	var boxes: Array = []
	var engine_mass := 0.0
	var gear_mass := 0.0
	for item: Dictionary in raw.inventory:
		boxes.append(Director.inventory_box(item, datum))
		if item.name == engine_item:
			engine_mass = float(item.mass.value)
		if gear_items.has(item.name):
			gear_mass += float(item.mass.value)
	var mass := float(model.mass_kg)
	var cg_model := Frames.cg_in_model_frame(model.cg_le, datum.x, datum.y)
	var airplane: Node3D = AirplaneBuilder.build(id).root
	root.add_child(airplane)
	var wreck: Variant = WreckController.new()
	root.add_child(wreck)
	await process_frame
	wreck.set_process(false)
	wreck.prepare(airplane)
	var pose := Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
	# C2 without a struck part: everything stays in the core, whose centre of mass must be the aircraft's own CG.
	wreck.start(pose, Vector3(0, -5, -5), Vector3.ZERO, {"class": 2, "component": "belly", "mass_kg": mass, "seed": 1, "inventory_boxes": boxes, "cg_model": cg_model})
	var core: RigidBody3D = wreck._core_body
	var com_model: Vector3 = Vector3(wreck._groups[0].center) + core.center_of_mass
	_check("%s intact wreck weighs the aircraft" % id, absf(core.mass - mass) < 1e-6, "%.4f vs %.4f" % [core.mass, mass])
	_check("%s intact wreck's centre of mass is the aircraft CG" % id, com_model.distance_to(cg_model) < 0.01,
		"%s vs %s (%.1f mm)" % [str(com_model), str(cg_model), com_model.distance_to(cg_model) * 1000.0])
	_check("%s uses a custom centre of mass" % id, core.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	wreck.reset()
	# C4: every section flies with its own inventory mass.
	wreck.start(pose, Vector3(0, -15, -10), Vector3.ZERO, {"class": 4, "component": "nose", "mass_kg": mass, "seed": 2, "inventory_boxes": boxes, "cg_model": cg_model})
	wreck._process(0.5)
	var masses := {}
	var total := 0.0
	for i in wreck._groups.size():
		var body: RigidBody3D = wreck._bodies[i]
		if body.visible:
			masses[String(wreck._groups[i].kind)] = body.mass
			total += body.mass
	print("     %s section masses: %s" % [id, str(masses)])
	_check("%s destroyed wreck conserves mass" % id, absf(total - mass) < 1e-6, "%.6f vs %.6f" % [total, mass])
	_check("%s wing halves weigh the same" % id, masses.has("wing_left") and absf(float(masses.wing_left) - float(masses.wing_right)) < 0.02 * mass,
		"%s / %s" % [str(masses.get("wing_left")), str(masses.get("wing_right"))])
	_check("%s wing halves carry real wing mass" % id, float(masses.get("wing_left", 0.0)) > 0.1)
	_check("%s gear section does not swallow tank and battery" % id, float(masses.get("gear", 0.0)) <= 1.3 * gear_mass,
		"%.3f vs gear items %.3f" % [float(masses.get("gear", 0.0)), gear_mass])
	_check("%s %s section carries the engine" % [id, engine_kind], float(masses.get(engine_kind, 0.0)) >= 0.9 * engine_mass,
		"%.3f vs engine %.3f" % [float(masses.get(engine_kind, 0.0)), engine_mass])
	wreck.reset()
	_check("%s reset restores automatic centre of mass" % id, wreck._bodies.all(func(b: RigidBody3D) -> bool: return b.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_AUTO))
	# Without inventory data the fixed shares remain.
	wreck.start(pose, Vector3(0, -15, -10), Vector3.ZERO, {"class": 4, "component": "nose", "mass_kg": mass, "seed": 2})
	wreck._process(0.5)
	var legacy := 0.0
	for body: RigidBody3D in wreck._bodies:
		if body.visible:
			legacy += body.mass
	_check("%s without inventory keeps the fixed shares and conserves mass" % id, absf(legacy - mass) < 0.05 * mass and wreck._section_masses.is_empty())
	wreck.free()
	airplane.free()
