# Deterministic production-class probes for the input-contract follow-up.
# Injected readings/identities; these do not establish hardware incidence, event
# delivery while unfocused, OS focus state, UI behavior, or storage I/O failure.
# The owner executes this with the repository's checked Godot runner.
extends SceneTree

const RcInput = preload("res://input/rc_input.gd")
const Profile = preload("res://input/controller_profile.gd")
const Flight = preload("res://sim/flight_session.gd")
const DEVICE := 15
const DT := 1.0 / 240.0

var checks := 0
var failures := 0
var results: Array[Dictionary] = []


class CompletedCalibration extends RefCounted:
	var profile: Dictionary
	var aux_warning := ""
	func _init(candidate: Dictionary) -> void:
		profile = candidate.duplicate(true)
	func advance(_axes: PackedFloat64Array) -> bool:
		return true


func check(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks += 1
	if not passed:
		failures += 1
	results.append({"name": name, "passed": passed, "details": details})


func _initialize() -> void:
	var info := {"name": "Synthetic raw radio", "kind": "radio", "guid": "fixture"}
	var p: Dictionary = Profile.defaults("radio", "radio_custom")
	var radio = RcInput.new()

	# One event marks roll seen. A subsequent independent poll supplies a different
	# roll value; there are deliberately no events between these operations.
	radio.connect_device(DEVICE, info, p)
	radio.on_motion(DEVICE, 0, 0.8)
	radio.on_motion(DEVICE, 2, -1.0)
	radio.poll(func(_id: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0, DT)
	var mismatched: Dictionary = radio.sticks()
	check("event_seen_but_command_uses_different_poll", radio.armed and radio.has_axis_sample(0) \
		and absf(float(mismatched.roll)) < 1.0e-12,
		{"roll_event": 0.8, "subsequent_roll_poll": 0.0, "event_seen": radio.has_axis_sample(0),
		"command_roll": mismatched.roll, "armed": radio.armed})

	# A radio-to-radio profile activation retains legacy diagnostic event history.
	radio.connect_device(DEVICE, info, p)
	radio.on_motion(DEVICE, 4, 0.6)
	var remap: Dictionary = p.duplicate(true)
	remap.roll.axis = 4
	var applied: bool = radio.use_profile(remap, "injected remap")
	check("new_mapping_inherits_historical_axis_seen", applied and not radio.armed and radio.has_axis_sample(4),
		{"new_roll_axis": 4, "event_before_activation": 0.6, "seen_after_activation": radio.has_axis_sample(4),
		"armed_after_activation": radio.armed})

	# Model a focus-loss reset followed by a LOW event and a non-integrating poll.
	# The reader has no OS-focus argument: this models call ordering only.
	radio.connect_device(DEVICE, info, p)
	radio.require_neutral(true, true)
	radio.on_motion(DEVICE, 2, -1.0)
	radio.poll(func(_id: int, axis: int) -> float: return -1.0 if axis == 2 else 0.0, DT, Callable(), false)
	check("post_reset_low_can_arm_during_nonintegrating_poll", radio.armed and not radio.has_axis_sample(0),
		{"post_reset_throttle_event": -1.0, "integrate": false, "armed": radio.armed,
		"roll_event_seen": radio.has_axis_sample(0)})

	# Unarmed is a throttle gate for an absolute radio, not a gate on surfaces.
	radio.connect_device(DEVICE, info, p)
	radio.on_motion(DEVICE, 0, 0.8)
	radio.poll(func(_id: int, axis: int) -> float: return 0.8 if axis == 0 else (-1.0 if axis == 2 else 0.0), DT)
	var unarmed: Dictionary = radio.sticks()
	check("unarmed_radio_still_reports_surface", not radio.armed and absf(float(unarmed.roll) - 0.8) < 1.0e-12 \
		and float(unarmed.throttle) == 0.0,
		{"armed": radio.armed, "roll": unarmed.roll, "throttle": unarmed.throttle})

	# The direct calibration route rejects a duplicate legacy identity for storage,
	# but only after applying the candidate. No filesystem write is attempted.
	var session = Flight.new()
	var direct_info := {"name": "Twin radio", "kind": "radio", "guid": "same-key", "known": false}
	session.device_info = func(_id: int) -> Dictionary: return direct_info.duplicate(true)
	session.connected_device_ids = func() -> Array: return [DEVICE, DEVICE + 1]
	session.radio.connect_device(DEVICE, direct_info, p)
	var before: Dictionary = session.radio.profile.duplicate(true)
	var measured: Dictionary = p.duplicate(true)
	measured.roll.center = 0.2
	session.calibration = CompletedCalibration.new(measured)
	session.cancel_calibration()
	check("cancelled_candidate_leaves_active_profile", session.calibration == null and session.radio.profile == before,
		{"unchanged": session.radio.profile == before})
	session.calibration = CompletedCalibration.new(measured)
	session.advance_calibration()
	check("direct_duplicate_identity_refuses_save_after_activation", session.calibration == null \
		and absf(float(session.radio.profile.roll.center) - 0.2) < 1.0e-12 \
		and session.radio.profile != before and "NOT saved" in session.pause_reason,
		{"old_center": before.roll.center, "active_center_after": session.radio.profile.roll.center,
		"pause_reason": session.pause_reason, "filesystem_save_called": false})

	# Managed route with an injected rejecting persistence callback: the failed
	# candidate is retained in a lease-bound pending draft, not activated here.
	session.external_controller_selection = true
	session.radio.connect_device(DEVICE, direct_info, p)
	before = session.radio.profile.duplicate(true)
	session._calibration_generation = 12
	session.controller_connection_generation = func(_id: int) -> int: return 12
	session.persist_controller_profile = func(_candidate: Dictionary) -> Dictionary: return {"ok": false, "error": "injected refusal"}
	session.calibration = CompletedCalibration.new(measured)
	session.advance_calibration()
	var pending: Dictionary = session.pending_controller_calibration
	check("managed_refusal_retains_pending_without_activation", session.radio.profile == before \
		and pending.get("profile", {}) == measured and int(pending.get("generation", -1)) == 12 \
		and "injected refusal" in session.pause_reason,
		{"active_unchanged": session.radio.profile == before, "pending_generation": pending.get("generation", -1),
		"pause_reason": session.pause_reason})
	session.free()

	print("FOLLOWUP_INPUT_PROBE_JSON ", JSON.stringify({"head": "00610ce3df391560dc195444d797bb81f2f83270",
		"scope": "synthetic production-class inputs and duplicate identity; no hardware, real focus or storage I/O failure",
		"checks": checks, "failures": failures, "complete": true, "results": results}))
	quit(0 if failures == 0 else 1)
