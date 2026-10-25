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
	check("live ledger validates: %s" % str(q.get("errors", [])), bool(q.get("ok", false)))
	check("air start counted once", int(q.started) == 1)
	check("airborne time includes confirmation interval", float(q.airborne_seconds) > 1.2)
	check("HUD summary equals full rollup", service.summary().airborne_seconds == q.airborne_seconds)
	var previous_time: float = float(q.airborne_seconds)
	player.hold("menu")
	for i: int in 50: player.sim._physics_process(1.0 / 240.0)
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
	check("reset's synthetic tick zero cannot invalidate the old flight", int(service.query().partial) == 0 and int(service.query().average_count) == 1)
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
	check("closed ledger validates: %s" % str(lifetime.get("errors", [])), bool(lifetime.get("ok", false)))
	check("independent account reset succeeds", service.reset_counters("account"))
	check("account reset retains lifetime", service.query("", "lifetime").started == lifetime.started)
	check("account window starts empty", int(service.query("", "counters").started) == 0)
	check("aircraft window remains intact", int(service.query("jensen-das-ugly-stik-60", "counters").started) == 2)
	check("session reset succeeds", service.reset_counters("session"))
	check("new session empty; lifetime retained", int(service.query().started) == 0 and service.query("", "lifetime").started == lifetime.started)
	check("finish session succeeds", service.finish())
	for cycle: int in 100:
		service.begin_activity(player, "jensen-das-ugly-stik-60", "Ugly Stick")
		service.end_activity()
	check("100 activity cycles leave observer count at baseline", player.sim.stepped.get_connections().size() == before_count - 1)
	service.close()
	service.free()
	player.free()
	reference.free()
	_test_durable_service()
	print("Flight statistics lifecycle: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_durable_service() -> void:
	var path := "user://flight_statistics_lifecycle_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var service: Node = load("res://statistics/service.gd").new()
	check("isolated persistent service opens", service.setup(path, true))
	var player: Node = Session.new()
	player.input_enabled = false
	player.setup()
	service.begin_activity(player, "jensen-das-ugly-stik-60", "Ugly Stick")
	for i: int in 300: player.sim.step()
	check("active flight and detector checkpoint save: %s" % service.note, service.flush())
	player.hold("test_checkpoint")
	service._process(0.0)
	check("automatic checkpoint starts a background writer", service._writer.pending())
	player.release("test_checkpoint")
	player.resume()
	for i: int in 24: player.sim.step()
	var current_time: float = service.summary().airborne_seconds
	service._finish_write()
	check("background receipt cannot rewind live flight", service.summary().airborne_seconds == current_time)
	check("live time advances beyond worker snapshot", current_time > float(service.store.data.records[0].airborne_seconds))
	check("live state remains valid after concurrent save", service.query().ok)
	check("updated time saves", service.flush())
	var saved_time: float = service.query().airborne_seconds
	var saved_session: String = service.data.current_session
	service.store.writable = false
	check("failed end keeps activity attached", not service.end_activity() and not service.can_manage())
	check("failed end rolls back active outcome", service.query().active == 1 and service.query().closed == 0)
	service.store.writable = true
	for i: int in 24: player.sim.step()
	check("rolled back detector continues exact time", service.summary().airborne_seconds > saved_time)
	# Simulate process loss: only the last acknowledged checkpoint survives.
	service.close()
	service.free()
	var recovered: Node = load("res://statistics/service.gd").new()
	check("interrupted service reopens", recovered.setup(path, true))
	var result: Dictionary = recovered.query()
	check("recovery retains session and durable time", recovered.data.current_session == saved_session and result.airborne_seconds == saved_time)
	check("recovery closes once as partial without completion", result.started == 1 and result.completed == 0 and result.closed == 1 and result.partial == 1)
	check("recovered ledger permits independent reset", recovered.reset_counters("account"))
	check("clean finish saved", recovered.finish())
	recovered.close()
	recovered.free()
	var clean: Node = load("res://statistics/service.gd").new()
	check("clean relaunch opens", clean.setup(path, true))
	check("clean relaunch starts empty session, keeps lifetime", clean.query().started == 0 and clean.query("", "lifetime").started == 1)
	clean.close()
	clean.free()
	player.free()
	var absolute := ProjectSettings.globalize_path(path)
	var user_root := ProjectSettings.globalize_path("user://")
	if absolute.begins_with(user_root) and absolute != user_root:
		_remove_fixture(absolute)


func _remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories():
		_remove_fixture(path.path_join(directory_name))
	directory = null
	DirAccess.remove_absolute(path)
