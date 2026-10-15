extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")

const AIRCRAFT_ID := "sebart-avanti-s-a200-p100rx"
const TEST_COMMAND := [0.8, -0.4, 0.3, 0.6]

var _before_step_count := 0


func _initialize() -> void:
	var entry: Dictionary = Catalog.entry(AIRCRAFT_ID)
	if entry.is_empty():
		printerr("DIAG_ERROR missing catalog entry: ", AIRCRAFT_ID)
		quit(2)
		return

	var flight := Flight.new()
	flight.setup(entry.data, AIRCRAFT_ID)
	flight.input_enabled = false
	if not flight.is_flyable():
		printerr("DIAG_ERROR aircraft is not flyable: ", flight.aircraft.get("reason", "unknown"))
		flight.free()
		quit(2)
		return

	var initial_inputs: PackedFloat64Array = flight.sim.inputs.duplicate()
	var initial_state: PackedFloat64Array = flight.sim.state.duplicate()
	var initial_previous: PackedFloat64Array = flight.sim.previous.duplicate()
	var initial_aux: PackedFloat64Array = flight.sim.aux.duplicate()
	var initial_continuous: PackedFloat64Array = flight.sim.continuous.duplicate()
	var initial_modes: PackedInt64Array = flight.sim.modes.duplicate()
	var initial_loads: PackedFloat64Array = flight.sim.last_loads.duplicate()
	var initial_tick: int = flight.sim.tick
	var input_size_before: int = flight.sim.input_size
	var gear_is_retractable: bool = flight.gear_is_retractable()
	_before_step_count = 0
	flight.sim.before_step.connect(_on_before_step)
	flight.sim.inputs = PackedFloat64Array(TEST_COMMAND)
	flight.sim.step()

	var report := {
		"aircraft_id": AIRCRAFT_ID,
		"flyable": flight.is_flyable(),
		"retractable_gear": gear_is_retractable,
		"declared_input_size_before": input_size_before,
		"initialized_input_length": initial_inputs.size(),
		"initialized_inputs": initial_inputs,
		"attempted_command_length": TEST_COMMAND.size(),
		"attempted_command": TEST_COMMAND,
		"tick_before": initial_tick,
		"tick_after": flight.sim.tick,
		"fault_reason": flight.sim.fault_reason,
		"before_step_signal_count": _before_step_count,
		"input_size_after": flight.sim.input_size,
		"inputs_after_rollback": flight.sim.inputs,
		"input_length_after_rollback": flight.sim.inputs.size(),
		"state_unchanged": var_to_bytes(flight.sim.state) == var_to_bytes(initial_state),
		"previous_unchanged": var_to_bytes(flight.sim.previous) == var_to_bytes(initial_previous),
		"aux_unchanged": var_to_bytes(flight.sim.aux) == var_to_bytes(initial_aux),
		"continuous_unchanged": var_to_bytes(flight.sim.continuous) == var_to_bytes(initial_continuous),
		"modes_unchanged": var_to_bytes(flight.sim.modes) == var_to_bytes(initial_modes),
		"loads_unchanged": var_to_bytes(flight.sim.last_loads) == var_to_bytes(initial_loads),
		"inputs_restored_exactly": var_to_bytes(flight.sim.inputs) == var_to_bytes(initial_inputs),
	}
	print("SERVO_STEP_DIAGNOSTIC " + JSON.stringify(report))
	var reproduced: bool = flight.sim.tick == 0 \
		and flight.sim.fault_reason == "step rejected: input or auxiliary state is nonfinite or malformed" \
		and _before_step_count == 0 \
		and input_size_before == 6 \
		and initial_inputs.size() == 6 \
		and flight.sim.inputs.size() == 6 \
		and var_to_bytes(flight.sim.inputs) == var_to_bytes(initial_inputs) \
		and var_to_bytes(flight.sim.state) == var_to_bytes(initial_state) \
		and var_to_bytes(flight.sim.aux) == var_to_bytes(initial_aux) \
		and var_to_bytes(flight.sim.continuous) == var_to_bytes(initial_continuous) \
		and var_to_bytes(flight.sim.modes) == var_to_bytes(initial_modes) \
		and var_to_bytes(flight.sim.last_loads) == var_to_bytes(initial_loads)
	flight.free()
	quit(0 if reproduced else 1)


func _on_before_step(_tick: int) -> void:
	_before_step_count += 1
