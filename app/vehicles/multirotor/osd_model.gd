## DR-31b: FPV quad OSD model (Betaflight/INAV-style elements). Pure, presentation-side derivations from the drawn
## state and the session telemetry: attitude angles, heading, climb rate, home vector (home = where the quad was last
## armed, as a flight controller sets it), unit formatting, OSD layouts and the post-flight statistics. Nothing here
## writes simulation state, and nothing is invented: an element whose source is absent is simply not shown.
extends RefCounted

const FC = preload("res://physics/multirotor/flight_controller.gd")
const Cam = preload("res://vehicles/multirotor/multirotor_camera.gd")

## Element ids. Warnings, hints, the arm state, race lines and messages are always shown (they are not layout).
const ELEMENTS: Array[String] = ["crosshair", "horizon", "sidebars", "ladder", "compass", "altitude", "vario",
	"speed", "home", "battery", "battery_detail", "power", "throttle", "motors", "sticks", "angles", "timer", "mode",
	"stats"]
## Layouts, like a flight controller's OSD profiles: a pilot cycles them in flight (O) or in the pause menu.
const LAYOUTS: Array[String] = ["off", "race", "freestyle", "full"]
const LAYOUT_NAMES := {"off": "Off", "race": "Race", "freestyle": "Freestyle", "full": "Full"}
const LAYOUT_ELEMENTS := {
	"off": [],
	"race": ["crosshair", "mode", "timer", "battery", "throttle", "stats"],
	"freestyle": ["crosshair", "horizon", "sidebars", "compass", "altitude", "vario", "speed", "home", "battery",
		"battery_detail", "throttle", "timer", "mode", "stats"],
	"full": ELEMENTS,
}
const UNITS: Array[String] = ["metric", "imperial"]
const UNIT_NAMES := {"metric": "Metric", "imperial": "Imperial"}
const DEFAULTS := {"layout": "freestyle", "units": "metric"}
const SECTION := "osd"
const M_TO_FT := 3.28084
const MPS_TO_KMH := 3.6
const MPS_TO_MPH := 2.236936
## A flight shorter than this (armed seconds) leaves no statistics screen (an arm-disarm on the pad is not a flight).
const STATS_MIN_FLIGHT_S := 1.0
## Efficiency (mAh/km) is listed only after this much horizontal path (m): shorter hops give meaningless figures.
const EFFICIENCY_MIN_M := 200.0


## Validated {layout, units}; anything unknown falls back to the default.
static func sanitize(config: Variant) -> Dictionary:
	var out := DEFAULTS.duplicate()
	if typeof(config) != TYPE_DICTIONARY:
		return out
	var layout: Variant = (config as Dictionary).get("layout")
	if typeof(layout) == TYPE_STRING and layout in LAYOUTS:
		out.layout = layout
	var units: Variant = (config as Dictionary).get("units")
	if typeof(units) == TYPE_STRING and units in UNITS:
		out.units = units
	return out


## The saved OSD configuration at `path` ("" = none: automation and tests never read a player file).
static func load_config(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return DEFAULTS.duplicate()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return DEFAULTS.duplicate()
	return sanitize({layout = file.get_value(SECTION, "layout", DEFAULTS.layout),
		units = file.get_value(SECTION, "units", DEFAULTS.units)})


static func save_config(path: String, config: Dictionary) -> bool:
	if path.is_empty():
		return false
	var clean := sanitize(config)
	var file := ConfigFile.new()
	file.set_value(SECTION, "layout", clean.layout)
	file.set_value(SECTION, "units", clean.units)
	return file.save(path) == OK


static func next_in(list: Array[String], current: String) -> String:
	var index := list.find(current)
	return list[(index + 1) % list.size()] if index >= 0 else list[0]


static func shows(layout: String, element: String) -> bool:
	return element in (LAYOUT_ELEMENTS.get(layout, []) as Array)


## Pitch and roll (deg, aerospace ZYX Euler) of a body-to-NED quaternion [w, x, y, z]; pitch > 0 nose up, roll > 0
## right wing down.
static func euler_deg(q: PackedFloat64Array) -> Vector2:
	var n := sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
	var w := q[0] / n
	var x := q[1] / n
	var y := q[2] / n
	var z := q[3] / n
	var pitch := asin(clampf(2.0 * (w * y - z * x), -1.0, 1.0))
	var roll := atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
	return Vector2(rad_to_deg(pitch), rad_to_deg(roll))


## Heading in degrees [0, 360), clockwise from north (the flight controller's own definition, defined everywhere).
static func heading_deg(q: PackedFloat64Array) -> float:
	return fposmod(rad_to_deg(FC.heading(q)), 360.0)


## Flight values of a rigid-body state [north, east, down, u, v, w, qw, qx, qy, qz, ...]: {pitch_deg, roll_deg,
## heading_deg, climb_mps (NED velocity, up positive), ground_mps (horizontal speed), north, east}. {} if too short.
static func flight_values(body: PackedFloat64Array) -> Dictionary:
	if body.size() < 10:
		return {}
	var q := body.slice(6, 10)
	var v := Cam.rotate(q, body.slice(3, 6))
	var angles := euler_deg(q)
	return {pitch_deg = angles.x, roll_deg = angles.y, heading_deg = heading_deg(q), climb_mps = -v[2],
		ground_mps = sqrt(v[0] * v[0] + v[1] * v[1]), north = body[0], east = body[1]}


## Horizontal distance (m) and the home direction relative to the nose (deg, clockwise, 0 = straight ahead) from a
## position and heading to the home point.
static func home_vector(north: float, east: float, heading: float, home: Vector2) -> Dictionary:
	var dn := home.x - north
	var de := home.y - east
	var distance := sqrt(dn * dn + de * de)
	var bearing := fposmod(rad_to_deg(atan2(de, dn)), 360.0)
	return {distance_m = distance, relative_deg = wrapf(bearing - heading, -180.0, 180.0)}


## Speed text: km/h or mph, whole numbers like an FPV OSD.
static func speed_text(mps: float, units: String) -> String:
	return OsdText.speed(mps, units)


## Altitude text: one decimal below 100 m (330 ft whole feet), whole metres above.
static func altitude_text(m: float, units: String) -> String:
	return OsdText.altitude(m, units)


## Distance text: metres (feet) then kilometres (miles).
static func distance_text(m: float, units: String) -> String:
	return OsdText.distance(m, units)


## Climb rate text with an explicit sign: m/s or ft/s.
static func climb_text(mps: float, units: String) -> String:
	if units == "imperial":
		return "%+.1f FT/S" % (mps * M_TO_FT)
	return "%+.1f M/S" % mps


## Number of vario chevrons (sign = direction): 0 below 0.3 m/s, then 1, 2, 3 at 0.3, 2 and 5 m/s.
static func vario_steps(climb_mps: float) -> int:
	var a := absf(climb_mps)
	var steps := 0 if a < 0.3 else (1 if a < 2.0 else (2 if a < 5.0 else 3))
	return steps * (1 if climb_mps >= 0.0 else -1)


## Pack charge colour band: 2 = full enough, 1 = caution (< 50 %), 0 = low (< 25 %).
static func charge_band(soc: float) -> int:
	return 0 if soc < 0.25 else (1 if soc < 0.5 else 2)


## Post-flight statistics of one armed flight, like a flight controller's stats screen. The quad fills it while armed;
## the HUD shows it after the disarm.
class Stats extends RefCounted:
	var flight_s := 0.0
	var max_speed_mps := 0.0
	var max_altitude_m := 0.0
	var max_distance_m := 0.0
	var total_distance_m := 0.0
	var min_cell_v := INF
	var min_pack_v := INF
	var max_current_a := 0.0
	var max_power_w := 0.0
	var used_mah := 0.0
	var _start_mah := -1.0
	var _last := Vector2.INF

	func reset() -> void:
		flight_s = 0.0
		max_speed_mps = 0.0
		max_altitude_m = 0.0
		max_distance_m = 0.0
		total_distance_m = 0.0
		min_cell_v = INF
		min_pack_v = INF
		max_current_a = 0.0
		max_power_w = 0.0
		used_mah = 0.0
		_start_mah = -1.0
		_last = Vector2.INF

	## t: telemetry; position: (north, east) m; home_m: distance from home; cells: pack cells (0 = unknown).
	func sample(t: Dictionary, position: Vector2, home_m: float, cells: int, armed_s: float) -> void:
		flight_s = armed_s
		max_speed_mps = maxf(max_speed_mps, float(t.get("speed_mps", 0.0)))
		max_altitude_m = maxf(max_altitude_m, float(t.get("altitude_agl_m", 0.0)))
		if is_finite(home_m):
			max_distance_m = maxf(max_distance_m, home_m)
		if position.is_finite():
			if _last.is_finite():
				total_distance_m += _last.distance_to(position)
			_last = position
		if bool(t.get("has_battery", false)):
			var volts := float(t.get("bus_voltage_v", 0.0))
			var amps := float(t.get("pack_current_a", 0.0))
			min_pack_v = minf(min_pack_v, volts)
			if cells > 0:
				min_cell_v = minf(min_cell_v, volts / float(cells))
			max_current_a = maxf(max_current_a, amps)
			max_power_w = maxf(max_power_w, volts * amps)
			var mah := float(t.get("consumed_mah", 0.0))
			if _start_mah < 0.0:
				_start_mah = mah
			used_mah = maxf(0.0, mah - _start_mah)

	## Rows [label (English source), value] for the stats screen; battery rows only with a pack.
	func rows(units: String, cells: int) -> Array:
		var out: Array = [
			["Flight time", "%02d:%02d" % [int(flight_s) / 60, int(flight_s) % 60]],
			["Max speed", OsdText.speed(max_speed_mps, units)],
			["Max altitude", OsdText.altitude(max_altitude_m, units)],
			["Max distance", OsdText.distance(max_distance_m, units)],
			["Total distance", OsdText.distance(total_distance_m, units)],
		]
		if is_finite(min_pack_v):
			if cells > 0 and is_finite(min_cell_v):
				out.append(["Min cell voltage", "%.2f V" % min_cell_v])
			out.append(["Min pack voltage", "%.1f V" % min_pack_v])
			out.append(["Max current", "%.1f A" % max_current_a])
			out.append(["Max power", "%d W" % int(round(max_power_w))])
			out.append(["Used", "%d MAH" % int(round(used_mah))])
			if total_distance_m >= EFFICIENCY_MIN_M:
				out.append(["Efficiency", "%d MAH/KM" % int(round(used_mah / (total_distance_m / 1000.0)))])
		return out


## Static formatters reachable from the inner Stats class (inner classes cannot call the outer script's statics).
class OsdText:
	static func speed(mps: float, units: String) -> String:
		if units == "imperial":
			return "%d MPH" % int(round(mps * MPS_TO_MPH))
		return "%d KM/H" % int(round(mps * MPS_TO_KMH))

	static func altitude(m: float, units: String) -> String:
		if units == "imperial":
			return "%d FT" % int(round(m * M_TO_FT))
		return ("%.1f M" % m) if absf(m) < 100.0 else ("%d M" % int(round(m)))

	static func distance(m: float, units: String) -> String:
		if units == "imperial":
			var ft := m * M_TO_FT
			return ("%d FT" % int(round(ft))) if ft < 5280.0 else ("%.2f MI" % (ft / 5280.0))
		return ("%d M" % int(round(m))) if m < 1000.0 else ("%.2f KM" % (m / 1000.0))
