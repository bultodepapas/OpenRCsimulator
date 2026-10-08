extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const Driver = preload("res://tests/landing_test_driver.gd")
var failures: int = 0
var checks: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	var old_hz: int = Engine.physics_ticks_per_second
	var loaded: Dictionary = Field.load_from()
	check("default field loads", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var field: Dictionary = loaded.field
	var geometry_state: PackedFloat64Array = RB.make_state(M.v3(10.0, 20.0, -1.0), M.v3(0.0, 0.0, 0.4),
		M.q_from_euler(PI / 2.0, 0.0, 0.0), M.v3(2.0, 0.0, 0.0))
	var point: PackedFloat64Array = Driver.contact_state(geometry_state, M.v3(0.5, 0.3, 0.2))
	check("wheel velocity includes rotation, position uses the world frame", absf(point[0]-9.7) < 1e-12
		and absf(point[1]-20.5) < 1e-12 and absf(point[2]+0.8) < 1e-12 and absf(point[5]-1.0) < 1e-12)
	var results: Array = []
	var quick: bool = OS.get_cmdline_user_args().has("--quick")
	for hz: int in ([240] if quick else [240, 480]):
		Engine.physics_ticks_per_second = hz
		for eastbound: bool in ([true] if quick else [true, false]):
			var session: Node = Session.new()
			session.setup()
			root.add_child(session)
			var result: Dictionary = Driver.fly(session, field, eastbound)
			if result.has("contacts"):
				results.append(result)
			session.free()
			var label: String = "%d Hz %s" % [hz, "east" if eastbound else "west"]
			check(label + " completes without crash/fault", result.get("completed", false), result.get("error", ""))
			if not result.has("contacts"):
				continue
			var wheels: Dictionary = {}
			for event: Dictionary in result.contacts:
				wheels[event.wheel] = true
			check(label + " touches down below 1 m/s at every wheel/recontact", wheels.size() == 3 and result.max_contact_sink_mps <= 1.0, str(result.max_contact_sink_mps))
			check(label + " all wheels stay on runway with 0.5 m margin", result.min_runway_margin_m >= Driver.EDGE_MARGIN, str(result.min_runway_margin_m))
			check(label + " stops and holds at idle for >=2 s", result.stop_time_s > 0.0 and result.dwell_s >= Driver.STOP_DWELL and not result.stopped_then_moved and result.max_stop_drift_m < 0.002
				and result.engine_running and result.final_throttle == 0.0 and absf(result.final_rpm-result.idle_rpm) < 1e-6, str(result.stop_time_s))
			check(label + " baseline wash remains off", not result.wash_enabled)
			print("landing: ", JSON.stringify({hz=hz, eastbound=eastbound, touchdown_time_s=result.touchdown_time_s,
				touchdown_east_m=result.touchdown_east_m, sink_mps=result.max_contact_sink_mps,
				stop_east_m=result.stop_east_m, stop_time_s=result.stop_time_s,
				compression_m=result.max_compression_m, margin_m=result.min_runway_margin_m}))
	check("all requested flights produce results", results.size() == (1 if quick else 4))
	if results.size() == 4:
		for i: int in 2:
			var a: Dictionary = results[i]
			var b: Dictionary = results[i+2]
			check("refinement touchdown <=0.25 m, sink <=0.05 m/s", absf(a.touchdown_east_m-b.touchdown_east_m) <= 0.25 and absf(a.max_contact_sink_mps-b.max_contact_sink_mps) <= 0.05)
			check("refinement stop <=0.5 m / 0.5 s, compression <=5 mm", absf(a.stop_east_m-b.stop_east_m) <= 0.5 and absf(a.stop_time_s-b.stop_time_s) <= 0.5 and absf(a.max_compression_m-b.max_compression_m) <= 0.005)
	Engine.physics_ticks_per_second = 240
	var unsafe_session: Node = Session.new()
	unsafe_session.setup()
	root.add_child(unsafe_session)
	var unsafe: Dictionary = Driver.fly(unsafe_session, field, true, 0.0, 0.0, 0.0, 0.1, 0.05)
	check("real session rejects an initial hull/gear penetration before advancing", not unsafe.completed
		and not unsafe_session.crash.is_empty() and unsafe_session.sim.tick == 0)
	unsafe_session.free()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file == null:
				check("report writes", false)
			else:
				file.store_string(JSON.stringify(results, "\t") + "\n")
	Engine.physics_ticks_per_second = old_hz
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
