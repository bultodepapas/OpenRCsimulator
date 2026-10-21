extends SceneTree
## Smoke timing host: the production flight activity with input disabled and no
## shell focus holds. Main's bounded monotonic sampler owns timing and reporting.
## Run paired --smoke=off/on with identical --frametimes/--warmup/--t options.

var flight: Node
var output_path := ""
var observed_frames := 0
var emitting_frames := 0
var peak_capacity := 0
var unattended_resumes := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var has_output := false
	for arg: String in args:
		if arg.begins_with("--frametimes="):
			has_output = true
			output_path = arg.trim_prefix("--frametimes=")
	if not has_output:
		printerr("A fresh --frametimes=<absolute-path.json> is required.")
		quit(1)
		return
	flight = load("res://main.tscn").instantiate()
	flight.external_controller_selection = true
	flight.crash_effects_enabled = false
	flight.accident_reports_enabled = false
	flight.set_user_args(args)
	root.add_child(flight)
	if not flight.startup_error.is_empty() or flight.session == null:
		printerr("Timing flight unavailable: ", flight.startup_error)
		quit(1)
		return
	flight.session.input_enabled = false
	flight.set_process_input(false)
	flight.set_process_unhandled_input(false)
	flight.session.crash_auto_restart = false
	flight.session.reset()
	flight.session.sim.set_paused(false)
	flight._smoke_key_on = "--smoke-pump=on" in args
	flight.session.sim.paused_changed.connect(_benchmark_pause_changed)
	flight.tree_exiting.connect(_write_smoke_evidence)
	print("SMOKE_TIMING_READY: ", JSON.stringify(flight._smoke_evidence()))

func _benchmark_pause_changed(paused: bool) -> void:
	if paused:
		_resume_unattended.call_deferred()

func _resume_unattended() -> void:
	# Simulation intentionally pauses on application focus loss. This isolated,
	# input-free measurement host may resume that bare pause, never a guarded
	# pause, crash or fault. Production flight and its focus policy are unchanged.
	if not is_instance_valid(flight) or flight.session == null: return
	var session: Node = flight.session
	if session.sim.paused and session.sim.fault_reason.is_empty() \
			and session.pause_reason.is_empty() and session.holds.is_empty() \
			and session.crash.is_empty():
		unattended_resumes += 1
		session.sim.set_paused(false)

func _process(_delta: float) -> bool:
	if not is_instance_valid(flight) or flight.session == null: return false
	observed_frames += 1
	var smoke: Node = flight._profile_smoke
	if is_instance_valid(smoke):
		var active := false
		var capacity := 0
		for emitter: GPUParticles3D in smoke._emitters.values():
			active = active or emitter.emitting
			capacity += emitter.amount
		if active: emitting_frames += 1
		peak_capacity = maxi(peak_capacity, capacity)
	return false

func _write_smoke_evidence() -> void:
	var file := FileAccess.open(output_path + ".smoke.json", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"observed_frames_including_warmup": observed_frames,
		"emitting_frames": emitting_frames, "peak_capacity": peak_capacity,
		"unattended_focus_resumes": unattended_resumes,
		"smoke": flight._smoke_evidence(), "crash": not flight.session.crash.is_empty(),
		"pause_reason": flight.session.pause_reason, "holds": flight.session.holds,
		"harness_sha256": FileAccess.get_sha256(get_script().resource_path)}, "\t"))
