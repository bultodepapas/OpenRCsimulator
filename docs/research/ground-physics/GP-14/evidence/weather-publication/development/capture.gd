extends SceneTree
const Flight := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-weather-publication/flight_session.before.gd")
const Weather := preload("res://physics/wind_config.gd")
const Field := preload("res://data/field_loader.gd")
var failed := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Engine.physics_ticks_per_second = 240
	var results := {}
	for name: String in ["calm", "gusty", "turbulent", "cool-dense"]:
		var f := Flight.new()
		f.input_enabled = false
		f.crash_auto_restart = false
		f.setup()
		if not f.set_field(Field.load_from().field): failed += 1
		var config := Weather.defaults() if name == "calm" else Weather.preset(name)
		if not f.setup_weather(config): failed += 1
		f.reset()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		for i: int in 25:
			var checkpoint: Dictionary = f.checkpoint()
			if checkpoint.is_empty(): failed += 1
			hash.update(var_to_bytes(checkpoint))
			if i < 24: f.sim.step()
		results[name] = hash.finish().hex_encode()
		f.free()
	var file := FileAccess.open("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-weather-publication/baseline.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")); file.close()
	print("Weather baseline: 108 checks, %d failed" % failed)
	quit(1 if failed else 0)
