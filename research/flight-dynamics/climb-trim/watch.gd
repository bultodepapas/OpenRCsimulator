# Read-only flight observer for a user reproduction in the real native application.
# Separate recorder: the normal T key and the player's controls remain available.
extends SceneTree
const Recorder = preload("res://sim/recorder.gd")
var app: Node
var session: Node
var recorder: RefCounted
var raw_file: FileAccess
var output_dir: String
var part := 0
var started_tick := 0

func _initialize() -> void:
	output_dir = ProjectSettings.globalize_path("res://../.tools/climb-observed/") + Time.get_datetime_string_from_system(true).replace(":", "-") + "-" + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(output_dir)
	print("CLIMB_DIAGNOSTIC ", output_dir)
	node_added.connect(_node_added)
	call_deferred("_launch")

func _launch() -> void:
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	root.add_child(app)

func _node_added(node: Node) -> void:
	var script: Script = node.get_script()
	if script != null and script.resource_path == "res://sim/flight_session.gd":
		_attach.call_deferred(node)

func _attach(node: Node) -> void:
	if not is_instance_valid(node): return
	_finish()
	session = node
	recorder = Recorder.new(session.sim, session.electrical_state if session.has_method("electrical_state") else Callable())
	session.resetting.connect(_finish)
	session.tree_exiting.connect(_detach)
	session.sim.stepped.connect(_sample)
	_begin()

func _begin() -> void:
	if not is_instance_valid(session) or not session.is_flyable(): return
	part += 1
	started_tick = session.sim.tick
	recorder.start(session.trace_meta())
	raw_file = FileAccess.open(output_dir.path_join("input-%03d.csv" % part), FileAccess.WRITE)
	raw_file.store_line("tick,time_s,raw_roll,raw_pitch,raw_yaw,raw_throttle,stick_pitch,trim_pitch,radio_connected")

func _sample(tick: int, time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if not recorder.recording: _begin()
	if raw_file != null:
		raw_file.store_line("%d,%.9f,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f,%s" % [tick,time,
			session.raw.roll,session.raw.pitch,session.raw.yaw,session.raw.throttle,session.commands.pitch,session.trims.pitch,session.radio.connected])
	if tick - started_tick >= 1200:
		_finish() # save every five simulated seconds, so an abrupt close loses at most one segment

func _finish() -> void:
	if recorder != null and recorder.recording:
		recorder.stop(output_dir.path_join("flight-%03d.csv" % part))
	if raw_file != null:
		raw_file.close()
		raw_file = null

func _detach() -> void:
	_finish()
	if recorder != null: recorder.detach()
	recorder = null
	session = null

func _finalize() -> void:
	_finish()
