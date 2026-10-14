extends SceneTree

const RcInput := preload("res://input/rc_input.gd")

const DEVICE_ID := 7
const DT := 1.0 / 240.0
const TICK_BUDGET_US := 1000000.0 / 240.0
const WARMUP_NEUTRAL_POLLS := 240
const WARMUP_STEADY_POLLS := 1200
const BATCH_COUNT := 5
const POLLS_PER_BATCH := 2400
const EVENT_AXES: Array[int] = [0, 1, 2, 3]
const SAMPLE_AXES := [0.25, 0.0, -0.4, 0.6, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
const INITIAL_RATE_THROTTLE := 0.5


func _initialize() -> void:
	var variant := "unspecified"
	var preflight_only := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
		elif argument == "--preflight-only":
			preflight_only = true
	_run(variant, preflight_only)


func _run(variant: String, preflight_only: bool) -> void:
	var axis_state := {"values": PackedFloat64Array()}
	axis_state.values.resize(10)
	var read_axis: Callable = func(_device_id: int, axis: int) -> float:
		return float(axis_state.values[axis])
	var read_button: Callable = func(_device_id: int, _button: int) -> bool:
		return false
	var reader: Variant = RcInput.new()
	reader.connect_device(DEVICE_ID, {"name": "Synthetic known gamepad", "guid": "f6-cost-probe", "known": true})

	# Start both readers from the same explicit neutral evidence. Current RcInput requires
	# 200 ms of neutral plus released-button observations; the baseline has its older gate.
	axis_state.values.fill(0.0)
	for axis in EVENT_AXES:
		reader.on_motion(DEVICE_ID, axis, 0.0)
	for _tick in WARMUP_NEUTRAL_POLLS:
		reader.poll(read_axis, DT, read_button)
	if not reader.armed or not reader.is_rate_throttle():
		push_error("Synthetic gamepad did not reach the comparable armed rate-throttle state.")
		quit(1)
		return
	if not reader.set_rate_throttle_for_start(INITIAL_RATE_THROTTLE):
		push_error("Synthetic gamepad could not be seeded to the comparable rate-throttle position.")
		quit(1)
		return

	var event_costs: Array[int] = []
	var poll_command_costs: Array[int] = []
	var full_step_costs: Array[int] = []
	var batch_results: Array[Dictionary] = []
	var command_sum := 0.0
	var last_command: Dictionary = {}
	var measured_ticks := 0

	axis_state.values = PackedFloat64Array(SAMPLE_AXES)
	if preflight_only:
		last_command = _step(reader, axis_state, read_axis, read_button, false).command
		if not _valid_command(last_command):
			push_error("Synthetic gamepad produced an invalid preflight command.")
			quit(1)
			return
		var report := _report(variant, true, [], {}, {}, {}, last_command, measured_ticks, command_sum)
		print("F6_INPUT_COST_RESULT " + JSON.stringify(report))
		quit()
		return

	# Warm the mapping/reader path after the neutral gate, with the measured four-axis state.
	for _tick in WARMUP_STEADY_POLLS:
		last_command = _step(reader, axis_state, read_axis, read_button, false).command
	if not _valid_command(last_command):
		push_error("Synthetic gamepad produced an invalid warmup command.")
		quit(1)
		return

	for batch_index in BATCH_COUNT:
		var batch_events: Array[int] = []
		var batch_poll_command: Array[int] = []
		var batch_full_step: Array[int] = []
		for _sample in POLLS_PER_BATCH:
			var timing: Dictionary = _step(reader, axis_state, read_axis, read_button, true)
			batch_events.append(int(timing.event_us))
			batch_poll_command.append(int(timing.poll_command_us))
			batch_full_step.append(int(timing.full_step_us))
			event_costs.append(int(timing.event_us))
			poll_command_costs.append(int(timing.poll_command_us))
			full_step_costs.append(int(timing.full_step_us))
			last_command = timing.command
			command_sum += float(last_command.roll) + float(last_command.pitch) + float(last_command.yaw) + float(last_command.throttle)
			measured_ticks += 1
		batch_results.append({
			"batch": batch_index + 1,
			"samples": POLLS_PER_BATCH,
			"event_callbacks": _stats(batch_events),
			"poll_plus_command": _stats(batch_poll_command),
			"event_to_command": _stats(batch_full_step),
		})

	var report := _report(variant, false, batch_results, _stats(event_costs), _stats(poll_command_costs), _stats(full_step_costs), last_command, measured_ticks, command_sum)
	print("F6_INPUT_COST_RESULT " + JSON.stringify(report))
	quit()


func _step(reader: Variant, axis_state: Dictionary, read_axis: Callable, read_button: Callable, measure: bool) -> Dictionary:
	var start_us := Time.get_ticks_usec() if measure else 0
	for axis in EVENT_AXES:
		reader.on_motion(DEVICE_ID, axis, float(axis_state.values[axis]))
	var before_poll_us := Time.get_ticks_usec() if measure else 0
	reader.poll(read_axis, DT, read_button)
	var command: Dictionary = reader.sticks()
	var end_us := Time.get_ticks_usec() if measure else 0
	if not measure:
		return {"command": command}
	return {
		"event_us": before_poll_us - start_us,
		"poll_command_us": end_us - before_poll_us,
		"full_step_us": end_us - start_us,
		"command": command,
	}


func _stats(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"samples": 0, "median_us": 0.0, "p95_us": 0.0, "p95_budget_percent": 0.0}
	var sorted: Array[int] = samples.duplicate()
	sorted.sort()
	var middle := int(sorted.size() / 2)
	var median_us: float = float(sorted[middle])
	if sorted.size() % 2 == 0:
		median_us = (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	var p95_index := maxi(0, ceili(0.95 * float(sorted.size())) - 1)
	var p95_us := float(sorted[p95_index])
	return {
		"samples": sorted.size(),
		"median_us": median_us,
		"p95_us": p95_us,
		"p95_budget_percent": 100.0 * p95_us / TICK_BUDGET_US,
	}


func _report(variant: String, preflight_only: bool, batches: Array[Dictionary], event_stats: Dictionary,
		poll_stats: Dictionary, full_step_stats: Dictionary, command: Dictionary, measured_ticks: int,
		command_sum: float) -> Dictionary:
	return {
		"format": "openrc-controller-input-cost v1",
		"variant": variant,
		"timestamp_utc": Time.get_datetime_string_from_system(true, true),
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"device": {"id": DEVICE_ID, "name": "Synthetic known gamepad", "known": true, "kind": "gamepad"},
		"sample_axes_0_to_3": [SAMPLE_AXES[0], SAMPLE_AXES[1], SAMPLE_AXES[2], SAMPLE_AXES[3]],
		"axis_value_stage": "Synthetic Godot-facing mapped-axis values at the RcInput seam; raw HID/SDL mapping and event delivery are not measured.",
		"event_axes": EVENT_AXES,
		"read_axis_slots": 10,
		"read_button_semantics": "Callable always returns released. The current reader polls all 128 button indices; the baseline receives the same callable but does not poll buttons for its default gamepad profile. No button hardware or SDL event delivery.",
		"initial_rate_throttle": INITIAL_RATE_THROTTLE,
		"tick_hz": 240,
		"dt_s": DT,
		"tick_budget_us": TICK_BUDGET_US,
		"warmup_neutral_polls": WARMUP_NEUTRAL_POLLS,
		"warmup_steady_polls": 0 if preflight_only else WARMUP_STEADY_POLLS,
		"batch_count": batches.size(),
		"polls_per_batch": POLLS_PER_BATCH if not preflight_only else 0,
		"preflight_only": preflight_only,
		"measurement_scope": "Direct RcInput.on_motion callbacks + RcInput.poll(read_axis, dt, read_button) + RcInput.sticks(). No Input.parse_input_event, SDL/HID/USB/Bluetooth transport, display, renderer, FlightSession, physics simulation, or physical latency.",
		"timing_note": "Time.get_ticks_usec around software callbacks. Both readers start armed after neutral setup and at the same 0.5 virtual throttle. Connection, neutral arming and warmup are outside timed samples. Each measured tick sends four synthetic axis callbacks; event schedule is controlled and is not an engine/SDL delivery-rate model.",
		"measurements": {
			"event_callbacks": event_stats,
			"poll_plus_command": poll_stats,
			"event_to_command": full_step_stats,
			"batches": batches,
		},
		"last_command": command,
		"command_sum": command_sum,
		"measured_ticks": measured_ticks,
	}


func _valid_command(command: Dictionary) -> bool:
	if not command.has("roll") or not command.has("pitch") or not command.has("yaw") or not command.has("throttle"):
		return false
	for key in ["roll", "pitch", "yaw", "throttle"]:
		if not is_finite(float(command[key])):
			return false
	return absf(float(command.throttle) - INITIAL_RATE_THROTTLE) <= 0.000001
