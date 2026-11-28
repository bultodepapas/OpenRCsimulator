extends RefCounted
## Visual settings for the field. Membership is assigned by the render builders.

const TREES := &"openrc_visual_trees"
const GROUND_SIMPLE := &"openrc_ground_simple"

static var _tree_detail := "full"
static var _ground_simple := false
static var _ground_registered := false


## The ground shaders' global (every material including grass_surface.gdshaderinc reads it). A real renderer loads
## the project's shader_globals at startup, and only the editor may list them (outside it the list is an engine error).
## The headless dummy renderer of the exported build's field pack check did not have it, and those materials failed to
## compile. Register it in code when it is missing, before such a material compiles, as atmosphere.gd registers
## cloud_drift_offset.
static func ensure_ground_global() -> void:
	if _ground_registered:
		return
	var present: bool
	if DisplayServer.get_name() == "headless":
		present = RenderingServer.global_shader_parameter_get_list().has(GROUND_SIMPLE)
	else:
		present = ProjectSettings.has_setting("shader_globals/%s" % GROUND_SIMPLE)
	if not present:
		RenderingServer.global_shader_parameter_add(GROUND_SIMPLE, RenderingServer.GLOBAL_VAR_TYPE_BOOL, _ground_simple)
	_ground_registered = true


static func apply(tree: SceneTree, config: Dictionary) -> void:
	var detail := str(config.get("tree_detail", "full"))
	if detail != _tree_detail:
		_tree_detail = detail
		for node: Node3D in tree.get_nodes_in_group(TREES):
			_apply_tree(node)
	var simple: bool = config.get("ground_detail", "full") == "simple"
	if simple != _ground_simple:
		_ground_simple = simple
		ensure_ground_global()
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
