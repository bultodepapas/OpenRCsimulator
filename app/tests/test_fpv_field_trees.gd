## The moving FPV camera can reach 3D trees behind the pilot and in the far ring. Exercise
## entry, hysteresis, exit and vertical overflight with the real imported mesh resources.
extends SceneTree

const Forest := preload("res://render/fpv_field_trees.gd")
const Treeline := preload("res://render/treeline.gd")
const Frames := preload("res://render/frames.gd")
const Field := preload("res://data/field_loader.gd")

var _failed := false


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failed = true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var forest := Forest.new()
	var trees := {id = "treeline", positions = [[-900.0, -400.0, 0.0], [-901.0, -404.0, 0.0], [700.0, 60.0, -4.0]]}
	forest.build(trees, {north = 140.0, east = 80.0, down = -3.0}, "high")
	_check(forest.position == Vector3(80.0, 3.0, -140.0), "The FPV forest uses the field's pilot-relative origin")
	var first := Frames.ned_to_render(trees.positions[0])
	forest.update_focus(Vector3.ZERO)
	_check(_drawn_parts(forest) == 0, "Distant placements use cards")
	forest.update_focus(first + Vector3.UP * 10.0)
	_check(forest._near.has(0) and forest._near.has(1) and _drawn_parts(forest) == 2,
		"Approaching from behind the pilot selects both far-ring 3D trees")
	if DisplayServer.get_name() != "headless":
		var card: Dictionary = forest._trees[0]
		var pose: Transform3D = card.batch.get_instance_transform(card.slot)
		_check(pose.basis.x.is_zero_approx() and pose.origin.is_equal_approx(first),
			"The impostor under the detailed model has zero area")
	var asset: String = Treeline.DETAIL_ASSETS[Treeline.identity(-900.0, -400.0).species]
	var parts: Array = forest._parts[asset]
	if not parts.is_empty():
		var model: MultiMeshInstance3D = parts[0].node
		_check(model.custom_aabb.has_point(first + Vector3.UP * 6.0), "Visible tree batch bounds follow the far grove")
	var border := forest._radius + Forest.EXIT_MARGIN_M / 2.0
	forest.update_focus(first + Vector3.RIGHT * border)
	_check(forest._near.has(0), "A small excursion beyond the entry radius keeps the near representation")
	forest.update_focus(first + Vector3.UP * 200.0)
	_check(forest._near.is_empty() and _drawn_parts(forest) == 0, "A high overflight releases all detailed instances")
	if DisplayServer.get_name() != "headless":
		var card: Dictionary = forest._trees[0]
		var pose: Transform3D = card.batch.get_instance_transform(card.slot)
		_check(pose.is_equal_approx(Transform3D(Basis.IDENTITY, first)), "A distant card recovers its exact pose")
	forest.update_focus(Frames.ned_to_render(trees.positions[2]))
	_check(forest._near.size() == 1 and forest._near.has(2) and _drawn_parts(forest) == 1,
		"A camera jump puts the new grove in 3D and leaves the previous one as cards")
	if DisplayServer.get_name() != "headless":
		await _check_rendered_handoff(forest, first)
	forest.free()
	_check_stock_capacity()
	_check_dense_capacity()
	if not _failed:
		print("FPV field tree tests passed")
	quit(1 if _failed else 0)


func _check_stock_capacity() -> void:
	var field := Field.load_from()
	if not field.ok:
		_check(false, "Club Field geometry loads")
		return
	var forest := Forest.new()
	var group: Dictionary = field.field.objects[0]
	forest.build(group, field.field.pilot, "extreme")
	var slots := 0
	for asset: String in forest._parts:
		var parts: Array = forest._parts[asset]
		if not parts.is_empty():
			slots += int(parts[0].node.multimesh.instance_count)
	_check(slots > 0 and slots < group.positions.size() / 2.0, "Stock near-tree buffers cover local groves")
	for id: int in [0, 401, 821, 1267, 1679]:
		var eye := Frames.ned_to_render(group.positions[id])
		forest.update_focus(eye + Vector3.UP * 200.0)
		forest.update_focus(eye)
		var expected := {}
		for point: Array in group.positions:
			if Frames.ned_to_render(point).distance_squared_to(eye) <= forest._radius * forest._radius:
				var shape := Treeline.identity(point[0], point[1])
				var asset: String = Treeline.DETAIL_ASSETS[shape.species]
				expected[asset] = int(expected.get(asset, 0)) + 1
		for asset: String in forest._parts:
			for part: Dictionary in forest._parts[asset]:
				_check(part.node.multimesh.visible_instance_count == expected.get(asset, 0),
					"Every %s part in stock grove %d is drawn at the new focus" % [asset, id])
	print("FPV near-tree slots at extreme: %d for %d field trees" % [slots, group.positions.size()])
	forest.free()


func _check_dense_capacity() -> void:
	var positions := []
	for x in range(-10, 10):
		for z in range(-10, 10):
			positions.append([x * 0.25, z * 0.25, 0.0])
	var forest := Forest.new()
	forest.build({id = "dense", positions = positions}, {north = 0, east = 0, down = 0}, "low")
	forest.update_focus(Vector3.ZERO)
	_check(forest._near.size() == positions.size(), "A custom grove across four grid cells retains every tree")
	for asset: String in forest._parts:
		var count := 0
		for tree: Dictionary in forest._trees:
			if tree.asset == asset:
				count += 1
		for part: Dictionary in forest._parts[asset]:
			_check(part.node.multimesh.visible_instance_count == count, "Dense custom grove fits the %s buffer" % asset)
	forest.free()


func _drawn_parts(forest: Node3D) -> int:
	var count := 0
	for node: MultiMeshInstance3D in forest.get_node("ImportedVegetationBatches").get_children():
		count += node.multimesh.visible_instance_count
	return count


## Fixed camera, same trees. Compare actual drawn silhouettes with each representation in
## isolation. A shader drawing a promoted card despite its collapsed instance fails here.
func _check_rendered_handoff(forest: Node3D, first: Vector3) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(forest)
	forest.set_process(false)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var target := forest.global_position + first + Vector3.UP * 9.0
	camera.position = target + Vector3(0.0, 0.0, 30.0)
	camera.look_at(target)
	camera.far = 100.0
	camera.make_current()
	forest.update_focus(first)
	var models := forest.get_node("ImportedVegetationBatches") as Node3D
	var near_pixels := await _coverage(viewport)
	models.hide()
	var residual_pixels := await _coverage(viewport)
	forest.update_focus(first + Vector3.UP * 200.0)
	var card_pixels := await _coverage(viewport)
	_check(near_pixels > 80 and residual_pixels == 0 and card_pixels > 80,
		"GPU handoff (3D, with models hidden, restored cards) drew %d/%d/%d pixels" % [near_pixels, residual_pixels, card_pixels])
	print("FPV forest GPU coverage: near %d, residual %d, far %d" % [near_pixels, residual_pixels, card_pixels])
	viewport.remove_child(forest)
	viewport.free()


func _coverage(viewport: SubViewport) -> int:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var visible_pixels := 0
	for y in pixels.get_height():
		for x in pixels.get_width():
			if pixels.get_pixel(x, y).a > 0.5:
				visible_pixels += 1
	return visible_pixels
