# HELI-07: finite, torque- and power-limited drive for the one-speed rotor lump.
# This proxy has no separate engine-speed state or clutch/freewheel dynamics.
extends RefCounted

const PARAMETER_KEYS: Array = [
	"engine_torque_max_nm", "engine_power_max_w", "engine_speed_ratio_to_main",
	"gear_efficiency", "governor_target_main_rad_s", "governor_gain_nm_per_rad_s",
	"shaft_loss_torque_nm", "shaft_viscous_loss_nm_per_rad_s",
]
const LAW: String = "openrc-one-speed-drive-proxy-v1"


## Convert loader-authored powerplant and gearing into a flat immutable context.
static func prepare(parameters: Dictionary) -> Dictionary:
	if parameters.size() != PARAMETER_KEYS.size() or not parameters.has_all(PARAMETER_KEYS):
		return {"ok": false, "message": "drive parameters are missing or contain unknown fields"}
	var model: Dictionary = {"law": LAW}
	for key: String in PARAMETER_KEYS:
		if not _number(parameters[key]):
			return {"ok": false, "message": "drive parameter " + key + " must be finite"}
		model[key] = float(parameters[key])
	if model.engine_torque_max_nm <= 0.0 or model.engine_power_max_w <= 0.0 \
			or model.engine_speed_ratio_to_main <= 0.0 or model.gear_efficiency <= 0.0 \
			or model.gear_efficiency > 1.0 or model.governor_target_main_rad_s <= 0.0 \
			or model.governor_gain_nm_per_rad_s < 0.0 or model.shaft_loss_torque_nm < 0.0 \
			or model.shaft_viscous_loss_nm_per_rad_s < 0.0:
		return {"ok": false, "message": "drive torque, power, ratio and governor bounds are invalid"}
	model.make_read_only()
	return {"ok": true, "model": model}


## `drive_fraction` comes from the selected collective/throttle curve. The P-only
## governor adjusts engine torque within its declared limit. At zero speed the
## requested torque is finite and no artificial angular-speed floor is used.
static func evaluate(model: Dictionary, main_speed: float, drive_fraction: float,
		governor_enabled: bool = true, zero_drive_hold: bool = false) -> Dictionary:
	if not _prepared(model) or not _finite([main_speed, drive_fraction]) \
			or main_speed < 0.0 or drive_fraction < 0.0 or drive_fraction > 1.0:
		return {"ok": false, "message": "invalid drive state, command or prepared context"}
	var ratio: float = model.engine_speed_ratio_to_main
	var engine_speed: float = ratio * main_speed
	if not is_finite(engine_speed):
		return {"ok": false, "message": "engine shaft speed overflowed"}
	if zero_drive_hold:
		var held_loss: float = model.shaft_viscous_loss_nm_per_rad_s * main_speed
		if main_speed > 0.0:
			held_loss += model.shaft_loss_torque_nm
		return {"ok": true, "engine_speed_rad_s": engine_speed,
			"engine_torque_nm": 0.0, "engine_power_w": 0.0,
			"main_drive_torque_nm": 0.0, "main_drive_power_w": 0.0,
			"shaft_loss_torque_nm": held_loss,
			"net_main_torque_nm": -held_loss,
			"governor_error_rad_s": model.governor_target_main_rad_s - main_speed,
			"power_limited": false, "zero_drive_hold_proxy": true,
			"one_speed_lump_preserved": true}
	var commanded_torque: float = drive_fraction * model.engine_torque_max_nm
	var governor_error: float = model.governor_target_main_rad_s - main_speed
	if governor_enabled:
		commanded_torque += model.governor_gain_nm_per_rad_s * governor_error
	commanded_torque = clampf(commanded_torque, 0.0, model.engine_torque_max_nm)
	var delivered_torque: float = commanded_torque
	var power_limited: bool = false
	if engine_speed > 0.0:
		var torque_at_power: float = model.engine_power_max_w / engine_speed
		if torque_at_power < delivered_torque:
			delivered_torque = torque_at_power
			power_limited = true
	var engine_power: float = delivered_torque * engine_speed
	var main_torque: float = model.gear_efficiency * ratio * delivered_torque
	var main_power: float = main_torque * main_speed
	var shaft_loss: float = model.shaft_viscous_loss_nm_per_rad_s * main_speed
	if main_speed > 0.0:
		shaft_loss += model.shaft_loss_torque_nm
	var net_main_torque: float = main_torque - shaft_loss
	if main_speed == 0.0:
		# Coulomb loss acts as a finite static breakaway load at the stop. A weak
		# request holds the rotor at zero; it never creates a negative-speed state.
		shaft_loss = minf(main_torque, model.shaft_loss_torque_nm)
		net_main_torque = main_torque - shaft_loss
	if not _finite([delivered_torque, engine_power, main_torque, main_power, shaft_loss, net_main_torque]):
		return {"ok": false, "message": "drive output overflowed finite range"}
	return {"ok": true, "engine_speed_rad_s": engine_speed,
		"engine_torque_nm": delivered_torque, "engine_power_w": engine_power,
		"main_drive_torque_nm": main_torque, "main_drive_power_w": main_power,
		"shaft_loss_torque_nm": shaft_loss, "net_main_torque_nm": net_main_torque,
		"governor_error_rad_s": governor_error, "power_limited": power_limited,
		"zero_drive_hold_proxy": false, "one_speed_lump_preserved": true}


static func _prepared(model: Dictionary) -> bool:
	if not model.is_read_only() or model.get("law") != LAW or model.size() != PARAMETER_KEYS.size() + 1:
		return false
	for key: String in PARAMETER_KEYS:
		if not model.has(key) or typeof(model[key]) != TYPE_FLOAT or not is_finite(model[key]):
			return false
	return model.engine_torque_max_nm > 0.0 and model.engine_power_max_w > 0.0 \
		and model.engine_speed_ratio_to_main > 0.0 and model.gear_efficiency > 0.0 \
		and model.gear_efficiency <= 1.0 and model.governor_target_main_rad_s > 0.0 \
		and model.governor_gain_nm_per_rad_s >= 0.0 and model.shaft_loss_torque_nm >= 0.0 \
		and model.shaft_viscous_loss_nm_per_rad_s >= 0.0


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _number(value: Variant) -> bool:
	var kind: int = typeof(value)
	return (kind == TYPE_FLOAT or kind == TYPE_INT) and is_finite(float(value))
