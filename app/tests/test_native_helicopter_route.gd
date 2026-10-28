## NK-3 production helicopter activity backend selection.
extends SceneTree

const FlightMain := preload("res://helicopter_main.gd")
const NativeStage := preload("res://sim/native_stage.gd")

var checks := 0
var failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_run.call_deferred()


func _activity(args: PackedStringArray, requested: String) -> void:
	var flight: Node = FlightMain.new()
	flight.interactive_start = true
	flight.set_user_args(args)
	root.add_child(flight)
	var session: Node = flight.session
	_check(requested + " activity starts", flight.startup_error.is_empty() and session != null,
		flight.startup_error)
	if session != null:
		var status: Dictionary = session.stage_backend_status()
		_check(requested + " request reaches the session", status.requested == requested, str(status))
		if requested == NativeStage.BACKEND_REFERENCE:
			_check("explicit reference is owned", status.identity == NativeStage.reference_identity() \
				and status.reason.is_empty() and session.is_flyable(), str(status))
		elif NativeStage.library_status().ok:
			_check("verified native stage is owned", status.identity.get("backend") == NativeStage.BACKEND_NATIVE \
				and session._native_stage != null and session._native_stage.owns_stage(session) \
				and session.is_flyable(), str(status))
		else:
			_check("unavailable native stage has explicit fallback", status.identity == NativeStage.reference_identity() \
				and not status.reason.is_empty() and session.is_flyable(), str(status))
	root.remove_child(flight)
	flight.free()


func _root_activity(args: PackedStringArray, requested: String) -> void:
	var app: Node = load("res://app_root.tscn").instantiate()
	var actual_args := PackedStringArray(["--aircraft=xcell-60-research", "--soundscape=off"])
	actual_args.append_array(args)
	app.user_args = actual_args
	root.add_child(app)
	await process_frame
	var flight: Node = app.flight
	var session: Node = flight.session if flight != null else null
	_check("app root forwards " + requested + " to the helicopter activity", flight != null \
		and flight.get_script() == FlightMain and flight.startup_error.is_empty() and session != null \
		and session.stage_backend_status().requested == requested)
	if session != null:
		var status: Dictionary = session.stage_backend_status()
		var expected := NativeStage.BACKEND_NATIVE if requested == NativeStage.BACKEND_NATIVE \
			and NativeStage.library_status().ok else NativeStage.BACKEND_REFERENCE
		_check("app root reports the actual " + requested + " backend", status.identity.backend == expected \
			and session.is_flyable(), str(status))
	app.queue_free()
	await process_frame


func _run() -> void:
	var invalid: Node = FlightMain.new()
	invalid.interactive_start = true
	invalid.set_user_args(PackedStringArray(["--physics-backend=future"]))
	root.add_child(invalid)
	_check("unknown backend rejected before setup", invalid.session == null and invalid.get_child_count() == 0 \
		and "--physics-backend" in invalid.startup_error, invalid.startup_error)
	root.remove_child(invalid)
	invalid.free()
	_activity(PackedStringArray(["--soundscape=off"]), NativeStage.BACKEND_NATIVE)
	_activity(PackedStringArray(["--physics-backend=native", "--soundscape=off"]), NativeStage.BACKEND_NATIVE)
	_activity(PackedStringArray(["--physics-backend=gdscript_reference", "--soundscape=off"]), NativeStage.BACKEND_REFERENCE)
	await _root_activity(PackedStringArray(), NativeStage.BACKEND_NATIVE)
	await _root_activity(PackedStringArray(["--physics-backend=gdscript_reference"]), NativeStage.BACKEND_REFERENCE)
	print("NK-3 helicopter activity backend: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
