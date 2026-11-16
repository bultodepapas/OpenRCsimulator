# Audit observation probe for cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b.
# Uses the supported research/test air start; this is not the normal pad-start route.
# A successful probe reproduces over-capacity charge, not correct product behavior.
extends SceneTree

const Session := preload("res://sim/multirotor/session.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print("%s %s %s" % ["OBSERVED" if condition else "NOT OBSERVED", label, detail])

func _run() -> void:
	var s: Node = Session.new()
	root.add_child(s)
	var prepared: bool = s.prepare({}, {start = "air", altitude_m = 20.0, initial_soc = 1.0})
	_check("unmodified shipped document prepares through research air start", prepared, str(s.load_error))
	if prepared:
		var capacity: float = s.sim.continuous[Plant.C_CHARGE]
		var initial_rpm: float = s.sim.continuous[0]
		_check("session resumes", s.resume(), "initial charge %.9f C, shaft %.6f rad/s" % [capacity, initial_rpm])
		var pilot: PackedFloat64Array = FC.neutral_input()
		_check("ready OFF input commits", s.tick_once(pilot), "charge %.9f C" % s.sim.continuous[Plant.C_CHARGE])
		pilot[FC.IN_ARM] = 1.0
		_check("zero-throttle ON input commits", s.tick_once(pilot), "charge %.9f C, motor mode %d" % [s.sim.continuous[Plant.C_CHARGE], s.sim.modes[FC.MODE_MOTOR]])
		var telemetry: Dictionary = s.plant.telemetry(s.frame())
		_check("research air start overcharges without manually editing a frame", s.sim.continuous[Plant.C_CHARGE] > capacity \
			and float(telemetry.soc) == 1.0 and float(telemetry.consumed_mah) < 0.0,
			"capacity %.9f C -> %.9f C, SOC %.9f, consumed %.9f mAh, fault '%s'" % [capacity,
				s.sim.continuous[Plant.C_CHARGE], telemetry.soc, telemetry.consumed_mah, s.fault_reason])
	s.free()
	print("air-start regen: %d checks, %d not reproduced" % [_checks, _failures])
	quit(1 if _failures else 0)
