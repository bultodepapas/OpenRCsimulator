# L0d: the shader clock wraps simulation time to [0, 1024) s in 64-bit before shaders see it.
# The wiring (main feeds the session's simulation time every frame) is checked end to end in test_e2e_input.gd.
# Run: godot --headless --path . --script res://tests/test_shader_clock.gd
extends SceneTree

const ShaderClock := preload("res://render/shader_clock.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_check("t = 0 → 0", ShaderClock.value(0.0) == 0.0)
	_check("t = 1000.25 s → 1000.25", ShaderClock.value(1000.25) == 1000.25)
	_check("t = 2049.5 s → 1.5 (wrapped twice)", ShaderClock.value(2049.5) == 1.5)
	_check("a frequency of k/1024 Hz is seamless across the wrap", is_equal_approx(sin(TAU * 3.0 / 1024.0 * ShaderClock.value(1024.0 + 0.1)), sin(TAU * 3.0 / 1024.0 * 0.1)))
	_check("wrapping happens in float64: a 10-day flight keeps millisecond resolution",
		absf(ShaderClock.value(864000.0 + 0.001) - (fposmod(864000.0, 1024.0) + 0.001)) < 1e-9)
	ShaderClock.register()
	ShaderClock.register() # idempotent (adding twice would be an engine error)
	var have := RenderingServer.global_shader_parameter_get_list() # fine headless; editor-only under a real renderer
	_check("sim_clock and wind_vec registered once", have.count(&"sim_clock") == 1 and have.count(&"wind_vec") == 1, str(have))
	ShaderClock.update(2049.5)
	_check("update remembers the value it sent", ShaderClock.last_clock == 1.5 and ShaderClock.last_wind == Vector3.ZERO)
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
