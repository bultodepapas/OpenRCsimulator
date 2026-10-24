# SC-HUM-03: field people head aim. Checks the mesh-derived head weight against the real LU-21 poses,
# the PeopleGaze behaviour (coupled pilots, step-and-hold spectators, limits, rear gate, range,
# determinism, reset) and the default scenery wiring. Native runs also read back the MultiMesh writes.
#   godot --headless --path . --script res://tests/test_field_people_gaze.gd
extends SceneTree

const Population = preload("res://scenery/population.gd")
const PeopleGaze = preload("res://scenery/people_gaze.gd")
const Scenery = preload("res://scenery/scenery.gd")
const Loader = preload("res://scenery/scenery_loader.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const ShaderClock = preload("res://render/shader_clock.gd")

const HUMAN_ASSETS := ["standing", "sitting", "pilot"]
const OPTS := {audio = false, birds = false, theme = "", quality = "high"}

var _failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	for asset: String in HUMAN_ASSETS:
		_test_head_mask(asset)
	_test_coupled_pilot()
	_test_step_and_hold()
	_test_rear_gate_and_range()
	_test_determinism_and_desync()
	_test_reset_and_repeats()
	_test_companion_pilots()
	_test_crash_glance()
	_test_default_scenery()
	print("people gaze: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures > 0 else 0)


func _vertices(part: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: Mesh = part.mesh
	for surface in mesh.get_surface_count():
		for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			out.append((part.transform as Transform3D) * v)
	return out


func _test_head_mask(asset: String) -> void:
	var source: Dictionary = Population._source(asset)
	_check("%s has a head rig" % asset, source.has("head"))
	if not source.has("head"):
		return
	var head: Dictionary = source.head
	var pivot: Vector3 = head.pivot
	_check("%s pivot below the eyes" % asset, pivot.y < float(head.eye_y) and pivot.y > float(head.eye_y) - 0.12, str(head))
	for part: Dictionary in source.parts:
		var name := str(part.name).to_lower()
		_check("%s part transform is identity rotation" % asset, (part.transform as Transform3D).basis.is_equal_approx(Basis.IDENTITY), name)
		var weights := PackedFloat32Array()
		for v: Vector3 in _vertices(part):
			weights.append(Population.head_weight(head, v))
		var full := 0
		var any := 0
		for w: float in weights:
			full += 1 if w > 0.99 else 0
			any += 1 if w > 0.0 else 0
		if "low-poly" in name or "eyebrow" in name:
			_check("%s %s turns rigidly" % [asset, name], full == weights.size(), "%d/%d" % [full, weights.size()])
		elif "short01" in name:
			_check("%s hair mostly rigid" % asset, full >= int(0.9 * weights.size()), "%d/%d" % [full, weights.size()])
		elif "shoes" in name or "transmitter" in name:
			_check("%s %s never moves" % [asset, name], any == 0, "%d moved" % any)
		elif "casualsuit" in name:
			# Only the collar may follow the neck.
			_check("%s clothing barely moves" % asset, any <= int(0.06 * weights.size()), "%d/%d" % [any, weights.size()])
		elif "male1591" in name:
			var low := 0
			for v: Vector3 in _vertices(part):
				if v.y < (head.band as Vector2).x and Population.head_weight(head, v) > 0.0:
					low += 1
			_check("%s body below the neck band is fixed" % asset, low == 0, "%d" % low)


func _person(role: String, seed: int, pivot := Vector3(0.0, 1.55, 0.0)) -> Dictionary:
	return {asset = "test", index = 0, seed = seed, id = "person_test", role = role, pivot = pivot,
		basis = Basis.IDENTITY, tint = Color.WHITE, custom = Color(0, 0, 0, 0)}


func _run(model: RefCounted, target_at: Callable, seconds: float, dt: float = 1.0 / 240.0, start: float = 0.0) -> Array:
	var series: Array = []
	var steps := int(round(seconds / dt))
	for i in steps:
		var t := start + float(i + 1) * dt
		model.update_to(t, target_at.call(t))
		series.append(model.head_angles(0))
	return series


func _test_coupled_pilot() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("pilot", 11)], {})
	var left := Vector3(-10.0, 1.55, -10.0) # 45° to the person's left (forward is -Z).
	model.reset(0.0, left)
	_run(model, func(_t: float) -> Vector3: return left, 3.0)
	var params := PeopleGaze._params("pilot", 11)
	var yaw: float = model.head_angles(0).x
	_check("pilot settles on a static target", absf(yaw - deg_to_rad(45.0) * float(params.mover)) < deg_to_rad(1.0), str(rad_to_deg(yaw)))
	# A crossing aircraft: the coupled head keeps up with modest lag.
	var crossing := func(t: float) -> Vector3: return Vector3(-60.0 + 20.0 * t, 20.0, -60.0)
	model.reset(0.0, crossing.call(0.0))
	var series := _run(model, crossing, 6.0)
	var t_end := 6.0
	var aim: Vector3 = crossing.call(t_end)
	var want := atan2(-aim.x, -aim.z) * float(params.mover)
	_check("pilot tracks a crossing aircraft", absf((series[-1] as Vector2).x - want) < deg_to_rad(6.0),
		"%.1f vs %.1f" % [rad_to_deg((series[-1] as Vector2).x), rad_to_deg(want)])
	var up := atan2(20.0 - 1.55, Vector2(aim.x, aim.z).length()) * float(params.mover)
	_check("pilot looks up at the aircraft", absf((series[-1] as Vector2).y - up) < deg_to_rad(3.0), str(rad_to_deg((series[-1] as Vector2).y)))
	var max_step := 0.0
	for i in range(1, series.size()):
		max_step = maxf(max_step, absf((series[i] as Vector2).x - (series[i - 1] as Vector2).x))
	_check("head rate stays limited", max_step <= PeopleGaze.RATE_LIMIT_RAD_S * (1.0 / 120.0) + 1.0e-9, str(max_step))


func _test_step_and_hold() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("spectator", 23)], {})
	var params := PeopleGaze._params("spectator", 23)
	var dz: float = params.dead_zone
	var rest := Vector2(params.rest_yaw, params.rest_pitch) * float(params.mover)
	# Inside the dead zone: the head holds still.
	var inside := Vector3(-tan(float(params.rest_yaw) + dz * 0.5) * 50.0, 1.55, -50.0)
	model.reset(0.0, inside)
	_run(model, func(_t: float) -> Vector3: return inside, 2.0)
	_check("spectator holds inside the dead zone", model.head_angles(0).distance_to(rest) < deg_to_rad(0.5), str(model.head_angles(0)))
	# Outside: the head turns, then holds when the target creeps by less than the dead zone.
	var outside := Vector3(-50.0, 1.55, -50.0)
	_run(model, func(_t: float) -> Vector3: return outside, 3.0, 1.0 / 240.0, 2.0)
	var settled: Vector2 = model.head_angles(0)
	_check("spectator turns once outside the dead zone", absf(settled.x - deg_to_rad(45.0) * float(params.mover)) < deg_to_rad(1.5), str(rad_to_deg(settled.x)))
	# A slow creep (no lead spike) by less than the dead zone, then held for a second.
	var creep := func(t: float) -> Vector3: return outside.rotated(Vector3.UP, -dz * 0.4 * clampf((t - 5.0) / 2.0, 0.0, 1.0))
	_run(model, creep, 3.0, 1.0 / 240.0, 5.0)
	_check("spectator holds after a small creep", model.head_angles(0).distance_to(settled) < deg_to_rad(0.5), str(model.head_angles(0)))


func _test_rear_gate_and_range() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("pilot", 5)], {})
	var params := PeopleGaze._params("pilot", 5)
	var rest := Vector2(params.rest_yaw, params.rest_pitch) * float(params.mover)
	var behind := Vector3(5.0, 1.55, 30.0)
	model.reset(0.0, Vector3(0.0, 1.55, -30.0))
	_run(model, func(_t: float) -> Vector3: return behind, 3.0)
	_check("a target behind returns the head to rest", model.head_angles(0).distance_to(rest) < deg_to_rad(1.0), str(model.head_angles(0)))
	# Beyond the yaw limit but inside the rear-gate margin: the head clamps at its limit.
	var side_yaw: float = float(params.yaw_limit) + PeopleGaze.REAR_GATE_MARGIN_RAD * 0.5
	var side := Vector3(-sin(side_yaw) * 30.0, 1.55, -cos(side_yaw) * 30.0)
	_run(model, func(_t: float) -> Vector3: return side, 3.0, 1.0 / 240.0, 3.0)
	_check("a target past the limit clamps the yaw", absf(model.head_angles(0).x - float(params.yaw_limit) * float(params.mover)) < deg_to_rad(1.0),
		str(rad_to_deg(model.head_angles(0).x)))
	var far := Vector3(0.0, 50.0, -2000.0)
	var spectator: RefCounted = PeopleGaze.new()
	spectator.configure([_person("spectator", 7)], {})
	var sp := PeopleGaze._params("spectator", 7)
	spectator.reset(0.0, far)
	_run(spectator, func(_t: float) -> Vector3: return far, 2.0)
	_check("spectators ignore a distant aircraft", spectator.head_angles(0).distance_to(Vector2(sp.rest_yaw, sp.rest_pitch) * float(sp.mover)) < deg_to_rad(0.5))
	var far_side := Vector3(-1000.0, 50.0, -2000.0)
	model.reset(0.0, far_side)
	_run(model, func(_t: float) -> Vector3: return far_side, 3.0)
	var far_yaw := atan2(1000.0, 2000.0) * float(params.mover)
	_check("pilots keep watching a distant aircraft", absf(model.head_angles(0).x - far_yaw) < deg_to_rad(1.0), str(rad_to_deg(model.head_angles(0).x)))


func _test_determinism_and_desync() -> void:
	var people := [_person("spectator", 101), _person("spectator", 202)]
	var path := func(t: float) -> Vector3: return Vector3(-80.0 + 25.0 * t, 15.0, -40.0)
	var a: RefCounted = PeopleGaze.new()
	var b: RefCounted = PeopleGaze.new()
	a.configure(people, {})
	b.configure(people, {})
	a.reset(0.0, path.call(0.0))
	b.reset(0.0, path.call(0.0))
	var same := true
	var differ := 0.0
	for i in 1440:
		var t := float(i + 1) / 240.0
		a.update_to(t, path.call(t))
		b.update_to(t, path.call(t))
		same = same and a.head_angles(0) == b.head_angles(0) and a.head_angles(1) == b.head_angles(1)
		differ = maxf(differ, absf(a.head_angles(0).x - a.head_angles(1).x))
	_check("identical inputs give identical head states", same)
	_check("two people do not move in sync", differ > deg_to_rad(3.0), str(rad_to_deg(differ)))
	# Frame rate independence: 60 Hz and 240 Hz updates agree on the fixed internal step.
	var c: RefCounted = PeopleGaze.new()
	c.configure(people, {})
	c.reset(0.0, path.call(0.0))
	for i in 360:
		var t := float(i + 1) / 60.0
		c.update_to(t, path.call(t))
	_check("update rate does not change the head path", c.head_angles(0).distance_to(a.head_angles(0)) < deg_to_rad(0.5),
		"%s vs %s" % [c.head_angles(0), a.head_angles(0)])


func _test_reset_and_repeats() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("pilot", 3)], {})
	var target := Vector3(-20.0, 10.0, -20.0)
	model.reset(0.0, Vector3(0.0, 1.55, -20.0))
	_run(model, func(_t: float) -> Vector3: return target, 1.0)
	var held: Vector2 = model.head_angles(0)
	model.update_to(1.0, target)
	model.update_to(1.0, target)
	_check("repeated timestamps (pause) change nothing", model.head_angles(0) == held)
	model.update_to(0.5, target)
	var params := PeopleGaze._params("pilot", 3)
	_check("a backward time jump resets to rest", model.head_angles(0).distance_to(Vector2(params.rest_yaw, params.rest_pitch) * float(params.mover)) < 1.0e-6)


## SC-HUM-04: each flight-line pilot flies one companion; the rest of the field watches the player.
func _test_companion_pilots() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("pilot", 31), _person("pilot", 32), _person("spectator", 33)], {})
	_check("pilots take companion slots in order", model.companion_slot(0) == 0 and model.companion_slot(1) == 1 and model.companion_slot(2) == -1)
	var player := Vector3(-40.0, 20.0, -40.0) # 45° left
	var companion := Vector3(40.0, 20.0, -40.0) # 45° right
	model.reset(0.0, player, [companion])
	for i in 720:
		model.update_to(float(i + 1) / 240.0, player, [companion])
	var p0 := PeopleGaze._params("pilot", 31)
	var p1 := PeopleGaze._params("pilot", 32)
	_check("pilot 0 watches its companion", absf(model.head_angles(0).x + deg_to_rad(45.0) * float(p0.mover)) < deg_to_rad(1.0), str(rad_to_deg(model.head_angles(0).x)))
	_check("pilot 1 without a companion watches the player", absf(model.head_angles(1).x - deg_to_rad(45.0) * float(p1.mover)) < deg_to_rad(1.0), str(rad_to_deg(model.head_angles(1).x)))
	_check("spectators watch the player", model.head_angles(2).x > deg_to_rad(20.0), str(rad_to_deg(model.head_angles(2).x)))
	# Removing the companion (null slot or an empty roster) returns pilot 0 to the player.
	for i in 720:
		model.update_to(3.0 + float(i + 1) / 240.0, player, [null])
	_check("a removed companion returns its pilot to the player", absf(model.head_angles(0).x - deg_to_rad(45.0) * float(p0.mover)) < deg_to_rad(1.0), str(rad_to_deg(model.head_angles(0).x)))
	# A companion appearing far from its last position starts without a lead spike.
	var before_rate: float = 0.0
	model.update_to(6.0 + 1.0 / 240.0, player, [Vector3(400.0, 20.0, -40.0)])
	for target: Dictionary in model._targets:
		before_rate = maxf(before_rate, (target.get("velocity", Vector3.ZERO) as Vector3).length())
	_check("a new companion target has no velocity spike", before_rate < 1.0, str(before_rate))


## SC-HUM-05: a crash lifts the range limit for a while after each person's startle delay.
func _test_crash_glance() -> void:
	var model: RefCounted = PeopleGaze.new()
	model.configure([_person("pits", 41), _person("pilot", 42)], {})
	var p := PeopleGaze._params("pits", 41)
	var rest := Vector2(p.rest_yaw, p.rest_pitch) * float(p.mover)
	var wreck := Vector3(-400.0, 0.5, -400.0) # beyond any pits range, 45° left
	model.reset(0.0, wreck)
	for i in 240:
		model.update_to(float(i + 1) / 240.0, wreck)
	_check("a distant aircraft is ignored before the crash", model.head_angles(0).distance_to(rest) < deg_to_rad(0.5))
	var t := 1.0
	var reacted_at := -1.0
	while t < 1.0 + float(p.reaction_s) + 3.0:
		t += 1.0 / 60.0 # presentation frames while the simulation is paused
		model.update_to(t, wreck, [], true)
		if reacted_at < 0.0 and model.head_angles(0).distance_to(rest) > deg_to_rad(1.0):
			reacted_at = t - 1.0
	_check("the crash glance starts after the startle delay", reacted_at >= float(p.reaction_s) - 0.02 and reacted_at < float(p.reaction_s) + 0.3,
		"%.2f vs %.2f" % [reacted_at, float(p.reaction_s)])
	_check("the pits member looks at the crash", absf(model.head_angles(0).x - deg_to_rad(45.0) * float(p.mover)) < deg_to_rad(2.0), str(rad_to_deg(model.head_angles(0).x)))
	while t < 1.0 + float(p.reaction_s) + PeopleGaze.ALERT_DURATION_S + 3.0:
		t += 1.0 / 60.0
		model.update_to(t, wreck, [], true)
	_check("interest fades after the alert window", model.head_angles(0).distance_to(rest) < deg_to_rad(1.0), str(model.head_angles(0)))
	# A restart (time back to zero, no crash) resets everything.
	model.update_to(0.0, wreck, [], false)
	_check("restart clears the alert", model.head_angles(0).distance_to(rest) < 1.0e-6)


func _test_default_scenery() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = Loader.load_from(Loader.DEFAULT_PATH, field).scenery
	var root := Scenery.build(field, scenery, OPTS)
	var population := root.get_node_or_null("Population") as Node3D
	_check("default scenery has a population", population != null)
	if population == null:
		root.free()
		return
	var model: RefCounted = PeopleGaze.from_population(population)
	_check("gaze model built", model != null)
	if model == null:
		root.free()
		return
	var roles := {}
	for i in model.person_count():
		roles[model.person_role(i)] = int(roles.get(model.person_role(i), 0)) + 1
	_check("default roles", roles == {pilot = 2, pits = 5, spectator = 6}, str(roles))
	var slots := []
	for i in model.person_count():
		if model.companion_slot(i) >= 0:
			slots.append(model.companion_slot(i))
	_check("both flight-line pilots fly companion slots 0 and 1", slots == [0, 1], str(slots))
	model.reset(0.0, Vector3(0.0, 30.0, -80.0))
	for i in 480:
		var t := float(i + 1) / 240.0
		model.update_to(t, Vector3(-40.0 + 30.0 * t, 30.0, -80.0))
	model.apply()
	if DisplayServer.get_name() == "headless":
		print("skip MultiMesh readback under the headless dummy renderer")
	else:
		var nodes: Dictionary = population.get_meta("people_nodes")
		var person: Dictionary = (population.get_meta("people") as Array)[0]
		var angles: Vector2 = model.head_angles(0)
		for node: MultiMeshInstance3D in nodes[person.asset]:
			var custom := node.multimesh.get_instance_custom_data(int(person.index))
			var color := node.multimesh.get_instance_color(int(person.index))
			_check("yaw written to %s" % node.name, absf(custom.a - angles.x / PI) < 2.0e-3, "%f vs %f" % [custom.a, angles.x / PI])
			_check("pitch written to %s" % node.name, absf(color.a - (0.5 + angles.y / PI)) < 5.0e-3, "%f" % color.a)
	root.free()
