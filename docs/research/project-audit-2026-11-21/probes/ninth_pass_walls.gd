extends SceneTree
## Read-only focused witness. Invoke under the parent's checked, admitted fixture.
## Stock Bisonte, level road, held brake, 1 N stationary front-hull wall load.
## Compare with precisely the same generalized force applied before the friction solve.
## The equivalent-force comparison isolates solve order; it is not a proposed fix.

const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const M := preload("res://physics/math3d.gd")
const BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
const NO_BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}
var failures := 0
var checks := 0

func check(name: String, passed: bool, detail: String = "") -> void:
	checks += 1
	print("%s %s %s" % ["OK" if passed else "FAIL", name, detail])
	if not passed:
		failures += 1

func road(walls: Array) -> Callable:
	return func(_north: float, _east: float) -> Dictionary:
		return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
			"mu": 0.8, "rolling": 0.0, "surface_id": "flat-witness", "walls": walls}

# Independently construct patch velocities from point kinematics, then calculate
# d(slip)/dt by a small virtual change of velocity at this zero-velocity state.
# No Vehicle._contact_row or Vehicle._tire_contact_bias is used by this oracle.
func slip_rates(state: PackedFloat64Array, model: Dictionary, acceleration: PackedFloat64Array) -> PackedFloat64Array:
	var epsilon := 0.000001
	var velocity := PackedFloat64Array([epsilon * acceleration[0], epsilon * acceleration[1], epsilon * acceleration[2]])
	var omega := PackedFloat64Array([epsilon * acceleration[3], epsilon * acceleration[4], epsilon * acceleration[5]])
	var radius := float(model.tire_radius_m)
	var arm := float(model.arm_length_m)
	var result := PackedFloat64Array()
	for corner in 4:
		var travel := state[Vehicle.TRAVEL + corner]
		var side := signf(model.corner_y_m[corner])
		var horizontal_arm := sqrt(arm * arm - travel * travel)
		var hub := PackedFloat64Array([model.corner_x_m[corner], model.corner_y_m[corner] + side * (horizontal_arm - arm),
			float(model.cg_height_above_chassis_datum_m) + float(model.wheel_center_rest_below_chassis_datum_m) - travel])
		var hub_prime := PackedFloat64Array([0.0, -side * travel / horizontal_arm, -1.0])
		var hub_vel := M.add(velocity, M.add(M.cross(omega, hub), M.scale(hub_prime, epsilon * acceleration[6 + corner])))
		var wheel_omega := M.add(omega, PackedFloat64Array([0.0, -epsilon * acceleration[10 + corner], 0.0]))
		var patch_vel := M.add(hub_vel, M.cross(wheel_omega, PackedFloat64Array([0.0, 0.0, radius])))
		result.append(patch_vel[0] / epsilon)
		result.append(patch_vel[1] / epsilon)
	return result

func max_abs(values: PackedFloat64Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result

func difference(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in a.size():
		out.append(a[i] - b[i])
	return out

func summarize(label: String, result: Dictionary, state: PackedFloat64Array, model: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		print("RESULT %s ERROR %s" % [label, str(result)])
		return
	var accel: PackedFloat64Array = result.generalized_acceleration
	print("RESULT ", label, " ", JSON.stringify({
		"accel_x_m_s2": accel[0], "pitch_accel_rad_s2": accel[4],
		"patch_slip_accel_long_lat_m_s2": slip_rates(state, model, accel),
		"wheel_relative_accel_rad_s2": accel.slice(10, 14),
		"ground_tire_load_n": result.wheel_load_n,
		"ground_tire_long_n": result.wheel_longitudinal_force_n,
		"ground_tire_lat_n": result.wheel_lateral_force_n,
		"brake_torque_nm": result.wheel_brake_torque_n_m,
		"tire_contacts": result.wheel_in_contact,
		"wall_count": result.get("wall_contact_count", 0),
		"wall_load_n": result.get("wall_normal_load_n", 0.0),
		"sweeps": result.friction_sweeps_used,
	}))

func _initialize() -> void:
	check("select reference backend", Vehicle.set_backend_override_for_tests(Vehicle.BACKEND_GDSCRIPT_REFERENCE))
	var loaded := Data.load_default()
	check("load stock Bisonte", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var model: Dictionary = loaded.model
	var clear_road := road([])
	var initialized := Vehicle.initialize(model, clear_road, 0.0, 0.0)
	check("initialize flat equilibrium", bool(initialized.get("ok", false)), str(initialized.get("error", "")))
	if not bool(initialized.get("ok", false)):
		quit(1)
		return
	var state: PackedFloat64Array = initialized.state
	var hull_center: PackedFloat64Array = model.hull_probe_centers_frd_m.slice(0, 3)
	var hull_radius := float(model.hull_probe_radii_m[0])
	var wall_load := 1.0
	var overlap := wall_load / float(model.hull_contact_stiffness_n_per_m)
	var wall_front := hull_center[0] + hull_radius - overlap
	var wall := {"id": "audit-wall", "north_min_m": wall_front, "north_max_m": 0.6,
		"east_min_m": -1.0, "east_max_m": 1.0, "bottom_up_m": 0.0, "top_up_m": 2.0, "mu": 0.0}
	var wall_road := road([wall])
	var clear: Dictionary = Vehicle._evaluate_active(state, model, BRAKE, clear_road, false, false)
	var with_wall: Dictionary = Vehicle._evaluate_active(state, model, BRAKE, wall_road, false, false)
	var external := PackedFloat64Array()
	external.resize(Vehicle.GENERALIZED_SIZE)
	var force := PackedFloat64Array([-wall_load, 0.0, 0.0])
	var torque := M.cross(hull_center, force)
	for axis in 3:
		external[axis] = force[axis]
		external[3 + axis] = torque[axis]
	var controls_with_load := BRAKE.duplicate(true)
	controls_with_load["external_generalized_force"] = external
	var prior_load: Dictionary = Vehicle._evaluate_active(state, model, controls_with_load, clear_road, false, false)
	var wall_adaptive: Dictionary = Vehicle._evaluate_active(state, model, BRAKE, wall_road, false)
	var prior_adaptive: Dictionary = Vehicle._evaluate_active(state, model, controls_with_load, clear_road, false)
	for value in [clear, with_wall, prior_load, wall_adaptive, prior_adaptive]:
		check("evaluation returned ok", bool(value.get("ok", false)), str(value.get("error", "")))
	if failures > 0:
		quit(1)
		return
	summarize("clear_ground_braked", clear, state, model)
	summarize("wall_after_solve_braked", with_wall, state, model)
	summarize("same_load_before_solve_braked", prior_load, state, model)
	summarize("wall_after_solve_adaptive", wall_adaptive, state, model)
	summarize("same_load_before_solve_adaptive", prior_adaptive, state, model)
	var wall_acc: PackedFloat64Array = with_wall.generalized_acceleration
	var clear_acc: PackedFloat64Array = clear.generalized_acceleration
	var prior_acc: PackedFloat64Array = prior_load.generalized_acceleration
	var wall_slip := slip_rates(state, model, wall_acc)
	var prior_slip := slip_rates(state, model, prior_acc)
	check("exactly one hull wall contact near 1 N", int(with_wall.wall_contact_count) == 1 and absf(float(with_wall.wall_normal_load_n) - 1.0) < 1.0e-8,
		"wall_front=%.12f overlap=%.12f" % [wall_front, overlap])
	check("four ground contacts", (with_wall.wheel_in_contact as PackedByteArray).count(1) == 4)
	check("negative control clear-road equilibrium", max_abs(clear_acc) < 1.0e-7, str(clear_acc))
	check("source ordering moves held wheel spin", max_abs(wall_acc.slice(10, 14)) > 0.1, str(wall_acc.slice(10, 14)))
	check("source ordering creates large tire slip acceleration", max_abs(wall_slip) > 0.1, str(wall_slip))
	check("force-before solve reduces tire residual below 0.001", max_abs(prior_slip) < 0.001, str(prior_slip))
	check("force-before solve reduces brake residual below 0.001", max_abs(prior_acc.slice(10, 14)) < 0.001, str(prior_acc.slice(10, 14)))
	var force_margin_ok := true
	var brake_margin_ok := true
	for corner in 4:
		var flong := float(prior_load.wheel_longitudinal_force_n[corner])
		var flat := float(prior_load.wheel_lateral_force_n[corner])
		var capacity := 0.8 * float(model.tire_friction_scale) * float(prior_load.wheel_load_n[corner])
		var brake_cap := float(model.brake_torque_per_wheel_nm) * 2.0 * (float(model.brake_front_fraction) if corner < 2 else 1.0 - float(model.brake_front_fraction))
		force_margin_ok = force_margin_ok and sqrt(flong * flong + flat * flat) < capacity * 0.1
		brake_margin_ok = brake_margin_ok and absf(float(prior_load.wheel_brake_torque_n_m[corner])) < brake_cap * 0.1
	check("force-before tire reactions below ten percent of capacity", force_margin_ok)
	check("force-before brake reactions below ten percent of capacity", brake_margin_ok)
	var adaptive_wall_acc: PackedFloat64Array = wall_adaptive.generalized_acceleration
	var adaptive_prior_acc: PackedFloat64Array = prior_adaptive.generalized_acceleration
	var adaptive_wall_residual := max_abs(slip_rates(state, model, adaptive_wall_acc))
	var adaptive_prior_residual := max_abs(slip_rates(state, model, adaptive_prior_acc))
	check("default-adaptive wall retains large tire residual", adaptive_wall_residual > 0.1, str(adaptive_wall_residual))
	check("default-adaptive force-before retains small tire residual", adaptive_prior_residual < 0.001, str(adaptive_prior_residual))
	check("default-adaptive force-before retains small brake residual", max_abs(adaptive_prior_acc.slice(10, 14)) < 0.001)
	print("ADAPTIVE wall_sweeps=", wall_adaptive.friction_sweeps_used, " before_sweeps=", prior_adaptive.friction_sweeps_used,
		" wall_tire_residual=", adaptive_wall_residual, " before_tire_residual=", adaptive_prior_residual,
		" wall_brake_residual=", max_abs(adaptive_wall_acc.slice(10,14)),
		" before_brake_residual=", max_abs(adaptive_prior_acc.slice(10,14)))
	print("ORDER COMPARISON max state accel difference: ", max_abs(difference(wall_acc, prior_acc)),
		"; force-before residual tire: ", max_abs(prior_slip), "; brake: ", max_abs(prior_acc.slice(10,14)))
	# Negative control: release brake and raise the whole truck clear of the ground.
	# Wall remains at the same horizontal position, so wall-only acceleration is
	# the same M^-1 Q, with no tire/brake solve to be perturbed by ordering.
	var air_state := state.duplicate()
	air_state[Vehicle.POS + 2] -= 1.0
	var air_clear: Dictionary = Vehicle._evaluate_active(air_state, model, NO_BRAKE, clear_road, false, false)
	var air_wall: Dictionary = Vehicle._evaluate_active(air_state, model, NO_BRAKE, wall_road, false, false)
	for value in [air_clear, air_wall]:
		check("air negative control evaluation ok", bool(value.get("ok", false)), str(value.get("error", "")))
	if bool(air_clear.get("ok", false)) and bool(air_wall.get("ok", false)):
		summarize("air_wall_unbraked", air_wall, air_state, model)
		check("no terrain tire contacts in airborne control", (air_wall.wheel_in_contact as PackedByteArray).count(1) == 0)
		check("one identical air wall load", int(air_wall.wall_contact_count) == 1 and absf(float(air_wall.wall_normal_load_n) - 1.0) < 1.0e-8)
		var ground_increment := difference(wall_acc, clear_acc)
		var air_increment := difference(air_wall.generalized_acceleration, air_clear.generalized_acceleration)
		check("same unconstrained additive response with and without terrain support", max_abs(difference(ground_increment, air_increment)) < 1.0e-8,
			"max difference=" + str(max_abs(difference(ground_increment, air_increment))))
	print("R9_WALL_BACKEND=", JSON.stringify(Vehicle.backend_identity()))
	print("R9 WALL: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
