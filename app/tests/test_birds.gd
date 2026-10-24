# SC-BIRD-02…05 (docs/plans/birds-sky-life.md): the bird data validates and rejects bad edits, every circuit closes,
# repeats on the 1024 s shader clock and flies inside the measured ranges (SC-BIRD-00 section 4), every bird keeps out
# of the flight box and away from the pilot at its real (instance) height, the silhouettes are true-size and rigged so
# the shader's wing rig never touches the tail, the shader's float32 tables follow the float64 reference over the
# shader's whole time range, the layer fits the scenery_Birds budget, and real time-of-day snapshots decide which
# species are out (night snapshots clamp sun_elevation_deg, so the true solar elevation must be read).
# Run: python3 tools/godot/run_checked.py --timeout 90 -- "$(app/get-godot.sh)" --headless --path app --script res://tests/test_birds.gd
extends SceneTree

const BirdData = preload("res://scenery/birds/bird_data.gd")
const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")
const BirdPlanform = preload("res://scenery/birds/bird_planform.gd")
const Birds = preload("res://scenery/birds.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const Lighting = preload("res://render/time_of_day_lighting.gd")

const BUDGET_PRIMITIVES := 1000 # tools/scenery/scene_budget.json scenery_Birds (every view class)
const BUDGET_DRAWS := 2
const FLIGHT_BOX_NORTH_M := 229.0 # scenery profile: AMA sport field depth and half width
const FLIGHT_BOX_HALF_WIDTH_M := 305.0
const FLIGHT_BOX_TOP_M := 150.0
const RUNWAY_CENTRE_NORTH_M := 15.0
const TREE_TOP_M := 25.0 # render/treeline.gd identity(): 12-25 m
const SAMPLE_S := 0.5
const JOINT_PROBE_S := 1e-3

# Measured ranges (SC-BIRD-00 section 4): speed (m/s), bank (deg), world height of every bird (m), circling.
const LIMITS := {
	"vulture_kettle": {speed = [8.0, 14.5], bank = [16.0, 35.0], height = [85.0, 160.0], circle_radius = [16.0, 30.0],
		turn_period = [10.0, 19.5], climb = [0.04, 2.08]},
	"kite_quartering": {speed = [5.5, 9.0], bank = [0.0, 27.0], height = [TREE_TOP_M + 8.0, 70.0],
		circle_radius = [8.1, 16.0], turn_period = [8.0, 16.0], climb = [0.09, 2.0]},
	"swallow_coursing": {speed = [6.0, 12.5], bank = [0.0, 60.0], height = [0.25, 4.1]},
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
	var loaded: Dictionary = BirdData.load_from()
	_check("bundled birds.json validates", loaded.ok, str(loaded.get("errors", [])))
	if loaded.ok:
		_test_mutations()
		_test_tracks(loaded)
		_test_placement(loaded)
		_test_planforms(loaded)
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
	_rejects("an unknown species in a flock", func(d: Dictionary) -> void: d.flocks[0].species = "dodo", "unknown")
	_rejects("too many birds", func(d: Dictionary) -> void: d.flocks[2].count = 500, "count")
	_rejects("a non-boolean instance flag", func(d: Dictionary) -> void: d.flocks[2].mirror_instances = "no", "true or false")
	_rejects("a circuit that does not close", func(d: Dictionary) -> void:
		d.flocks[2].tracks[0].motif[1].turn = 131.0, "does not close")
	_rejects("a circuit that ends higher than it starts", func(d: Dictionary) -> void:
		d.flocks[1].tracks[0].motif[2].climb = 20.0, "vertically")
	_rejects("a period that cannot divide 1024 s", func(d: Dictionary) -> void:
		d.flocks[0].tracks[0].motif[1].duration = 160.0, "time scale")
	_rejects("a segment with both speed and duration", func(d: Dictionary) -> void:
		d.flocks[1].tracks[0].motif[0].duration = 4.0, "exactly one of speed or duration")
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
			var joints: Dictionary = _joints(track)
			_check(name + ": continuous and tangent at every joint (sampled on both sides)",
				joints.gap < 1e-4 and joints.turn < 1e-3, "gap %.7f m, turn %.7f rad" % [joints.gap, joints.turn])
			var stats: Dictionary = _stats(track)
			_check(name + ": speed in the measured range %s" % [lim.speed],
				stats.speed_min >= lim.speed[0] and stats.speed_max <= lim.speed[1], "%.2f..%.2f" % [stats.speed_min, stats.speed_max])
			_check(name + ": bank in the measured range %s" % [lim.bank],
				stats.bank_max <= lim.bank[1] and (not lim.has("circle_radius") or stats.circle_bank_min >= lim.bank[0]),
				"circles %.1f, max %.1f" % [stats.circle_bank_min, stats.bank_max])
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
	for s: Dictionary in track.segments:
		var end_t: float = float(s.t) + float(s.duration)
		var d: Array[float] = _delta(track, end_t - 1e-7, end_t + 1e-7)
		gap = maxf(gap, sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]))
		var before: Array[float] = _delta(track, end_t - JOINT_PROBE_S, end_t - 1e-6)
		var after: Array[float] = _delta(track, end_t + 1e-6, end_t + JOINT_PROBE_S)
		var bend: float = absf(atan2(before[0] * after[1] - before[1] * after[0], before[0] * after[0] + before[1] * after[1]))
		# A curved side bends by kappa * v * probe; allow that much on top of the joint's own turn.
		var allowance: float = absf(float(s.kappa)) * float(s.v) * JOINT_PROBE_S * 2.0
		turn = maxf(turn, maxf(0.0, bend - allowance - _next_bend(track, s)))
	return {gap = gap, turn = turn}


func _delta(track: Dictionary, t0: float, t1: float) -> Array[float]:
	var a: Array[float] = BirdTracks.evaluate(track, t0)
	var b: Array[float] = BirdTracks.evaluate(track, t1)
	return [b[0] - a[0], b[1] - a[1], b[2] - a[2]]


func _next_bend(track: Dictionary, s: Dictionary) -> float:
	var segments: Array = track.segments
	var next: Dictionary = segments[(segments.find(s) + 1) % segments.size()]
	return absf(float(next.kappa)) * float(next.v) * JOINT_PROBE_S * 2.0


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


## Every instance's world positions, over a whole circuit and with its own transform and offsets: heights inside the
## flock's limits; soaring birds outside the flight box; small birds 30 m off the runway centreline and short of the
## north hedge; no bird within 30 m of the pilot.
func _test_placement(loaded: Dictionary) -> void:
	for group: String in BirdData.GROUPS:
		var flocks: Array[Dictionary] = []
		var order: Array[String] = []
		var tracks: Array = []
		for f: Dictionary in loaded.flocks:
			if f.group == group:
				flocks.append(f)
				tracks.append_array(f.tracks)
				if not order.has(f.species):
					order.append(f.species)
		var layout: Array[Dictionary] = Birds.instances(flocks, order)
		for index: int in layout.size():
			var item: Dictionary = layout[index]
			var track: Dictionary = tracks[item.track]
			var lim: Dictionary = LIMITS[item.flock]
			var low := INF
			var high := -INF
			var in_box := false
			var near_pilot := false
			var off_runway := true
			var near_hedge := false
			var t := 0.0
			while t < float(track.period):
				var p: Vector3 = _pos(track, t)
				var w: Vector3 = item.transform * Vector3(p.x, p.z, -p.y)
				var north: float = -w.z
				var east: float = w.x
				low = minf(low, w.y)
				high = maxf(high, w.y)
				in_box = in_box or (north >= 0.0 and north <= FLIGHT_BOX_NORTH_M and absf(east) <= FLIGHT_BOX_HALF_WIDTH_M \
					and w.y <= FLIGHT_BOX_TOP_M)
				near_pilot = near_pilot or Vector2(north, east).length() < 30.0
				off_runway = off_runway and absf(north - RUNWAY_CENTRE_NORTH_M) >= 30.0
				near_hedge = near_hedge or north > 230.0
				t += SAMPLE_S
			var who := "%s bird %d" % [item.flock, index]
			_check(who + ": height %.1f..%.1f m within %s m" % [low, high, lim.height],
				low >= lim.height[0] and high <= lim.height[1])
			_check(who + ": never within 30 m of the pilot", not near_pilot)
			if group == "soaring":
				_check(who + ": stays outside the flight box", not in_box)
			else:
				_check(who + ": 30 m or more from the runway centreline, short of the hedge", off_runway and not near_hedge)
			var c: Color = item.custom
			_check(who + ": offset and hash exact in a half float", c.r == roundf(c.r * 2.0) * 0.5 and c.r < 1024.0 \
				and c.a == floorf(c.a * 1024.0) / 1024.0 and c.a < 1.0)


func _test_planforms(loaded: Dictionary) -> void:
	var expected := {griffon_vulture = 34, red_kite = 31, barn_swallow = 19}
	for id: String in loaded.species:
		var s: Dictionary = loaded.species[id]
		var b: Dictionary = BirdPlanform.build(s.planform, s.span)
		_check("%s silhouette has %d triangles" % [id, expected.get(id, -1)], b.triangles == expected.get(id, -1), str(b.triangles))
		var reach := 0.0
		var weights_ok := true
		var rig_gate_ok := true
		var mirrored := true
		var lookup: Dictionary = {}
		for v: Vector3 in b.vertices:
			lookup[Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))] = true
		for i: int in b.vertices.size():
			var v: Vector3 = b.vertices[i]
			var c: Color = b.colors[i]
			var part: int = b.parts[i]
			reach = maxf(reach, absf(v.x))
			weights_ok = weights_ok and c.r >= 0.0 and c.r <= 1.0 and c.b >= 0.0 and c.b <= 1.0 and c.a == 1.0 \
				and (c.g == 0.0 or absf(v.x) > b.rig.y) and (c.b == 0.0 or v.z < b.rig.z)
			# sky_birds.gdshader rigs vertices outboard of the shoulder with COLOR.b == 0 as wing: that must be exactly
			# the wing's outboard vertices (8-bit vertex colour keeps 0 exact and every tail weight above 1/255).
			var rigged: bool = absf(v.x) > b.rig.x + 1e-5 and c.b == 0.0
			rig_gate_ok = rig_gate_ok and (rigged == (part == BirdPlanform.PART_WING and absf(v.x) > b.rig.x + 1e-5)) \
				and (part != BirdPlanform.PART_TAIL or c.b == 0.0 or c.b >= 1.0 / 255.0)
			mirrored = mirrored and lookup.has(Vector3i(roundi(-v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5)))
		_check("%s silhouette spans %.2f m" % [id, s.span], absf(reach * 2.0 - float(s.span)) < 1e-6, str(reach * 2.0))
		_check("%s rig weights: hand outboard of the wrist, tail behind its root" % id, weights_ok)
		_check("%s: the shader's wing rig moves exactly the wing (never the tail or body)" % id, rig_gate_ok)
		_check("%s silhouette is left-right symmetric" % id, mirrored)


## GDScript copy of sky_birds.gdshader track_pos() (float32 tables, same branch structure).
func _shader_track_pos(packed: Dictionary, track: int, t: float) -> Vector3:
	var info: Vector4 = packed.track_info[track]
	var first: int = int(info.x + 0.5)
	var count: int = int(info.y + 0.5)
	var tt: float = fposmod(t, info.z)
	var index: int = first
	for i: int in range(1, BirdData.MAX_SEGMENTS_PER_GROUP):
		if i >= count or packed.seg_a[first + i].w > tt:
			break
		index = first + i
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


func _test_scene() -> void:
	var noon: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	_check("builds the Birds node", noon != null and noon.name == Birds.NODE_NAME)
	if noon == null:
		return
	var primitives := 0
	var draws := 0
	var names: Array[String] = []
	var aabb_ok := true
	for child: Node in noon.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null:
			continue
		draws += 1
		names.append(str(mmi.name))
		var mm: MultiMesh = mmi.multimesh
		primitives += mm.instance_count * floori(mm.mesh.get_faces().size() / 3.0)
		var tracks: Array = mmi.get_meta("tracks")
		for item: Dictionary in mmi.get_meta("instances"):
			var track: Dictionary = tracks[item.track]
			var t := 0.0
			while t < float(track.period):
				var p: Vector3 = _pos(track, t)
				aabb_ok = aabb_ok and mmi.custom_aabb.has_point(item.transform * Vector3(p.x, p.z, -p.y))
				t += 2.0
		_check("%s: shadow casting off" % mmi.name, mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_check_shader_tables(mmi)
	_check("one MultiMesh per group %s" % [names], names == ["Birds_soaring", "Birds_small"], str(names))
	_check("within the scenery_Birds budget (%d primitives, %d draws)" % [BUDGET_PRIMITIVES, BUDGET_DRAWS],
		primitives <= BUDGET_PRIMITIVES and draws <= BUDGET_DRAWS, "%d primitives, %d draws" % [primitives, draws])
	_check("every bird stays inside its MultiMesh's culling box (no pop-out)", aabb_ok)
	_check("noon: every species is out", _activity(noon) == [Vector4(1, 1, 0, 0), Vector4(1, 0, 0, 0)], str(_activity(noon)))
	Birds.apply_lighting(noon, {sun_elevation_deg = 8.0, sun_azimuth_deg = 250.0})
	var low: Array = _activity(noon)
	_check("low sun: no thermals, so no vultures; kites and swallows still out",
		low[0].x == 0.0 and low[0].y > 0.4 and low[1].x > 0.9, str(low))
	var defaults: Dictionary = LightingConfig.defaults()
	for preset: String in ["night", "dawn"]:
		var snapshot: Dictionary = Lighting.snapshot(LightingConfig.preset(defaults, preset).config)
		Birds.apply_lighting(noon, snapshot)
		_check("%s time-of-day snapshot (sky clamp %.2f deg, sun %.1f deg): no birds" % [preset,
			float(snapshot.get("sun_elevation_deg", NAN)), Birds.sun_elevation_deg(snapshot)],
			_activity(noon) == [Vector4.ZERO, Vector4.ZERO], str(_activity(noon)))
	var real_noon: Dictionary = Lighting.snapshot(LightingConfig.preset(defaults, "noon").config)
	Birds.apply_lighting(noon, real_noon)
	_check("noon time-of-day snapshot (sun %.1f deg): every species out" % Birds.sun_elevation_deg(real_noon),
		_activity(noon) == [Vector4(1, 1, 0, 0), Vector4(1, 0, 0, 0)], str(_activity(noon)))
	var again: Node3D = Birds.build({sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	Birds.apply_lighting(noon, {sun_elevation_deg = 45.0, sun_azimuth_deg = 180.0})
	_check("build is deterministic (instances, meshes, culling boxes and every shader table, byte for byte)",
		not _signature(noon).is_empty() and _signature(again) == _signature(noon))
	_check("invalid data builds nothing", Birds.build({}, "res://data/scenery/birds/missing.json") == null)
	noon.free()
	again.free()


## The group's real shader tables (as birds.gd packs them: several flocks per group, offset first segments), checked
## against the float64 reference over the shader's whole time range (sim_clock + offset < 2048 s).
func _check_shader_tables(mmi: MultiMeshInstance3D) -> void:
	var material := mmi.material_override as ShaderMaterial
	var packed := {seg_a = material.get_shader_parameter("seg_a"), seg_b = material.get_shader_parameter("seg_b"),
		track_info = material.get_shader_parameter("track_info")}
	var tracks: Array = mmi.get_meta("tracks")
	var worst := 0.0
	for ti: int in tracks.size():
		var t := 0.0
		while t < 2048.0:
			worst = maxf(worst, _pos(tracks[ti], t).distance_to(_shader_track_pos(packed, ti, t)))
			t += 1.7
	_check("%s: float32 shader tables within 5 cm of the float64 tracks over 0-2048 s" % mmi.name, worst < 0.05,
		"%.4f m" % worst)


func _activity(node: Node3D) -> Array:
	var out: Array = []
	for m: ShaderMaterial in node.get_meta("bird_materials"):
		out.append(m.get_shader_parameter("activity"))
	return out


func _signature(node: Node3D) -> PackedByteArray:
	var parts: Array = []
	for child: Node in node.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null:
			continue
		var material := mmi.material_override as ShaderMaterial
		var uniforms: Array = []
		for uniform: String in ["seg_a", "seg_b", "track_info", "gait_a", "gait_b", "gait_c", "rig", "color_top",
				"color_under", "color_tip", "activity"]:
			uniforms.append(material.get_shader_parameter(uniform))
		parts.append([mmi.multimesh.buffer, mmi.multimesh.mesh.get_faces(), mmi.custom_aabb, uniforms])
	return var_to_bytes(parts) if parts.size() == 2 else PackedByteArray()
