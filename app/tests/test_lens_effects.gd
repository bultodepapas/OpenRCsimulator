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

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_settings_checks()
	_rain_checks()
	_trigger_checks()
	_pilot_checks()
	_pool_checks()
	_shader_rule_checks()
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


func _shader_rule_checks() -> void:
	var clean := true
	for path: String in ["res://render/lens/lens_drop.gdshader", "res://render/lens/lens_film.gdshader",
			"res://render/lens/lens_stamp.gdshader", "res://render/lens/rain_streaks.gdshader"]:
		var source := FileAccess.get_file_as_string(path)
		var regex := RegEx.create_from_string("(?m)^\\s*[^/\\s].*\\bTIME\\b")
		clean = clean and not source.is_empty() and regex.search(source) == null
	_check("lens shaders never read TIME", clean)


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
	stack.advance(1.0 / 60.0, 1.0, false)
	_check("an enabled stack with nothing to show allocates no nodes yet", ok and stack.get_child_count() == 0)
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
	stack.reset()
	snap = stack.snapshot()
	_check("reset clears blood, stamps, dust, oil and drops", not snap.blood and snap.stamps == 0 and snap.dust == 0.0 and snap.oil == 0.0 and snap.drops == 0)
	view[0] = "closeup"
	stack.strike_person(0.02, camera.global_position - Vector3(0, 0, 5))
	_check("a brush only pulses the edges", not stack.snapshot().blood and float(stack.snapshot().pulse) > 0.0)
	holder.queue_free()
	await process_frame
