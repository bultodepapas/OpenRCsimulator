# Flight trace recorder: one row per physics tick, CSV with units in every column name.
# 64-bit floats only (guarded). Feed it from Simulation.stepped; it never reads the clock or the scene.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const WeatherField = preload("res://physics/wind_field.gd")
const Session = preload("res://sim/flight_session.gd")
const Air = preload("res://physics/air_data.gd")
const Flaps = preload("res://physics/flaps.gd")
const GlowFlight = preload("res://physics/glow/flight.gd")

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
const ATMOSPHERE_COLUMNS = ["rho_kgm3", "density_ratio", "equivalent_airspeed_mps", "density_altitude_m", "pressure_pa", "temperature_k", "engine_charge_ratio"]
const COLUMN_ATMOSPHERE_COLUMNS = ["geometric_altitude_m", "loads_rho_kgm3", "loads_pressure_pa", "loads_temperature_k"]
var _atmosphere: Dictionary = {}
var _columns: Array = COLUMNS.duplicate()
var _weather: WeatherField
var _previous_recorded: PackedFloat64Array = PackedFloat64Array()
var _last_recorded_tick: int = -1
var _invalid_weather: bool = false
var _weather_meta: Dictionary = {}
const ELECTRIC_COLUMNS: Array = ["drive_enabled", "drive_duty", "bus_voltage_v", "motor_current_a", "drive_bus_current_a", "source_torque_nm", "shaft_power_w", "copper_loss_w", "rotational_loss_w"]
## Optional recorder-owned endpoint sampler; required only for the versioned electric trace.
var electrical_sample: Callable
var _electric: bool = false
var _battery: bool = false
var _battery_capacity_c: float = NAN
var _battery_initial_charge_c: float = NAN
const BATTERY_COLUMNS: Array = ["battery_soc", "remaining_charge_c", "consumed_charge_c", "pack_current_a", "auxiliary_current_a", "ocv_v", "pack_terminal_power_w", "pack_loss_w", "terminal_energy_j", "pack_heat_j", "pack_exhausted"]
const BATTERY_KEYS: Array[String] = ["soc", "remaining_charge_c", "consumed_charge_c", "pack_current_a", "auxiliary_current_a", "ocv_v", "pack_terminal_power_w", "pack_loss_w", "terminal_energy_j", "pack_heat_j"]
const GLOW_COLUMNS: Array[String] = [
	"glow_fuel_kg", "glow_temperature_k", "glow_running", "glow_stop_reason_code",
	"glow_phase_revolutions", "glow_mixture_command_phi", "glow_fuel_transport_kg_s",
	"glow_opportunity_count", "glow_fire_count", "glow_fire_events", "glow_firing_accumulator",
	"glow_shaft_work_j", "glow_propeller_work_j", "glow_thrust_work_j", "glow_chemical_work_j",
]
const GLOW_CONTINUOUS_LAYOUT: String = "rpm; fuel kg, temperature K, servo, admission, fuel transport kg/s, crank revolutions; running, reason, opportunities, fires, firing accumulator; mixture; shaft/prop/thrust/chemical work J"
const GLOW_TRACE_SCHEMA: String = "openrc-glow-trace v1"
const GLOW_LAW: String = GlowFlight.LAW
const GEAR_TRACE_SCHEMA: String = "openrc-gear-trace v1"
const GEAR_LAW: String = "retractable-point-gear-v1"
const GEAR_INPUT_LAYOUT: Array[String] = ["roll", "pitch", "yaw", "throttle", "gear_down", "wheel_brake"]
const GEAR_COLUMNS: Array[String] = ["gear_extension", "gear_target_down", "cmd_gear_down", "cmd_wheel_brake"]
const FLAP_TRACE_SCHEMA: String = "openrc-flap-trace v1"
const FLAP_LAW: String = Flaps.LAW
const FLAP_COLUMNS: Array[String] = ["cmd_flaps", "flap_fraction", "flap_deg"]
const FLAP_BASE_INPUT_LAYOUT: Array[String] = ["roll", "pitch", "yaw", "throttle"]
var _coupled_shaft: bool = false
var _continuous_turbine: bool = false
var _coupled_start_rpm: float = NAN
var _glow: bool = false
var _glow_family: String = ""
var _glow_cycle_revolutions: float = NAN
var _glow_recording_start: Dictionary = {}
var _glow_recording_start_continuous: PackedFloat64Array = PackedFloat64Array()
var _glow_start_fuel_kg: float = NAN
var _glow_last_fuel_kg: float = NAN
var _glow_last_opportunities: int = -1
var _glow_last_fires: int = -1
var _gear: bool = false
var _gear_aux_index: int = -1
var _gear_meta: Dictionary = {}
var _gear_recording_start: PackedFloat64Array = PackedFloat64Array()
var _flaps: bool = false
var _flap_aux_index: int = -1
var _flap_input_index: int = -1
var _flap_max_angle_deg: float = NAN
var _flap_meta: Dictionary = {}
var _flap_recording_start: float = NAN


func clear() -> void:
	_rows.clear()
	_columns = COLUMNS.duplicate()
	_weather = null
	_previous_recorded = PackedFloat64Array()
	_last_recorded_tick = -1
	_invalid_weather = false
	_weather_meta = {}
	_coupled_shaft = false
	_continuous_turbine = false
	_electric = false
	_battery = false
	_battery_capacity_c = NAN
	_battery_initial_charge_c = NAN
	_coupled_start_rpm = NAN
	_glow = false
	_glow_family = ""
	_glow_cycle_revolutions = NAN
	_glow_recording_start = {}
	_glow_recording_start_continuous = PackedFloat64Array()
	_glow_start_fuel_kg = NAN
	_glow_last_fuel_kg = NAN
	_glow_last_opportunities = -1
	_glow_last_fires = -1
	_gear = false
	_gear_aux_index = -1
	_gear_meta = {}
	_gear_recording_start = PackedFloat64Array()
	_flaps = false
	_flap_aux_index = -1
	_flap_input_index = -1
	_flap_max_angle_deg = NAN
	_flap_meta = {}
	_flap_recording_start = NAN
	_atmosphere = {}
	_turbulence_index = -1


func row_count() -> int:
	return _rows.size() / _columns.size()


func value(row: int, column: String) -> float:
	return _rows[row * _columns.size() + _columns.find(column)]


func columns() -> Array:
	return _columns.duplicate()


func _prepare_weather() -> void:
	_prepare_shaft_metadata()
	if _invalid_weather:
		return
	if not meta.has("weather_config"):
		_prepare_gear_metadata()
		_prepare_flap_metadata()
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
	if _weather.has_atmosphere():
		var supported_metadata_schema: bool = meta.get("metadata_schema") == "openrc-flight-meta v5" \
			or (meta.get("metadata_schema") == "openrc-flight-meta v6" \
				and meta.get("wheel_state_model") == "relative-wheel-rim-speed-rk4-v1") \
			or (meta.get("metadata_schema") == "openrc-flight-meta v7" and meta.get("propulsion_model") == GLOW_LAW) \
			or (meta.get("metadata_schema") == "openrc-flight-meta v8" and _has_gear_metadata_claim()) \
			or (meta.get("metadata_schema") == "openrc-flight-meta v9" and _has_flap_metadata_claim())
		if meta.get("atmosphere_model") != _weather.atmosphere_law() \
				or not supported_metadata_schema or typeof(meta.get("atmosphere_state")) != TYPE_STRING:
			_invalid_weather = true
			return
		var air: Variant = JSON.parse_string(meta.atmosphere_state)
		var calculated: Dictionary = _weather.atmosphere()
		if not air is Dictionary or air.size() != calculated.size() or not air.has_all(calculated.keys()) \
				or typeof(air.get("ok")) != TYPE_BOOL or not air.ok or not air.get("errors") is Array or not air.errors.is_empty():
			_invalid_weather = true
			return
		for key: String in calculated:
			if key in ["ok", "errors"]:
				continue
			if typeof(air[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(air[key])) \
					or absf(float(air[key]) - float(calculated[key])) > maxf(1e-10, absf(float(calculated[key])) * 1e-12):
				_invalid_weather = true
				return
		_atmosphere = calculated
		_columns.append_array(ATMOSPHERE_COLUMNS)
		if _weather.has_vertical_atmosphere():
			_columns.append_array(COLUMN_ATMOSPHERE_COLUMNS)
	_prepare_gear_metadata()
	_prepare_flap_metadata()


## Retractable gear is an opt-in extension to the four legacy command columns.
## Its physical state and commands are validated and appended only when the versioned metadata is complete.
func _prepare_gear_metadata() -> void:
	if not _has_gear_metadata_claim():
		return
	var index: Variant = meta.get("gear_aux_index")
	var dt: Variant = meta.get("dt_s")
	var start_tick: Variant = meta.get("recording_start_tick")
	var raw_start: Variant = meta.get("recording_start_gear")
	var layout_value: Variant = meta.get("input_layout")
	var layout: Variant = JSON.parse_string(layout_value) if typeof(layout_value) == TYPE_STRING else null
	var has_flap_claim: bool = _has_flap_metadata_claim()
	var expected_layout_size: int = GEAR_INPUT_LAYOUT.size() + (1 if has_flap_claim else 0)
	if meta.get("metadata_schema") != ("openrc-flight-meta v9" if has_flap_claim else "openrc-flight-meta v8") \
			or meta.get("gear_law") != GEAR_LAW or meta.get("gear_trace_schema") != GEAR_TRACE_SCHEMA \
			or typeof(index) != TYPE_INT or int(index) < 4 \
			or typeof(dt) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(dt)) or float(dt) <= 0.0 \
			or typeof(start_tick) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(start_tick)) \
			or float(start_tick) < 0.0 or float(start_tick) != floor(float(start_tick)) \
			or typeof(raw_start) != TYPE_STRING or not layout is Array or layout.size() != expected_layout_size:
		_invalid_weather = true
		return
	for i: int in GEAR_INPUT_LAYOUT.size():
		if typeof(layout[i]) != TYPE_STRING or layout[i] != GEAR_INPUT_LAYOUT[i]:
			_invalid_weather = true
			return
	if has_flap_claim and (typeof(layout[6]) != TYPE_STRING or layout[6] != "flaps"):
		_invalid_weather = true
		return
	var start: Variant = JSON.parse_string(raw_start)
	if not start is Array or start.size() != 2:
		_invalid_weather = true
		return
	for component: Variant in start:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			_invalid_weather = true
			return
	if float(start[0]) < 0.0 or float(start[0]) > 1.0 or float(start[1]) not in [0.0, 1.0]:
		_invalid_weather = true
		return
	if meta.has("turbulence_aux_index"):
		var turbulence_index: Variant = meta.get("turbulence_aux_index")
		if not meta.has("weather_config") or typeof(turbulence_index) != TYPE_INT \
				or int(turbulence_index) != int(index) + 2 + (1 if has_flap_claim else 0):
			_invalid_weather = true
			return
	_gear = true
	_gear_aux_index = int(index)
	_gear_meta = meta.duplicate(true)
	_gear_recording_start = PackedFloat64Array([float(start[0]), float(start[1])])
	_columns.append_array(GEAR_COLUMNS)


func _has_gear_metadata_claim() -> bool:
	if meta.has("gear_law") or meta.has("gear_aux_index") or meta.has("gear_trace_schema") or meta.has("recording_start_gear"):
		return true
	if not meta.has("input_layout"):
		return false
	var raw_layout: Variant = meta.get("input_layout")
	var parsed_layout: Variant = JSON.parse_string(raw_layout) if typeof(raw_layout) == TYPE_STRING else raw_layout
	return (parsed_layout is Array and (parsed_layout.size() == 6 \
		or parsed_layout.has("gear_down") or parsed_layout.has("wheel_brake"))) \
		or str(raw_layout).contains("gear_down") or str(raw_layout).contains("wheel_brake")


func _has_flap_metadata_claim() -> bool:
	for key: String in ["flap_law", "flap_aux_index", "flap_input_index", "flap_trace_schema",
			"flap_max_angle_deg", "recording_start_flap"]:
		if meta.has(key):
			return true
	if not meta.has("input_layout"):
		return false
	var raw_layout: Variant = meta.get("input_layout")
	var parsed_layout: Variant = JSON.parse_string(raw_layout) if typeof(raw_layout) == TYPE_STRING else raw_layout
	return (parsed_layout is Array and parsed_layout.has("flaps")) or str(raw_layout).contains("flaps")


func _expected_input_count() -> int:
	return 4 + (2 if _gear else 0) + (1 if _flaps else 0)


func _gear_sample(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	if not _gear:
		return PackedFloat64Array()
	var dt: float = float(_gear_meta.get("dt_s", NAN))
	var turbulence_index: int = int(_gear_meta.get("turbulence_aux_index", -1))
	var expected_aux_size: int = turbulence_index + 7 if turbulence_index >= 0 else _gear_aux_index + 2
	if _flaps:
		expected_aux_size = maxi(expected_aux_size, _flap_aux_index + 1)
	if tick < 0 or not is_finite(t) or t < 0.0 or t != float(tick) * dt \
			or not _state_valid(state) or not _finite(loads, 6) or not _finite(inputs, _expected_input_count()) \
			or not _finite(aux, expected_aux_size) \
			or (_last_recorded_tick >= 0 and tick != _last_recorded_tick + 1):
		_invalid_weather = true
		return PackedFloat64Array()
	var extension: float = aux[_gear_aux_index]
	var target_down: float = aux[_gear_aux_index + 1]
	var command_down: float = inputs[4]
	var wheel_brake: float = inputs[5]
	if extension < 0.0 or extension > 1.0 or target_down not in [0.0, 1.0] \
			or command_down not in [0.0, 1.0] or wheel_brake < 0.0 or wheel_brake > 1.0:
		_invalid_weather = true
		return PackedFloat64Array()
	if _rows.is_empty():
		var start_tick: float = float(_gear_meta.get("recording_start_tick", NAN))
		if float(tick) != start_tick or not _positive_float64_within_one_ulp(extension, _gear_recording_start[0]) \
				or target_down != _gear_recording_start[1]:
			_invalid_weather = true
			return PackedFloat64Array()
	return PackedFloat64Array([extension, target_down, command_down, wheel_brake])


func _prepare_flap_metadata() -> void:
	if not _has_flap_metadata_claim():
		return
	var flap_law: Variant = meta.get("flap_law")
	var schema: Variant = meta.get("metadata_schema")
	var trace_schema: Variant = meta.get("flap_trace_schema")
	var aux_index: Variant = meta.get("flap_aux_index")
	var input_index: Variant = meta.get("flap_input_index")
	var max_angle: Variant = meta.get("flap_max_angle_deg")
	var raw_start: Variant = meta.get("recording_start_flap")
	var dt: Variant = meta.get("dt_s")
	var start_tick: Variant = meta.get("recording_start_tick")
	var raw_layout: Variant = meta.get("input_layout")
	var layout: Variant = JSON.parse_string(raw_layout) if typeof(raw_layout) == TYPE_STRING else null
	var has_gear_claim: bool = _has_gear_metadata_claim()
	var expected_input_index: int = 6 if has_gear_claim else 4
	var expected_layout: Array[String] = FLAP_BASE_INPUT_LAYOUT.duplicate()
	if has_gear_claim:
		expected_layout.append_array(GEAR_INPUT_LAYOUT.slice(4, 6))
	expected_layout.append("flaps")
	if schema != "openrc-flight-meta v9" or typeof(flap_law) != TYPE_STRING or flap_law.is_empty() \
			or flap_law != FLAP_LAW or trace_schema != FLAP_TRACE_SCHEMA or typeof(aux_index) != TYPE_INT or int(aux_index) < 4 \
			or typeof(input_index) != TYPE_INT or int(input_index) != expected_input_index \
			or typeof(max_angle) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(max_angle)) or float(max_angle) <= 0.0 \
			or typeof(raw_start) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw_start)) \
			or float(raw_start) < 0.0 or float(raw_start) > 1.0 \
			or typeof(dt) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(dt)) or float(dt) <= 0.0 \
			or typeof(start_tick) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(start_tick)) \
			or float(start_tick) < 0.0 or float(start_tick) != floor(float(start_tick)) \
			or not layout is Array or layout.size() != expected_layout.size():
		_invalid_weather = true
		return
	for i: int in expected_layout.size():
		if typeof(layout[i]) != TYPE_STRING or layout[i] != expected_layout[i]:
			_invalid_weather = true
			return
	if has_gear_claim and (typeof(meta.get("gear_aux_index")) != TYPE_INT \
			or int(aux_index) != int(meta.gear_aux_index) + 2):
		_invalid_weather = true
		return
	if meta.has("turbulence_aux_index") and (typeof(meta.turbulence_aux_index) != TYPE_INT \
			or int(meta.turbulence_aux_index) != int(aux_index) + 1):
		_invalid_weather = true
		return
	_flaps = true
	_flap_aux_index = int(aux_index)
	_flap_input_index = int(input_index)
	_flap_max_angle_deg = float(max_angle)
	_flap_meta = meta.duplicate(true)
	_flap_recording_start = float(raw_start)
	_columns.append_array(FLAP_COLUMNS)


func _flap_sample(tick: int, t: float, state: PackedFloat64Array, loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	if not _flaps:
		return PackedFloat64Array()
	var dt: float = float(_flap_meta.get("dt_s", NAN))
	if tick < 0 or not is_finite(t) or t < 0.0 or t != float(tick) * dt \
			or not _state_valid(state) or not _finite(loads, 6) or not _finite(inputs, _expected_input_count()) \
			or aux.size() <= _flap_aux_index or not _finite(aux) \
			or (_last_recorded_tick >= 0 and tick != _last_recorded_tick + 1):
		_invalid_weather = true
		return PackedFloat64Array()
	var actual: float = aux[_flap_aux_index]
	var requested: float = inputs[_flap_input_index]
	if actual < 0.0 or actual > 1.0 or requested < 0.0 or requested > 1.0:
		_invalid_weather = true
		return PackedFloat64Array()
	if _rows.is_empty():
		if float(tick) != float(_flap_meta.get("recording_start_tick", NAN)) \
				or not _positive_float64_within_one_ulp(actual, _flap_recording_start):
			_invalid_weather = true
			return PackedFloat64Array()
	return PackedFloat64Array([requested, actual, actual * _flap_max_angle_deg])


## AV-20 adds no CSV columns: engine_rpm is the committed continuous endpoint mirror.
func _prepare_turbine_metadata() -> void:
	var wheel_keys: Array[String] = ["wheel_state_model", "wheel_state_layout", "wheel_profile_status",
		"wheel_profile_sha256", "wheel_profile_input_sha256", "wheel_profile_hash_convention",
		"wheel_brakes", "launch_continuous"]
	var has_wheel_metadata: bool = false
	for key: String in wheel_keys:
		has_wheel_metadata = has_wheel_metadata or meta.has(key)
	var gear_claim: bool = _has_gear_metadata_claim()
	var flap_claim: bool = _has_flap_metadata_claim()
	var wheel_count: int = 0
	var expected_layout: String = Session.Turbine.CONTINUOUS_LAYOUT \
		+ ("; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail" if has_wheel_metadata else "")
	if meta.get("propulsion_model") != Session.Turbine.CONTINUOUS_LAW or meta.get("turbine_integrator") != "rk4" \
			or meta.get("continuous_layout") != expected_layout \
			or meta.has("shaft_integrator") or meta.has("rotor_coupling") or meta.has("electric_configuration"):
		_invalid_weather = true
		return
	var values: Variant = JSON.parse_string(str(meta.get("recording_start_continuous", "null")))
	var sampled: Variant = JSON.parse_string(str(meta.get("recording_start_aux", "null")))
	if not values is Array or values.is_empty() or not sampled is Array or sampled.size() != 4 \
			or typeof(values[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[0])) or float(values[0]) < 0.0 \
			or typeof(sampled[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(sampled[0])) or values[0] != sampled[0]:
		_invalid_weather = true
		return
	if has_wheel_metadata:
		var layout: Variant = JSON.parse_string(str(meta.get("wheel_state_layout", "null")))
		var launch: Variant = JSON.parse_string(str(meta.get("launch_continuous", "null")))
		var brakes: Variant = JSON.parse_string(str(meta.get("wheel_brakes", "null")))
		if not gear_claim or (meta.get("metadata_schema") != "openrc-flight-meta v8" \
				and not (flap_claim and meta.get("metadata_schema") == "openrc-flight-meta v9")) \
				or meta.get("wheel_state_model") != "relative-wheel-rim-speed-rk4-v1" \
				or meta.get("wheel_profile_status") != "applied" \
				or not _is_sha256(str(meta.get("wheel_profile_sha256", ""))) \
				or not _is_sha256(str(meta.get("wheel_profile_input_sha256", ""))) \
				or meta.get("wheel_profile_hash_convention") != "profile_sha256 is canonical JSON for the selected aircraft profile; input_sha256 is SHA-256 of exact wheel_profiles.json bytes" \
				or not layout is Array or layout.is_empty() \
				or values.size() != layout.size() + 1 \
				or not launch is Array or launch.size() != values.size() \
				or not brakes is Array or brakes.size() != layout.size():
			_invalid_weather = true
			return
		wheel_count = layout.size()
		var contacts := {}
		for i: int in layout.size():
			var entry: Variant = layout[i]
			if not entry is Dictionary or typeof(entry.get("index")) not in [TYPE_INT, TYPE_FLOAT] \
					or not is_finite(float(entry.index)) or float(entry.index) != float(int(entry.index)) \
					or int(entry.index) != i + 1 or typeof(entry.get("contact")) != TYPE_STRING \
					or str(entry.contact).is_empty() or contacts.has(entry.contact) or entry.get("unit") != "m/s rim speed":
				_invalid_weather = true
				return
			contacts[entry.contact] = true
			var brake: Variant = brakes[i]
			var torque: Variant = brake.get("max_torque_nm") if brake is Dictionary else null
			if not brake is Dictionary or brake.get("contact") != entry.contact \
					or brake.get("availability") not in ["available", "none", "unspecified"] \
					or typeof(torque) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(torque)) or float(torque) < 0.0 \
					or (float(torque) > 0.0 and brake.availability != "available"):
				_invalid_weather = true
				return
		for component: Variant in launch:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
				_invalid_weather = true
				return
	elif gear_claim or flap_claim:
		_invalid_weather = true
		return
	for component: Variant in sampled:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			_invalid_weather = true
			return
	for component: Variant in values:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			_invalid_weather = true
			return
	if values.size() != 1 + wheel_count:
		_invalid_weather = true
		return
	if typeof(meta.get("dt_s")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(meta.dt_s)) or float(meta.dt_s) <= 0.0:
		_invalid_weather = true
		return
	_continuous_turbine = true
	_coupled_start_rpm = values[0]
	_weather_meta = meta.duplicate(true)


## Glow traces have their own continuous layout and validation; keep the established shaft paths intact.
func _prepare_glow_metadata() -> void:
	var family: String = str(meta.get("glow_family", ""))
	var cycle: float = 1.0 if family == "glow_2t" else (2.0 if family == "glow_4t" else NAN)
	var identity: Variant = JSON.parse_string(str(meta.get("glow_identity", "null")))
	var start: Variant = JSON.parse_string(str(meta.get("glow_recording_start", "null")))
	var start_continuous: Variant = JSON.parse_string(str(meta.get("recording_start_continuous", "null")))
	var aux_start: Variant = JSON.parse_string(str(meta.get("recording_start_aux", "null")))
	var dt: Variant = meta.get("dt_s")
	var start_tick: Variant = meta.get("recording_start_tick")
	var start_reason: int = GlowFlight.REASONS.find(str(start.get("stop_reason", ""))) if start is Dictionary else -1
	var profile_identity: Variant = start.get("profile_identity", {}) if start is Dictionary else {}
	var installation_profile: Variant = identity.get("profile", {}) if identity is Dictionary else {}
	if meta.get("metadata_schema") != "openrc-flight-meta v7" or meta.get("propulsion_model") != GLOW_LAW \
			or family not in ["glow_2t", "glow_4t"] or not is_finite(cycle) \
			or meta.get("continuous_layout") != GLOW_CONTINUOUS_LAYOUT \
			or not identity is Dictionary or not installation_profile is Dictionary \
			or not _is_sha256(str(installation_profile.get("sha256", ""))) \
			or not start is Dictionary or start.get("ok") != true or start.get("family") != family \
			or not profile_identity is Dictionary \
			or profile_identity.get("input_sha256") != installation_profile.get("sha256") \
			or start.get("cycle_revolutions") != cycle or start_reason < 0 \
			or not start_continuous is Array or start_continuous.size() != GlowFlight.SIZE \
			or not aux_start is Array or aux_start.size() != 4 \
			or typeof(dt) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(dt)) or float(dt) <= 0.0 \
			or typeof(start_tick) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(start_tick)) \
			or float(start_tick) < 0.0 or float(start_tick) != floor(float(start_tick)) \
			or meta.get("shaft_integrator") != "coupled-rk4" \
			or meta.get("rotor_coupling") != "relative-spin-locked-inertia-reaction-v1":
		_invalid_weather = true
		return
	for component: Variant in aux_start:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			_invalid_weather = true
			return
	for component: Variant in start_continuous:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
			_invalid_weather = true
			return
	for key: String in ["rpm", "fuel_kg", "temperature_k", "phase_revolutions", "mixture_command", "opportunity_count", "fire_count", "firing_accumulator"]:
		if typeof(start.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(start[key])):
			_invalid_weather = true
			return
	if typeof(start.get("running")) != TYPE_BOOL or float(start.rpm) < 0.0 \
			or float(start.fuel_kg) < 0.0 or float(start.temperature_k) <= 0.0 \
			or float(start.phase_revolutions) < 0.0 or float(start.phase_revolutions) >= cycle \
			or float(start.mixture_command) < 0.0 or float(start.mixture_command) > 2.8 \
			or int(start.opportunity_count) < 0 or int(start.fire_count) < 0 \
			or float(start.opportunity_count) != floor(float(start.opportunity_count)) \
			or float(start.fire_count) != floor(float(start.fire_count)) \
			or int(start.fire_count) > int(start.opportunity_count) \
			or float(start.firing_accumulator) < 0.0 or float(start.firing_accumulator) >= 1.0 \
			or absf(float(aux_start[0]) - float(start.rpm)) > maxf(1e-9, absf(float(start.rpm)) * 1e-12) \
			or meta.get("recording_start_engine_running") != str(bool(start.running)):
		_invalid_weather = true
		return
	_glow = true
	_glow_family = family
	_glow_cycle_revolutions = cycle
	_glow_recording_start = start.duplicate(true)
	_glow_recording_start_continuous = PackedFloat64Array(start_continuous)
	_glow_start_fuel_kg = float(start.fuel_kg)
	_weather_meta = meta.duplicate(true)
	_columns.append_array(GLOW_COLUMNS)


func _prepare_shaft_metadata() -> void:
	var glow_metadata: bool = meta.get("propulsion_model") == GLOW_LAW or meta.has("glow_identity") \
		or meta.has("glow_family") or meta.has("glow_recording_start")
	if glow_metadata:
		_prepare_glow_metadata()
		return
	if meta.get("propulsion_model") == Session.Turbine.CONTINUOUS_LAW or meta.has("turbine_integrator"):
		_prepare_turbine_metadata()
		return
	_battery = meta.get("propulsion_model") == Session.BATTERY_LAW
	_electric = meta.get("propulsion_model") in [Session.ELECTRIC_LAW, Session.BATTERY_LAW]
	if not _electric and (meta.has("electric_configuration") or meta.has("electric_sample_timing")):
		_invalid_weather = true
		return
	if not meta.has("shaft_integrator") and meta.get("propulsion_model") not in ["propeller-shaft-coupled-rk4-v1", Session.ELECTRIC_LAW, Session.BATTERY_LAW]:
		return
	if meta.get("propulsion_model") not in ["propeller-shaft-coupled-rk4-v1", Session.ELECTRIC_LAW, Session.BATTERY_LAW] or meta.get("shaft_integrator") != "coupled-rk4" \
			or meta.get("rotor_coupling") != "relative-spin-locked-inertia-reaction-v1":
		_invalid_weather = true
		return


	var values: Variant = JSON.parse_string(str(meta.get("recording_start_continuous", "null")))
	var sampled: Variant = JSON.parse_string(str(meta.get("recording_start_aux", "null")))
	if not values is Array or values.is_empty() or not sampled is Array or sampled.size() != 4:
		_invalid_weather = true
		return
	var wheel_count: int = 0
	var wheel_first_index: int = -1
	var has_wheel_metadata: bool = meta.has("wheel_state_model") or meta.has("wheel_state_layout") \
		or meta.has("wheel_profile_status") or meta.has("wheel_profile_sha256") or meta.has("wheel_profile_input_sha256") \
		or meta.has("wheel_profile_hash_convention") or meta.has("wheel_brakes") or meta.has("launch_continuous")
	var gear_claim: bool = _has_gear_metadata_claim()
	var flap_claim: bool = _has_flap_metadata_claim()
	var base_layout: String = Session.BATTERY_LAYOUT if _battery else "axial wash increment m/s, slipstream.pieces order, then propeller shaft rpm; RK4 coupled"
	if has_wheel_metadata:
		var layout: Variant = JSON.parse_string(str(meta.get("wheel_state_layout", "null")))
		var launch: Variant = JSON.parse_string(str(meta.get("launch_continuous", "null")))
		if (meta.get("metadata_schema") != "openrc-flight-meta v6" \
				and not (gear_claim and meta.get("metadata_schema") == "openrc-flight-meta v8") \
				and not (flap_claim and meta.get("metadata_schema") == "openrc-flight-meta v9")) \
				or meta.get("wheel_state_model") != "relative-wheel-rim-speed-rk4-v1" \
				or meta.get("wheel_profile_status") != "applied" \
				or not _is_sha256(str(meta.get("wheel_profile_sha256", ""))) \
				or not _is_sha256(str(meta.get("wheel_profile_input_sha256", ""))) \
				or meta.get("wheel_profile_hash_convention") != "profile_sha256 is canonical JSON for the selected aircraft profile; input_sha256 is SHA-256 of exact wheel_profiles.json bytes" \
				or not layout is Array or layout.is_empty() or not launch is Array or launch.size() != values.size():
			_invalid_weather = true
			return
		wheel_count = layout.size()
		wheel_first_index = values.size() - wheel_count
		var contacts := {}
		for i: int in wheel_count:
			var entry: Variant = layout[i]
			if not entry is Dictionary or typeof(entry.get("index")) not in [TYPE_INT, TYPE_FLOAT] \
					or not is_finite(float(entry.index)) or float(entry.index) != float(int(entry.index)) \
					or int(entry.index) != wheel_first_index + i or typeof(entry.get("contact")) != TYPE_STRING \
					or str(entry.contact).is_empty() or contacts.has(entry.contact) or entry.get("unit") != "m/s rim speed":
				_invalid_weather = true
				return
			contacts[entry.contact] = true
		for value: Variant in launch:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				_invalid_weather = true
				return
		var brakes: Variant = JSON.parse_string(str(meta.get("wheel_brakes", "null")))
		if not brakes is Array or brakes.size() != wheel_count:
			_invalid_weather = true
			return
		for i: int in wheel_count:
			var brake: Variant = brakes[i]
			var torque: Variant = brake.get("max_torque_nm") if brake is Dictionary else null
			if not brake is Dictionary or brake.get("contact") != layout[i].contact \
					or brake.get("availability") not in ["available", "none", "unspecified"] \
					or typeof(torque) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(torque)) or float(torque) < 0.0 \
					or (float(torque) > 0.0 and brake.availability != "available"):
				_invalid_weather = true
				return
	elif gear_claim or flap_claim:
		_invalid_weather = true
		return
	if str(meta.get("continuous_layout", "")) != base_layout + ("; wheel rim speeds in m/s, landing-gear contact order, appended continuous tail" if has_wheel_metadata else ""):
		_invalid_weather = true
		return
	var shaft_index: int = values.size() - (4 if _battery else 1) - wheel_count
	if shaft_index < 0 or (meta.get("propwash_model") == "tail-slipstream-axial-transport-v1") != (shaft_index > 0):
		_invalid_weather = true
		return
	if has_wheel_metadata and wheel_first_index != shaft_index + 1 + (3 if _battery else 0):
		_invalid_weather = true
		return
	for value: Variant in values:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			_invalid_weather = true
			return
	if values[shaft_index] < 0.0 or typeof(sampled[0]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(sampled[0])) or values[shaft_index] != sampled[0]:
		_invalid_weather = true
		return
	if _electric:
		var configuration: Variant = JSON.parse_string(str(meta.get("electric_configuration", "null")))
		if not electrical_sample.is_valid() or not configuration is Dictionary \
				or not configuration.get("motor") is Dictionary or not configuration.get("battery") is Dictionary \
				or not configuration.get("esc") is Dictionary \
				or configuration.battery.get("kind") != ("ocv_resistance" if _battery else "fixed_voltage") \
				or meta.get("electric_sample_timing") != "accepted endpoint; current tick input and source-enabled mode":
			_invalid_weather = true
			return
		_columns.append_array(ELECTRIC_COLUMNS)
		if _battery:
			for key: String in ["capacity_ah", "initial_soc"]:
				if typeof(configuration.battery.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(configuration.battery[key])):
					_invalid_weather = true
					return
			_battery_capacity_c = 3600.0 * float(configuration.battery.capacity_ah)
			_battery_initial_charge_c = _battery_capacity_c * float(configuration.battery.initial_soc)
			if not is_finite(_battery_capacity_c) or not is_finite(_battery_initial_charge_c) \
					or _battery_capacity_c <= 0.0 or _battery_initial_charge_c <= 0.0 or _battery_initial_charge_c > _battery_capacity_c \
					or values[shaft_index + 1] < 0.0 or values[shaft_index + 1] > _battery_initial_charge_c \
					or values[shaft_index + 2] < 0.0 or values[shaft_index + 3] < 0.0 \
					or meta.get("battery_model") != "balanced-pack-ocv-resistance-no-regeneration-v1":
				_invalid_weather = true
				return
			_columns.append_array(BATTERY_COLUMNS)
	_coupled_shaft = true
	_coupled_start_rpm = values[shaft_index]
	_weather_meta = meta.duplicate(true)


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true


## Additional battery channels share the endpoint timestamp and carry their own charge budget.
func _valid_battery_sample(point: Dictionary) -> bool:
	for key: String in BATTERY_KEYS:
		if typeof(point.get(key)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(point[key])) or float(point[key]) < 0.0:
			return false
	if typeof(point.get("exhausted")) != TYPE_BOOL or point.exhausted != (point.remaining_charge_c == 0.0):
		return false
	var tolerance: float = maxf(1e-9, _battery_initial_charge_c * 1e-12)
	if point.soc > 1.0 or point.remaining_charge_c > _battery_initial_charge_c \
			or absf(point.soc - point.remaining_charge_c / _battery_capacity_c) > 1e-12 \
			or absf(point.remaining_charge_c + point.consumed_charge_c - _battery_initial_charge_c) > tolerance:
		return false
	if point.exhausted and (point.pack_current_a != 0.0 or point.auxiliary_current_a != 0.0 or point.bus_voltage_v != 0.0):
		return false
	return true


## JSON metadata can decode the initial positive RPM to an adjacent float64.
static func _positive_float64_within_one_ulp(a: float, b: float) -> bool:
	if a == b: # Also treats +0.0 and -0.0 as equal.
		return true
	if not is_finite(a) or not is_finite(b) or a < 0.0 or b < 0.0:
		return false
	var a_bytes := PackedByteArray()
	var b_bytes := PackedByteArray()
	a_bytes.resize(8)
	b_bytes.resize(8)
	a_bytes.encode_double(0, a)
	b_bytes.encode_double(0, b)
	return absi(a_bytes.decode_u64(0) - b_bytes.decode_u64(0)) <= 1


## Signature matches Simulation.stepped, so it can be connected directly.
func record(tick: int, t: float, s: PackedFloat64Array, loads: PackedFloat64Array, inputs: PackedFloat64Array, aux := PackedFloat64Array([0.0]), continuous := PackedFloat64Array()) -> void:
	if _invalid_weather:
		return
	if _rows.is_empty():
		_prepare_weather()
	if _invalid_weather:
		return
	if inputs.size() != _expected_input_count():
		_invalid_weather = true
		return
	var gear_row: PackedFloat64Array = _gear_sample(tick, t, s, loads, inputs, aux)
	if _invalid_weather:
		return
	var flap_row: PackedFloat64Array = _flap_sample(tick, t, s, loads, inputs, aux)
	if _invalid_weather:
		return
	if _coupled_shaft and (aux.size() < 4 or not _finite(aux) or aux[0] < 0.0 \
			or (_rows.is_empty() and not _positive_float64_within_one_ulp(aux[0], _coupled_start_rpm))):
		_invalid_weather = true
		return
	if _continuous_turbine and (tick < 0 or not is_finite(t) or t < 0.0 or t != tick * float(_weather_meta.dt_s) \
			or not _state_valid(s) or not _finite(loads, 6) or not _finite(inputs, _expected_input_count()) or aux.size() < 4 or not _finite(aux) \
			or aux[0] < 0.0 or (_last_recorded_tick >= 0 and tick != _last_recorded_tick + 1) \
			or (_rows.is_empty() and (absf(aux[0] - _coupled_start_rpm) > 1e-9 or str(meta.get("recording_start_tick")) != str(tick)))):
		_invalid_weather = true
		return
	var glow_row := PackedFloat64Array()
	if _glow:
		glow_row = _glow_sample(continuous, tick, t, aux)
		if _invalid_weather:
			return
	var electric_row: PackedFloat64Array = PackedFloat64Array()
	if _electric:
		var point: Variant = electrical_sample.call()
		if not point is Dictionary or not point.get("ok", false) or point.get("tick") != tick \
				or point.get("time_s") != t or point.get("rpm") != aux[0] or typeof(point.get("enabled")) != TYPE_BOOL:
			_invalid_weather = true
			return
		electric_row.append(1.0 if point.enabled else 0.0)
		for key: String in ["duty", "bus_voltage_v", "motor_current_a", "battery_current_a", "shaft_torque_nm", "shaft_power_w", "copper_loss_w", "rotational_loss_w"]:
			if typeof(point.get(key)) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(point[key])):
				_invalid_weather = true
				return
			electric_row.append(float(point[key]))
		if _battery:
			if not _valid_battery_sample(point):
				_invalid_weather = true
				return
			for key: String in BATTERY_KEYS:
				electric_row.append(float(point[key]))
			electric_row.append(1.0 if point.exhausted else 0.0)
	if _weather != null:
		if tick < 0 or not is_finite(t) or t < 0.0 or t != tick * float(_weather_meta.dt_s) \
				or not _state_valid(s) or not _finite(loads, 6) or not _finite(inputs, _expected_input_count()) or aux.size() < 4 or not _finite(aux):
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
	var atmosphere_endpoint: Dictionary = _atmosphere
	var atmosphere_loads: Dictionary = _atmosphere
	if _weather != null and _weather.has_vertical_atmosphere():
		atmosphere_endpoint = _weather.atmosphere(s[RB.POS + 2])
		atmosphere_loads = _weather.atmosphere(force_state[RB.POS + 2])
		if not atmosphere_endpoint.get("ok", false) or not atmosphere_loads.get("ok", false):
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
	_rows.append_array(inputs.slice(0, 4) if _gear or _flaps else inputs)
	for i in 4: # [engine_rpm, srv_roll, srv_pitch, srv_yaw]; missing entries record as 0
		_rows.append(aux[i] if aux.size() > i else 0.0)
	if _electric:
		_rows.append_array(electric_row)
	if _glow:
		_rows.append_array(glow_row)
	if _weather != null:
		var wind: PackedFloat64Array = _weather.sample(t)
		var noise: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
		if _turbulence_index >= 0:
			noise = Session.turbulence_at(aux, _turbulence_index, t, float(_weather_meta.dt_s))
			for axis: int in 3:
				wind[axis] += noise[axis]
		var air: Dictionary = Air.compute(s, wind, _weather.air_density(s[RB.POS + 2]))
		var velocity_ned: PackedFloat64Array = M.q_rotate(q, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
		var load_time: float = max(0, tick - 1) * float(_weather_meta.dt_s)
		var load_wind: PackedFloat64Array = _weather.sample(load_time)
		var load_noise := PackedFloat64Array([0.0, 0.0, 0.0])
		if _turbulence_index >= 0:
			load_noise = Session.turbulence_at(aux, _turbulence_index, load_time, float(_weather_meta.dt_s))
			for axis: int in 3:
				load_wind[axis] += load_noise[axis]
		var load_air: Dictionary = Air.compute(force_state, load_wind, _weather.air_density(force_state[RB.POS + 2]))
		_rows.append_array(PackedFloat64Array([wind[0], wind[1], wind[2], air.V,
			M.sqrt_(velocity_ned[0] * velocity_ned[0] + velocity_ned[1] * velocity_ned[1]), load_time,
			load_wind[0], load_wind[1], load_wind[2], load_air.V]))
		if _turbulence_index >= 0:
			_rows.append_array(noise)
			_rows.append_array(load_noise)
		if not _atmosphere.is_empty():
			_rows.append_array(PackedFloat64Array([atmosphere_endpoint.rho_kgm3, atmosphere_endpoint.sigma,
				air.V * M.sqrt_(atmosphere_endpoint.sigma), atmosphere_endpoint.density_altitude_m, atmosphere_endpoint.pressure_pa,
				atmosphere_endpoint.temperature_k, atmosphere_endpoint.engine_charge_ratio]))
			if _weather.has_vertical_atmosphere():
				_rows.append_array(PackedFloat64Array([float(_weather.configuration().field_elevation_m) - s[RB.POS + 2],
					atmosphere_loads.rho_kgm3, atmosphere_loads.pressure_pa, atmosphere_loads.temperature_k]))
	if _gear:
		_rows.append_array(gear_row)
	if _flaps:
		_rows.append_array(flap_row)
	_previous_recorded = s.duplicate()
	_last_recorded_tick = tick
	if _glow:
		_glow_last_opportunities = int(continuous[9])
		_glow_last_fires = int(continuous[10])
		_glow_last_fuel_kg = continuous[1]


func _glow_sample(values: PackedFloat64Array, tick: int, t: float, aux: PackedFloat64Array) -> PackedFloat64Array:
	var dt: float = float(meta.get("dt_s", NAN))
	var expected_time: float = float(tick) * dt
	if values.size() != GlowFlight.SIZE or not _finite(values) or tick < 0 or not is_finite(t) \
			or absf(t - expected_time) > maxf(1e-12, absf(expected_time) * 1e-12) \
			or aux.size() < 4 or not _finite(aux) \
			or absf(aux[0] - values[0]) > maxf(1e-9, absf(values[0]) * 1e-12) \
			or (_last_recorded_tick >= 0 and tick != _last_recorded_tick + 1):
		_invalid_weather = true
		return PackedFloat64Array()
	if _rows.is_empty():
		var expected_start_tick: float = float(meta.get("recording_start_tick", NAN))
		if tick != int(expected_start_tick) or not _glow_start_matches(values):
			_invalid_weather = true
			return PackedFloat64Array()
	else:
		var fuel_tolerance: float = maxf(1e-12, absf(_glow_last_fuel_kg) * 2e-12)
		if values[1] > _glow_last_fuel_kg + fuel_tolerance \
				or int(values[9]) < _glow_last_opportunities or int(values[10]) < _glow_last_fires \
				or int(values[10]) - _glow_last_fires > int(values[9]) - _glow_last_opportunities:
			_invalid_weather = true
			return PackedFloat64Array()
	var reason: int = int(values[8])
	var fuel_tolerance: float = maxf(1e-12, absf(_glow_start_fuel_kg) * 2e-12)
	if values[0] < 0.0 or values[1] < 0.0 or values[1] > _glow_start_fuel_kg + fuel_tolerance \
			or values[2] <= 0.0 or values[3] < 0.0 or values[3] > 1.0 \
			or values[4] < 0.0 or values[4] > 1.0 or values[5] < 0.0 \
			or values[6] < 0.0 or values[6] >= _glow_cycle_revolutions \
			or values[7] not in [0.0, 1.0] or values[8] != floor(values[8]) \
			or reason < 0 or reason >= GlowFlight.REASONS.size() \
			or values[9] < 0.0 or values[9] != floor(values[9]) \
			or values[10] < 0.0 or values[10] != floor(values[10]) or values[10] > values[9] \
			or values[11] < 0.0 or values[11] >= 1.0 or values[12] < 0.0 or values[12] > 2.8:
		_invalid_weather = true
		return PackedFloat64Array()
	var opportunity_delta: int = 0 if _rows.is_empty() else int(values[9]) - _glow_last_opportunities
	var fire_events: int = 0 if _rows.is_empty() else int(values[10]) - _glow_last_fires
	if fire_events > opportunity_delta:
		_invalid_weather = true
		return PackedFloat64Array()
	return PackedFloat64Array([
		values[1], values[2], values[7], values[8], values[6], values[12], values[5],
		values[9], values[10], fire_events, values[11], values[13], values[14], values[15], values[16],
	])


func _glow_start_matches(values: PackedFloat64Array) -> bool:
	var start: Dictionary = _glow_recording_start
	if values.size() != _glow_recording_start_continuous.size():
		return false
	for index: int in values.size():
		var expected: float = _glow_recording_start_continuous[index]
		if absf(values[index] - expected) > maxf(1e-12, absf(expected) * 2e-12):
			return false
	var number_fields: Array = [
		[0, "rpm"], [1, "fuel_kg"], [2, "temperature_k"], [6, "phase_revolutions"],
		[9, "opportunity_count"], [10, "fire_count"], [11, "firing_accumulator"], [12, "mixture_command"],
	]
	for pair: Array in number_fields:
		var observed: float = values[int(pair[0])]
		var recorded: float = float(start.get(pair[1], NAN))
		if not is_finite(recorded) or absf(observed - recorded) > maxf(1e-12, absf(recorded) * 2e-12):
			return false
	return typeof(start.get("running")) == TYPE_BOOL and values[7] == (1.0 if start.running else 0.0) \
		and str(start.get("stop_reason", "")) == GlowFlight.REASONS[int(values[8])]


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
	var base_trace_format: String = _base_trace_format()
	lines.append("# format: %s" % ("openrc-trace v12" if _flaps else base_trace_format))
	var written_meta: Dictionary = (_weather_meta if _weather != null or _coupled_shaft or _continuous_turbine or _glow else (_flap_meta if _flaps else meta)).duplicate(true)
	if _flaps:
		written_meta.flap_base_trace_format = base_trace_format
	if _glow:
		written_meta.glow_trace_schema = GLOW_TRACE_SCHEMA
		written_meta.glow_stop_reason_codes = JSON.stringify(GlowFlight.REASONS)
		written_meta.glow_event_semantics = "glow_fire_events is the per-row delta of successful accepted fires; counts are cumulative within this trace"
		written_meta.glow_mode_semantics = "glow_running: 0 stopped, 1 running; stop reason is a separate enumerated code"
	# Physical metadata stays frozen at the first sample. Paused visual edits can extend the same recording.
	for visual_key: String in ["visual_context", "visual_timeline"]:
		if meta.has(visual_key):
			written_meta[visual_key] = meta[visual_key]
	for key in written_meta:
		var encoded: String = JSON.stringify(written_meta[key], "", true, true) if (_weather != null or _continuous_turbine or _glow or _flaps) and key == "dt_s" else str(written_meta[key])
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


func _base_trace_format() -> String:
	if _weather != null and _weather.has_vertical_atmosphere():
		return "openrc-trace v11"
	if _gear:
		return "openrc-trace v10"
	if _glow:
		return "openrc-trace v9"
	if _battery:
		return "openrc-trace v8"
	if _electric:
		return "openrc-trace v7"
	if not _atmosphere.is_empty():
		return "openrc-trace v6"
	if _turbulence_index >= 0:
		return "openrc-trace v5"
	if _weather != null:
		return "openrc-trace v4"
	return FORMAT


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
