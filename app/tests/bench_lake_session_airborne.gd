## LU-26: paired FlightSession step cost with and without the lake query at 10 m above it.
## Run: godot --headless --path app --script res://tests/bench_lake_session_airborne.gd
extends SceneTree

const RB := preload("res://physics/rigid_body.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")
const Session := preload("res://sim/flight_session.gd")

const START_NED := [110.0, 125.0, -10.0]
const WARMUP_TICKS := 4
const MEASURED_TICKS := 20

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("default field and normalized lake load", field_result.ok and lake_result.ok,
		"field=%s lake=%s" % [field_result.get("errors", []), lake_result.get("errors", [])])
	if _failures > 0:
		quit(1)
		return
	var scenery_result: Dictionary = CollisionSetup.build(field_result.field)
	var world: Dictionary = scenery_result.get("world", {})
	_check("default production scenery collision world builds", scenery_result.get("ok", false)
		and world.get("proxies", []).size() >= 3360,
		"errors=%s proxies=%d" % [scenery_result.get("errors", []), world.get("proxies", []).size()])
	if _failures > 0:
		quit(1)
		return
	var initial: PackedFloat64Array = RB.make_state(PackedFloat64Array(START_NED),
		PackedFloat64Array([0.0, 0.0, 0.0]), PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]))
	var dry: Session = _new_session(world, {}, initial)
	var lake: Session = _new_session(world, lake_result.lake, initial)
	if dry == null or lake == null:
		quit(1)
		return
	for tick: int in WARMUP_TICKS:
		dry.sim.step()
		lake.sim.step()
		if not dry.crash.is_empty() or not lake.crash.is_empty():
			_check("warmup stays airborne without contact", false,
				"tick=%d dry=%s lake=%s" % [tick, dry.crash, lake.crash])
			quit(1)
			return
	dry.sim.reset(initial)
	lake.sim.reset(initial)
	dry.sim.set_paused(false)
	lake.sim.set_paused(false)
	var dry_wall := PackedInt64Array()
	var lake_wall := PackedInt64Array()
	var paired_delta: Array[int] = []
	var dry_step_internal := PackedFloat64Array()
	var lake_step_internal := PackedFloat64Array()
	for tick: int in MEASURED_TICKS:
		var dry_usec: int
		var lake_usec: int
		if tick % 2 == 0:
			dry_usec = _measure_step(dry)
			lake_usec = _measure_step(lake)
		else:
			lake_usec = _measure_step(lake)
			dry_usec = _measure_step(dry)
		dry_wall.append(dry_usec)
		lake_wall.append(lake_usec)
		paired_delta.append(lake_usec - dry_usec)
		dry_step_internal.append(float(dry.sim.step_usec))
		lake_step_internal.append(float(lake.sim.step_usec))
	_check("all 20 paired steps remain precontact at 10 m", dry.sim.tick == MEASURED_TICKS
		and lake.sim.tick == MEASURED_TICKS and dry.crash.is_empty() and lake.crash.is_empty(),
		"dry_tick=%d lake_tick=%d dry_crash=%s lake_crash=%s" % [
			dry.sim.tick, lake.sim.tick, dry.crash, lake.crash])
	_check("airborne session state remains bit-identical with bounded lake context",
		_same_packed(dry.sim.state, lake.sim.state),
		"dry=%s lake=%s" % [str(dry.sim.state), str(lake.sim.state)])
	var dry_total: int = _sum(dry_wall)
	var lake_total: int = _sum(lake_wall)
	var sorted_dry: PackedInt64Array = dry_wall.duplicate()
	var sorted_lake: PackedInt64Array = lake_wall.duplicate()
	sorted_dry.sort()
	sorted_lake.sort()
	paired_delta.sort()
	print("lake session airborne / full production scenery: proxies=%d bins=%d start_ned=%s ticks=%d; " % [
		world.proxies.size(), world.bins.size(), str(START_NED), MEASURED_TICKS],
		"wall_usec dry p50/p95=%d/%d lake=%d/%d paired_added_p50=%d total_added=%d avg_added=%.1f; " % [
			_percentile(sorted_dry, 0.50), _percentile(sorted_dry, 0.95),
			_percentile(sorted_lake, 0.50), _percentile(sorted_lake, 0.95),
			paired_delta[clampi(int(floor(float(MEASURED_TICKS - 1) * 0.5)), 0, paired_delta.size() - 1)],
			lake_total - dry_total, float(lake_total - dry_total) / float(MEASURED_TICKS)],
		"sim.step_usec dry avg=%.1f lake avg=%.1f" % [
			_average(dry_step_internal), _average(lake_step_internal)])
	dry.queue_free()
	lake.queue_free()
	await process_frame
	print("lake session airborne benchmark: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_session(world: Dictionary, lake: Dictionary,
		initial: PackedFloat64Array) -> Session:
	var session := Session.new()
	session.physics_enabled = false
	session.crash_auto_restart = false
	root.add_child(session)
	session.setup()
	if not session.set_collision_world(world):
		_check("session installs shared production scenery inventory", false)
		return null
	if not lake.is_empty() and not session.set_lake_context(lake):
		_check("lake session accepts the normalized basin", false)
		return null
	if not session.sim.reset(initial):
		_check("session accepts the 10 m airborne start", false, str(session.sim.fault_reason))
		return null
	session.sim.set_paused(false)
	return session


func _measure_step(session: Session) -> int:
	var start_usec: int = Time.get_ticks_usec()
	session.sim.step()
	return Time.get_ticks_usec() - start_usec


func _sum(values: PackedInt64Array) -> int:
	var total := 0
	for value: int in values:
		total += value
	return total


func _percentile(sorted: PackedInt64Array, fraction: float) -> int:
	if sorted.is_empty():
		return 0
	return sorted[clampi(ceili(float(sorted.size()) * fraction) - 1, 0, sorted.size() - 1)]


func _average(values: PackedFloat64Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(float(values.size()), 1.0)


func _same_packed(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if a[index] != b[index]:
			return false
	return true


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
