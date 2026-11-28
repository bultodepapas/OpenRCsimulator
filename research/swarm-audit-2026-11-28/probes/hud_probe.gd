extends SceneTree

const Manager := preload("res://render/overlays/overlay_manager.gd")

func _initialize() -> void:
	call_deferred("_run")

# Public plus internal descendants; includes each named widget root in the subtotal.
func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children(true):
		total += _count_nodes(child)
	return total

func _run() -> void:
	var rows := []
	for preset in ["off", "pilot", "cockpit"]:
		var manager := Manager.new({"preset":preset})
		root.add_child(manager)
		var visible_optional := 0
		var hidden_nodes := 0
		var nodes := 0
		var glass := 0
		var loaded_icons := 0
		for key in Manager.PLAYER_POSITIONS.keys():
			var widget: Control = manager.frames[key]
			var count := _count_nodes(widget)
			nodes += count
			if widget.is_visible_in_tree(): visible_optional += 1
			else: hidden_nodes += count
			if is_instance_valid(widget._glass): glass += 1
			if is_instance_valid(widget._header_icon.texture): loaded_icons += 1
		var fuel: Control = manager.frames.fuel
		rows.append({"preset":preset, "manager_nodes":_count_nodes(manager), "frame_slots":manager.frames.size(),
			"optional_widgets":Manager.PLAYER_POSITIONS.size(), "visible_optional":visible_optional,
			"optional_nodes":nodes, "hidden_optional_nodes":hidden_nodes, "glass":glass, "loaded_header_icons":loaded_icons,
			"fuel_visible":fuel.is_visible_in_tree(), "fuel_material":is_instance_valid(fuel._liquid_material)})
		root.remove_child(manager)
		manager.free()
	print("HUD_ALLOCATION ", JSON.stringify(rows))
	var ok: bool = rows[0].visible_optional == 0 and rows[1].visible_optional == 0 and rows[2].visible_optional == 5 \
		and rows[0].hidden_optional_nodes > 100 and rows[0].hidden_optional_nodes == rows[1].hidden_optional_nodes \
		and rows[0].glass == 0 and rows[2].glass == 5 and rows[0].fuel_material and not rows[0].fuel_visible
	if ok: print("HUD_EAGER_CONTROLS_CONFIRMED")
	quit(0 if ok else 1)
