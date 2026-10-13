# O1 Flight data (HUD-04): the pilot's numbers in the chosen units.
extends "res://render/overlays/overlay_frame.gd"

const Units := preload("res://render/overlays/units.gd")

var values: Dictionary


func _init() -> void:
	super("flight", tr("Flight data"))
	values = add_rows([
		["airspeed", tr("Airspeed")],
		["ground_speed", tr("Ground speed")],
		["height", tr("Height")],
		["vertical_speed", tr("Vertical speed")],
		["throttle", tr("Throttle")],
		["distance", tr("Distance")],
		["time", tr("Flight time")],
	])


## t: Telemetry.compute() output, or {} when there is no flight to describe. system: a resolved unit system.
func refresh(t: Dictionary, system: String) -> void:
	if t.is_empty():
		for key in values:
			values[key].text = "–"
		return
	values.airspeed.text = Units.format(Units.speed(t.airspeed, system))
	values.ground_speed.text = Units.format(Units.speed(t.ground_speed, system))
	values.height.text = Units.format(Units.length(t.height_agl, system))
	values.vertical_speed.text = Units.format(Units.vertical(t.vertical_speed, system), true)
	values.throttle.text = "%d %%" % roundi(t.throttle * 100.0)
	values.distance.text = Units.format(Units.length(t.distance_pilot, system))
	values.time.text = clock(t.time_s)


## m:ss, or h:mm:ss after an hour.
static func clock(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
