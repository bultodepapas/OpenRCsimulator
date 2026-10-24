## VQ-04a-F1: cached geometry shadows for flight cues and nearby static scenery.
## Uses the same projection as the aircraft, without changing scenery ownership.
extends Node

const Projected = preload("res://render/projected_shadow.gd")
const WindsockProjected = preload("res://render/windsock_projected_shadow.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Scenery = preload("res://scenery/scenery.gd")
const MAX_SCENERY_RANGE := 100.0 # artistic near-field budget, metres from pilot
const MAX_MAPS := 16
const MAX_TARGET_PIXELS := 8 * 1024 * 1024 # <=64 MiB nominal RGBA8 + 32-bit depth
const OPACITY := 0.40 # artistic direct-light reduction, before time-of-day strength

var projectors: Array[Node] = []
var snapshot: Dictionary = {}
var target_pixels := 0
var _light_signature: Array = []


static func attach(field_node: Node3D, field: Dictionary, lighting: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--field-shadows=off"):
		return # explicit evidence/recovery route keeps the legacy contact shadows
	var manager := new()
	manager.name = "ProjectedFieldShadows"
	field_node.add_child(manager)
	manager.snapshot = lighting.duplicate(true)
	var cues_complete := true
	for cue: Dictionary in field.get("flight_cues", []):
		var model := field_node.get_node_or_null(NodePath(str(cue.id))) as Node3D
		# The windsock keeps its static pole, and shares the visible GPU deformation
		# for the moving sleeve and swivelling hardware in the same coverage map.
		var shape: Dictionary = {}
		if model != null and cue.type == "windsock":
			var support := model.get_node_or_null("Support") as Node3D
			if support != null:
				shape = Projected.collect(support, 0.04)
		if model == null or not manager.add_caster(model, shape):
			cues_complete = false
	# Legacy cues share one mesh. Keep the complete old set if any new cue fails,
	# avoiding both missing contacts and overlapping old/new receivers.
	if not cues_complete:
		for projector in manager.projectors:
			projector.free()
		manager.projectors.clear()
		manager.target_pixels = 0
	var contacts := field_node.get_node_or_null("FlightCueShadows") as MeshInstance3D
	if contacts != null and not manager.projectors.is_empty():
		contacts.visible = false
	var scenery := field_node.get_node_or_null("Scenery") as Node3D
	if scenery != null:
		var pilot := Vector2(float(field.pilot.east), -float(field.pilot.north))
		var population := scenery.get_node_or_null("Population") as Node3D
		var candidate_cells: Array[MeshInstance3D] = []
		for node in scenery.get_children():
			if not node is MeshInstance3D or not str(node.name).begins_with("cell_"):
				continue
			var box: AABB = node.mesh.get_aabb()
			var centre := box.get_center()
			if box.size.y < 0.08 or Vector2(centre.x, centre.z).distance_to(pilot) > MAX_SCENERY_RANGE:
				continue
			candidate_cells.append(node)
		var owners := population_cell_owners(candidate_cells, population, pilot)
		for node in candidate_cells:
			var shape := collect_cell_shape(node, population, pilot, MAX_SCENERY_RANGE, 0.04, owners)
			if manager.add_caster(node, shape):
				var old := scenery.get_node_or_null(NodePath(str(node.name).replace("cell_", "shadows_"))) as MeshInstance3D
				if old != null:
					old.visible = false
	if manager.projectors.is_empty():
		manager.free()
		return
	manager.apply(lighting)


static func apply_lighting(field_node: Node3D, lighting: Dictionary) -> void:
	var manager := field_node.get_node_or_null("ProjectedFieldShadows")
	if manager != null:
		manager.apply(lighting)


func add_caster(model: Node3D, collected_shape: Dictionary = {}) -> bool:
	if projectors.size() >= MAX_MAPS:
		return false
	var shape: Dictionary = collected_shape if not collected_shape.is_empty() else Projected.collect(model, 0.04)
	if shape.is_empty():
		return false
	var longest := maxf(shape.bounds.size.x, shape.bounds.size.z)
	# At most 1024² per static batch, without an MSAA depth/color target. Small cues
	# use 256². This preserves the narrow fence slats within the bounded memory cap.
	var moving_sock := model.has_meta("windsock_motion")
	var resolution := 512 if moving_sock else (256 if longest < 8.0 else (512 if longest < 20.0 else 1024))
	if target_pixels + resolution * resolution > MAX_TARGET_PIXELS:
		return false
	var projector: Node = WindsockProjected.new() if moving_sock else Projected.new()
	projector.name = "Caster_" + str(model.name)
	add_child(projector)
	projector.setup(model, shape, resolution, Viewport.MSAA_DISABLED)
	projector.set_meta("soft_height", maxf(shape.bounds.size.y * 0.5, 0.0))
	projector.set_meta("population_placements", int(shape.get("population_placements", 0)))
	projector.set_meta("population_triangles", int(shape.get("population_triangles", 0)))
	projectors.append(projector)
	target_pixels += resolution * resolution
	return true


## Add only nearby human MultiMesh instances to their existing static cell caster.
## This runs once during field assembly; it does not expand vehicle meshes or rebuild per frame.
static func population_cell_owners(cells: Array[MeshInstance3D], population: Node3D,
		pilot_xz: Vector2, max_range_m: float = MAX_SCENERY_RANGE) -> Dictionary:
	var owners: Dictionary = {}
	if population == null or cells.is_empty():
		return owners
	var cells_by_key: Dictionary = {}
	for cell in cells:
		var parts := str(cell.name).split("_")
		if parts.size() == 3:
			cells_by_key[Vector2i(int(parts[1]), int(parts[2]))] = cell
	var seen: Dictionary = {}
	for child in population.get_children():
		if not child is MultiMeshInstance3D:
			continue
		var asset := str(child.get_meta("source_asset", ""))
		if asset not in ["standing", "sitting", "pilot"]:
			continue
		var placements: Array = child.get_meta("placements", [])
		for i in placements.size():
			# SC-HUM-07: outfit variants share a pose; the asset key keeps each person unique.
			var id := "%s:%d" % [str(child.get_meta("asset_key", asset)), i]
			if seen.has(id):
				continue
			seen[id] = true
			var placement: Dictionary = placements[i]
			var placement_xf: Transform3D = placement.get("transform", Transform3D.IDENTITY)
			var pos := placement_xf.origin
			if Vector2(pos.x, pos.z).distance_to(pilot_xz) > max_range_m:
				continue
			var native_key := Scenery._cell(-pos.z, pos.x)
			if cells_by_key.has(native_key):
				owners[id] = native_key
				continue
			var best_key := Vector2i.ZERO
			var best_distance := INF
			for key: Vector2i in cells_by_key:
				var cell := cells_by_key[key] as MeshInstance3D
				var centre := cell.mesh.get_aabb().get_center()
				var distance := Vector2(centre.x - pos.x, centre.z - pos.z).length_squared()
				if distance < best_distance:
					best_distance = distance
					best_key = key
			owners[id] = best_key
	return owners


static func collect_cell_shape(cell: MeshInstance3D, population: Node3D, pilot_xz: Vector2,
		max_range_m: float = MAX_SCENERY_RANGE, min_height_m: float = 0.04,
		owner_by_placement: Dictionary = {}) -> Dictionary:
	var shape := Projected.collect(cell, min_height_m)
	if shape.is_empty() or population == null:
		return shape
	var cell_parts := str(cell.name).split("_")
	if cell_parts.size() != 3:
		return shape
	var cell_key := Vector2i(int(cell_parts[1]), int(cell_parts[2]))
	var vertices: PackedVector3Array = shape.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].duplicate()
	var selected: Dictionary = {}
	var elevated: Dictionary = {}
	var extra_triangles := 0
	for child in population.get_children():
		if not child is MultiMeshInstance3D or not child.visible:
			continue
		var source_asset := str(child.get_meta("source_asset", ""))
		if source_asset not in ["standing", "sitting", "pilot"]:
			continue
		var mm := (child as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			continue
		var placements: Array = child.get_meta("placements", [])
		var transforms: Array = child.get_meta("instance_transforms", [])
		var count: int = mini(mm.instance_count, mini(placements.size(), transforms.size()))
		if count == 0:
			continue
		var faces := mm.mesh.get_faces()
		if faces.is_empty():
			continue
		var relative_to_cell: Transform3D = cell.transform.affine_inverse() * population.transform * child.transform
		for i in count:
			var placement: Dictionary = placements[i]
			var placement_xf: Transform3D = placement.get("transform", Transform3D.IDENTITY)
			var pos := placement_xf.origin
			var placement_id := "%s:%d" % [str(child.get_meta("asset_key", source_asset)), i]
			var owner: Vector2i = owner_by_placement.get(placement_id, Scenery._cell(-pos.z, pos.x))
			if owner != cell_key or Vector2(pos.x, pos.z).distance_to(pilot_xz) > max_range_m:
				continue
			selected[placement_id] = true
			if float(placement.get("foot_height", 0.0)) > 0.001:
				elevated[placement_id] = true
			var instance_to_cell: Transform3D = relative_to_cell * transforms[i]
			# Transform the selected instance in native code; retain triangle order and cutoff.
			var placed_faces: PackedVector3Array = instance_to_cell * faces
			extra_triangles += Projected.append_above(vertices, placed_faces, min_height_m)
	if extra_triangles == 0:
		shape["population_placements"] = 0
		shape["population_elevated_placements"] = 0
		shape["population_triangles"] = 0
		return shape
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		bounds = bounds.expand(vertex)
	return {
		mesh = merged,
		bounds = bounds,
		triangles = vertices.size() / 3,
		population_placements = selected.size(),
		population_elevated_placements = elevated.size(),
		population_triangles = extra_triangles,
	}


func _ready() -> void:
	# Field and Home are assembled outside the tree; now every source has its final
	# global transform. No new animation clock.
	apply(snapshot)


func _process(_delta: float) -> void:
	# FW flowing time changes its shared visual state; read it, never advance it.
	var signature := [Atmosphere.shadow_direction(), Atmosphere.light_energy(), Atmosphere.shadow_strength()]
	if signature != _light_signature:
		apply(snapshot)


func apply(lighting: Dictionary) -> void:
	snapshot = lighting.duplicate(true)
	var direction := Atmosphere.shadow_direction(lighting)
	var strength: float = Atmosphere.shadow_strength(lighting)
	var flowing := lighting.is_empty() and not Atmosphere.state.is_empty()
	set_process(flowing)
	if flowing:
		strength *= clampf(Atmosphere.light_energy() / float(Atmosphere.Spec.ATMOSPHERE.sun_energy), 0.0, 1.0)
	_light_signature = [direction, Atmosphere.light_energy(lighting), Atmosphere.shadow_strength(lighting)]
	for projector in projectors:
		projector.refresh(float(projector.get_meta("soft_height")), direction,
			OPACITY * strength, strength > 0.0)
