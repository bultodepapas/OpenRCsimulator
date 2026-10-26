## Disposable GP reset audit: reproduce publication before a refused commit.
extends SceneTree
const Session := preload("res://sim/flight_session.gd")
const Field := preload("res://data/field_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Log := preload("res://sim/flight_log.gd")
var checks := 0
var failed := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failed += 1
		printerr("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	Engine.physics_ticks_per_second = 240
	var field: Dictionary = Field.load_from().field
	var spot: Dictionary = GroundStart.threshold(field)
	for action: String in ["hold", "mass"]:
		var session := Session.new()
		session.input_enabled = false
		session.crash_auto_restart = false
		session.setup()
		check(action + " field", session.set_field(field))
		# Opt into the existing generic endpoint contract without changing forces,
		# continuous layout, or stock aircraft data. No advanced ground activation.
		var sim: Node = session.sim
		sim.model.aux_size = sim.aux.size()
		sim.model.continuous_size = sim.continuous.size()
		sim.model.modes_size = sim.modes.size()
		sim.model.state_layout_identity = "disposable-runway-reset-audit-v1"
		check(action + " endpoint reset", sim.reset(sim.state.duplicate()))
		for i: int in 2: sim.step()
		check(action + " prior tick accepted", sim.tick == 2 and sim.fault_reason.is_empty())
		var writer := Log.new(session)
		var path := "C:/DEVELOPMENT/OpenRCsimulator/tmp/gp-reset-transaction/" + action + "-" + str(Time.get_ticks_usec()) + ".orfl"
		check(action + " actual recorder starts", writer.start(path) == OK and writer.recording)
		var events := [0, 0]
		var old_tick: int = sim.tick
		var old_state: PackedByteArray = sim.state.to_byte_array()
		var old_aux: PackedByteArray = sim.aux.to_byte_array()
		var old_contact: PackedByteArray = var_to_bytes(session.contact_events())
		var old_mass: float = sim.mass
		session.resetting.connect(func() -> void:
			events[0] += 1
			if action == "hold": session.hold("companions-reset")
			else: sim.mass = 0.0)
		sim.stepped.connect(func(_k, _t, _s, _l, _i, _a) -> void: events[1] += 1)
		var result: Dictionary = session.try_runway_start(spot.north, spot.east, spot.heading)
		var receipt := {action = action, reported_ok = result.ok, status = result.get("status"),
			before_tick = old_tick, after_tick = sim.tick, state_unchanged = old_state == sim.state.to_byte_array(),
			aux_unchanged = old_aux == sim.aux.to_byte_array(), contacts_unchanged = old_contact == var_to_bytes(session.contact_events()),
			resetting = events[0], stepped = events[1], recorder_still_recording = writer.recording,
			checkpoint_available = not session.checkpoint().is_empty(), prior_mass = old_mass, mass = sim.mass,
			holds = session.holds, paused = sim.paused, fault = sim.fault_reason}
		print("RESET_AUDIT ", JSON.stringify(receipt))
		check(action + " reproduces false-success without tick publication", result.ok and sim.tick == old_tick
			and old_state == sim.state.to_byte_array() and events == [1, 0])
		check(action + " recorder closed despite no accepted reset", not writer.recording)
		check(action + " attempted candidate aux survives refused commit", old_aux != sim.aux.to_byte_array())
		writer.stop("audit cleanup")
		session.free()
	print("Reset transaction audit: %d checks, %d failed" % [checks, failed])
	quit(1 if failed else 0)
