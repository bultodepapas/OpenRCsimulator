# PT1h-R10: flight-model lines for the debug bridge, after X-Plane's flight-model display and the force gizmos of
# avian_fdm and Unreal's Chaos vehicles. Read-only presentation: every frame it reads the session's committed
# 64-bit state, loads and air data and converts them at the render boundary (render/frames.gd), like the RC truck's
# contact overlay (vehicles/ground/contact_debug.gd). Nothing here feeds back into the simulation.
#   axes      body x (forward, red), y (right, green), z (down, blue)
#   velocity  inertial velocity (white)
#   air       velocity through the air (cyan); its difference from `velocity` is the wind
#   wind      wind at the aircraft (blue), drawn from the CG
#   forces    aerodynamic + propulsive force (yellow), split along the flight path (orange: thrust − drag)
#             and across it (green: lift + side force); gravity m·g (magenta)
#   moments   body moment as an equivalent lever arm |M| / (m·g) (purple)
#   trail     the CG path over the last `trail_s` seconds
#   label     V, α, β, load factor, height and tick next to the aircraft
# Guide: tools/debug/README.md#flight-gizmos-pt1h-r10.
extends Node3D

const Frames := preload("res://render/frames.gd")
const LAYERS := ["axes", "velocity", "air", "wind", "forces", "moments", "trail", "label"]
const COLORS := {x = Color(1.0, 0.25, 0.25), y = Color(0.3, 1.0, 0.3), z = Color(0.35, 0.55, 1.0),
	velocity = Color(1.0, 1.0, 1.0), air = Color(0.2, 0.95, 1.0), wind = Color(0.3, 0.45, 1.0),
	force = Color(1.0, 0.9, 0.15), along = Color(1.0, 0.55, 0.1), across = Color(0.35, 1.0, 0.45),
	gravity = Color(1.0, 0.3, 0.9), moment = Color(0.7, 0.4, 1.0), trail = Color(1.0, 1.0, 1.0)}

var shown := {} # layer -> true
var axis_m := 0.6 # body axis length
var force_m_per_g := 1.0 # a force equal to the aircraft's weight is this long
var velocity_m_per_mps := 0.1 # 20 m/s draws 2 m
var moment_gain := 10.0 # moment arrow = gain × |M| / (m·g), metres
var trail_s := 10.0
var thickness_m := 0.012 # parallel copies make 1-pixel GL lines readable at 1080p
var auto_scale := true # far or zoomed views (the pilot camera on the ground): grow arrows to stay readable
var _scale := 1.0 # this frame's arrow multiplier (1 near the aircraft)
var _thick := true
var _camera: Camera3D # this frame's camera
var _lines := ImmediateMesh.new()
var _mesh := MeshInstance3D.new()
var _label := Label3D.new()
var _trail := PackedVector3Array()
var _trail_ticks := PackedInt64Array()
var last := {} # the numbers drawn this frame (gizmos returns them)


func _init() -> void:
	name = "DebugFlightGizmos"
	_mesh.mesh = _lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 100
	_mesh.material_override = material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.font_size = 28
	_label.outline_size = 8
	_label.render_priority = 101
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.visible = false
	add_child(_label)


func configure(layers: Array) -> void:
	shown.clear()
	for layer: String in layers:
		shown[layer] = true
	if not shown.has("trail"):
		_trail.clear()
		_trail_ticks.clear()


## One frame. `pose` is what the renderer drew ({pos, basis}); everything else is the committed tick.
func update_from(session: Node, pose: Dictionary) -> void:
	_lines.clear_surfaces()
	_label.visible = false
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	if s.size() < 13 or pose.is_empty():
		return
	var origin: Vector3 = pose.pos
	var basis: Basis = pose.basis
	_camera = get_viewport().get_camera_3d() if is_inside_tree() else null
	_scale = _view_scale(origin)
	var mass: float = sim.mass
	var weight: float = mass * sim.gravity
	var loads: PackedFloat64Array = sim.last_loads
	var air: Dictionary = session.air_data(s) if session.has_method("air_data") else {}
	var wind_ned: PackedFloat64Array = session.wind_at(sim.time(), s) if session.has_method("wind_at") else PackedFloat64Array()
	var force := _body(basis, loads, 0)
	var v_air := _body(basis, air.get("v_air", PackedFloat64Array([0.0, 0.0, 0.0])), 0)
	var velocity := _body(basis, s, 3)
	var wind := Frames.ned_to_render([wind_ned[0], wind_ned[1], wind_ned[2]]) if wind_ned.size() >= 3 else Vector3.ZERO
	if not wind.is_finite():
		wind = Vector3.ZERO # NAN while the weather resets
	var path_dir := v_air.normalized() if v_air.length() > 0.5 else basis * Vector3.FORWARD
	var along := path_dir * force.dot(path_dir)
	var across := force - along
	last = {tick = sim.tick, airspeed_mps = air.get("V", 0.0), alpha_deg = rad_to_deg(air.get("alpha", 0.0)),
		beta_deg = rad_to_deg(air.get("beta", 0.0)), load_factor = -loads[2] / weight if weight > 0.0 else 0.0,
		force_n = [force.x, force.y, force.z], along_path_n = force.dot(path_dir), across_path_n = across.length(),
		wind_mps = wind.length(), height_m = -s[2], arrow_scale = _scale, frame = "render (x east, y up, z south)"}
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew := false
	if shown.has("axes"):
		_arrow(origin, basis * Vector3(0, 0, -axis_m), COLORS.x)
		_arrow(origin, basis * Vector3(axis_m, 0, 0), COLORS.y)
		_arrow(origin, basis * Vector3(0, -axis_m, 0), COLORS.z)
		drew = true
	if shown.has("velocity"):
		_arrow(origin, velocity * velocity_m_per_mps, COLORS.velocity)
		drew = true
	if shown.has("air"):
		_arrow(origin, v_air * velocity_m_per_mps, COLORS.air)
		drew = true
	if shown.has("wind") and wind.length() > 1.0e-3:
		_arrow(origin, wind * velocity_m_per_mps, COLORS.wind)
		drew = true
	if shown.has("forces") and weight > 0.0:
		var scale := force_m_per_g / weight
		_arrow(origin, force * scale, COLORS.force)
		_arrow(origin, along * scale, COLORS.along)
		_arrow(origin, across * scale, COLORS.across)
		_arrow(origin, Vector3(0, -weight, 0) * scale, COLORS.gravity)
		drew = true
	if shown.has("moments") and weight > 0.0:
		_arrow(origin, _body(basis, loads, 3) * (moment_gain / weight), COLORS.moment)
		drew = true
	if shown.has("trail"):
		_record_trail(origin, int(sim.tick), 1.0 / sim.dt())
		_thick = false # hundreds of segments: one copy each keeps the frame cost low
		for i in range(1, _trail.size()):
			var fade := float(i) / _trail.size()
			_segment(_trail[i - 1], _trail[i], Color(COLORS.trail, 0.15 + 0.75 * fade))
		_thick = true
		drew = drew or _trail.size() > 1
	if drew:
		_lines.surface_end()
	else:
		_lines.clear_surfaces()
	if shown.has("label"):
		_label.visible = true
		_label.position = origin + Vector3(0, 0.6 * _scale, 0)
		var camera := _camera
		# fixed_size keeps a constant size at a 75° field of view; a zoomed camera would magnify it.
		_label.pixel_size = 0.0009 * (tan(deg_to_rad(camera.fov) / 2.0) / tan(deg_to_rad(37.5)) if camera != null else 1.0)
		_label.text = "V %.1f m/s  α %.1f°  β %.1f°\nn %.2f g  h %.1f m  tick %d" % [last.airspeed_mps, last.alpha_deg,
			last.beta_deg, last.load_factor, last.height_m, last.tick]


## A body-axis (FRD) vector at `offset` of a packed array, in render world axes.
static func _body(basis: Basis, values: PackedFloat64Array, offset: int) -> Vector3:
	if values.size() < offset + 3:
		return Vector3.ZERO
	return basis * Frames.ned_to_render([values[offset], values[offset + 1], values[offset + 2]])


func _record_trail(point: Vector3, tick: int, ticks_per_s: float) -> void:
	if not _trail_ticks.is_empty() and tick < _trail_ticks[_trail_ticks.size() - 1]:
		_trail.clear() # restart or rewind: a new path
		_trail_ticks.clear()
	if _trail_ticks.is_empty() or tick - _trail_ticks[_trail_ticks.size() - 1] >= 12:
		_trail.append(point)
		_trail_ticks.append(tick)
	var oldest := tick - int(trail_s * ticks_per_s)
	var keep := 0
	while keep < _trail_ticks.size() and _trail_ticks[keep] < oldest:
		keep += 1
	if keep > 0:
		_trail = _trail.slice(keep)
		_trail_ticks = _trail_ticks.slice(keep)


## 1 near the aircraft; grows with distance and zoom so a 1 m arrow keeps about the size it has at 8 m in a 60° view.
func _view_scale(origin: Vector3) -> float:
	var camera := _camera
	if not auto_scale or camera == null:
		return 1.0
	var distance := camera.global_position.distance_to(origin)
	return maxf(1.0, distance * tan(deg_to_rad(camera.fov) / 2.0) / (8.0 * tan(deg_to_rad(30.0))))


func _arrow(from: Vector3, unscaled: Vector3, color: Color) -> void:
	var vector := unscaled * _scale
	var length := vector.length()
	if length < 1.0e-4:
		return
	var tip := from + vector
	_segment(from, tip, color)
	var direction := vector / length
	var side := direction.cross(Vector3.UP)
	if side.length() < 1.0e-3:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var head := minf(0.15 * _scale, 0.25 * length)
	for sign: float in [-1.0, 1.0]:
		_segment(tip, tip - direction * head + side * head * 0.5 * sign, color)


func _segment(a: Vector3, b: Vector3, color: Color) -> void:
	var camera := _camera
	var offsets: Array = [Vector3.ZERO]
	if camera != null and thickness_m > 0.0 and _thick:
		var right := camera.global_basis.x * thickness_m * _scale
		var up := camera.global_basis.y * thickness_m * _scale
		offsets = [Vector3.ZERO, right, -right, up, -up]
	for offset: Vector3 in offsets:
		_lines.surface_set_color(color)
		_lines.surface_add_vertex(a + offset)
		_lines.surface_set_color(color)
		_lines.surface_add_vertex(b + offset)
