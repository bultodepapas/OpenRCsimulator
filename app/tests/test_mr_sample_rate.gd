# DR-09a (NUM-01, NUM-02): is the 240 Hz control sample adequate for this controller on this plant?
# NUM-01 holds the controller samples at k/240 s and refines only the plant integration (kernel substeps 1, 2, 4).
# NUM-02 compares the 240 Hz closed loop on a refined plant against 960 Hz and 1920 Hz closed loops in which every
# controller sample has fresh feedback (the kernel itself is stepped at that rate; the law is prepared for it
# through the research seam of flight_controller.gd). Screen from the plan: rise-time error <= 15 %, settling-time
# error <= 20 %, overshoot difference <= 5 percentage points, on +/-200 deg/s steps. An engineering screen on
# synthetic fixture numbers: it qualifies the sampling of this simulator controller, not a real aircraft.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Sim := preload("res://sim/simulation.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const MultirotorData := preload("res://physics/multirotor_data.gd")

const STEP_DPS := 200.0
const REST_S := 0.2
const HOLD_S := 1.0
const RELEASE_S := 0.25
const PRODUCT := "res://data/multirotors/openrc-fpv5-x1.json"

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


## Stick deflection whose rate target is `dps` on `axis` (bisection on the monotonic curve).
func _stick_for(prepared_rates: Dictionary, axis: int, dps: float) -> float:
	var low := 0.0
	var high := 1.0
	for _i in 60:
		var mid: float = 0.5 * (low + high)
		if Rates.setpoint_dps(prepared_rates, axis, mid) < absf(dps):
			low = mid
		else:
			high = mid
	return 0.5 * (low + high) * signf(dps)


## One closed-loop run: hover, a rate step on `axis`, release. Returns the sampled rate trace at the tick rate.
func _trace(data: Dictionary, tick_hz: int, plant_substeps: int, axis: int, dps: float) -> Dictionary:
	Engine.physics_ticks_per_second = tick_hz
	var research_hz: int = 0 if tick_hz == 240 else tick_hz
	var created: Dictionary = Plant.create(data, Rates.default_profile(), FC.THROTTLE_ABSOLUTE, research_hz)
	if not created.ok:
		return {ok = false, message = str(created.errors)}
	var plant: RefCounted = created.plant
	var sim: Node = Sim.new()
	root.add_child(sim)
	var vehicle: RefCounted = plant.build()
	if plant_substeps > 1:
		vehicle.substeps = func(_b: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> int: return plant_substeps
	sim.set_model(vehicle)
	sim.mass = float(data.mass_kg)
	sim.inertia = data.inertia_kg_m2.duplicate()
	var frame: Dictionary = plant.initial_frame(Fixtures.body(50.0))
	var hover_speed: float = sqrt(float(data.mass_kg) * 9.80665 / (4.0 * float(data.rotor_law.thrust_coefficient_n_s2)))
	for i in 4:
		frame.continuous[i] = hover_speed
	# Research air start: armed with valid arm evidence, so every tick rate begins from the same physical state.
	frame.modes[FC.MODE_MOTOR] = FC.MOTOR_ARMED
	frame.modes[FC.MODE_PREVIOUS_ARM] = 1
	frame.modes[FC.MODE_OFF_OBSERVED] = 1
	frame.modes[FC.MODE_ARM_BLOCK] = FC.BLOCK_NONE
	var map: Dictionary = plant.config.actuator
	var command: float = ActuatorMap.command_for_thrust(map, float(data.mass_kg) * 9.80665 / 4.0, plant.supply_voltage(frame.continuous))
	var throttle: float = (command - float(map.idle)) / (float(map.top) - float(map.idle))
	var message: String = Fixtures.reset(sim, frame, Fixtures.pilot(0.0, 0.0, 0.0, throttle, 1))
	var stick: float = _stick_for(plant.config.rates, axis, dps)
	var rest_ticks: int = roundi(REST_S * tick_hz)
	var hold_ticks: int = roundi(HOLD_S * tick_hz)
	var total: int = rest_ticks + hold_ticks + roundi(RELEASE_S * tick_hz)
	var rate := PackedFloat64Array()
	rate.resize(total + 1)
	rate[0] = sim.state[RB.RATE + axis]
	var ok: bool = message.is_empty()
	for tick in total:
		var sticks := PackedFloat64Array([0.0, 0.0, 0.0])
		if tick >= rest_ticks and tick < rest_ticks + hold_ticks:
			sticks[axis] = stick
		sim.inputs = Fixtures.pilot(sticks[0], sticks[1], sticks[2], throttle, 1)
		sim.step()
		ok = ok and sim.fault_reason.is_empty()
		rate[tick + 1] = sim.state[RB.RATE + axis]
	var result := {ok = ok, message = message + sim.fault_reason, rate = rate, tick_hz = tick_hz, rest_ticks = rest_ticks,
		hold_ticks = hold_ticks, final_state = sim.state.duplicate(), final_continuous = sim.continuous.duplicate()}
	sim.free()
	return result


## Step metrics on the hold window, in seconds from the step edge: 10–90 % rise time, overshoot as a fraction of
## the step, settling time into a +/-5 % band that then holds to the end of the window (NAN when it never settles).
func _metrics(trace: Dictionary, dps: float) -> Dictionary:
	var target: float = deg_to_rad(dps)
	var hz: float = float(trace.tick_hz)
	var start: int = trace.rest_ticks
	var stop: int = start + int(trace.hold_ticks)
	var rate: PackedFloat64Array = trace.rate
	var t10 := NAN
	var t90 := NAN
	var peak := 0.0
	var last_outside: int = start
	for i in range(start, stop + 1):
		var value: float = rate[i] / target # normalized: 0 at rest, 1 on target, sign-independent
		var previous: float = rate[i - 1] / target if i > start else 0.0
		if is_nan(t10) and value >= 0.1:
			t10 = (float(i - start) - (value - 0.1) / maxf(value - previous, 1e-12)) / hz
		if is_nan(t90) and value >= 0.9:
			t90 = (float(i - start) - (value - 0.9) / maxf(value - previous, 1e-12)) / hz
		peak = maxf(peak, value)
		if absf(value - 1.0) > 0.05:
			last_outside = i
	var dwell_ticks: int = roundi(0.1 * hz)
	var settling := NAN
	if stop - last_outside >= dwell_ticks:
		settling = float(last_outside + 1 - start) / hz
	return {rise_s = t90 - t10, overshoot = maxf(peak - 1.0, 0.0), settling_s = settling}


func _screen(label: String, candidate: Dictionary, reference: Dictionary) -> void:
	var floor_s := 0.002 # resolution floor for near-zero reference times
	var rise_error: float = absf(candidate.rise_s - reference.rise_s) / maxf(reference.rise_s, floor_s)
	var settle_error: float = absf(candidate.settling_s - reference.settling_s) / maxf(reference.settling_s, floor_s)
	var overshoot_points: float = 100.0 * absf(candidate.overshoot - reference.overshoot)
	var settled: bool = not is_nan(candidate.settling_s) and not is_nan(reference.settling_s) and not is_nan(candidate.rise_s)
	_check(label, settled and rise_error <= 0.15 and settle_error <= 0.20 and overshoot_points <= 5.0,
		"rise %.2f/%.2f ms (%.1f %%) settle %.1f/%.1f ms (%.1f %%) overshoot %.2f/%.2f %% (%.2f pp)" % [
			1000.0 * candidate.rise_s, 1000.0 * reference.rise_s, 100.0 * rise_error, 1000.0 * candidate.settling_s,
			1000.0 * reference.settling_s, 100.0 * settle_error, 100.0 * candidate.overshoot, 100.0 * reference.overshoot, overshoot_points])


func _difference(a: Dictionary, b: Dictionary) -> Dictionary:
	var position := 0.0
	var rate := 0.0
	var shaft := 0.0
	for i in 3:
		position = maxf(position, absf(a.final_state[RB.POS + i] - b.final_state[RB.POS + i]))
		rate = maxf(rate, absf(a.final_state[RB.RATE + i] - b.final_state[RB.RATE + i]))
	for i in 4:
		shaft = maxf(shaft, absf(a.final_continuous[i] - b.final_continuous[i]))
	return {position_m = position, rate_radps = rate, shaft_radps = shaft}


func _run() -> void:
	var configurations: Array = [["synthetic electrical fixture", Fixtures.electric()]]
	var loaded: Dictionary = MultirotorData.load_file(PRODUCT)
	if loaded.ok:
		var prepared: Dictionary = MultirotorData.prepare(loaded.data, loaded.sha256)
		if prepared.ok:
			configurations.append(["product candidate openrc-fpv5-x1", prepared.prepared])
	_check("the product candidate document is part of the qualification", configurations.size() == 2,
		"" if configurations.size() == 2 else str(loaded.get("errors", [])))
	var high_rate_available := true
	for entry: Array in configurations:
		var name: String = entry[0]
		var data: Dictionary = entry[1]
		# NUM-01: plant refinement with the controller samples held at k/240 s.
		var h1: Dictionary = _trace(data, 240, 1, 0, STEP_DPS)
		var h2: Dictionary = _trace(data, 240, 2, 0, STEP_DPS)
		var h4: Dictionary = _trace(data, 240, 4, 0, STEP_DPS)
		_check("%s: NUM-01 runs complete at h, h/2 and h/4" % name, h1.ok and h2.ok and h4.ok, str(h1.get("message", "")))
		if not (h1.ok and h2.ok and h4.ok):
			continue
		var coarse: Dictionary = _difference(h1, h2)
		var fine: Dictionary = _difference(h2, h4)
		_check("%s: NUM-01 the plant integration converges under refinement at fixed control times" % name,
			fine.position_m <= coarse.position_m and fine.rate_radps <= coarse.rate_radps and coarse.position_m < 1e-3,
			"h vs h/2: %s m, %s rad/s, %s rad/s shaft; h/2 vs h/4: %s m, %s rad/s, %s rad/s shaft" % [
				String.num_scientific(coarse.position_m), String.num_scientific(coarse.rate_radps), String.num_scientific(coarse.shaft_radps),
				String.num_scientific(fine.position_m), String.num_scientific(fine.rate_radps), String.num_scientific(fine.shaft_radps)])
		# NUM-02: controller sample rate, every sample with fresh feedback.
		# The synthetic fixture runs the roll case only; the product candidate runs every axis and the 1920 Hz check.
		var product: bool = entry == configurations[configurations.size() - 1] and configurations.size() == 2
		for axis in (3 if product else 1):
			for direction: float in ([1.0, -1.0] if axis == 0 and product else [1.0]):
				var dps: float = STEP_DPS * direction
				var c240: Dictionary = _trace(data, 240, 4, axis, dps)
				var c960: Dictionary = _trace(data, 960, 1, axis, dps)
				if not (c240.ok and c960.ok):
					_check("%s: NUM-02 %s runs complete" % [name, Rates.AXIS_NAMES[axis]], false, str(c240.get("message", "")) + str(c960.get("message", "")))
					continue
				var m240: Dictionary = _metrics(c240, dps)
				var m960: Dictionary = _metrics(c960, dps)
				_screen("%s: NUM-02 %s %+.0f deg/s, 240 Hz against the 960 Hz reference" % [name, Rates.AXIS_NAMES[axis], dps], m240, m960)
				if product and axis == 0 and direction > 0.0 and high_rate_available:
					var c1920: Dictionary = _trace(data, 1920, 1, axis, dps)
					if Engine.physics_ticks_per_second != 1920 or not c1920.ok:
						high_rate_available = false
						print("note 1920 Hz reference-refinement run unavailable on this engine: %s" % str(c1920.get("message", "")))
					else:
						_screen("%s: NUM-02 the 960 Hz reference has converged against 1920 Hz" % name, m960, _metrics(c1920, dps))
	Engine.physics_ticks_per_second = 240
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
