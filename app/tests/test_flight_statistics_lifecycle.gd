extends SceneTree

const Session = preload("res://sim/flight_session.gd")
var checks := 0
var failures := 0


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


class RejectReloadSession extends "res://sim/flight_session.gd":
	var reject_next_reload := false
	var _reject_load_once := false
	func _commit_aircraft(prepared: Dictionary) -> void:
		super._commit_aircraft(prepared)
		if reject_next_reload:
			reject_next_reload = false
			_reject_load_once = true
	func _wheel_evaluate(s: PackedFloat64Array, x: PackedFloat64Array, t: float) -> Dictionary:
		if _reject_load_once:
			_reject_load_once = false
			return {}
		return super._wheel_evaluate(s, x, t)


class CheckpointClock extends Node:
	var tick := 0
	var elapsed := 0.0
	func time() -> float: return elapsed


class CheckpointSession extends Node:
	var sim := CheckpointClock.new()


class CheckpointDetector extends RefCounted:
	var flight := {airborne_seconds = 1.0}
	func observe(_sample: Dictionary) -> Array[Dictionary]: return []
	func snapshot() -> Dictionary: return {}


## Deterministic completion control, so accepted ticks can arrive while a write is in flight.
class CheckpointWriter extends RefCounted:
	var snapshots: Array[Dictionary] = []
	var in_flight := false
	var result := {}
	func start(_store: Variant, candidate: Dictionary) -> bool:
		if in_flight: return false
		snapshots.append(candidate.duplicate(true))
		in_flight = true
		return true
	func pending() -> bool: return in_flight
	func poll() -> Dictionary:
		if result.is_empty(): return {}
		var completed := result
		result = {}
		in_flight = false
		return completed
	func finish() -> Dictionary: return poll()


func _initialize() -> void:
	var service: Node = load("res://statistics/service.gd").new()
	check("in-memory service opens without player files", service.setup("", false))
	var player: Node = RejectReloadSession.new()
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
	player.reject_next_reload = true # Refuse before physical commit/publication.
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
	check("accepted generation records its current aircraft input identity",
		service.data.records.back().config_hash == str(player.aircraft.input_identity.sha256))
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
	_test_checkpoint_scheduler()
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
	var reader: Node = load("res://statistics/service.gd").new()
	check("second service opens the owned store read-only", not reader.setup(path, true) and not reader.store.writable)
	var reader_before: Dictionary = reader.data.duplicate(true)
	reader.begin_activity(player, "jensen-das-ugly-stik-60", "Ugly Stick")
	check("read-only service starts no activity", reader.detector == null and reader._session == null)
	check("read-only service with no activity can finish without changing data", reader.finish() and reader.data == reader_before)
	reader.close()
	reader.free()
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
	check("failed quit does not discard an active owned session", not service.finish() and service.detector != null)
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
	recovered.store.writable = false
	check("owned recovered session still reports a failed finish", not recovered.finish())
	recovered.store.writable = true
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


func _scheduler_fixture() -> Dictionary:
	var service: Node = load("res://statistics/service.gd").new()
	var session := CheckpointSession.new()
	var writer := CheckpointWriter.new()
	service.data = {generation = 0, records = [], sessions = [], epochs = {}, active_context = {}}
	service.store = RefCounted.new()
	service.persistent = true
	service._session = session
	service.detector = CheckpointDetector.new()
	service._writer = writer
	service._dirty = true
	service._active_record = {id = "scheduler-flight", metadata = {events = []}}
	return {service = service, session = session, writer = writer}


func _scheduler_tick(fixture: Dictionary, tick: int) -> void:
	fixture.session.sim.tick = tick
	fixture.session.sim.elapsed = float(tick) / 240.0
	fixture.service._observe({tick = tick})


func _scheduler_dispose(fixture: Dictionary) -> void:
	fixture.service.free()
	fixture.session.sim.free()
	fixture.session.free()


func _test_checkpoint_scheduler() -> void:
	var fixture := _scheduler_fixture()
	_scheduler_tick(fixture, 1200)
	fixture.service._process(0.0)
	check("five simulated seconds request one background checkpoint", fixture.writer.snapshots.size() == 1 and fixture.writer.pending())
	for tick in range(1201, 1231): _scheduler_tick(fixture, tick)
	check("ticks during the in-flight interval do not request a duplicate checkpoint", not fixture.service._flush_requested)
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	check("successful receipt does not start a duplicate write", fixture.writer.snapshots.size() == 1 and not fixture.writer.pending())
	check("successful receipt retains the scheduled durable cursor", fixture.service._durable_tick == 1200 and fixture.service._last_flush_time == 5.0)
	_scheduler_tick(fixture, 2400)
	fixture.service._process(0.0)
	check("the next checkpoint is due five seconds after the durable snapshot", fixture.writer.snapshots.size() == 2 and fixture.writer.pending())
	_scheduler_dispose(fixture)

	fixture = _scheduler_fixture()
	_scheduler_tick(fixture, 1200)
	fixture.service._process(0.0)
	_scheduler_tick(fixture, 1201)
	fixture.service._paused(true)
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	check("pause during a pending write still requests a separate checkpoint", fixture.writer.snapshots.size() == 2 and fixture.writer.pending())
	_scheduler_dispose(fixture)

	fixture = _scheduler_fixture()
	_scheduler_tick(fixture, 1200)
	fixture.service._process(0.0)
	_scheduler_tick(fixture, 1201)
	fixture.service._ingest([{type = "landing", tick = 1201}])
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	var event_snapshot: Dictionary = fixture.writer.snapshots.back()
	check("event during a pending write is included in a subsequent checkpoint", fixture.writer.snapshots.size() == 2 \
		and fixture.writer.pending() and event_snapshot.records[0].metadata.events[0].type == "landing")
	_scheduler_dispose(fixture)

	fixture = _scheduler_fixture()
	_scheduler_tick(fixture, 1200)
	fixture.service._process(0.0)
	_scheduler_tick(fixture, 2399)
	check("a slow write does not queue the next period early", not fixture.service._flush_requested)
	_scheduler_tick(fixture, 2400)
	check("a pending write does not hide another elapsed five-second interval", fixture.service._flush_requested)
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	check("a delayed checkpoint is started after the older write finishes", fixture.writer.snapshots.size() == 2 and fixture.writer.pending())
	_scheduler_dispose(fixture)

	# A write from before Restart can acknowledge an older generation at a larger
	# simulation time. A new-generation write must still get its own five-second clock.
	fixture = _scheduler_fixture()
	fixture.service._last_flush_time = 20.0
	fixture.session.sim.tick = 240
	fixture.session.sim.elapsed = 1.0
	fixture.service._flush_requested = true
	fixture.service._process(0.0)
	_scheduler_tick(fixture, 1439)
	check("a new-generation pending write does not checkpoint early", not fixture.service._flush_requested)
	_scheduler_tick(fixture, 1440)
	check("a pending new-generation write uses its own clock after restart", fixture.service._flush_requested)
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	check("elapsed new-generation checkpoint follows the pending write", fixture.writer.snapshots.size() == 2 and fixture.writer.pending())
	_scheduler_dispose(fixture)

	fixture = _scheduler_fixture()
	_scheduler_tick(fixture, 1200)
	fixture.service._process(0.0)
	_scheduler_tick(fixture, 1201)
	fixture.writer.result = {ok = false, note = "injected write failure"}
	fixture.service._process(0.0)
	check("failed checkpoint retains its retry and prior durable cursor", fixture.service._flush_requested \
		and fixture.service._dirty and fixture.service._durable_tick == 0 and fixture.service._last_flush_time == 0.0 \
		and fixture.writer.snapshots.size() == 1)
	fixture.service._process(0.0)
	check("failed checkpoint respects its retry delay", fixture.writer.snapshots.size() == 1)
	fixture.service._retry_after_msec = 0
	fixture.service._process(0.0)
	check("failed checkpoint retries after the delay", fixture.writer.snapshots.size() == 2 and fixture.writer.pending())
	fixture.writer.result = {ok = true, generation = 1}
	fixture.service._process(0.0)
	check("successful retry records its actual new durable cursor", fixture.service._durable_tick == 1201 \
		and fixture.service._last_flush_time == 1201.0 / 240.0 and not fixture.service._flush_requested)
	_scheduler_dispose(fixture)


func _remove_fixture(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name: String in directory.get_directories():
		_remove_fixture(path.path_join(directory_name))
	directory = null
	DirAccess.remove_absolute(path)
