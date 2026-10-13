## CR-17a: material-specific scenery aftermath, entirely downstream of committed float64 damage.
## Intact objects retain their existing batches. Debris/marks are capped and never collide with the flight solver.
extends Node3D
const Frames := preload("res://render/frames.gd")
const MeshKit := preload("res://scenery/mesh_kit.gd")
const DamageBatches := preload("res://scenery/damage_batches.gd")
const Scenery := preload("res://scenery/scenery.gd")

const MAX_EFFECT_GROUPS := 24
const MAX_FRAGMENTS_PER_OBJECT := 6
const PARTICLES_PER_IMPACT := 32
const COLORS := {wood = Color("#96744e"), wire = Color("#78817e"), foam = Color("#e5e3d9"),
	straw = Color("#ae945c"), foliage = Color("#617643"), metal = Color("#6b7274"), masonry = Color("#9a9386"),
	wood_mark = Color("#96744e"), foliage_mark = Color("#617643")}

var flight: Node3D
var _sources: Array[MeshInstance3D] = []
var _motion: Array[Node3D] = []
var _shown: Dictionary = {}
var _groups: Array[Dictionary] = []

func configure(scene: Node3D) -> void:
	flight = scene
	_collect(flight._field_node)
	flight.session.scenery_damage_changed.connect(sync)
	sync()

func _collect(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D and node.has_meta("damage_ranges"):
		_sources.append(node)
	if node is Node3D and node.has_meta("damage_motion_id"):
		_motion.append(node)
	for child: Node in node.get_children():
		_collect(child)

## Public for checkpoint lighting commits: restore the current damage after any shadow rebuild.
func sync(force_shadows: bool = false) -> void:
	var damage: Dictionary = flight.session.scenery_damage()
	if damage.is_empty() or not _shown.keys().all(func(id: Variant) -> bool: return damage.has(id)):
		_clear_effects()
		_shown.clear()
	for source: MeshInstance3D in _sources:
		DamageBatches.apply(source, damage)
	for node: Node3D in _motion:
		node.visible = damage.get(node.get_meta("damage_motion_id"), {}).get("state", "") != "broken"
	Scenery.apply_damage(flight._field_node, damage, force_shadows)
	var ids := damage.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = damage[id]
		var fingerprint := var_to_bytes(record)
		if _shown.get(id) == fingerprint:
			continue
		for index: int in range(_groups.size() - 1, -1, -1):
			if str(_groups[index].id) == id:
				_groups[index].root.free()
				_groups.remove_at(index)
		_shown[id] = fingerprint
		var age_ticks := maxi(0, flight.session.sim.tick - int(record.tick))
		_spawn(id, record, float(age_ticks) * flight.session.sim.dt())

func _spawn(id: String, record: Dictionary, age: float) -> void:
	while _groups.size() >= MAX_EFFECT_GROUPS:
		var oldest: Dictionary = _groups.pop_front()
		oldest.root.free()
	var root := Node3D.new()
	root.name = "SceneryImpact"
	add_child(root)
	var point := Frames.ned_to_render(Array(record.point_ned))
	var normal := Frames.ned_to_render(Array(record.normal_ned)).normalized()
	var incoming := Frames.ned_to_render(Array(record.velocity_ned))
	var profile := str(record.profile)
	var color: Color = COLORS.get(profile, Color.GRAY)
	var fragments: Array[Dictionary] = []
	var seed := int(id.hash()) & 0x7fffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if record.state == "broken":
		for source: MeshInstance3D in _sources:
			var piece := DamageBatches.piece(source, id)
			if piece.is_empty():
				continue
			if profile == "wire":
				_wire_ends(root, source, id)
			elif profile == "straw":
				_straw_debris(root, source, piece, incoming, rng, fragments)
			elif profile == "wood" and _beam_fragments(root, source, id, incoming, rng, fragments):
				pass
			else:
				_fragments(root, source, piece, profile, incoming, rng, fragments)
	else:
		_scar(root, point, normal, color, profile, seed)
	var particles: CPUParticles3D = null
	if age < 2.5:
		particles = _burst(root, point, normal, color, profile, seed)
	_groups.append({id = id, root = root, fragments = fragments, age = age, particles = particles, profile = profile})
	_update_group(_groups.back())

func _wire_ends(root: Node3D, source: MeshInstance3D, id: String) -> void:
	for range_data: Dictionary in source.get_meta("damage_ranges", []):
		if str(range_data.id) != id or not range_data.has("beam"):
			continue
		var beam: Dictionary = range_data.beam
		var a: Vector3 = source.global_transform * beam.a
		var b: Vector3 = source.global_transform * beam.b
		var kit := MeshKit.new()
		for endpoints: Array in [[a, b], [b, a]]:
			var attached: Vector3 = endpoints[0]
			var cut: Vector3 = attached.lerp(endpoints[1], 0.42)
			cut.y = maxf(0.025, cut.y - 0.55)
			var elbow := attached.lerp(cut, 0.5) + Vector3.DOWN * 0.10
			kit.beam(attached, elbow, beam.width, beam.color)
			kit.beam(elbow, cut, beam.width, beam.color)
		_mesh(root, kit)

func _beam_fragments(root: Node3D, source: MeshInstance3D, id: String, incoming: Vector3,
		rng: RandomNumberGenerator, fragments: Array[Dictionary]) -> bool:
	for range_data: Dictionary in source.get_meta("damage_ranges", []):
		if str(range_data.id) != id or not range_data.has("beam"):
			continue
		var beam: Dictionary = range_data.beam
		for index: int in 3:
			var a: Vector3 = beam.a.lerp(beam.b, float(index) / 3.0)
			var b: Vector3 = beam.a.lerp(beam.b, float(index + 1) / 3.0)
			var center := (a + b) * 0.5
			var kit := MeshKit.new()
			kit.beam(a - center, b - center, beam.width, beam.color)
			_add_fragment(root, source, kit, center, "wood", incoming, rng, fragments)
		return true
	return false

func _straw_debris(root: Node3D, source: MeshInstance3D, piece: MeshKit, incoming: Vector3,
		rng: RandomNumberGenerator, fragments: Array[Dictionary]) -> void:
	var center := Vector3.ZERO
	for vertex: Vector3 in piece.verts:
		center += vertex
	center /= piece.verts.size()
	for index: int in MAX_FRAGMENTS_PER_OBJECT:
		var kit := MeshKit.new()
		kit.ellipsoid(Vector3.ZERO, Vector3(rng.randf_range(0.25, 0.45), 0.10, 0.22), COLORS.straw,
			int(rng.randi()), 7, 3)
		_add_fragment(root, source, kit, center, "straw", incoming, rng, fragments)

func _fragments(root: Node3D, source: MeshInstance3D, piece: MeshKit, profile: String,
		incoming: Vector3, rng: RandomNumberGenerator, fragments: Array[Dictionary]) -> void:
	# Source triangles stay in their original colours; spatial partitions give a bounded lightweight breakup.
	var kits: Array[MeshKit] = []
	for index: int in MAX_FRAGMENTS_PER_OBJECT:
		kits.append(MeshKit.new())
	var bounds := AABB(piece.verts[0], Vector3.ZERO)
	for vertex: Vector3 in piece.verts:
		bounds = bounds.expand(vertex)
	var axis := bounds.size.max_axis_index()
	for first: int in range(0, piece.verts.size(), 3):
		var center := (piece.verts[first] + piece.verts[first + 1] + piece.verts[first + 2]) / 3.0
		var fraction: float = (center[axis] - bounds.position[axis]) / maxf(0.001, bounds.size[axis])
		var kit := kits[clampi(int(fraction * MAX_FRAGMENTS_PER_OBJECT), 0, MAX_FRAGMENTS_PER_OBJECT - 1)]
		kit.verts.append_array(piece.verts.slice(first, first + 3))
		kit.norms.append_array(piece.norms.slice(first, first + 3))
		kit.cols.append_array(piece.cols.slice(first, first + 3))
	for kit: MeshKit in kits:
		if kit.is_empty():
			continue
		var center := Vector3.ZERO
		for vertex: Vector3 in kit.verts:
			center += vertex
		center /= kit.verts.size()
		for index: int in kit.verts.size():
			kit.verts[index] -= center
		_add_fragment(root, source, kit, center, profile, incoming, rng, fragments)

func _add_fragment(root: Node3D, source: MeshInstance3D, kit: MeshKit, center: Vector3,
		profile: String, incoming: Vector3, rng: RandomNumberGenerator, fragments: Array[Dictionary]) -> void:
	var node := _mesh(root, kit)
	var bounds := node.mesh.get_aabb()
	var kick := incoming.limit_length(12.0) * 0.25 + Vector3(rng.randf_range(-1.3, 1.3), rng.randf_range(0.6, 2.2), rng.randf_range(-1.3, 1.3))
	fragments.append({node = node, position = source.global_transform * center, velocity = kick,
		bounds = bounds, floor_y = maxf(0.025, -bounds.position.y + 0.025),
		spin = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5)), rest_basis = source.global_basis,
		fade = profile == "foliage"})

func _mesh(root: Node3D, kit: MeshKit) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = kit.to_mesh(Scenery.opaque_material())
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	return node

func _scar(root: Node3D, point: Vector3, normal: Vector3, color: Color, profile: String, seed: int) -> void:
	if profile == "foliage_mark":
		return # leaves shed, the whole crown/hedge remains standing.
	var kit := MeshKit.new()
	var size := 0.12 if profile in ["wood_mark", "metal"] else 0.20
	# A shallow irregular impact patch, offset along the contact normal to prevent depth fighting.
	var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := tangent.cross(normal).normalized()
	kit.xf = Transform3D(Basis(tangent, up, normal), point + normal * 0.012)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for at: int in 9:
		var a := TAU * at / 9.0
		var b := TAU * (at + 1) / 9.0
		kit.tri(Vector3.ZERO, Vector3(cos(a), sin(a), 0) * size * rng.randf_range(0.7, 1.1),
			Vector3(cos(b), sin(b), 0) * size, color.darkened(0.55))
	var node := _mesh(root, kit)
	var material := node.mesh.surface_get_material(0) as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _burst(root: Node3D, point: Vector3, normal: Vector3, color: Color, profile: String, seed: int) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.amount = 8 if profile == "wire" else PARTICLES_PER_IMPACT
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 1.8 if profile in ["foliage", "foliage_mark", "straw"] else 0.9
	particles.use_fixed_seed = true
	particles.seed = seed
	particles.position = point
	particles.local_coords = false
	particles.direction = (normal + Vector3.UP * 0.7).normalized()
	particles.spread = 65.0
	particles.initial_velocity_min = 0.7
	particles.initial_velocity_max = 3.5
	particles.gravity = Vector3.DOWN * (1.5 if profile in ["foliage", "foliage_mark", "straw"] else 9.81)
	particles.scale_amount_min = 0.012
	particles.scale_amount_max = 0.045
	particles.color = color
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.18, 1.0) if profile in ["wood", "wood_mark", "straw"] else Vector3.ONE
	mesh.material = material
	particles.mesh = mesh
	root.add_child(particles)
	particles.emitting = true
	return particles

func _process(delta: float) -> void:
	if flight == null:
		return
	# Crash aftermath advances while the crash holds the flight; menus/focus/manual pauses freeze it.
	var paused: bool = not flight.session.holds.is_empty() or (flight.session.sim.paused and flight.session.crash.is_empty())
	for group: Dictionary in _groups:
		if group.particles != null:
			group.particles.speed_scale = 0.0 if paused else 1.0
		if not paused:
			var previous_age: float = group.age
			group.age += minf(delta, 0.1)
			if previous_age < 5.0:
				_update_group(group)

func _update_group(group: Dictionary) -> void:
	for fragment: Dictionary in group.fragments:
		var t := minf(float(group.age), 5.0)
		var node: MeshInstance3D = fragment.node
		var floor_y: float = fragment.floor_y
		var start: Vector3 = fragment.position
		var velocity: Vector3 = fragment.velocity
		var landing_time := (velocity.y + sqrt(maxf(0.0, velocity.y * velocity.y + 19.62 * maxf(0.0, start.y - floor_y)))) / 9.81
		t = minf(t, landing_time)
		node.position = start + velocity * t + Vector3.DOWN * 4.905 * t * t
		node.basis = Basis.from_euler(fragment.spin * t) * fragment.rest_basis
		var bounds: AABB = fragment.bounds
		var c := node.basis * bounds.get_center()
		var h := bounds.size * 0.5
		var extent := absf(node.basis.x.y) * h.x + absf(node.basis.y.y) * h.y + absf(node.basis.z.y) * h.z
		node.position.y = maxf(0.025 - c.y + extent, node.position.y)
		node.visible = not fragment.fade or group.age < 4.0

func _clear_effects() -> void:
	for group: Dictionary in _groups:
		group.root.free()
	_groups.clear()
