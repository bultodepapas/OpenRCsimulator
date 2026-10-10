# Flight trace recorder: one row per physics tick, CSV with units in every column name.
# 64-bit floats only (guarded). Feed it from Simulation.stepped; it never reads the clock or the scene.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const WeatherField = preload("res://physics/wind_field.gd")
const Session = preload("res://sim/flight_session.gd")
const Air = preload("res://physics/air_data.gd")

const FORMAT := "openrc-trace v3" # v2: + engine_rpm; v3: + servo (actual surface) positions
const COLUMNS := [
	"tick", "t_s",
	"north_m", "east_m", "down_m", "alt_m",
	"u_mps", "v_mps", "w_mps", "speed_mps",
	"qw", "qx", "qy", "qz", "yaw_deg", "pitch_deg", "roll_deg",
	"p_radps", "q_radps", "r_radps",
	"Fx_N", "Fy_N", "Fz_N", "Mx_Nm", "My_Nm", "Mz_Nm",
	"cmd_roll", "cmd_pitch", "cmd_yaw", "cmd_throttle",
	"engine_rpm",
	"srv_roll", "srv_pitch", "srv_yaw",
]

var meta := {} # written as "# key: value" lines above the header
var _rows := PackedFloat64Array() # flattened, COLUMNS.size() per row
const WEATHER_COLUMNS = ["wind_north_mps", "wind_east_mps", "wind_down_mps", "tas_mps", "ground_horizontal_mps", "loads_t_s", "loads_wind_north_mps", "loads_wind_east_mps", "loads_wind_down_mps", "loads_tas_mps"]
const TURBULENCE_COLUMNS = ["turbulence_north_mps", "turbulence_east_mps", "turbulence_down_mps", "loads_turbulence_north_mps", "loads_turbulence_east_mps", "loads_turbulence_down_mps"]
var _turbulence_index: int = -1
var _columns: Array = COLUMNS.duplicate()
var _weather: WeatherField
var _previous_recorded: PackedFloat64Array = PackedFloat64Array()
var _last_recorded_tick: int = -1
var _invalid_weather: bool = false
var _weather_meta: Dictionary = {}


func clear() -> void:
	_rows.clear()
	_columns = COLUMNS.duplicate()
	_weather = null
	_previous_recorded = PackedFloat64Array()
	_last_recorded_tick = -1
	_invalid_weather = false
	_weather_meta = {}
	_turbulence_index = -1


func row_count() -> int:
	return _rows.size() / _columns.size()


func value(row: int, column: String) -> float:
	return _rows[row * _columns.size() + _columns.find(column)]


func columns() -> Array:
	return _columns.duplicate()


func _prepare_weather() -> void:
	if not meta.has("weather_config"):
		return
	if typeof(meta.weather_config) != TYPE_STRING or typeof(meta.get("dt_s")) not in [TYPE_FLOAT, TYPE_INT] \
			or not is_finite(float(meta.dt_s)) or float(meta.dt_s) <= 0.0:
		_invalid_weather = true
		return
	var parser: JSON = JSON.new()
	if parser.parse(meta.weather_config) != OK:
		_invalid_weather = true
		return
	var built: Dictionary = WeatherField.build(parser.data)
	if not built.ok:
		_invalid_weather = true
		return
	_weather = built.field
	_weather_meta = meta.duplicate(true)
	_columns.append_array(WEATHER_COLUMNS)
	if _weather.has_turbulence():
		var index: Variant = meta.get("turbulence_aux_index")
		if typeof(index) != TYPE_INT or index < 4:
			_invalid_weather = true
			return
		var raw_state: Variant = meta.get("recording_start_rng_state")
		var interval: Variant = JSON.parse_string(str(meta.get("recording_start_turbulence", "null")))
		if typeof(raw_state) != TYPE_STRING or not raw_state.is_valid_int() or str(int(raw_state)) != raw_state \
				or not interval is Array or interval.size() != 7:
			_invalid_weather = true
			return
		for value: Variant in interval:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				_invalid_weather = true
				return
		_turbulence_index = index
		_columns.append_array(TURBULENCE_COLUMNS)


## Signature matches Simulation.stepped, so it can be connected directly.
func record(tick: int, t: float, s: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux := PackedFloat64Array([0.0])) -> void:
	if _invalid_weather:
		return
	if _rows.is_empty():
		_prepare_weather()
	if _invalid_weather:
		return
	if _weather != null:
		if tick < 0 or not is_finite(t) or t < 0.0 or t != tick * float(_weather_meta.dt_s) \
				or not _state_valid(s) or not _finite(loads, 6) or not _finite(inputs, 4) or aux.size() < 4 or not _finite(aux):
			_invalid_weather = true
			return
	if _turbulence_index >= 0:
		var at: float = max(0, tick - 1) * float(_weather_meta.dt_s)
		if aux.size() != _turbulence_index + 7 or aux[_turbulence_index + 6] != at \
				or (_last_recorded_tick < 0 and JSON.stringify(Array(aux.slice(_turbulence_index)), "", true, true) != _weather_meta.recording_start_turbulence):
			_invalid_weather = true
			return
	var force_state: PackedFloat64Array = _previous_recorded
	if _weather != null and force_state.is_empty():
		if tick == 0:
			force_state = s
		else:
			var decoded: Variant = JSON.parse_string(str(meta.get("recording_start_previous_state", "null")))
			if not decoded is Array or decoded.size() != RB.SIZE:
				_invalid_weather = true
				return
			for component: Variant in decoded:
				if typeof(component) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(component)):
					_invalid_weather = true
					return
			force_state = PackedFloat64Array(decoded)
	if _weather != null and _last_recorded_tick >= 0 and tick != _last_recorded_tick + 1:
		_invalid_weather = true
		return
	if _weather != null and not _state_valid(force_state):
		_invalid_weather = true
		return
	var q := M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var e := M.q_to_euler(q)
	var speed := M.sqrt_(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	_rows.append_array(PackedFloat64Array([
		tick, t,
		s[RB.POS], s[RB.POS + 1], s[RB.POS + 2], -s[RB.POS + 2],
		s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2], speed,
		q[0], q[1], q[2], q[3], rad_to_deg(e[0]), rad_to_deg(e[1]), rad_to_deg(e[2]),
		s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2],
	]))
	_rows.append_array(loads)
	_rows.append_array(inputs)
	for i in 4: # [engine_rpm, srv_roll, srv_pitch, srv_yaw]; missing entries record as 0
		_rows.append(aux[i] if aux.size() > i else 0.0)
	if _weather != null:
		var wind: PackedFloat64Array = _weather.sample(t)
		var noise: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
		if _turbulence_index >= 0:
			noise = Session.turbulence_at(aux, _turbulence_index, t, float(_weather_meta.dt_s))
			for axis: int in 3:
				wind[axis] += noise[axis]
		var air: Dictionary = Air.compute(s, wind)
		var velocity_ned: PackedFloat64Array = M.q_rotate(q, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
		var load_time: float = max(0, tick - 1) * float(_weather_meta.dt_s)
		var load_wind: PackedFloat64Array = _weather.sample(load_time)
		var load_noise := PackedFloat64Array([0.0, 0.0, 0.0])
		if _turbulence_index >= 0:
			load_noise = Session.turbulence_at(aux, _turbulence_index, load_time, float(_weather_meta.dt_s))
			for axis: int in 3:
				load_wind[axis] += load_noise[axis]
		var load_air: Dictionary = Air.compute(force_state, load_wind)
		_rows.append_array(PackedFloat64Array([wind[0], wind[1], wind[2], air.V,
			M.sqrt_(velocity_ned[0] * velocity_ned[0] + velocity_ned[1] * velocity_ned[1]), load_time,
			load_wind[0], load_wind[1], load_wind[2], load_air.V]))
		if _turbulence_index >= 0:
			_rows.append_array(noise)
			_rows.append_array(load_noise)
	_previous_recorded = s.duplicate()
	_last_recorded_tick = tick


## Ticks that are missing between consecutive rows (a recorder that drops samples must be visible).
func gaps() -> PackedInt64Array:
	var missing := PackedInt64Array()
	for r in range(1, row_count()):
		var expected := int(value(r - 1, "tick")) + 1
		var got := int(value(r, "tick"))
		for k in range(expected, got):
			missing.append(k)
	return missing


## True when ticks go up by exactly 1 per row: no gaps, duplicates or reordering.
func is_continuous() -> bool:
	for r in range(1, row_count()):
		if int(value(r, "tick")) != int(value(r - 1, "tick")) + 1:
			return false
	return true


func to_csv() -> String:
	if _invalid_weather:
		return ""
	var lines := PackedStringArray()
	lines.append("# format: %s" % ("openrc-trace v5" if _turbulence_index >= 0 else ("openrc-trace v4" if _weather != null else FORMAT)))
	var written_meta: Dictionary = _weather_meta if _weather != null else meta
	for key in written_meta:
		var encoded: String = JSON.stringify(written_meta[key], "", true, true) if _weather != null and key == "dt_s" else str(written_meta[key])
		lines.append("# %s: %s" % [key, encoded])
	lines.append(",".join(_columns))
	var n := _columns.size()
	for r in row_count():
		var cells := PackedStringArray()
		cells.append(str(int(_rows[r * n])))
		for c in range(1, n):
			cells.append("%.9f" % _rows[r * n + c])
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


func save(path: String) -> Error:
	if _invalid_weather:
		return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_csv())
	f.close()
	return OK


static func _finite(values: PackedFloat64Array, size: int = -1) -> bool:
	if size >= 0 and values.size() != size:
		return false
	for component: float in values:
		if not is_finite(component):
			return false
	return true


static func _state_valid(s: PackedFloat64Array) -> bool:
	if not _finite(s, RB.SIZE):
		return false
	var norm_sq: float = 0.0
	for axis: int in 4:
		norm_sq += s[RB.ATT + axis] * s[RB.ATT + axis]
	return is_finite(norm_sq) and absf(norm_sq - 1.0) <= 1e-10
