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
const CollisionWorld := preload("res://scenery/collision_world.gd")
const DROP_SHADER := preload("res://render/lens/lens_drop.gdshader")
const STAMP_SHADER := preload("res://render/lens/lens_stamp.gdshader")
const FILM_SHADER := preload("res://render/lens/lens_film.gdshader")
const STREAK_SHADER := preload("res://render/lens/rain_streaks.gdshader")
## Real ink splatters (CC0, Dino0040 via OpenGameArt): app/assets/lens/sources.json, tools/lens/build_splat_atlas.py.
## Loaded only when the stamp channel is built: a disabled stack holds no atlas in memory.
const SPLAT_ATLAS_PATH := "res://assets/lens/splats.png"
## Frames the warmed-up nodes draw invisibly at flight setup, so the first strike or raindrop compiles nothing.
const WARMUP_FRAMES := 3
const MESSAGE_S := 5.0
const STREAK_TRAVEL_REBASE_M := 50000.0
## Closing speed above which arriving drops may burst into satellite beads.
const SPLASH_SPEED_MPS := 8.0
## Wheel throw (kick_up): full strength at this speed; the camera catches it inside KICK_NEAR_M, none past KICK_FAR_M;
## average flecks and drops per second at full mud or water activity.
const KICK_FULL_SPEED_MPS := 8.0
const KICK_SPIN_FLOOR := 0.45
const KICK_NEAR_M := 1.5
const KICK_FAR_M := 6.0
const KICK_MUD_PER_S := 2.5
const KICK_WATER_PER_S := 14.0
const CRACK_POINTS := 30
## Rain streaks fall faster than the number-weighted mean drop: what the eye reads as rain are the large, fast drops.
## Art factor on the mean fall speed for the streaks only; arrivals on the lens use the physical mean.
const STREAK_SPEED_FACTOR := 2.6
const WET_RISE_S := 6.0
const WET_DRY_S := 40.0
## The pilot-strike sweep runs only while the aircraft is this close to the station (horizontal metres).
const PILOT_WATCH_RADIUS_M := 15.0

const LAYER := -9
const CURTAIN_SPEED := 0.8
const CURTAIN_DRAIN_RATE := 0.42
const PULSE_DECAY_S := 0.35
const SPLATTER_LIFE_S := 7.0
const SPLATTER_STAY_S := 22.0
const DUST_DECAY_S := 14.0
const OIL_FULL_S := 900.0
const OIL_MAX := 0.55
const CRACK_SPEED_MPS := 12.0
const STREAK_BOX := Vector3(36.0, 24.0, 36.0)
## Spec.CAMERA.fov_deg: the unzoomed vertical field of view the streak volume is sized for.
const BASE_FOV_DEG := 50.0
const STREAK_ZOOM_DENSITY := 4.0
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
	"red": {"sigma": Vector3(1.8, 9.0, 10.0), "albedo": Vector3(0.19, 0.009, 0.008), "dry": Vector3(0.09, 0.016, 0.011)},
	"dark": {"sigma": Vector3(2.4, 3.0, 3.3), "albedo": Vector3(0.08, 0.05, 0.04), "dry": Vector3(0.05, 0.035, 0.03)},
	"desaturated": {"sigma": Vector3(2.0, 2.0, 2.0), "albedo": Vector3(0.18, 0.18, 0.18), "dry": Vector3(0.1, 0.1, 0.1)},
}
const STAMP_BLOOD := 0
const STAMP_MUD := 1
const STAMP_GRASS := 2
const STAMP_CRACK := 3
const STAMP_RUNNER := 4
## Blood runner quad height / length (lens_stamp.gdshader RUNNER_ASPECT) and how fast a runner creeps toward its reach:
## blood is viscous, so it slows exponentially and stops as it sets.
const RUNNER_ASPECT := 0.12
const RUNNER_TAU_S := 2.2
## Seconds of dry air for a splat to set: blood dries in seconds, mud takes longer. Rain keeps both wet.
const BLOOD_DRY_S := 7.0
const MUD_DRY_S := 25.0
## Steady rain rinses mud off the glass within this many seconds.
const MUD_RINSE_S := 35.0

## A person (player = the pilot) was struck hard enough to draw blood. The flight shows a short safety note.
signal person_struck(player: bool)

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
var _wetness := 0.0
var _wet_clock := 0.0
var _last_surface_tick := -1000000
## Accumulated fall of the rain streaks (render metres): integrating the changing fall velocity keeps every streak
## continuous when wind or the rain rate changes, instead of jumping by Δv × clock.
var _streak_travel := Vector3.ZERO
var _warmup_frames := 0
var _frame_view := ""
## Gravity on the image plane (screen axes, y down), refreshed every frame; runners creep along it.
var _screen_gravity := Vector2(0.0, 1.0)
var _camera_acceleration := Vector3.ZERO
var _sun: DirectionalLight3D
var _player_struck := false
var _message: Label
var _message_left := 0.0
var _canvas_scale := -1.0

var _camera_previous := Vector3.ZERO
var _camera_velocity := Vector3.ZERO
var _camera_primed := false
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
	_sun = ctx.get("sun") as DirectionalLight3D
	if _sun == null and get_parent() != null:
		_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	_tier = settings.get("tier", Settings.TIERS.medium)
	_rng.seed = hash([_seed, "LENS"])
	_blood_seed = _rng.randf()
	configured = true
	_warm_up()
	return true


## CR-22c-R1's lesson: a loaded material is not a compiled draw. Build the enabled channels' nodes now, during flight
## setup, and draw each once with nothing visible (opacity 0, every film off), so no shader compiles at the first
## strike or raindrop. Disabled channels still build nothing.
func _warm_up() -> void:
	if not is_inside_tree():
		return
	if str(settings.get("impact", "off")) != "off" or bool(settings.get("grime", false)):
		_ensure_stamps()
		_ensure_film()
		_stamps_node.multimesh.set_instance_transform_2d(0, Transform2D(0.0, Vector2(4.0, 4.0), 0.0, Vector2(8.0, 8.0)))
		_stamps_node.multimesh.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 2.0))
		_stamps_node.multimesh.visible_instance_count = 1
	if bool(settings.get("rain", false)) and _ensure_pool():
		_drops_node.multimesh.set_instance_transform_2d(0, Transform2D(0.0, Vector2(4.0, 4.0), 0.0, Vector2(8.0, 8.0)))
		_drops_node.multimesh.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 2.0))
		_drops_node.multimesh.visible_instance_count = 1
	_warmup_frames = WARMUP_FRAMES
	_apply_visibility()


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
	_wetness = 0.0
	_blood_dry = 0.0
	_cracked = false
	_crash_seen = false
	_last_surface_tick = -1000000
	_player_struck = false
	_streak_travel = Vector3.ZERO
	_stamps.clear()
	_seen.clear()
	if _message != null:
		_message.visible = false
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
	# The signal fires on every committed tick; a tick without events needs no detached deep copy.
	var pending: Variant = _session.get("_contact_events")
	if pending is Array and (pending as Array).is_empty():
		return
	var records := ImpactTrigger.admit(_session.contact_events(), _seen, _floor_tick, _mass_kg)
	for record: Dictionary in records:
		var point := Frames.ned_to_render(Array(record.point_ned))
		if record.kind == "person":
			var player := _near_station(record.point_ned, 1.2)
			if player:
				_pilot.reset() # The proximity detector must not fire a second time for the same strike.
			strike_person(float(record.strength), point, player, record.id)
		else:
			_last_surface_tick = int(record.tick)
			strike_surface(str(record.kind), float(record.strength), point, float(record.speed_mps), record.id)


## A person was struck. `player` marks the pilot (the player): always a full strike. `event_key` (the contact event id
## or another accepted identity) reseeds the random stream, so one event always draws the same splats and drips.
func strike_person(strength: float, point: Vector3 = Vector3.INF, player: bool = false, event_key: Variant = null) -> void:
	if not configured or str(settings.get("impact", "off")) == "off":
		return
	_reseed(event_key)
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
	if player:
		_player_struck = true
	person_struck.emit(player)
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
		var splat_size := _rng.randf_range(0.06, 0.15) * (0.6 + 0.6 * s)
		# Splatter stays on the glass and dries in view; with the curtain, the splats leave with it.
		var splat_life := SPLATTER_STAY_S if splatter_only else SPLATTER_LIFE_S - 2.0
		_add_stamp(STAMP_BLOOD, at, splat_size, splat_life)
		# Most splats bleed a runner or two down the glass before they set.
		for _runner in int(_rng.randf() < 0.7) + int(_rng.randf() < 0.25):
			_add_runner(at, splat_size, splat_life)
	_blood_dry = 0.0
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
func strike_surface(kind: String, strength: float, point: Vector3, speed_mps: float = 0.0, event_key: Variant = null) -> void:
	if not configured or not bool(settings.get("grime", false)):
		return
	_reseed(event_key)
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
					_add_stamp(STAMP_MUD, _scatter(screen), _rng.randf_range(0.05, 0.12) * (0.7 + 0.6 * s), INF)
				for i in int(round(1.5 * s)):
					_add_stamp(STAMP_GRASS, _scatter(screen), _rng.randf_range(0.03, 0.06), INF)
		"mown", "foliage":
			_dust = maxf(_dust, 0.12 * s)
			if near_lens:
				_ensure_stamps()
				for i in 1 + int(round(2.0 * s)):
					_add_stamp(STAMP_GRASS, _scatter(screen), _rng.randf_range(0.035, 0.07), INF)
		_:
			_dust = maxf(_dust, 0.45 * s)
	if near_lens and view in ["closeup", "fpv"] and speed_mps >= CRACK_SPEED_MPS and not _cracked:
		_ensure_stamps()
		_cracked = true
		_add_stamp(STAMP_CRACK, Vector2(_rng.randf_range(0.5, 1.2), _rng.randf_range(0.3, 0.7)), 0.8, INF)
		_stamp_material.set_shader_parameter("crack_points", _crack_points())
		_stamp_material.set_shader_parameter("crack_point_count", CRACK_POINTS)
	if _dust > 0.0:
		_ensure_film()
		_film_material.set_shader_parameter("dust_seed", _rng.randf())
	_apply_visibility()


## Routes whose sessions report a crash only as a reason and a position (FPV quad, helicopter) name what was hit here:
## the installed obstacle inventory is asked, read-only, what lies within `radius_m` of the accepted crash point. A
## person draws blood; another obstacle or the ground leaves grime. Nothing is written back to the session.
func strike_from_crash(point_ned: PackedFloat64Array, speed_mps: float, obstacle_world: Dictionary, event_key: Variant,
		radius_m: float = 0.6) -> void:
	if not configured or point_ned.size() != 3:
		return
	var point := Frames.ned_to_render(Array(point_ned))
	var strength := clampf(speed_mps / 20.0, 0.0, 1.0)
	var obstacle := false
	if not obstacle_world.is_empty():
		for proxy: Dictionary in CollisionWorld.nearby(obstacle_world, point_ned[0], point_ned[1], point_ned[2], radius_m):
			if str(proxy.get("kind", "")) == "person":
				var player := _near_station(point_ned, 1.2)
				if player and _player_struck:
					return # the pilot-strike sweep already showed this strike
				var energy := 0.5 * _mass_kg * speed_mps * speed_mps
				strike_person(ImpactTrigger.person_strength(energy, false), point, player, event_key)
				return
			obstacle = true
	strike_surface("obstacle" if obstacle else "ground", strength, point, speed_mps, event_key)


## RC cars and trucks: wheels throwing mud and water at a camera close behind them (the rally-game classic). `mud` and
## `water` are the wheels' summed activity (0…1 each, as the wet-effects presenter measures it), `source` the vehicle's
## render position. Arrivals are random in presentation time, scaled by speed and how close the camera is.
func kick_up(mud: float, water: float, source: Vector3, speed_mps: float, dt: float) -> void:
	if not configured or not bool(settings.get("grime", false)) or dt <= 0.0 or (mud <= 0.0 and water <= 0.0):
		return
	if _view() == "pilot" and not bool(settings.get("glasses", false)):
		return # the driver's eye is metres away from the wheels
	var reach := 1.0 - smoothstep(KICK_NEAR_M, KICK_FAR_M, _camera.global_position.distance_to(source))
	# Spinning wheels throw even when the truck crawls (the activity already carries wheel motion): a floor, plus speed.
	var throw := clampf(KICK_SPIN_FLOOR + speed_mps / KICK_FULL_SPEED_MPS, 0.0, 1.5) * reach
	if throw <= 0.01:
		return
	var aspect := _aspect()
	if mud > 0.0 and _rng.randf() < clampf(mud, 0.0, 1.0) * throw * KICK_MUD_PER_S * dt:
		_ensure_stamps()
		# Flecks land low on the lens first: the wheels are below the camera.
		var at := Vector2(_rng.randf() * aspect, clampf(_rng.randfn(0.72, 0.18), 0.05, 0.98))
		_add_stamp(STAMP_MUD, at, _rng.randf_range(0.012, 0.038), INF)
		_apply_visibility()
	if water > 0.0 and bool(settings.get("rain", false)) and _ensure_pool():
		for i in _pool.poisson(clampf(water, 0.0, 1.0) * throw * KICK_WATER_PER_S * dt):
			_pool.spawn(_rng.randf() * aspect, clampf(_rng.randfn(0.7, 0.2), 0.02, 0.98), _rng.randf_range(0.004, 0.016))


## A rebuilt stack (settings changed mid-flight) must not replay the crash it was rebuilt after.
func mark_crash_shown() -> void:
	_crash_seen = true


## One accepted event, one random stream: placement still follows the camera, but sizes, shapes and drips repeat.
func _reseed(event_key: Variant) -> void:
	if event_key != null:
		_rng.seed = hash([_seed, event_key, "LENS"])


## Feature points of the cracked lens (after Impact Glass Shader, MIT): scattered at growing radii around the impact,
## computed once per crack on the CPU so the shader loop is plain distances. Quad half-size units.
func _crack_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(CRACK_POINTS)
	for i in CRACK_POINTS:
		var t := float(i) / float(CRACK_POINTS - 1)
		var radius := 1.05 * pow(t, 1.2)
		var angle := _rng.randf() * TAU + _rng.randf_range(-0.5, 0.5)
		points[i] = Vector2(cos(angle), sin(angle)) * radius
	return points


## Water thrown onto the lens (a splash-down, a ditching, spray from a wet field).
func _spray(strength: float) -> void:
	if not _ensure_pool():
		return
	var aspect := _aspect()
	for i in 6 + int(round(30.0 * strength)):
		_pool.spawn_random(aspect, _rng.randf_range(0.004, 0.022))


## A short caption over the lens (above the curtain, under the HUD): built on first use, fades out by itself.
func show_message(text: String, seconds: float = MESSAGE_S) -> void:
	if not configured or text.is_empty():
		return
	_ensure_layer()
	if _message == null:
		_message = Label.new()
		_message.name = "LensMessage"
		_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_message.add_theme_color_override("font_color", Color(1.0, 0.96, 0.92))
		_message.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 0.9))
		_layer.add_child(_message)
	_layer.move_child(_message, -1)
	var size := _viewport_size()
	_message.add_theme_font_size_override("font_size", int(round(clampf(size.y * 0.03, 16.0, 64.0))))
	_message.add_theme_constant_override("outline_size", int(round(clampf(size.y * 0.006, 3.0, 12.0))))
	_message.position = Vector2(size.x * 0.15, size.y * 0.70)
	_message.size = Vector2(size.x * 0.7, size.y * 0.12)
	_message.text = text
	_message_left = seconds
	_message.modulate.a = 1.0
	_message.visible = true


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
		"dust": _dust, "oil": _oil, "cracked": _cracked, "wetness": _wetness,
		"nodes": {"layer": _layer != null, "drops": _drops_node != null, "stamps": _stamps_node != null,
			"film": _film != null, "streaks": _streaks != null},
	}


## One rendered frame. `clock_s` is the visual clock (simulation time on interactive flights); `paused` holds every
## animation (menus, pause, calibration) exactly like the crash presentation.
func advance(delta: float, clock_s: float, paused: bool) -> void:
	if not configured or _camera == null or not is_instance_valid(_camera):
		return
	var dt := 0.0 if paused else clampf(delta, 0.0, 0.1)
	_frame_view = _query_view()
	_track_camera(delta, paused)
	var g_cam := _camera.global_basis.inverse() * Vector3.DOWN
	if Vector2(g_cam.x, -g_cam.y).length() > 0.25:
		_screen_gravity = Vector2(g_cam.x, -g_cam.y).normalized()
	if not paused:
		_observe_pilot(clock_s)
		_observe_crash()
	_advance_rain(dt, clock_s)
	_advance_blood(dt)
	_advance_grime(dt)
	if _message != null and _message.visible:
		_message_left -= dt
		_message.modulate.a = clampf(_message_left / 0.8, 0.0, 1.0)
		_message.visible = _message_left > 0.0
	_write_stamps()
	_apply_canvas_scale()
	if _warmup_frames > 0:
		_warmup_frames -= 1
	_apply_visibility()


## Drops and wet splats catch the sun (or moon): their highlight turns toward its screen position and brightens when
## it shines into the lens. Reads the scene's DirectionalLight3D; never changes it.
func _apply_sun_glint(material: ShaderMaterial) -> void:
	if material == null:
		return
	var uv := Vector2(-1.0, -1.0)
	var strength := 0.0
	if is_instance_valid(_sun) and _sun.visible:
		var toward := _sun.global_basis.z.normalized()
		var target := _camera.global_position + toward * 1000.0
		if not _camera.is_position_behind(target):
			var size := _viewport_size()
			uv = _camera.unproject_position(target) / size
			var facing := clampf(toward.dot(-_camera.global_basis.z), 0.0, 1.0)
			strength = clampf(_sun.light_energy, 0.0, 2.0) * facing * facing
	material.set_shader_parameter("sun_uv", uv)
	material.set_shader_parameter("sun_strength", strength)


## A material created after the scale was measured gets it at once (lazy channels, debug calls).
func _push_canvas_scale(material: ShaderMaterial) -> void:
	if material != null and _canvas_scale > 0.0:
		material.set_shader_parameter("canvas_scale", _canvas_scale)


## Physical pixels per canvas pixel. The UI stretches the canvas on large screens (canvas_items content scale), and
## the drop and stamp shaders turn canvas-pixel offsets into screen uv with it.
func _apply_canvas_scale() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	var logical := viewport.get_visible_rect().size
	var physical := Vector2(viewport.size) if not (viewport is Window) else Vector2((viewport as Window).size)
	var scale := physical.y / maxf(logical.y, 1.0) if physical.y > 0.0 else 1.0
	if is_equal_approx(scale, _canvas_scale):
		return
	_canvas_scale = scale
	if _drop_material != null:
		_drop_material.set_shader_parameter("canvas_scale", scale)
	if _stamp_material != null:
		_stamp_material.set_shader_parameter("canvas_scale", scale)


## The active view, read once per frame (advance) and between frames on demand.
func _view() -> String:
	if not _frame_view.is_empty():
		return _frame_view
	return _query_view()


func _query_view() -> String:
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
	return Vector2(clampf(screen.x + _rng.randf_range(-0.55, 0.55), 0.0, aspect), clampf(screen.y + _rng.randf_range(-0.38, 0.38), 0.0, 1.0))


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
		_camera_acceleration = Vector3.ZERO
		return
	var previous_velocity := _camera_velocity
	_camera_velocity = _camera_velocity.lerp(raw, clampf(delta * 8.0, 0.0, 1.0))
	var raw_acceleration := (_camera_velocity - previous_velocity) / delta
	_camera_acceleration = _camera_acceleration.lerp(raw_acceleration.limit_length(80.0), clampf(delta * 6.0, 0.0, 1.0))


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
	# Far from the pilot nothing can strike: skip the hull transform and forget the sweep's start.
	if Vector2(state[RB.POS] - _station[0], state[RB.POS + 1] - _station[1]).length() > PILOT_WATCH_RADIUS_M:
		_pilot.forget()
		return
	var points := PilotStrike.hull_world(state.slice(RB.POS, RB.POS + 3), state.slice(RB.ATT, RB.ATT + 4), _hull)
	if dt <= 0.0:
		_pilot.observe(points, _station, _eye_height, 1.0)
		return
	var hit: Dictionary = _pilot.observe(points, _station, _eye_height, dt)
	if not hit.is_empty():
		strike_person(1.0, Frames.ned_to_render(Array(hit.point_ned)), true, "pilot:%d" % int(sim.tick))


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
	# Scenery and lake impacts already arrived as contact events; a ground event at the same tick did too.
	var tick := int(impact.get("tick"))
	if str(impact.get("trigger")) in ["scenery", "water", "lake_bank"] or absi(tick - _last_surface_tick) <= 4:
		return
	var point_ned: PackedFloat64Array = impact.get("point_ned")
	if point_ned.size() != 3:
		return
	var speed := float(impact.get("speed_mps"))
	strike_surface("ground", clampf(speed / 20.0, 0.0, 1.0), Frames.ned_to_render(Array(point_ned)), speed, "crash:%d" % tick)


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
	var fall_speed := maxf(RainModel.mean_fall_speed(maxf(rate, 0.5)), 2.0)
	var fall := Vector3(wind.x, -fall_speed, wind.z)
	var streak_fall := Vector3(wind.x, -fall_speed * STREAK_SPEED_FACTOR, wind.z)
	_streak_travel += streak_fall * dt
	# float32 uniforms lose millimetres past ~1e5 m (hours of rain): rebase rarely; the one-off reshuffle is invisible.
	if _streak_travel.length() > STREAK_TRAVEL_REBASE_M:
		_streak_travel = Vector3.ZERO
	if _streaks != null:
		_streaks.visible = raining
		if raining:
			# A zoomed view (the pilot's auto-zoom down to 6°) sees a narrow, deep cone: the rain volume grows in powers
			# of two with the zoom and moves ahead along the view, so the frustum stays filled. Steps, not a continuous
			# scale, keep every streak's world trajectory fixed between steps.
			var zoom := tan(deg_to_rad(BASE_FOV_DEG) * 0.5) / tan(deg_to_rad(clampf(_camera.fov, 1.0, 120.0)) * 0.5)
			var scale := clampf(pow(2.0, round(log(maxf(zoom, 1.0)) / log(2.0))), 1.0, 8.0)
			var box := STREAK_BOX * scale
			# A larger volume needs more drops for the same visible density in its narrower cone (vertex cost only:
			# drops outside the view are clipped). Up to STREAK_ZOOM_DENSITY × the tier's base count.
			var count := int(_streaks.multimesh.instance_count)
			var base := float(count) / STREAK_ZOOM_DENSITY
			var wanted := base * minf(scale * scale, STREAK_ZOOM_DENSITY) * clampf(rate / 18.0, 0.12, 1.0)
			_streaks.multimesh.visible_instance_count = clampi(int(wanted), 1, count)
			var centre := _camera.global_position - _camera.global_basis.z * (box.z * 0.4 if scale > 1.0 else 0.0)
			# Moving the box never moves a streak inside the overlap: the wrap is invariant to its origin.
			_streaks.global_position = centre
			_streaks.custom_aabb = AABB(-box * 0.5, box)
			_streak_material.set_shader_parameter("box_size", box)
			_streak_material.set_shader_parameter("near_fade_m", 1.2 * scale)
			_streak_material.set_shader_parameter("far_fade_m", box.z * (0.85 if scale > 1.0 else 0.46))
			_streak_material.set_shader_parameter("travel", _streak_travel)
			_streak_material.set_shader_parameter("box_centre", centre)
			_streak_material.set_shader_parameter("fall_velocity", streak_fall)
			_streak_material.set_shader_parameter("camera_velocity", _camera_velocity)
			_streak_material.set_shader_parameter("flash", flash)
	var view := _view()
	var profile: Dictionary = VIEW_RAIN.get(view, VIEW_RAIN.chase)
	var lens := view != "pilot" or bool(settings.get("glasses", false))
	_advance_wetness(dt, rate, lens)
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
		# A fast drop does not just land: it bursts into a crown of beads (more likely the harder it hits).
		var splash_chance := clampf((closing - SPLASH_SPEED_MPS) / 25.0, 0.0, 0.7)
		for i in _pool.poisson(expected):
			var diameter := RainModel.sample_diameter(rate, _pool.random())
			var radius := diameter * float(profile.scale)
			var x := _pool.random() * aspect
			var y := _pool.random()
			_pool.spawn(x, y, radius)
			if _pool.random() < splash_chance:
				_pool.splash(x, y, radius, 2 + int(_pool.random() * 4.0))
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
	# The glass is carried by the camera: its acceleration is a pseudo-gravity the other way (g units, image plane).
	var a_cam := to_camera * _camera_acceleration
	var inertia := Vector2(-a_cam.x, a_cam.y) / 9.81 if bool(profile.air) or view == "flyby" else Vector2.ZERO
	_pool.step(dt, aspect, gravity, focus, air, lateral, raining, inertia.limit_length(4.0))
	_drop_material.set_shader_parameter("focus_lod", float(profile.focus) * float(_tier.get("focus_lod", 1.5)) / 1.5)
	_drop_material.set_shader_parameter("flash", flash)
	_apply_sun_glint(_drop_material)
	_pool.write(_drops_node.multimesh, _viewport_size().y, raining, gravity)


## Fine beads cover a lens in the rain within seconds and evaporate slowly after it; airflow at speed thins them.
func _advance_wetness(dt: float, rate: float, lens: bool) -> void:
	var target := 0.0
	if lens and rate > 0.0 and bool(_tier.get("wetness", true)):
		var v_cam := _camera.global_basis.inverse() * _camera_velocity
		var air := clampf(pow(maxf(-v_cam.z, 0.0) / 30.0, 2.0), 0.0, 1.0)
		target = clampf(rate / 10.0, 0.25, 1.0) * (1.0 - 0.6 * air)
	if not lens:
		_wetness = 0.0
	elif _wetness < target:
		_wetness = minf(_wetness + dt / WET_RISE_S, target)
	else:
		_wetness = maxf(_wetness - dt / WET_DRY_S, target)
	_wet_clock += dt
	if _wetness > 0.0:
		_ensure_film()


func _advance_blood(dt: float) -> void:
	_pulse = maxf(_pulse - dt / PULSE_DECAY_S * _pulse, 0.0) if _pulse > 0.002 else 0.0
	# Rain on the glass washes blood away: the curtain runs and drains faster, up to 1.6× in a downpour.
	var wash := 1.0 + clampf(last_rain_mmph / 20.0, 0.0, 0.6) if _view() != "pilot" or bool(settings.get("glasses", false)) else 1.0
	if _blood_active:
		_blood_t += dt * wash
		if _blood_t >= _blood_end:
			_blood_active = false
	if _blood_active:
		_blood_dry = clampf((_blood_t - _blood_drain_start) / 3.5, 0.0, 1.0)
	elif not _stamps.is_empty():
		# Lens splatter has no curtain clock: its splats darken over their own life.
		_blood_dry = minf(_blood_dry + dt / SPLATTER_LIFE_S, 1.0)
	# A hidden film needs no uniforms: nothing it would draw is active.
	if _film_material == null or not (_blood_active or _pulse > 0.002 or _dust > 0.002 or _oil > 0.002 or _wetness > 0.002):
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
	_film_material.set_shader_parameter("wetness", _wetness)
	if _wetness > 0.002:
		_apply_sun_glint(_film_material)
	_film_material.set_shader_parameter("wet_clock", fposmod(_wet_clock, 1000.0))
	_film_material.set_shader_parameter("wet_focus", float(VIEW_RAIN.get(_view(), VIEW_RAIN.chase).focus))
	_film_material.set_shader_parameter("dust", _dust)
	_film_material.set_shader_parameter("oil", _oil)


func _advance_grime(dt: float) -> void:
	if dt <= 0.0:
		return
	var v_air := _camera.global_basis.inverse() * _camera_velocity
	# Airspeed scours dust off the glass: at 30 m/s it clears about three times faster.
	_dust = maxf(_dust - dt / DUST_DECAY_S * (1.0 + maxf(-v_air.z, 0.0) / 15.0), 0.0)
	var wet_lens := last_rain_mmph > 0.0 and (_view() != "pilot" or bool(settings.get("glasses", false)))
	if _glow and _view() == "closeup" and _engine_running.is_valid() and bool(_engine_running.call()):
		_oil = minf(_oil + dt / OIL_FULL_S, OIL_MAX)
		if _oil > 0.0:
			_ensure_film()
	var v_cam := _camera.global_basis.inverse() * _camera_velocity
	var blowing := -v_cam.z > 22.0 and _view() in ["closeup", "chase", "fpv"]
	var i := 0
	while i < _stamps.size():
		var stamp: Dictionary = _stamps[i]
		var kind := int(stamp.kind)
		var bloody := kind == STAMP_BLOOD or kind == STAMP_RUNNER
		# Rain rinses blood off the glass sooner, keeps every splat wet, and washes mud away over half a minute.
		var rinse := 1.0 + clampf(last_rain_mmph / 10.0, 0.0, 1.5) if bloody else 1.0
		stamp.age = float(stamp.age) + dt * rinse
		if not wet_lens:
			stamp.dry_t = float(stamp.dry_t) + dt
		elif kind == STAMP_MUD:
			stamp.life = minf(float(stamp.life), float(stamp.age) + MUD_RINSE_S)
		if kind == STAMP_RUNNER:
			# Creeps fast while fresh, slows as it thins and stops once the blood sets.
			stamp.grow = 1.0 - exp(-minf(float(stamp.age), BLOOD_DRY_S + float(stamp.age) - float(stamp.dry_t)) / RUNNER_TAU_S)
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


## A viscous blood runner leaving a splat along screen gravity (a little off it, as real drips wander).
func _add_runner(at: Vector2, splat_size: float, life: float) -> void:
	var direction := _screen_gravity.rotated(_rng.randf_range(-0.18, 0.18))
	var start := at + direction * splat_size * _rng.randf_range(0.15, 0.4) + direction.orthogonal() * splat_size * _rng.randf_range(-0.3, 0.3)
	_add_stamp(STAMP_RUNNER, start, splat_size * _rng.randf_range(1.0, 3.2), life)
	if not _stamps.is_empty() and int(_stamps[-1].kind) == STAMP_RUNNER:
		_stamps[-1].angle = direction.angle()


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
		"seed": _rng.randf(), "age": 0.0, "life": life, "alpha": 0.0, "dry_t": 0.0, "grow": 0.0})


func _write_stamps() -> void:
	if _stamps_node == null or (_stamps.is_empty() and (_warmup_frames > 0 or _stamps_node.multimesh.visible_instance_count == 0)):
		return
	var mesh := _stamps_node.multimesh
	var height := _viewport_size().y
	var n := mini(_stamps.size(), mesh.instance_count)
	# The crack refracts the whole region it covers from the screen copy taken before the stamps: drawn last it would
	# paint the clean scene over mud and blood. It is the glass itself, so it goes first and everything sits on it.
	var order: Array[Dictionary] = []
	for stamp: Dictionary in _stamps:
		if int(stamp.kind) == STAMP_CRACK:
			order.push_front(stamp)
		else:
			order.append(stamp)
	for i in n:
		var stamp: Dictionary = order[i]
		var kind := int(stamp.kind)
		var dry := 0.0
		if kind == STAMP_BLOOD or kind == STAMP_RUNNER:
			dry = clampf(float(stamp.dry_t) / BLOOD_DRY_S, 0.0, 1.0)
		elif kind == STAMP_MUD:
			dry = clampf(float(stamp.dry_t) / MUD_DRY_S, 0.0, 1.0)
		# The kind and this stamp's dryness share x: integer part and fraction (lens_stamp.gdshader).
		var packed_kind := float(kind) + dry * 0.9
		if kind == STAMP_RUNNER:
			var length_px := float(stamp.size) * height
			var direction := Vector2.from_angle(float(stamp.angle))
			var centre := Vector2(float(stamp.x), float(stamp.y)) * height + direction * length_px * 0.5
			mesh.set_instance_transform_2d(i, Transform2D(float(stamp.angle), Vector2(length_px, length_px * RUNNER_ASPECT), 0.0, centre))
			mesh.set_instance_custom_data(i, Color(packed_kind, float(stamp.grow), float(stamp.alpha), length_px * 0.5))
			continue
		var size_px := float(stamp.size) * 2.0 * height
		var aspect_scale := Vector2(size_px * (2.6 if kind == STAMP_GRASS else 1.0), size_px)
		mesh.set_instance_transform_2d(i, Transform2D(float(stamp.angle), aspect_scale, 0.0, Vector2(float(stamp.x), float(stamp.y)) * height))
		mesh.set_instance_custom_data(i, Color(packed_kind, float(stamp.seed), float(stamp.alpha), size_px * 0.5))
	mesh.visible_instance_count = n
	_stamp_material.set_shader_parameter("blood_dry", _blood_dry)
	var colour: Dictionary = COLOURS.get(str(settings.get("colour", "red")), COLOURS.red)
	_stamp_material.set_shader_parameter("blood_sigma", colour.sigma)
	_stamp_material.set_shader_parameter("blood_albedo", colour.albedo)


func _apply_visibility() -> void:
	var warming := _warmup_frames > 0
	if _film != null:
		_film.visible = warming or _blood_active or _pulse > 0.002 or _dust > 0.002 or _oil > 0.002 or _wetness > 0.002
	if _stamps_node != null:
		_stamps_node.visible = warming or not _stamps.is_empty()
	if _drops_node != null:
		_drops_node.visible = warming or (_pool != null and _pool.count > 0)


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
	_push_canvas_scale(_drop_material)
	return true


func _ensure_stamps() -> void:
	if _stamps_node != null:
		return
	_ensure_layer()
	_stamp_material = ShaderMaterial.new()
	_stamp_material.shader = STAMP_SHADER
	_stamp_material.set_shader_parameter("splat_atlas", load(SPLAT_ATLAS_PATH))
	_stamps_node = _quad_instances("LensStamps", int(_tier.get("stamps", 16)), _stamp_material)
	_layer.add_child(_stamps_node)
	if _film != null:
		_layer.move_child(_film, -1)
	if _message != null:
		_layer.move_child(_message, -1)
	_push_canvas_scale(_stamp_material)


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
	if _message != null:
		_layer.move_child(_message, -1)


func _ensure_streaks() -> void:
	if _streaks != null:
		return
	var count := int(_tier.get("streaks", 4000)) * int(STREAK_ZOOM_DENSITY)
	if count <= 0:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	# Positions come from the shader; every instance keeps the identity transform (12 floats each).
	# Built by doubling, not a per-instance loop: no hitch when the first rain starts mid-flight.
	var buffer := PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	while buffer.size() < count * 12:
		buffer.append_array(buffer)
	buffer.resize(count * 12)
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
