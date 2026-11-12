## CR-22e micro costs on the real flight scene after a crash (headless, best of N, microseconds).
## Run from the repo root: godot --headless --path app --audio-driver Dummy --script "$PWD/research/crash-damage/cr-22e/micro_costs.gd"
extends SceneTree
## Final-pass micro costs on the real flight scene after a crash (best of N, microseconds).
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
const SceneryBodies = preload("res://render/landscape_upgrade/scenery_bodies.gd")
const GlowVoice = preload("res://audio/glow_voice.gd")

func _initialize() -> void:
	_run.call_deferred()

func _best(c: Callable, n := 7) -> int:
	var best := 1 << 40
	for i in n:
		var t := Time.get_ticks_usec(); c.call(); best = mini(best, Time.get_ticks_usec() - t)
	return best

func _run() -> void:
	var flight: Node3D = load("res://main.tscn").instantiate()
	root.add_child(flight)
	flight.session.input_enabled = false
	for i in 30: await process_frame
	var s: PackedFloat64Array = flight.session.sim.state.duplicate()
	var att := M.q_from_euler(0.2, -0.95, 0.55)
	for i in 4: s[RB.ATT + i] = att[i]
	s[RB.POS] = -25.0; s[RB.POS + 1] = -15.0; s[RB.POS + 2] = -1.5
	var v := M.q_rotate(M.q_conj(att), PackedFloat64Array([12.0, 0.0, 25.0]))
	for i in 3: s[RB.VEL + i] = v[i]; s[RB.RATE + i] = 0.0
	flight.session.sim.state = s.duplicate(); flight.session.sim.previous = s.duplicate()
	flight.session.sim.set_paused(false)
	for i in 240:
		await process_frame
		if not flight.session.crash.is_empty(): break
	for i in 30: await process_frame
	var inc: RefCounted = flight._accident_incident
	inc.wait_for_valuation()
	var out := {crashed = not flight.session.crash.is_empty(), revision = inc._revision}
	out.clone_us = _best(func(): inc._valuation_clone())
	out.report_dup_us = _best(func(): inc.report.duplicate(true))
	out.property_list_us = _best(func(): inc.get_property_list())
	var sizes := {}
	for p: Dictionary in inc.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = inc.get(p.name)
			if value is Dictionary or value is Array:
				var t := Time.get_ticks_usec(); value.duplicate(true); var d := Time.get_ticks_usec() - t
				if d > 20: sizes[p.name] = d
	out.clone_field_us = sizes
	var world: Dictionary = flight._camera_obstacles
	out.proxies = world.get("proxies", []).size()
	var point := PackedFloat64Array([-25.0, -15.0, 0.0])
	out.scan_us = _best(func():
		var c := 0
		for proxy: Dictionary in world.get("proxies", []):
			if absf(float(proxy.north) - point[0]) <= 65.0 and absf(float(proxy.east) - point[1]) <= 65.0: c += 1, 5)
	var damage: Dictionary = flight.session.scenery_damage()
	out.build_near_us = _best(func(): SceneryBodies.build_near(world, point, damage).free(), 5)
	out.staged_first16_us = _best(func(): SceneryBodies.build_near_staged(world, point, damage, 16).free(), 5)
	var staged := SceneryBodies.build_near_staged(world, point, damage, 16)
	out.staged_next24_us = _best(func(): SceneryBodies.continue_build(staged, 24), 5)
	staged.free()
	out.clone_us_cached = _best(func(): inc._valuation_clone())
	out.damage_entries = damage.size()
	out.plan_damage_us = _best(func(): SceneryBodies._plan_near(world, point, damage), 5)
	out.plan_nodamage_us = _best(func(): SceneryBodies._plan_near(world, point, {}), 5)
	var cand := 0
	for proxy: Dictionary in world.get("proxies", []):
		var margin := maxf(float(proxy.get("radius", 0.0)), maxf(float(proxy.get("half_x", 0.0)), float(proxy.get("half_z", 0.0))))
		if absf(float(proxy.north) - point[0]) <= 65.0 + margin and absf(float(proxy.east) - point[1]) <= 65.0 + margin: cand += 1
	out.candidates = cand
	out.extents = SceneryBodies.prepare(world)
	out.nearby = SceneryBodies._nearby_indices(world, point).size()
	out.nearby_us = _best(func(): SceneryBodies._nearby_indices(world, point), 5)
	var margins := []
	for proxy: Dictionary in world.get("proxies", []): margins.append([SceneryBodies._margin(proxy), str(proxy.get("kind","")), str(proxy.id)])
	margins.sort(); margins.reverse()
	out.top_margins = margins.slice(0, 6)
	out.dist_us = _best(func():
		for proxy: Dictionary in world.get("proxies", []): SceneryBodies._distance_squared(proxy, point), 3)
	out.staged_root_only_us = _best(func():
		var r := Node3D.new(); r.set_meta("pending", SceneryBodies._plan_near(world, point, damage)); r.free(), 5)
	var gv := GlowVoice.new()
	var silent := {family = "glow_2t", rpm = 0.0, running = false, max_rpm = 12000.0}
	var running := {family = "glow_2t", rpm = 9000.0, running = true, max_rpm = 12000.0, load = 0.8}
	out.glow_silent_us_per_100ms = _best(func(): gv.render_telemetry(silent, 2205))
	out.glow_running_us_per_100ms = _best(func(): gv.render_telemetry(running, 2205))
	var report: Node = flight._accident_report
	report._count_up_elapsed = 0.3
	out.count_up_us = _best(func(): report._apply_count_up(), 20)
	report._count_up_elapsed = -1.0
	print("MICRO ", JSON.stringify(out))
	flight.free()
	await process_frame
	quit()
