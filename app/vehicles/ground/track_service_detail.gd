## Low, sourced course hardware. Every footprint is checked against the road sampler.
extends RefCounted

const TAPE := preload("res://assets/landscape/track-tape-barrier/barrier-tape-on-weighted-posts.glb")
const CABINET := preload("res://assets/landscape/track-timing-cabinet/utility_box_01_1k.gltf")
const CABINET_SCALE := 0.6
static var _batched_tape: ArrayMesh


static func add(root: Node3D, track: Dictionary, road: Callable) -> void:
	if root == null or track.is_empty() or not road.is_valid():
		return
	var detail := Node3D.new()
	detail.name = "TrackServiceDetail"
	root.add_child(detail)
	var ce := float(track.center_east_m)
	var cn := float(track.center_north_m)
	var radius := float(track.radius_m)
	var clear_half := float(track.lane_width_m) * 0.5 + float(track.shoulder_m)
	var south_edge := cn - radius - clear_half
	var north_edge := cn + radius + clear_half
	# Portable spectator limits sit beyond the south jump and north roller verges.
	_add_asset(detail, road, TAPE, "SouthJumpSafetyTape",
		ce + 12.0, south_edge - 2.3, 1.73, 0.23, 1.0)
	_add_asset(detail, road, TAPE, "NorthRollerSafetyTape",
		ce - 8.0, north_edge + 2.5, 1.73, 0.23, 1.0)
	# A small weatherproof controller is near the timing heads, clear of the lane.
	_add_asset(detail, road, CABINET, "TimingControlCabinet",
		ce - float(track.half_straight_m) + 10.0, south_edge - 1.5,
		0.21, 0.18, CABINET_SCALE)


static func _add_asset(parent: Node3D, road: Callable, source: PackedScene,
		name_value: String, east: float, north: float,
		half_east: float, half_north: float, scale_value: float) -> void:
	if not _clear_footprint(road, east, north, half_east, half_north):
		return
	var sample: Dictionary = road.call(north, east)
	var asset: Node3D
	if source == TAPE:
		asset = Node3D.new()
		var tape_mesh := MeshInstance3D.new()
		tape_mesh.name = "TapeAndWeightedPosts"
		tape_mesh.mesh = _tape_mesh()
		asset.add_child(tape_mesh)
	else:
		asset = source.instantiate() as Node3D
	asset.name = name_value
	asset.position = Vector3(east, float(sample.height_m) + 0.004, -north)
	asset.scale = Vector3.ONE * scale_value
	parent.add_child(asset)


static func _tape_mesh() -> ArrayMesh:
	if _batched_tape != null:
		return _batched_tape
	var source := TAPE.instantiate() as Node3D
	var materials: Array[Material] = []
	var builders: Array[SurfaceTool] = []
	_collect_tape(source, Transform3D.IDENTITY, materials, builders)
	var combined := ArrayMesh.new()
	for builder in builders:
		builder.commit(combined)
	source.free()
	_batched_tape = combined
	return combined


static func _collect_tape(node: Node3D, accumulated: Transform3D,
		materials: Array[Material], builders: Array[SurfaceTool]) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		for surface in range(part.mesh.get_surface_count()):
			if part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var material := part.get_active_material(surface)
			var slot := materials.find(material)
			if slot == -1:
				slot = materials.size()
				materials.append(material)
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builder.set_material(material)
				builders.append(builder)
			builders[slot].append_from(part.mesh, surface, accumulated)
	for child in node.get_children():
		if child is Node3D:
			_collect_tape(child, accumulated * (child as Node3D).transform, materials, builders)


static func _clear_footprint(road: Callable, east: float, north: float,
		half_east: float, half_north: float) -> bool:
	for e_offset in [-half_east, 0.0, half_east]:
		for n_offset in [-half_north, 0.0, half_north]:
			var value: Variant = road.call(north + n_offset, east + e_offset)
			if typeof(value) != TYPE_DICTIONARY:
				return false
			var sample: Dictionary = value
			if not is_finite(float(sample.get("height_m", NAN))):
				return false
			var coverage := float(sample.get("track_coverage", sample.get("coverage", NAN)))
			if not is_finite(coverage) or coverage < 0.0 or coverage > 0.0001:
				return false
	return true
