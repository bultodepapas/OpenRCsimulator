## Paired source-model probe. Run only under the repository's checked runner.
## A temporary airborne fixture is used to isolate the installed flywheel:
## the real stock parameters and actual NitroDynamics.step are unchanged.
extends SceneTree

const VehicleData := preload("res://physics/ground_vehicle/vehicle_data.gd")
const VehicleDynamics := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const NitroDynamics := preload("res://physics/ground_vehicle/nitro_dynamics.gd")

var failures: int = 0
var checks: int = 0


func _initialize() -> void:
	if not VehicleDynamics.set_backend_override_for_tests(VehicleDynamics.BACKEND_GDSCRIPT_REFERENCE):
		print("FAIL reference backend selection")
		quit(1)
		return
	var loaded: Dictionary = VehicleData.load_vehicle("monster-car-2")
	if not bool(loaded.get("ok", false)):
		print("FAIL stock vehicle load: ", loaded.get("errors", []))
		quit(1)
		return
	var model: Dictionary = loaded.model
	var pose: Dictionary = {"id": "r9-airborne", "north_m": 0.0, "east_m": 0.0,
		"heading_rad": 0.0, "vehicle_up_m": 5.0}
	var road: Callable = Callable(self, "_flat_road")
	var start: PackedFloat64Array = NitroDynamics.make_state(model, pose, road)
	if start.size() != NitroDynamics.STATE_SIZE:
		print("FAIL start state")
		quit(1)
		return
	var initial_telemetry: Dictionary = NitroDynamics.telemetry(start, model, road)
	_check("airborne initial state; no wheel or hull contacts", _airborne(initial_telemetry))
	_check("initial rotor is idle and disengaged", is_equal_approx(start[NitroDynamics.ENGINE_SPEED],
		float(model.powertrain.engine_idle_speed_rad_s))
		and float(initial_telemetry.nitro.clutch_engagement) == 0.0)
	var initial_w: float = start[NitroDynamics.ENGINE_SPEED]
	var inertia: float = float(model.powertrain.engine_rotor_inertia_kg_m2)
	var neutral: Dictionary = _controls(0.0)
	var full: Dictionary = _controls(1.0)
	var results: Array[Dictionary] = []
	for n: int in [1, 2, 4, 8]:
		var h: float = (1.0 / 240.0) / float(n)
		var a: PackedFloat64Array = start.duplicate()
		var b: PackedFloat64Array = start.duplicate()
		var all_disengaged: bool = true
		var all_airborne: bool = true
		for i in n:
			a = NitroDynamics.step(a, model, neutral, h, road)
			b = NitroDynamics.step(b, model, full, h, road)
			if a.size() != NitroDynamics.STATE_SIZE or b.size() != NitroDynamics.STATE_SIZE:
				print("FAIL rejected step n=%d i=%d" % [n, i])
				quit(1)
				return
			var ta: Dictionary = NitroDynamics.telemetry(a, model, road, neutral, h)
			var tb: Dictionary = NitroDynamics.telemetry(b, model, road, full, h)
			if not bool(ta.get("ok", false)) or not bool(tb.get("ok", false)):
				print("FAIL telemetry n=%d i=%d" % [n, i])
				quit(1)
				return
			all_airborne = all_airborne and _airborne(ta) and _airborne(tb)
			all_disengaged = all_disengaged and float(ta.nitro.clutch_engagement) == 0.0 \
				and float(tb.nitro.clutch_engagement) == 0.0 \
				and float(ta.nitro.wheel_drive_torque_nm) == 0.0 \
				and float(tb.nitro.wheel_drive_torque_nm) == 0.0
		var body_a: PackedFloat64Array = a.slice(0, NitroDynamics.BODY_STATE_SIZE)
		var body_b: PackedFloat64Array = b.slice(0, NitroDynamics.BODY_STATE_SIZE)
		var same_body: bool = body_a.to_byte_array() == body_b.to_byte_array()
		var h_delta_neutral: float = inertia * (a[NitroDynamics.ENGINE_SPEED] - initial_w)
		var h_delta_full: float = inertia * (b[NitroDynamics.ENGINE_SPEED] - initial_w)
		_check("subdivision %d: airborne, zero clutch, unchanged body response" % n,
			all_airborne and all_disengaged and same_body)
		_check("subdivision %d: neutral rotor steady and full-throttle rotor speeds up" % n,
			absf(h_delta_neutral) < 1.0e-12 and h_delta_full > 0.0)
		results.append({"substeps": n, "dt_s": h, "airborne": all_airborne,
			"clutch_disengaged": all_disengaged, "body_bytes_equal": same_body,
			"neutral_engine_rpm": a[NitroDynamics.ENGINE_SPEED] * NitroDynamics.RPM_PER_RAD_S,
			"full_engine_rpm": b[NitroDynamics.ENGINE_SPEED] * NitroDynamics.RPM_PER_RAD_S,
			"neutral_flywheel_delta_h_nms": h_delta_neutral,
			"full_flywheel_delta_h_nms": h_delta_full})
	# Check the one-step independent scalar calculation from the shipped JSON.
	_check("240 Hz rotor increment agrees with independent source-equation oracle",
		absf(float(results[0].full_flywheel_delta_h_nms) - 0.000502952979828575) < 1.0e-10)
	# Empty-fuel rundown removes combustion from this accounting example. It is
	# still conditional on whether the declared drag is internal to the truck.
	var dry_start: PackedFloat64Array = start.duplicate()
	dry_start[NitroDynamics.ENGINE_SPEED] = 700.0
	dry_start[NitroDynamics.FUEL_MASS] = 0.0
	var wet_start: PackedFloat64Array = dry_start.duplicate()
	wet_start[NitroDynamics.FUEL_MASS] = float(model.powertrain.initial_fuel_mass_kg)
	var dry_next: PackedFloat64Array = NitroDynamics.step(dry_start, model, full, 1.0 / 240.0, road)
	var wet_next: PackedFloat64Array = NitroDynamics.step(wet_start, model, full, 1.0 / 240.0, road)
	if dry_next.size() != NitroDynamics.STATE_SIZE or wet_next.size() != NitroDynamics.STATE_SIZE:
		print("FAIL empty-fuel rundown step rejected")
		quit(1)
		return
	var dry_telemetry: Dictionary = NitroDynamics.telemetry(dry_next, model, road, full)
	var wet_telemetry: Dictionary = NitroDynamics.telemetry(wet_next, model, road, full)
	if not bool(dry_telemetry.get("ok", false)) or not bool(wet_telemetry.get("ok", false)):
		print("FAIL empty-fuel rundown telemetry")
		quit(1)
		return
	var dry_dh: float = inertia * (dry_next[NitroDynamics.ENGINE_SPEED] - 700.0)
	var wet_dh: float = inertia * (wet_next[NitroDynamics.ENGINE_SPEED] - 700.0)
	var same_rundown_body: bool = dry_next.slice(0, NitroDynamics.BODY_STATE_SIZE).to_byte_array() \
		== wet_next.slice(0, NitroDynamics.BODY_STATE_SIZE).to_byte_array()
	_check("empty-fuel engine rundown has zero combustion and zero clutch output",
		_airborne(dry_telemetry) and float(dry_telemetry.nitro.engine_torque_nm) == 0.0 \
		and float(dry_telemetry.nitro.wheel_drive_torque_nm) == 0.0)
	_check("fuelled and empty cases have equal body bytes, but opposite engine momentum change",
		_airborne(wet_telemetry) and same_rundown_body and dry_dh < 0.0 and wet_dh > 0.0)
	_check("empty-fuel rundown agrees with independent drag midpoint calculation",
		absf(dry_dh - (-0.00007124554687500222)) < 1.0e-10)
	print("R9_REACTION_RESULT=", JSON.stringify({"fixture": "synthetic-airborne-stock-monster-car-2",
		"identity": NitroDynamics.backend_identity(), "model_identity": loaded.identity,
		"elapsed_s": 1.0 / 240.0, "results": results, "rundown": {
			"initial_engine_rad_s": 700.0, "no_fuel_delta_h_nms": dry_dh,
			"fuelled_delta_h_nms": wet_dh, "body_bytes_equal": same_rundown_body},
		"failures": failures}))
	print("R9 NITRO: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _controls(throttle: float) -> Dictionary:
	return {"throttle": throttle, "steering": 0.0, "brake": 0.0, "reverse": false}


func _flat_road(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 0.025, "surface_id": "r9-flat"}


func _airborne(telemetry: Dictionary) -> bool:
	if not bool(telemetry.get("ok", false)) or not bool(telemetry.get("airborne", false)):
		return false
	var wheel: PackedByteArray = telemetry.wheel_in_contact
	var hull: PackedByteArray = telemetry.hull_in_contact
	return wheel.count(1) == 0 and hull.count(1) == 0


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS: " if passed else "FAIL: ") + label)
	if not passed:
		failures += 1
