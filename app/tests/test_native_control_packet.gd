## Fixed-wing ABI 2 at the GDScript/native call boundary. The receiver records
## the arguments and refusal order without loading a platform extension.
extends SceneTree

const Stage := preload("res://sim/native_stage.gd")
const Config := preload("res://sim/native/stage_config.gd")


class Session extends Node:
	var sim: Node:
		get: return self
	var state := PackedFloat64Array()
	var continuous := PackedFloat64Array([0.375])
	var modes := PackedInt64Array()
	var aircraft := {model = {propulsion = {kind = "gas"}}}
	var engine_running := true
	var _flap_mix_owner := "simulator"
	var downwash := -1
	var samples := 0

	func time() -> float: return 4.25
	func downwash_index() -> int: return downwash
	func propulsion_throttle() -> float: return 0.625
	func propulsion_power_enabled() -> bool: return false
	func failure_power_cut_active() -> bool: return false

	func _should_capture_substep_context(body, internals, at: float) -> bool:
		return body == state and internals == continuous and at == time()

	func _deflections(aux: PackedFloat64Array) -> Dictionary:
		samples += 1
		return {aileron_left = aux[3] + 0.125, flap = aux[4] * 0.5, elevator = aux[1] + 0.5,
			rudder = aux[2] - 0.125, aileron_right = aux[0] - 0.25}


class Receiver extends RefCounted:
	var calls: Array = []
	var refuse := ""
	var next_aux := PackedFloat64Array([7.0, -11.0, 5.0, -13.0, 17.0, -991.0])

	func set_tick_context(aux, inputs, packet, at) -> bool:
		calls.append(["tick", aux, inputs, packet, at])
		return refuse != "tick"

	func set_power_context(throttle, enabled) -> bool:
		calls.append(["power", throttle, enabled])
		return refuse != "power"

	func set_glow_context(throttle, running, cut) -> bool:
		calls.append(["glow", throttle, running, cut])
		return refuse != "glow"

	func set_preview_context(body, internals, capture) -> bool:
		calls.append(["preview", body, internals, capture])
		return refuse != "preview"

	func stage_wing_wake(body, air, packet, up) -> float:
		calls.append(["wake", body, air, packet, up])
		return 1.75

	func pre_step(aux, inputs, dt, body, internals, at, running, flap_mix, packet, rng) -> PackedFloat64Array:
		calls.append(["pre", aux, inputs, dt, body, internals, at, running, flap_mix, packet, rng])
		return next_aux


var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	# Use literal expected bytes independently of the packet builder. Ordinary
	# numerical equality hides both negative zero and a narrowing conversion.
	var d := {rudder = -4.5, aileron_left = 3.75, elevator = 1.0000000000000002, aileron_right = -2.25}
	var expected := PackedFloat64Array([1.0000000000000002, -2.25, 3.75, -4.5, 0.0])
	var first := Config.pack_deflections(d)
	check("four required channels and an omitted flap", first.to_byte_array() == expected.to_byte_array())
	d.flap = -0.0
	expected[4] = -0.0
	var second := Config.pack_deflections(d)
	check("explicit negative zero flap", second.to_byte_array() == expected.to_byte_array())
	first[0] = 99.0
	check("separate packets retain their values", second.to_byte_array() == expected.to_byte_array()
		and d.elevator == 1.0000000000000002)

	var session := Session.new()
	var receiver := Receiver.new()
	var stage := Stage.new()
	stage._native = receiver
	stage._installed = true
	stage._wing_wake_bound = true
	stage._pre_step_bound = true
	var old := PackedFloat64Array([-0.125, 0.25, -0.375, 0.5, -0.625, 999.0])
	var old_packet := PackedFloat64Array([0.75, -0.375, 0.625, -0.5, -0.3125])
	var next_packet := PackedFloat64Array([-10.5, 6.75, -12.875, 4.875, 8.5])
	var inputs := PackedFloat64Array([0.875])
	var dt := 1.0 / 240.0
	# Call the two adapter entry points explicitly. The pre-step should sample
	# incoming aux only with downwash; tick context should sample its own aux.
	for slot in [-1, 0]:
		session.downwash = slot
		var before := session.samples
		receiver.calls.clear()
		var next := stage.pre_step(session, old, inputs, dt)
		var packet := old_packet if slot >= 0 else PackedFloat64Array()
		check("pre-step downwash slot %d" % slot, session.samples == before + int(slot >= 0)
			and receiver.calls == [["pre", old, inputs, dt, session.state, session.continuous,
				session.time(), true, true, packet, 0]] and next == receiver.next_aux)
		stage._family = "wheel"
		receiver.calls.clear()
		check("wheel tick uses returned aux %d" % slot, stage.tick_context(session, next, inputs)
			and receiver.calls == [["tick", next, inputs, next_packet, session.time()]])

	var air := {v_air = PackedFloat64Array([1, 2, 3]), V = 4.0, alpha = 5.0, beta = 6.0, qbar = 7.0}
	receiver.calls.clear()
	check("wing wake receives body, air, deflections and ground height",
		stage.wing_wake(session.state, air, d, -3.0) == 1.75
		and receiver.calls == [["wake", session.state, PackedFloat64Array([1, 2, 3, 4, 5, 6, 7]), expected, -3.0]])

	session.state.resize(13)
	for family: String in ["electric", "liquid", "glow", "prescribed"]:
		stage._family = family
		session.aircraft.model.propulsion.kind = "turbine" if family == "prescribed" else "gas"
		var expected_calls := [["tick", old, inputs, old_packet, session.time()]]
		if family == "glow":
			expected_calls.append(["glow", 0.625, true, false])
		else:
			expected_calls.append(["power", 0.625, family == "prescribed"])
		if family in ["liquid", "prescribed"]:
			expected_calls.append(["preview", session.state, session.continuous, true])
		receiver.calls.clear()
		receiver.refuse = ""
		check(family + " accepts ordered context", stage.tick_context(session, old, inputs)
			and receiver.calls == expected_calls)
		for i in expected_calls.size():
			receiver.calls.clear()
			receiver.refuse = expected_calls[i][0]
			check(family + " stops at refused " + receiver.refuse, not stage.tick_context(session, old, inputs)
				and receiver.calls == expected_calls.slice(0, i + 1))

	session.free()
	print("Fixed-wing native control packet: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
