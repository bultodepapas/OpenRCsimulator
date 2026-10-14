## Run with the editor or exported runtime; res:// loads the corresponding packaged solver/data.
## The 500 us plan gate and 4166.67 us real-time ceiling remain separate from correctness.
extends SceneTree
const Session = preload("res://sim/ground_vehicle/session.gd")
const Kernel = preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const NEUTRAL := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false, "armed": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var report := measure()
	print(JSON.stringify(report, "\t", true, true))
	quit(1 if report.has("error") else 0)

static func measure() -> Dictionary:
	var results := []
	for record in [false, true]:
		var session := Session.new()
		if not session.prepare_default():
			var error := session.load_error
			session.free()
			return {"error": error}
		session.tick_once(NEUTRAL)
		session.resume()
		var durations := PackedFloat64Array()
		var controls := NEUTRAL.duplicate()
		controls.throttle = 0.4
		controls.steering = 0.12
		if record: session.start_recording()
		for i in 300:
			if i == 210:
				controls.throttle = 0.0
				controls.brake = 1.0
			var before := Time.get_ticks_usec()
			var ok := session.tick_once(controls)
			var elapsed := float(Time.get_ticks_usec() - before)
			if not ok:
				var error := session.fault_reason
				session.free()
				return {"error": error}
			if i >= 60: durations.append(elapsed)
		var mean := 0.0
		for value in durations: mean += value / float(durations.size())
		durations.sort()
		results.append({"recording": record, "samples": durations.size(), "mean_us": mean,
			"median_us": durations[120], "p95_us": durations[228], "maximum_us": durations[-1],
			"plan_500us_mean_gate": mean <= 500.0,
			"realtime_mean_gate": mean < 1000000.0 / 240.0,
			"realtime_p95_gate": durations[228] < 1000000.0 / 240.0,
			"identities": session.identities_snapshot()})
		session.free()
	return {"format": "openrc-rcv-cost", "engine": Engine.get_version_info().string,
		"debug_build": OS.is_debug_build(), "solver": Kernel.SOLVER_VERSION,
		"backend_identity": Kernel.backend_identity(),
		"processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"scope": "Session.tick_once, 60 warmup + 240 measured ticks; drive/steer then brake; no rendering",
		"results": results}
