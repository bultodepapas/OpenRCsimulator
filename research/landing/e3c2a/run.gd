# E3c2a: offline circuit verification. Invoke with --script using this file's absolute path.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
var failures: int = 0
var checks: int = 0


func check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	print(("ok " if passed else "FAIL ") + label + " " + detail)
	if not passed:
		failures += 1


func acceptance(r: Dictionary, label: String) -> void:
	check(label + " completes without crash/fault", r.get("completed", false) and not r.get("crash", true) and r.get("fault", "missing") == "", r.get("error", "missing"))
	if not r.has("contacts"):
		return
	check(label + " continuous normal flight ticks and bounded commands", r.continuity_ok and r.commands_finite_bounded)
	check(label + " begins parked and lifts off on the runway", r.idle_drift_m < 0.002 and r.liftoff_time_s > 1.0 and r.departure_margin_m >= 0.5, str(r.departure_margin_m))
	check(label + " actual circuit encloses area and completes a turn", absf(r.turn_rad) >= 5.8 and absf(r.turn_rad) <= 6.8 and absf(r.signed_area_m2) >= 15000.0 and r.max_cross_track_m >= 80.0, str([r.turn_rad, r.signed_area_m2, r.max_cross_track_m]))
	var wheels: Dictionary = {}
	for event: Dictionary in r.contacts:
		wheels[event.wheel] = true
	var phases: Array = []
	var approach: Dictionary = {}
	var high_legs: bool = true
	for event: Dictionary in r.phases:
		phases.append(event.phase)
		if event.phase == "approach":
			approach = event
		if event.phase in ["crosswind_turn", "downwind"]:
			high_legs = high_legs and event.altitude_m >= 10.0
	var required: Array = ["idle", "takeoff_roll", "initial_climb", "crosswind_turn", "crosswind", "downwind_turn", "downwind", "base_turn", "base", "final_turn", "final_join", "approach", "flare", "rollout"]
	check(label + " flies the ordered circuit phases above the ground", phases == required and high_legs, str(phases))
	var heading: float = PI / 2.0 if r.eastbound else -PI / 2.0
	# Field center is recorded by the driver; these are bounded test-entry limits.
	check(label + " enters the proven landing regime without a state reset", not approach.is_empty()
		and absf(approach.get("altitude_m", -100.0) - 6.0) <= 0.5
		and absf(approach.get("speed_mps", -100.0) - 12.0) <= 0.5
		and absf(approach.get("north_m", -1000.0) - r.runway_center_north) <= 1.0
		and absf(approach.get("east_m", -1000.0) - (r.runway_center_east - (144.0 if r.eastbound else -144.0))) <= 0.25
		and absf(wrapf(approach.get("yaw_rad", 100.0) - heading, -PI, PI)) <= deg_to_rad(3.0)
		and absf(approach.get("bank_rad", 100.0)) <= deg_to_rad(3.0)
		and absf(approach.get("sink_mps", 100.0)) <= 1.0, str(approach))
	check(label + " lands all wheels with sink <=1m/s", wheels.size() == 3 and r.touchdown_time_s > r.liftoff_time_s and r.max_contact_sink_mps <= 1.0, str(r.max_contact_sink_mps))
	check(label + " landing and rollout stay inside runway", r.touchdown_time_s > 0.0 and r.landing_margin_m >= 0.5, str(r.landing_margin_m))
	check(label + " stops and remains anchored at idle", r.stop_time_s > r.touchdown_time_s and r.stop_dwell_s >= 5.0 and not r.stopped_then_moved and r.max_stop_drift_m < 0.002 and r.engine_running and r.final_throttle == 0.0 and absf(r.final_rpm-r.idle_rpm) < 1e-6, str([r.stop_time_s, r.stop_east_m]))
	check(label + " wash-off baseline", not r.wash_enabled)
	if r.has("trace_saved"):
		check(label + " whole trace saved with every tick", r.trace_saved and r.trace_continuous and r.trace_rows == r.tick_count + 1)


func _initialize() -> void:
	var here: String = get_script().resource_path.get_base_dir()
	var driver: Script = load(here.path_join("circuit_driver.gd"))
	var pilot: Script = load(here.path_join("circuit_pilot.gd"))
	var field: Dictionary = Field.load_from()
	if not field.ok or driver == null or pilot == null:
		printerr("field or circuit scripts unavailable")
		quit(1)
		return
	var report_path: String = ""
	var trace_path: String = ""
	var quick: bool = false
	var west_only: bool = false
	var duration: float = 240.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
		elif arg.begins_with("--trace="):
			trace_path = arg.trim_prefix("--trace=")
		elif arg == "--quick":
			quick = true
		elif arg == "--west":
			quick = true
			west_only = true
		elif arg.begins_with("--duration="):
			duration = float(arg.trim_prefix("--duration="))
	if not is_finite(duration) or duration <= 0.0 or duration > 240.0:
		printerr("duration must be finite and in (0, 240] seconds")
		quit(2)
		return
	if not quick and trace_path.is_empty():
		printerr("full acceptance requires --trace=/absolute/path.csv; use --quick only for development")
		quit(2)
		return
	var old_hz: int = Engine.physics_ticks_per_second
	var results: Array = []
	var cases: Array = [[240, not west_only]] if quick else [[240, true], [240, false], [480, true]]
	for requested: Array in cases:
		Engine.physics_ticks_per_second = requested[0]
		var session: Node = Session.new()
		session.setup()
		root.add_child(session)
		var trace: String = trace_path if results.is_empty() else ""
		var result: Dictionary = driver.fly(session, field.field, pilot, requested[1], trace, duration)
		results.append(result)
		session.free()
		acceptance(result, "%dHz %s" % [requested[0], "east" if requested[1] else "west"])
		print("RESULT ", JSON.stringify({hz = requested[0], eastbound = requested[1], completed = result.get("completed", false), error = result.get("error", ""), phases = result.get("phases", [])}))
	if results.size() == 3 and results[0].has("contacts") and results[2].has("contacts"):
		var a: Dictionary = results[0]
		var b: Dictionary = results[2]
		check("refinement touchdown <=0.5m, sink <=0.05m/s", absf(a.touchdown_east_m-b.touchdown_east_m) <= 0.5 and absf(a.max_contact_sink_mps-b.max_contact_sink_mps) <= 0.05)
		check("refinement stop <=0.75m /1s and compression <=5mm", absf(a.stop_east_m-b.stop_east_m) <= 0.75 and absf(a.stop_time_s-b.stop_time_s) <= 1.0 and absf(a.max_compression_m-b.max_compression_m) <= 0.005)
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		check("report file opens", file != null)
		if file != null:
			file.store_string(JSON.stringify({format = "openrc-circuit-verification v1", coverage = "development" if quick else "full", checks = checks, failures = failures, results = results}, "\t") + "\n")
	Engine.physics_ticks_per_second = old_hz
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
