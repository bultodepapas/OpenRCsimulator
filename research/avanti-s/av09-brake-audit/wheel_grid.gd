# AV-09 / review R2: fixed-axle characterization of the stock wheel evaluator.
# See the companion evidence README for scope, output columns and invocation.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const AIRCRAFT := "res://data/aircraft/sebart_avanti_s_a200.json"
const SAMPLE_TICKS := [0, 1, 2, 3, 6, 12, 24, 60, 120, 240, 480, 720, 960, 1200]
const HEADER := ["case", "tick", "time_s", "axle_speed_mps", "side_speed_mps", "normal_target_n",
	"friction_factor", "demand", "hardware_capacity_nm", "normal_actual_n", "mu", "crr",
	"rim_speed_mps", "omega_rad_s", "long_slip_mps", "side_slip_mps", "tire_force_n", "rolling_force_n",
	"lateral_force_n", "long_force_n", "brake_torque_nm", "rim_accel_mps2", "traction_limit_n",
	"torque_capacity_over_radius_n", "tire_slope_cap", "brake_slope_cap", "friction_circle",
	"brake_torque_cap", "tire_power_w", "rolling_power_w", "lateral_power_w", "brake_power_w",
	"passive_power_w", "tire_energy_j", "rolling_energy_j", "lateral_energy_j", "brake_energy_j",
	"axle_force_work_j", "wheel_energy_change_j", "energy_closure_error_j"]

var out_dir := ""
var hz := 240
var tick_scale := 1
var min_ticks := 240
var max_ticks := 1200
var failures := 0
var checks := 0
var max_positive_power := 0.0
var max_formula_error := 0.0
var max_final_rate := 0.0
var max_energy_error := 0.0
var max_case_ticks := 0
var unsettled := 0
var cases := 0
var csv: FileAccess
var stock_gear: Dictionary
var stock_contact: Dictionary


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--hz="):
			hz = int(arg.trim_prefix("--hz="))
	if hz not in [240, 480]:
		printerr("--hz must be 240 or 480")
		quit(1)
		return
	tick_scale = hz / 240
	min_ticks = 240 * tick_scale
	max_ticks = 1200 * tick_scale
	if out_dir.is_empty() or DirAccess.dir_exists_absolute(out_dir):
		printerr("Use --out=<new absolute directory>; existing output is never overwritten")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		printerr("Cannot create output directory: ", out_dir)
		quit(1)
		return
	var loaded: Dictionary = AircraftData.load_file(AIRCRAFT)
	check("stock Avanti loads and applies its wheel profile", loaded.ok \
		and loaded.model.wheel_profile.status == "applied")
	if not loaded.ok:
		printerr(str(loaded.errors))
		quit(1)
		return
	stock_gear = loaded.model.landing_gear.duplicate(true)
	stock_contact = stock_gear.contacts[0].duplicate(true)
	check("selected contact is available left main brake", stock_contact.name == "main_left" \
		and stock_contact.brake_availability == "available")
	check("expected profiled radius, inertia, and relaxation", stock_contact.wheel_radius == 0.04338 \
		and stock_contact.wheel_inertia == 0.000055552 and stock_contact.spin_relaxation == 0.03)
	csv = FileAccess.open(out_dir.path_join("wheel-traces.csv"), FileAccess.WRITE)
	if csv == null:
		printerr("Cannot create wheel-traces.csv")
		quit(1)
		return
	csv.store_csv_line(PackedStringArray(HEADER))
	for friction_factor in [1.0, 0.2]:
		for normal in [1.0, 10.0, 40.0, 80.0]:
			for speed in [1.0, 3.0, 10.0, 20.0]:
				for demand in [0.0, 0.25, 0.5, 1.0]:
					for capacity in [0.1, 1.0, 10.0]:
						run_case(speed, 0.0, normal, friction_factor, demand, capacity)
	# Exercise combined-slip circle scaling, separately from the straight grid.
	for friction_factor in [1.0, 0.2]:
		run_case(3.0, 1.0, 40.0, friction_factor, 1.0, 1.0)
	csv.flush()
	csv.close()
	check("all 386 cases completed", cases == 386)
	check("reconstructed branch forces match evaluator", max_formula_error < 1e-9)
	check("all sampled and RK-stage passive powers are nonpositive", max_positive_power <= 1e-10)
	check("bounded final acceleration recorded", is_finite(max_final_rate) and max_final_rate < 0.002)
	check("integrated force work and wheel energy agree within the numerical tolerance", max_energy_error < (0.0003 if hz == 240 else 0.00003))
	var summary := {cases = cases, checks = checks, failures = failures, hz = hz, minimum_ticks = min_ticks, maximum_ticks = max_ticks,
		max_positive_power_w = max_positive_power, max_formula_error = max_formula_error,
		max_final_rim_acceleration_mps2 = max_final_rate, max_case_ticks = max_case_ticks, unsettled_cases = unsettled,
		max_energy_closure_error_j = max_energy_error, engine = Engine.get_version_info(),
		profile = {name = stock_contact.name, radius_m = stock_contact.wheel_radius,
			inertia_kg_m2 = stock_contact.wheel_inertia, relaxation_s = stock_contact.spin_relaxation,
			stock_capacity_nm = stock_contact.brake_torque, stock_mu = stock_gear.side_friction,
			stock_crr = stock_gear.rolling_resistance}}
	var file := FileAccess.open(out_dir.path_join("summary.json"), FileAccess.WRITE)
	if file == null:
		printerr("Cannot write summary")
		quit(1)
		return
	file.store_string(JSON.stringify(summary, "\t", true, true) + "\n")
	file.flush()
	file.close()
	print("AV09_WHEEL_GRID %d cases, %d checks, %d failures" % [cases, checks, failures])
	quit(1 if failures else 0)


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func run_case(speed: float, side: float, normal: float, friction_factor: float,
		demand: float, capacity: float) -> void:
	cases += 1
	var contact := stock_contact.duplicate(true)
	# Replace only support geometry to prescribe normal load on a level fixed axle.
	contact.position = M.v3(0.0, 0.0, 0.2)
	contact.stiffness = 1000.0
	contact.damping = 0.0
	contact.brake_torque = capacity
	var gear := stock_gear.duplicate(true)
	gear.contacts = [contact]
	gear.reach = 0.5
	gear.side_friction = float(stock_gear.side_friction) * friction_factor
	var state := RB.make_state(M.v3(0.0, 0.0, -(0.2 - normal / 1000.0)),
		M.v3(speed, side, 0.0), M.quat(1.0, 0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var rim := speed
	var energy := [0.0, 0.0, 0.0, 0.0, 0.0]
	var dt := 1.0 / float(hz)
	for tick in max_ticks + 1:
		var a := evaluate(state, gear, rim, demand)
		var finished: bool = tick >= min_ticks and (absf(a.rate) < 1e-7 or tick == max_ticks)
		if (tick % tick_scale == 0 and tick / tick_scale in SAMPLE_TICKS) or finished:
			write_sample(tick, speed, side, normal, friction_factor, demand, capacity, rim, energy, a, gear)
		if finished:
			if absf(a.rate) >= 1e-7:
				unsettled += 1
			max_final_rate = maxf(max_final_rate, absf(a.rate))
			max_case_ticks = maxi(max_case_ticks, tick)
			break
		var b := evaluate(state, gear, rim + dt * a.rate / 2.0, demand)
		var c := evaluate(state, gear, rim + dt * b.rate / 2.0, demand)
		var d := evaluate(state, gear, rim + dt * c.rate, demand)
		rim += dt * (a.rate + 2.0 * b.rate + 2.0 * c.rate + d.rate) / 6.0
		for i in 5:
			energy[i] += dt * (a.power[i] + 2.0 * b.power[i] + 2.0 * c.power[i] + d.power[i]) / 6.0


func evaluate(state: PackedFloat64Array, gear: Dictionary, rim: float, demand: float) -> Dictionary:
	var result := Wheels.evaluate(state, gear, 0.0, PackedFloat64Array(), PackedFloat64Array(),
		PackedFloat64Array([rim]), demand)
	var wheel: Dictionary = result.wheels[0]
	var contact: Dictionary = gear.contacts[0]
	var powers := [float(wheel.slip_force) * float(wheel.longitudinal_slip),
		float(wheel.rolling_force) * float(wheel.long_speed),
		float(wheel.lateral_force) * state[RB.VEL + 1],
		-float(wheel.brake_torque) * rim / float(contact.wheel_radius)]
	for power: float in powers:
		max_positive_power = maxf(max_positive_power, power)
	powers.append(float(wheel.longitudinal_force) * float(wheel.long_speed) \
		+ float(wheel.lateral_force) * state[RB.VEL + 1])
	return {wheel = wheel, rate = result.derivative[0], power = powers}


func write_sample(tick: int, speed: float, side: float, normal: float, friction_factor: float,
		demand: float, capacity: float, rim: float, energy: Array, actual: Dictionary, gear: Dictionary) -> void:
	var w: Dictionary = actual.wheel
	var c: Dictionary = gear.contacts[0]
	var mu: float = gear.side_friction
	var crr: float = gear.rolling_resistance
	var radius: float = c.wheel_radius
	var mass: float = c.wheel_inertia / (radius * radius)
	var limit: float = mu * float(w.normal_load)
	var tire_cap: bool = mass / float(c.spin_relaxation) < limit
	var tire_raw: float = -minf(limit, mass / float(c.spin_relaxation)) * (speed - rim)
	var rr_raw: float = -crr * float(w.normal_load) * clampf(speed / maxf(0.01, crr * 0.1), -1.0, 1.0)
	var side_raw: float = -limit * clampf(side / (float(gear.tan_peak_slip) * maxf(absf(speed), 1.0)), -1.0, 1.0)
	var total := sqrt((rr_raw + tire_raw) ** 2 + side_raw ** 2)
	var scale := limit / total if total > limit else 1.0
	var maximum := demand * capacity
	var brake_cap: bool = mass * radius / float(c.spin_relaxation) < maximum / 0.25
	var brake_raw := minf(maximum / 0.25, mass * radius / float(c.spin_relaxation)) * rim
	var torque := clampf(brake_raw, -maximum, maximum)
	max_formula_error = maxf(max_formula_error, absf(float(w.normal_load) - normal))
	max_formula_error = maxf(max_formula_error, absf(float(w.slip_force) - tire_raw * scale))
	max_formula_error = maxf(max_formula_error, absf(float(w.rolling_force) - rr_raw * scale))
	max_formula_error = maxf(max_formula_error, absf(float(w.lateral_force) - side_raw * scale))
	max_formula_error = maxf(max_formula_error, absf(float(w.brake_torque) - torque))
	var total_power: float = actual.power[0] + actual.power[1] + actual.power[2] + actual.power[3]
	var wheel_energy_change: float = 0.5 * mass * (rim * rim - speed * speed)
	var closure: float = energy[4] + wheel_energy_change - energy[0] - energy[1] - energy[2] - energy[3]
	max_energy_error = maxf(max_energy_error, absf(closure))
	var row := [cases, tick, float(tick) / hz, speed, side, normal, friction_factor, demand, capacity,
		w.normal_load, mu, crr, rim, rim / radius, w.longitudinal_slip, side, w.slip_force,
		w.rolling_force, w.lateral_force, w.longitudinal_force, w.brake_torque, actual.rate,
		limit, maximum / radius, int(tire_cap), int(brake_cap), int(total > limit),
		int(absf(brake_raw) > maximum), actual.power[0], actual.power[1], actual.power[2],
		actual.power[3], total_power, energy[0], energy[1], energy[2], energy[3], energy[4],
		wheel_energy_change, closure]
	var cells := PackedStringArray()
	for value in row:
		cells.append(String.num(value, 12) if value is float else str(value))
	csv.store_csv_line(cells)
