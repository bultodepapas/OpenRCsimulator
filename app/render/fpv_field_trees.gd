## Field treeline for a moving FPV camera. Distant trees share the existing eight card batches.
## Nearby trees use one reusable instance buffer per source mesh part. GPU resources are built
## with the field; moving across a grove updates instance data only.
extends Node3D

const Treeline := preload("res://render/treeline.gd")
const Detail := preload("res://render/field_tree_detail.gd")
const Frames := preload("res://render/frames.gd")
const Vegetation := preload("res://scenery/imported_vegetation.gd")
const Preferences := preload("res://render/field_detail_preferences.gd")

const CELL_M := 32.0
const ENTER_RADIUS_M := {"low": 18.0, "medium": 24.0, "high": 32.0, "extreme": 40.0}
const EXIT_MARGIN_M := 8.0
const UPDATE_TRAVEL_M := 3.0

var _radius: float
var _previous_eye := Vector3.INF
var _cells := {}
var _trees: Array = []
var _parts := {}
var _near := {}
var _pending_treeline := {}


func build(object_data: Dictionary, pilot: Dictionary, quality: String) -> void:
	name = str(object_data.id)
	position = Frames.ned_to_render([pilot.north, pilot.east, pilot.down])
	process_priority = 1 # after the flight camera takes its interpolated pose
	_radius = float(ENTER_RADIUS_M.get(quality, 32.0))
	Preferences.register_tree(self)
	if not visible:
		_pending_treeline = object_data
		return
	_prepare(object_data)


func _prepare(object_data: Dictionary) -> void:
	if Preferences.tree_half_angle(1.0) == 0.0:
		_radius = float(ENTER_RADIUS_M.low)
	_trees.resize(object_data.positions.size())
	var cards := Treeline.build(object_data, {north = 0.0, east = 0.0, down = 0.0}, NAN, 0.0, _trees)
	cards.name = "Cards"
	add_child(cards)
	if _trees.is_empty() or _trees[0] == null:
		set_process(false)
		return

	var batches := {}
	var windows := {}
	var capacities := {}
	var diameter := 2.0 * (_radius + EXIT_MARGIN_M) + 0.01 # include rounding at the visibility boundary
	for id in _trees.size():
		var tree: Dictionary = _trees[id]
		var asset: String = tree.asset
		var origin: Vector3 = tree.origin
		if Vegetation.queue(batches, asset, Vegetation.fit_to_height(asset, tree.height, tree.placement), id).is_empty():
			continue # retain the card if an optional detailed model is unavailable
		var cell := Vector2i(floori(origin.x / CELL_M), floori(origin.z / CELL_M))
		if not _cells.has(cell):
			_cells[cell] = []
		_cells[cell].append(id)
		# The visibility square can span at most two adjacent diameter-wide cells on each axis.
		# Count the four possible 2x2 windows containing this tree, including coincident trees.
		if not windows.has(asset):
			windows[asset] = {}
			capacities[asset] = 0
		var counts: Dictionary = windows[asset]
		var block := Vector2i(floori(origin.x / diameter), floori(origin.z / diameter))
		for dx in 2:
			for dz in 2:
				var corner := Vector2i(block.x - dx, block.y - dz)
				var count := int(counts.get(corner, 0)) + 1
				counts[corner] = count
				capacities[asset] = maxi(capacities[asset], count)
	# The tallest representative preserves each species' material and LOD setup.
	var representatives := {}
	for asset: String in batches:
		var tallest: Dictionary = batches[asset][0]
		for record: Dictionary in batches[asset]:
			var id: int = record.seed
			_trees[id].placement = record.transform
			if _trees[id].height > _trees[tallest.seed].height:
				tallest = record
		representatives[asset] = [tallest]
	var models := Vegetation.build(representatives, false, {tree_wind = Detail._tree_wind_enabled()})
	add_child(models)
	for asset: String in representatives:
		_parts[asset] = []
		var source_parts := Vegetation.get_parts(asset)
		for i in source_parts.size():
			var node := models.get_node_or_null("%s_Part_%02d" % [asset, i]) as MultiMeshInstance3D
			if node == null:
				continue
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.multimesh.instance_count = capacities[asset]
			node.multimesh.visible_instance_count = 0
			_parts[asset].append({node = node, transform = source_parts[i].transform, bounds = source_parts[i].bounds})


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not _pending_treeline.is_empty():
		_prepare(_pending_treeline)
		_pending_treeline = {}
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_focus(to_local(camera.global_position))


## Local render-space eye. Use distance to the full vertical extent so canopy-level flight
## selects the same geometry as a low pass, and high overflights stay inexpensive.
func update_focus(eye: Vector3) -> void:
	if eye.distance_squared_to(_previous_eye) < UPDATE_TRAVEL_M * UPDATE_TRAVEL_M:
		return
	_previous_eye = eye
	var outer := _radius + EXIT_MARGIN_M
	var selected := {}
	for x in range(floori((eye.x - outer) / CELL_M), floori((eye.x + outer) / CELL_M) + 1):
		for z in range(floori((eye.z - outer) / CELL_M), floori((eye.z + outer) / CELL_M) + 1):
			for id: int in _cells.get(Vector2i(x, z), []):
				var tree: Dictionary = _trees[id]
				if _parts[tree.asset].is_empty():
					continue
				var closest: Vector3 = tree.origin
				closest.y = clampf(eye.y, closest.y, closest.y + float(tree.height))
				var reach := outer if _near.has(id) else _radius
				if closest.distance_squared_to(eye) <= reach * reach:
					selected[id] = true
	if _near == selected:
		return
	# Collapse the replaced cards at their own roots (the scenery damage renderer uses the
	# same degenerate transform). Their encoded position, sector bounds and instance IDs persist.
	var changed := {}
	for id: int in _near:
		if not selected.has(id):
			var tree: Dictionary = _trees[id]
			changed[tree.asset] = true
			tree.batch.set_instance_transform(tree.slot, Transform3D(Basis.IDENTITY, tree.origin))
	for id: int in selected:
		if not _near.has(id):
			var tree: Dictionary = _trees[id]
			changed[tree.asset] = true
			tree.batch.set_instance_transform(tree.slot, Transform3D(Basis.from_scale(Vector3.ZERO), tree.origin))
	_near = selected
	for asset: String in changed:
		for part: Dictionary in _parts[asset]:
			var node: MultiMeshInstance3D = part.node
			var batch := node.multimesh
			var count := 0
			var bounds := AABB()
			for id: int in selected:
				var tree: Dictionary = _trees[id]
				if tree.asset != asset:
					continue
				var transform_value: Transform3D = tree.placement * part.transform
				batch.set_instance_transform(count, transform_value)
				batch.set_instance_color(count, Color.WHITE)
				batch.set_instance_custom_data(count, Color(fposmod(id * 0.61803398875, 1.0), 0, 0, 1))
				var placed: AABB = transform_value * (part.bounds as AABB)
				bounds = placed if count == 0 else bounds.merge(placed)
				count += 1
			if count > 0:
				# Include the maximum sway of every admitted tree species.
				node.custom_aabb = bounds.grow(Treeline.WIND_LEAN_M + 0.02)
				batch.custom_aabb = node.custom_aabb
			batch.visible_instance_count = count
