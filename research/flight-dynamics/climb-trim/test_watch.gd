extends "watch.gd"
const Session = preload("res://sim/flight_session.gd")
func _launch() -> void:
	node_added.disconnect(_node_added)
	var baseline = Session.new()
	var observed = Session.new()
	for s in [baseline,observed]:
		s.setup("res://data/aircraft/turbo_lumber_evolution.json","turbo-lumber-evolution")
		root.add_child(s)
		s.set_physics_process(false)
		s.sim.set_physics_process(false)
		s.radio.connected = false
		s.read_raw = func() -> Dictionary: return {roll=0.0,pitch=0.0,yaw=0.0,throttle=0.0}
		s.commands.throttle = 0.25
	_attach(observed)
	for tick in 1400:
		for s in [baseline,observed]:
			s._physics_process(s.sim.dt())
			s.sim.step()
	assert(var_to_bytes(baseline.sim.checkpoint()) == var_to_bytes(observed.sim.checkpoint()))
	baseline.reset()
	observed.reset()
	for tick in 20:
		for s in [baseline,observed]:
			s._physics_process(s.sim.dt())
			s.sim.step()
	assert(var_to_bytes(baseline.sim.checkpoint()) == var_to_bytes(observed.sim.checkpoint()))
	observed.sim.paused = true
	_process(0.0)
	assert(not recorder.recording)
	assert(FileAccess.file_exists(output_dir.path_join("flight-003.csv")))
	assert(FileAccess.file_exists(output_dir.path_join("input-003.csv")))
	var samples := FileAccess.get_file_as_string(output_dir.path_join("telemetry-003.jsonl")).strip_edges().split("\n")
	assert(JSON.parse_string(samples[0]).kind == "metadata")
	var last_sample: Dictionary = JSON.parse_string(samples[-1])
	assert(int(last_sample.tick) == observed.sim.tick)
	for i in observed.sim.state.size():
		assert(abs(float(last_sample.state[i]) - observed.sim.state[i]) <= 1e-14 * max(1.0, abs(observed.sim.state[i])))
	baseline.free()
	observed.free()
	print("CLIMB_OBSERVER_PASS: exact physics checkpoint parity, segmentation, reset, detach")
	quit()

