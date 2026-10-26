## Dated diagnostic of an existing admission/runtime endpoint mismatch; not a shipped test.
extends SceneTree
const Config := preload("res://physics/wind_spatial_config.gd")
func _initialize() -> void:
	var raw := Config.defaults()
	var start := 63869.150306074676
	var duration := 32.88826421165945
	var boundary := start + duration
	for i in 5:
		raw.gusts.events.append({"id": "edge_%d" % i, "start_s": boundary if i == 4 else start,
			"duration_s": 0.1 if i == 4 else (duration if i == 0 else 40.0), "amplitude_ned_mps": [0.5, 0.0, 0.0]})
	var checked := Config.resolve(raw)
	var active := 0
	for event: Dictionary in raw.gusts.events:
		var elapsed := boundary - float(event.start_s)
		if elapsed >= 0.0 and elapsed < float(event.duration_s):
			active += 1
	print(JSON.stringify({"admitted": checked.ok, "runtime_active": active, "start": start,
		"duration": duration, "boundary": boundary, "elapsed": boundary - start}, "", true, true))
	quit(0 if checked.ok and active == 5 else 1)
