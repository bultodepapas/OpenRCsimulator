# SC-BIRD-02…05 and 08 (docs/plans/birds-sky-life.md): the bird data validates and rejects bad edits; every circuit
# closes, repeats on the 1024 s shader clock and flies inside the measured ranges (SC-BIRD-00 section 4); every bird,
# including on its way out, keeps out of the flight box and away from the pilot at its real (instance) height; each
# group's species share one topology and the shader's wing rig never touches the tail; the float32 shader tables
# follow the float64 reference over the shader's whole time range; real time-of-day snapshots, cloud cover and the
# detail tier decide which species fly; birds arrive and leave smoothly on sim_clock and never replay a transition
# at the clock wrap; and the drawn birds fit the scenery_Birds budget at every sun elevation, transitions included.
# Run: python3 tools/godot/run_checked.py --timeout 120 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_birds.gd
extends SceneTree

const BirdData = preload("res://scenery/birds/bird_data.gd")
const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")
const BirdPlanform = preload("res://scenery/birds/bird_planform.gd")
const BirdDirector = preload("res://scenery/birds/bird_director.gd")
const Birds = preload("res://scenery/birds.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const DisplayPreferences = preload("res://app_state/display_preferences.gd")

const BUDGET_PRIMITIVES := 1000 # tools/scenery/scene_budget.json scenery_Birds (every view class)
const BUDGET_DRAWS := 2
const FLIGHT_BOX_NORTH_M := 229.0 # scenery profile: AMA sport field depth and half width
const FLIGHT_BOX_HALF_WIDTH_M := 305.0
const FLIGHT_BOX_TOP_M := 150.0
const RUNWAY_CENTRE_NORTH_M := 15.0
const TREE_TOP_M := 25.0 # render/treeline.gd identity(): 12-25 m
const CLUB_TREE_TOP_M := 14.0 # scenery/prefabs.gd shade_tree envelope
const SAMPLE_S := 0.5
const JOINT_PROBE_S := 1e-3
const SUN_PER_TRANSITION_DEG := 1.0 # the sun moves <= 0.63 deg during the longest (150 s) transition

# Measured ranges (SC-BIRD-00 section 4): speed (m/s), bank (deg), world height of every bird (m), circling; roll
# (deg per 0.05 s, default 2.5): swallows reach 4.4 g in turns (Warrick et al. 2016) and flick from bank to bank.
const LIMITS := {
	"vulture_kettle": {speed = [8.0, 14.5], bank = [16.0, 35.0], height = [85.0, 160.0], circle_radius = [16.0, 30.0],
		turn_period = [10.0, 19.5], climb = [0.04, 2.08]},
	"stork_kettle": {speed = [8.0, 15.5], bank = [19.0, 30.0], height = [90.0, 180.0], circle_radius = [15.7, 25.5],
		turn_period = [10.98, 16.32], climb = [0.04, 2.52]},
	"kite_quartering": {speed = [5.5, 9.0], bank = [0.0, 27.0], height = [TREE_TOP_M + 8.0, 70.0],
		circle_radius = [8.1, 16.0], turn_period = [8.0, 16.0], climb = [0.09, 2.0]},
	"swallow_coursing": {speed = [6.0, 12.5], bank = [0.0, 60.0], height = [0.25, 4.1], roll = 10.0},
	"swift_party": {speed = [7.0, 12.5], bank = [0.0, 60.0], height = [CLUB_TREE_TOP_M + 5.0, 40.0], roll = 10.0},
}

var _failures := 0
var _checks := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ShaderClock.register()
	ShaderClock.update(100.0)
	var loaded: Dictionary = BirdData.load_from()
	_check("bundled birds.json validates", loaded.ok, str(loaded.get("errors", [])))
	if loaded.ok:
		_test_mutations()
		_test_tracks(loaded)
		_test_placement(loaded)
		_test_planforms(loaded)
		_test_director(loaded)
		_test_budget(loaded)
		_test_transitions()
		_test_preference()
		_test_scene()
	print("all %d bird checks passed" % _checks if _failures == 0 else "%d of %d bird checks failed" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BirdData.DEFAULT_PATH))


func _rejects(label: String, edit: Callable, expect: String) -> void:
	var raw: Dictionary = _raw()
	edit.call(raw)
	var r: Dictionary = BirdData.validate(raw)
	var found := false
	for e: String in r.errors:
		found = found or e.contains(expect)
	_check("rejects " + label, not r.ok and found, str(r.errors))


func _test_mutations() -> void:
	_rejects("a wrong format", func(d: Dictionary) -> void: d.format = "openrc-birds v0", "format")
	_rejects("a span in feet", func(d: Dictionary) -> void: d.species.griffon_vulture.span.unit = "ft", "unit must be 'm'")
	_rejects("a quantity without a source", func(d: Dictionary) -> void: d.species.red_kite.mass.source = " ", "source missing")
	_rejects("an unknown evidence kind", func(d: Dictionary) -> void: d.species.red_kite.mass.kind = "guessed", "kind must be")
	_rejects("an implausible span", func(d: Dictionary) -> void: d.species.barn_swallow.span.value = 9.0, "outside")
	_rejects("a burst period that does not divide 1024 s", func(d: Dictionary) -> void:
		d.species.barn_swallow.gait.burst_period.value = 3.0, "divide 1024")
	_rejects("a fork deeper than the tail", func(d: Dictionary) -> void:
		d.species.red_kite.planform.tail_fork.value = 0.5, "outside")
	_rejects("an unknown tail shape", func(d: Dictionary) -> void: d.species.red_kite.planform.tail_shape = "round", "tail_shape")
	_rejects("an unknown activity period", func(d: Dictionary) -> void: d.species.common_swift.activity.period = "night", "period")
	_rejects("a sun window that closes before it opens", func(d: Dictionary) -> void:
		d.species.common_swift.activity.sun_max.value = 1.0, "sun_max")
	_rejects("a departure without a mode", func(d: Dictionary) -> void: d.species.red_kite.departure.erase("mode"), "mode")
	_rejects("a departure that never ends", func(d: Dictionary) -> void:
		d.species.red_kite.departure.duration.value = 5000.0, "outside")
	_rejects("a departure faster than any bird", func(d: Dictionary) -> void:
		d.species.red_kite.departure.duration.value = 10.0, "faster than")
	_rejects("more birds in a group than the budget allows", func(d: Dictionary) -> void: d.flocks[3].count = 25,
		"birds, more than")
	_rejects("an unknown species in a flock", func(d: Dictionary) -> void: d.flocks[0].species = "dodo", "unknown")
	_rejects("too many birds", func(d: Dictionary) -> void: d.flocks[3].count = 500, "count")
	_rejects("a non-boolean instance flag", func(d: Dictionary) -> void: d.flocks[3].mirror_instances = "no", "true or false")
	_rejects("a circuit that does not close", func(d: Dictionary) -> void:
		d.flocks[3].tracks[0].motif[1].turn = 131.0, "does not close")
	_rejects("a circuit that ends higher than it starts", func(d: Dictionary) -> void:
		d.flocks[2].tracks[0].motif[2].climb = 20.0, "vertically")
	_rejects("a period that cannot divide 1024 s", func(d: Dictionary) -> void:
		d.flocks[0].tracks[0].motif[1].duration = 160.0, "time scale")
	_rejects("a segment with both speed and duration", func(d: Dictionary) -> void:
		d.flocks[2].tracks[0].motif[0].duration = 4.0, "exactly one of speed or duration")
	_rejects("an impossible speed hidden in a duration", func(d: Dictionary) -> void:
		d.flocks[0].tracks[0].motif[1].duration = 0.01, "m/s over")
	_rejects("a non-numeric duration", func(d: Dictionary) -> void:
		d.flocks[0].tracks[0].motif[1].duration = {}, "positive number")
	_rejects("a climb rate no bird has", func(d: Dictionary) -> void:
		d.flocks[0].tracks[0].motif[0].climb = 2000.0, "climb")
	_rejects("a repeated flock id", func(d: Dictionary) -> void: d.flocks[1].id = d.flocks[0].id, "repeated")
	var r: Dictionary = BirdData.validate("[]")
	_check("rejects a non-object root", not r.ok)


func _test_tracks(loaded: Dictionary) -> void:
	for f: Dictionary in loaded.flocks:
		var lim: Dictionary = LIMITS.get(f.id, {})
		_check("%s has measured limits in this test" % f.id, not lim.is_empty())
		if lim.is_empty():
			continue
		for ti: int in (f.tracks as Array).size():
			var track: Dictionary = f.tracks[ti]
			var name := "%s track %d" % [f.id, ti]
			var period: float = track.period
			_check(name + ": period divides 1024 s", absf(1024.0 / period - roundf(1024.0 / period)) < 1e-9, str(period))
			var gap := 0.0
			for t: float in [0.0, 3.7, period * 0.5, 811.3]:
				gap = maxf(gap, _pos(track, t).distance_to(_pos(track, t + 1024.0)))
			_check(name + ": repeats every 1024 s", gap < 1e-6, str(gap))
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			var sample := 0.0
			while sample < period:
				var q: Vector3 = _pos(track, sample)
				lo = lo.min(q)
				hi = hi.max(q)
				sample += 0.05
			var box_lo: Vector3 = track.bbox_min
			var box_hi: Vector3 = track.bbox_max
			_check(name + ": exact bounds hold every sampled position and are tight (within 0.1 m)",
				(lo - box_lo).x >= -1e-3 and (lo - box_lo).y >= -1e-3 and (lo - box_lo).z >= -1e-3 \
				and (box_hi - hi).x >= -1e-3 and (box_hi - hi).y >= -1e-3 and (box_hi - hi).z >= -1e-3 \
				and (lo - box_lo).length() < 0.1 and (box_hi - hi).length() < 0.1, "%s..%s vs %s..%s" % [box_lo, box_hi, lo, hi])
			var joints: Dictionary = _joints(track)
			_check(name + ": continuous and tangent at every joint (sampled on both sides)",
				joints.gap < 1e-4 and joints.turn < 1e-3, "gap %.7f m, turn %.7f rad" % [joints.gap, joints.turn])
			var stats: Dictionary = _stats(track)
			_check(name + ": speed in the measured range %s" % [lim.speed],
				stats.speed_min >= lim.speed[0] and stats.speed_max <= lim.speed[1], "%.2f..%.2f" % [stats.speed_min, stats.speed_max])
			_check(name + ": bank in the measured range %s" % [lim.bank],
				stats.bank_max <= lim.bank[1] and (not lim.has("circle_radius") or stats.circle_bank_min >= lim.bank[0]),
				"circles %.1f, max %.1f" % [stats.circle_bank_min, stats.bank_max])
			# Bank: exact inside a long arc (the true lateral acceleration, not the second difference's chord-shortened
			# value) and rolled smoothly across every joint.
			var interior := 0.0
			for s: Dictionary in track.segments:
				if float(s.duration) > 2.0 * BirdTracks.BANK_STEP_S + 0.2:
					var mid: float = float(s.t) + float(s.duration) * 0.5
					var exact: float = atan2(float(s.kappa) * float(s.v) * float(s.v), 9.81)
					interior = maxf(interior, absf(BirdTracks.kinematics(track, mid).bank - exact))
			var roll := 0.0
			var previous_bank: float = BirdTracks.kinematics(track, 0.0).bank
			var u := 0.05
			while u <= float(track.period):
				var bank_now: float = BirdTracks.kinematics(track, u).bank
				roll = maxf(roll, rad_to_deg(absf(bank_now - previous_bank)))
				previous_bank = bank_now
				u += 0.05
			var roll_limit: float = lim.get("roll", 2.5) # deg per 0.05 s: soarers roll slowly, swallows and swifts flick
			_check(name + ": bank exact inside arcs and rolled smoothly across joints (max %.2f of %.1f deg per 0.05 s)" % [
				roll, roll_limit], interior < 1e-9 and roll <= roll_limit, "interior error %.9f rad" % interior)
			if lim.has("circle_radius"):
				var circles: Array = _circles(track)
				var ok := not circles.is_empty()
				for c: Dictionary in circles:
					ok = ok and c.radius >= lim.circle_radius[0] and c.radius <= lim.circle_radius[1] \
						and c.turn_period >= lim.turn_period[0] and c.turn_period <= lim.turn_period[1] \
						and c.climb >= lim.climb[0] and c.climb <= lim.climb[1]
				_check(name + ": thermal circling radius, period and climb measured", ok, str(circles))


func _pos(track: Dictionary, t: float) -> Vector3:
	var p: Array[float] = BirdTracks.evaluate(track, t)
	return Vector3(p[0], p[1], p[2])


## Position gap and heading change across every joint, from positions sampled on each side (not from the segment
## tables, which share their accumulated end points by construction). Differences are taken in float64: Vector3 is
## float32 and rounds positions 800 m out to ~6e-5 m, which is noise at a 1 ms probe.
func _joints(track: Dictionary) -> Dictionary:
	var gap := 0.0
	var turn := 0.0
	var segments: Array = track.segments
	for i: int in segments.size():
		var s: Dictionary = segments[i]
		var next: Dictionary = segments[(i + 1) % segments.size()]
		var end_t: float = float(s.t) + float(s.duration)
		var d: Array[float] = _delta(track, end_t - 1e-7, end_t + 1e-7)
		gap = maxf(gap, sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]))
		var before: Array[float] = _delta(track, end_t - JOINT_PROBE_S, end_t - 1e-6)
		var after: Array[float] = _delta(track, end_t + 1e-6, end_t + JOINT_PROBE_S)
		var bend: float = absf(atan2(before[0] * after[1] - before[1] * after[0], before[0] * after[0] + before[1] * after[1]))
		# Each curved side bends by kappa * v * probe; allow that on top of the joint's own turn.
		var allowance: float = (absf(float(s.kappa)) * float(s.v) + absf(float(next.kappa)) * float(next.v)) * JOINT_PROBE_S * 2.0
		turn = maxf(turn, maxf(0.0, bend - allowance))
	return {gap = gap, turn = turn}


func _delta(track: Dictionary, t0: float, t1: float) -> Array[float]:
	var a: Array[float] = BirdTracks.evaluate(track, t0)
	var b: Array[float] = BirdTracks.evaluate(track, t1)
	return [b[0] - a[0], b[1] - a[1], b[2] - a[2]]


func _stats(track: Dictionary) -> Dictionary:
	var out := {speed_min = INF, speed_max = 0.0, bank_max = 0.0, circle_bank_min = INF}
	var t := 0.0
	while t < float(track.period):
		var k: Dictionary = BirdTracks.kinematics(track, t)
		out.speed_min = minf(out.speed_min, k.speed)
		out.speed_max = maxf(out.speed_max, k.speed)
		out.bank_max = maxf(out.bank_max, rad_to_deg(absf(k.bank)))
		t += SAMPLE_S
	for c: Dictionary in _circles(track):
		var v: float = TAU * c.radius / c.turn_period
		out.circle_bank_min = minf(out.circle_bank_min, rad_to_deg(atan(v * v / c.radius / 9.81)))
	return out


## Thermal circling segments (at least one full turn): radius, time per turn and climb rate.
func _circles(track: Dictionary) -> Array:
	var out: Array = []
	for s: Dictionary in track.segments:
		var kappa: float = absf(float(s.kappa))
		if kappa > 0.0 and float(s.v) * float(s.duration) * kappa >= TAU - 1e-9:
			out.append({radius = 1.0 / kappa, turn_period = TAU / (kappa * float(s.v)), climb = float(s.vz)})
	return out


func _group(loaded: Dictionary, group: String) -> Dictionary:
	var flocks: Array[Dictionary] = []
	var order: Array[String] = []
	var tracks: Array = []
	for f: Dictionary in loaded.flocks:
		if f.group == group:
			flocks.append(f)
			tracks.append_array(f.tracks)
			if not order.has(f.species):
				order.append(f.species)
	return {flocks = flocks, order = order, tracks = tracks, layout = Birds.instances(flocks, order)}


## Every instance's world positions over a whole circuit, on its circuit and along its way out: heights inside the
## flock's limits (on the circuit); soaring birds outside the flight box; small birds 30 m off the runway centreline
## and short of the north hedge; no bird within 30 m of the pilot.
func _test_placement(loaded: Dictionary) -> void:
	for group: String in BirdData.GROUPS:
		var g: Dictionary = _group(loaded, group)
		for index: int in (g.layout as Array).size():
			var item: Dictionary = g.layout[index]
			var track: Dictionary = g.tracks[item.track]
			var lim: Dictionary = LIMITS[item.flock]
			var away: Vector3 = Birds.departure_vector(loaded.species[g.order[item.species]], g.flocks)
			var low := INF
			var high := -INF
			var in_box := false
			var near_pilot := false
			var off_runway := true
			var near_hedge := false
			var t := 0.0
			while t < float(track.period):
				var p: Vector3 = _pos(track, t)
				var on_circuit: Vector3 = item.transform * Vector3(p.x, p.z, -p.y)
				low = minf(low, on_circuit.y)
				high = maxf(high, on_circuit.y)
				for share: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var w: Vector3 = on_circuit + away * share
					var north: float = -w.z
					var east: float = w.x
					in_box = in_box or (north >= 0.0 and north <= FLIGHT_BOX_NORTH_M and absf(east) <= FLIGHT_BOX_HALF_WIDTH_M \
						and w.y <= FLIGHT_BOX_TOP_M)
					near_pilot = near_pilot or Vector2(north, east).length() < 30.0
					if share == 0.0:
						off_runway = off_runway and absf(north - RUNWAY_CENTRE_NORTH_M) >= 30.0
						near_hedge = near_hedge or north > 230.0
				t += SAMPLE_S * 4.0
			var who := "%s bird %d" % [item.flock, index]
			_check(who + ": height %.1f..%.1f m within %s m" % [low, high, lim.height],
				low >= lim.height[0] and high <= lim.height[1])
			_check(who + ": never within 30 m of the pilot, on its circuit or leaving", not near_pilot)
			if group == "soaring" or item.flock == "swift_party":
				_check(who + ": stays outside the flight box, on its circuit or leaving", not in_box)
			else:
				_check(who + ": 30 m or more from the runway centreline, short of the hedge", off_runway and not near_hedge)
			_check(who + ": offset and hash exact in a half float", item.offset == roundf(item.offset * 2.0) * 0.5 \
				and item.offset < 1024.0 and item.hash == floorf(item.hash * 1024.0) / 1024.0 and item.hash < 1.0)


func _test_planforms(loaded: Dictionary) -> void:
	for group: String in BirdData.GROUPS:
		var g: Dictionary = _group(loaded, group)
		var slots := 0
		for id: String in g.order:
			slots = maxi(slots, int(loaded.species[id].planform.fingers))
		var builds: Array = []
		for id: String in g.order:
			var s: Dictionary = loaded.species[id]
			var b: Dictionary = BirdPlanform.build(s.planform, s.span, slots)
			builds.append(b)
			var reach := 0.0
			var rig_gate_ok := true
			var mirrored := true
			var lookup: Dictionary = {}
			for v: Vector3 in b.vertices:
				lookup[Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))] = true
			for i: int in b.vertices.size():
				var v: Vector3 = b.vertices[i]
				var w: Array[float] = BirdPlanform.unpack_weight(b.weights[i])
				var part: int = b.parts[i]
				reach = maxf(reach, absf(v.x))
				# sky_birds.gdshader rigs vertices outboard of the shoulder with no tail weight as wing: exactly the
				# wing's outboard vertices; hand only outboard of the wrist; tail weight only behind the tail root.
				var rigged: bool = absf(v.x) > b.rig.x + 1e-5 and w[1] == 0.0
				rig_gate_ok = rig_gate_ok and rigged == (part == BirdPlanform.PART_WING and absf(v.x) > b.rig.x + 1e-5) \
					and (w[0] == 0.0 or (part == BirdPlanform.PART_WING and absf(v.x) > b.rig.y)) \
					and (w[1] == 0.0 or (part == BirdPlanform.PART_TAIL and v.z < b.rig.z)) and w[1] <= 1.0
				mirrored = mirrored and lookup.has(Vector3i(roundi(-v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5)))
			_check("%s silhouette spans %.2f m" % [id, s.span], absf(reach * 2.0 - float(s.span)) < 1e-6, str(reach * 2.0))
			_check("%s: the shader's wing rig moves exactly the wing; hand and tail weights where they belong" % id, rig_gate_ok)
			_check("%s silhouette is left-right symmetric" % id, mirrored)
		var same := true
		for b: Dictionary in builds:
			same = same and b.triangles == builds[0].triangles and b.parts == builds[0].parts
		_check("%s: every species shares one topology (%d triangles)" % [group, builds[0].triangles], same)
		var mesh: ArrayMesh = BirdPlanform.group_mesh(builds)
		var arrays: Array = mesh.surface_get_arrays(0)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var shapes_ok: bool = indices.size() == builds[0].vertices.size()
		for slot: int in BirdPlanform.MAX_SPECIES:
			var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0 + slot]
			var b: Dictionary = builds[slot] if slot < builds.size() else builds[0]
			for i: int in b.vertices.size():
				var j: int = indices[i]
				shapes_ok = shapes_ok and Vector3(custom[j * 4], custom[j * 4 + 1], custom[j * 4 + 2]) == b.vertices[i] \
					and custom[j * 4 + 3] == b.weights[i] and (arrays[Mesh.ARRAY_TEX_UV][j] as Vector2).y == builds[0].shades[i]
		var unique: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		_check("%s: indexed mesh, every corner keeps each species' shape, rig weights and shade (%d vertices for %d corners)" % [
			group, unique, indices.size()], shapes_ok and unique < indices.size())


func _snapshot(local_hour: float) -> Dictionary:
	var config: Dictionary = LightingConfig.defaults()
	config.mode = "astronomical"
	config.local_seconds = int(local_hour * 3600.0)
	var validated: Dictionary = LightingConfig.validate(config)
	return Lighting.snapshot(validated.config)


func _shares(loaded: Dictionary, lighting: Dictionary, quality := "high", clouds := 0.2) -> Dictionary:
	var c: Dictionary = BirdDirector.conditions(lighting, quality, clouds)
	var out := {}
	for id: String in loaded.species:
		out[id] = snappedf(BirdDirector.activity(loaded.species[id], c), 0.001)
	return out


func _test_director(loaded: Dictionary) -> void:
	var night: Dictionary = Lighting.snapshot(LightingConfig.preset(LightingConfig.defaults(), "night").config)
	var dawn: Dictionary = Lighting.snapshot(LightingConfig.preset(LightingConfig.defaults(), "dawn").config)
	for pair: Array in [["night", night], ["dawn", dawn]]:
		var s: Dictionary = _shares(loaded, pair[1])
		_check("%s snapshot (sky clamp %.2f deg, sun %.1f deg): no species out" % [pair[0],
			float(pair[1].sun_elevation_deg), BirdDirector.sun_elevation_deg(pair[1])], s.values().max() == 0.0, str(s))
	var noon: Dictionary = _shares(loaded, _snapshot(12.0))
	_check("noon: vultures, storks, kites and swallows out; no swifts", noon.griffon_vulture == 1.0 and noon.white_stork == 1.0 \
		and noon.red_kite == 1.0 and noon.barn_swallow == 1.0 and noon.common_swift == 0.0, str(noon))
	var evening_light: Dictionary = _snapshot(17.8)
	var evening: Dictionary = _shares(loaded, evening_light)
	_check("evening (sun %.1f deg, afternoon): swifts and swallows out; no vultures" % BirdDirector.sun_elevation_deg(evening_light),
		evening.common_swift > 0.9 and evening.barn_swallow > 0.9 and evening.griffon_vulture == 0.0, str(evening))
	var evening_sun: float = BirdDirector.sun_elevation_deg(evening_light)
	var morning_light: Dictionary = {}
	var hour := 5.5
	while hour < 9.0 and morning_light.is_empty(): # the morning hour with the same sun as the evening one
		var candidate: Dictionary = _snapshot(hour)
		if BirdDirector.sun_elevation_deg(candidate) >= evening_sun:
			morning_light = candidate
		hour += 0.01
	var morning: Dictionary = _shares(loaded, morning_light)
	_check("morning at the same sun (%.1f deg): no evening swifts" % BirdDirector.sun_elevation_deg(morning_light),
		morning.common_swift == 0.0 and morning.barn_swallow > 0.9, str(morning))
	var overcast: Dictionary = _shares(loaded, _snapshot(12.0), "high", 0.95)
	_check("overcast noon: no thermals, so no vultures or storks; kites and swallows still out",
		overcast.griffon_vulture == 0.0 and overcast.white_stork == 0.0 and overcast.red_kite == 1.0, str(overcast))
	var low: Dictionary = _shares(loaded, _snapshot(12.0), "low")
	_check("low scene detail halves each species' share", low.griffon_vulture == 0.5 and low.barn_swallow == 0.5, str(low))
	var high_birds: Node3D = Birds.build(_snapshot(12.0), "high")
	var low_birds: Node3D = Birds.build(_snapshot(12.0), "low")
	var drawn_high: int = Birds.drawn(high_birds).values().reduce(func(a: int, b: int) -> int: return a + b)
	var drawn_low: int = Birds.drawn(low_birds).values().reduce(func(a: int, b: int) -> int: return a + b)
	_check("low scene detail draws about half the birds at noon (%d of %d)" % [drawn_low, drawn_high],
		drawn_low >= roundi(drawn_high * 0.35) and drawn_low <= roundi(drawn_high * 0.65))
	high_birds.free()
	low_birds.free()


## Drawn primitives over a whole day: birds out at a sun elevation, plus those still on their way in or out from the
## sun elevations a transition can span, never exceed the scenery_Birds budget.
func _test_budget(loaded: Dictionary) -> void:
	var worst := 0
	var worst_at := ""
	var groups: Array[Dictionary] = []
	for group: String in BirdData.GROUPS:
		var g: Dictionary = _group(loaded, group)
		var slots := 0
		for id: String in g.order:
			slots = maxi(slots, int(loaded.species[id].planform.fingers))
		var s: Dictionary = loaded.species[g.order[0]]
		g.triangles = BirdPlanform.build(s.planform, s.span, slots).triangles
		groups.append(g)
	for afternoon: bool in [false, true]:
		for clouds: float in [0.0, 0.7, 0.95]:
			var sun := -20.0
			while sun <= 90.0:
				var total := 0
				for g: Dictionary in groups:
					var drawn := 0
					for item: Dictionary in g.layout:
						var s: Dictionary = loaded.species[g.order[item.species]]
						var out := false
						for d: float in [-SUN_PER_TRANSITION_DEG, 0.0, SUN_PER_TRANSITION_DEG]:
							var c := {sun_deg = sun + d, afternoon = afternoon, clouds = clouds, density = 1.0}
							out = out or float(item.hash) < BirdDirector.activity(s, c)
						drawn += 1 if out else 0
					total += drawn * int(g.triangles)
				if total > worst:
					worst = total
					worst_at = "sun %.1f deg, %s, clouds %.2f" % [sun, "afternoon" if afternoon else "morning", clouds]
				sun += 0.25
	_check("drawn birds stay within %d primitives all day, transitions included (worst %d at %s)" % [BUDGET_PRIMITIVES,
		worst, worst_at], worst <= BUDGET_PRIMITIVES)


func _test_transitions() -> void:
	var duration := 60.0
	# A bird out, told to leave at clock 100, told to come back at 120, then left alone.
	var state: float = Birds.STEADY
	var previous := 0.0
	var worst_step := 0.0
	var clock := 100.0
	state = Birds.next_state(state, false, clock, duration)
	_check("a flying bird starts leaving at the nearest half-second", state == 100.0, str(state))
	while clock < 300.0:
		if absf(clock - 120.0) < 0.05:
			state = Birds.next_state(state, true, clock, duration)
		var share: float = Birds.departure_share(state, fposmod(clock, 1024.0), duration)
		worst_step = maxf(worst_step, absf(share - previous))
		previous = share
		clock += 0.1
	_check("leaving and turning back is continuous (largest step %.4f of the way per 0.1 s)" % worst_step, worst_step < 0.008)
	_check("after turning back it is fully home", Birds.departure_share(state, 300.0, duration) == 0.0)
	# Starts on any fraction of a second, also just before the wrap: rounding may put the start a moment ahead, which
	# must wait at 0, never read as finished (a pop).
	var starts_ok := true
	for start_clock: float in [100.0, 100.2, 100.3, 100.8, 511.6, 1023.8]:
		for want: bool in [false, true]:
			var s: float = Birds.next_state(Birds.HIDDEN if want else Birds.STEADY, want, start_clock, duration)
			var away_now: float = Birds.departure_share(s, start_clock, duration)
			var away_later: float = Birds.departure_share(s, fposmod(start_clock + 10.0, 1024.0), duration)
			var expected_now := 1.0 if want else 0.0
			starts_ok = starts_ok and absf(away_now - expected_now) < 0.01 and absf(away_later - expected_now) > 0.01 \
				and absf(away_later - expected_now) < 0.2 and s == roundf(s * 2.0) * 0.5
	_check("transitions started on any fraction of a second ease in (no pop), also at the clock wrap", starts_ok)
	var root_birds: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	# A small sun step animates; every bird that leaves starts at its circuit.
	ShaderClock.update(200.3)
	Birds.apply_lighting(root_birds, {sun_elevation_deg = 43.5, sun_azimuth_deg = 182.0}, true, 0.95)
	var leaving_ok := Birds.pending(root_birds)
	for node: MultiMeshInstance3D in root_birds.get_meta("bird_groups"):
		var species: Array = node.get_meta("species_data")
		var layout: Array = node.get_meta("instances")
		var states: PackedFloat32Array = node.get_meta("states")
		for i: int in layout.size():
			if states[i] == Birds.HIDDEN:
				continue # already away before the clouds came (the evening swifts)
			var d: float = species[layout[i].species].departure.duration
			leaving_ok = leaving_ok and Birds.departure_share(states[i], ShaderClock.last_clock, d) < 0.01
	_check("clouds coming over: soarers start leaving from their circuits, none vanishes at once", leaving_ok)
	ShaderClock.update(200.3 + 151.0)
	Birds.settle(root_birds, ShaderClock.last_clock)
	_check("after the longest departure the leavers are away and cost nothing",
		not Birds.pending(root_birds) and Birds.drawn(root_birds).Birds_soaring == 2, str(Birds.drawn(root_birds)))
	# A jump of the time of day (paused edit, restore) snaps and stays within the budget.
	Birds.apply_lighting(root_birds, {sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0}, true, 0.2)
	Birds.apply_lighting(root_birds, _snapshot(17.8), true, 0.2)
	_check("noon to evening in one step snaps (no transitions) within %d primitives (%d)" % [Birds.DRAWN_PRIMITIVE_LIMIT,
		Birds.drawn_primitives(root_birds)], not Birds.pending(root_birds) \
		and Birds.drawn_primitives(root_birds) <= Birds.DRAWN_PRIMITIVE_LIMIT)
	# Flowing time: the runtime follows Atmosphere.state without a lighting commit.
	var saved_state: Dictionary = Atmosphere.state
	Atmosphere.state = {sun_elevation_deg = 4.0, sun_azimuth_deg = 265.0}
	root_birds.call("poll")
	Atmosphere.state = {sun_elevation_deg = 40.0, sun_azimuth_deg = 200.0}
	var followed: bool = root_birds.call("poll")
	ShaderClock.update(1000.0)
	for i: int in 3:
		root_birds.call("poll")
	_check("flowing time: the birds follow the flow state's sun (swifts gone at 40 deg)", followed \
		and float((root_birds.get_meta("conditions") as Dictionary).sun_deg) == 40.0)
	Atmosphere.state = saved_state
	# The wrap: a finished arrival must not replay 1024 s later; settle() makes it STEADY.
	Birds.apply_lighting(root_birds, {sun_elevation_deg = 44.0, sun_azimuth_deg = 180.0}, true, 0.2)
	ShaderClock.update(fposmod(1000.0 + 151.0, 1024.0))
	Birds.settle(root_birds, ShaderClock.last_clock)
	var states_ok := true
	for node: MultiMeshInstance3D in root_birds.get_meta("bird_groups"):
		for s: float in node.get_meta("states"):
			states_ok = states_ok and (s == Birds.STEADY or s == Birds.HIDDEN)
	_check("transitions settle to flying or away, so nothing replays when the clock wraps", states_ok \
		and not Birds.pending(root_birds))
	root_birds.free()
	ShaderClock.update(100.0)


## Settings → Graphics → Birds: saved in display.cfg, mirrored levels, density per tier, applied live by the runtime.
func _test_preference() -> void:
	_check("the saved Birds levels mirror the director's", DisplayPreferences.BIRD_LEVELS == BirdDirector.PREFERENCES
		and DisplayPreferences.DEFAULTS.birds == BirdDirector.DEFAULT_PREFERENCE)
	var path := "user://test_birds_display.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var config: Dictionary = DisplayPreferences.load_from(path)
	_check("a new or old display.cfg means Normal birds", config.birds == "normal")
	config.birds = "few"
	_check("Few saves and loads back", DisplayPreferences.save_to(path, config) == OK and DisplayPreferences.load_from(path).birds == "few")
	var invalid: Dictionary = config.duplicate()
	invalid.birds = "flocks"
	_check("an unknown Birds level is refused", not DisplayPreferences.validate(invalid).ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_check("density per level and tier: off 0, few half, normal the tier, many full",
		BirdDirector.density("off", "high") == 0.0 and BirdDirector.density("few", "high") == 0.5
		and BirdDirector.density("normal", "low") == 0.5 and BirdDirector.density("many", "low") == 1.0
		and BirdDirector.density("normal", "balanced") == 0.75)
	BirdDirector.set_preference("normal")
	var serial: int = BirdDirector.preference_serial
	BirdDirector.set_preference("normal")
	_check("choosing the current level changes nothing", BirdDirector.preference_serial == serial)
	BirdDirector.set_preference("dodos")
	_check("an unknown level falls back to Normal", BirdDirector.preference == "normal")
	ShaderClock.update(300.0)
	var noon := {sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0}
	var birds: Node3D = Birds.build(noon)
	var flying: int = _drawn_total(birds)
	BirdDirector.set_preference("off")
	birds.call("poll")
	_check("Off applies at once: every bird starts leaving (none vanishes)", Birds.pending(birds) and _drawn_total(birds) == flying)
	ShaderClock.update(300.0 + 151.0)
	birds.call("poll")
	_check("…and once they have left, nothing is drawn", _drawn_total(birds) == 0 and not Birds.pending(birds))
	BirdDirector.set_preference("many")
	birds.call("poll")
	ShaderClock.update(451.0 + 151.0)
	birds.call("poll")
	_check("Many brings the noon birds back (%d of %d)" % [_drawn_total(birds), flying], _drawn_total(birds) == flying)
	BirdDirector.set_preference("off")
	birds.call("poll")
	for i: int in 31: # Home's fixed clock, or a paused flight
		birds.call("poll")
	_check("with the clock standing still (Home, pause) a change settles at once", _drawn_total(birds) == 0
		and not Birds.pending(birds), str(Birds.drawn(birds)))
	birds.free()
	BirdDirector.set_preference("off")
	var off_built: Node3D = Birds.build(noon)
	_check("built while Off: the layer exists but draws nothing", off_built != null and _drawn_total(off_built) == 0)
	off_built.free()
	BirdDirector.set_preference("few")
	var few_built: Node3D = Birds.build(noon, "high")
	_check("Few at High draws about half the noon birds (%d of %d)" % [_drawn_total(few_built), flying],
		_drawn_total(few_built) >= roundi(flying * 0.3) and _drawn_total(few_built) <= roundi(flying * 0.7))
	few_built.free()
	BirdDirector.set_preference("normal")
	ShaderClock.update(100.0)


func _drawn_total(node: Node3D) -> int:
	var total := 0
	for count: int in Birds.drawn(node).values():
		total += count
	return total


func _test_scene() -> void:
	var noon: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	_check("builds the Birds node", noon != null and noon.name == Birds.NODE_NAME)
	if noon == null:
		return
	var primitives := 0
	var draws := 0
	var names: Array[String] = []
	var aabb_ok := true
	for node: MultiMeshInstance3D in noon.get_meta("bird_groups"):
		var mm: MultiMesh = node.multimesh
		draws += 1 if mm.visible_instance_count > 0 else 0
		names.append(str(node.name))
		primitives += mm.visible_instance_count * floori(mm.mesh.get_faces().size() / 3.0)
		var tracks: Array = node.get_meta("tracks")
		var species: Array = node.get_meta("species_data")
		for item: Dictionary in node.get_meta("instances"):
			var track: Dictionary = tracks[item.track]
			var away: Vector3 = Birds.departure_vector(species[item.species], _flocks_of(node))
			var t := 0.0
			while t < float(track.period):
				var p: Vector3 = _pos(track, t)
				var w: Vector3 = item.transform * Vector3(p.x, p.z, -p.y)
				aabb_ok = aabb_ok and node.custom_aabb.has_point(w) and node.custom_aabb.has_point(w + away)
				t += 2.0
		_check("%s: shadow casting off" % node.name, node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_check_shader_tables(node)
		_check_species_uniforms(node)
	_check("one MultiMesh per group %s" % [names], names == ["Birds_soaring", "Birds_small"], str(names))
	_check("noon within the scenery_Birds budget (%d primitives, %d draws)" % [BUDGET_PRIMITIVES, BUDGET_DRAWS],
		primitives <= BUDGET_PRIMITIVES and draws <= BUDGET_DRAWS, "%d primitives, %d draws" % [primitives, draws])
	_check("every bird stays inside its culling box on its circuit and on its way out (no pop-out)", aabb_ok)
	var again: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	_check("build is deterministic (instances, meshes, culling boxes and every shader table, byte for byte)",
		not _signature(noon).is_empty() and _signature(again) == _signature(noon))
	_check("invalid data builds nothing", Birds.build({}, "high", "res://data/scenery/birds/missing.json") == null)
	noon.free()
	again.free()


func _flocks_of(node: MultiMeshInstance3D) -> Array[Dictionary]:
	var loaded: Dictionary = BirdData.load_from()
	var out: Array[Dictionary] = []
	var group: String = str(node.name).trim_prefix("Birds_")
	for f: Dictionary in loaded.flocks:
		if f.group == group:
			out.append(f)
	return out


## The group's real shader tables (as birds.gd packs them: several flocks per group, offset first segments), checked
## against the float64 reference over the shader's whole time range (sim_clock + offset < 2048 s).
func _check_shader_tables(node: MultiMeshInstance3D) -> void:
	var material := node.material_override as ShaderMaterial
	var packed := {seg_a = material.get_shader_parameter("seg_a"), seg_b = material.get_shader_parameter("seg_b"),
		track_info = material.get_shader_parameter("track_info")}
	var tracks: Array = node.get_meta("tracks")
	var worst := 0.0
	for ti: int in tracks.size():
		var t := 0.0
		while t < 2048.0:
			worst = maxf(worst, _pos(tracks[ti], t).distance_to(_shader_track_pos(packed, ti, t)))
			t += 1.7
	_check("%s: float32 shader tables within 5 cm of the float64 tracks over 0-2048 s" % node.name, worst < 0.05,
		"%.4f m" % worst)
	var worst_lateral := 0.0
	for ti: int in tracks.size():
		var t := 0.0
		while t < 1024.0:
			var tt: float = fposmod(t, float(tracks[ti].period))
			worst_lateral = maxf(worst_lateral, absf(BirdTracks.lateral_acceleration(tracks[ti], tt) \
				- _shader_lateral(packed, ti, tt)))
			t += 0.37
	_check("%s: the shader's smoothed lateral acceleration matches the float64 reference (%.5f m/s2)" % [node.name,
		worst_lateral], worst_lateral < 0.01)


## Every per-species uniform holds that species' data (a list of packed arrays would fill copies and leave zeros).
func _check_species_uniforms(node: MultiMeshInstance3D) -> void:
	var material := node.material_override as ShaderMaterial
	var species: Array = node.get_meta("species_data")
	var ok := true
	for i: int in species.size():
		var s: Dictionary = species[i]
		for pair: Array in [["color_top", s.colors.top], ["color_under", s.colors.under], ["color_tip", s.colors.tip]]:
			var c: Color = pair[1]
			ok = ok and (material.get_shader_parameter(pair[0]) as PackedVector4Array)[i].is_equal_approx(Vector4(c.r, c.g, c.b, 1.0))
		var g: Dictionary = s.gait
		ok = ok and is_equal_approx((material.get_shader_parameter("gait_a") as PackedVector4Array)[i].x, g.flap_frequency_clock) \
			and is_equal_approx((material.get_shader_parameter("gait_c") as PackedVector4Array)[i].z, s.departure.duration) \
			and is_equal_approx((material.get_shader_parameter("rig") as PackedVector4Array)[i].w, float(s.span) * 0.5)
	_check("%s: colour, gait, departure and rig uniforms hold each species' data" % node.name, ok)


## GDScript copy of sky_birds.gdshader track_segment(): the repeat directly, then its motif (float32 tables).
func _shader_segment(packed: Dictionary, info: Vector4, tt: float) -> int:
	var repeats: int = int(info.w + 0.5)
	@warning_ignore("integer_division")
	var motif: int = int(info.y + 0.5) / repeats
	var base: int = int(info.x + 0.5) + mini(int(tt / (info.z / float(repeats))), repeats - 1) * motif
	var index: int = base
	for i: int in range(1, 16):
		if i >= motif or packed.seg_a[base + i].w > tt:
			break
		index = base + i
	return index


## GDScript copy of sky_birds.gdshader smoothed_lateral() (float32 tables, same loop).
func _shader_lateral(packed: Dictionary, track: int, tt: float) -> float:
	var info: Vector4 = packed.track_info[track]
	var first: int = int(info.x + 0.5)
	var count: int = int(info.y + 0.5)
	var period: float = info.z
	var h: float = BirdTracks.BANK_STEP_S
	var w0: float = tt - h
	var w1: float = tt + h
	var offset: float = -period if w0 < 0.0 else 0.0
	var index: int = _shader_segment(packed, info, w0 - offset)
	var lateral := 0.0
	for k: int in 8:
		var last: int = first + count - 1
		var start: float = packed.seg_a[index].w + offset
		var end: float = (packed.seg_a[index + 1].w if index < last else period) + offset
		var b: Vector4 = packed.seg_b[index]
		var lo: float = maxf(start, w0)
		var hi: float = minf(end, w1)
		if hi > lo:
			lateral += b.x * b.y * b.y * (BirdTracks._kernel_cdf(hi - tt) - BirdTracks._kernel_cdf(lo - tt))
		if end >= w1:
			break
		if index == last:
			index = first
			offset += period
		else:
			index += 1
	return lateral


## GDScript copy of sky_birds.gdshader segment lookup and segment_pos() (float32 tables, same branch structure).
func _shader_track_pos(packed: Dictionary, track: int, t: float) -> Vector3:
	var info: Vector4 = packed.track_info[track]
	var tt: float = fposmod(t, info.z)
	var index: int = _shader_segment(packed, info, tt)
	var a: Vector4 = packed.seg_a[index]
	var b: Vector4 = packed.seg_b[index]
	var d: float = tt - a.w
	var s: float = b.y * d
	var p: Vector2
	if absf(b.x) < 1e-7:
		p = Vector2(a.x, a.y) + s * Vector2(cos(a.z), sin(a.z))
	else:
		var h: float = a.z + b.x * s
		p = Vector2(a.x, a.y) + Vector2(sin(h) - sin(a.z), cos(a.z) - cos(h)) / b.x
	return Vector3(p.x, p.y, b.z + b.w * d)


func _signature(node: Node3D) -> PackedByteArray:
	var parts: Array = []
	for mmi: MultiMeshInstance3D in node.get_meta("bird_groups"):
		var material := mmi.material_override as ShaderMaterial
		var uniforms: Array = []
		for uniform: String in ["seg_a", "seg_b", "track_info", "gait_a", "gait_b", "gait_c", "rig", "color_top",
				"color_under", "color_tip", "depart"]:
			uniforms.append(material.get_shader_parameter(uniform))
		parts.append([mmi.multimesh.buffer, mmi.multimesh.visible_instance_count, mmi.multimesh.mesh.surface_get_arrays(0),
			mmi.custom_aabb, uniforms])
	return var_to_bytes(parts) if parts.size() == 2 else PackedByteArray()
