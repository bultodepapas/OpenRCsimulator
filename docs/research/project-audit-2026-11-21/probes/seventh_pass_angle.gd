# R7 research witness. Uses synthetic device/key callbacks through unchanged production input, controller and session code.
# Observes the baseline; passing this probe does not mean the observed behavior is repaired.
extends SceneTree

const Session = preload("res://sim/multirotor/session.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const PilotInput = preload("res://input/multirotor_input.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
const DT = 1.0 / 240.0

var checks := 0
var fails := 0
var keys: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok: fails += 1
	print("%s %s %s" % ["ok" if ok else "FAIL", label, detail])

func send_tick(s: Node, inp: RefCounted) -> bool:
	var sample: Dictionary = inp.sample(DT, true)
	return s.tick_once(sample.pilot)

func run_case(roll: float, pitch: float, label: String) -> Dictionary:
	keys = {}
	var inp := PilotInput.new()
	inp.read_keys = func() -> Dictionary: return keys.duplicate()
	# A pilot can select the full-throttle option (0.45 -> 0.6 -> 1.0).
	inp.cycle_throttle_limit()
	inp.cycle_throttle_limit()
	var s := Session.new()
	root.add_child(s)
	var ready: bool = s.prepare({}, {throttle_policy = inp.throttle_policy(), throttle_limit = inp.throttle_limit(),
		source_generation = inp.source_generation})
	if not ready:
		print("prepare failed ", s.load_error)
		s.queue_free()
		return {ok = false}
	s.resume()
	var ok: bool = send_tick(s, inp)
	keys = {arm = true}
	ok = send_tick(s, inp) and ok
	keys = {throttle = 1.0}
	ok = send_tick(s, inp) and ok
	for i in 239:
		ok = send_tick(s, inp) and ok
	var start_alt: float = -s.sim.state[RB.POS + 2]
	keys = {roll = roll, pitch = pitch}
	var max_tilt := 0.0
	for i in 360:
		if not send_tick(s, inp):
			ok = false
			break
		var q: PackedFloat64Array = s.sim.state.slice(RB.ATT, RB.ATT + 4)
		var tilt := rad_to_deg(acos(clampf(1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2]), -1.0, 1.0)))
		max_tilt = maxf(max_tilt, tilt)
		if i in [119, 239, 359]:
			print("TRACE %s t=%.3f tilt=%.9f altitude=%.5f rates=(%.4f,%.4f,%.4f) motor=%d fault=%s" % [label, (i + 1) * DT, tilt,
				-s.sim.state[RB.POS+2], s.sim.state[RB.RATE], s.sim.state[RB.RATE+1], s.sim.state[RB.RATE+2], s.sim.modes[FC.MODE_MOTOR], s.fault_reason])
	var q: PackedFloat64Array = s.sim.state.slice(RB.ATT, RB.ATT + 4)
	var final_tilt := rad_to_deg(acos(clampf(1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2]), -1.0, 1.0)))
	var final_input: Dictionary = inp.sample(DT, true)
	var answer := {ok = ok and s.fault_reason.is_empty() and s.crash.is_empty() and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED,
		start_alt = start_alt, final_tilt = final_tilt, max_tilt = max_tilt, pilot = final_input.pilot, tick = s.sim.tick,
		max_config = rad_to_deg(float(s.plant.config.angle_max_tilt)), data_id = s.source_sha256,
		final_quaternion = Array(q), requested_axes = [roll, pitch], mode = s.sim.modes[FC.MODE_FLIGHT]}
	s.queue_free()
	return answer

func _run() -> void:
	var solo: Dictionary = run_case(1.0, 0.0, "roll_only")
	var circular: Dictionary = run_case(sqrt(0.5), sqrt(0.5), "circle_diagonal")
	var diagonal: Dictionary = run_case(1.0, 1.0, "full_diagonal")
	print("R7_ANGLE ", JSON.stringify({case_name = "solo", result = solo}, "", true, true))
	print("R7_ANGLE ", JSON.stringify({case_name = "circular", result = circular}, "", true, true))
	print("R7_ANGLE ", JSON.stringify({case_name = "diagonal", result = diagonal}, "", true, true))
	check("stock-data pad start and real keyboard adapter reach all three flights", solo.ok and circular.ok and diagonal.ok
		and solo.start_alt > 0.1 and circular.start_alt > 0.1 and diagonal.start_alt > 0.1)
	check("single-axis control is near 55 deg after 1.5 s", absf(solo.final_tilt - 55.0) < 2.0, str(solo.final_tilt))
	check("unit-disc diagonal pilot input is accepted on both axes", absf(circular.pilot[0]-sqrt(0.5)) < 1e-9
		and absf(circular.pilot[1]-sqrt(0.5)) < 1e-9)
	check("unit-disc diagonal is near its 52.7123 deg target after 1.5 s", absf(circular.final_tilt - 52.712265831804) < 2.0, str(circular.final_tilt))
	check("full diagonal pilot input is accepted on both axes", diagonal.pilot[0] == 1.0 and diagonal.pilot[1] == 1.0)
	check("full diagonal exceeds 55 deg after 1.5 s", diagonal.final_tilt > 60.0, str(diagonal.final_tilt))
	check("all three witnesses use Angle mode", solo.mode == FC.FLIGHT_ANGLE and circular.mode == FC.FLIGHT_ANGLE and diagonal.mode == FC.FLIGHT_ANGLE)
	print("R7 angle: %d checks, %d failed" % [checks, fails])
	quit(1 if fails else 0)
