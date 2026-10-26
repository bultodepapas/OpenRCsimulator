extends SceneTree
const Probe := preload("res://render/lake/lake_reflection.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var probe := Probe.new()
	probe.reflection_mask = 2
	probe.cull_mask = 8
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.001, 0.002, 0.004)
	environment.ambient_light_energy = 0.7
	environment.tonemap_exposure = 12596.5
	probe._sync_color_ambient(environment, true)
	check("color-only world ambient reaches the Compatibility probe without exposure multiplication",
		probe.ambient_mode == ReflectionProbe.AMBIENT_COLOR
		and probe.ambient_color == environment.ambient_light_color
		and is_equal_approx(probe.ambient_color_energy, 0.7))
	check("ambient correction retains reflection strength, masks and update cadence",
		probe.intensity == 1.0 and probe.visible and probe.reflection_mask == 2
		and probe.cull_mask == 8 and probe.update_mode == ReflectionProbe.UPDATE_ONCE
		and probe.get_meta("refreshes", 0) == 0)
	var color_before := probe.ambient_color
	environment.tonemap_exposure = 150000.0
	probe._sync_color_ambient(environment, true)
	check("adaptation gain alone never changes unexposed ambient", probe.ambient_color == color_before
		and is_equal_approx(probe.ambient_color_energy, 0.7))
	environment.ambient_light_color = Color(0.12, 0.2, 0.3)
	environment.ambient_light_energy = 1.2
	probe._sync_color_ambient(environment, true)
	check("a paused world color/energy edit propagates without a cube refresh",
		probe.ambient_color == environment.ambient_light_color
		and is_equal_approx(probe.ambient_color_energy, 1.2) and probe.get_meta("refreshes", 0) == 0)
	probe._sync_color_ambient(environment, false)
	check("other renderers retain environment-sourced probe ambient", probe.ambient_mode == ReflectionProbe.AMBIENT_ENVIRONMENT)
	probe._sync_color_ambient(environment, true)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	probe._sync_color_ambient(environment, true)
	check("a sky-ambient world restores the existing probe mode", probe.ambient_mode == ReflectionProbe.AMBIENT_ENVIRONMENT)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	probe._sync_color_ambient(environment, true)
	probe._sync_color_ambient(null, true)
	check("removing the world environment cannot leave a stale color override", probe.ambient_mode == ReflectionProbe.AMBIENT_ENVIRONMENT)
	check("the probe never rewrites the world environment", environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and environment.ambient_light_color == Color(0.12, 0.2, 0.3)
		and is_equal_approx(environment.ambient_light_energy, 1.2) and environment.tonemap_exposure == 150000.0)
	probe.free()
	print("Lake probe ambient: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
