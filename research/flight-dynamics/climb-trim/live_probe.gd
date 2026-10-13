extends SceneTree
const Weather = preload("res://physics/wind_config.gd")
const RB = preload("res://physics/rigid_body.gd")
const M = preload("res://physics/math3d.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	for id in ["turbo-lumber-evolution", "jensen-das-ugly-stik-60"]:
		var main = load("res://main.tscn").instantiate()
		main.aircraft_id = id
		main.weather_config = Weather.GENTLE_PRACTICE.duplicate(true)
		root.add_child(main)
		await process_frame
		var s = main.session
		s.reset()
		s.commands.throttle = 0.25
		main.recorder.start(s.trace_meta())
		while s.sim.tick < 2400 and not s.sim.paused:
			await physics_frame
			if s.sim.tick % 240 == 0:
				print("LIVE ",id," t=",s.sim.time()," h=",-s.sim.state[2]," raw=",s.raw," cmd=",s.sim.inputs)
		main.recorder.stop()
		print("RESULT ",id," h=",-s.sim.state[2]," tick=",s.sim.tick," raw=",s.raw," record=",main.recorder.note)
		main.free()
		await process_frame
	quit()
