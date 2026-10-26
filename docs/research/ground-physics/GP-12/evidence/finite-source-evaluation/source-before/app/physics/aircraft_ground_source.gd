## Explicit bridge from existing source/propeller maps to the common rotor law.
## No new propeller map, electromagnetic law, shaft integration or stop projector.
extends RefCounted

const Propulsion := preload("res://physics/propulsion.gd")
const M := preload("res://physics/math3d.gd")
const LAW := "fixed-voltage-electric-common-rotor-torque-split-v1"


## propeller_loads_o is the complete existing propeller wrench at THIS stage,
## already included exactly once in the external aircraft wrench. It uses the
## aircraft's fixed reference datum, not the changing live CG. Remove its hub
## force moment to get the complete local rotor couple (drag plus P-factor).
##
## The old motor torque has a rest clamp and contains Coulomb bearing loss.
## The common stage instead receives electromagnetic drive alone. A finite
## internal shaft row in the SAME contact QP owns bearing friction once.
## Motor copper loss remains electrical, and the propeller aerodynamic couple
## remains external. Neither is assigned to the bearing impulse loss ledger.
##
## trial_extension=true permits a negative algebraic RPM only while locating or
## refining the stop boundary: source maps are evaluated at their zero left
## limit. It does not authorize reverse accepted RPM or supply a one-way clutch.
static func electric_fixed_voltage(prop: Dictionary, rpm: float, duty: float, enabled: bool,
		propeller_loads_o: PackedFloat64Array, trial_extension := false) -> Dictionary:
	if not Propulsion.is_electric(prop) or not Propulsion.has_rotor_dynamics(prop) \
		or not prop.get("battery") is Dictionary or prop.battery.get("kind") != "fixed_voltage" \
		or typeof(prop.get("rotor_inertia")) not in [TYPE_FLOAT, TYPE_INT] \
		or not is_finite(float(prop.rotor_inertia)) or prop.rotor_inertia <= 0.0:
		return _failure("this adapter requires the existing closed fixed-voltage electric installation")
	if not is_finite(rpm) or (rpm < 0.0 and not trial_extension) or not is_finite(duty) or duty < 0.0 or duty > 1.0 \
		or not _shape(propeller_loads_o, 6) or not _shape(prop.get("offset"), 3):
		return _failure("finite supported source state and fixed-datum propeller wrench are required")
	var axis := Propulsion.axis(prop)
	if not _shape(axis, 3) or absf(M.dot(axis, axis) - 1.0) > 1e-9:
		return _failure("invalid installed shaft axis")
	var map_rpm := maxf(0.0, rpm)
	var point := Propulsion.electric_source_state(map_rpm, duty, prop, enabled)
	if not point.get("ok", false): return _failure("existing electric source rejected this stage: " + str(point.get("message", "invalid")))
	# Arithmetic matches ElectricMotor's SI conversion, without its isolated rest
	# friction clamp. Explicit static capacity remains available with drive off.
	var kt: float = 60.0 / TAU / float(prop.motor.kv_rpm_per_volt)
	var drive: float = kt * float(point.motor_current_a)
	var capacity: float = kt * float(prop.motor.no_load_current_a)
	var offset: PackedFloat64Array = prop.offset
	var hub := PackedFloat64Array([-offset[0], offset[1], -offset[2]])
	var couple := M.sub(propeller_loads_o.slice(3, 6), M.cross(hub, propeller_loads_o.slice(0, 3)))
	var electromagnetic_power: float = drive * map_rpm * TAU / 60.0
	var electrical_residual: float = float(point.bus_power_w) - float(point.copper_loss_w) - electromagnetic_power
	if not _shape(couple, 3) or not _shape(PackedFloat64Array([drive, capacity, electromagnetic_power, electrical_residual]), 4) \
		or drive < 0.0 or capacity < 0.0:
		return _failure("source torque decomposition exceeds numeric range")
	return {ok = true, law = LAW, source_kind = "electric_fixed_voltage", stage_map_rpm = map_rpm,
		trial_extension_only = rpm < 0.0, accepted_spin_domain = "nonnegative_relative_shaft_rpm",
		internal_drive_torque_nm = drive, shaft_friction_capacity_nm = capacity,
		shaft_external_couple_body_nm = couple, shaft_axis_body = axis.duplicate(), propeller_hub_body_m = hub,
		motor_current_a = float(point.motor_current_a), battery_current_a = float(point.battery_current_a),
		bus_power_w = float(point.bus_power_w), copper_loss_w = float(point.copper_loss_w),
		electromagnetic_power_at_map_rpm_w = electromagnetic_power, electrical_balance_residual_w = electrical_residual,
		friction_owner = "bounded_internal_shaft_impulse_in_same_ground_QP",
		external_wrench_ownership = "supplied_propeller_wrench_is_already_in_total_aircraft_external_loads_once"}


static func _shape(value: Variant, size: int) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != size: return false
	for number: float in value:
		if not is_finite(number): return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {ok = false, law = LAW, reason = reason}
