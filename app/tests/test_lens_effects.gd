## LENS-01…11 (docs/plans/lens-screen-effects.md): focused checks of the lens stack's pure laws and its lifecycle.
## Headless: no pixels are judged here (captures do that); this holds settings, rain law, triggers, the pilot strike
## detector, the drop pool's conservation and the zero-allocation rule.
extends SceneTree

const Settings = preload("res://render/lens/lens_settings.gd")
const RainModel = preload("res://render/lens/rain_model.gd")
const ImpactTrigger = preload("res://render/lens/impact_trigger.gd")
const PilotStrike = preload("res://render/lens/pilot_strike.gd")
const DropPool = preload("res://render/lens/drop_pool.gd")
const LensStack = preload("res://render/lens/lens_stack.gd")
const DisplayPreferences = preload("res://app_state/display_preferences.gd")
const CollisionWorld = preload("res://scenery/collision_world.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_settings_checks()
	_rain_checks()
	_trigger_checks()
	_pilot_checks()
	_pool_checks()
	_shader_rule_checks()
	_preference_file_checks()
	await process_frame
	await _stack_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _settings_checks() -> void:
	var interactive: Dictionary = Settings.resolve({}, true, Settings.DEFAULTS)
	_check("defaults enable the stack on interactive flights", interactive.enabled and interactive.impact == "curtain" and interactive.rain and interactive.grime)
	var scripted: Dictionary = Settings.resolve({}, false, Settings.DEFAULTS)
	_check("scripted, capture and trace routes get nothing by default", not scripted.enabled)
	_check("Automatic is the default and resolves to a real tier", Settings.DEFAULTS.lens_effects == "auto"
		and interactive.requested_quality == "auto" and interactive.quality in ["low", "medium", "high", "ultra"])
	var forced: Dictionary = Settings.resolve({"lens-effects": "high"}, false, Settings.DEFAULTS)
	_check("an explicit --lens-effects enables a non-interactive route", forced.enabled and forced.quality == "high")
	var off: Dictionary = Settings.resolve({"lens-effects": "off"}, true, Settings.DEFAULTS)
	_check("--lens-effects=off disables everything", not off.enabled and off.impact == "off" and not off.rain and not off.grime)
	var all_off: Dictionary = Settings.resolve({"impact-fx": "off", "lens-rain": "off", "lens-grime": "off"}, true, Settings.DEFAULTS)
	_check("every channel off means no stack", not all_off.enabled)
	var bogus: Dictionary = Settings.validate({"lens_effects": "extreme", "impact_effects": 3, "lens_rain": "maybe"})
	_check("invalid saved values fall back to defaults", bogus == Settings.DEFAULTS)
	var rain: Dictionary = Settings.resolve({"lens-rain-mmph": "7.5"}, true, Settings.DEFAULTS)
	_check("rain override parses", is_equal_approx(float(rain.rain_override_mmph), 7.5))
	var bad_rain: Dictionary = Settings.resolve({"lens-rain-mmph": "lots"}, true, Settings.DEFAULTS)
	_check("a malformed rain override is ignored", is_nan(float(bad_rain.rain_override_mmph)))


func _rain_checks() -> void:
	var slope := RainModel.slope_per_mm(5.0)
	_check("Marshall–Palmer slope at 5 mm/h ≈ 2.92 mm⁻¹", absf(slope - 2.92) < 0.01)
	_check("number density at 5 mm/h ≈ 2740 m⁻³", absf(RainModel.number_density(5.0) - 2740.0) < 15.0)
	_check("no rain has no drops", RainModel.number_density(0.0) == 0.0 and RainModel.arrival_rate(0.0, 30.0, 1.0) == 0.0)
	var at_rest := RainModel.arrival_rate(5.0, 0.0, 1.0)
	var flying := RainModel.arrival_rate(5.0, 30.0, 1.0)
	_check("a lens flying into the rain catches far more drops than one at rest", flying > 10.0 * at_rest and at_rest > 0.0)
	_check("worked example: about 9 drops/s at 30 m/s (plus deposition)", flying > 8.5 and flying < 11.5)
	_check("heavier rain has larger drops", RainModel.sample_diameter(20.0, 0.5) > RainModel.sample_diameter(1.0, 0.5))
	var inside := true
	for i in 50:
		var d := RainModel.sample_diameter(3.0, float(i) / 50.0)
		inside = inside and d >= RainModel.MIN_DIAMETER_MM and d <= RainModel.MAX_DIAMETER_MM
	_check("sampled diameters stay in the truncated range", inside)
	_check("fall speed grows with diameter", RainModel.fall_speed(2.0) > RainModel.fall_speed(1.0))
	var b1 := RainModel.burst(100.0, 7)
	_check("bursts are deterministic and bounded", b1 == RainModel.burst(100.0, 7) and b1 >= 0.45 and b1 <= 1.55)
	_check("the electrical storm rains at the field; distant storms do not",
		RainModel.rate_for_preset("electrical_storm") > 7.6 and RainModel.rate_for_preset("distant_storm") == 0.0)


func _event(kind: String, tick: int, extra: Dictionary = {}) -> Dictionary:
	var event := {"event_id": "as13:impact:scenery:%d:new:%s" % [tick, kind], "event_type": "impact", "source": "scenery",
		"lifecycle": "new", "tick": tick, "obstacle_kind": kind, "probe_source": "hull",
		"point_ned": PackedFloat64Array([10.0, 5.0, -1.0]), "measure": {"speed_mps": 9.0}}
	event.merge(extra, true)
	return event


func _trigger_checks() -> void:
	var person := ImpactTrigger.classify(_event("person", 10), 1.5)
	_check("a person strike is admitted as person", person.get("kind") == "person")
	_check("1.5 kg at 9 m/s is a full-strength strike", absf(float(person.strength) - 1.0) < 1e-6)
	var brush := ImpactTrigger.classify(_event("person", 11, {"measure": {"speed_mps": 0.8}}), 1.0)
	_check("a slow brush is below the curtain threshold", float(brush.strength) < 0.2)
	var energy := ImpactTrigger.classify(_event("person", 12, {"measure": {"speed_mps": 1.0, "impact_energy_j": 60.0}}), 1.0)
	_check("measured impact energy overrides the kinetic estimate", absf(float(energy.strength) - 1.0) < 1e-6)
	_check("persistent contacts are not new strikes", ImpactTrigger.classify(_event("person", 13, {"lifecycle": "persistent"}), 1.0).is_empty())
	_check("trees become foliage grime", ImpactTrigger.classify(_event("tree_foliage", 14), 1.0).get("kind") == "foliage")
	var lake := ImpactTrigger.classify({"event_id": "l", "source": "lake", "lifecycle": "new", "tick": 3, "material": "water",
		"point_ned": PackedFloat64Array([0.0, 0.0, 0.0]), "measure": {"speed_mps": 6.0}}, 1.0)
	_check("a lake splash is water", lake.get("kind") == "water")
	_check("slow ground contacts leave no grime", ImpactTrigger.classify({"event_id": "g", "source": "hull", "event_type": "impact",
		"lifecycle": "new", "tick": 3, "point_ned": PackedFloat64Array([0.0, 0.0, 0.0]), "measure": {"speed_mps": 1.0}}, 1.0).is_empty())
	var seen := {}
	var snapshot := {"events": [_event("person", 20), _event("person", 5)]}
	var first := ImpactTrigger.admit(snapshot, seen, 10, 1.5)
	_check("admission ignores events at or before the floor tick", first.size() == 1 and int(first[0].tick) == 20)
	_check("the same event is admitted only once", ImpactTrigger.admit(snapshot, seen, 10, 1.5).is_empty())
	_check("the pilot view scales a distant strike down", ImpactTrigger.view_factor("pilot", 90.0, false) < 0.5)
	_check("the player's own strike is always full", ImpactTrigger.view_factor("pilot", 90.0, true) == 1.0)


func _pilot_checks() -> void:
	var station := PackedFloat64Array([0.0, 0.0, 0.0])
	var detector := PilotStrike.new()
	# A point flying north at 40 m/s through the pilot's chest (1.2 m up), sampled at 20, 60 and 144 FPS.
	for fps: float in [20.0, 60.0, 144.0]:
		detector.reset()
		var dt := 1.0 / fps
		var hit := {}
		var north := -5.0
		while north < 5.0 and hit.is_empty():
			hit = detector.observe(PackedFloat64Array([north, 0.1, -1.2]), station, 1.7, dt)
			north += 40.0 * dt
		_check("a 40 m/s head-on pass is detected at %d FPS" % int(fps), not hit.is_empty() and absf(float(hit.speed_mps) - 40.0) < 0.5)
	detector.reset()
	var miss := {}
	var n := -5.0
	while n < 5.0:
		var r := detector.observe(PackedFloat64Array([n, 0.85, -1.2]), station, 1.7, 1.0 / 60.0)
		if not r.is_empty():
			miss = r
		n += 40.0 / 60.0
	_check("a pass 0.5 m clear of the pilot is not a strike", miss.is_empty())
	detector.reset()
	var hits := 0
	for i in 40:
		var p := PackedFloat64Array([-1.0 + float(i) * 0.05, 0.0, -1.0])
		if not detector.observe(p, station, 1.7, 1.0 / 60.0).is_empty():
			hits += 1
	_check("a lingering contact strikes once until re-armed", hits == 1)
	_check("segment distance of crossing segments is zero",
		PilotStrike.segment_distance(PackedFloat64Array([-1, 0, 0]), PackedFloat64Array([1, 0, 0]),
			PackedFloat64Array([0, -1, 0]), PackedFloat64Array([0, 1, 0])) < 1e-9)


func _pool_checks() -> void:
	var pool := DropPool.new()
	pool.configure(32, 4, false)
	pool.spawn(0.5, 0.5, 0.01)
	pool.spawn(0.505, 0.5, 0.01)
	var before := pool.volume()
	pool.step(1.0 / 60.0, 1.7778, Vector2.ZERO, Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true)
	_check("overlapping drops merge into one", pool.count == 1)
	_check("merging conserves water volume", absf(pool.volume() - before) / before < 1e-4)
	pool.clear()
	pool.spawn(0.5, 0.3, 0.004)
	for i in 120:
		pool.step(1.0 / 60.0, 1.7778, Vector2(0.0, 1.0), Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true)
	_check("a small bead stays pinned under gravity", pool.count == 1 and absf(pool.drop_position(0).y - 0.3) < 1e-3)
	pool.clear()
	pool.spawn(0.5, 0.3, 0.03)
	for i in 120:
		pool.step(1.0 / 60.0, 1.7778, Vector2(0.0, 1.0), Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true)
	_check("a large drop runs down the glass", pool.count == 1 and pool.drop_position(0).y > 0.32)
	pool.clear()
	pool.spawn(1.2, 0.5, 0.012)
	for i in 30:
		pool.step(1.0 / 60.0, 1.7778, Vector2.ZERO, Vector2(0.889, 0.5), 1.0, Vector2.ZERO, true)
	_check("airflow pushes drops away from the focus of expansion", pool.count == 0 or pool.drop_position(0).x > 1.21)
	pool.clear()
	for i in 40:
		pool.spawn_random(1.7778, 0.006)
	_check("the pool never exceeds its capacity", pool.count <= pool.capacity)
	var layout := DropPool.new()
	layout.configure(4, 2, false)
	layout.spawn(0.5, 0.25, 0.02)
	layout.step(1.0 / 60.0, 1.7778, Vector2(0.6, 0.8), Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.instance_count = 4
	layout.write(mm, 1080.0, true)
	var velocity := layout.drop_velocity(0)
	var elongation := clampf(velocity.length() * 4.0, 0.0, 1.6)
	var diameter := 2.0 * layout.drop_radius(0) * 1080.0
	var expected := Transform2D(velocity.angle(), Vector2(diameter * (1.0 + elongation), diameter), 0.0, layout.drop_position(0) * 1080.0)
	var written := mm.get_instance_transform_2d(0)
	# The headless dummy renderer stores no MultiMesh data; the layout is then checked in the rendered app only.
	var probe := MultiMesh.new()
	probe.transform_format = MultiMesh.TRANSFORM_2D
	probe.instance_count = 1
	probe.set_instance_transform_2d(0, Transform2D(0.0, Vector2(2.0, 2.0), 0.0, Vector2(3.0, 4.0)))
	if probe.get_instance_transform_2d(0).origin != Vector2(3.0, 4.0):
		print("skip the packed buffer layout (dummy renderer keeps no MultiMesh data)")
	else:
		_check("the packed buffer matches the engine's 2D instance layout", written.x.is_equal_approx(expected.x)
			and written.y.is_equal_approx(expected.y) and written.origin.is_equal_approx(expected.origin)
			and mm.visible_instance_count == 1)
	var thrown := DropPool.new()
	thrown.configure(8, 6, false)
	thrown.spawn(0.9, 0.5, 0.018)
	for i in 30:
		thrown.step(1.0 / 60.0, 1.7778, Vector2.ZERO, Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true, Vector2(3.0, 0.0))
	_check("a hard acceleration throws a drop across the glass (inertia)", thrown.count == 1 and thrown.drop_position(0).x > 0.92)
	var crown := DropPool.new()
	crown.configure(16, 7, false)
	crown.splash(0.9, 0.5, 0.01, 4)
	_check("a fast impact leaves a crown of smaller beads around it", crown.count == 4 and crown.drop_radius(0) < 0.01)
	var crowd := DropPool.new()
	crowd.configure(96, 9, false)
	for i in 90:
		crowd.spawn(0.4 + crowd.random() * 0.2, 0.4 + crowd.random() * 0.2, 0.004)
	var crowd_volume := crowd.volume()
	crowd.step(1.0 / 60.0, 1.7778, Vector2.ZERO, Vector2(0.889, 0.5), 0.0, Vector2.ZERO, true)
	_check("a crowded patch merges through the hashed grid and conserves water", crowd.count < 90
		and absf(crowd.volume() - crowd_volume) / crowd_volume < 1e-4)


func _shader_rule_checks() -> void:
	var clean := true
	for path: String in ["res://render/lens/lens_drop.gdshader", "res://render/lens/lens_film.gdshader",
			"res://render/lens/lens_stamp.gdshader", "res://render/lens/rain_streaks.gdshader"]:
		var source := FileAccess.get_file_as_string(path)
		var regex := RegEx.create_from_string("(?m)^\\s*[^/\\s].*\\bTIME\\b")
		clean = clean and not source.is_empty() and regex.search(source) == null
	_check("lens shaders never read TIME", clean)


func _preference_file_checks() -> void:
	var defaults: Dictionary = DisplayPreferences.DEFAULTS.duplicate(true)
	_check("display defaults carry the lens defaults", defaults.lens_effects == Settings.DEFAULTS.lens_effects
		and defaults.impact_effects == Settings.DEFAULTS.impact_effects)
	var bad := defaults.duplicate(true)
	bad.impact_effects = "gore"
	_check("an unknown impact style is refused", not DisplayPreferences.validate(bad).ok)
	var chosen := defaults.duplicate(true)
	chosen.lens_effects = "ultra"
	chosen.impact_effects = "splatter"
	chosen.impact_colour = "dark"
	chosen.lens_rain = "off"
	chosen.lens_glasses = "on"
	var path := "user://test_lens_display.cfg"
	var saved := DisplayPreferences.save_to(path, chosen)
	var loaded: Dictionary = DisplayPreferences.load_from(path)
	_check("lens preferences survive a save and load", saved == OK and loaded.lens_effects == "ultra"
		and loaded.impact_effects == "splatter" and loaded.impact_colour == "dark" and loaded.lens_rain == "off"
		and loaded.lens_glasses == "on")
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("lens", "impact", 7)
	cfg.save(path)
	var recovered: Dictionary = DisplayPreferences.load_from(path)
	_check("one malformed lens value falls back alone", recovered.impact_effects == Settings.DEFAULTS.impact_effects
		and recovered.lens_effects == "ultra")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var resolved: Dictionary = Settings.resolve({}, true, loaded)
	_check("a saved preference resolves into the flight's settings", resolved.quality == "ultra"
		and resolved.impact == "splatter" and not resolved.rain and resolved.glasses)


func _stack_checks() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	var view := ["chase"] # lambdas capture locals by value: mutate a container
	var disabled := LensStack.new()
	holder.add_child(disabled)
	var refused := disabled.configure({"settings": Settings.resolve({"lens-effects": "off"}, true, Settings.DEFAULTS),
		"camera": camera, "view_provider": func() -> String: return view[0]})
	disabled.advance(1.0 / 60.0, 1.0, false)
	_check("a disabled stack builds nothing", not refused and disabled.get_child_count() == 0)
	var stack := LensStack.new()
	holder.add_child(stack)
	var ok := stack.configure({"settings": Settings.resolve({}, true, Settings.DEFAULTS), "camera": camera,
		"view_provider": func() -> String: return view[0], "seed": 3})
	_check("an enabled stack warms its shaders at setup", ok and stack.get_child_count() == 1
		and bool(stack.snapshot().nodes.film) and bool(stack.snapshot().nodes.stamps) and bool(stack.snapshot().nodes.drops))
	for i in 4:
		stack.advance(1.0 / 60.0, 1.0, false)
	var layer: CanvasLayer = stack.get_node("LensLayer")
	var shown := false
	for child: Node in layer.get_children():
		shown = shown or (child as CanvasItem).visible
	_check("after the warm-up nothing is drawn until something happens", not shown)
	stack.debug_blood(1.0)
	stack.advance(1.0 / 60.0, 1.0, false)
	var snap: Dictionary = stack.snapshot()
	_check("a strike shows the curtain and splats", snap.blood and snap.nodes.film and snap.nodes.stamps and snap.stamps >= 2)
	stack.advance(1.0 / 60.0, 1.0, true)
	var held: float = stack.snapshot().blood_t
	stack.advance(0.5, 1.5, true)
	_check("pause holds the curtain", is_equal_approx(float(stack.snapshot().blood_t), held))
	for i in 600:
		stack.advance(1.0 / 60.0, 1.0 + i / 60.0, false)
	_check("the curtain drains and ends", not stack.snapshot().blood)
	stack.debug_rain(10.0)
	for i in 300:
		stack.advance(1.0 / 60.0, 20.0 + i / 60.0, false)
	snap = stack.snapshot()
	_check("rain builds streaks and drops on the lens", snap.nodes.streaks and snap.nodes.drops and snap.drops > 0)
	view[0] = "pilot"
	stack.advance(1.0 / 60.0, 23.0, false)
	_check("the pilot's eye has no drops without glasses", stack.snapshot().drops == 0)
	stack.debug_grime("rough", 18.0)
	stack.debug_oil(0.3)
	var struck := [0, 0]
	stack.person_struck.connect(func(player: bool) -> void: struck[1 if player else 0] += 1)
	var crash_world: Dictionary = CollisionWorld.build({pilot = {north = -60.0, east = 0.0, down = 0.0}, objects = []},
		{groups = [{id = "spectators", prefab = "person_standing", placements = [{north = 10.0, east = 0.0, heading = 0.0}]}]})
	stack.reset()
	stack.strike_from_crash(PackedFloat64Array([10.0, 0.0, -0.9]), 14.0, crash_world.world, "test:1")
	_check("a crash at a spectator draws blood and announces it", bool(stack.snapshot().blood) and struck[0] == 1)
	stack.reset()
	stack.strike_from_crash(PackedFloat64Array([40.0, 0.0, 0.0]), 14.0, crash_world.world, "test:2")
	_check("a crash in the open is ground, not blood", not bool(stack.snapshot().blood) and struck[0] == 1)
	stack.reset()
	stack.settings["impact"] = "splatter"
	view[0] = "chase"
	stack.advance(1.0 / 60.0, 30.0, false)
	stack.strike_person(1.0, Vector3.INF, false, "runner:1")
	var runners: Array = stack._stamps.filter(func(s: Dictionary) -> bool: return int(s.kind) == LensStack.STAMP_RUNNER)
	for i in 120:
		stack.advance(1.0 / 60.0, 30.0 + i / 60.0, false)
	var early: float = runners[0].grow if not runners.is_empty() else -1.0
	for i in 600:
		stack.advance(1.0 / 60.0, 32.0 + i / 60.0, false)
	var late: float = runners[0].grow if not runners.is_empty() else -1.0
	_check("blood splats bleed runners that creep down and stop as they set", not runners.is_empty()
		and early > 0.3 and late > early and late < 1.0)
	stack.reset()
	stack.debug_grime("rough", 10.0)
	var mud: Array = stack._stamps.filter(func(s: Dictionary) -> bool: return int(s.kind) == LensStack.STAMP_MUD)
	stack.debug_rain(12.0)
	for i in 60:
		stack.advance(1.0 / 60.0, 40.0 + i / 60.0, false)
	_check("rain keeps mud wet and rinses it off within half a minute", not mud.is_empty()
		and float(mud[0].dry_t) < 0.05 and is_finite(float(mud[0].life)) and float(mud[0].life) <= LensStack.MUD_RINSE_S + 2.0)
	stack.debug_rain(0.0)
	stack.reset()
	var wheels := camera.global_position + Vector3(0.0, -0.5, -2.0)
	for i in 30:
		stack.kick_up(1.0, 1.0, wheels, 6.0, 0.5)
	_check("wheels throw mud flecks and water at a camera close behind them", stack.snapshot().stamps > 0 and stack.snapshot().drops > 0)
	stack.reset()
	for i in 30:
		stack.kick_up(1.0, 1.0, camera.global_position + Vector3(0.0, 0.0, -40.0), 6.0, 0.5)
	_check("a distant truck throws nothing at the lens", stack.snapshot().stamps == 0 and stack.snapshot().drops == 0)
	stack.settings["impact"] = "curtain"
	var pilot_stack := LensStack.new()
	holder.add_child(pilot_stack)
	pilot_stack.configure({"settings": Settings.resolve({}, true, Settings.DEFAULTS), "camera": camera,
		"view_provider": func() -> String: return "pilot", "station": PackedFloat64Array([10.0, 0.0, 0.0]), "seed": 4})
	var pilot_hits := [0]
	pilot_stack.person_struck.connect(func(player: bool) -> void: pilot_hits[0] += 1 if player else 0)
	pilot_stack.show_message("caption first")
	pilot_stack.strike_person(1.0, Vector3.INF, true, "pilot:1")
	pilot_stack.strike_from_crash(PackedFloat64Array([10.0, 0.0, -0.9]), 14.0, crash_world.world, "crash:2")
	_check("a crash at the pilot after the sweep fired is not a second strike", pilot_hits[0] == 1)
	var pilot_layer: CanvasLayer = pilot_stack.get_node("LensLayer")
	_check("the caption stays above the curtain", pilot_layer.get_child(pilot_layer.get_child_count() - 1).name == "LensMessage")
	pilot_stack.queue_free()
	stack.reset()
	snap = stack.snapshot()
	_check("reset clears blood, stamps, dust, oil and drops", not snap.blood and snap.stamps == 0 and snap.dust == 0.0 and snap.oil == 0.0 and snap.drops == 0)
	view[0] = "closeup"
	stack.strike_person(0.02, camera.global_position - Vector3(0, 0, 5))
	_check("a brush only pulses the edges", not stack.snapshot().blood and float(stack.snapshot().pulse) > 0.0)
	holder.queue_free()
	await process_frame
