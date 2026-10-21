extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const Trial := preload("res://workshop/trial.gd")
const Presentation := preload("res://workshop/presentation.gd")
const FINITE_GLOW_ID := "stik-glow-61fx-2t"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bindings_result: Dictionary = Customization.describe(FINITE_GLOW_ID)
	check("default aircraft has verified smoke bindings", bool(bindings_result.get("ok", false)))
	if not bool(bindings_result.get("ok", false)):
		_finish()
		return
	var bindings: Dictionary = bindings_result.bindings
	var show_slot: Dictionary = {}
	var source_slot: Dictionary = {}
	for slot: Dictionary in bindings.smoke_slots:
		if str(slot.kind) == "show" and show_slot.is_empty():
			show_slot = slot
		elif str(slot.kind) == "source" and source_slot.is_empty():
			source_slot = slot
	check("test aircraft declares both show and source endpoints", not show_slot.is_empty() and not source_slot.is_empty())
	if show_slot.is_empty() or source_slot.is_empty():
		_finish()
		return
	var profile: Dictionary = Presentation.defaults(bindings)
	profile.smoke = [_smoke_entry(str(show_slot.id)), _smoke_entry(str(source_slot.id))]
	var base_bytes: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(FINITE_GLOW_ID).data)
	var frozen: Dictionary = Trial.freeze({
		"base_id": FINITE_GLOW_ID,
		"base_bytes": base_bytes,
		"recipe": {},
		"presentation_profile": profile,
	})
	check("dual-route smoke profile freezes for an isolated trial", bool(frozen.get("ok", false)), str(frozen.get("errors", [])))
	if not bool(frozen.get("ok", false)):
		_finish()
		return

	var disabled: Node = await _start_trial(frozen, PackedStringArray(["--smoke=off", "--smoke-pump=on"]))
	var disabled_evidence: Dictionary = disabled.call("capture_evidence")
	check("global smoke-off suppresses both profile and legacy runtimes",
		disabled.get("_profile_smoke") == null and disabled.get("_smoke") == null
		and not bool(disabled.get("_smoke_key_on"))
		and disabled_evidence.get("smoke_effects", {}).get("mode", "") == "profile"
		and bool(disabled_evidence.smoke_effects.get("disabled", false)), str(disabled.get("startup_error")))
	disabled.queue_free()
	await process_frame

	var flight: Node = await _start_trial(frozen, PackedStringArray(["--smoke-pump=on"]))
	var smoke: Node = flight.get("_profile_smoke") as Node
	check("profile mode owns the shared renderer and accepts the direct pump request",
		smoke != null and flight.get("_smoke") == null and bool(flight.get("_smoke_key_on")))
	if smoke == null:
		flight.queue_free()
		await process_frame
		_finish()
		return
	var capture_state: Dictionary = flight.call("capture_evidence")
	check("capture evidence records profile identity and shared allocation",
		capture_state.get("smoke_effects", {}).get("mode", "") == "profile"
		and capture_state.smoke_effects.get("profile_identity", {}).get("sha256", "") == frozen.presentation_identity.get("sha256", "")
		and bool(capture_state.smoke_effects.get("requested", false))
		and int(capture_state.smoke_effects.get("allocation", {}).get("capacity", 0)) > 0 and int(capture_state.smoke_effects.get("allocation", {}).get("capacity", 0)) <= 768)
	var session: Node = flight.get("session")
	session.physics_enabled = false
	session.set_physics_process(false)
	session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	session.sim.set_physics_process(false)
	check("flight source test uses the finite-glow model", bool(session.glow_is_active()))
	if not bool(session.glow_is_active()):
		flight.queue_free()
		await process_frame
		_finish()
		return

	session.engine_running = true
	var continuous: PackedFloat64Array = session.sim.continuous.duplicate()
	continuous[7] = 1.0
	session.sim.continuous = continuous
	flight.call("_reset_profile_smoke")
	flight.set("_profile_last_running", false)
	flight.call("_sample_profile_smoke", 10, session.sim.time(), session.sim.state,
		PackedFloat64Array(), PackedFloat64Array(), session.sim.aux)
	var on_tape: Array = flight.get("_profile_source_tape")
	var request_tape: Array = flight.get("_profile_request_tape")
	check("direct smoke-pump request enters the 240 Hz request tape",
		request_tape.size() == 1 and int(request_tape[0].tick) == 10 and is_equal_approx(float(request_tape[0].level), 1.0))
	check("running accepted glow source enters the source tape",
		on_tape.size() == 1 and int(on_tape[0].tick) == 10 and bool(on_tape[0].running))
	flight.set("_profile_source_tape", [])
	flight.set("_profile_request_tape", [])

	continuous = session.sim.continuous.duplicate()
	continuous[7] = 0.0
	session.sim.continuous = continuous
	var state_before: PackedFloat64Array = session.sim.state.duplicate()
	var continuous_before: PackedFloat64Array = session.sim.continuous.duplicate()
	var aux_before: PackedFloat64Array = session.sim.aux.duplicate()
	var modes_before: PackedInt64Array = session.sim.modes.duplicate()
	var tick_before: int = session.sim.tick
	var time_before: float = session.sim.time()
	check("stopped accepted source is distinct from enabled ignition command",
		bool(session.propulsion_power_enabled()) and not bool(session.propulsion_source_running()))
	flight.call("_sample_profile_smoke", 11, session.sim.time(), session.sim.state,
		PackedFloat64Array(), PackedFloat64Array(), session.sim.aux)
	var off_tape: Array = flight.get("_profile_source_tape")
	check("accepted finite-glow latch enqueues one exact off event",
		off_tape.size() == 1 and int(off_tape[0].tick) == 11
		and str(off_tape[0].kind) == "glow_prop" and not bool(off_tape[0].running)
		and is_zero_approx(float(off_tape[0].level)))
	check("smoke sampling leaves accepted physics state untouched",
		session.sim.state == state_before and session.sim.continuous == continuous_before
		and session.sim.aux == aux_before and session.sim.modes == modes_before
		and session.sim.tick == tick_before and is_equal_approx(session.sim.time(), time_before))

	flight.queue_free()
	await process_frame
	_finish()


func _start_trial(frozen: Dictionary, args: PackedStringArray) -> Node:
	var flight: Node = load("res://main.tscn").instantiate()
	flight.set_user_args(args)
	flight.set("workshop_trial", frozen.duplicate(true))
	flight.set("aircraft_id", FINITE_GLOW_ID)
	flight.set("interactive_start", true)
	flight.set("start_choice", "airborne")
	flight.set("crash_effects_enabled", false)
	root.add_child(flight)
	await process_frame
	flight.set_process(false)
	flight.set_process_unhandled_input(false)
	return flight


func _smoke_entry(slot_id: String) -> Dictionary:
	return {
		"slot": slot_id,
		"enabled": true,
		"color": "#E54646FF",
		"amount": 0.6,
		"width_m": 0.15,
		"lifetime_s": 1.0,
		"shape": "ribbon",
		"mode": "hold",
		"burst_s": 0.0,
		"pulse_period_s": 0.0,
		"pulse_duty": 0.0,
		"palette": [],
		"step_s": 0.0,
	}


func check(label: String, condition: bool, detail := "") -> void:
	checks += 1
	if condition:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _finish() -> void:
	print("Workshop smoke integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
