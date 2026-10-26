## Accepted contact audio captures brief support transitions without player work.
extends SceneTree
const Audio := preload("res://audio/ground_audio.gd")
var checks := 0
var failed := 0

func _initialize() -> void: call_deferred("_run")

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1; printerr("FAIL ", label)

func contact(id := "main", loaded := false, approach := 2.0) -> Dictionary:
	return {id = id, position = Vector3(1.0, 0.0, 2.0), normal_force_n = 20.0 if loaded else 0.0,
		reference_load_n = 10.0, approach_speed_mps = approach, rolling_speed_mps = 3.0, surface = "grass"}

func snap(tick: int, contacts: Array, paused := false, rate := 240.0) -> Dictionary:
	return {tick = tick, tick_rate = rate, paused = paused, contacts = contacts}

func rig() -> Node:
	var a := Audio.new()
	a.configure(root, &"Master")
	a.set_accepted_tick_observation(true)
	return a

func airborne(a: Node, first := 0, count := 40, id := "main") -> void:
	for tick: int in range(first, first + count): a.observe_accepted(snap(tick, [contact(id)]))

func render(a: Node, tick: int, paused := false) -> void:
	a.update_contacts(tick, paused, [], 0.0, 1.0 / 60.0, Vector3.ZERO, 240.0)

func _run() -> void:
	root.audio_listener_enable_3d = true
	_brief()
	_lifecycle()
	_bounds()
	_malformed()
	_legacy_parity()
	_rolling_presentation()
	print("Ground accepted ticks: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)

func _brief() -> void:
	var a := rig()
	airborne(a)
	var touchdown := snap(40, [contact("main", true, 0.0)])
	var before := var_to_bytes(touchdown)
	check("accepted loaded endpoint accepted", a.observe_accepted(touchdown))
	check("capture preserves caller snapshot", before == var_to_bytes(touchdown))
	check("capture queues one touchdown and creates no players", a.accepted_diagnostics().queued == 1 and a.get_child_count() == 0 and a.touchdown_events == 0)
	touchdown.contacts[0].position = Vector3(90.0, 90.0, 90.0)
	touchdown.contacts[0].normal_force_n = 0.0
	check("queued cue detached from caller mutation", a._accepted_events[0].contact.position == Vector3(1.0, 0.0, 2.0) and a._accepted_contacts[0].normal_force_n == 20.0)
	a.observe_accepted(snap(41, [contact()]))
	check("brief contact survives separation before render", a.accepted_diagnostics().queued == 1 and not a._accepted_states.main.grounded)
	render(a, 41)
	check("render drains captured contact once", a.accepted_diagnostics().queued == 0 and a.accepted_diagnostics().drained == 1 and a.touchdown_events == 1)
	check("impact remains at actual accepted touchdown point", a._slots[0].impact.global_position == Vector3(1.0, 0.0, 2.0))
	render(a, 41)
	check("repeated render does not replay impact", a.touchdown_events == 1 and a.accepted_diagnostics().drained == 1)
	var old := var_to_bytes([a._accepted_states, a._accepted_contacts])
	a.observe_accepted(snap(41, [contact("main", true)]))
	check("duplicate tick cannot change accepted history", old == var_to_bytes([a._accepted_states, a._accepted_contacts]))
	# Re-entry before the real airborne/cooldown windows is chatter, not a new cue.
	a.observe_accepted(snap(42, [contact("main", true)]))
	check("brief bounce chatter retains original audio debounce", a.accepted_diagnostics().observed == 1)
	airborne(a, 43, 200)
	a.observe_accepted(snap(243, [contact("main", true, 0.0)]))
	check("later supported touchdown after real airborne time remains audible", a.accepted_diagnostics().observed == 2 and a.accepted_diagnostics().queued == 1)
	a.free()
	# Stale high descent must not override the immediately preceding accepted rate.
	a = rig()
	airborne(a)
	a.observe_accepted(snap(40, [contact("main", false, 0.0)]))
	a.observe_accepted(snap(41, [contact("main", true, 0.0)]))
	check("past dive cannot fabricate later settled impact", a.accepted_diagnostics().observed == 0)
	a.free()

func _lifecycle() -> void:
	var a := rig()
	airborne(a)
	a.observe_accepted(snap(40, [contact("main", true)]))
	a.observe_accepted(snap(40, [], true))
	check("same-tick pause discards queued sound without render", a.accepted_diagnostics().queued == 0 and a.accepted_diagnostics().discarded == 1)
	a.observe_accepted(snap(41, [contact("main", true)]))
	render(a, 41)
	check("resume into support primes without playback", a.touchdown_events == 0)
	airborne(a, 42, 40)
	a.observe_accepted(snap(82, [contact("main", true)]))
	a.observe_accepted(snap(100, [contact("main", true)]))
	check("missing accepted ticks discard history and prime", a.accepted_diagnostics().queued == 0 and a._accepted_states.main.airborne_s == 0.0)
	airborne(a, 101, 40)
	a.observe_accepted(snap(141, [contact("main", true)]))
	a.observe_accepted(snap(142, [contact("main", true)], false, 480.0))
	check("rate change discards history and primes", a.accepted_diagnostics().queued == 0)
	a.observe_accepted(snap(0, [contact("main", true)]))
	check("rewind primes loaded contact without event", a.accepted_diagnostics().tick == 0 and a.accepted_diagnostics().queued == 0)
	a.reset()
	check("reset clears history and diagnostics", a.accepted_diagnostics().tick == -1 and a.accepted_diagnostics().states == 0 and a.accepted_diagnostics().observed == 0)
	airborne(a)
	a.observe_accepted(snap(40, [contact("main", true)]))
	root.remove_child(a)
	root.add_child(a)
	check("detach drops unheard flight interval", a.accepted_diagnostics().queued == 0 and a.accepted_diagnostics().tick == -1)
	a.observe_accepted(snap(1000, [contact("main", true)]))
	render(a, 1000)
	check("reattached loaded contact does not replay", a.touchdown_events == 0)
	airborne(a)
	a.observe_accepted(snap(40, [contact("main", true)]))
	check("new post-rewind landing captured before first render", a.accepted_diagnostics().queued == 1)
	render(a, 40)
	check("render rewind preserves legitimate newly captured cue", a.touchdown_events == 1 and a.accepted_diagnostics().drained == 1)
	a.free()

func _bounds() -> void:
	var a := rig()
	# Nine landing cycles in eight simultaneous slots over four ticks per second:
	# enough elapsed accepted time for the unchanged cooldown, with no rendering.
	var tick := 0
	for cycle: int in 9:
		for _air in 4:
			var rows := []
			for i in 8: rows.append(contact("wheel_%d" % i))
			a.observe_accepted(snap(tick, rows, false, 4.0))
			tick += 1
		var rows := []
		for i in 8: rows.append(contact("wheel_%d" % i, true))
		a.observe_accepted(snap(tick, rows, false, 4.0))
		tick += 1
	check("accepted queue and state are explicitly bounded", a.accepted_diagnostics().queued == 64 and a.accepted_diagnostics().states == 8)
	check("overflow retains newest history with counted drops", a.accepted_diagnostics().observed == 72 and a.accepted_diagnostics().overflowed == 8 and a.accepted_diagnostics().discarded == 8)
	check("even overflow capture creates no audio nodes", a.get_child_count() == 0)
	a.update_contacts(tick - 1, false, [], 0.0, .01, Vector3.ZERO, 4.0)
	check("old cues expire rather than replay whole stall", a.accepted_diagnostics().discarded == 64 and a.accepted_diagnostics().drained == 8)
	check("playback remains within existing 32-player pool", a.contact_slot_count == 8 and a.get_child_count() == 32 and a.touchdown_events == 8)
	a.free()

func _malformed() -> void:
	var a := rig()
	var bad: Array = []
	for value: Variant in [null, false, 1.5, -1, 9007199254740992, [], {}]:
		var s := snap(0, []); s.tick = value; bad.append(s)
	for value: Variant in [null, false, NAN, INF, 0, 10001, [], {}]:
		var s := snap(0, []); s.tick_rate = value; bad.append(s)
	for value: Variant in [null, 0, "false", [], {}]:
		var s := snap(0, []); s.paused = value; bad.append(s)
	for value: Variant in [null, {}, PackedFloat64Array(), [null], [contact(), contact()]]:
		var s := snap(0, []); s.contacts = value; bad.append(s)
	for key: String in ["normal_force_n", "reference_load_n", "approach_speed_mps", "rolling_speed_mps"]:
		for value: Variant in [null, false, NAN, INF, -1, [], {}]:
			var c := contact(); c[key] = value; bad.append(snap(0, [c]))
	for value: Variant in [null, [], &"id", "", "x".repeat(129)]:
		var c := contact(); c.id = value; bad.append(snap(0, [c]))
	for value: Variant in [null, [], Vector3(NAN, 0.0, 0.0)]:
		var c := contact(); c.position = value; bad.append(snap(0, [c]))
	for s: Dictionary in bad:
		check("malformed snapshot quietly refuses and clears history", not a.observe_accepted(s) and a.accepted_diagnostics().tick == -1)
	check("all malformed refusals counted", a.accepted_diagnostics().refused == bad.size())
	a.free()

func _legacy_parity() -> void:
	# Complete pre-refactor legacy state/layer/impact trace captured independently
	# before promotion. This is presentation compatibility, not a golden flight.
	var a := Audio.new()
	a.configure(root, &"Master")
	var rows := []
	var c := {id = "main", position = Vector3(1.0, 2.0, 3.0), normal_force_n = 0.0,
		reference_load_n = 10.0, approach_speed_mps = 2.0, rolling_speed_mps = 3.0, surface = "grass"}
	for tick in 100:
		c.normal_force_n = 20.0 if tick >= 50 else 0.0
		c.approach_speed_mps = 0.0 if tick >= 50 else 2.0
		c.surface = "grass" if tick < 70 else "hard"
		a.update_contacts(tick, tick >= 85 and tick < 90, [c], .3, 1.0 / 60.0, Vector3.ZERO, 240.0)
		rows.append([a._slots[0].state.duplicate(true), a._slots[0].layer_gain.duplicate(),
			a._slots[0].impact_gain, a.touchdown_events])
	check("legacy complete presentation trace preserves frozen original bytes",
		var_to_bytes(rows).hex_encode().sha256_text() == "a0e755d2caa50a5e8515d16ad96d83ccfd00ff554319794588bf0799c171fb40")
	a.free()

func _rolling_presentation() -> void:
	var a := rig()
	var c := contact("main", true)
	a.observe_accepted(snap(0, [c]))
	render(a, 0)
	check("accepted rolling retains render-owned pitch state", a._slots[0].state.has("roll_pitch"))
	var before: float = a._slots[0].state.get("roll_pitch", 0.0)
	c.rolling_speed_mps = 10.0
	a.observe_accepted(snap(1, [c]))
	render(a, 1)
	var after: float = a._slots[0].state.get("roll_pitch", 0.0)
	check("new wheel speed crossfades pitch rather than losing history", after > before and after < .85 + .025 * sqrt(10.0))
	check("render pitch never enters accepted contact state", not a._accepted_states.main.has("roll_pitch"))
	a.free()
