## DR-31b/c: FPV quad OSD model (Betaflight/INAV-style elements). Pure, presentation-side derivations from the drawn
## state and the session telemetry: attitude angles, heading, climb rate, home vector (home = where the quad was last
## armed, as a flight controller sets it), G-force, remaining flight time, unit formatting, the OSD configuration
## (layouts, a custom element set, units, HD/analog style, crosshair), the one-slot warning of a flight controller and
## the post-flight statistics. Nothing here writes simulation state, and nothing is invented: an element whose source
## is absent is simply not shown (no RSSI/link quality: the simulator has no radio link to measure).
## References: the height is the session's height above the ground below the quad (not above the arm point, as on a
## barometer OSD), the vario the inertial climb rate, PITCH/ROLL the body attitude, and the ladder rungs elevation
## from the camera (with uptilt θ, the θ rung crosses the crosshair in level flight).
## Conventions follow the firmware sources read for DR-31c (Betaflight 2026.6.2 osd_warnings.c/osd.c, INAV 9.1.0
## osd.c): one warning slot by priority, 2 Hz blink at 50 %, severity colours white/green/amber/red on HD goggles,
## alarms at 10 min flight time, 100 m altitude and 5 g, statistics after the disarm until a throttle-high or
## pitch-high stick or 60 s, and the G value filtered with a 0.2 s time constant.
extends RefCounted

const FC = preload("res://physics/multirotor/flight_controller.gd")
const Cam = preload("res://vehicles/multirotor/multirotor_camera.gd")

## Element ids. Warnings, hints, the arm state, race lines and messages are always shown (they are not layout).
const ELEMENTS: Array[String] = ["crosshair", "horizon", "ladder", "sidebars", "compass", "updown", "altitude",
	"vario", "speed", "gforce", "home", "gate", "battery", "battery_detail", "power", "efficiency", "remaining",
	"throttle", "motors", "rpm", "sticks", "angles", "timer", "on_timer", "mode", "craft", "stats"]
## English names of the elements (the settings panel translates them).
const ELEMENT_NAMES := {"crosshair": "Crosshair", "horizon": "Artificial horizon", "ladder": "Pitch ladder",
	"sidebars": "Horizon sidebars", "compass": "Compass bar", "updown": "Up/down reference", "altitude": "Altitude",
	"vario": "Vario", "speed": "Speed", "gforce": "G-force", "home": "Home arrow and distance", "gate": "Next gate",
	"battery": "Battery voltage", "battery_detail": "Current and mAh", "power": "Power", "efficiency": "Efficiency",
	"remaining": "Remaining time", "throttle": "Throttle", "motors": "Motor outputs", "rpm": "Motor RPM",
	"sticks": "Stick overlay", "angles": "Pitch and roll angles", "timer": "Flight timer", "on_timer": "On timer",
	"mode": "Flight mode", "craft": "Craft name", "stats": "Post-flight statistics"}
## Layouts, like a flight controller's OSD profiles: a pilot cycles them in flight (O) or in the settings panel.
const LAYOUTS: Array[String] = ["off", "race", "freestyle", "full", "custom"]
const LAYOUT_NAMES := {"off": "Off", "race": "Race", "freestyle": "Freestyle", "full": "Full", "custom": "Custom"}
const LAYOUT_ELEMENTS := {
	"off": [],
	"race": ["crosshair", "mode", "timer", "battery", "throttle", "craft", "gate", "stats"],
	"freestyle": ["crosshair", "horizon", "sidebars", "compass", "updown", "altitude", "vario", "speed", "home", "gate",
		"battery", "battery_detail", "throttle", "timer", "mode", "stats"],
	"full": ELEMENTS,
}
const UNITS: Array[String] = ["metric", "imperial"]
const UNIT_NAMES := {"metric": "Metric", "imperial": "Imperial"}
## HD: colour by severity (DJI/Walksnail/HDZero DisplayPort fonts); analog: white characters refreshed at the 12 Hz of
## a flight controller's character OSD.
const STYLES: Array[String] = ["hd", "analog"]
const STYLE_NAMES := {"hd": "HD", "analog": "Analog"}
const CROSSHAIRS: Array[String] = ["default", "aircraft", "cross", "dot"]
const CROSSHAIR_NAMES := {"default": "Default", "aircraft": "Aircraft", "cross": "Cross", "dot": "Dot"}
const DEFAULTS := {"layout": "freestyle", "units": "metric", "style": "hd", "crosshair": "default",
	"custom": ["crosshair", "horizon", "sidebars", "compass", "updown", "altitude", "vario", "speed", "home", "gate",
		"battery", "battery_detail", "throttle", "timer", "mode", "stats"]}
const SECTION := "osd"
const M_TO_FT := 3.28084
const MPS_TO_KMH := 3.6
const MPS_TO_MPH := 2.236936
const G := 9.80665
## A flight shorter than this (armed seconds) leaves no statistics screen (an arm-disarm on the pad is not a flight).
const STATS_MIN_FLIGHT_S := 1.0
const STATS_MIN_HEIGHT_M := 0.5
const STATS_MIN_PATH_M := 2.0
## Seconds the statistics stay without a dismissing stick (Betaflight's 60 s).
const STATS_TIMEOUT_S := 60.0
## Efficiency (mAh/km) is listed only after this much horizontal path (m): shorter hops give meaningless figures.
const EFFICIENCY_MIN_M := 200.0
## The live efficiency shows "---" below this ground speed (INAV's 1 m/s).
const EFFICIENCY_MIN_MPS := 1.0
## Alarms (Betaflight/INAV defaults): the flight timer, the height and the G value blink past them.
const TIMER_ALARM_S := 600.0
const ALTITUDE_ALARM_M := 100.0
const GFORCE_ALARM := 5.0
## G filter time constant (INAV's 0.2 s).
const GFORCE_TAU_S := 0.2
## The remaining-time estimate counts down to this share of the pack used (the pilots' 80 % rule), and appears once
## a tenth of the pack has been used (Betaflight waits for 10 % of its capacity alarm).
const RESERVE_USE := 0.8
const ESTIMATE_AFTER_USE := 0.1
## A full pack reads at least this average cell voltage at rest (Betaflight's BATT < FULL before the first arm).
const CELL_FULL_V := 4.1
const CELL_CAUTION_V := 3.6
const CELL_LAND_V := 3.4
## Severity of a warning or value (Betaflight DisplayPort font pages): colour on HD, all white on analog.
enum {NORMAL, INFO, WARNING, CRITICAL}
## The 2 Hz, 50 % blink of a flight controller (250 ms on, 250 ms off).
const BLINK_PERIOD_S := 0.5


## Validated configuration; anything unknown falls back to the default.
static func sanitize(config: Variant) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	if typeof(config) != TYPE_DICTIONARY:
		return out
	var c: Dictionary = config
	for pair: Array in [["layout", LAYOUTS], ["units", UNITS], ["style", STYLES], ["crosshair", CROSSHAIRS]]:
		var value: Variant = c.get(pair[0])
		if typeof(value) == TYPE_STRING and value in (pair[1] as Array):
			out[pair[0]] = value
	var custom: Variant = c.get("custom")
	if typeof(custom) == TYPE_ARRAY or typeof(custom) == TYPE_PACKED_STRING_ARRAY:
		var clean: Array = []
		for element: Variant in custom:
			if typeof(element) == TYPE_STRING and element in ELEMENTS and not element in clean:
				clean.append(element)
		out.custom = clean
	return out


## The saved OSD configuration at `path` ("" = none: automation and tests never read a player file).
static func load_config(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return DEFAULTS.duplicate(true)
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return DEFAULTS.duplicate(true)
	var raw := {}
	for key: String in DEFAULTS:
		raw[key] = file.get_value(SECTION, key, DEFAULTS[key])
	return sanitize(raw)


static func save_config(path: String, config: Dictionary) -> bool:
	if path.is_empty():
		return false
	var clean := sanitize(config)
	var file := ConfigFile.new()
	for key: String in clean:
		file.set_value(SECTION, key, clean[key])
	return file.save(path) == OK


static func next_in(list: Array[String], current: String) -> String:
	var index := list.find(current)
	return list[(index + 1) % list.size()] if index >= 0 else list[0]


## Elements of a fixed layout (the custom layout's come from the configuration: elements_of).
static func shows(layout: String, element: String) -> bool:
	return element in (LAYOUT_ELEMENTS.get(layout, []) as Array)


static func elements_of(config: Dictionary) -> Array:
	var layout := str(config.get("layout", "freestyle"))
	if layout == "custom":
		return (config.get("custom", []) as Array).duplicate()
	return (LAYOUT_ELEMENTS.get(layout, []) as Array).duplicate()


## The configuration after switching one element on or off: the current layout's set becomes the custom layout.
static func toggled(config: Dictionary, element: String, on: bool) -> Dictionary:
	var out := config.duplicate(true)
	var chosen := elements_of(config)
	if on and not element in chosen:
		chosen.append(element)
	elif not on:
		chosen.erase(element)
	out.layout = "custom"
	out.custom = chosen
	return out


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


## Betaflight's up/down reference: "U" when the zenith, "D" when the nadir lies within 25° of the camera axis, "" else.
static func updown(q: PackedFloat64Array, tilt_rad: float) -> String:
	var forward := Cam.rotate(q, PackedFloat64Array([cos(tilt_rad), 0.0, -sin(tilt_rad)]))
	var limit := cos(deg_to_rad(25.0))
	if forward[2] >= limit:
		return "D"
	return "U" if forward[2] <= -limit else ""


## Horizontal distance (m) and the home direction relative to the nose (deg, clockwise, 0 = straight ahead) from a
## position and heading to the home point.
static func home_vector(north: float, east: float, heading: float, home: Vector2) -> Dictionary:
	var dn := home.x - north
	var de := home.y - east
	var distance := sqrt(dn * dn + de * de)
	var bearing := fposmod(rad_to_deg(atan2(de, dn)), 360.0)
	return {distance_m = distance, relative_deg = wrapf(bearing - heading, -180.0, 180.0)}


## Seconds of flight left before RESERVE_USE of the pack at the average draw since the arm; -1 until a tenth of the
## pack is used or without a capacity (the OSD then shows --:--).
static func remaining_s(soc: float, capacity_mah: float, used_mah: float, armed_s: float) -> float:
	if capacity_mah <= 0.0 or armed_s <= 0.0 or used_mah < ESTIMATE_AFTER_USE * capacity_mah or soc < 0.0:
		return -1.0
	var left_mah := maxf(0.0, RESERVE_USE * capacity_mah - (1.0 - soc) * capacity_mah)
	return left_mah / (used_mah / armed_s)


## Live efficiency text: mAh per km (mAh per mile) at the present draw and ground speed, "---" when slow.
static func efficiency_text(current_a: float, ground_mps: float, units: String) -> String:
	if ground_mps < EFFICIENCY_MIN_MPS:
		return "--- MAH/MI" if units == "imperial" else "--- MAH/KM"
	var per_km := current_a * 1000.0 / 3.6 / ground_mps
	if units == "imperial":
		return "%d MAH/MI" % int(round(per_km * 1.609344))
	return "%d MAH/KM" % int(round(per_km))


static func clock_text(seconds: float) -> String:
	if seconds < 0.0 or not is_finite(seconds):
		return "--:--"
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]


## Motor speed text in thousands of rpm, like an ESC telemetry element.
static func rpm_text(rad_s: float) -> String:
	return "%.1fK" % (rad_s * 60.0 / TAU / 1000.0)


## The warning slot of a flight controller: {text (English source), severity, blink}, most urgent first. s: {armed,
## arm_requested, block (FC.BLOCK_*), not_ready, crashed, depleted, cell_v (INF without a pack), ever_armed,
## armed_notice}. Arming refusals show only while the arm switch is on, as on Betaflight.
static func warning(s: Dictionary) -> Dictionary:
	var armed := bool(s.get("armed", false))
	var cell := float(s.get("cell_v", INF))
	if not armed and bool(s.get("arm_requested", false)):
		var block := int(s.get("block", FC.BLOCK_NONE))
		if bool(s.get("crashed", false)) or block == FC.BLOCK_TERMINAL:
			return {text = "CRASH", severity = CRITICAL, blink = true}
		if bool(s.get("not_ready", false)) or block == FC.BLOCK_SOURCE:
			return {text = "RXLOSS", severity = WARNING, blink = false}
		if block == FC.BLOCK_THROTTLE:
			return {text = "THROTTLE", severity = WARNING, blink = false}
		if block == FC.BLOCK_SWITCH:
			return {text = "ARM SWITCH", severity = WARNING, blink = false}
	if bool(s.get("crashed", false)):
		return {text = "CRASH", severity = CRITICAL, blink = true}
	if bool(s.get("depleted", false)):
		return {text = "BATT EMPTY", severity = CRITICAL, blink = true}
	if cell < CELL_LAND_V:
		return {text = "LAND NOW", severity = CRITICAL, blink = true}
	if cell < CELL_CAUTION_V:
		return {text = "LOW BATTERY", severity = WARNING, blink = true}
	if not bool(s.get("ever_armed", false)) and cell < CELL_FULL_V:
		return {text = "BATT < FULL", severity = WARNING, blink = false}
	if armed and bool(s.get("armed_notice", false)):
		return {text = "ARMED", severity = INFO, blink = false}
	return {text = "", severity = NORMAL, blink = false}


## The visible half of the 2 Hz blink at `now` seconds.
static func blink_on(now: float) -> bool:
	return fposmod(now, BLINK_PERIOD_S) < BLINK_PERIOD_S * 0.5


## Pack charge colour band: 2 = full enough, 1 = caution (< 50 %), 0 = low (< 25 %).
static func charge_band(soc: float) -> int:
	return 0 if soc < 0.25 else (1 if soc < 0.5 else 2)


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


## G-force of the accepted ticks: the specific force |dv/dt - g| / g from the NED velocity of consecutive accepted
## states, low-pass filtered with GFORCE_TAU_S (a quad at rest or in steady flight reads 1.0 G).
class GForce extends RefCounted:
	var value := 1.0
	var _tick := -1
	var _velocity := PackedFloat64Array()

	func reset() -> void:
		value = 1.0
		_tick = -1
		_velocity = PackedFloat64Array()

	## tick: the accepted tick; body: its rigid-body state; dt: seconds per tick.
	func sample(tick: int, body: PackedFloat64Array, dt: float) -> void:
		if body.size() < 10 or tick == _tick:
			return
		var v := Cam.rotate(body.slice(6, 10), body.slice(3, 6))
		if _tick >= 0 and tick > _tick and _velocity.size() == 3:
			var span := float(tick - _tick) * dt
			var f0 := (v[0] - _velocity[0]) / span
			var f1 := (v[1] - _velocity[1]) / span
			var f2 := (v[2] - _velocity[2]) / span - G
			var g_now := sqrt(f0 * f0 + f1 * f1 + f2 * f2) / G
			value += (g_now - value) * (1.0 - exp(-span / GFORCE_TAU_S))
		elif tick < _tick:
			value = 1.0 # a restart or a restore: the history no longer applies
		_tick = tick
		_velocity = v


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
	var end_pack_v := INF
	var max_current_a := 0.0
	var max_power_w := 0.0
	var used_mah := 0.0
	var max_g := 0.0
	var max_rpm_rad_s := 0.0
	var full_throttle_s := 0.0
	var _throttle_integral := 0.0
	var _start_mah := -1.0
	var _last := Vector2.INF
	var _last_s := -1.0

	## A real flight: armed long enough and it left the pad (an arm-and-wait on the ground shows no statistics).
	func was_flight() -> bool:
		return flight_s >= STATS_MIN_FLIGHT_S and (max_altitude_m > STATS_MIN_HEIGHT_M or total_distance_m > STATS_MIN_PATH_M)

	func reset() -> void:
		flight_s = 0.0
		max_speed_mps = 0.0
		max_altitude_m = 0.0
		max_distance_m = 0.0
		total_distance_m = 0.0
		min_cell_v = INF
		min_pack_v = INF
		end_pack_v = INF
		max_current_a = 0.0
		max_power_w = 0.0
		used_mah = 0.0
		max_g = 0.0
		max_rpm_rad_s = 0.0
		full_throttle_s = 0.0
		_throttle_integral = 0.0
		_start_mah = -1.0
		_last = Vector2.INF
		_last_s = -1.0

	## Average collective (0..1) over the armed time.
	func average_throttle() -> float:
		return _throttle_integral / flight_s if flight_s > 0.0 else 0.0

	## t: telemetry; position: (north, east) m; home_m: distance from home; cells: pack cells (0 = unknown);
	## armed_s: seconds since the arm; g: the filtered G value (NAN = none).
	func sample(t: Dictionary, position: Vector2, home_m: float, cells: int, armed_s: float, g := NAN) -> void:
		var step := armed_s - _last_s if _last_s >= 0.0 else 0.0
		_last_s = armed_s
		flight_s = armed_s
		var collective := float(t.get("collective", 0.0))
		if step > 0.0:
			_throttle_integral += collective * step
			if collective >= 0.99:
				full_throttle_s += step
		max_speed_mps = maxf(max_speed_mps, float(t.get("speed_mps", 0.0)))
		max_altitude_m = maxf(max_altitude_m, float(t.get("altitude_agl_m", 0.0)))
		if is_finite(g):
			max_g = maxf(max_g, g)
		var rotors: Variant = t.get("rotor_speed_rad_s")
		if typeof(rotors) == TYPE_PACKED_FLOAT64_ARRAY:
			for w: float in rotors:
				max_rpm_rad_s = maxf(max_rpm_rad_s, absf(w))
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
			end_pack_v = volts
			if cells > 0:
				min_cell_v = minf(min_cell_v, volts / float(cells))
			max_current_a = maxf(max_current_a, amps)
			max_power_w = maxf(max_power_w, volts * amps)
			var mah := float(t.get("consumed_mah", 0.0))
			if _start_mah < 0.0:
				_start_mah = mah
			used_mah = maxf(0.0, mah - _start_mah)

	## Rows [label (English source), value] in Betaflight's order; battery rows only with a pack.
	func rows(units: String, cells: int) -> Array:
		var out: Array = [
			["Flight time", "%02d:%02d" % [int(flight_s) / 60, int(flight_s) % 60]],
			["Max altitude", OsdText.altitude(max_altitude_m, units)],
			["Max speed", OsdText.speed(max_speed_mps, units)],
			["Max distance", OsdText.distance(max_distance_m, units)],
			["Total distance", OsdText.distance(total_distance_m, units)],
		]
		if is_finite(min_pack_v):
			if cells > 0 and is_finite(min_cell_v):
				out.append(["Min cell voltage", "%.2f V" % min_cell_v])
			out.append(["Min pack voltage", "%.1f V" % min_pack_v])
			out.append(["End battery", "%.1f V" % end_pack_v])
			out.append(["Max current", "%.1f A" % max_current_a])
			out.append(["Max power", "%d W" % int(round(max_power_w))])
			out.append(["Used", "%d MAH" % int(round(used_mah))])
			if total_distance_m >= EFFICIENCY_MIN_M:
				out.append(["Efficiency", "%d MAH/KM" % int(round(used_mah / (total_distance_m / 1000.0)))])
		if max_g > 0.0:
			out.append(["Max G-force", "%.1f G" % max_g])
		if max_rpm_rad_s > 0.0:
			out.append(["Max motor RPM", "%d" % int(round(max_rpm_rad_s * 60.0 / TAU))])
		out.append(["Avg throttle", "%d%%" % int(round(100.0 * average_throttle()))])
		out.append(["Full throttle time", "%.1f S" % full_throttle_s])
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
