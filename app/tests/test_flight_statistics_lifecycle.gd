extends SceneTree

const Session = preload("res://sim/flight_session.gd")
var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	var service: Node = load("res://statistics/service.gd").new()
	check("in-memory service opens without player files", service.setup("", false))
	var player: Node = Session.new()
	var reference: Node = Session.new()
	player.input_enabled = false
	reference.input_enabled = false
	player.setup()
	reference.setup()
	service.begin_activity(player, "jensen-das-ugly-stik-60", "Ugly Stick")
	for i: int in 300:
		player.sim.step()
		reference.sim.step()
	check("observer leaves exact state unchanged", player.sim.state.to_byte_array() == reference.sim.state.to_byte_array())
	check("observer leaves exact checkpoint unchanged", var_to_bytes(player.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint()))
	var q: Dictionary = service.query()
	check("air start counted once", int(q.started) == 1)
	check("airborne time includes confirmation interval", float(q.airborne_seconds) > 1.2)
	var previous_time: float = float(q.airborne_seconds)
	player.hold("menu")
	for i: int in 50: player.sim.step()
	check("paused ticks do not add time", service.query().airborne_seconds == previous_time)
	var before_count: int = player.sim.stepped.get_connections().size()
	service.suspend_activity()
	check("suspension detaches observer", player.sim.stepped.get_connections().size() == before_count - 1)
	service.resume_activity()
	service.resume_activity()
	check("resume attaches exactly once", player.sim.stepped.get_connections().size() == before_count)
	check("suspension creates no restart", int(service.query().restarts) == 0)
	var generation: int = player.statistics_generation
	player.resetting.connect(func() -> void: player.sim.mass = 0.0, CONNECT_ONE_SHOT)
	var failed_reload: String = player.reload()
	check("failed reload rolled back", failed_reload.begins_with("reload failed;"))
	check("failed reload does not publish success", player.statistics_generation == generation)
	check("failed reload preserves statistics", int(service.query().started) == 1 and int(service.query().restarts) == 0)
	player.reset()
	check("accepted reset increments one restart", int(service.query().restarts) == 1)
	check("restart closes old flight distinctly", int(service.query().closed) == 1 and int(service.query().crashes) == 0)
	player.release("menu")
	player.resume()
	for i: int in 300: player.sim.step()
	check("second flight starts after reset confirmation", int(service.query().started) == 2)
	var snapshot: Dictionary = player.checkpoint()
	check("physics checkpoint restore accepted", player.restore_checkpoint(snapshot))
	var after_restore: float = float(service.query().airborne_seconds)
	player.resume()
	for i: int in 300: player.sim.step()
	check("checkpoint experiment cannot credit replayed time", service.query().airborne_seconds == after_restore)
	check("active activity cannot reset counters", not service.reset_counters("account"))
	check("end succeeds", service.end_activity())
	check("ended observer detached", player.sim.stepped.get_connections().size() == before_count - 1)
	check("Home can manage counters", service.can_manage())
	var lifetime: Dictionary = service.query("", "lifetime")
	check("independent account reset succeeds", service.reset_counters("account"))
	check("account reset retains lifetime", service.query("", "lifetime").started == lifetime.started)
	check("account window starts empty", int(service.query("", "counters").started) == 0)
	check("aircraft window remains intact", int(service.query("jensen-das-ugly-stik-60", "counters").started) == 2)
	check("session reset succeeds", service.reset_counters("session"))
	check("new session empty; lifetime retained", int(service.query().started) == 0 and service.query("", "lifetime").started == lifetime.started)
	check("finish session succeeds", service.finish())
	service.close()
	service.free()
	player.free()
	reference.free()
	print("Flight statistics lifecycle: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
