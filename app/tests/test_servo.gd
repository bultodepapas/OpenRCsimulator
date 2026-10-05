# D6c: servos between the pilot's commands and the surfaces, advanced at the physics tick.
# Run: godot --headless --path . --script res://tests/test_servo.gd
extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const Recorder := preload("res://sim/recorder.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	var session := FlightSession.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.reset()
	var sim: Node = session.sim
	var rate: float = session.aircraft.model.controls.servo_rate
	_check("servos start at the trimmed surface positions", sim.aux[1] == sim.inputs[0] and sim.aux[2] == sim.inputs[1] and sim.aux[3] == sim.inputs[2], str(sim.aux))

	# Full aileron step from neutral: 0.14 s at 240 Hz = 33.6 ticks → full throw on tick 34, not before.
	var aux: PackedFloat64Array = sim.aux
	aux[1] = 0.0
	sim.aux = aux
	var inputs: PackedFloat64Array = sim.inputs
	inputs[0] = 1.0
	sim.inputs = inputs
	var rec := Recorder.new(sim)
	rec.start({})
	var reached := -1
	for i in 72:
		sim.step()
		if reached < 0 and sim.aux[1] == 1.0:
			reached = sim.tick
	_check("full throw on tick 34 (0.14 s)", reached == 34, "tick %d, rate %.3f/s" % [reached, rate])
	var t := rec.trace
	_check("trace: srv_roll lags cmd_roll (row 5: 5/33.6 of the way)", t.value(5, "cmd_roll") == 1.0 and absf(t.value(5, "srv_roll") - 5.0 / 33.6) < 1e-9, str(t.value(5, "srv_roll")))
	# The airplane responds to the surface, not the stick: the roll rate builds up only as the aileron moves.
	_check("roll rate after 1 tick is small (aileron at 3 %)", absf(t.value(1, "p_radps")) < 0.05, str(t.value(1, "p_radps")))
	_check("roll rate well established after 0.3 s", t.value(72, "p_radps") > 1.0, str(t.value(72, "p_radps")))

	# Servos never overshoot and follow a reversal at the same rate.
	inputs[0] = -1.0
	sim.inputs = inputs
	var prev: float = sim.aux[1]
	var max_step := 0.0
	for i in 80:
		sim.step()
		max_step = maxf(max_step, absf(sim.aux[1] - prev))
		prev = sim.aux[1]
	_check("reversal at the servo rate, ends exactly at −1", sim.aux[1] == -1.0 and absf(max_step - rate / 240.0) < 1e-12, "%s %s" % [sim.aux[1], max_step])

	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
