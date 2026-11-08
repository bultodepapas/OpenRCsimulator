# RC-TRACK: the RC car circuit on the airplane field. One surface for the wheels, the car course and the
# rendered dirt; hull contact with the raised dirt; solid dressing in the collision world; session identity;
# the flight render budget; and the Automatic setting.
# Run: godot --headless --path app --script res://tests/test_rc_track_flight.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Field := preload("res://data/field_loader.gd")
const Course := preload("res://physics/ground_vehicle/airfield_course.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const Ground := preload("res://physics/ground_contact.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Session := preload("res://sim/flight_session.gd")
const View := preload("res://vehicles/ground/airfield_track_view.gd")
const RcTrackField := preload("res://render/rc_track_field.gd")
const Option := preload("res://scenery/rc_track_option.gd")
const DisplayPreferences := preload("res://app_state/display_preferences.gd")

var _count := 0
var _failures := 0


func _initialize() -> void:
	var loaded := Field.load_from()
	var track_result := Track.load_default()
	_check("default field and circuit load", loaded.ok and track_result.ok)
	if not loaded.ok or not track_result.ok:
		quit(1)
		return
	var field: Dictionary = loaded.field
	var track: Dictionary = track_result.track
	var table := GroundSurfaces.load_table()
	var rects: PackedFloat64Array = GroundSurfaces.build(table.table, field).rects
	_test_shared_surface(loaded, track, rects)
	_test_wheels(track, rects)
	_test_session(field, track)
	_test_hull_contact(field, track)
	_test_collision_world(field, track)
	_test_dressing_matches_render(track)
	_test_flight_render(field, track, rects)
	_test_option(field)
	print("%d RC circuit flight checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## The wheels' composition equals the car course's sampler bit for bit, over the circuit and its margins.
func _test_shared_surface(loaded: Dictionary, track: Dictionary, rects: PackedFloat64Array) -> void:
	var built := Course.build(loaded)
	var course: Dictionary = built.course
	var equal := true
	var max_height := 0.0
	var bounds := Track.bounds_ne(track)
	for ni in range(0, 141):
		var north := lerpf(bounds[0] - 1.0, bounds[1] + 1.0, float(ni) / 140.0)
		for ei in range(0, 177):
			var east := lerpf(bounds[2] - 1.0, bounds[3] + 1.0, float(ei) / 176.0)
			var car: Dictionary = Course.sample(course, north, east)
			var plane := Track.composed(GroundTerrain.sample_validated(north, east, rects), track, north, east)
			equal = equal and car.height_m == plane[0] and car.track_coverage == plane[3]
			max_height = maxf(max_height, float(Track.sample(track, north, east).height_m))
	_check("aircraft terrain equals the car course height and coverage exactly", equal)
	_check("height bound holds the sampled relief", max_height <= Track.max_height_m(track)
		and max_height > 0.8, "max %.4f bound %.4f" % [max_height, Track.max_height_m(track)])
	var outside := Track.sample(track, bounds[0] - 0.01, 0.0)
	_check("relief is zero outside the footprint bounds", float(outside.height_m) == 0.0
		and float(Track.sample(track, 45.0, bounds[3] + 0.01).height_m) == 0.0)


## A wheel on the banked turn is compressed against the raised surface; without the circuit it is airborne.
func _test_wheels(track: Dictionary, rects: PackedFloat64Array) -> void:
	var north := 45.0
	var east := float(track.center_east_m) + float(track.half_straight_m) + float(track.radius_m) + 1.4
	var raised := Track.composed(GroundTerrain.sample_validated(north, east, rects), track, north, east)
	_check("probe point sits on the high side of the bank", raised[0] > 0.5, "h %.4f" % raised[0])
	var gear := {reach = 1.0, contacts = [{name = "probe", position = PackedFloat64Array([0.0, 0.0, 0.0]),
		stiffness = 400.0, damping = 4.0, max_compression = 0.05}], side_friction = 0.6, rolling_resistance = 0.04}
	# CG 1 cm below the circuit surface: compressed with the overlay, 0.5 m clear of the flat field without.
	var state := RB.make_state(PackedFloat64Array([north, east, -(raised[0] - 0.01)]), PackedFloat64Array([0.0, 0.0, 0.0]),
		M.q_from_euler(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))
	var with_track := Ground.compressions(state, gear, rects, {}, track)
	var without := Ground.compressions(state, gear, rects, {})
	var expected := 0.01 / sqrt(1.0 + raised[1] * raised[1] + raised[2] * raised[2])
	_check("wheel compression follows the circuit surface", absf(with_track[0] - expected) < 1.0e-12,
		"%.9f vs %.9f" % [with_track[0], expected])
	_check("the same wheel is airborne over the flat field", without[0] < -0.4)
	var loads := Ground.evaluate(state, gear, 0.0, rects, PackedFloat64Array(), PackedFloat64Array([0.0]), 0.0, true, {}, track)
	_check("wheel loads push up the circuit normal", loads.loads.size() == 6 and loads.loads[2] < 0.0)
	var no_track := Ground.evaluate(state, gear, 0.0, rects, PackedFloat64Array(), PackedFloat64Array([0.0]), 0.0, true, {})
	_check("no circuit, no wheel load at this height", no_track.loads.is_empty())
	var dirt := Track.surface_factors(track)
	_check("dirt tyre factors are the course's own", is_equal_approx(dirt[0] * Track.DRY_PAVEMENT_MU, float(track.mu))
		and dirt[1] == float(track.rolling) and Track.DRY_PAVEMENT_MU == Course.DRY_PAVEMENT_MU)


func _test_session(field: Dictionary, track: Dictionary) -> void:
	var session := _new_session(field)
	var plain_config: String = session._checkpoint_configuration()
	var plain_identity: Dictionary = session.environment.identity()
	_check("session accepts the validated circuit", session.set_rc_track(track) and not session.rc_track_context().is_empty())
	_check("collision step runs with the circuit alone", session.sim.model.post_tick.is_valid())
	_check("the circuit is part of the configuration hash", session._checkpoint_configuration() != plain_config)
	_check("environment identity names the circuit", str(session.environment.identity().get("rc_track", "")) == Track.identity(track)
		and not plain_identity.has("rc_track"))
	var ground: PackedFloat64Array = session.environment.ground(45.0, 19.4)
	_check("environment ground includes the circuit", ground[0] > 0.3 and ground.size() == 3)
	_check("flight metadata carries the circuit identity", str(session.trace_meta().get("rc_track_identity", "")) == Track.identity(track))
	var malformed := track.duplicate(true)
	malformed.erase("mu")
	_check("an invalid circuit is refused", not session.set_rc_track(malformed) and session.rc_track_identity() == Track.identity(track))
	var checkpoint: Dictionary = session.checkpoint()
	_check("checkpoint records the circuit identity", str(checkpoint.get("rc_track_identity", "")) == Track.identity(track))
	var plain := _new_session(field)
	_check("a session without the circuit refuses its checkpoint", not checkpoint.is_empty() and not plain.restore_checkpoint(checkpoint))
	_check("and the circuit session restores it", session.restore_checkpoint(checkpoint))
	_check("removing the circuit restores the plain identity", session.set_rc_track({})
		and not session.environment.identity().has("rc_track") and session._checkpoint_configuration() == plain_config)
	session.free()
	plain.free()


## The hull meets the tabletop deck at the exact surface; thin pad dirt stays with the flat datum.
func _test_hull_contact(field: Dictionary, track: Dictionary) -> void:
	var session := _new_session(field)
	session.aircraft.model.crash_hull = PackedFloat64Array([0.0, 0.0, 0.0])
	session.aircraft.model.landing_gear = {}
	session._prop_disc = {}
	_check("collision fixture installs the circuit", session.set_rc_track(track))
	var deck := {height_m = session.environment.ground(39.0, -4.0)[0]}
	var previous := _state([39.0, -4.0, -1.0], [0.0, 0.0, 0.0])
	var candidate := _state([39.0, -4.0, -0.3], [0.0, 0.0, 0.0])
	var hit: Dictionary = session._rc_track_hit(previous, candidate, 1)
	var expected := (1.0 - float(deck.height_m)) / 0.7
	_check("hull point meets the deck at the swept crossing", hit.impact != null
		and absf(float(hit.fraction) - expected) < 1.0e-6, "fraction %s expected %.6f" % [str(hit.fraction), expected])
	_check("impact carries the circuit normal and crossing", hit.impact != null and hit.impact.crossing.available
		and hit.impact.crossing.method == Session.RcTrackCrossing.LAW and hit.impact.has_kinematics)
	var pad_previous := _state([25.0, -10.0, -0.5], [0.0, 0.0, 0.0])
	var pad_candidate := _state([25.0, -10.0, -0.01], [0.0, 0.0, 0.0])
	_check("thin access-lane pad is not a relief obstacle", session._rc_track_hit(pad_previous, pad_candidate, 1).impact == null
		and float(Track.sample(track, 25.0, -10.0).height_m) < Session.RC_RELIEF_MIN_M)
	_check("a sweep far from the circuit is gated out", session._rc_track_hit(_state([-60.0, 0.0, -0.5], [0.0, 0.0, 0.0]),
		_state([-60.0, 0.0, 0.2], [0.0, 0.0, 0.0]), 1).impact == null)
	# Through the session's post-tick resolver (no lake, no scenery world): the sweep stops on the deck.
	session._resolving_contact = false
	var resolved: PackedFloat64Array = session._resolve_collision_step(previous, candidate, 1)
	var pending: Variant = session._pending_crash
	_check("tick resolution stops on the raised dirt", pending != null and resolved.size() == candidate.size()
		and absf(-resolved[RB.POS + 2] - float(deck.height_m)) < 1.0e-4
		and absf(-float(pending.detected_state[RB.POS + 2]) - float(deck.height_m)) < 1.0e-4,
		"up %.5f deck %.5f" % [-resolved[RB.POS + 2] if resolved.size() > 2 else NAN, float(deck.height_m)])
	var clear: PackedFloat64Array = session._resolve_collision_step(_state([39.0, -4.0, -2.0], [0.0, 0.0, 0.0]),
		_state([39.0, -4.0, -1.5], [0.0, 0.0, 0.0]), 2)
	_check("a clear sweep keeps its candidate", clear == _state([39.0, -4.0, -1.5], [0.0, 0.0, 0.0]))
	session.free()


func _test_collision_world(field: Dictionary, track: Dictionary) -> void:
	var scenery := {groups = []}
	var plain := CollisionWorld.build(field, scenery, {})
	var with_track := CollisionWorld.build(field, scenery, {}, track)
	_check("collision worlds build", plain.ok and with_track.ok)
	var circuit: Array = []
	for proxy: Dictionary in with_track.world.proxies:
		if str(proxy.kind) == "rc_track":
			circuit.append(proxy)
	_check("the circuit adds its 17 solid parts", circuit.size() == 17 and with_track.world.proxies.size() == plain.world.proxies.size() + 17,
		"%d parts" % circuit.size())
	_check("the circuit changes the world identity", str(plain.world.identity) != str(with_track.world.identity))
	_check("an empty circuit keeps the legacy identity", str(CollisionWorld.build(field, scenery, {}, {}).world.identity) == str(plain.world.identity))
	var walls_exact := true
	for wall: Dictionary in track.walls:
		for proxy: Dictionary in circuit:
			if str(proxy.id) == "rc_track:wall:" + str(wall.id):
				walls_exact = walls_exact and is_equal_approx(float(proxy.bounds_north_min), float(wall.north_min_m)) \
					and is_equal_approx(float(proxy.bounds_east_max), float(wall.east_max_m)) \
					and is_equal_approx(-float(proxy.bounds_down_min), float(wall.top_up_m)) \
					and proxy.response_class == "hard_terminal" and proxy.damage_profile == "masonry"
	_check("walls are the course's exact collision boxes", walls_exact)
	var malformed := track.duplicate(true)
	malformed.erase("walls")
	_check("an invalid circuit is refused by the inventory", not CollisionWorld.build(field, scenery, {}, malformed).ok)


## Every rendered dressing node stands on its collision record (car profile, the owner's tested layout).
func _test_dressing_matches_render(track: Dictionary) -> void:
	var built := Course.build(Field.load_from())
	var course: Dictionary = built.course
	var road := func(n: float, e: float) -> Dictionary: return Course.sample(course, n, e)
	var view: Node3D = View.build(course, road)
	var by_id := {}
	for item: Dictionary in Track.dressing(track):
		by_id[str(item.id)] = item
	var nodes := {
		"rc_track:sign:access": "TrackFurniture/AccessSign", "rc_track:sign:jumps": "TrackFurniture/JumpsSign",
		"rc_track:sign:slalom": "TrackFurniture/SlalomSign", "rc_track:sign:rollers": "TrackFurniture/RollersSign",
		"rc_track:tape:south": "TrackServiceDetail/SouthJumpSafetyTape", "rc_track:tape:north": "TrackServiceDetail/NorthRollerSafetyTape",
		"rc_track:cabinet": "TrackServiceDetail/TimingControlCabinet",
		"rc_track:timing_post:south": "TrackFurniture/StartTimingGate/SouthTimingPost",
		"rc_track:timing_post:north": "TrackFurniture/StartTimingGate/NorthTimingPost",
	}
	var matched := true
	for id: String in nodes:
		var node := view.get_node_or_null(nodes[id]) as Node3D
		var item: Dictionary = by_id.get(id, {})
		# Every dressing parent stands at the view origin, so a node's local position is its field position.
		matched = matched and node != null and not item.is_empty() \
			and absf(-node.position.z - float(item.north)) < 1.0e-4 and absf(node.position.x - float(item.east)) < 1.0e-4
		if node != null and id.begins_with("rc_track:sign:"):
			matched = matched and is_equal_approx(rad_to_deg(-node.rotation.y), float(item.heading_deg))
	_check("signs, tape, cabinet and timing posts match their collision records", matched)
	var stacks := view.get_node("TrackTyreStacks").get_children()
	var tyres_match := stacks.size() == Track.TYRE_STACKS.size()
	for index in mini(stacks.size(), Track.TYRE_STACKS.size()):
		var anchor := stacks[index] as Node3D
		# Render positions are float32 (34.9 m carries 1.5e-6 m of rounding).
		tyres_match = tyres_match and absf(anchor.position.x - float(Track.TYRE_STACKS[index].east)) < 1.0e-4 \
			and absf(-anchor.position.z - float(Track.TYRE_STACKS[index].north)) < 1.0e-4
	_check("tyre stacks match their collision records", tyres_match, "%d stacks: %s" % [stacks.size(),
		str(stacks.map(func(node: Node) -> Vector3: return (node as Node3D).position))])
	view.free()


func _test_flight_render(field: Dictionary, track: Dictionary, rects: PackedFloat64Array) -> void:
	var started := Time.get_ticks_usec()
	var view: Node3D = RcTrackField.build(field, track, {}, null)
	var first_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_check("flight circuit builds", view != null and view.get_node_or_null("DirtLoopSurface") != null)
	if view == null:
		return
	var surface := view.get_node("DirtLoopSurface") as MeshInstance3D
	var dirt_mesh := surface.mesh
	var arrays := surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var exact := true
	for index in range(0, vertices.size(), 37):
		var v := vertices[index]
		var physics := Track.composed(GroundTerrain.sample_validated(-v.z, v.x, rects), track, -v.z, v.x)
		exact = exact and absf(v.y - float(physics[0]) - 0.002) < 1.0e-5
	_check("flight dirt vertices sit 2 mm over the wheels' surface", exact)
	var used := PackedByteArray()
	used.resize(vertices.size())
	for value in indices:
		used[value] = 1
	_check("the dirt buffer holds no unused vertices", used.count(0) == 0)
	_check("the dirt bounds stay on the circuit, clear of the pilot", surface.get_aabb().end.z < -15.0, str(surface.get_aabb()))
	var triangles := indices.size() / 3
	_check("flight dirt stays under 45k triangles", triangles > 10000 and triangles < 45000, "%d" % triangles)
	var tyres := view.get_node_or_null("TrackTyreStacks") as MultiMeshInstance3D
	_check("eight tyres draw as one instanced mesh", tyres != null and tyres.multimesh.instance_count == 8)
	_check("start grid and arrows merge into two paint meshes", view.get_node_or_null("TrackPaintLight") != null
		and view.get_node_or_null("TrackPaintDark") != null and view.get_node_or_null("StartGrid00") == null)
	var ranged := true
	var fine := 0
	for node: Node in view.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == surface:
			continue
		ranged = ranged and geometry.visibility_range_end > 0.0
		fine += 1 if geometry.visibility_range_end <= View.FLIGHT_LABEL_RANGE_M else 0
	_check("every prop has a visibility range and fine hardware fades early", ranged and fine > 10, "%d fine" % fine)
	_check("the renderer adds no physics bodies", view.find_children("*", "CollisionObject3D", true, false).is_empty())
	var exclusions := RcTrackField.grass_exclusions(track)
	_check("grass masks cover the lane", exclusions.size() == 28 and _inside_any(exclusions, 45.0 - 6.0, 0.0)
		and _inside_any(exclusions, 45.0, 19.0) and _inside_any(exclusions, 30.0, -10.0))
	_check("grass masks leave the infield corners", not _inside_any(exclusions, 48.2, 8.0))
	view.free()
	started = Time.get_ticks_usec()
	var again: Node3D = RcTrackField.build(field, track, {}, null)
	var cached_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_check("a second flight reuses the cached dirt mesh", (again.get_node("DirtLoopSurface") as MeshInstance3D).mesh == dirt_mesh
		and cached_ms < first_ms, "first %.1f ms, cached %.1f ms" % [first_ms, cached_ms])
	print("RC circuit flight build: first %.1f ms, cached %.1f ms, %d dirt triangles" % [first_ms, cached_ms, triangles])
	again.free()


func _test_option(field: Dictionary) -> void:
	_check("Automatic needs a dedicated GPU", bool(Option.automatic({level = "high", reason = "dedicated GPU"}, "high").enabled)
		and not bool(Option.automatic({level = "medium", reason = "integrated GPU"}, "high").enabled)
		and not bool(Option.automatic({level = "high", reason = "unrecognized GPU"}, "high").enabled)
		and not bool(Option.automatic({level = "high", reason = "no GPU reported"}, "extreme").enabled))
	_check("Automatic respects a lower Scene detail", not bool(Option.automatic({level = "high", reason = "dedicated GPU"}, "medium").enabled)
		and bool(Option.automatic({level = "high", reason = "dedicated GPU"}, "extreme").enabled))
	var previous := Option.preference()
	Option.set_preference("on")
	_check("menu flights follow On", not Option.resolve(field, true).is_empty())
	_check("traces and tests never read the preference", Option.resolve(field, false).is_empty())
	var custom := field.duplicate(true)
	custom.id = "custom"
	_check("custom fields never receive the circuit", Option.resolve(custom, true).is_empty())
	Option.set_preference("off")
	_check("Off disables it", Option.resolve(field, true).is_empty())
	Option.set_preference("bogus")
	_check("unknown preferences fall back to Automatic", Option.preference() == Option.AUTO)
	Option.set_preference(previous)
	_check("preferences mirror the option", DisplayPreferences.RC_TRACK_LEVELS == Option.PREFERENCES
		and DisplayPreferences.DEFAULTS.rc_track == Option.DEFAULT)
	var invalid := DisplayPreferences.DEFAULTS.duplicate(true)
	invalid.rc_track = "sometimes"
	_check("display preferences reject an unknown circuit value", not DisplayPreferences.validate(invalid).ok)


func _inside_any(records: Array[Dictionary], north: float, east: float) -> bool:
	for record: Dictionary in records:
		if Geometry2D.is_point_in_polygon(Vector2(north, east), record.points):
			return true
	return false


func _new_session(field: Dictionary) -> Session:
	var session: Session = Session.new()
	session.physics_enabled = false
	session.crash_auto_restart = false
	root.add_child(session)
	session.setup()
	_check("session installs the default field", session.set_field(field))
	return session


func _state(position: Array, velocity: Array) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array(position), PackedFloat64Array(velocity),
		M.q_from_euler(0.0, 0.0, 0.0), PackedFloat64Array([0.0, 0.0, 0.0]))


func _check(label: String, ok: bool, detail: String = "") -> void:
	_count += 1
	if ok:
		print("PASS: ", label)
	else:
		_failures += 1
		print("FAIL: ", label, ("  " + detail) if not detail.is_empty() else "")
