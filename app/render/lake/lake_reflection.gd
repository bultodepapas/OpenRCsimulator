## LU-25: one bounded cubemap, refreshed by lighting changes or explicit sky edits.
extends ReflectionProbe
const PlanarReflection := preload("res://render/lake/lake_planar_reflection.gd")
var water_material: ShaderMaterial
var _signature := PackedByteArray()
var _offset_sign := 1.0
var _static_layers_ready := false

## A paused sky edit can change clouds without changing any lighting uniform.
## Coalesce explicit edits with the ordinary lighting refresh on the next process.
func request_refresh() -> void:
	_signature = PackedByteArray()

func _process(_delta: float) -> void:
	if water_material == null:
		return
	if not _static_layers_ready:
		# Reflect the field, excluding the moving flight aircraft and the water surface itself.
		var pending: Array[Node] = [get_parent().get_parent()]
		while not pending.is_empty():
			var item: Node = pending.pop_back()
			pending.append_array(item.get_children())
			if item is GeometryInstance3D and item != get_parent().get_node("Water"):
				item.layers |= 8
		_static_layers_ready = true
		if PlanarReflection.requested():
			var planar := PlanarReflection.new()
			planar.name = "PlanarReflection"
			get_parent().add_child(planar)
			planar.configure(self, get_parent().get_node("Water"))
	var signature := var_to_bytes([water_material.get_shader_parameter("sun_dir"),
		water_material.get_shader_parameter("sun_lin"), water_material.get_shader_parameter("haze_lin"),
		water_material.get_shader_parameter("lobe_lin")])
	if signature == _signature:
		return
	_signature = signature
	# Godot UPDATE_ONCE refreshes on a transform change; no per-frame cube capture.
	position.x += _offset_sign * 0.001
	_offset_sign = -_offset_sign
	set_meta("refreshes", int(get_meta("refreshes", 0)) + 1)


## End-of-collection evidence only; installation and current activity are distinct.
## Return plain values so a saved report cannot retain any scene resources.
static func describe(field_root: Node) -> Dictionary:
	var result := {
		requested = OS.get_environment(PlanarReflection.ENVIRONMENT_KEY).strip_edges().to_lower(),
		mode = "absent", planar_active_at_report = false, capture_size_at_report = [0, 0],
	}
	if not is_instance_valid(field_root):
		return result
	var lake := field_root.get_node_or_null("Lake")
	if lake == null or lake.get_node_or_null("Water") == null \
			or not lake.get_node_or_null("Reflection") is ReflectionProbe:
		return result
	result.mode = "probe"
	var planar := lake.get_node_or_null("PlanarReflection") as PlanarReflection
	if planar == null:
		return result
	result.mode = "planar"
	if is_instance_valid(planar.reflect_viewport):
		var size: Vector2i = planar.reflect_viewport.size
		result.capture_size_at_report = [size.x, size.y]
		result.planar_active_at_report = planar.reflect_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	return result
