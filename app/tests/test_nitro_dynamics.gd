## Monster Car 2 Nitro kernel: source ride support, fuel, braking, and replay.
## Run with `.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_nitro_dynamics.gd`.
extends SceneTree

const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")

const DT_240 := 1.0 / 240.0
const DT_120 := 1.0 / 120.0
const DT_480 := 1.0 / 480.0
const FORWARD_SPEED := 3
const ENGINE_SPEED := NitroDynamics.ENGINE_SPEED
const FUEL_MASS := NitroDynamics.FUEL_MASS

var _checks := 0
var _failures := 0


func _initialize() -> void:
	var loaded := VehicleData.load_vehicle("monster-car-2")
	_check("Monster Car 2 data loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded.model
	var road := Callable(self, "_flat_road")
	_test_backend_identity()
	_test_preloaded_support(loaded, road)
	var initialized := NitroDynamics.initialize(model, road, 0.0, 0.0)
	_check("initialized state contains body, engine, and fuel float64 fields",
		bool(initialized.get("ok", false)) and initialized.state.size() == NitroDynamics.STATE_SIZE)
	if not bool(initialized.get("ok", false)):
		quit(1)
		return
	var start: PackedFloat64Array = initialized.state
	var initial_telemetry: Dictionary = NitroDynamics.telemetry(start, model, road)
	_check("source ride datum is zero suspension compression at nominal gravity",
		absf(start[13]) < 1.0e-9 and absf(start[14]) < 1.0e-9
		and absf(start[15]) < 1.0e-9 and absf(start[16]) < 1.0e-9)
	_check("engine starts at idle with full fuel and four tire contacts",
		bool(initial_telemetry.get("ok", false))
		and is_equal_approx(float(initial_telemetry.nitro.engine_rpm), 4500.0)
		and is_equal_approx(float(initial_telemetry.nitro.fuel_fraction), 1.0)
		and initial_telemetry.wheel_in_contact.count(1) == 4)
	var initial_body_telemetry: Dictionary = VehicleDynamics.telemetry(
		NitroDynamics._body_state(start), model, road,
		NitroDynamics._body_controls(VehicleDynamics.DEFAULT_CONTROLS, false, float(model.suspension_preload_n)),
	)
	var initial_expected_added_energy := 0.5 * float(model.powertrain.engine_rotor_inertia_kg_m2) \
		* start[ENGINE_SPEED] * start[ENGINE_SPEED]
	_check("mechanical total energy includes the spinning Nitro flywheel",
		bool(initial_telemetry.get("ok", false)) and bool(initial_body_telemetry.get("ok", false))
		and absf(float(initial_telemetry.total_energy_j) - float(initial_body_telemetry.total_energy_j)
			- initial_expected_added_energy) < 1.0e-7,
		"added=%.8f J, expected=%.8f J" % [
			float(initial_telemetry.get("total_energy_j", NAN)) - float(initial_body_telemetry.get("total_energy_j", NAN)),
			initial_expected_added_energy,
		])

	var idle := _run(start, model, _controls(), road, DT_240, 240)
	_check("idle remains steady without unintended restart or propulsion",
		idle.size() == NitroDynamics.STATE_SIZE
		and absf(idle[ENGINE_SPEED] - start[ENGINE_SPEED]) < 1.0e-8
		and absf(idle[FORWARD_SPEED]) < 5.0e-5,
		"u=%.8f m/s, RPM delta=%.8f" % [idle[FORWARD_SPEED] if not idle.is_empty() else NAN,
			(idle[ENGINE_SPEED] - start[ENGINE_SPEED]) if not idle.is_empty() else NAN])

	var throttle := _controls(1.0)
	var driven := _run(start, model, throttle, road, DT_240, 240)
	var drive_telemetry := NitroDynamics.telemetry(driven, model, road, throttle) if not driven.is_empty() else {}
	_check("240 Hz sustained throttle moves the truck and spends fuel",
		driven.size() == NitroDynamics.STATE_SIZE and driven[FORWARD_SPEED] > 0.25
		and driven[ENGINE_SPEED] > start[ENGINE_SPEED] and driven[FUEL_MASS] < start[FUEL_MASS]
		and bool(drive_telemetry.get("ok", false))
		and float(drive_telemetry.get("nitro", {}).get("clutch_engagement", 0.0)) > 0.0,
		"u=%.3f m/s, RPM=%.0f, fuel=%.6f kg" % [
			driven[FORWARD_SPEED] if not driven.is_empty() else NAN,
			driven[ENGINE_SPEED] * NitroDynamics.RPM_PER_RAD_S if not driven.is_empty() else NAN,
			driven[FUEL_MASS] if not driven.is_empty() else NAN,
		])
	_check("Nitro effect telemetry reports accepted throttle, bounded fuel flow, and signed slip",
		bool(drive_telemetry.get("ok", false))
		and float(drive_telemetry.get("nitro", {}).get("throttle_fraction", -1.0)) == 1.0
		and float(drive_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", INF)) >= 0.0
		and float(drive_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", INF)) <= driven[FUEL_MASS] / DT_240
		and absf(float(drive_telemetry.get("nitro", {}).get("clutch_slip", 2.0))) <= 1.0
		and float(drive_telemetry.get("nitro", {}).get("clutch_slip", 2.0)) > 0.0,
		"throttle=%.3f, flow=%.7f kg/s, slip=%.4f" % [
			float(drive_telemetry.get("nitro", {}).get("throttle_fraction", NAN)),
			float(drive_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", NAN)),
			float(drive_telemetry.get("nitro", {}).get("clutch_slip", NAN)),
		])

	var braked := _run(driven, model, _controls(0.0, 0.0, 1.0), road, DT_240, 120)
	_check("four-wheel braking reduces speed after the sustained run",
		braked.size() == NitroDynamics.STATE_SIZE and braked[FORWARD_SPEED] < driven[FORWARD_SPEED])
	var reverse_controls := _controls(1.0)
	reverse_controls.reverse = true
	var reverse_step := _run(start, model, reverse_controls, road, DT_240, 240)
	_check("raw reverse input cannot drive the forward-only Nitro transmission backward or forward",
		reverse_step.size() == NitroDynamics.STATE_SIZE
		and reverse_step[FORWARD_SPEED] <= 1.0e-8
		and absf(reverse_step[ENGINE_SPEED] - start[ENGINE_SPEED]) < 1.0e-8,
		"u=%.8f m/s, RPM delta=%.8f" % [reverse_step[FORWARD_SPEED] if not reverse_step.is_empty() else NAN,
			(reverse_step[ENGINE_SPEED] - start[ENGINE_SPEED]) if not reverse_step.is_empty() else NAN])

	var replay_a := _run(start, model, throttle, road, DT_240, 120)
	replay_a = _run(replay_a, model, _controls(0.0, 0.0, 0.75), road, DT_240, 60)
	var replay_b := _run(start, model, throttle, road, DT_240, 120)
	replay_b = _run(replay_b, model, _controls(0.0, 0.0, 0.75), road, DT_240, 60)
	_check("complete Nitro state replays bit-for-bit from the same control tape",
		replay_a.size() == NitroDynamics.STATE_SIZE and replay_a.to_byte_array() == replay_b.to_byte_array())

	var refined_120 := _run(start, model, throttle, road, DT_120, 120)
	var refined_240 := _run(start, model, throttle, road, DT_240, 240)
	var refinement_ok := refined_120.size() == NitroDynamics.STATE_SIZE and refined_240.size() == NitroDynamics.STATE_SIZE
	var speed_delta := absf(refined_120[FORWARD_SPEED] - refined_240[FORWARD_SPEED]) if refinement_ok else INF
	var rpm_delta := absf(refined_120[ENGINE_SPEED] - refined_240[ENGINE_SPEED]) * NitroDynamics.RPM_PER_RAD_S if refinement_ok else INF
	_check("powertrain converges under 120/240 Hz step refinement",
		refinement_ok and speed_delta < 0.08 and rpm_delta < 25.0,
		"Δu=%.4f m/s, ΔRPM=%.1f" % [speed_delta, rpm_delta])
	var refined_480 := _run(start, model, throttle, road, DT_480, 480)
	refinement_ok = refined_480.size() == NitroDynamics.STATE_SIZE and refined_240.size() == NitroDynamics.STATE_SIZE
	speed_delta = absf(refined_480[FORWARD_SPEED] - refined_240[FORWARD_SPEED]) if refinement_ok else INF
	rpm_delta = absf(refined_480[ENGINE_SPEED] - refined_240[ENGINE_SPEED]) * NitroDynamics.RPM_PER_RAD_S if refinement_ok else INF
	_check("powertrain converges under 240/480 Hz step refinement",
		refinement_ok and speed_delta < 0.08 and rpm_delta < 25.0,
		"Δu=%.4f m/s, ΔRPM=%.1f" % [speed_delta, rpm_delta])

	_test_fuel_limits(model, start, road)
	_test_bidirectional_clutch(model, start, road)
	print("Nitro dynamics: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_preloaded_support(base_loaded: Dictionary, road: Callable) -> void:
	var preload_n := float(base_loaded.model.get("suspension_preload_n", -1.0))
	_check("preload derives from estimated sprung mass at nominal gravity",
		preload_n > 12.0 and preload_n < 12.3
		and absf(VehicleDynamics._static_travel(base_loaded.model)) < 1.0e-9)
	var controls := NitroDynamics._body_controls(_controls(), false, preload_n)
	var external: PackedFloat64Array = controls.get("external_generalized_force", PackedFloat64Array())
	_check("Nitro applies source preload privately to generalized suspension forces",
		external.size() == VehicleDynamics.GENERALIZED_SIZE
		and external.slice(6, 10) == PackedFloat64Array([-preload_n, -preload_n, -preload_n, -preload_n]))
	for case in [
		{"label": "zero gravity settles toward the droop stop", "gravity_scale": 0.0, "spring_scale": 1.0},
		{"label": "double gravity remains inside compliant bump travel", "gravity_scale": 2.0, "spring_scale": 1.0},
		{"label": "half spring scale retains constant source preload", "gravity_scale": 1.0, "spring_scale": 0.5},
	]:
		var experiment := VehicleData.with_experiment(base_loaded, _knobs(float(case.gravity_scale), float(case.spring_scale)))
		var pose := {"id": "lab-support", "north_m": 0.0, "east_m": 0.0, "heading_rad": 0.0, "vehicle_up_m": 0.0}
		var state := NitroDynamics.make_terrain_state(experiment.model, pose, road) if experiment.get("ok", false) else PackedFloat64Array()
		_check(str(case.label), state.size() == NitroDynamics.STATE_SIZE,
			"travel=%.5f m" % state[13] if state.size() == NitroDynamics.STATE_SIZE else str(experiment.get("errors", [])))
		if state.size() == NitroDynamics.STATE_SIZE and float(case.gravity_scale) == 0.0:
			var geometry := VehicleDynamics._corner_geometry(
				NitroDynamics._body_state(state), experiment.model, 0.0, 0.0, 0.0)
			var wheel_clearance_error := INF
			if geometry.get("ok", false):
				wheel_clearance_error = 0.0
				for hub: PackedFloat64Array in geometry.hub_position_body:
					var center_down := state[2] + hub[2]
					wheel_clearance_error = maxf(wheel_clearance_error,
						absf(center_down + float(experiment.model.tire_radius_m)))
			_check("zero-gravity wheel centers remain on the unmodified road plane",
				wheel_clearance_error < 1.0e-7, "center error=%.9f m" % wheel_clearance_error)
			var startup := _run(state, experiment.model, _controls(), road, DT_240, 240)
			var startup_telemetry := NitroDynamics.telemetry(startup, experiment.model, road) if not startup.is_empty() else {}
			_check("zero-gravity preloaded wheels start clear and avoid a launch impulse",
				startup.size() == NitroDynamics.STATE_SIZE and absf(startup[FORWARD_SPEED]) < 0.01
				and absf(startup[5]) < 0.01 and absf(startup[2] - state[2]) < 0.01
				and bool(startup_telemetry.get("ok", false)))


func _test_backend_identity() -> void:
	var identity := NitroDynamics.backend_identity()
	var adapter := VehicleDynamics._reference_implementation_artifact("res://physics/ground_vehicle/nitro_dynamics.gd")
	var body := VehicleDynamics._reference_implementation_artifact("res://physics/ground_vehicle/vehicle_dynamics.gd")
	var expected_payload := {
		"adapter_source_sha256": str(adapter.get("sha256", "")),
		"body_source_sha256": str(body.get("sha256", "")),
		"body_backend": VehicleDynamics.backend_identity(),
	}
	var expected_sha256: String = NitroDynamics._sha256(JSON.stringify(expected_payload, "", true, true))
	_check("Nitro backend identity pins both adapter and body GDScript artifacts",
		str(identity.get("source_sha256", "")) == expected_sha256 and expected_sha256.length() == 64)


func _test_fuel_limits(model: Dictionary, start: PackedFloat64Array, road: Callable) -> void:
	var tiny_fuel := 1.0e-12
	var rates: Dictionary = NitroDynamics._engine_rates(
		start[ENGINE_SPEED], tiny_fuel, 1.0, 0.0, model.powertrain, true, tiny_fuel / DT_240)
	var combustion_work_j := float(rates.engine_combustion_torque_nm) * start[ENGINE_SPEED] * DT_240
	var available_j := tiny_fuel / float(model.powertrain.fuel_specific_consumption_kg_per_j)
	_check("near-empty fuel caps combustion work to available chemical energy",
		combustion_work_j >= 0.0 and combustion_work_j <= available_j * (1.0 + 1.0e-9))
	var near_empty := start.duplicate()
	near_empty[FUEL_MASS] = tiny_fuel
	var limited_telemetry := NitroDynamics.telemetry(near_empty, model, road, _controls(1.0), DT_240)
	_check("effect telemetry throttle and fuel flow reflect the near-empty accepted limit",
		bool(limited_telemetry.get("ok", false))
		and float(limited_telemetry.get("nitro", {}).get("throttle_fraction", 1.0)) < 1.0
		and float(limited_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", INF)) <= tiny_fuel / DT_240,
		"throttle=%.8f, flow=%.12f kg/s" % [
			float(limited_telemetry.get("nitro", {}).get("throttle_fraction", NAN)),
			float(limited_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", NAN)),
		])
	var depleted := start.duplicate()
	depleted[FUEL_MASS] = tiny_fuel
	depleted = NitroDynamics.step(depleted, model, _controls(1.0), DT_240, road)
	_check("fuel depletion reaches zero without negative mass",
		depleted.size() == NitroDynamics.STATE_SIZE and depleted[FUEL_MASS] == 0.0)
	if depleted.size() != NitroDynamics.STATE_SIZE:
		return
	var stopped := depleted.duplicate()
	stopped[ENGINE_SPEED] = 0.0
	stopped[FUEL_MASS] = float(model.powertrain.initial_fuel_mass_kg)
	var after := NitroDynamics.step(stopped, model, _controls(), DT_240, road)
	var telemetry := NitroDynamics.telemetry(depleted, model, road)
	_check("stalled engine does not auto-restart while fuel remains",
		after.size() == NitroDynamics.STATE_SIZE and after[ENGINE_SPEED] == 0.0)
	var throttled_stall := NitroDynamics.step(stopped, model, _controls(1.0), DT_240, road)
	var stalled_telemetry := NitroDynamics.telemetry(stopped, model, road, _controls(1.0), DT_240)
	_check("full throttle cannot restart a stopped engine or consume fuel",
		throttled_stall.size() == NitroDynamics.STATE_SIZE
		and throttled_stall[ENGINE_SPEED] == 0.0
		and throttled_stall[FUEL_MASS] == stopped[FUEL_MASS]
		and bool(stalled_telemetry.get("ok", false))
		and not bool(stalled_telemetry.get("nitro", {}).get("engine_running", true))
		and float(stalled_telemetry.get("nitro", {}).get("throttle_fraction", -1.0)) == 0.0
		and float(stalled_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", INF)) == 0.0,
		"rpm=%.1f, fuel delta=%.9f kg, flow=%.9f kg/s" % [
			throttled_stall[ENGINE_SPEED] * NitroDynamics.RPM_PER_RAD_S if throttled_stall.size() == NitroDynamics.STATE_SIZE else NAN,
			(stopped[FUEL_MASS] - throttled_stall[FUEL_MASS]) if throttled_stall.size() == NitroDynamics.STATE_SIZE else NAN,
			float(stalled_telemetry.get("nitro", {}).get("fuel_flow_kg_per_s", NAN)),
		])
	_check("empty tank telemetry reports no combustion and zero fuel fraction",
		bool(telemetry.get("ok", false))
		and float(telemetry.get("nitro", {}).get("fuel_fraction", 1.0)) == 0.0
		and float(telemetry.get("nitro", {}).get("engine_torque_nm", INF)) == 0.0)


func _test_bidirectional_clutch(model: Dictionary, start: PackedFloat64Array, road: Callable) -> void:
	var powertrain: Dictionary = model.powertrain
	var ratio := float(powertrain.gear_ratio)
	var rotor_inertia := float(powertrain.engine_rotor_inertia_kg_m2)
	var wheel_inertia := float(model.wheel_spin_inertia_kg_m2)
	var dt := 1.0 / 30.0
	for case in [
		{"label": "engine-leading clutch transfers forward torque without net energy", "engine_speed": 1200.0, "slip": 10.0, "drive_sign": 1.0},
		{"label": "wheel overrun back-drives engine with dissipative negative torque", "engine_speed": 1200.0, "slip": -10.0, "drive_sign": -1.0},
	]:
		var engine_speed := float(case.engine_speed)
		var wheel_speed := (engine_speed - float(case.slip)) / ratio
		var rates: Dictionary = NitroDynamics._engine_rates(
			engine_speed, 0.1, 0.0, wheel_speed, powertrain, true, INF, dt, wheel_inertia)
		var clutch_torque := float(rates.clutch_torque_nm)
		var clutch_power_w := -clutch_torque * engine_speed \
			+ float(rates.wheel_drive_torque_nm) * wheel_speed
		var engine_next := engine_speed + dt * float(rates.speed_rate_rad_s2)
		var wheel_next := wheel_speed + dt * float(rates.wheel_drive_torque_nm) / (4.0 * wheel_inertia)
		var slip_next := engine_next - ratio * wheel_next
		var direction_ok := signf(clutch_torque) == float(case.drive_sign)
		var no_cross := float(case.drive_sign) > 0.0 and slip_next >= -1.0e-8 \
			or float(case.drive_sign) < 0.0 and slip_next <= 1.0e-8
		_check(str(case.label), direction_ok and clutch_power_w <= 1.0e-9 and no_cross,
			"T=%.6f Nm, Pnet=%.7f W, slip %.3f→%.6f rad/s" % [clutch_torque, clutch_power_w, float(case.slip), slip_next])
	var overrun_state := start.duplicate()
	overrun_state[ENGINE_SPEED] = 1200.0
	var overrun_wheel_speed := (overrun_state[ENGINE_SPEED] + 100.0) / ratio
	for corner in 4:
		overrun_state[NitroDynamics.WHEEL_SPIN + corner] = overrun_wheel_speed
	var telemetry := NitroDynamics.telemetry(overrun_state, model, road, _controls(), DT_240)
	_check("overrun telemetry reports negative normalized slip and back-drive torque",
		bool(telemetry.get("ok", false))
		and float(telemetry.get("nitro", {}).get("clutch_slip", 0.0)) < 0.0
		and float(telemetry.get("nitro", {}).get("clutch_slip", 0.0)) >= -1.0
		and float(telemetry.get("nitro", {}).get("clutch_slip_rad_s", 0.0)) < 0.0
		and float(telemetry.get("nitro", {}).get("clutch_torque_nm", 0.0)) < 0.0
		and float(telemetry.get("nitro", {}).get("wheel_drive_torque_nm", 0.0)) < 0.0,
		"slip=%.4f, torque=%.5f Nm, wheel=%.5f Nm" % [
			float(telemetry.get("nitro", {}).get("clutch_slip", NAN)),
			float(telemetry.get("nitro", {}).get("clutch_torque_nm", NAN)),
			float(telemetry.get("nitro", {}).get("wheel_drive_torque_nm", NAN)),
		])


func _run(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable, dt: float, count: int) -> PackedFloat64Array:
	if state.size() != NitroDynamics.STATE_SIZE:
		return PackedFloat64Array()
	var result := state.duplicate()
	for _tick in count:
		result = NitroDynamics.step(result, model, controls, dt, road)
		if result.size() != NitroDynamics.STATE_SIZE:
			return PackedFloat64Array()
	return result


func _knobs(gravity_scale: float, spring_scale: float) -> Dictionary:
	return {"gravity_scale": gravity_scale, "grip_scale": 1.0, "spring_scale": spring_scale,
		"damper_scale": 1.0, "ballast_kg": 0.0, "ballast_height_m": 0.10}


func _controls(throttle := 0.0, steering := 0.0, brake := 0.0, reverse := false) -> Dictionary:
	return {"throttle": throttle, "steering": steering, "brake": brake, "reverse": reverse}


func _flat_road(_north_m: float, _east_m: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 0.025, "surface_id": "nitro-test-asphalt"}


func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	print(("PASS: " if passed else "FAIL: ") + label + ("" if detail.is_empty() else "  " + detail))
	if not passed:
		_failures += 1
