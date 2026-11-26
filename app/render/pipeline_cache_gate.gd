extends Node
## F3 (2026-11-26): keeps the RenderingDevice pipeline cache (Vulkan, Direct3D 12, Metal) from being re-serialized
## while a flight runs. Godot writes the whole cache each time it has grown by
## `rendering/rendering_device/pipeline_cache/save_chunk_size_mb` (3 MB by default). On a cold cache that was a
## 40–48 MB write with a 22 MB allocation and a 21–37 ms render stall every few seconds of a player's first flights
## (Windows, Forward+). The engine reads the setting at every check, so while a flight or the RC truck runs it is raised
## beyond any growth, and otherwise it keeps the project value: the deferred growth is written at the next pause,
## menu, loading screen or Home, or at exit. A crash in flight loses at most that flight's growth.

const SETTING := "rendering/rendering_device/pipeline_cache/save_chunk_size_mb"
const FLIGHT_CHUNK_MB := 1.0e6

var _idle_chunk_mb := 3.0
var _deferring := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_idle_chunk_mb = float(ProjectSettings.get_setting(SETTING, 3.0))


func _process(_delta: float) -> void:
	var defer := flight_running(get_tree())
	if defer != _deferring:
		_deferring = defer
		ProjectSettings.set_setting(SETTING, FLIGHT_CHUNK_MB if defer else _idle_chunk_mb)


func _exit_tree() -> void:
	if _deferring:
		_deferring = false
		ProjectSettings.set_setting(SETTING, _idle_chunk_mb)


## Whether an unpaused flight or RC truck is on screen: AppRoot owns them (`flight`, `ground_vehicle`). Loading screens,
## pause, menus over a paused tree and Home leave the cache writes as configured.
static func flight_running(tree: SceneTree) -> bool:
	if tree == null or tree.paused:
		return false
	var app := tree.root.get_node_or_null("AppRoot")
	if app == null or bool(app.get("_loading_active")):
		return false
	var flight: Variant = app.get("flight")
	var vehicle: Variant = app.get("ground_vehicle")
	return (is_instance_valid(flight) and flight is Node) or (is_instance_valid(vehicle) and vehicle is Node)
