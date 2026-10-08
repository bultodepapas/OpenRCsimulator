# E3c1a held-out entry variations and a real runway-overrun negative control.
extends SceneTree
const Session = preload("res://sim/flight_session.gd")
const Field = preload("res://data/field_loader.gd")
const Driver = preload("res://tests/landing_test_driver.gd")
var failures: int = 0
var checks: int = 0
func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	print(("ok   " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	var loaded: Dictionary = Field.load_from()
	check("default field loads", loaded.ok)
	if not loaded.ok:
		quit(1)
		return
	var results: Array = []
	for variant: int in 3:
		var session: Node = Session.new()
		session.setup()
		root.add_child(session)
		var result: Dictionary = Driver.fly(session, loaded.field, variant != 1,
			[1.0, -1.0, 0.0][variant], deg_to_rad([2.0, -2.0, 0.0][variant]), 15.0 if variant == 2 else 0.0)
		session.free()
		results.append(result)
		check("variant %d completes without crash/fault" % variant, result.get("completed", false), result.get("error", ""))
		if not result.has("contacts"):
			continue
		if variant == 2:
			check("late approach is rejected: leaves runway despite eventually stopping", result.min_runway_margin_m < 0.0 and result.stop_time_s > 0.0,
				"margin %.3f m, stop east %.3f m" % [result.min_runway_margin_m, result.stop_east_m])
		else:
			check("offset/bank entry has safe wheel contact and containment", result.contacts.size() >= 3 and result.max_contact_sink_mps <= 1.0
				and result.min_runway_margin_m >= Driver.EDGE_MARGIN, "sink %.3f, margin %.3f" % [result.max_contact_sink_mps, result.min_runway_margin_m])
			check("offset/bank entry stops and holds with engine idling", result.stop_time_s > 0.0 and result.dwell_s >= Driver.STOP_DWELL
				and not result.stopped_then_moved and result.max_stop_drift_m < 0.002 and result.engine_running
				and result.final_throttle == 0.0 and absf(result.final_rpm-result.idle_rpm) < 1e-6)
		print("landing variation: ", JSON.stringify({variant=variant, touchdown_east_m=result.touchdown_east_m,
			sink_mps=result.max_contact_sink_mps, stop_east_m=result.stop_east_m, margin_m=result.min_runway_margin_m}))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			if file == null:
				check("report writes", false)
			else:
				file.store_string(JSON.stringify(results, "\t") + "\n")
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
