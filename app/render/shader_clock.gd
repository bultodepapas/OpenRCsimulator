# Shader clock (LANDSCAPE-PLAN L0d). Shaders NEVER read TIME (test.sh enforces it): animation would then depend on
# the rendering clock, captures would not repeat, and a sky reading TIME re-renders its radiance every frame.
# Instead every shader gets the global uniforms `sim_clock` (simulation time wrapped to [0, 1024) s, wrapped on the
# CPU in 64-bit) and `wind_vec` (zero until wind exists, M5). Animation frequencies must be multiples of 1/1024 Hz
# so the wrap is seamless. They follow pause, replays and fixed-fps runs exactly like the physics.
extends RefCounted

const WRAP_S := 1024.0

## The last values sent to the GPU (Godot's global_shader_parameter_get/_get_list are editor-only: outside the editor
## they print an engine error and return null, so tests and captures read these instead).
static var last_clock := 0.0
static var last_wind := Vector3.ZERO
static var _registered := false


## Registers the global uniforms (once, before any material that uses them compiles).
static func register() -> void:
	if _registered:
		return
	RenderingServer.global_shader_parameter_add(&"sim_clock", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	RenderingServer.global_shader_parameter_add(&"wind_vec", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_registered = true


## The clock value shaders see for a simulation time (s): wrapped in float64 before the GPU's float32 sees it.
static func value(sim_time: float) -> float:
	return fposmod(sim_time, WRAP_S)


static func update(sim_time: float, wind := Vector3.ZERO) -> void:
	last_clock = value(sim_time)
	last_wind = wind
	RenderingServer.global_shader_parameter_set(&"sim_clock", last_clock)
	RenderingServer.global_shader_parameter_set(&"wind_vec", wind)
