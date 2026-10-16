extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Surfaces := preload("res://physics/control_surfaces.gd")
const Main := preload("res://main.gd")

class AsymmetricObservation extends Node:
	func throws_deg() -> Dictionary:
		return {aileron = 30.0, aileron_down = 10.0, elevator = 20.0, rudder = 40.0}
	func surface_angles_deg() -> Dictionary:
		return {aileron_right = 15.0, aileron_left = 0.0, elevator = -3.0, rudder = 5.0}

var checks := 0
var failures := 0


func _check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL surface observation: ", label)


func _initialize() -> void:
	for aircraft_id: String in Catalog.airplane_flyable_ids():
		var flight := Flight.new()
		flight.setup(Catalog.entry(aircraft_id).data, aircraft_id)
		flight.input_enabled = false
		_check(aircraft_id + " validates", flight.is_flyable())
		if not flight.is_flyable():
			flight.free()
			continue
		var initial: Dictionary = flight.checkpoint()
		var initial_angles: Dictionary = flight.surface_angles_deg()
		var servo_inputs: PackedFloat64Array = flight.sim.inputs.duplicate()
		servo_inputs[0] = 0.8
		servo_inputs[1] = -0.4
		servo_inputs[2] = 0.3
		servo_inputs[3] = 0.6
		if flight.flaps_available():
			servo_inputs[flight.flap_input_index()] = 0.6
		flight.sim.inputs = servo_inputs
		flight.sim.step()
		_check(aircraft_id + " accepts a servo step", flight.sim.tick == 1)
		var accepted: Dictionary = flight.checkpoint()
		var angles: Dictionary = flight.surface_angles_deg()
		_check(aircraft_id + " observes actual positions distinct from full demand",
			angles.aileron_right != 0.8 * flight.throws_deg().aileron)
		var expected_deflections: Dictionary = Surfaces.deflections_from_surfaces(angles)
		if flight.flaps_available():
			var accepted_aux: PackedFloat64Array = accepted.simulation.aux
			var flap_fraction: float = accepted_aux[flight.flap_aux_index()]
			_check(aircraft_id + " accepts a nonzero flap servo position", flap_fraction > 0.0)
			expected_deflections.flap = deg_to_rad(
				flap_fraction * float(flight.aircraft.model.flaps.max_angle_deg))
		_check(aircraft_id + " aero receives the observed surface angles",
			var_to_bytes(flight._deflections(flight.sim.aux)) == var_to_bytes(expected_deflections))
		angles.aileron_right = 999.0
		_check(aircraft_id + " observation is detached and read-only",
			flight.surface_angles_deg().aileron_right != 999.0
			and var_to_bytes(flight.checkpoint()) == var_to_bytes(accepted))
		_check(aircraft_id + " restore restores the same surface observation",
			flight.restore_checkpoint(initial) and flight.surface_angles_deg() == initial_angles)
		flight.free()

	var main := Main.new()
	var observation := AsymmetricObservation.new()
	main.session = observation
	var command := {roll = 0.2, pitch = 0.4, yaw = -0.1, throttle = 0.5}
	var rotations: Dictionary = main._surface_rotations_for_render(command)
	_check("physical rendering reads asymmetric actual positions, not the logical roll command",
		rotations.aileron_right.x == -deg_to_rad(15.0) and rotations.aileron_left.x == 0.0
		and rotations.elevator.x == deg_to_rad(3.0) and rotations.rudder.y == deg_to_rad(5.0))
	main._scripted = true
	rotations = main._surface_rotations_for_render(command)
	_check("scripted captures keep their explicit commands and differential throw",
		is_equal_approx(rotations.aileron_right.x, -deg_to_rad(6.0))
		and is_equal_approx(rotations.aileron_left.x, deg_to_rad(2.0))
		and is_equal_approx(rotations.elevator.x, -deg_to_rad(8.0))
		and is_equal_approx(rotations.rudder.y, -deg_to_rad(4.0)))
	main.free()
	observation.free()
	print("Control surface observation: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
