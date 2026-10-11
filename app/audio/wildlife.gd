## AUD-05: authored wildlife behaviour; private RNG, bounded event slots, no simulation writes.
extends RefCounted

const GROUPS: Array[String] = ["bird", "crow", "owl", "dog"]
const INTERVALS: Dictionary = {bird = Vector2(8, 19), crow = Vector2(35, 85), owl = Vector2(35, 80), dog = Vector2(70, 160)}
var rng := RandomNumberGenerator.new()
var durations: Dictionary = {}
var timers: Dictionary = {}
var last_variant: Dictionary = {}
var remaining: Array[float] = [0.0, 0.0, 0.0]
var gap: float = 0.0
var fright: float = 0.0
var reply: Dictionary = {}
var serial: int = 0
var last_event: Dictionary = {}

func configure(clips: Dictionary, seed_value: int) -> void:
	durations = clips
	rng.seed = seed_value
	for species: String in GROUPS:
		last_variant[species] = -1
	_reset_timers()

static func activity(snapshot: Dictionary) -> Dictionary:
	var sun: float = float(snapshot.get("sun_elevation", 45.0))
	var wind: float = maxf(0.0, float(snapshot.get("wind_speed", 0.0)))
	var day: float = smoothstep(-5.0, 4.0, sun)
	var night: float = 1.0 - smoothstep(-10.0, -2.0, sun)
	var shelter: float = 1.0 - smoothstep(5.0, 16.0, wind)
	var warm: float = smoothstep(8.0, 18.0, float(snapshot.get("temperature_c", 15.0)))
	var chorus: float = 1.0 + 0.55 * (1.0 - smoothstep(4.0, 22.0, absf(sun)))
	return {bird = day * shelter * chorus, crow = day * shelter,
		owl = night * shelter, dog = (0.4 + 0.6 * day) * (1.0 - smoothstep(10.0, 25.0, wind)),
		cricket = night * shelter * warm}

func _reset_timers() -> void:
	timers = {bird = rng.randf_range(2, 6), crow = rng.randf_range(18, 50),
		owl = rng.randf_range(12, 32), dog = rng.randf_range(35, 80)}

func reset() -> void:
	remaining.fill(0.0)
	reply.clear()
	gap = 3.0
	fright = 0.0
	_reset_timers()

func advance(snapshot: Dictionary, delta: float, perch_count: int, disturbed: bool = false) -> Dictionary:
	if bool(snapshot.get("paused", false)):
		return {}
	var dt: float = clampf(delta, 0.0, 0.1)
	var a: Dictionary = activity(snapshot)
	gap = maxf(0.0, gap - dt)
	fright = 6.0 if disturbed else maxf(0.0, fright - dt)
	var occupied: int = 0
	var slot: int = -1
	for i: int in remaining.size():
		remaining[i] = maxf(0.0, remaining[i] - dt)
		if remaining[i] > 0.0:
			occupied += 1
		elif slot < 0:
			slot = i
	for species: String in GROUPS:
		if species != "dog" and (perch_count == 0 or fright > 0.0):
			continue
		timers[species] = maxf(0.0, float(timers[species]) - dt * float(a[species]))
	if not reply.is_empty():
		if float(a[reply.species]) < 0.05 or fright > 0.0 or perch_count < 2:
			reply.clear()
		else:
			reply.wait = maxf(0.0, float(reply.wait) - dt)
	if gap > 0.0 or occupied >= 2 or slot < 0:
		return {}
	var species: String = ""
	var perch: int = -1
	var answering: bool = false
	if not reply.is_empty() and float(reply.wait) <= 0.0:
		species = reply.species
		perch = posmod(int(reply.perch) + rng.randi_range(1, perch_count - 1), perch_count)
		reply.clear()
		answering = true
	else:
		var eligible: Array[String] = []
		for candidate: String in GROUPS:
			if float(timers[candidate]) <= 0.0 and float(a[candidate]) >= 0.05:
				if candidate == "dog" or (perch_count > 0 and fright <= 0.0):
					eligible.append(candidate)
		if eligible.is_empty():
			return {}
		species = eligible[rng.randi_range(0, eligible.size() - 1)]
		perch = rng.randi_range(0, 1) if species == "dog" else rng.randi_range(0, perch_count - 1)
	var count: int = (durations[species] as Array).size()
	var previous: int = int(last_variant[species])
	var variant: int = rng.randi_range(0, count - (2 if previous >= 0 else 1))
	if previous >= 0 and variant >= previous:
		variant += 1
	last_variant[species] = variant
	var pitch: float = rng.randf_range(0.94, 1.06)
	remaining[slot] = float(durations[species][variant]) / pitch + 0.3
	var interval: Vector2 = INTERVALS[species]
	timers[species] = rng.randf_range(interval.x, interval.y)
	gap = rng.randf_range(3.0, 5.0)
	if not answering and species != "dog" and perch_count >= 2 and rng.randf() < 0.22:
		reply = {species = species, perch = perch, wait = rng.randf_range(3.2, 6.0)}
	serial += 1
	last_event = {species = species, variant = variant, slot = slot, perch = perch,
		pitch = pitch, level = rng.randf_range(0.80, 1.0), answering = answering, serial = serial}
	return last_event.duplicate()
