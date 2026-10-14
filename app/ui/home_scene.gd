# The Home backdrop (MENU-PLAN §3/§7, UI-01c, UI-05): the selected airplane (the Ugly Stik by default) over our
# field, rendered from the same builders the flight uses (sky, clouds, grass, runway, sun, the model team's airplane), posed in a fixed, still composition.
# No simulation, no input, no animation: shaders get a fixed sim_clock, so every frame is the same picture.
# A live still render follows the current models, imported tree atlas and landscape.
# World (render/world/world.gd, FW-02) composes the environment, field and sun exactly as the flight does.
extends Node3D

const Spec := preload("res://spec.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Shadow := preload("res://render/shadow.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const World := preload("res://render/world/world.gd")
const FieldError = preload("res://ui/field_error.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

## Composition, in NED metres from the pilot's eyes and degrees: a low pass along the runway at eye height, banked
## toward the camera so the planform shows, seen with a long lens from the field edge (a photographer's view:
## flat perspective, the horizon in the lower third, the airplane in the right third facing the menu).
const AIRPLANE_NED := [15.0, 3.0, -1.05]
const ATTITUDE_DEG := { yaw = -112.0, pitch = 2.0, roll = -30.0 }
const HELICOPTER_ATTITUDE_DEG := { yaw = -112.0, pitch = 0.0, roll = 0.0 }
const CAMERA_NED := [2.0, 3.0, 0.0]
const FOV_DEG := 12.0
## The camera looks this far left of the airplane (deg), and this far above the horizon (deg).
const AIRPLANE_RIGHT_DEG := 4.5
const CAMERA_PITCH_DEG := 3.2
const PROP_ANGLE := 0.6 # rad: a blade off the vertical reads better than a single line
## Fixed clock (s) for clouds and any time-based shader: a still picture.
const CLOCK := 37.0

var field: Dictionary = {}
var lighting_config: Dictionary = {}
var _lighting: Dictionary = {}
var field_errors: PackedStringArray = PackedStringArray()

var airplane: Dictionary
var camera: Camera3D
var _shadow: MeshInstance3D


## `aircraft`: the catalog ID to show (app_state/aircraft_catalog.gd); show_aircraft() swaps it in place.
func _init(aircraft := AirplaneBuilder.STIK_ID, field_path: String = FieldLoader.DEFAULT_PATH, selected_lighting: Dictionary = {}) -> void:
	name = "HomeScene"
	var checked_light: Dictionary = LightingConfig.validate(LightingConfig.defaults() if selected_lighting.is_empty() else selected_lighting)
	if not checked_light.ok:
		field_errors = PackedStringArray(checked_light.errors)
		return
	lighting_config = checked_light.config.duplicate(true)
	_lighting = TimeOfDayLighting.snapshot(lighting_config)
	var loaded_field: Dictionary = FieldLoader.load_from(field_path)
	field_errors = loaded_field.errors
	if not loaded_field.ok:
		return
	field = loaded_field.field
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	var env: Environment = World.build(self, field, Callable(), {}, snapshot).environment

	_shadow = Shadow.create(self)
	show_aircraft(aircraft)
	var pos := _composition_position(AIRPLANE_NED)

	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = Spec.CAMERA.near
	camera.far = Spec.CAMERA.far
	add_child(camera)
	camera.position = _composition_position(CAMERA_NED)
	var to_airplane := pos - camera.position
	var azimuth := atan2(to_airplane.x, -to_airplane.z) - deg_to_rad(AIRPLANE_RIGHT_DEG) # render: x east, -z north
	var elevation := deg_to_rad(CAMERA_PITCH_DEG)
	var look := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	camera.look_at_from_position(camera.position, camera.position + look, Vector3.UP)
	camera.current = true

	World.update(env, CLOCK, Vector3.ZERO, _composition_position(AIRPLANE_NED), camera) # FW-23: the eye adapts to the view


func _composition_position(offset_ned: Array) -> Vector3:
	return Frames.ned_to_render([
		float(field.pilot.north) + float(offset_ned[0]),
		float(field.pilot.east) + float(offset_ned[1]),
		float(field.pilot.down) - float(field.pilot.eye_height) + float(offset_ned[2]),
	])


func _ready() -> void:
	if not field_errors.is_empty():
		FieldError.report(self, field_errors)


## Builds `id` in the composition's pose (and its shadow), replacing the selected model.
func show_aircraft(id: String) -> void:
	var built := AirplaneBuilder.build(id)
	if built.is_empty():
		return
	if not airplane.is_empty():
		remove_child(airplane.root)
		airplane.root.queue_free()
	airplane = built
	add_child(airplane.root)
	var rotorcraft: bool = Catalog.is_rotorcraft(id)
	var attitude: Dictionary = HELICOPTER_ATTITUDE_DEG if rotorcraft else ATTITUDE_DEG
	var basis := Frames.attitude_to_render(deg_to_rad(attitude.yaw), deg_to_rad(attitude.pitch), deg_to_rad(attitude.roll))
	var pos := _composition_position(AIRPLANE_NED)
	var model_cg: Vector3 = airplane.get("cg_model_m", Vector3.ZERO) if rotorcraft else Vector3.ZERO
	airplane.root.transform = Frames.root_transform(basis, pos, model_cg)
	if rotorcraft:
		var main_pivot: Node3D = airplane.get("main_rotor_pivot") as Node3D
		if main_pivot != null:
			main_pivot.rotation.z = PROP_ANGLE
	else:
		airplane.propeller.rotation.z = PROP_ANGLE
	var extent := Shadow.model_extent(airplane.root)
	Shadow.bind_model(_shadow, airplane.root)
	World.dress_aircraft(airplane.root)
	var snapshot_lighting: bool = lighting_config.get("mode", "legacy") != "legacy"
	var strength: float = Atmosphere.shadow_strength(_lighting) if snapshot_lighting else 1.0
	_shadow.visible = strength > 0.0
	var direction: Vector3 = Atmosphere.sun_direction(_lighting) if snapshot_lighting else Atmosphere.shadow_direction()
	Shadow.update(_shadow, basis, pos, extent.x, extent.y, direction, strength)
