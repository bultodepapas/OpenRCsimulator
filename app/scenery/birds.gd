## Birds over the field (docs/plans/birds-sky-life.md, SC-BIRD-02…05 and 08; replaces SC-20's single flock). Species,
## silhouettes, gaits and closed flight circuits come from app/data/scenery/birds/birds.json; each group ("soaring",
## "small") is one MultiMesh whose species share one topology (their shapes are in CUSTOM0..3), so all birds cost two
## draws and a bird draws only its own triangles. Motion is analytic on sim_clock (sky_birds.gdshader).
## bird_director.gd decides from the committed lighting how many of each species are out; a bird that starts or stops
## flying arrives or leaves over its species' departure time (on sim_clock), never pops, and only birds that are out
## or on their way are drawn (visible_instance_count). Invalid data builds nothing and a warning names the errors.
extends RefCounted

const BirdData = preload("res://scenery/birds/bird_data.gd")
const BirdTracks = preload("res://scenery/birds/bird_tracks.gd")
const BirdPlanform = preload("res://scenery/birds/bird_planform.gd")
const BirdDirector = preload("res://scenery/birds/bird_director.gd")
const BirdsRuntime = preload("res://scenery/birds/birds_runtime.gd")
const Frames = preload("res://render/frames.gd")
const Palette = preload("res://scenery/palette.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const SHADER: Shader = preload("res://scenery/birds/sky_birds.gdshader")

const NODE_NAME := "Birds"
const SLOTS := 4 # species per MultiMesh (shader arrays, CUSTOM0..3)
const TRACK_SLOTS := 8
const SEGMENT_SLOTS := 48
const SPECIES_STRIDE := 8.0 # INSTANCE_CUSTOM.y = track + 8 * species
const HALF_WRAP_S := 512.0
const AABB_MARGIN_M := 6.0
# INSTANCE_CUSTOM.z: the bird's state. The Compatibility renderer stores MultiMesh custom data as half floats and
# truncates (measured 2026-10-24: 1000.3 reads 1000.0, 100.3 reads 100.25), so every value is exact in a half float.
const DRAWN_PRIMITIVE_LIMIT := 1000 # tools/scenery/scene_budget.json scenery_Birds
const SNAP_SUN_DEG := 2.0 # a larger sun change between commits is a jump (paused edit, restore), not time passing
const STEADY := 1500.0 # flying its circuit
const HIDDEN := 2000.0 # away (not drawn)
# departing: the half-second it started leaving, 0..1023.5; arriving: -(start + 0.5), -1024..-0.5


## The "Birds" node with one MultiMeshInstance3D per group, or null when the data is invalid.
static func build(lighting: Dictionary = {}, quality: String = "high", path: String = BirdData.DEFAULT_PATH) -> Node3D:
	var loaded: Dictionary = BirdData.load_from(path)
	if not loaded.ok:
		push_warning("birds: %s not built: %s" % [path, "; ".join(loaded.errors)])
		return null
	var root := Node3D.new()
	root.name = NODE_NAME
	root.set_script(BirdsRuntime)
	var groups: Array[MultiMeshInstance3D] = []
	for group: String in BirdData.GROUPS:
		var flocks: Array[Dictionary] = []
		for f: Dictionary in loaded.flocks:
			if f.group == group:
				flocks.append(f)
		if flocks.is_empty():
			continue
		var node: MultiMeshInstance3D = _group(group, flocks, loaded.species)
		root.add_child(node)
		groups.append(node)
	root.set_meta("bird_groups", groups)
	root.set_meta("quality", quality)
	apply_lighting(root, lighting, false)
	return root


## Committed lighting → which birds fly. With `animate`, a bird whose state changes arrives or leaves over its
## species' departure time starting now (ShaderClock.last_clock); without it (build) it simply is or is not there.
## A jump of the sun (more than SNAP_SUN_DEG since the last call) or an animation that would draw more than the
## budget snaps instead. Only writes MultiMesh buffers and counts, so it is safe at the checkpoint boundary.
## `clouds` < 0 reads the rendered weather's cover.
static func apply_lighting(root: Node, lighting: Dictionary, animate: bool = true, clouds: float = -1.0) -> void:
	if root == null or not root.has_meta("bird_groups"):
		return
	var c: Dictionary = BirdDirector.conditions(lighting, str(root.get_meta("quality", "high")), clouds)
	var previous: Dictionary = root.get_meta("conditions", {})
	if animate and (previous.is_empty() or absf(float(c.sun_deg) - float(previous.sun_deg)) > SNAP_SUN_DEG):
		animate = false
	var before: Dictionary = {}
	for node: MultiMeshInstance3D in root.get_meta("bird_groups"):
		before[node] = (node.get_meta("states") as PackedFloat32Array).duplicate()
	_apply(root, c, animate)
	if animate and drawn_primitives(root) > DRAWN_PRIMITIVE_LIMIT:
		for node: MultiMeshInstance3D in before:
			node.set_meta("states", before[node])
		_apply(root, c, false)
	root.set_meta("conditions", c)
	root.set_meta("lighting", lighting.duplicate(true))


static func _apply(root: Node, c: Dictionary, animate: bool) -> void:
	for node: MultiMeshInstance3D in root.get_meta("bird_groups"):
		var species: Array = node.get_meta("species_data")
		var shares: Array[float] = []
		for s: Dictionary in species:
			shares.append(BirdDirector.activity(s, c))
		var layout: Array = node.get_meta("instances")
		var states: PackedFloat32Array = node.get_meta("states")
		for i: int in layout.size():
			var item: Dictionary = layout[i]
			var want: bool = float(item.hash) < shares[item.species]
			var duration: float = species[item.species].departure.duration
			states[i] = next_state(states[i], want, ShaderClock.last_clock, duration) if animate \
				else (STEADY if want else HIDDEN)
		node.set_meta("states", states)
		write_buffer(node)


## Primitives the drawn birds cost (visible instances x the group's triangles).
static func drawn_primitives(root: Node) -> int:
	var total := 0
	for node: MultiMeshInstance3D in root.get_meta("bird_groups", []):
		total += node.multimesh.visible_instance_count * int(node.get_meta("triangles"))
	return total


## A bird's next state at shader clock `clock` when its species wants it out (`want`) or not. A bird already on its
## way turns round where it is: smoothstep is symmetric, so the start is set back by the time still to go.
static func next_state(state: float, want: bool, clock: float, duration: float) -> float:
	var p: float = progress(state, clock, duration)
	if want:
		if state == STEADY:
			return STEADY
		if state == HIDDEN:
			return -(_start(clock) + 0.5)
		if state >= 0.0:
			return -(_start(clock - (1.0 - p) * duration) + 0.5)
		return state
	if state == HIDDEN:
		return HIDDEN
	if state == STEADY:
		return _start(clock)
	if state < 0.0:
		return _start(clock - (1.0 - p) * duration)
	return state


## Transition progress in [0, 1] (1 = arrived or gone); STEADY and HIDDEN are complete. The clock difference is
## wrapped to [-512, 512) s, so a start a moment ahead (half-second rounding) or after a rewind waits at 0 instead of
## reading as finished (transitions last at most 300 s and settle when done).
static func progress(state: float, clock: float, duration: float) -> float:
	if state == STEADY or state == HIDDEN:
		return 1.0
	var start: float = state if state >= 0.0 else -state - 0.5
	return clampf((fposmod(clock - start + HALF_WRAP_S, ShaderClock.WRAP_S) - HALF_WRAP_S) / duration, 0.0, 1.0)


## Share of the departure offset applied (0 = on its circuit, 1 = away), as sky_birds.gdshader computes it.
static func departure_share(state: float, clock: float, duration: float) -> float:
	if state == STEADY:
		return 0.0
	if state == HIDDEN:
		return 1.0
	var eased: float = smoothstep(0.0, 1.0, progress(state, clock, duration))
	return eased if state >= 0.0 else 1.0 - eased


## Finishes transitions that have run their time (or all of them when the clock never moves, as on Home). Returns true
## when a buffer changed. Called by birds_runtime.gd every frame while a transition is pending.
static func settle(root: Node, clock: float, force: bool = false) -> bool:
	var changed := false
	for node: MultiMeshInstance3D in root.get_meta("bird_groups", []):
		var species: Array = node.get_meta("species_data")
		var layout: Array = node.get_meta("instances")
		var states: PackedFloat32Array = node.get_meta("states")
		var dirty := false
		for i: int in layout.size():
			var s: float = states[i]
			if s == STEADY or s == HIDDEN:
				continue
			if force or progress(s, clock, species[layout[i].species].departure.duration) >= 1.0:
				states[i] = HIDDEN if s >= 0.0 else STEADY
				dirty = true
		if dirty:
			node.set_meta("states", states)
			write_buffer(node)
			changed = true
	return changed


static func pending(root: Node) -> bool:
	for node: MultiMeshInstance3D in root.get_meta("bird_groups", []):
		for s: float in node.get_meta("states"):
			if s != STEADY and s != HIDDEN:
				return true
	return false


## Birds that are out or on their way first, then visible_instance_count = their number: away birds cost nothing.
static func write_buffer(node: MultiMeshInstance3D) -> void:
	var mm: MultiMesh = node.multimesh
	var layout: Array = node.get_meta("instances")
	var states: PackedFloat32Array = node.get_meta("states")
	var slot := 0
	for i: int in layout.size():
		if states[i] == HIDDEN:
			continue
		var item: Dictionary = layout[i]
		mm.set_instance_transform(slot, item.transform)
		mm.set_instance_custom_data(slot, Color(item.offset, item.track + SPECIES_STRIDE * item.species, states[i], item.hash))
		slot += 1
	mm.visible_instance_count = slot


## Drawn birds per group (tests and budget checks).
static func drawn(root: Node) -> Dictionary:
	var out := {}
	for node: MultiMeshInstance3D in root.get_meta("bird_groups", []):
		out[str(node.name)] = node.multimesh.visible_instance_count
	return out


## Instance layout for one group: [{flock, track (group index), species (slot), transform, offset, hash}].
static func instances(flocks: Array[Dictionary], species_order: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var track_base := 0
	for fi: int in flocks.size():
		var f: Dictionary = flocks[fi]
		var ntracks: int = (f.tracks as Array).size()
		var origin: Vector3 = Frames.ned_to_render(f.origin)
		for i: int in f.count:
			var h1: float = Palette.hash01(i, fi + 11, 1)
			var basis := Basis.IDENTITY
			if f.rotate_instances:
				basis = Basis(Vector3.UP, TAU * h1)
			if f.mirror_instances and Palette.hash01(i, fi + 11, 2) < 0.5:
				basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
			var offset := Vector3((Palette.hash01(i, fi + 11, 3) - 0.5) * 2.0 * f.spread_offset,
				float(f.base_height) + (Palette.hash01(i, fi + 11, 4) - 0.5) * 2.0 * f.spread_height,
				(Palette.hash01(i, fi + 11, 5) - 0.5) * 2.0 * f.spread_offset)
			out.append({
				flock = f.id,
				track = track_base + i % ntracks,
				species = species_order.find(f.species),
				transform = Transform3D(basis, origin + offset),
				offset = time_offset(float(i) / f.count * f.spread_time + h1 * 3.0),
				hash = floorf(Palette.hash01(i, fi + 11, 6) * 1024.0) / 1024.0,
			})
		track_base += ntracks
	return out


## Per-bird time offsets are whole half-seconds in [0, 1024) and hashes multiples of 1/1024 below 1: both exact in a
## half float, so the GPU sees the very values the CPU reference uses even if custom data is stored at 16 bits.
static func time_offset(seconds: float) -> float:
	return fposmod(roundf(seconds * 2.0) * 0.5, 1024.0)


## The departure displacement (render axes, metres) of a species in a group, as the shader applies it.
static func departure_vector(species: Dictionary, flocks: Array[Dictionary]) -> Vector3:
	var d: Dictionary = species.departure
	if d.mode == "climb":
		return Vector3(0.0, float(d.distance), 0.0)
	for f: Dictionary in flocks:
		if f.species == species.id:
			var away: Vector3 = Frames.ned_to_render(f.origin)
			away.y = 0.0
			return away.normalized() * float(d.distance) if away.length() > 1.0 else Vector3(float(d.distance), 0.0, 0.0)
	return Vector3.ZERO


## A transition start: the nearest half-second on the 1024 s clock (exact in a half float).
static func _start(seconds: float) -> float:
	return fposmod(roundf(seconds * 2.0) * 0.5, ShaderClock.WRAP_S)


static func _group(group: String, flocks: Array[Dictionary], species: Dictionary) -> MultiMeshInstance3D:
	var order: Array[String] = []
	var tracks: Array = []
	for f: Dictionary in flocks:
		if not order.has(f.species):
			order.append(f.species)
		tracks.append_array(f.tracks)
	var slots := 0
	for id: String in order:
		slots = maxi(slots, int(species[id].planform.fingers))
	var builds: Array = []
	var species_data: Array = []
	for id: String in order:
		builds.append(BirdPlanform.build(species[id].planform, species[id].span, slots))
		species_data.append(species[id])
	var material := ShaderMaterial.new()
	material.shader = SHADER
	_set_tables(material, tracks, species_data, builds, flocks)
	var layout: Array[Dictionary] = instances(flocks, order)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BirdPlanform.group_mesh(builds)
	mm.instance_count = layout.size()
	var box := AABB()
	for i: int in layout.size():
		var item: Dictionary = layout[i]
		var track: Dictionary = tracks[item.track]
		var local := AABB(_track_render(track.bbox_min), Vector3.ZERO).expand(_track_render(track.bbox_max))
		var world: AABB = item.transform * local
		var away: Vector3 = departure_vector(species_data[item.species], flocks)
		world = world.merge(AABB(world.position + away, world.size))
		box = world if i == 0 else box.merge(world)
	var node := MultiMeshInstance3D.new()
	node.name = "Birds_" + group
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.custom_aabb = box.grow(AABB_MARGIN_M)
	var states := PackedFloat32Array()
	states.resize(layout.size())
	states.fill(HIDDEN)
	node.set_meta("species", order)
	node.set_meta("species_data", species_data)
	node.set_meta("instances", layout)
	node.set_meta("states", states)
	node.set_meta("tracks", tracks)
	node.set_meta("triangles", builds[0].triangles)
	return node


static func _set_tables(material: ShaderMaterial, tracks: Array, species: Array, builds: Array,
		flocks: Array[Dictionary]) -> void:
	var packed: Dictionary = BirdTracks.pack(tracks)
	var gait_a := PackedVector4Array()
	var gait_b := PackedVector4Array()
	var gait_c := PackedVector4Array()
	var rig := PackedVector4Array()
	var top := PackedVector4Array()
	var under := PackedVector4Array()
	var tip := PackedVector4Array()
	var depart := PackedVector4Array()
	for i: int in species.size():
		var s: Dictionary = species[i]
		var g: Dictionary = s.gait
		gait_a.append(Vector4(g.flap_frequency_clock, deg_to_rad(g.flap_amplitude), g.burst_period, g.burst_duty))
		gait_b.append(Vector4(deg_to_rad(g.dihedral), deg_to_rad(g.hand_lag), deg_to_rad(g.tip_curl), g.fold))
		gait_c.append(Vector4(g.tail_twist, deg_to_rad(g.tail_wobble), s.departure.duration, 0.0))
		rig.append(builds[i].rig)
		# Packed arrays are values in GDScript: append to each one directly (appending through a list of them would
		# fill copies and leave the uniforms black).
		top.append(_rgba(s.colors.top))
		under.append(_rgba(s.colors.under))
		tip.append(_rgba(s.colors.tip))
		var away: Vector3 = departure_vector(s, flocks)
		depart.append(Vector4(away.x, away.y, away.z, 0.0))
	material.set_shader_parameter("seg_a", _pad(packed.seg_a, SEGMENT_SLOTS))
	material.set_shader_parameter("seg_b", _pad(packed.seg_b, SEGMENT_SLOTS))
	material.set_shader_parameter("track_info", _pad(packed.track_info, TRACK_SLOTS))
	for pair: Array in [["gait_a", gait_a], ["gait_b", gait_b], ["gait_c", gait_c], ["rig", rig],
			["color_top", top], ["color_under", under], ["color_tip", tip], ["depart", depart]]:
		material.set_shader_parameter(pair[0], _pad(pair[1], SLOTS))


static func _rgba(c: Color) -> Vector4:
	return Vector4(c.r, c.g, c.b, 1.0)


static func _pad(values: PackedVector4Array, size: int) -> PackedVector4Array:
	var out := values.duplicate()
	out.resize(size)
	return out


## Track (x east, y north, z up) to the MultiMesh's render axes (x east, y up, z south), as the shader does.
static func _track_render(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)
