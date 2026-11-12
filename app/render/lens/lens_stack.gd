## LENS-01…11 (docs/plans/lens-screen-effects.md): the lens stack. One presentation-only owner for three effects:
##   impact blood   a classic red curtain (or lens splatter) when the aircraft strikes a person or the pilot;
##   rain           drops that land, bead, run, merge and blow off the camera lens, plus falling streaks around it;
##   impact grime   mud, grass, dust, water spray, a cracked lens and glow-engine oil film.
## It reads accepted evidence only (detached contact events, the accepted state, the camera) and writes nothing back;
## the simulation is unchanged with or without it. Nodes exist only for enabled channels and are created lazily:
## with every channel off, configure() builds nothing and advance() returns at once.
##
## Draw order inside one CanvasLayer (−9: over the 3D image and SUN-03's afterimage on −10, under every interface
## layer): drops, stamps, film. The first screen reader triggers the back-buffer copy the others share.
extends Node

const Settings := preload("res://render/lens/lens_settings.gd")
const RainModel := preload("res://render/lens/rain_model.gd")
const DropPool := preload("res://render/lens/drop_pool.gd")
const ImpactTrigger := preload("res://render/lens/impact_trigger.gd")
const PilotStrike := preload("res://render/lens/pilot_strike.gd")
const Frames := preload("res://render/frames.gd")
const RB := preload("res://physics/rigid_body.gd")
const DROP_SHADER := preload("res://render/lens/lens_drop.gdshader")
const STAMP_SHADER := preload("res://render/lens/lens_stamp.gdshader")
const FILM_SHADER := preload("res://render/lens/lens_film.gdshader")
const STREAK_SHADER := preload("res://render/lens/rain_streaks.gdshader")

const LAYER := -9
const CURTAIN_SPEED := 0.8
const CURTAIN_DRAIN_RATE := 0.42
const PULSE_DECAY_S := 0.35
const SPLATTER_LIFE_S := 7.0
const DUST_DECAY_S := 14.0
const OIL_FULL_S := 900.0
const OIL_MAX := 0.55
const CRACK_SPEED_MPS := 12.0
const STREAK_BOX := Vector3(36.0, 24.0, 36.0)
## Drop arrivals per view: art gain on the physical sweep (RainModel), and the drop radius per millimetre of diameter
## (screen heights). A fixed tripod catches only what falls on it; a moving camera sweeps the rain.
const VIEW_RAIN := {
	"closeup": {"gain": 6.0, "scale": 0.0075, "air": true, "focus": 1.6},
	"chase": {"gain": 5.0, "scale": 0.0065, "air": true, "focus": 1.8},
	"orbit": {"gain": 5.0, "scale": 0.0065, "air": false, "focus": 1.8},
	"flyby": {"gain": 12.0, "scale": 0.0065, "air": false, "focus": 1.8},
	"fpv": {"gain": 3.0, "scale": 0.0085, "air": true, "focus": 1.0},
	"pilot": {"gain": 3.0, "scale": 0.0095, "air": false, "focus": 3.2},
}
## Art ceiling on arrivals: past it a fast camera in a downpour only floods the pool's capacity.
const MAX_ARRIVALS_PER_S := 28.0
const COLOURS := {
	"red": {"sigma": Vector3(0.55, 7.5, 8.5), "albedo": Vector3(0.30, 0.012, 0.010), "dry": Vector3(0.16, 0.022, 0.014)},
	"dark": {"sigma": Vector3(2.4, 3.0, 3.3), "albedo": Vector3(0.08, 0.05, 0.04), "dry": Vector3(0.05, 0.035, 0.03)},
	"desaturated": {"sigma": Vector3(2.0, 2.0, 2.0), "albedo": Vector3(0.18, 0.18, 0.18), "dry": Vector3(0.1, 0.1, 0.1)},
}
const STAMP_BLOOD := 0
const STAMP_MUD := 1
const STAMP_GRASS := 2
const STAMP_CRACK := 3

## The resolved settings (LensSettings.resolve); empty until configured.
var settings: Dictionary = {}
var configured := false
## Last presentation snapshot for tools and tests.
var last_rain_mmph := 0.0

var _session: Object
var _camera: Camera3D
var _view_provider: Callable
var _wind_provider: Callable
var _sky_provider: Callable
var _flash_provider: Callable
var _engine_running: Callable
var _field: Dictionary = {}
var _hull := PackedFloat64Array()
var _station := PackedFloat64Array()
var _eye_height := 1.7
var _mass_kg := 1.0
var _glow := false
var _seed := 1
var _tier: Dictionary = {}

var _layer: CanvasLayer
var _drops_node: MultiMeshInstance2D
var _stamps_node: MultiMeshInstance2D
var _film: ColorRect
var _drop_material: ShaderMaterial
var _stamp_material: ShaderMaterial
var _film_material: ShaderMaterial
var _streaks: MultiMeshInstance3D
var _streak_material: ShaderMaterial

var _pool: DropPool
var _stamps: Array[Dictionary] = []
var _pilot := PilotStrike.new()
var _seen: Dictionary = {}
var _floor_tick := -1
var _rng := RandomNumberGenerator.new()

var _blood_active := false
var _blood_t := 0.0
var _blood_depth := 1.0
var _blood_drain_start := 2.0
var _blood_end := 6.0
var _blood_seed := 0.0
var _blood_dry := 0.0
var _pulse := 0.0
var _dust := 0.0
var _oil := 0.0
var _cracked := false
var _crash_seen := false

var _camera_previous := Vector3.ZERO
var _camera_velocity := Vector3.ZERO
var _camera_primed := false
var _last_clock := NAN
var _pilot_clock := NAN


## ctx keys: settings (LensSettings.resolve), camera (Camera3D), view_provider (→ String); optional: session
## (FlightSession: contact events, accepted state, crash), wind_provider (time → render Vector3), sky_provider
## (→ preset id), flash_provider (→ 0…1), engine_running (→ bool), field, hull (body FRD triples), station
## ([north, east, down]), eye_height, mass_kg, glow (bool), seed. Returns false (and builds nothing) when disabled.
func configure(ctx: Dictionary) -> bool:
	settings = ctx.get("settings", {})
	if not bool(settings.get("enabled", false)) or not (ctx.get("camera") is Camera3D) \
			or not (ctx.get("view_provider") is Callable):
		configured = false
		return false
	_camera = ctx.camera
	_view_provider = ctx.view_provider
	_session = ctx.get("session")
	_wind_provider = ctx.get("wind_provider", Callable())
	_sky_provider = ctx.get("sky_provider", Callable())
	_flash_provider = ctx.get("flash_provider", Callable())
	_engine_running = ctx.get("engine_running", Callable())
	_field = ctx.get("field", {})
	_hull = ctx.get("hull", PackedFloat64Array())
	_station = ctx.get("station", PackedFloat64Array())
	_eye_height = float(ctx.get("eye_height", 1.7))
	_mass_kg = maxf(float(ctx.get("mass_kg", 1.0)), 0.05)
	_glow = bool(ctx.get("glow", false))
	_seed = int(ctx.get("seed", 1))
	_tier = settings.get("tier", Settings.TIERS.medium)
	_rng.seed = hash([_seed, "LENS"])
	_blood_seed = _rng.randf()
	configured = true
	return true


## True when a session event, crash or rain can still draw something this flight.
func wants_contacts() -> bool:
	return configured and (str(settings.get("impact", "off")) != "off" or bool(settings.get("grime", false)))


## Clears every channel (flight reset, checkpoint restore, aircraft change). Events at or before `floor_tick` are
## never admitted: a restored checkpoint passes its tick, so it does not replay old blood; a new flight passes −1.
func reset(floor_tick: int = -1) -> void:
	_blood_active = false
	_blood_t = 0.0
	_pulse = 0.0
	_dust = 0.0
	_oil = 0.0
	_cracked = false
	_crash_seen = false
	_stamps.clear()
	_seen.clear()
	_pilot.reset()
	_pilot_clock = NAN
	_camera_primed = false
	_floor_tick = floor_tick
	if _pool != null:
		_pool.clear()
	_apply_visibility()


## Connect to FlightSession.contact_events_changed. Pure filtering (ImpactTrigger.admit); no I/O, no allocation of
## nodes inside the physics callback: strikes queue state that the next advance() presents.
func on_contacts() -> void:
	if not wants_contacts() or _session == null:
		return
	var records := ImpactTrigger.admit(_session.contact_events(), _seen, _floor_tick, _mass_kg)
	for record: Dictionary in records:
		var point := Frames.ned_to_render(Array(record.point_ned))
		if record.kind == "person":
			var player := _near_station(record.point_ned, 1.2)
			if player:
				_pilot.reset() # The proximity detector must not fire a second time for the same strike.
			strike_person(float(record.strength), point, player)
		else:
			strike_surface(str(record.kind), float(record.strength), point, float(record.speed_mps))


## A person was struck. `player` marks the pilot (the player): always a full strike.
func strike_person(strength: float, point: Vector3 = Vector3.INF, player: bool = false) -> void:
	if not configured or str(settings.get("impact", "off")) == "off":
		return
	var view := _view()
	var distance := 0.0 if point == Vector3.INF or _camera == null else _camera.global_position.distance_to(point)
	var s := clampf(strength, 0.0, 1.0)
	if player:
		s = maxf(s, 0.85)
	s *= ImpactTrigger.view_factor(view, distance, player)
	if s < ImpactTrigger.BRUSH_STRENGTH and not player:
		_pulse = maxf(_pulse, 0.6)
		_apply_visibility()
		return
	_pulse = 1.0
	var screen := _screen_point(point)
	var splatter_only := str(settings.impact) == "splatter"
	if splatter_only and view == "pilot" and not bool(settings.get("glasses", false)):
		# An eye has no glass to splatter: the edge pulse alone.
		_apply_visibility()
		return
	_ensure_stamps()
	var splats := 2 + int(round(3.0 * s))
	for i in splats:
		var spread := Vector2(_rng.randf_range(-0.22, 0.22), _rng.randf_range(-0.16, 0.16))
		var at: Vector2 = screen + spread if screen.x >= 0.0 else Vector2(_rng.randf_range(0.15, 1.6), _rng.randf_range(0.0, 0.25))
		_add_stamp(STAMP_BLOOD, at, _rng.randf_range(0.06, 0.15) * (0.6 + 0.6 * s), SPLATTER_LIFE_S + (0.0 if splatter_only else -2.0))
	if not splatter_only:
		_ensure_film()
		_blood_active = true
		_blood_t = 0.0
		_blood_seed = _rng.randf()
		_blood_depth = 0.35 + 0.65 * s
		var hold := 0.2 + 0.6 * s + (0.2 if player else 0.0)
		_blood_drain_start = _blood_depth / CURTAIN_SPEED + hold
		_blood_end = _blood_drain_start + (_blood_depth + 0.45) / CURTAIN_DRAIN_RATE
	_apply_visibility()


## The aircraft hit something solid near the camera. kind: ground, foliage, obstacle, water, mud.
func strike_surface(kind: String, strength: float, point: Vector3, speed_mps: float = 0.0) -> void:
	if not configured or not bool(settings.get("grime", false)):
		return
	var view := _view()
	var distance := 0.0 if _camera == null else _camera.global_position.distance_to(point)
	var reach := 1.0 - smoothstep(4.0, 15.0, distance)
	if view == "pilot":
		reach = 1.0 - smoothstep(2.0, 6.0, distance)
	if reach <= 0.01:
		return
	var s := clampf(strength, 0.0, 1.0) * reach
	var surface := kind
	if kind == "ground" and not _field.is_empty():
		var ned := [-point.z, point.x, -point.y]
		surface = _surface_at(float(ned[0]), float(ned[1]))
	var screen := _screen_point(point)
	var near_lens := view != "pilot"
	match surface:
		"water":
			_spray(s)
		"mud", "rough":
			_dust = maxf(_dust, 0.25 * s)
			if near_lens:
				_ensure_stamps()
				for i in 1 + int(round(2.0 * s)):
					_add_stamp(STAMP_MUD, _scatter(screen), _rng.randf_range(0.03, 0.09) * (0.6 + s), INF)
				for i in int(round(2.0 * s)):
					_add_stamp(STAMP_GRASS, _scatter(screen), _rng.randf_range(0.08, 0.16), INF)
		"mown", "foliage":
			_dust = maxf(_dust, 0.12 * s)
			if near_lens:
				_ensure_stamps()
				for i in 2 + int(round(3.0 * s)):
					_add_stamp(STAMP_GRASS, _scatter(screen), _rng.randf_range(0.08, 0.2), INF)
		_:
			_dust = maxf(_dust, 0.45 * s)
	if near_lens and view in ["closeup", "fpv"] and speed_mps >= CRACK_SPEED_MPS and not _cracked:
		_ensure_stamps()
		_cracked = true
		_add_stamp(STAMP_CRACK, Vector2(_rng.randf_range(0.5, 1.2), _rng.randf_range(0.3, 0.7)), 0.8, INF)
	if _dust > 0.0:
		_ensure_film()
		_film_material.set_shader_parameter("dust_seed", _rng.randf())
	_apply_visibility()


## Water thrown onto the lens (a splash-down, a ditching, spray from a wet field).
func _spray(strength: float) -> void:
	if not _ensure_pool():
		return
	var aspect := _aspect()
	for i in 6 + int(round(30.0 * strength)):
		_pool.spawn_random(aspect, _rng.randf_range(0.004, 0.022))


## Debug-bridge helpers (`debugctl.py call node=… method=debug_blood`): presentation only.
func debug_blood(strength: float = 1.0, player: bool = false) -> void:
	strike_person(strength, Vector3.INF, player)


func debug_grime(kind: String = "rough", speed_mps: float = 15.0) -> void:
	if _camera != null:
		var point := _camera.global_position - _camera.global_basis.z * 2.0
		if kind in ["mud", "rough", "mown", "foliage", "water", "dust"]:
			match kind:
				"rough": _debug_surface("mud", point, speed_mps)
				"mown": _debug_surface("foliage", point, speed_mps)
				"dust": _debug_surface("obstacle", point, speed_mps)
				_: _debug_surface(kind, point, speed_mps)


func _debug_surface(kind: String, point: Vector3, speed_mps: float) -> void:
	strike_surface(kind, clampf(speed_mps / 20.0, 0.0, 1.0), point, speed_mps)


func debug_rain(mmph: float) -> void:
	settings["rain_override_mmph"] = maxf(mmph, 0.0)
	settings["rain"] = configured


func debug_oil(amount: float) -> void:
	_oil = clampf(amount, 0.0, OIL_MAX)
	if _oil > 0.0:
		_ensure_film()
	_apply_visibility()


func snapshot() -> Dictionary:
	return {
		"configured": configured, "view": _view(), "rain_mmph": last_rain_mmph,
		"drops": _pool.count if _pool != null else 0, "stamps": _stamps.size(),
		"blood": _blood_active, "blood_t": _blood_t, "blood_depth": _blood_depth, "pulse": _pulse,
		"dust": _dust, "oil": _oil, "cracked": _cracked,
		"nodes": {"layer": _layer != null, "drops": _drops_node != null, "stamps": _stamps_node != null,
			"film": _film != null, "streaks": _streaks != null},
	}


## One rendered frame. `clock_s` is the visual clock (simulation time on interactive flights); `paused` holds every
## animation (menus, pause, calibration) exactly like the crash presentation.
func advance(delta: float, clock_s: float, paused: bool) -> void:
	if not configured or _camera == null or not is_instance_valid(_camera):
		return
	var dt := 0.0 if paused else clampf(delta, 0.0, 0.1)
	_track_camera(delta, paused)
	if not paused:
		_observe_pilot(clock_s)
		_observe_crash()
	_advance_rain(dt, clock_s)
	_advance_blood(dt)
	_advance_grime(dt)
	_write_stamps()
	_apply_visibility()


func _view() -> String:
	if _view_provider.is_valid():
		return str(_view_provider.call())
	return "pilot"


func _aspect() -> float:
	var size := _viewport_size()
	return size.x / maxf(size.y, 1.0)


func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1920.0, 1080.0)


## Screen position in screen-height units (x in [0, aspect]); x < 0 when the point is behind the camera or unknown.
func _screen_point(point: Vector3) -> Vector2:
	if point == Vector3.INF or _camera == null or _camera.is_position_behind(point):
		return Vector2(-1.0, -1.0)
	var size := _viewport_size()
	var px := _camera.unproject_position(point)
	return Vector2(clampf(px.x, 0.0, size.x), clampf(px.y, 0.0, size.y)) / maxf(size.y, 1.0)


func _scatter(screen: Vector2) -> Vector2:
	var aspect := _aspect()
	if screen.x < 0.0:
		return Vector2(_rng.randf() * aspect, _rng.randf())
	return Vector2(clampf(screen.x + _rng.randf_range(-0.3, 0.3), 0.0, aspect), clampf(screen.y + _rng.randf_range(-0.25, 0.25), 0.0, 1.0))


func _near_station(point_ned: PackedFloat64Array, radius_m: float) -> bool:
	if _station.size() != 3 or point_ned.size() != 3:
		return false
	return Vector2(point_ned[0] - _station[0], point_ned[1] - _station[1]).length() <= radius_m


func _surface_at(north: float, east: float) -> String:
	for kind: String in ["runway", "rotorpad", "mown", "rough"]:
		for surface: Variant in _field.get("surfaces", []):
			if typeof(surface) != TYPE_DICTIONARY:
				continue
			var s: Dictionary = surface
			if str(s.get("type", "")) == kind and absf(north - float(s.get("center_north", 0.0))) <= float(s.get("width_north_south", 0.0)) * 0.5 \
					and absf(east - float(s.get("center_east", 0.0))) <= float(s.get("length_east_west", 0.0)) * 0.5:
				return "mown" if kind == "rotorpad" else ("obstacle" if kind == "runway" else kind)
	return "rough"


func _track_camera(delta: float, paused: bool) -> void:
	var position := _camera.global_position
	if not _camera_primed or delta <= 0.0:
		_camera_previous = position
		_camera_velocity = Vector3.ZERO
		_camera_primed = true
		return
	if paused:
		_camera_previous = position
		return
	var raw := (position - _camera_previous) / delta
	_camera_previous = position
	if raw.length() > 150.0:
		_camera_velocity = Vector3.ZERO # a view change or reset is a cut, not motion
		return
	_camera_velocity = _camera_velocity.lerp(raw, clampf(delta * 8.0, 0.0, 1.0))


func _observe_pilot(clock_s: float) -> void:
	if _session == null or _hull.is_empty() or _station.size() != 3 or str(settings.get("impact", "off")) == "off":
		return
	var sim: Variant = _session.get("sim")
	if sim == null:
		return
	if not is_nan(_pilot_clock) and clock_s <= _pilot_clock:
		return
	var dt := 0.0 if is_nan(_pilot_clock) else clock_s - _pilot_clock
	_pilot_clock = clock_s
	var state: PackedFloat64Array = sim.state
	if state.size() < RB.SIZE:
		return
	var points := PilotStrike.hull_world(state.slice(RB.POS, RB.POS + 3), state.slice(RB.ATT, RB.ATT + 4), _hull)
	if dt <= 0.0:
		_pilot.observe(points, _station, _eye_height, 1.0)
		return
	var hit: Dictionary = _pilot.observe(points, _station, _eye_height, dt)
	if not hit.is_empty():
		strike_person(1.0, Frames.ned_to_render(Array(hit.point_ned)), true)


func _observe_crash() -> void:
	if _session == null or _crash_seen:
		return
	var crash: Variant = _session.get("crash")
	if typeof(crash) != TYPE_DICTIONARY or (crash as Dictionary).is_empty():
		return
	_crash_seen = true
	var impact: Object = (crash as Dictionary).get("impact") as Object
	if impact == null or not bool(impact.get("has_kinematics")):
		return
	var point_ned: PackedFloat64Array = impact.get("point_ned")
	if point_ned.size() != 3:
		return
	var speed := float(impact.get("speed_mps"))
	strike_surface("ground", clampf(speed / 20.0, 0.0, 1.0), Frames.ned_to_render(Array(point_ned)), speed)


func _advance_rain(dt: float, clock_s: float) -> void:
	if not bool(settings.get("rain", false)):
		last_rain_mmph = 0.0
		return
	var nominal: float = settings.get("rain_override_mmph", NAN)
	if is_nan(nominal):
		nominal = RainModel.rate_for_preset(str(_sky_provider.call())) if _sky_provider.is_valid() else 0.0
	var rate := nominal * RainModel.burst(clock_s, _seed) if nominal > 0.0 else 0.0
	last_rain_mmph = rate
	var raining := rate > 0.0
	if raining:
		_ensure_streaks()
	var flash := clampf(float(_flash_provider.call()), 0.0, 1.0) if _flash_provider.is_valid() else 0.0
	var wind := _wind_provider.call(clock_s) as Vector3 if _wind_provider.is_valid() else Vector3.ZERO
	var fall := Vector3(wind.x, -maxf(RainModel.mean_fall_speed(maxf(rate, 0.5)), 2.0) * 2.6, wind.z)
	if _streaks != null:
		_streaks.visible = raining
		if raining:
			var count := int(_streaks.multimesh.instance_count)
			_streaks.multimesh.visible_instance_count = clampi(int(count * clampf(rate / 18.0, 0.12, 1.0)), 1, count)
			_streaks.global_position = _camera.global_position
			_streak_material.set_shader_parameter("clock_s", fposmod(clock_s, 600.0))
			_streak_material.set_shader_parameter("box_centre", _camera.global_position)
			_streak_material.set_shader_parameter("fall_velocity", fall)
			_streak_material.set_shader_parameter("camera_velocity", _camera_velocity)
			_streak_material.set_shader_parameter("flash", flash)
	var view := _view()
	var profile: Dictionary = VIEW_RAIN.get(view, VIEW_RAIN.chase)
	var lens := view != "pilot" or bool(settings.get("glasses", false))
	if not lens:
		if _pool != null:
			_pool.clear()
		return
	if not raining and (_pool == null or _pool.count == 0):
		return
	if not _ensure_pool():
		return
	var aspect := _aspect()
	if raining and dt > 0.0:
		var forward := -_camera.global_basis.z
		var closing := -(fall - _camera_velocity).dot(forward)
		var expected := minf(RainModel.arrival_rate(rate, closing, float(profile.gain)), MAX_ARRIVALS_PER_S) * dt
		for i in _pool.poisson(expected):
			var diameter := RainModel.sample_diameter(rate, _pool.random())
			_pool.spawn_random(aspect, diameter * float(profile.scale))
	# Gravity on the image plane, the focus of expansion and the air shear, in screen axes (y down).
	var to_camera := _camera.global_basis.inverse()
	var g_cam := to_camera * Vector3.DOWN
	var gravity := Vector2(g_cam.x, -g_cam.y)
	var v_cam := to_camera * _camera_velocity
	var focus := Vector2(aspect * 0.5, 0.5)
	var air := 0.0
	var lateral := Vector2.ZERO
	if bool(profile.air):
		var forward_speed := -v_cam.z
		if forward_speed > 1.0 and not _camera.is_position_behind(_camera.global_position + _camera_velocity):
			var size := _viewport_size()
			focus = _camera.unproject_position(_camera.global_position + _camera_velocity.normalized() * 10.0) / maxf(size.y, 1.0)
		air = clampf(pow(maxf(forward_speed, 0.0) / 30.0, 2.0), 0.0, 1.5)
		lateral = Vector2(-v_cam.x, v_cam.y) / 30.0 * 0.4
	_pool.step(dt, aspect, gravity, focus, air, lateral, raining)
	_drop_material.set_shader_parameter("focus_lod", float(profile.focus) * float(_tier.get("focus_lod", 1.5)) / 1.5)
	_drop_material.set_shader_parameter("flash", flash)
	_pool.write(_drops_node.multimesh, _viewport_size().y, raining)


func _advance_blood(dt: float) -> void:
	_pulse = maxf(_pulse - dt / PULSE_DECAY_S * _pulse, 0.0) if _pulse > 0.002 else 0.0
	if _blood_active:
		_blood_t += dt
		if _blood_t >= _blood_end:
			_blood_active = false
	_blood_dry = clampf((_blood_t - _blood_drain_start) / 3.5, 0.0, 1.0) if _blood_active else _blood_dry
	if _film_material == null:
		return
	var colour: Dictionary = COLOURS.get(str(settings.get("colour", "red")), COLOURS.red)
	_film_material.set_shader_parameter("curtain_on", 1.0 if _blood_active else 0.0)
	_film_material.set_shader_parameter("curtain_t", _blood_t)
	_film_material.set_shader_parameter("depth", _blood_depth)
	_film_material.set_shader_parameter("speed", CURTAIN_SPEED)
	_film_material.set_shader_parameter("drain_start", _blood_drain_start)
	_film_material.set_shader_parameter("drain_rate", CURTAIN_DRAIN_RATE)
	_film_material.set_shader_parameter("fade", 1.0 - smoothstep(_blood_end - 1.2, _blood_end, _blood_t))
	_film_material.set_shader_parameter("seed", _blood_seed)
	_film_material.set_shader_parameter("clear_centre", 1.0 if bool(settings.get("clear_centre", false)) else 0.0)
	_film_material.set_shader_parameter("sigma", colour.sigma)
	_film_material.set_shader_parameter("albedo", colour.albedo)
	_film_material.set_shader_parameter("dry_albedo", colour.dry)
	_film_material.set_shader_parameter("pulse", _pulse)
	_film_material.set_shader_parameter("dust", _dust)
	_film_material.set_shader_parameter("oil", _oil)


func _advance_grime(dt: float) -> void:
	if dt <= 0.0:
		return
	_dust = maxf(_dust - dt / DUST_DECAY_S, 0.0)
	if _glow and _view() == "closeup" and _engine_running.is_valid() and bool(_engine_running.call()):
		_oil = minf(_oil + dt / OIL_FULL_S, OIL_MAX)
		if _oil > 0.0:
			_ensure_film()
	var v_cam := _camera.global_basis.inverse() * _camera_velocity
	var blowing := -v_cam.z > 22.0 and _view() in ["closeup", "chase", "fpv"]
	var i := 0
	while i < _stamps.size():
		var stamp: Dictionary = _stamps[i]
		stamp.age = float(stamp.age) + dt
		var life: float = stamp.life
		var alpha := clampf(float(stamp.age) / 0.06, 0.0, 1.0)
		if is_finite(life):
			alpha *= clampf((life - float(stamp.age)) / 1.5, 0.0, 1.0)
		if blowing and int(stamp.kind) == STAMP_GRASS:
			stamp.life = minf(life, float(stamp.age) + 0.6)
		stamp.alpha = alpha
		if is_finite(life) and float(stamp.age) >= life:
			_stamps.remove_at(i)
			continue
		i += 1


func _add_stamp(kind: int, at: Vector2, size: float, life: float) -> void:
	var limit := int(_tier.get("stamps", 16))
	if _stamps.size() >= limit:
		# Keep the crack; drop the oldest other stamp.
		for index in _stamps.size():
			if int(_stamps[index].kind) != STAMP_CRACK:
				_stamps.remove_at(index)
				break
		if _stamps.size() >= limit:
			return
	_stamps.append({"kind": kind, "x": at.x, "y": at.y, "size": size, "angle": _rng.randf() * TAU,
		"seed": _rng.randf(), "age": 0.0, "life": life, "alpha": 0.0})


func _write_stamps() -> void:
	if _stamps_node == null:
		return
	var mesh := _stamps_node.multimesh
	var height := _viewport_size().y
	var n := mini(_stamps.size(), mesh.instance_count)
	for i in n:
		var stamp: Dictionary = _stamps[i]
		var size_px := float(stamp.size) * 2.0 * height
		var aspect_scale := Vector2(size_px * (2.6 if int(stamp.kind) == STAMP_GRASS else 1.0), size_px)
		mesh.set_instance_transform_2d(i, Transform2D(float(stamp.angle), aspect_scale, 0.0, Vector2(float(stamp.x), float(stamp.y)) * height))
		mesh.set_instance_custom_data(i, Color(float(stamp.kind), float(stamp.seed), float(stamp.alpha), size_px * 0.5))
	mesh.visible_instance_count = n
	_stamp_material.set_shader_parameter("blood_dry", _blood_dry)
	var colour: Dictionary = COLOURS.get(str(settings.get("colour", "red")), COLOURS.red)
	_stamp_material.set_shader_parameter("blood_sigma", colour.sigma)
	_stamp_material.set_shader_parameter("blood_albedo", colour.albedo)


func _apply_visibility() -> void:
	if _film != null:
		_film.visible = _blood_active or _pulse > 0.002 or _dust > 0.002 or _oil > 0.002
	if _stamps_node != null:
		_stamps_node.visible = not _stamps.is_empty()
	if _drops_node != null:
		_drops_node.visible = _pool != null and _pool.count > 0


func _ensure_layer() -> void:
	if _layer != null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "LensLayer"
	_layer.layer = LAYER
	add_child(_layer)


func _ensure_pool() -> bool:
	if _pool != null:
		return true
	var capacity := int(_tier.get("drops", 64))
	if capacity <= 0:
		return false
	_ensure_layer()
	_pool = DropPool.new()
	_pool.configure(capacity, hash([_seed, "drops"]), bool(_tier.get("trails", true)))
	_drop_material = ShaderMaterial.new()
	_drop_material.shader = DROP_SHADER
	_drops_node = _quad_instances("LensDrops", capacity, _drop_material)
	_layer.add_child(_drops_node)
	_layer.move_child(_drops_node, 0)
	return true


func _ensure_stamps() -> void:
	if _stamps_node != null:
		return
	_ensure_layer()
	_stamp_material = ShaderMaterial.new()
	_stamp_material.shader = STAMP_SHADER
	_stamps_node = _quad_instances("LensStamps", int(_tier.get("stamps", 16)), _stamp_material)
	_layer.add_child(_stamps_node)
	if _film != null:
		_layer.move_child(_film, -1)


func _ensure_film() -> void:
	if _film != null:
		return
	_ensure_layer()
	_film_material = ShaderMaterial.new()
	_film_material.shader = FILM_SHADER
	_film = ColorRect.new()
	_film.name = "LensFilm"
	_film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_film.material = _film_material
	_film.visible = false
	_layer.add_child(_film)


func _ensure_streaks() -> void:
	if _streaks != null:
		return
	var count := int(_tier.get("streaks", 4000))
	if count <= 0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	# Positions come from the shader; every instance keeps the identity transform (12 floats each).
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	buffer.fill(0.0)
	for i in count:
		buffer[i * 12] = 1.0
		buffer[i * 12 + 5] = 1.0
		buffer[i * 12 + 10] = 1.0
	multimesh.buffer = buffer
	_streak_material = ShaderMaterial.new()
	_streak_material.shader = STREAK_SHADER
	_streak_material.set_shader_parameter("box_size", STREAK_BOX)
	_streaks = MultiMeshInstance3D.new()
	_streaks.name = "RainStreaks"
	_streaks.multimesh = multimesh
	_streaks.material_override = _streak_material
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_streaks.custom_aabb = AABB(-STREAK_BOX * 0.5, STREAK_BOX)
	_streaks.top_level = true
	add_child(_streaks)


static func _quad_instances(node_name: String, capacity: int, material: ShaderMaterial) -> MultiMeshInstance2D:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = maxi(capacity, 1)
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance2D.new()
	node.name = node_name
	node.multimesh = multimesh
	node.material = material
	node.visible = false
	return node
