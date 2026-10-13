## LU-25: one bounded cubemap, refreshed only when the simulation-owned lighting changes.
extends ReflectionProbe
var water_material: ShaderMaterial
var _signature := PackedByteArray()
var _offset_sign := 1.0

func _process(_delta: float) -> void:
	if water_material == null:
		return
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
