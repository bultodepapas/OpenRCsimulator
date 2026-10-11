# E5a: Extra taildragger through the real session (servos, engine, aero, surfaces and crash checks).
# Test-only starts; Home continues to offer runway starts only for the Stik.
extends SceneTree

const Flight: Script = preload("res://sim/flight_session.gd")
const Ground: Script = preload("res://physics/ground_contact.gd")
const RB: Script = preload("res://physics/rigid_body.gd")
const M: Script = preload("res://physics/math3d.gd")
const Field: Script = preload("res://data/field_loader.gd")

var failures: int = 0
var count: int = 0
var results: Dictionary = {}


func check(label: String, ok: bool, detail: String = "") -> void:
	count += 1
	print(("ok " if ok else "FAIL ") + label + " " + detail)
	if not ok:
		failures += 1


func trial(hz: int, initial_speed: float, yaw: float, powered: bool, pulse: bool) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var flight: Node = Flight.new()
	flight.setup("res://data/aircraft/gp_extra_300s_60.json")
	root.add_child(flight)
	flight.input_enabled = false
	var field: Dictionary = Field.load_from(Field.DEFAULT_PATH)
	if not flight.aircraft.ok or not flight.start.get("ok", false) or not flight.set_field(field.get("field", field)):
		flight.free()
		return {ok = false, message = "setup failed"}
	var gear: Dictionary = flight.aircraft.model.landing_gear
	if gear.is_empty():
		flight.free()
		return {ok = false, message = "missing gear"}
	var main: PackedFloat64Array = gear.contacts[0].position
	var tail: PackedFloat64Array = gear.contacts[2].position
	var pitch: float = atan2(main[2] - tail[2], main[0] - tail[0])
	var down: float = main[0] * sin(pitch) - main[2] * cos(pitch) + float(gear.static_sag)
	var state: PackedFloat64Array = RB.make_state(M.v3(15, -30, down),
		M.v3(initial_speed * cos(pitch), 0, initial_speed * sin(pitch)),
		M.q_from_euler(PI / 2, pitch, 0), M.v3(0, 0, 0))
	flight.reset()
	flight.trims = {roll = 0.0, pitch = 0.0, yaw = 0.0}
	flight.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	flight.engine_running = powered
	flight.sim.inputs = flight._inputs()
	var aux: PackedFloat64Array = flight.sim.aux.duplicate()
	aux[0] = float(flight.aircraft.model.propulsion.idle_rpm) if powered else 0.0
	for i in range(1, 4):
		aux[i] = 0.0
	if flight.downwash_index() >= 0:
		aux[flight.downwash_index()] = flight._wing_cl(state, aux)
	flight.sim.aux = aux
	flight.sim.continuous = flight._settled_wash(state, aux)
	flight.sim.reset(state)
	flight.sim.set_paused(false)
	var rows: Array = []
	var maximum_compression: float = 0.0
	var peak_rpm: float = float(aux[0])
	var min_contacts: int = 3
	var completed: int = 0
	for tick in range(3 * hz):
		var time: float = float(tick) / hz
		flight.commands.yaw = yaw if time >= 0.25 else 0.0
		flight.commands.throttle = 0.25 if pulse and time >= 0.5 and time < 1.5 else 0.0
		flight.sim.inputs = flight._inputs()
		flight._physics_process(1.0 / hz)
		if not flight.crash.is_empty():
			break
		flight.sim.step()
		completed += 1
		peak_rpm = maxf(peak_rpm, float(flight.sim.aux[0]))
		if not flight.sim.fault_reason.is_empty():
			break
		var contacts: int = 0
		for compression in Ground.compressions(flight.sim.state, gear):
			maximum_compression = maxf(maximum_compression, compression)
			contacts += int(compression > 0.0)
		min_contacts = mini(min_contacts, contacts)
		if completed % roundi(float(hz) / 20.0) == 0:
			rows.append(Array(flight.sim.state))
	# Check the final boundary too: crashes are normally detected before the next integration tick.
	flight._physics_process(1.0 / hz)
	var end: PackedFloat64Array = flight.sim.state
	var angles: PackedFloat64Array = M.q_to_euler(M.quat(end[6], end[7], end[8], end[9]))
	var result: Dictionary = {ok = flight.crash.is_empty() and flight.sim.fault_reason.is_empty() and completed == 3 * hz,
		message = flight.pause_reason + " " + flight.sim.fault_reason, hz = hz, ticks = completed,
		state = Array(end), rows = rows, max_compression_m = maximum_compression, min_contacts = min_contacts,
		heading_change_deg = rad_to_deg(wrapf(angles[0] - PI / 2, -PI, PI)),
		distance_m = sqrt((end[0] - state[0]) ** 2 + (end[1] - state[1]) ** 2),
		final_speed_m_s = sqrt(end[3] ** 2 + end[4] ** 2 + end[5] ** 2), rpm = flight.sim.aux[0],
		peak_rpm = peak_rpm, expected_idle_rpm = flight.aircraft.model.propulsion.idle_rpm}
	flight.free()
	return result


func _initialize() -> void:
	var original_hz: int = Engine.physics_ticks_per_second
	for scenario in ["coast_left", "coast_right", "idle", "pulse"]:
		var coasting: bool = scenario.begins_with("coast")
		var yaw: float = -0.3 if scenario == "coast_left" else (0.3 if scenario == "coast_right" else 0.0)
		var pair: Array = []
		for hz in [240, 480, 960]:
			var result: Dictionary = trial(hz, 3.0 if coasting else 0.0, yaw, not coasting, scenario == "pulse")
			check("%s at %d Hz completes without crash/fault" % [scenario, hz], result.ok, str(result.get("message", "")))
			pair.append(result)
			if result.ok:
				check("%s retains three wheel contacts" % scenario, result.min_contacts == 3, str(result.min_contacts))
				if scenario == "idle":
					check("idle engine remains running near its configured idle", result.rpm >= 0.9 * result.expected_idle_rpm,
						str(result.rpm))
				if coasting:
					check("ground heading follows yaw command", float(result.heading_change_deg) * yaw > 0.1,
						"%.6f deg" % float(result.heading_change_deg))
		results[scenario] = pair
		var differences: Array = []
		for level in range(2):
			if not pair[level].ok or not pair[level + 1].ok:
				continue
			var maxima: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0])
			for index in range(pair[level].rows.size()):
				for component in range(13):
					var error: float = absf(pair[level].rows[index][component] - pair[level + 1].rows[index][component])
					var group: int = 0 if component < 3 else (1 if component < 6 else (2 if component < 10 else 3))
					maxima[group] = maxf(maxima[group], error)
			# Sampled servos/engine advance before RK4; control transitions can converge at first order.
			check("%s refinement level %d: 2 mm / 1 cm/s / 0.001 quaternion / 0.005 rad/s" % [scenario, level],
				maxima[0] < 0.002 and maxima[1] < 0.01 and maxima[2] < 0.001 and maxima[3] < 0.005, str(maxima))
			differences.append(Array(maxima))
		if differences.size() == 2:
			for group in range(4):
				check("%s component group %d difference shrinks on second refinement" % [scenario, group],
					differences[1][group] <= maxf(1e-7, differences[0][group] / 1.5),
					str([differences[0][group], differences[1][group]]))
		results[scenario + "_refinement"] = differences
	for index in range(3):
		var idle: Dictionary = results.idle[index]
		var pulse: Dictionary = results.pulse[index]
		if idle.ok and pulse.ok:
			check("pulse produces resolved RPM response at %d Hz" % pulse.hz, pulse.peak_rpm > idle.peak_rpm + 100.0,
				str([idle.peak_rpm, pulse.peak_rpm]))
			check("pulse moves farther than idle by more than the refinement allowance", pulse.distance_m > idle.distance_m + 0.01,
				str([idle.distance_m, pulse.distance_m]))
	Engine.physics_ticks_per_second = original_hz
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file: FileAccess = FileAccess.open(arg.trim_prefix("--out="), FileAccess.WRITE)
			check("report opened", file != null)
			if file != null:
				file.store_string(JSON.stringify({checks = count, failures = failures, results = results}, "\t") + "\n")
	print("%d checks, %d failed" % [count, failures])
	quit(1 if failures > 0 else 0)
