extends RefCounted
## Estimated nitro powertrain layered over the shared 31-state ground-vehicle
## body kernel. Engine speed and remaining fuel are appended as float64 state;
## the GDScript adapter always passes only the original 31-value body slice to
## VehicleDynamics and its optional native evaluator.

const VehicleDynamics := preload("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_vehicle_dynamics.gd")

const POS := VehicleDynamics.POS
const WHEEL_SPIN := VehicleDynamics.WHEEL_SPIN
const BODY_STATE_SIZE := VehicleDynamics.STATE_SIZE
const ENGINE_SPEED := BODY_STATE_SIZE
const FUEL_MASS := BODY_STATE_SIZE + 1
const STATE_SIZE := BODY_STATE_SIZE + 2
const SUBSTEPS_PER_TICK := 1
const SOURCE_PATH := "res://physics/ground_vehicle/nitro_dynamics.gd"
const BACKEND_VERSION := "openrc-nitro-ground-vehicle-composite-v2"
const SOLVER_VERSION := "openrc-nitro-powertrain-midpoint-v2"
const RPM_PER_RAD_S := 30.0 / PI
const ENGINE_STALL_SPEED_RAD_S := 1.0

const STATE_LAYOUT := [
	"north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
	"qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
	"travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
	"travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
	"wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
	"wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
	"steering_right_rad", "steering_rate_right_rad_per_s",
	"engine_speed_rad_s", "fuel_mass_kg",
]


## Preserve the active body backend identity while pinning this adapter's source
## into the composite source digest. The base native extension is still used for
## body evaluations, but it only ever receives 31 state values.
static func backend_identity() -> Dictionary:
	var base: Dictionary = VehicleDynamics.backend_identity()
	var adapter: Dictionary = VehicleDynamics._reference_implementation_artifact(SOURCE_PATH)
	var body_artifact: Dictionary = VehicleDynamics._reference_implementation_artifact("res://physics/ground_vehicle/vehicle_dynamics.gd")
	var payload := {
		"adapter_source_sha256": str(adapter.get("sha256", "")),
		"body_source_sha256": str(body_artifact.get("sha256", "")),
		"body_backend": base,
	}
	var source_sha256 := _sha256(JSON.stringify(payload, "", true, true))
	var identity := base.duplicate(true)
	identity["backend_version"] = BACKEND_VERSION + "+" + str(base.get("backend_version", ""))
	identity["solver_version"] = SOLVER_VERSION + "+" + str(base.get("solver_version", ""))
	identity["source_sha256"] = source_sha256
	identity["implementation_artifact_kind"] = str(adapter.get("kind", "gdscript_source"))
	return identity


static func initialize(
	model: Dictionary,
	road: Callable,
	north_m: float = 0.0,
	east_m: float = 0.0,
) -> Dictionary:
	if not _valid_model(model):
		return {"ok": false, "state": PackedFloat64Array(), "error": "Invalid nitro vehicle model"}
	var base: Dictionary = VehicleDynamics.initialize(model, road, north_m, east_m)
	if not bool(base.get("ok", false)):
		return base
	var state := _append_powertrain_state(base.state, model)
	if state.size() != STATE_SIZE:
		return {"ok": false, "state": PackedFloat64Array(), "error": "Nitro initial state could not be constructed"}
	base["state"] = state
	return base


static func make_state(model: Dictionary, pose: Dictionary, road: Callable) -> PackedFloat64Array:
	if not _valid_model(model):
		return PackedFloat64Array()
	var base: PackedFloat64Array = VehicleDynamics.make_state(model, pose, road)
	return _append_powertrain_state(base, model)


static func make_terrain_state(model: Dictionary, pose: Dictionary, road: Callable) -> PackedFloat64Array:
	if not _valid_model(model):
		return PackedFloat64Array()
	var base: PackedFloat64Array = VehicleDynamics.make_terrain_state(model, pose, road)
	return _append_powertrain_state(base, model)


## Advance the engine with a midpoint powertrain update, then advance the body
## through the shared RK4 kernel using the tick's estimated clutch output torque.
## Controls remain caller-owned and unmodified. Nitro has no reverse gear; a raw
## reverse flag is cleared before it reaches the body kernel.
static func step(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
	if not _valid_state(state, model) or not VehicleDynamics._valid_controls(controls):
		return PackedFloat64Array()
	if not road.is_valid() or not is_finite(dt) or dt <= 0.0 or dt > 1.0 / 30.0:
		return PackedFloat64Array()
	# A nitro model has no reverse gear. Treat an unadapted reverse request as
	# neutral power; the owning UI maps its reverse input to the brake control.
	var throttle := float(controls["throttle"]) if not bool(controls["reverse"]) else 0.0
	var wheel_speed := _mean_wheel_speed(state)
	var initial_rates := _engine_rates(
		state[ENGINE_SPEED], state[FUEL_MASS], throttle, wheel_speed,
		model.powertrain, not bool(controls["reverse"]), state[FUEL_MASS] / dt, dt,
		float(model.wheel_spin_inertia_kg_m2),
	)
	var middle_speed := clampf(state[ENGINE_SPEED] + 0.5 * dt * float(initial_rates.speed_rate_rad_s2), 0.0, float(model.powertrain.engine_max_speed_rad_s))
	var middle_fuel := maxf(0.0, state[FUEL_MASS] - 0.5 * dt * float(initial_rates.fuel_flow_kg_per_s))
	var middle_rates := _engine_rates(
		middle_speed, middle_fuel, throttle, wheel_speed,
		model.powertrain, not bool(controls["reverse"]), state[FUEL_MASS] / dt, dt,
		float(model.wheel_spin_inertia_kg_m2),
	)
	var engine_speed_next := clampf(
		state[ENGINE_SPEED] + dt * float(middle_rates.speed_rate_rad_s2),
		0.0,
		float(model.powertrain.engine_max_speed_rad_s),
	)
	var fuel_flow := minf(float(middle_rates.fuel_flow_kg_per_s), state[FUEL_MASS] / dt)
	var fuel_next := maxf(0.0, state[FUEL_MASS] - fuel_flow * dt)
	var body_model := _body_model_with_drive_torque(model, float(middle_rates.wheel_drive_torque_nm))
	var body_controls := _body_controls(
		controls,
		float(middle_rates.wheel_drive_torque_nm) > 0.0,
		float(model.get("suspension_preload_n", 0.0)),
		minf(0.0, float(middle_rates.wheel_drive_torque_nm)),
	)
	var body_next: PackedFloat64Array = VehicleDynamics.step(_body_state(state), body_model, body_controls, dt, road)
	if body_next.size() != BODY_STATE_SIZE:
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(STATE_SIZE)
	for index in BODY_STATE_SIZE:
		result[index] = body_next[index]
	result[ENGINE_SPEED] = engine_speed_next
	result[FUEL_MASS] = fuel_next
	return result if _finite_array(result) else PackedFloat64Array()


static func telemetry(
	state: PackedFloat64Array,
	model: Dictionary,
	road: Callable,
	controls: Dictionary = VehicleDynamics.DEFAULT_CONTROLS,
	dt_s: float = 1.0 / 240.0,
) -> Dictionary:
	if not _valid_state(state, model) or not VehicleDynamics._valid_controls(controls) \
			or not road.is_valid() or not is_finite(dt_s) or dt_s <= 0.0 or dt_s > 1.0 / 30.0:
		return {"ok": false, "error": "Invalid nitro telemetry input"}
	# This is a bounded instantaneous estimate at the requested fixed-step size.
	# It is stateless and does not claim to reproduce the prior step's midpoint rate.
	var current_rates := _engine_rates(
		state[ENGINE_SPEED], state[FUEL_MASS],
		float(controls["throttle"]) if not bool(controls["reverse"]) else 0.0,
		_mean_wheel_speed(state), model.powertrain, not bool(controls["reverse"]),
		state[FUEL_MASS] / dt_s, dt_s, float(model.wheel_spin_inertia_kg_m2),
	)
	var body_model := _body_model_with_drive_torque(model, float(current_rates.wheel_drive_torque_nm))
	var body_controls := _body_controls(
		controls,
		float(current_rates.wheel_drive_torque_nm) > 0.0,
		float(model.get("suspension_preload_n", 0.0)),
		minf(0.0, float(current_rates.wheel_drive_torque_nm)),
	)
	var result: Dictionary = VehicleDynamics.telemetry(_body_state(state), body_model, road, body_controls)
	if not bool(result.get("ok", false)):
		return result
	var preload_n := float(model.get("suspension_preload_n", 0.0))
	var preload_energy := 0.0
	if preload_n > 0.0:
		var suspension_force: PackedFloat64Array = result.suspension_force_n.duplicate()
		for corner in 4:
			suspension_force[corner] += preload_n
			preload_energy += preload_n * state[VehicleDynamics.TRAVEL + corner]
		result["suspension_force_n"] = suspension_force
	var flywheel_energy := 0.5 * float(model.powertrain.engine_rotor_inertia_kg_m2) \
		* state[ENGINE_SPEED] * state[ENGINE_SPEED]
	result["total_energy_j"] = float(result.total_energy_j) + preload_energy + flywheel_energy
	var initial_fuel := float(model.powertrain.initial_fuel_mass_kg)
	var remaining_fuel := clampf(state[FUEL_MASS], 0.0, initial_fuel)
	var engagement := _clutch_engagement(state[ENGINE_SPEED], model.powertrain)
	var engine_spinning := state[ENGINE_SPEED] > ENGINE_STALL_SPEED_RAD_S
	var combustion_torque := float(current_rates.engine_combustion_torque_nm)
	var reflected_wheel_speed := _mean_wheel_speed(state) * float(model.powertrain.gear_ratio)
	var clutch_slip_rad_s := state[ENGINE_SPEED] - reflected_wheel_speed
	var clutch_slip_scale := maxf(1.0, maxf(state[ENGINE_SPEED], absf(reflected_wheel_speed)))
	result["nitro"] = {
		"engine_rpm": state[ENGINE_SPEED] * RPM_PER_RAD_S,
		"engine_speed_rad_s": state[ENGINE_SPEED],
		"engine_running": remaining_fuel > 0.0 and engine_spinning,
		"engine_spinning": engine_spinning,
		"combustion_active": combustion_torque > 0.0,
		"fuel_kg": remaining_fuel,
		"fuel_fraction": remaining_fuel / initial_fuel,
		"throttle_fraction": float(current_rates.accepted_throttle_fraction),
		"fuel_flow_kg_per_s": float(current_rates.fuel_flow_kg_per_s),
		"clutch_engaged": engagement >= 0.5,
		"clutch_engagement": engagement,
		"clutch_slip": clampf(clutch_slip_rad_s / clutch_slip_scale, -1.0, 1.0),
		"clutch_slip_rad_s": clutch_slip_rad_s,
		"engine_torque_nm": combustion_torque,
		"clutch_torque_nm": float(current_rates.clutch_torque_nm),
		"wheel_drive_torque_nm": float(current_rates.wheel_drive_torque_nm),
	}
	return result


static func _append_powertrain_state(body_state: PackedFloat64Array, model: Dictionary) -> PackedFloat64Array:
	if body_state.size() != BODY_STATE_SIZE or not _valid_model(model):
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(STATE_SIZE)
	for index in BODY_STATE_SIZE:
		result[index] = body_state[index]
	result[ENGINE_SPEED] = float(model.powertrain.engine_idle_speed_rad_s)
	result[FUEL_MASS] = float(model.powertrain.initial_fuel_mass_kg)
	return result


static func _body_model_with_drive_torque(model: Dictionary, wheel_drive_torque_nm: float) -> Dictionary:
	var body_model := model.duplicate()
	body_model["drive_torque_per_wheel_nm"] = maxf(0.0, wheel_drive_torque_nm / 4.0)
	# The electric kernel has its own wheel-speed fade. Keep it far above any
	# physically reachable wheel rate so the Nitro curve/clutch remains in charge.
	body_model["drive_torque_fade_rad_s"] = 1.0e12
	body_model["reverse_torque_fraction"] = 0.0
	return body_model


static func _body_controls(
	controls: Dictionary,
	engine_delivers_torque: bool,
	suspension_preload_n: float = 0.0,
	wheel_braking_torque_nm: float = 0.0,
) -> Dictionary:
	var result := controls.duplicate(true)
	result["throttle"] = 1.0 if engine_delivers_torque else 0.0
	result["reverse"] = false
	if controls.has("external_generalized_force") or suspension_preload_n > 0.0 or wheel_braking_torque_nm < 0.0:
		var external := PackedFloat64Array()
		external.resize(VehicleDynamics.GENERALIZED_SIZE)
		if controls.has("external_generalized_force"):
			var caller_external: PackedFloat64Array = controls.external_generalized_force
			for index in external.size():
				external[index] = caller_external[index]
		for corner in 4:
			# A positive preload stores its generalized spring load in the same
			# compression coordinate, so it enters the body RHS with negative sign.
			external[6 + corner] -= suspension_preload_n
			# A negative signed clutch output is wheel-overrun engine braking.
			# The shared generalized-force API takes one torque per wheel-spin DOF.
			external[10 + corner] += wheel_braking_torque_nm * 0.25
		result["external_generalized_force"] = external
	return result


static func _engine_rates(
	engine_speed_rad_s: float,
	fuel_mass_kg: float,
	throttle: float,
	forward_wheel_speed_rad_s: float,
	powertrain: Dictionary,
	drive_enabled: bool = true,
	fuel_flow_limit_kg_per_s: float = INF,
	dt_s: float = INF,
	wheel_spin_inertia_kg_m2: float = 0.0,
) -> Dictionary:
	var speed := maxf(0.0, engine_speed_rad_s)
	var fuel := maxf(0.0, fuel_mass_kg)
	var curve_torque := _torque_at_speed(speed, powertrain)
	var drag := float(powertrain.engine_drag_torque_nm) + float(powertrain.engine_viscous_drag_nm_s_per_rad) * speed
	var idle_torque := 0.0
	# Idle governor stabilizes a running engine but is not a starter. Once the
	# flywheel falls below the stall threshold, combustion cannot restart itself.
	if fuel > 0.0 and speed > ENGINE_STALL_SPEED_RAD_S \
			and speed <= float(powertrain.engine_idle_speed_rad_s):
		var idle_error := maxf(0.0, float(powertrain.engine_idle_speed_rad_s) - speed)
		idle_torque = minf(
			float(powertrain.idle_torque_nm),
			drag + idle_error * float(powertrain.idle_governor_gain_nm_s_per_rad),
		)
	# Fuel does not make a starter: throttle is ineffective below the stall
	# threshold. An explicit service start action must seed the engine state.
	var combustion := (curve_torque * throttle + idle_torque) \
		if fuel > 0.0 and speed > ENGINE_STALL_SPEED_RAD_S else 0.0
	var requested_combustion := combustion
	var engagement := _clutch_engagement(speed, powertrain)
	var gear_ratio := float(powertrain.gear_ratio)
	var efficiency := float(powertrain.gear_efficiency)
	var clutch_slip := speed - forward_wheel_speed_rad_s * gear_ratio
	var requested_clutch := clampf(
		float(powertrain.clutch_slip_stiffness_nm_s_per_rad) * clutch_slip * engagement,
		-float(powertrain.clutch_capacity_nm) * engagement,
		float(powertrain.clutch_capacity_nm) * engagement,
	)
	# Torque follows signed slip: engine-leading torque drives the wheels; wheel
	# overrun torque back-drives the flywheel. Apply gearbox losses in the power
	# flow direction so clutch plus gear never create mechanical energy.
	var clutch_torque := requested_clutch if drive_enabled else 0.0
	var wheel_torque_ratio := gear_ratio * (efficiency if clutch_torque >= 0.0 else 1.0 / efficiency)
	var specific_consumption := float(powertrain.fuel_specific_consumption_kg_per_j)
	var fuel_flow := combustion * speed * specific_consumption
	if fuel_flow > fuel_flow_limit_kg_per_s and speed > 1.0e-12:
		# Fuel-limited within-tick combustion torque scales with the available
		# chemical energy budget; this prevents an empty tank from producing a
		# full tick of engine work. The model smears the cutoff over this tick.
		combustion = maxf(0.0, fuel_flow_limit_kg_per_s / (speed * specific_consumption))
		fuel_flow = combustion * speed * specific_consumption
	var accepted_throttle := 0.0
	if requested_combustion > 0.0 and throttle > 0.0:
		accepted_throttle = clampf(throttle * combustion / requested_combustion, 0.0, 1.0)
	if is_finite(dt_s) and dt_s > 0.0 and wheel_spin_inertia_kg_m2 > 0.0 and clutch_torque != 0.0:
		# Limit clutch impulse to the remaining slip after the engine's free
		# combustion/drag change. Uncoupled wheel rotors provide a lower bound on
		# reflected wheel inertia, so the transfer cannot reverse slip mid-tick.
		var engine_inertia := float(powertrain.engine_rotor_inertia_kg_m2)
		var free_slip_next := clutch_slip + dt_s * (combustion - drag) / engine_inertia
		var slip_budget := 0.0
		if clutch_slip * free_slip_next > 0.0:
			slip_budget = minf(absf(clutch_slip), absf(free_slip_next))
		var effective_inverse_inertia := 1.0 / engine_inertia \
			+ gear_ratio * wheel_torque_ratio / (4.0 * wheel_spin_inertia_kg_m2)
		if not is_finite(effective_inverse_inertia) or effective_inverse_inertia <= 0.0 or slip_budget <= 0.0:
			clutch_torque = 0.0
		else:
			var impulse_safe_torque := slip_budget / (dt_s * effective_inverse_inertia)
			clutch_torque = signf(clutch_torque) * minf(absf(clutch_torque), impulse_safe_torque)
	var speed_rate := (combustion - drag - clutch_torque) / float(powertrain.engine_rotor_inertia_kg_m2)
	if speed <= 0.0 and speed_rate < 0.0:
		speed_rate = 0.0
	var wheel_drive_torque := clutch_torque * wheel_torque_ratio
	return {
		"speed_rate_rad_s2": speed_rate,
		"fuel_flow_kg_per_s": fuel_flow,
		"engine_combustion_torque_nm": combustion,
		"accepted_throttle_fraction": accepted_throttle,
		"clutch_torque_nm": clutch_torque,
		"wheel_drive_torque_nm": wheel_drive_torque,
		"clutch_slip_rad_s": clutch_slip,
	}


static func _torque_at_speed(speed_rad_s: float, powertrain: Dictionary) -> float:
	var speeds: PackedFloat64Array = powertrain.engine_torque_curve_speed_rad_s
	var torques: PackedFloat64Array = powertrain.engine_torque_curve_nm
	if speed_rad_s <= speeds[0]:
		return torques[0]
	for index in range(1, speeds.size()):
		if speed_rad_s <= speeds[index]:
			var fraction := (speed_rad_s - speeds[index - 1]) / (speeds[index] - speeds[index - 1])
			return lerpf(torques[index - 1], torques[index], fraction)
	return torques[torques.size() - 1]


static func _clutch_engagement(engine_speed_rad_s: float, powertrain: Dictionary) -> float:
	var start := float(powertrain.clutch_engage_start_speed_rad_s)
	var full := float(powertrain.clutch_engage_full_speed_rad_s)
	var fraction := clampf((engine_speed_rad_s - start) / (full - start), 0.0, 1.0)
	return fraction * fraction * (3.0 - 2.0 * fraction)


static func _mean_wheel_speed(state: PackedFloat64Array) -> float:
	var sum := 0.0
	for corner in 4:
		sum += state[WHEEL_SPIN + corner] * 0.25
	return sum


static func _body_state(state: PackedFloat64Array) -> PackedFloat64Array:
	if state.size() != STATE_SIZE:
		return PackedFloat64Array()
	var result := PackedFloat64Array()
	result.resize(BODY_STATE_SIZE)
	for index in BODY_STATE_SIZE:
		result[index] = state[index]
	return result


static func _valid_model(model: Dictionary) -> bool:
	if str(model.get("drive_configuration", "")) != "nitro_4wd" or not model.get("powertrain") is Dictionary:
		return false
	if not VehicleDynamics._valid_model(model):
		return false
	var powertrain: Dictionary = model.powertrain
	for key in [
		"engine_idle_speed_rad_s", "engine_max_speed_rad_s", "engine_rotor_inertia_kg_m2",
		"engine_drag_torque_nm", "engine_viscous_drag_nm_s_per_rad", "idle_torque_nm",
		"idle_governor_gain_nm_s_per_rad", "clutch_engage_start_speed_rad_s",
		"clutch_engage_full_speed_rad_s", "clutch_capacity_nm",
		"clutch_slip_stiffness_nm_s_per_rad", "gear_ratio", "gear_efficiency",
		"initial_fuel_mass_kg", "fuel_specific_consumption_kg_per_j",
	]:
		if not powertrain.has(key) or not is_finite(float(powertrain[key])):
			return false
	var positive := [
		"engine_idle_speed_rad_s", "engine_max_speed_rad_s", "engine_rotor_inertia_kg_m2",
		"clutch_engage_start_speed_rad_s", "clutch_engage_full_speed_rad_s",
		"clutch_capacity_nm", "clutch_slip_stiffness_nm_s_per_rad", "gear_ratio",
		"initial_fuel_mass_kg", "fuel_specific_consumption_kg_per_j",
	]
	for key in positive:
		if float(powertrain[key]) <= 0.0:
			return false
	if float(powertrain.gear_efficiency) <= 0.0 or float(powertrain.gear_efficiency) > 1.0 \
			or float(powertrain.engine_idle_speed_rad_s) >= float(powertrain.clutch_engage_start_speed_rad_s) \
			or float(powertrain.clutch_engage_start_speed_rad_s) >= float(powertrain.clutch_engage_full_speed_rad_s) \
			or float(powertrain.clutch_engage_full_speed_rad_s) >= float(powertrain.engine_max_speed_rad_s):
		return false
	for key in ["engine_drag_torque_nm", "engine_viscous_drag_nm_s_per_rad", "idle_torque_nm", "idle_governor_gain_nm_s_per_rad"]:
		if float(powertrain[key]) < 0.0:
			return false
	if not powertrain.get("engine_torque_curve_speed_rad_s") is PackedFloat64Array \
			or not powertrain.get("engine_torque_curve_nm") is PackedFloat64Array:
		return false
	var speeds: PackedFloat64Array = powertrain.engine_torque_curve_speed_rad_s
	var torques: PackedFloat64Array = powertrain.engine_torque_curve_nm
	if speeds.size() != 11 or torques.size() != speeds.size() or not _finite_array(speeds) or not _finite_array(torques):
		return false
	for index in speeds.size():
		if speeds[index] < 0.0 or torques[index] < 0.0 or (index > 0 and speeds[index] <= speeds[index - 1]):
			return false
	return speeds[0] == 0.0 and speeds[speeds.size() - 1] >= float(powertrain.engine_max_speed_rad_s)


static func _valid_state(state: PackedFloat64Array, model: Dictionary) -> bool:
	if state.size() != STATE_SIZE or not _valid_model(model) or not _finite_array(state):
		return false
	return state[ENGINE_SPEED] >= 0.0 \
		and state[ENGINE_SPEED] <= float(model.powertrain.engine_max_speed_rad_s) \
		and state[FUEL_MASS] >= 0.0 \
		and state[FUEL_MASS] <= float(model.powertrain.initial_fuel_mass_kg)


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _sha256(value: String) -> String:
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	hashing.update(value.to_utf8_buffer())
	return hashing.finish().hex_encode()
