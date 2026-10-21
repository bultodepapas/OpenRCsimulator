## Independent continuous-motion oracle and explicit accelerated/fast crossings.
extends SceneTree

const Index := preload("res://ai/companions/traffic_index.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(description: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", description)

func _entry(id: String, north: float, east: float, down: float, vn: float, ve: float, vd: float) -> Dictionary:
	return {id = id, state = PackedFloat64Array([north, east, down, vn, ve, vd, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])}

## Analytic relative-motion closest approach, independent of cells or boxes.
func _linear_distance_squared(a: Dictionary, b: Dictionary, horizon: float) -> float:
	var dot := 0.0
	var speed_squared := 0.0
	for axis: int in 3:
		var separation: float = b.state[axis] - a.state[axis]
		var relative_speed: float = b.state[axis + 3] - a.state[axis + 3]
		dot += separation * relative_speed
		speed_squared += relative_speed * relative_speed
	var closest_time: float = clampf(-dot / speed_squared, 0.0, horizon) if speed_squared > 0.0 else 0.0
	var distance_squared := 0.0
	for axis: int in 3:
		var distance: float = b.state[axis] - a.state[axis] + closest_time * (b.state[axis + 3] - a.state[axis + 3])
		distance_squared += distance * distance
	return distance_squared

func _run() -> void:
	var index := Index.new()
	var entries := [_entry("player", 0, 0, -50, 0, 0, 0), _entry("jet", -1000, 0, -50, 400, 0, 0),
		_entry("distant", 1000, 1000, -50, 0, 0, 0)]
	_check("fast crossing rebuild", index.rebuild(entries, 6.0).ok)
	_check("fast jet spans every traversed cell", index.query(0, 30.0).indices == PackedInt32Array([1]))
	var kept: Dictionary = index.query(0, 30.0)
	var kept_boxes: PackedByteArray = var_to_bytes(index._boxes)
	var invalid := entries.duplicate(true)
	invalid[1].state[0] = NAN
	_check("invalid rebuild preserves storage and invalidates queries", not index.rebuild(invalid, 6.0).ok
		and not index.query(0, 30.0).ok and index._generation == kept.generation and var_to_bytes(index._boxes) == kept_boxes)
	_check("successful rebuild restores query validity", index.rebuild(entries, 6.0).ok and index.query(0, 30.0).indices == kept.indices)
	invalid = entries.duplicate(true)
	invalid[1].state[3] = 1.7e308
	invalid[1].state[4] = 1.7e308
	invalid[1].state[6] = sqrt(0.5)
	invalid[1].state[9] = sqrt(0.5)
	_check("finite inputs with overflowing rotation refuse", not index.rebuild(invalid, 6.0).ok and not index.query(0, 30.0).ok)
	invalid = entries.duplicate(true)
	invalid[1].state[3] = 1.0e308
	_check("finite rotated motion with overflowing endpoint refuses", not index.rebuild(invalid, 6.0).ok)
	invalid = entries.duplicate(true)
	invalid[1].id = "player"
	_check("duplicate identity refused", not index.rebuild(invalid, 6.0).ok)
	invalid = entries.duplicate(true)
	invalid[1].state[6] = 0.0
	_check("invalid attitude refused", not index.rebuild(invalid, 6.0).ok)
	_check("invalid horizon and query refused", not index.rebuild(entries, INF).ok and not index.query(0, NAN).ok)
	entries = [_entry("own", -50, -50, 0, 0, 0, 0), _entry("boundary", -20, -50, 0, 0, 0, 0)]
	index.rebuild(entries, 0.0)
	_check("negative cells include touching separation boundary", index.query(0, 30.0).indices == PackedInt32Array([1]))
	entries[1].state[0] = 1000.0
	_check("index retains detached bounds", index.query(0, 30.0).indices == PackedInt32Array([1]))
	entries = [_entry("own", 0, 0, 0, 0, 0, 0), _entry("accelerating", 120, 0, 0, 0, 0, 0)]
	entries[1].acceleration_bound_m_s2 = 10.0
	var accelerated := index.rebuild(entries, 5.0)
	# Actual constant -10 m/s² acceleration crosses the stationary ownship at sqrt(24) s.
	_check("accelerating crossing uses local cells", accelerated.ok and accelerated.overflow == 0
		and accelerated.references < Index.MAX_CELL_REFERENCES and index.query(0, 0.0).indices.has(1))
	entries = [_entry("own", 0, 0, 0, 0, 0, 0), _entry("turning", 200, 0, 0, 0, 0, 0)]
	entries[1].acceleration_bound_m_s2 = 60.0
	var built := index.rebuild(entries, 6.0)
	_check("acceleration reach uses bounded overflow fallback", built.ok and built.overflow == 1 and index.query(0, 0.0).indices.has(1))
	entries[0].acceleration_bound_m_s2 = 60.0
	index.rebuild(entries, 6.0)
	_check("oversized own query scans all candidates", index.query(0, 30.0).indices == PackedInt32Array([1]))
	entries = [_entry("own", 0, 0, 0, 0, 0, 0), _entry("hull", 5, 0, 0, 0, 0, 0)]
	entries[0].radius_m = 2.0
	entries[1].radius_m = 2.0
	entries[1].uncertainty_m = 1.0
	index.rebuild(entries, 6.0)
	_check("both hull radii and uncertainty expand the query", index.query(0, 0.0).indices.has(1))
	entries = [_entry("own", 0, 0, 0, 0, 0, 0), _entry("rotated", 0, -100, 0, 20, 0, 0)]
	entries[1].state[6] = sqrt(0.5)
	entries[1].state[9] = sqrt(0.5)
	index.rebuild(entries, 6.0)
	_check("body velocity is rotated to ground NED", index.query(0, 1.0).indices.has(1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var missed := 0
	var unordered := 0
	var broad_candidates := 0
	var exact_conflicts := 0
	for fixture: int in 80:
		entries.clear()
		for aircraft: int in 32:
			entries.append(_entry("aircraft-%d" % aircraft, rng.randf_range(-400, 400), rng.randf_range(-400, 400),
				rng.randf_range(-120, -20), rng.randf_range(-120, 120), rng.randf_range(-120, 120), rng.randf_range(-5, 5)))
		var horizon := 6.0
		_check("dense synthetic rebuild %d" % fixture, index.rebuild(entries, horizon).ok)
		for aircraft: int in 32:
			var candidates: PackedInt32Array = index.query(aircraft, 30.0).indices
			broad_candidates += candidates.size()
			for order: int in range(1, candidates.size()):
				if candidates[order] <= candidates[order - 1]: unordered += 1
			for other: int in 32:
				if other != aircraft and _linear_distance_squared(entries[aircraft], entries[other], horizon) <= 900.0:
					exact_conflicts += 1
					if not candidates.has(other): missed += 1
	_check("continuous brute-force oracle has zero omissions", missed == 0 and exact_conflicts > 0)
	_check("all queries preserve unique original order", unordered == 0)
	_check("broad phase actually filters the synthetic workload", broad_candidates < 80 * 32 * 31)
	entries.clear()
	for aircraft: int in 256:
		var bounded := _entry("bounded-%d" % aircraft, 0, 0, 0, 0, 0, 0)
		bounded.uncertainty_m = 250.0
		entries.append(bounded)
	var capacity := index.rebuild(entries, 6.0)
	_check("fleet-wide bucket allocation is bounded", capacity.ok and capacity.references <= Index.MAX_CELL_REFERENCES
		and capacity.overflow > 0)
	_check("global overflow still returns every overlapping aircraft", index.query(0, 0.0).indices.size() == 255)
	_check("empty rebuild clears prior fleet", index.rebuild([], 6.0).ok and not index.query(0, 30.0).ok)
	print("traffic index: %d checks, %d failed; exact conflicts=%d candidates=%d" % [checks, failures, exact_conflicts, broad_candidates])
	quit(1 if failures else 0)
