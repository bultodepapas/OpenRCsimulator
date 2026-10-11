# FIELD-WORLD-PLAN FW-23: the current tonemap exposure as the global shader uniform `world_exposure`, so self-luminous
# shaders (render/world/light_sprite.gdshader) cap their on-screen value against the exposure the eye is adapted to
# at this moment, not the one at build time. Registered lazily, like render/shader_clock.gd.
extends RefCounted

static var last := 0.6
static var _registered := false


static func register() -> void:
	if _registered:
		return
	RenderingServer.global_shader_parameter_add(&"world_exposure", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, last)
	_registered = true


static func set_value(exposure: float) -> void:
	register()
	last = exposure
	RenderingServer.global_shader_parameter_set(&"world_exposure", exposure)
