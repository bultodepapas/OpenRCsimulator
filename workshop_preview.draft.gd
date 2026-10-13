extends SubViewportContainer

const AirplaneBuilder := preload("res://render/airplane.gd")

const BACKGROUND := Color("#263a40")
const AMBIENT := Color("#c5d3cb")

var _viewport: SubViewport
var _stage: Node3D
var _rig: Node3D
var _camera: Camera3D
var _airplane_root: Node3D
var _requested_id := ""
var _requested_scale := 1.0


func _init() -> void:
	name = "WorkshopPreview"
	custom_minimum_size = Vector2(380, 250)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.name = "StillPreviewViewport"
	_viewport.size = Vector2i(720, 420)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_build_world()


func _ready() -> void:
	if _requested_id != "":
		set_aircraft(_requested_id, _requested_scale)


## The model is a still render in its own World3D. This node has no flight state or input processing.
func set_aircraft(id: String, scale: float = 1.0) -> void:
	_requested_id = id
	_requested_scale = clampf(scale, 0.5, 2.0)
	if not is_instance_valid(_rig):
		return
	if is_instance_valid(_airplane_root):
		_rig.remove_child(_airplane_root)
		_airplane_root.queue_free()
		_airplane_root = null
	var built: Dictionary = AirplaneBuilder.build(id)
	if built.is_empty():
		return
	_airplane_root = built.get("root") as Node3D
	if not is_instance_valid(_airplane_root):
		_airplane_root = null
		return
	var datum: Vector2 = AirplaneBuilder.datum(id)
	_airplane_root.scale = Vector3.ONE * _requested_scale
	# Pivot at the builder's aerodynamic datum so the still camera keeps the same framing across airframes.
	_airplane_root.position = Vector3(0.0, -datum.y, -datum.x) * _requested_scale
	_rig.add_child(_airplane_root)


func _build_world() -> void:
	_stage = Node3D.new()
	_stage.name = "StillStage"
	_viewport.add_child(_stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_viewport.world_3d.environment = environment

	_rig = Node3D.new()
	_rig.name = "AircraftDatumPivot"
	_rig.rotation_degrees = Vector3(-4.0, -30.0, 0.0)
	_stage.add_child(_rig)

	var key_light := DirectionalLight3D.new()
	key_light.name = "PreviewKeyLight"
	key_light.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = false
	_stage.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "PreviewFillLight"
	fill_light.rotation_degrees = Vector3(18.0, 150.0, 0.0)
	fill_light.light_energy = 0.45
	fill_light.shadow_enabled = false
	_stage.add_child(fill_light)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 38.0
	_camera.near = 0.1
	_camera.far = 100.0
	_camera.position = Vector3(7.8, 4.6, 10.8)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.current = true
	_stage.add_child(_camera)
