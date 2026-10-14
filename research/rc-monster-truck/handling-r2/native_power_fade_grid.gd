extends SceneTree

## Final bounded native full-throttle startup fade scan.
## Each state advance goes through Vehicle.step; no reference evaluator clone.

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const DT := 1.0 / 240.0
const DURATION_S := 6.0
const TARGET_SPEED_MPS := 3.0
const CASES := [
	{"torque_nm": 3.0, "fade_rad_s": 160.0},
	{"torque_nm": 4.2, "fade_rad_s": 110.0},
	{"torque_nm": 4.5, "fade_rad_s": 110.0},
	{"torque_nm": 4.2, "fade_rad_s": 115.0},
]

func _initialize() -> void:
	_run.call_deferred()

func _road(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "handling_r2_native_power_scan"}

func _run() -> void:
	var backend: Dictionary = Vehicle.backend_identity()
	if str(backend.get("backend", "")) != Vehicle.BACKEND_NATIVE:
		_fail("Native backend is not active: " + JSON.stringify(backend))
		return
	var loaded: Dictionary = Data.load_default()
	if not bool(loaded.get("ok", false)):
		_fail("Default vehicle data failed to load: " + JSON.stringify(loaded.get("errors", [])))
		return
	var cases: Array[Dictionary] = []
	for case in CASES:
		var torque_nm := float(case.torque_nm)
		var fade_rad_s := float(case.fade_rad_s)
		var result := _case(torque_nm, fade_rad_s, loaded.model)
		if not bool(result.get("ok", false)):
			_fail("Torque case failed: " + JSON.stringify(result))
			return
		cases.append(result)
		print("CASE ", JSON.stringify(result))
	var output := {
		"backend_identity": backend,
		"vehicle_descriptor_identity": loaded.get("identity", {}),
		"native_evaluator_used": true,
		"advance_method": "Vehicle.step at 240 Hz; runtime dispatch pinned to native backend",
		"road": {"mu": 0.85, "rolling_multiplier": 1.0, "flat": true},
		"initialization": "Vehicle.initialize supported flat spawn; full throttle from rest",
		"duration_s": DURATION_S,
	"cases_requested": CASES,
		"cases": cases,
	}
	print("RESULT_JSON ", JSON.stringify(output))
	quit(0)

func _case(torque_nm: float, fade_rad_s: float, source_model: Dictionary) -> Dictionary:
	var model: Dictionary = source_model.duplicate(true)
	model["drive_torque_per_wheel_nm"] = torque_nm
	model["drive_torque_fade_rad_s"] = fade_rad_s
	var initialized: Dictionary = Vehicle.initialize(model, _road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		return {"ok": false, "torque_per_wheel_nm": torque_nm, "error": "initialize failed: " + JSON.stringify(initialized)}
	var state: PackedFloat64Array = initialized["state"].duplicate()
	var controls := {"throttle": 1.0, "steering": 0.0, "brake": 0.0, "reverse": false}
	var initial_telemetry: Dictionary = Vehicle.telemetry(state, model, _road, controls)
	if not bool(initial_telemetry.get("ok", false)):
		return {"ok": false, "torque_per_wheel_nm": torque_nm, "error": "initial native telemetry failed: " + JSON.stringify(initial_telemetry)}
	var initial_wheel_contacts := _contact_count(initial_telemetry.get("wheel_in_contact", PackedByteArray()))
	var initial_hull_contacts := _contact_count(initial_telemetry.get("hull_in_contact", PackedByteArray()))
	if initial_wheel_contacts != 4 or initial_hull_contacts != 0:
		return {"ok": false, "torque_per_wheel_nm": torque_nm,
			"error": "initialized fixture is not supported on four tires: wheels=%d hull=%d" % [initial_wheel_contacts, initial_hull_contacts]}
	var start_energy := float(initial_telemetry["total_energy_j"])
	var energy_min := start_energy
	var energy_max := start_energy
	var final_energy := start_energy
	var max_speed := float(initial_telemetry["speed_m_per_s"])
	var time_to_target := 0.0 if max_speed >= TARGET_SPEED_MPS else -1.0
	var min_upright_cos := _upright_cos(state)
	var initial_pitch := _pitch_rad(state)
	var max_abs_pitch := absf(initial_pitch)
	var peak_pitch := initial_pitch
	var peak_pitch_s := 0.0
	var max_hull_count := _contact_count(initial_telemetry.get("hull_in_contact", PackedByteArray()))
	var hull_contact_ticks := 1 if max_hull_count > 0 else 0
	var first_hull_contact_s := 0.0 if max_hull_count > 0 else -1.0
	var airborne_ticks := 1 if bool(initial_telemetry.get("airborne", false)) else 0
	var peak_sweeps := int(initial_telemetry.get("friction_sweeps_used", 0))
	var final_speed := max_speed
	var first_inverted_s := -1.0
	var pitch_samples: Array[Dictionary] = [{"t_s": 0.0, "pitch_deg": rad_to_deg(initial_pitch),
		"upright_cos": min_upright_cos, "speed_mps": max_speed}]
	var ticks_run := 0
	var termination := "duration_complete"
	for tick in int(round(DURATION_S / DT)):
		state = Vehicle.step(state, model, controls, DT, _road)
		if state.size() != Vehicle.STATE_SIZE or not _finite(state):
			termination = "step_failed_or_nonfinite"
			break
		var telemetry: Dictionary = Vehicle.telemetry(state, model, _road, controls)
		if not bool(telemetry.get("ok", false)):
			termination = "native_telemetry_failed"
			break
		ticks_run = tick + 1
		var speed := float(telemetry["speed_m_per_s"])
		final_speed = speed
		max_speed = maxf(max_speed, speed)
		if time_to_target < 0.0 and speed >= TARGET_SPEED_MPS:
			time_to_target = float(tick + 1) * DT
		var upright := _upright_cos(state)
		min_upright_cos = minf(min_upright_cos, upright)
		if first_inverted_s < 0.0 and upright < 0.0:
			first_inverted_s = float(tick + 1) * DT
		var pitch := _pitch_rad(state)
		if absf(pitch) > max_abs_pitch:
			max_abs_pitch = absf(pitch)
			peak_pitch = pitch
			peak_pitch_s = float(tick + 1) * DT
		if (tick + 1) % 12 == 0:
			pitch_samples.append({"t_s": float(tick + 1) * DT, "pitch_deg": rad_to_deg(pitch),
				"upright_cos": upright, "speed_mps": speed})
		var hull_count := _contact_count(telemetry.get("hull_in_contact", PackedByteArray()))
		max_hull_count = maxi(max_hull_count, hull_count)
		if hull_count > 0:
			hull_contact_ticks += 1
			if first_hull_contact_s < 0.0:
				first_hull_contact_s = float(tick + 1) * DT
		if bool(telemetry.get("airborne", false)):
			airborne_ticks += 1
		var energy := float(telemetry["total_energy_j"])
		final_energy = energy
		energy_min = minf(energy_min, energy)
		energy_max = maxf(energy_max, energy)
		peak_sweeps = maxi(peak_sweeps, int(telemetry.get("friction_sweeps_used", 0)))
	return {
		"ok": true,
		"torque_per_wheel_nm": torque_nm,
		"torque_fade_rad_s": fade_rad_s,
		"total_stall_torque_nm": torque_nm * 4.0,
		"ticks_run": ticks_run,
		"duration_s": float(ticks_run) * DT,
		"termination": termination,
		"time_to_3mps_s": time_to_target,
		"max_speed_mps": max_speed,
		"final_speed_mps": final_speed,
		"min_upright_cos": min_upright_cos,
		"first_inverted_s": first_inverted_s,
		"max_tilt_deg": rad_to_deg(acos(clampf(min_upright_cos, -1.0, 1.0))),
		"max_abs_pitch_deg": rad_to_deg(max_abs_pitch),
		"peak_pitch_deg": rad_to_deg(peak_pitch),
		"peak_pitch_s": peak_pitch_s,
		"pitch_samples_50ms": pitch_samples,
		"max_hull_contact_count": max_hull_count,
		"hull_contact_ticks": hull_contact_ticks,
		"first_hull_contact_s": first_hull_contact_s,
		"initial_wheel_contact_count": initial_wheel_contacts,
		"initial_hull_contact_count": initial_hull_contacts,
		"airborne_ticks": airborne_ticks,
		"start_energy_j": start_energy,
		"min_energy_j": energy_min,
		"max_energy_j": energy_max,
		"final_energy_j": final_energy,
		"complete": termination == "duration_complete",
		"peak_friction_sweeps": peak_sweeps,
	}

func _upright_cos(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var up_ned := M.q_rotate(q, PackedFloat64Array([0.0, 0.0, -1.0]))
	return -up_ned[2]

func _pitch_rad(state: PackedFloat64Array) -> float:
	var q := PackedFloat64Array([state[Vehicle.ATT], state[Vehicle.ATT + 1], state[Vehicle.ATT + 2], state[Vehicle.ATT + 3]])
	var forward_ned := M.q_rotate(q, PackedFloat64Array([1.0, 0.0, 0.0]))
	return M.atan2_(-forward_ned[2], sqrt(forward_ned[0] * forward_ned[0] + forward_ned[1] * forward_ned[1]))

func _contact_count(contacts: PackedByteArray) -> int:
	var count := 0
	for contact in contacts:
		count += int(contact)
	return count

func _finite(state: PackedFloat64Array) -> bool:
	for value in state:
		if not is_finite(value):
			return false
	return true

func _fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)
