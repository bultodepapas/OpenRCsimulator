## RC-TRACK: the RC car circuit inside the airplane field. Render only: the same float64 surface the aircraft
## wheels roll on (sim/flight_session.gd, physics/ground_vehicle/airfield_track.gd) is sampled once into a
## cached mesh with the car activity's view in its "flight" profile. No collision or simulation state here.
extends RefCounted

const RcGroundMaterial := preload("res://render/rc_ground_material.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Track := preload("res://physics/ground_vehicle/airfield_track.gd")
const GrassMask := preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

## Grass, meadow plants and near-grass clumps stay off the lane and the inner 60 % of its shoulder,
## where the dirt coverage exceeds about one third; the outer shoulder keeps a worn grass edge.
const GRASS_SHOULDER_FRACTION := 0.6
const TURN_SEGMENTS := 12


## The circuit node for `field`, or null when the field's surfaces cannot be mapped (the flight then shows none).
## `lake` is the field's resolved lake; `ground_material` the field's ground ShaderMaterial (left unmodified).
static func build(field: Dictionary, track: Dictionary, lake: Dictionary, ground_material: ShaderMaterial) -> Node3D:
	if track.is_empty():
		return null
	var track_view: Script = load("res://vehicles/ground/airfield_track_view.gd")
	var table := GroundSurfaces.load_table()
	if not bool(table.get("ok", false)):
		return null
	var mapped := GroundSurfaces.build(table.table, field)
	if not bool(mapped.get("ok", false)):
		return null
	var rects: PackedFloat64Array = mapped.rects
	var road := func(north: float, east: float) -> Dictionary:
		var terrain := Track.composed(GroundTerrain.sample_validated(north, east, rects, lake), track, north, east)
		return {height_m = terrain[0], normal_ned = GroundTerrain.normal_from_up_slopes(terrain[1], terrain[2]),
			track_coverage = terrain[3]}
	var material: ShaderMaterial = null
	if ground_material != null:
		# Only the circuit's own copy binds the RC soil maps; the field's ground keeps its accepted look.
		material = ground_material.duplicate() as ShaderMaterial
		RcGroundMaterial.configure(material)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes([Track.identity(track), rects, str(lake.get("identity", "")),
		track_view.FLIGHT_GRID_STEP_M]))
	var view: Node3D = track_view.build({"track": track}, road, material,
		{profile = "flight", cache_key = hashing.finish().hex_encode()})
	view.name = "RcTrack"
	view.set_meta("rc_track_identity", Track.identity(track))
	var surface := view.get_node_or_null("DirtLoopSurface") as MeshInstance3D
	if surface != null and surface.material_override is ShaderMaterial:
		# TrackView duplicates the configured material again; register the final surface copy.
		if ground_material != null:
			Atmosphere.track_shadow_material_copy(surface.material_override as ShaderMaterial, ground_material)
		view.set_meta("lighting_material", surface.material_override)
	return view


## Grass exclusion polygons (GrassMask records, north/east points) covering the circuit's dirt band.
static func grass_exclusions(track: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if track.is_empty():
		return records
	var cn := float(track.center_north_m)
	var ce := float(track.center_east_m)
	var length := float(track.half_straight_m)
	var radius := float(track.radius_m)
	var reach := float(track.lane_width_m) * 0.5 + float(track.shoulder_m) * GRASS_SHOULDER_FRACTION
	# Straights: one rectangle per lane, south and north of the infield.
	for side: float in [-1.0, 1.0]:
		var lane := cn + side * radius
		records.append(_rect("rc-track-straight-%s" % ("south" if side < 0.0 else "north"),
			lane - reach, lane + reach, ce - length, ce + length))
	# Turns: annular sectors around each end, as short quads.
	for end: float in [-1.0, 1.0]:
		var turn_east := ce + end * length
		for segment in range(TURN_SEGMENTS):
			var a0 := -PI * 0.5 + PI * float(segment) / float(TURN_SEGMENTS)
			var a1 := -PI * 0.5 + PI * float(segment + 1) / float(TURN_SEGMENTS)
			var inner := radius - reach
			var outer := (radius + reach) / cos(PI * 0.5 / float(TURN_SEGMENTS)) # chords enclose the outer arc
			var points := PackedVector2Array()
			for corner: Array in [[inner, a0], [outer, a0], [outer, a1], [inner, a1]]:
				points.append(Vector2(cn + float(corner[0]) * sin(float(corner[1])),
					turn_east + end * float(corner[0]) * cos(float(corner[1]))))
			records.append(GrassMask._record("rc-track-turn-%d-%02d" % [int(end), segment], "dirt_track", points))
	var technical := float(track.technical_width_m) * 0.5 + float(track.shoulder_m) * GRASS_SHOULDER_FRACTION
	records.append(_rect("rc-track-technical", cn - technical, cn + technical, ce - length - radius, ce + length + radius))
	var access: Dictionary = track.access
	var access_reach := float(access.width_m) * 0.5 + float(track.shoulder_m) * GRASS_SHOULDER_FRACTION
	records.append(_rect("rc-track-access", float(access.north_min_m) - float(track.shoulder_m) * GRASS_SHOULDER_FRACTION,
		float(access.north_max_m), float(access.east_m) - access_reach, float(access.east_m) + access_reach))
	return records


static func _rect(id: String, north_min: float, north_max: float, east_min: float, east_max: float) -> Dictionary:
	return GrassMask._record(id, "dirt_track", PackedVector2Array([Vector2(north_min, east_min),
		Vector2(north_max, east_min), Vector2(north_max, east_max), Vector2(north_min, east_max)]))
