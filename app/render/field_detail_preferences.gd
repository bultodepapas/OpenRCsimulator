extends RefCounted
## Visual settings for the field. Membership is assigned by the render builders.

const TREES := &"openrc_visual_trees"
const GROUND_SIMPLE := &"openrc_ground_simple"

static var _tree_detail := "full"
static var _ground_simple := false


static func apply(tree: SceneTree, config: Dictionary) -> void:
	var detail := str(config.get("tree_detail", "full"))
	if detail != _tree_detail:
		_tree_detail = detail
		for node: Node3D in tree.get_nodes_in_group(TREES):
			_apply_tree(node)
	var simple: bool = config.get("ground_detail", "full") == "simple"
	if simple != _ground_simple:
		_ground_simple = simple
		RenderingServer.global_shader_parameter_set(GROUND_SIMPLE, simple)


static func tree_half_angle(scene_angle: float) -> float:
	return scene_angle if _tree_detail == "full" else 0.0


static func register_tree(node: Node3D) -> void:
	node.add_to_group(TREES)
	if node is GeometryInstance3D:
		node.set_meta(&"openrc_tree_lod_bias", node.lod_bias)
	_apply_tree(node)


static func _apply_tree(node: Node3D) -> void:
	node.visible = _tree_detail != "off"
	if node is GeometryInstance3D:
		var original := float(node.get_meta(&"openrc_tree_lod_bias"))
		node.lod_bias = original * 0.5 if _tree_detail == "simple" else original
