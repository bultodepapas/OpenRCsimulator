# O1 Flight data (HUD-04): the pilot's numbers in the chosen units.
extends "res://render/overlays/overlay_frame.gd"

const Units := preload("res://render/overlays/units.gd")

var values: Dictionary
var _fuel_name: Label


func _init() -> void:
	super("flight", tr("Flight data"))
	values = add_rows([
		["airspeed", tr("Airspeed")],
		["ground_speed", tr("Ground speed")],
		["height", tr("Height")],
		["vertical_speed", tr("Vertical speed")],
		["throttle", tr("Throttle")],
		["distance", tr("Distance")],
		["time", tr("Elapsed simulation time")],
		["fuel", tr("Fuel")],
	])
	_fuel_name = values.fuel.get_parent().get_child(values.fuel.get_index() - 1) as Label
	_set_fuel_visible(false)


## t: Telemetry.compute() output, or {} when there is no flight to describe. system: a resolved unit system.
## mass_sample: one accepted FlightSession.mass_properties() result; finite fuel carries its volume and reserve.
func refresh(t: Dictionary, system: String, mass_sample: Dictionary = {}) -> void:
	if t.is_empty():
		for key in values:
			values[key].text = "–"
		_set_fuel_visible(false)
		return
	values.airspeed.text = Units.format(Units.speed(t.airspeed, system))
	values.ground_speed.text = Units.format(Units.speed(t.ground_speed, system))
	values.height.text = Units.format(Units.length(t.height_agl, system))
	values.vertical_speed.text = Units.format(Units.vertical(t.vertical_speed, system), true)
	values.throttle.text = "%d %%" % roundi(t.throttle * 100.0)
	values.distance.text = Units.format(Units.length(t.distance_pilot, system))
	values.time.text = clock(t.time_s)
	_set_fuel(mass_sample)


func _set_fuel(mass_sample: Dictionary) -> void:
	var amount: float = float(mass_sample.get("volume_ml", NAN))
	var fraction: float = float(mass_sample.get("fill_fraction", NAN))
	if not mass_sample.get("ok", false) or not mass_sample.get("finite_fuel", false) \
			or not is_finite(amount) or amount < 0.0 or not is_finite(fraction) or fraction < 0.0 or fraction > 1.0:
		_set_fuel_visible(false)
		values.fuel.text = "–"
		return
	_set_fuel_visible(true)
	values.fuel.text = tr("%d mL · %d %%") % [roundi(amount), roundi(fraction * 100.0)]
	var reserve_fraction: float = float(mass_sample.get("reserve_fraction", NAN))
	var basis := str(mass_sample.get("reserve_basis", "estimated reserve"))
	if is_finite(reserve_fraction) and reserve_fraction >= 0.0 and reserve_fraction <= 1.0:
		_fuel_name.tooltip_text = tr("Reserve: %d%% (%s)") % [roundi(reserve_fraction * 100.0), tr(basis)]
	else:
		_fuel_name.tooltip_text = ""


func _set_fuel_visible(visible: bool) -> void:
	if _fuel_name != null:
		_fuel_name.visible = visible
	if values.has("fuel"):
		values.fuel.visible = visible


## m:ss, or h:mm:ss after an hour.
static func clock(seconds: float) -> String:
	var s := maxi(0, floori(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
