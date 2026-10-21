# FW-MOON-03b (FW-MOON-01 decision): with time flowing, the moon's disc and the stars move every frame between the
# 30 s sky steps instead of jumping 0.12° per step. The per-frame values are a pure function of the simulation clock,
# meet the stepped state at every step, reuse the next step's state exactly, and are written only while the
# environment does not use the sky's radiance or High explicitly uses realtime filtering; frozen sessions,
# pauses and "no moon" leave the relevant uniforms alone; the
# disc stays out of the radiance cubemap pass. FW-MOON-06d: in twilight the slow sky terms follow per frame too.
# Run: godot --headless --path . --script res://tests/test_world_moon_flow.gd
extends SceneTree

const World := preload("res://render/world/world.gd")
const Conditions := preload("res://render/world/conditions.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const Ephemeris := preload("res://render/world/ephemeris.gd")
const SkyState := preload("res://render/world/sky_state.gd")
const MoonConfig := preload("res://environment/moon_config.gd")
const HighGraphics := preload("res://render/high_graphics_profile.gd")

const FPS := 60.0
## Full moon 25° high in the east-north-east at the reference field (FW-MOON-00 survey), time flowing ×20.
const ARGS := ["--date=2026-10-25", "--time=21:00", "--time_scale=20"]

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


static func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## The rotation angle between two bases from the quaternion's vector part: 2·acos(w) loses angles below ~0.04° in
## float32, while |xyz| = sin(θ/2) keeps them.
static func _basis_angle_deg(a: Basis, b: Basis) -> float:
	var q := (a.inverse() * b).get_rotation_quaternion()
	return rad_to_deg(2.0 * asin(minf(Vector3(q.x, q.y, q.z).length(), 1.0)))


## Plays `seconds` of flight at FPS from `start_s` the way World.update does; returns per-frame uniforms and stars.
func _play(mat: ShaderMaterial, stars: Node3D, start_s: float, seconds: float) -> Array:
	var frames := []
	for i in int(seconds * FPS) + 1:
		var t := start_s + float(i) / FPS
		World.flow_to(t)
		World.flow_frame(t)
		frames.append({t = t, moon = mat.get_shader_parameter("moon_dir"), body = mat.get_shader_parameter("moon_render_to_body"),
			stars = stars.basis, step = int(t * 20.0 / World.FLOW_STEP_SKY_S)})
	return frames


static func _lum(v: Vector3) -> float:
	return 0.2126 * v.x + 0.7152 * v.y + 0.0722 * v.z


## FW-MOON-06d: the slow sky between the steps, in the Moonrise evening's nautical twilight (sun about −6°), where
## one 30 s step darkens the sky by ~14 %: per frame it falls smoothly, meets the stepped sky at each step, leaves
## Atmosphere.state and the lake's water at the step, feeds the eye's adaptation, and replays exactly.
func _twilight(field: Dictionary) -> void:
	var holder := Node3D.new()
	var built := World.build(holder, field, Callable(), Conditions.resolve(PackedStringArray(["--date=2026-09-26", "--time=19:00",
		"--time_scale=20"])))
	var env: Environment = built.environment
	var mat := env.sky.sky_material as ShaderMaterial
	var water: ShaderMaterial = null
	for probe: Node in holder.find_children("*", "ReflectionProbe", true, false):
		water = probe.get("water_material")
	var start := 270.0 # 90 min of sky after 19:00 at ×20
	var rows := []
	var worst_frame := 0.0
	var worst_ambient := 0.0
	var state_kept := true
	var water_steps := true
	var previous := {}
	for i in int(3.0 * FPS) + 1:
		var t := start + float(i) / FPS
		var stepped := World.flow_to(t)
		var before := str(Atmosphere.state)
		var water_before: Variant = water.get_shader_parameter("haze_lin") if water != null else null
		World.flow_frame(t)
		state_kept = state_kept and str(Atmosphere.state) == before
		if water != null and not stepped:
			water_steps = water_steps and water.get_shader_parameter("haze_lin") == water_before
		var row := {z = _lum(mat.get_shader_parameter("zenith_lin")), a = _lum(Vector3(env.ambient_light_color.r,
			env.ambient_light_color.g, env.ambient_light_color.b)), x = World.view_exposure(Vector3(0.0, 30.0, -100.0))}
		if not previous.is_empty():
			worst_frame = maxf(worst_frame, absf(log(row.z / previous.z)))
			worst_ambient = maxf(worst_ambient, absf(log(maxf(row.a, 1e-30) / maxf(previous.a, 1e-30))))
		rows.append(row)
		previous = row
	_check("twilight: the sky changes per step by more than 5 %", absf(log(rows[90].z / rows[0].z)) > 0.05,
		"%.4f" % absf(log(rows[90].z / rows[0].z)))
	_check("twilight: no frame changes the zenith by more than 0.5 %", worst_frame < 0.005, "%.5f" % worst_frame)
	_check("twilight: no frame changes the ambient colour by more than 2 %", worst_ambient < 0.02, "%.5f" % worst_ambient)
	_check("twilight: Atmosphere.state stays the stepped state", state_kept)
	_check("twilight: the lake's water keeps the step cadence (its probe re-renders on change)", water != null and water_steps)
	var steady := true
	for i in range(1, rows.size()):
		steady = steady and rows[i].x > rows[i - 1].x * 0.995 # night falls: the eye opens, never jumps back
	_check("twilight: the eye's adaptation goal rises smoothly with the frame sky", steady)
	# At a step instant the frame sky is the step's own (fraction 0: flow_frame leaves the stepped uniforms).
	World.flow_to(start + 1.5)
	var z_step: float = _lum(mat.get_shader_parameter("zenith_lin"))
	World.flow_frame(start + 1.5)
	_check("twilight: at a step the frame sky is the stepped sky", absf(_lum(mat.get_shader_parameter("zenith_lin")) / z_step - 1.0) < 1e-6)
	# Replays: the same clock gives the same frame sky.
	World.flow_to(0.0)
	var again := []
	for i in int(3.0 * FPS) + 1:
		var t := start + float(i) / FPS
		World.flow_to(t)
		World.flow_frame(t)
		again.append(_lum(mat.get_shader_parameter("zenith_lin")))
	var same := true
	for i in again.size():
		same = same and again[i] == rows[i].z
	_check("twilight: replaying the clock gives the same frame sky", same)
	holder.free()


func _initialize() -> void:
	MoonConfig.session_config = {}
	var field: Dictionary = FieldLoader.load_from().field

	# The engine's radiance gate (Godot 4.7.2 render_scene): ambient or reflections from the sky use the cubemap.
	var probe := Environment.new()
	probe.background_mode = Environment.BG_SKY
	probe.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	probe.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_check("field-world mode leaves the radiance unused", World.radiance_unused(probe))
	probe.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_check("sky ambient uses the radiance", not World.radiance_unused(probe))
	probe.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	_check("background ambient with a sky background uses it", not World.radiance_unused(probe))
	probe.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	probe.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_check("sky reflections use it", not World.radiance_unused(probe))
	probe.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	_check("background reflections with a sky background use it", not World.radiance_unused(probe))
	probe.background_mode = Environment.BG_COLOR
	_check("background reflections without a sky background do not", World.radiance_unused(probe))

	# The disc is drawn in the main pass only.
	var sky_src := FileAccess.get_file_as_string("res://render/sky.gdshader")
	var guard := sky_src.find("if (!AT_CUBEMAP_PASS) {")
	_check("sky shader skips the disc in the cubemap pass", guard >= 0 and sky_src.find("moon_disc(EYEDIR)") > guard
		and sky_src.count("moon_disc(EYEDIR)") == 1)

	var c := Conditions.resolve(PackedStringArray(ARGS))
	var holder := Node3D.new()
	var built := World.build(holder, field, Callable(), c)
	var env: Environment = built.environment
	var mat := env.sky.sky_material as ShaderMaterial
	var stars: Node3D = holder.get_node_or_null("Stars")
	_check("flowing night with stars and a moon above the horizon", stars != null and float(Atmosphere.state.moon_elevation_deg) > 15.0
		and Atmosphere.state.moon_lin != Vector3.ZERO, str(Atmosphere.state.get("moon_elevation_deg")))
	_check("flow sky uses its renderer-specific radiance policy", World.radiance_unused(env) if not HighGraphics.active()
		else env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY and HighGraphics.supports_frame_sky(env))
	_check("only flowing High uses realtime filtering", env.sky.process_mode ==
		(Sky.PROCESS_MODE_REALTIME if HighGraphics.active() else Sky.PROCESS_MODE_QUALITY))

	# 4.5 s of flight at ×20 = three 30 s sky steps.
	var frames := _play(mat, stars, 0.0, 4.5)
	var step_moon := 0.0
	var step_stars := 0.0
	var max_moon := 0.0
	var max_stars := 0.0
	var max_body := 0.0
	for i in range(1, frames.size()):
		var d := _angle_deg(frames[i - 1].moon, frames[i].moon)
		var s := _basis_angle_deg(frames[i - 1].stars, frames[i].stars)
		max_moon = maxf(max_moon, d)
		max_stars = maxf(max_stars, s)
		max_body = maxf(max_body, _basis_angle_deg(frames[i - 1].body, frames[i].body))
		if frames[i].step == 1 and frames[i - 1].step == 1:
			step_moon += d
			step_stars += s
	# Over one step the summed motion equals one step's jump (0.12°): it is spread evenly over the 90 frames.
	var per_frame := step_moon / 89.0
	_check("the moon moves one step's arc per step", step_moon > 0.09 and step_moon < 0.13, "%.4f°" % step_moon)
	_check("no frame jumps: the largest per-frame motion stays within 1.5× the mean", max_moon <= 1.5 * per_frame,
		"max %.5f°, mean %.5f°" % [max_moon, per_frame])
	_check("the stars turn every frame without jumps", step_stars > 0.09 and max_stars <= 1.5 * step_stars / 89.0,
		"max %.5f°, step %.4f°" % [max_stars, step_stars])
	_check("the face turns with the disc, no jump", max_body < 0.01, "%.5f°" % max_body)

	# At a step instant the per-frame values equal the stepped state (fraction 0).
	World.flow_to(3.0)
	World.flow_frame(3.0)
	_check("at a step the disc is where the stepped state puts it", _angle_deg(mat.get_shader_parameter("moon_dir"), Atmosphere.state.moon_dir) < 1e-5)
	_check("at a step the face is the stepped orientation",
		_basis_angle_deg(mat.get_shader_parameter("moon_render_to_body"), Atmosphere.state.moon_render_to_body) < 1e-4)
	# The state reused from the look-ahead is exactly the state of that step.
	World.flow_frame(4.49)
	World.flow_to(4.5)
	var fresh := SkyState.state(Ephemeris.sky(World.shown_when()), World.moon_config())
	fresh.tonemapper = Atmosphere.state.tonemapper
	_check("the look-ahead state is the step's own state", str(fresh) == str(Atmosphere.state))
	# Mid-step: on the arc between the two step states, at the clock's fraction of it.
	var now: Vector3 = Atmosphere.state.moon_dir
	World.flow_to(6.0)
	var next: Vector3 = Atmosphere.state.moon_dir
	World.flow_to(4.5)
	World.flow_frame(5.25)
	var mid: Vector3 = mat.get_shader_parameter("moon_dir")
	_check("mid-step the disc is halfway along the arc", absf(_angle_deg(now, mid) - _angle_deg(mid, next)) < 1e-4
		and absf(_angle_deg(now, mid) + _angle_deg(mid, next) - _angle_deg(now, next)) < 1e-4)

	# Deterministic: replaying the same clock gives the same per-frame values.
	World.flow_to(0.0)
	var replay := _play(mat, stars, 0.0, 4.5)
	_check("replaying the clock gives the same per-frame sky", var_to_bytes(replay) == var_to_bytes(frames))

	# Paused (the clock stays inside step 3 from here on): the same clock writes nothing.
	World.flow_frame(5.0)
	_check("a paused clock moves nothing", not World.flow_frame(5.0))

	# QUALITY radiance must never acquire per-frame sky writes, even in High.
	var before: Vector3 = mat.get_shader_parameter("moon_dir")
	var mode_before := env.sky.process_mode
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_check("no per-frame writes while the sky's radiance is used", not World.flow_frame(5.1)
		and mat.get_shader_parameter("moon_dir") == before)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.sky.process_mode = mode_before

	# No moon: the disc stays invisible between the steps (FW-MOON-06d writes the whole frame sky); the stars still turn.
	var off := MoonConfig.defaults()
	off.moon = "off"
	World.set_moon_config(off)
	before = mat.get_shader_parameter("moon_dir")
	var stars_before := stars.basis
	var turned := World.flow_frame(5.2)
	_check("no moon: the disc stays invisible, the stars still turn", turned and mat.get_shader_parameter("moon_lin") == Vector3.ZERO
		and Atmosphere.state.moon_lin == Vector3.ZERO and not stars.basis.is_equal_approx(stars_before))
	World.set_moon_config(MoonConfig.defaults())
	_check("the moon returns and moves on the next frame", World.flow_frame(5.3) and Atmosphere.state.moon_lin != Vector3.ZERO
		and mat.get_shader_parameter("moon_dir") != before)
	holder.free()

	_twilight(field)

	# Frozen sessions never move.
	var frozen := Node3D.new()
	var frozen_world := World.build(frozen, field, Callable(), Conditions.resolve(PackedStringArray(["--date=2026-10-25", "--time=21:00"])))
	_check("frozen world keeps quality radiance", frozen_world.environment.sky.process_mode == Sky.PROCESS_MODE_QUALITY)
	_check("frozen time: no per-frame motion", not World.flow_frame(1.0) and not World.flow_frame(2.0))
	frozen.free()
	Atmosphere.state = {}
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
