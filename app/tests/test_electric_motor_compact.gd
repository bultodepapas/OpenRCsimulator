extends SceneTree

const Motor: Script = preload("res://physics/electric_motor.gd")
const Supply: Script = preload("res://physics/electric_supply.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var motor: Dictionary = _motor_fixture()
	var full_motor: Dictionary = Motor.evaluate(5000.0, 0.8, 11.1, motor)
	var compact_motor: Dictionary = Motor._evaluate_validated(
		5000.0, 0.8, 11.1, 600.0, 0.2, 1.0, true, true)
	var expected_motor: Dictionary = {
		ok = true,
		mode = full_motor.mode,
		shaft_torque_nm = full_motor.shaft_torque_nm,
		motor_current_a = full_motor.motor_current_a,
		battery_current_a = full_motor.battery_current_a,
	}
	_check("motor compact shape has five fields", compact_motor.size() == 5)
	_check("motor compact bytes match full source subset",
		var_to_bytes(compact_motor) == var_to_bytes(expected_motor))
	_check("motor compact fields keep their public scalar types",
		typeof(compact_motor.ok) == TYPE_BOOL and typeof(compact_motor.mode) == TYPE_STRING \
		and typeof(compact_motor.shaft_torque_nm) == TYPE_FLOAT \
		and typeof(compact_motor.motor_current_a) == TYPE_FLOAT \
		and typeof(compact_motor.battery_current_a) == TYPE_FLOAT)

	var motor_overflow_full: Dictionary = Motor._evaluate_validated(
		0.0, 1.0, 1e308, 1e100, 1e100, 0.0, true)
	var motor_overflow_compact: Dictionary = Motor._evaluate_validated(
		0.0, 1.0, 1e308, 1e100, 1e100, 0.0, true, true)
	_check("motor compact overflow preserves exact failure bytes",
		var_to_bytes(motor_overflow_compact) == var_to_bytes(motor_overflow_full))
	_check("motor compact overflow keeps first field diagnostic",
		motor_overflow_compact.get("message", "") == "motor evaluation overflow: bus_power_w")
	var invalid_scalar_full: Dictionary = Motor._evaluate_validated(
		-1.0, 0.8, 11.1, 600.0, 0.2, 1.0, true)
	var invalid_scalar_compact: Dictionary = Motor._evaluate_validated(
		-1.0, 0.8, 11.1, 600.0, 0.2, 1.0, true, true)
	_check("motor compact input failure preserves exact bytes",
		var_to_bytes(invalid_scalar_compact) == var_to_bytes(invalid_scalar_full))

	var pack: Dictionary = _pack_fixture()
	var full_supply: Dictionary = Supply.evaluate(5000.0, 0.8, 0.8, pack, motor)
	var compact_supply: Dictionary = Supply.evaluate_dynamics(5000.0, 0.8, 0.8, pack, motor)
	var expected_supply: Dictionary = {
		"ok": true,
		"shaft_torque_nm": full_supply.shaft_torque_nm,
		"motor_current_a": full_supply.motor_current_a,
		"pack_current_a": full_supply.pack_current_a,
		"pack_terminal_power_w": full_supply.pack_terminal_power_w,
		"pack_loss_w": full_supply.pack_loss_w,
	}
	_check("supply compact shape has six fields", compact_supply.size() == 6)
	_check("supply compact bytes match public consumed subset",
		var_to_bytes(compact_supply) == var_to_bytes(expected_supply))

	var overflow_pack: Dictionary = {
		"ocv_points": PackedFloat64Array([0.0, 1e-200, 1.0, 1e-200]),
		"capacity_ah": 1e-100,
		"resistance_ohm": 0.0,
		"auxiliary_current_a": 1e280,
	}
	var supply_overflow_full: Dictionary = Supply.evaluate(0.0, 0.0, 0.5, overflow_pack, motor)
	var supply_overflow_compact: Dictionary = Supply.evaluate_dynamics(0.0, 0.0, 0.5, overflow_pack, motor)
	_check("supply compact overflow preserves exact failure bytes",
		var_to_bytes(supply_overflow_compact) == var_to_bytes(supply_overflow_full))
	_check("supply compact overflow preserves first result field",
		supply_overflow_compact.get("message", "") == "battery evaluation overflow: soc_rate_per_s")

	motor["unsupported"] = 1.0
	var invalid_motor_stage: Dictionary = Supply.evaluate_dynamics(5000.0, 0.8, 0.8, pack, motor)
	_check("mutated motor definition is rejected on the next call",
		var_to_bytes(invalid_motor_stage) == var_to_bytes({
			"ok": false, "message": "motor has unsupported field unsupported",
		}))
	motor.erase("unsupported")
	motor["resistance_ohm"] = 0.25
	var changed_motor_full: Dictionary = Supply.evaluate(5000.0, 0.8, 0.8, pack, motor)
	var changed_motor_stage: Dictionary = Supply.evaluate_dynamics(5000.0, 0.8, 0.8, pack, motor)
	var changed_motor_expected: Dictionary = {
		"ok": true,
		"shaft_torque_nm": changed_motor_full.shaft_torque_nm,
		"motor_current_a": changed_motor_full.motor_current_a,
		"pack_current_a": changed_motor_full.pack_current_a,
		"pack_terminal_power_w": changed_motor_full.pack_terminal_power_w,
		"pack_loss_w": changed_motor_full.pack_loss_w,
	}
	_check("mutated valid motor values are recomputed on the next call",
		var_to_bytes(changed_motor_stage) == var_to_bytes(changed_motor_expected))
	pack["auxiliary_current_a"] = -0.1
	var invalid_pack_stage: Dictionary = Supply.evaluate_dynamics(5000.0, 0.8, 0.8, pack, motor)
	_check("mutated pack definition is rejected on the next call",
		var_to_bytes(invalid_pack_stage) == var_to_bytes({
			"ok": false, "message": "pack.auxiliary_current_a must be finite and >= 0",
		}))

	print("EL2a-P3 compact motor: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _motor_fixture() -> Dictionary:
	return {"kv_rpm_per_volt": 600.0, "resistance_ohm": 0.2, "no_load_current_a": 1.0}


func _pack_fixture() -> Dictionary:
	return {
		"ocv_points": PackedFloat64Array([0.0, 10.0, 0.5, 12.0, 1.0, 14.0]),
		"capacity_ah": 3.0,
		"resistance_ohm": 0.08,
		"auxiliary_current_a": 0.4,
	}


func _check(label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + label)
