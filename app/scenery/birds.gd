## Birds over the field (docs/plans/birds-sky-life.md, SC-BIRD-02…05; replaces SC-20's single "V" flock). Species,
## silhouettes, gaits and closed flight circuits come from app/data/scenery/birds/birds.json; each group ("soaring",
## "small") is one MultiMesh, so all birds cost two draws. Motion is analytic on sim_clock (sky_birds.gdshader), so
## captures and replays draw the same birds. Daylight decides how many are out (apply_lighting, Wildlife's day curve).
## Invalid data builds nothing: the scenery then has no birds and a warning names the errors.
extends RefCounted

const BirdData = preload("res://scenery/birds/bird_data.gd")
const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")
const BirdPlanform = preload("res://scenery/birds/bird_planform.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const Palette = preload("res://scenery/palette.gd")
const SHADER: Shader = preload("res://scenery/birds/sky_birds.gdshader")

const NODE_NAME := "Birds"
const SLOTS := 4 # species per MultiMesh (shader arrays)
const TRACK_SLOTS := 8
const SEGMENT_SLOTS := 48
const AABB_MARGIN_M := 6.0


## The "Birds" node with one MultiMeshInstance3D per group, or null when the data is invalid.
static func build(lighting: Dictionary = {}, path: String = BirdData.DEFAULT_PATH) -> Node3D:
	var loaded: Dictionary = BirdData.load_from(path)
	if not loaded.ok:
		push_warning("birds: %s not built: %s" % [path, "; ".join(loaded.errors)])
		return null
	var root := Node3D.new()
	root.name = NODE_NAME
	var materials: Array[ShaderMaterial] = []
	for group: String in BirdData.GROUPS:
		var flocks: Array[Dictionary] = []
		for f: Dictionary in loaded.flocks:
			if f.group == group:
				flocks.append(f)
		if flocks.is_empty():
			continue
		var node: MultiMeshInstance3D = _group(group, flocks, loaded.species)
		root.add_child(node)
		materials.append(node.material_override as ShaderMaterial)
	root.set_meta("bird_materials", materials)
	apply_lighting(root, lighting)
	return root


## Daylight → share of each species out (shader uniform `activity`). Called at build and on every committed lighting
## change; it only writes uniforms, so it is safe at the checkpoint boundary.
static func apply_lighting(root: Node, lighting: Dictionary) -> void:
	if root == null or not root.has_meta("bird_materials"):
		return
	var sun: float = sun_elevation_deg(lighting)
	for material: ShaderMaterial in root.get_meta("bird_materials"):
		var minima: PackedFloat32Array = material.get_meta("sun_min_deg")
		var a := Vector4.ZERO
		for i: int in minima.size():
			a[i] = species_activity(sun, minima[i])
		material.set_shader_parameter("activity", a)


## Wildlife.activity()'s day curve (birds call when they fly) times the species' own threshold, e.g. thermals.
static func species_activity(sun_deg: float, sun_min_deg: float) -> float:
	return smoothstep(-5.0, 4.0, sun_deg) * smoothstep(sun_min_deg - 4.0, sun_min_deg + 4.0, sun_deg)


## The true solar elevation. Time-of-day snapshots clamp `sun_elevation_deg` to >= 0.05 deg for the sky, so the
## night would look like sunrise; their `solar.elevation_deg` is the real value (as flight_audio.gd reads it).
static func sun_elevation_deg(lighting: Dictionary) -> float:
	var solar: Variant = lighting.get("solar", null)
	if solar is Dictionary and (solar as Dictionary).has("elevation_deg"):
		return float(solar.elevation_deg)
	if lighting.is_empty() and not Atmosphere.state.is_empty():
		return float(Atmosphere.state.get("sun_elevation_deg", 45.0))
	return float(Atmosphere.parameters(lighting).get("sun_elevation_deg", 45.0))


## Instance layout for one group: [{flock, track (group index), species (slot), transform, custom}], also used by tests.
static func instances(flocks: Array[Dictionary], species_order: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var track_base := 0
	for fi: int in flocks.size():
		var f: Dictionary = flocks[fi]
		var ntracks: int = (f.tracks as Array).size()
		var origin: Vector3 = Frames.ned_to_render(f.origin)
		for i: int in f.count:
			var h1: float = Palette.hash01(i, fi + 11, 1)
			var h2: float = Palette.hash01(i, fi + 11, 2)
			var h3: float = Palette.hash01(i, fi + 11, 3)
			var h4: float = Palette.hash01(i, fi + 11, 4)
			var basis := Basis.IDENTITY
			if f.rotate_instances:
				basis = Basis(Vector3.UP, TAU * h1)
			if f.mirror_instances and h2 < 0.5:
				basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
			var offset := Vector3((h3 - 0.5) * 2.0 * f.spread_offset, float(f.base_height) + (h4 - 0.5) * 2.0 * f.spread_height,
				(Palette.hash01(i, fi + 11, 5) - 0.5) * 2.0 * f.spread_offset)
			out.append({
				flock = f.id,
				track = track_base + i % ntracks,
				species = species_order.find(f.species),
				transform = Transform3D(basis, origin + offset),
				custom = Color(time_offset(float(i) / f.count * f.spread_time + h1 * 3.0), track_base + i % ntracks,
					species_order.find(f.species), floorf(Palette.hash01(i, fi + 11, 6) * 1024.0) / 1024.0),
			})
		track_base += ntracks
	return out


## Per-bird time offsets are whole half-seconds in [0, 1024) and hashes multiples of 1/1024 below 1: both exact in a
## half float, so the GPU sees the very values the CPU reference uses even if custom data is stored at 16 bits.
static func time_offset(seconds: float) -> float:
	return fposmod(roundf(seconds * 2.0) * 0.5, 1024.0)


static func _group(group: String, flocks: Array[Dictionary], species: Dictionary) -> MultiMeshInstance3D:
	var order: Array[String] = []
	var tracks: Array = []
	for f: Dictionary in flocks:
		if not order.has(f.species):
			order.append(f.species)
		tracks.append_array(f.tracks)
	var builds: Array = []
	for id: String in order:
		builds.append(BirdPlanform.build(species[id].planform, species[id].span))
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_set_tables(material, tracks, order, species, builds)
	var mesh: ArrayMesh = BirdPlanform.atlas(builds)
	var layout: Array[Dictionary] = instances(flocks, order)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true # see flowers.gd: keeps vertex COLOR intact in Compatibility
	mm.mesh = mesh
	mm.instance_count = layout.size()
	var box := AABB()
	for i: int in layout.size():
		var item: Dictionary = layout[i]
		mm.set_instance_transform(i, item.transform)
		mm.set_instance_color(i, Color.WHITE)
		mm.set_instance_custom_data(i, item.custom)
		var track: Dictionary = tracks[item.track]
		var local := AABB(_track_render(track.bbox_min), Vector3.ZERO).expand(_track_render(track.bbox_max))
		var world: AABB = item.transform * local
		box = world if i == 0 else box.merge(world)
	var node := MultiMeshInstance3D.new()
	node.name = "Birds_" + group
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = box.grow(AABB_MARGIN_M)
	node.set_meta("species", order)
	node.set_meta("instances", layout)
	node.set_meta("tracks", tracks)
	return node


static func _set_tables(material: ShaderMaterial, tracks: Array, order: Array[String], species: Dictionary, builds: Array) -> void:
	var packed: Dictionary = BirdTracks.pack(tracks)
	var gait_a := PackedVector4Array()
	var gait_b := PackedVector4Array()
	var gait_c := PackedVector4Array()
	var rig := PackedVector4Array()
	var top := PackedVector4Array()
	var under := PackedVector4Array()
	var tip := PackedVector4Array()
	var minima := PackedFloat32Array()
	for i: int in order.size():
		var s: Dictionary = species[order[i]]
		var g: Dictionary = s.gait
		gait_a.append(Vector4(g.flap_frequency_clock, deg_to_rad(g.flap_amplitude), g.burst_period, g.burst_duty))
		gait_b.append(Vector4(deg_to_rad(g.dihedral), deg_to_rad(g.hand_lag), deg_to_rad(g.tip_curl), g.fold))
		gait_c.append(Vector4(g.tail_twist, deg_to_rad(g.tail_wobble), 0.0, 0.0))
		rig.append(builds[i].rig)
		for pair: Array in [[top, "top"], [under, "under"], [tip, "tip"]]:
			var c: Color = s.colors[pair[1]]
			(pair[0] as PackedVector4Array).append(Vector4(c.r, c.g, c.b, 1.0))
		minima.append(s.activity.sun_min)
	material.set_shader_parameter("seg_a", _pad(packed.seg_a, SEGMENT_SLOTS))
	material.set_shader_parameter("seg_b", _pad(packed.seg_b, SEGMENT_SLOTS))
	material.set_shader_parameter("track_info", _pad(packed.track_info, TRACK_SLOTS))
	for pair: Array in [["gait_a", gait_a], ["gait_b", gait_b], ["gait_c", gait_c], ["rig", rig],
			["color_top", top], ["color_under", under], ["color_tip", tip]]:
		material.set_shader_parameter(pair[0], _pad(pair[1], SLOTS))
	material.set_meta("sun_min_deg", minima)


static func _pad(values: PackedVector4Array, size: int) -> PackedVector4Array:
	var out := values.duplicate()
	out.resize(size)
	return out


## Track (x east, y north, z up) to the MultiMesh's render axes (x east, y up, z south), as the shader does.
static func _track_render(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)
