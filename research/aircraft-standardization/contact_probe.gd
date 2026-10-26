extends SceneTree
## AS-13: before/after fingerprints through real contact routes; no golden files are rewritten.
const Flight := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const World := preload("res://scenery/collision_world.gd")
const Lake := preload("res://data/lake_loader.gd")

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("usage: contact_probe.gd -- <output.json>")
		quit(2)
		return
	var cases: Array[Dictionary] = []
	for fixture: String in ["legacy_brush", "soft_brush", "nose_impact", "belly_slide", "scenery_impulse", "scenery_terminal", "water"]:
		cases.append(_exercise(fixture))
	var ok := true
	for row: Dictionary in cases:
		ok = ok and row.ok
		print("AS contact ", row.fixture, " ", "PASS" if row.ok else "FAIL")
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	if out == null:
		quit(2)
		return
	out.store_string(JSON.stringify({format = "openrc-as-contact-probe v1", ok = ok,
		godot = Engine.get_version_info().string, hz = Engine.physics_ticks_per_second, cases = cases}, "\t") + "\n")
	out.close()
	quit(0 if ok else 1)

func _exercise(fixture: String) -> Dictionary:
	var f := Flight.new()
	f.soft_hull_contacts = fixture in ["soft_brush", "nose_impact", "belly_slide"]
	if fixture == "belly_slide":
		f.setup("res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx")
	else:
		f.setup()
	f.input_enabled = false
	f.crash_auto_restart = false
	var body := PackedFloat64Array()
	var ticks := 72
	match fixture:
		"legacy_brush", "soft_brush": body = _above(f, 0.01, M.q_from_euler(0, 0, deg_to_rad(40)), M.v3(15, 0, 0.5))
		"nose_impact": body = _above(f, 0.01, M.q_from_euler(0, -PI / 2.0, 0), M.v3(0, 0, 10))
		"belly_slide":
			body = _above(f, 0.01, M.q_from_euler(0, 0, 0), M.v3(12, 0, 1))
			ticks = 1440
		_:
			# Controlled sweep, retaining actual aircraft probes; propulsion is outside this fixture's scope.
			f.sim.continuous = PackedFloat64Array()
			for field: String in ["step_policy", "stage", "block_loads", "block_derivative",
				"stage_rotor_momentum", "block_aux"]:
				f.sim.model.set(field, Callable())
			f.sim.gravity = 0.0
			f.sim.model.loads = func(_s: PackedFloat64Array, _t: float) -> PackedFloat64Array: return PackedFloat64Array([0, 0, 0, 0, 0, 0])
			f.sim.model.pre_tick = func(aux: PackedFloat64Array, _inputs: PackedFloat64Array, _dt: float) -> PackedFloat64Array: return aux
			f.sim.model.rotor_momentum = func(_aux: PackedFloat64Array) -> PackedFloat64Array: return PackedFloat64Array()
			if fixture == "water":
				f.set_lake_context(Lake.load_from("res://data/fields/lake.json").lake)
				body = RB.make_state(M.v3(110, 125, -1), M.v3(0, 0, 480), M.quat(1, 0, 0, 0), M.v3(0, 0, 0))
			else:
				f.set_collision_world(World.build({pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []},
					{groups = []}, {fixtures = [{id = "contact-parity", type = "flood", north = 5.0, east = 0.0, height = 8.0}]}).world)
				var nose := -INF
				for at in range(0, f.aircraft.model.crash_hull.size(), 3): nose = maxf(nose, f.aircraft.model.crash_hull[at])
				body = RB.make_state(M.v3(4.9 - nose, 0, -4), M.v3(8 if fixture == "scenery_impulse" else 2400, 0, 0), M.quat(1, 0, 0, 0), M.v3(0, 0, 0))
				ticks = 8
	var ok: bool = f.is_flyable() and f.sim.reset(body)
	f.sim.set_paused(false)
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	var contact_seen := false
	var scenery_seen := false
	var response := ""
	for tick in ticks:
		f._physics_process(f.sim.dt())
		contact_seen = contact_seen or not f.soft_contacts.is_empty()
		if f.crash.is_empty(): f.sim.step()
		var scene_event: Variant = f.last_scenery_event()
		if scene_event != null:
			scenery_seen = true
			response = scene_event.response_status
		hash.update(var_to_bytes([f.sim.state, f.sim.previous, f.sim.continuous, f.sim.aux,
			f.sim.modes, f.sim.inputs, f.sim.last_loads, f.sim.tick, f.prop_strike]))
		ok = ok and f.sim.fault_reason.is_empty()
		if not ok or not f.crash.is_empty(): break
	var trigger: String = "" if f.crash.is_empty() else f.crash.impact.trigger
	if fixture in ["legacy_brush", "nose_impact"]: ok = ok and trigger == "hull_contact"
	if fixture in ["soft_brush", "belly_slide"]: ok = ok and contact_seen and trigger.is_empty()
	if fixture == "scenery_impulse": ok = ok and scenery_seen and response == "dissipative_impulse" and trigger.is_empty()
	if fixture == "scenery_terminal": ok = ok and trigger == "scenery"
	if fixture == "water": ok = ok and trigger == "water" and not f.engine_running
	var result := {fixture = fixture, ok = ok, tick = f.sim.tick, trigger = trigger,
		response = response, trajectory_sha256 = hash.finish().hex_encode()}
	f.free()
	return result

func _above(f: Node, clearance: float, attitude: PackedFloat64Array, velocity: PackedFloat64Array) -> PackedFloat64Array:
	var lowest := -INF
	var hull: PackedFloat64Array = f.aircraft.model.crash_hull
	for at in range(0, hull.size(), 3): lowest = maxf(lowest, M.q_rotate(attitude, hull.slice(at, at + 3))[2])
	return RB.make_state(M.v3(0, 0, -(lowest + clearance)), M.q_rotate(M.q_conj(attitude), velocity), attitude, M.v3(0, 0, 0))
