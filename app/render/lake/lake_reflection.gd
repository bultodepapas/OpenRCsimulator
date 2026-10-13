## LU-25: one bounded cubemap, refreshed only when the simulation-owned lighting changes.
extends ReflectionProbe
var water_material: ShaderMaterial
var _signature := PackedByteArray()
var _offset_sign := 1.0
var _static_layers_ready := false

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
