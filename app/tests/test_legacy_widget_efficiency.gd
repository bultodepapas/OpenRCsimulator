extends SceneTree

const RadioWidget := preload("res://render/overlays/transmitter.gd")
const BatteryWidget := preload("res://render/overlays/battery_panel.gd")
const WindWidget := preload("res://render/overlays/wind.gd")
const Sensors := preload("res://render/overlays/battery_sensors.gd")

var checks := 0
var failures := 0
var draws := [0, 0, 0, 0, 0]

func _initialize() -> void:
	await process_frame
	root.size = Vector2i(1920, 1080)
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	var radio := RadioWidget.new()
	var battery := BatteryWidget.new()
	var wind := WindWidget.new()
	stage.add_child(radio)
	stage.add_child(battery)
	stage.add_child(wind)
	battery.position = Vector2(400, 40)
	wind.position = Vector2(850, 40)
	battery.set_detailed(true)
	for canvas: Control in [radio.gimbals, battery.bar, battery.spark_v, battery.spark_a, wind.dial]:
		canvas.draw.connect(_count_draw.bind([radio.gimbals, battery.bar, battery.spark_v, battery.spark_a, wind.dial].find(canvas)))
	var sticks := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.5}
	var trims := {roll = 0.0, pitch = 0.0, yaw = 0.0}
	var sample := Sensors.empty()
	sample.merge({valid = true, series = 4, parallel = 1, chemistry = "lipo", capacity_mah = 3200.0,
		pack_voltage_v = 15.2, current_a = 20.0, power_w = 304.0, remaining_pct = 80.0,
		temperature_c = 27.0, history_v = PackedFloat64Array([15.3, 15.2]), history_a = PackedFloat64Array([18.0, 20.0])}, true)
	var weather := {wind_speed = 4.0, wind_up = 0.0, wind_from_deg = 90.0}
	radio.refresh(sticks, trims, 2)
	battery.refresh(sample, "metric")
	wind.refresh(weather, 0.0, "metric")
	await _settle()
	_check("all draw counters have a positive control", draws.all(func(n: int) -> bool: return n > 0))
	var before := draws.duplicate()
	for i in 30:
		radio.refresh(sticks, trims, 2)
		battery.refresh(sample.duplicate(true), "metric")
		wind.refresh(weather, 0.0, "metric")
		await _settle()
	var repeated := []
	for i in draws.size(): repeated.append(draws[i] - before[i])
	print("30 identical refreshes: transmitter/bar/voltage/current/wind redraws=", repeated)
	_check("30 unchanged snapshots do not redraw any legacy graphic", repeated == [0, 0, 0, 0, 0])
	before = draws.duplicate()
	sticks.roll = 0.4
	radio.refresh(sticks, trims, 2)
	await _settle()
	_check("changed stick redraws immediately", draws[0] == before[0] + 1 and is_equal_approx(radio._layout[1].x, 0.4))
	before = draws.duplicate()
	trims.yaw = 0.2
	radio.refresh(sticks, trims, 1)
	await _settle()
	_check("mode and trim changes invalidate radio", draws[0] == before[0] + 1 and radio.mode == 1 and radio._trims[0].x > 0.0)
	before = draws.duplicate()
	radio.set_radio_model("radiolink_t16d")
	await _settle()
	_check("model change invalidates radio", draws[0] > before[0])
	before = draws.duplicate()
	sample.temperature_c = 30.0
	battery.refresh(sample, "metric")
	weather.wind_speed = 5.0
	wind.refresh(weather, 0.0, "metric")
	await _settle()
	_check("text-only changes preserve cached graphics", draws == before and battery.values.temperature.text == "30 °C")
	before = draws.duplicate()
	sample.remaining_pct = 70.0
	sample.history_v.append(15.1)
	battery.refresh(sample, "metric")
	wind.refresh(weather, 30.0, "metric")
	await _settle()
	_check("changed charge and voltage invalidate only relevant battery graphics", draws[1] == before[1] + 1 and draws[2] == before[2] + 1 and draws[3] == before[3])
	_check("camera-relative wind arrow refreshes with view heading", draws[4] == before[4] + 1)
	before = draws.duplicate()
	sample.alarms = ["cell_critical"]
	battery.refresh(sample, "metric")
	await _settle()
	_check("alarm-only changes redraw charge color", draws[1] == before[1] + 1 and draws[2] == before[2] and draws[3] == before[3])
	before = draws.duplicate()
	battery.refresh(sample, "imperial")
	await _settle()
	_check("unit change updates labels without redrawing history", battery.values.temperature.text == "86 °F" and draws == before)
	sample.history_a = PackedFloat64Array([NAN, 20.0, NAN])
	battery.refresh(sample, "metric")
	await _settle()
	before = draws.duplicate()
	battery.refresh(sample.duplicate(true), "metric")
	wind.refresh({}, 0.0, "metric")
	await _settle()
	_check("unknown history samples do not cause perpetual redraw", draws[3] == before[3])
	before = draws.duplicate()
	wind.refresh({}, 0.0, "metric")
	await _settle()
	_check("repeated missing wind remains cached", draws[4] == before[4])
	battery.set_detailed(false)
	await _settle()
	before = draws.duplicate()
	sample.history_v.append(14.8)
	sample.current_a = 24.0
	battery.refresh(sample, "metric")
	await _settle()
	_check("compact battery keeps hidden graphs idle", draws[1] == before[1] and draws[2] == before[2] and draws[3] == before[3])
	battery.set_detailed(true)
	battery.refresh(sample, "metric")
	await _settle()
	_check("detail reopening shows latest values and history", battery.values.current.text == "24.0 A" and battery.reading.history_v[-1] == 14.8 and draws[2] > before[2])
	stage.queue_free()
	await process_frame
	print("legacy widget efficiency checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _count_draw(index: int) -> void:
	draws[index] += 1

func _settle() -> void:
	await process_frame
	RenderingServer.force_draw(false)

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
