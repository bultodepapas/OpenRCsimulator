# FW-61: time flows. The time scale resolves from arguments and from the Home "evening" choice; the sky advances in
# quantised steps of simulation time (same time, same sky); golden hour reaches night with the club lights on and the
# stars turned by sidereal time; haze materials, the light and the environment follow; the tonemapper never switches;
# frozen sessions never step.
# Run: godot --headless --path . --script res://tests/test_world_flow.gd
extends SceneTree

const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	# Resolution.
	var c := Conditions.resolve(PackedStringArray(["--time_of_day=golden_hour", "--time_scale=20"]))
	_check("time scale from arguments", is_equal_approx(float(c.time_scale), 20.0))
	_check("frozen by default", float(Conditions.resolve(PackedStringArray(["--time_of_day=night"])).time_scale) == 0.0)
	_check("bad scale stays frozen", float(Conditions.resolve(PackedStringArray(["--time_of_day=night", "--time_scale=-3"])).time_scale) == 0.0)
	Conditions.session_preset = "evening"
	var evening := Conditions.resolve(PackedStringArray())
	_check("Home evening = golden hour at ×20", evening.preset == "golden_hour" and is_equal_approx(float(evening.time_scale), 20.0), str(evening))
	Conditions.session_preset = ""

	var field: Dictionary = FieldLoader.load_from().field
	var holder := Node3D.new()
	var built := World.build(holder, field, Callable(), c)
	var env: Environment = built.environment
	var start_el: float = Atmosphere.state.sun_elevation_deg
	var lights: Node3D = holder.get_node_or_null("FieldLights")
	var stars: Node3D = holder.get_node_or_null("Stars")
	_check("flowing session builds stars and lights at once", lights != null and stars != null)
	_check("lights off in golden hour", lights != null and not lights.visible)
	_check("one tonemapper for the session (AgX from a 6° start)", env.tonemap_mode == Environment.TONE_MAPPER_AGX)
	var mats := World.haze_materials(holder)
	_check("haze materials found (ground and grass)", mats.size() >= 2, str(mats.size()))

	_check("no step within the first 30 s of sky time", not World.flow_to(1.0))
	_check("a step at 1.5 s (30 s of sky at ×20)", World.flow_to(1.5) and absf(World.flow_hour() - (float(c.when.hour) + 30.0 / 3600.0)) < 1e-9)
	var after_step := str(Atmosphere.state)
	World.flow_to(1.6)
	_check("same step, same sky", str(Atmosphere.state) == after_step)

	World.flow_to(300.0) # 100 minutes of sky later
	var night_el: float = Atmosphere.state.sun_elevation_deg
	_check("golden hour reaches deep dusk", night_el < -6.0 and night_el < start_el, "%f -> %f" % [start_el, night_el])
	_check("club lights on below 3°", lights.visible)
	_check("tonemapper unchanged", env.tonemap_mode == Environment.TONE_MAPPER_AGX and Atmosphere.state.tonemapper == "agx")
	_check("haze materials follow the light", (mats[0] as ShaderMaterial).get_shader_parameter("sun_dir") == Atmosphere.sun_direction())
	_check("environment follows the haze", env.fog_light_color.is_equal_approx(Color(Atmosphere.state.haze_lin.x, Atmosphere.state.haze_lin.y, Atmosphere.state.haze_lin.z).linear_to_srgb()))
	var sun_light: DirectionalLight3D = built.sun
	_check("the light points along the new sun/moon direction", (sun_light.transform.basis.z).distance_to(Atmosphere.sun_direction()) < 1e-4)
	_check("stars turned by sidereal time", not stars.basis.is_equal_approx(Basis.IDENTITY))
	var replay := str(Atmosphere.state)
	World.flow_to(0.0)
	World.flow_to(300.0)
	_check("deterministic: replaying the clock gives the same sky", str(Atmosphere.state) == replay)
	holder.free()

	# Frozen sessions never step.
	var frozen := Node3D.new()
	World.build(frozen, field, Callable(), Conditions.resolve(PackedStringArray(["--time_of_day=sunset"])))
	_check("frozen preset: no flow", not World.flow_to(300.0) and World.flow_hour() < 0.0)
	frozen.free()
	Atmosphere.state = {}
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
