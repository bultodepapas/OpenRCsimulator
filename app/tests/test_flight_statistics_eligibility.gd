extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Service := preload("res://statistics/service.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const AIRCRAFT := "jensen-das-ugly-stik-60"

class CountingAdapter extends "res://statistics/fixed_wing_adapter.gd":
	var samples := 0
	var contacts := 0
	var ordering: Array = []
	var on_sample := Callable()
	func sample() -> Dictionary:
		samples += 1
		ordering.append("statistics")
		if on_sample.is_valid(): on_sample.call()
		return super.sample()
	func _contacts() -> void:
		contacts += 1
		super._contacts()

var checks := 0
var failures := 0
var order: Array = []
var accepted_events: Array = []

func _check(label: String, condition: bool) -> void:
	checks += 1
	print(("ok   " if condition else "FAIL ") + label)
	if not condition: failures += 1

func _before(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: order.append("before")
func _after(_tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void: order.append("after")
func _events(events: Array) -> void: accepted_events.append_array(events)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var player := Session.new()
	var reference := Session.new()
	player.input_enabled = false
	reference.input_enabled = false
	player.setup()
	reference.setup()
	var service := Service.new()
	service.setup("", false)
	player.sim.stepped.connect(_before)
	service.begin_activity(player, AIRCRAFT, "Ugly Stick")
	service.adapter.detach()
	var adapter := CountingAdapter.new()
	adapter.ordering = order
	adapter.configure(player, AIRCRAFT, Callable(service, "_observe"), Callable(service, "_may_observe"))
	service.adapter = adapter
	adapter.profile.generation_id = service._generation
	service._set_event_identity()
	adapter.attach()
	player.sim.stepped.connect(_after)
	service.flight_events_accepted.connect(_events)
	var connections: Array = player.sim.stepped.get_connections().duplicate()
	player.sim.step()
	reference.sim.step()
	_check("eligible accepted tick samples in subscription order", adapter.samples == 1 and order == ["before", "statistics", "after"])
	_check("eligible observation preserves physical checkpoint", var_to_bytes(player.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint()))
	var rejected_before := adapter.samples
	var state_before: PackedByteArray = player.sim.state.to_byte_array()
	_check("invalid restore is refused", not player.restore_checkpoint({}))
	_check("refused restore retains eligible subscription and state", not service._branch and player.sim.stepped.get_connections() == connections and player.sim.state.to_byte_array() == state_before)
	player.sim.step()
	reference.sim.step()
	_check("sampling continues after refused restore", adapter.samples == rejected_before + 1)
	var checkpoint: Dictionary = player.checkpoint()
	var reference_checkpoint: Dictionary = reference.checkpoint()
	_check("matching restore succeeds", player.restore_checkpoint(checkpoint) and reference.restore_checkpoint(reference_checkpoint))
	_check("restore retains original listener order", service._branch and player.sim.stepped.get_connections() == connections)
	player.resume()
	reference.resume()
	var sample_before := adapter.samples
	var detector_before := var_to_bytes(service.detector.snapshot())
	var ledger_before := var_to_bytes(service.data)
	var log_folder := ProjectSettings.globalize_path("user://statistics-eligibility-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var player_log := FlightLog.new(player)
	var reference_log := FlightLog.new(reference)
	var owns_folder := DirAccess.make_dir_absolute(log_folder) == OK
	var player_started := owns_folder and player_log.start(log_folder.path_join("player.orfl")) == OK
	var reference_started := owns_folder and reference_log.start(log_folder.path_join("reference.orfl")) == OK
	var logs_started := player_started and reference_started
	_check("paired flight logs start on the restored sessions", logs_started)
	var parity := true
	for i in 30:
		player.sim.step()
		reference.sim.step()
		parity = parity and var_to_bytes(player.sim.checkpoint()) == var_to_bytes(reference.sim.checkpoint())
	_check("restored experiment skips all thirty samples", adapter.samples == sample_before)
	_check("restored ticks preserve physics and input checkpoint", parity)
	_check("restored ticks leave ledger and detector unchanged", var_to_bytes(service.data) == ledger_before and var_to_bytes(service.detector.snapshot()) == detector_before)
	_check("restored flight logs retain identical accepted rows", logs_started and player_log._rows.size() == 30 and var_to_bytes(player_log._rows) == var_to_bytes(reference_log._rows))
	var player_stop := player_log.stop()
	var reference_stop := reference_log.stop()
	_check("both flight logs finish successfully", logs_started and player_stop == OK and reference_stop == OK)
	if owns_folder:
		if FileAccess.file_exists(log_folder.path_join("player.orfl")): DirAccess.remove_absolute(log_folder.path_join("player.orfl"))
		if FileAccess.file_exists(log_folder.path_join("reference.orfl")): DirAccess.remove_absolute(log_folder.path_join("reference.orfl"))
		DirAccess.remove_absolute(log_folder)
	_test_crash(player, reference, adapter, service, false)
	player.reset()
	reference.reset()
	player.resume()
	reference.resume()
	_check("restart retains original listener order and reenables credit", not service._branch and player.sim.stepped.get_connections() == connections)
	sample_before = adapter.samples
	for i in 60:
		player.sim.step()
		reference.sim.step()
	_check("restart resumes sampling", adapter.samples == sample_before + 60)
	_test_crash(player, reference, adapter, service, true)
	player.reset()
	reference.reset()
	player.resume()
	reference.resume()
	# Reentry between sampling admission and consumption must still be rejected.
	var before_reentry := var_to_bytes(service.detector.snapshot())
	var before_ledger := var_to_bytes(service.data)
	adapter.on_sample = func() -> void: service._branch = true
	player.sim.step()
	adapter.on_sample = Callable()
	_check("consumer guard rejects an eligibility change during sampling", var_to_bytes(service.detector.snapshot()) == before_reentry and var_to_bytes(service.data) == before_ledger)
	service._branch = false
	service.persistent = true
	service.store.writable = false
	var before_failed_end: Array = player.sim.stepped.get_connections().duplicate()
	_check("failed save refuses end without detaching", not service.end_activity() and service.detector != null and player.sim.stepped.get_connections() == before_failed_end)
	service.persistent = false
	sample_before = adapter.samples
	player.sim.step()
	_check("failed save leaves sampling active", adapter.samples == sample_before + 1)
	var second_checkpoint: Dictionary = player.checkpoint()
	_check("second branch restore succeeds", player.restore_checkpoint(second_checkpoint))
	service.suspend_activity()
	service.resume_activity()
	sample_before = adapter.samples
	player.resume()
	player.sim.step()
	_check("resuming a branched activity attaches but does not sample", adapter._attached and service._branch and adapter.samples == sample_before)
	player.reset()
	player.resume()
	player.sim.step()
	_check("restart after branched resume restores sampling", not service._branch and adapter.samples == sample_before + 1)
	service.suspend_activity()
	var detached: int = player.sim.stepped.get_connections().size()
	player.reset()
	_check("restart while suspended stays detached", service._suspended and not service._branch and player.sim.stepped.get_connections().size() == detached)
	sample_before = adapter.samples
	player.resume()
	player.sim.step()
	_check("suspended activity does not sample", adapter.samples == sample_before)
	service.resume_activity()
	player.sim.step()
	_check("resume reattaches and samples", adapter.samples == sample_before + 1)
	_check("end detaches cleanly", service.end_activity() and service.detector == null)
	service.close()
	service.free()
	player.free()
	reference.free()
	print("Statistics eligibility: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func _crash_state(session: Node) -> PackedFloat64Array:
	var state: PackedFloat64Array = session.sim.state.duplicate()
	var attitude: PackedFloat64Array = state.slice(RB.ATT, RB.ATT + 4)
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest := -INF
	for index in range(0, hull.size(), 3):
		deepest = maxf(deepest, M.q_rotate(attitude, hull.slice(index, index + 3))[2])
	state[RB.POS + 2] = -deepest + 0.001 - 0.01
	var velocity := M.q_rotate(M.q_conj(attitude), PackedFloat64Array([0.0, 0.0, 20.0]))
	for axis in 3:
		state[RB.VEL + axis] = velocity[axis]
		state[RB.RATE + axis] = 0.0
	return state

func _test_crash(player: Node, reference: Node, adapter: CountingAdapter, service: Node, eligible: bool) -> void:
	var previous := _crash_state(player)
	player.sim.state = previous.duplicate()
	player.sim.previous = previous.duplicate()
	reference.sim.state = previous.duplicate()
	reference.sim.previous = previous.duplicate()
	var before_samples := adapter.samples
	var before_contacts := adapter.contacts
	var before_events := accepted_events.size()
	var before_crashes := 0
	for record: Dictionary in service.data.records:
		if record.get("kind") == "crash": before_crashes += 1
	player.sim.set_paused(false)
	reference.sim.set_paused(false)
	player.sim.step()
	reference.sim.step()
	if player.crash.is_empty(): player._physics_process(player.sim.dt())
	if reference.crash.is_empty(): reference._physics_process(reference.sim.dt())
	var suffix := "eligible" if eligible else "branched"
	_check(suffix + " real hull crash emits contact notification", not player.crash.is_empty() and not reference.crash.is_empty() and adapter.contacts > before_contacts)
	_check(suffix + " crash leaves physical state and inputs identical", player.sim.state.to_byte_array() == reference.sim.state.to_byte_array() and player.sim.inputs.to_byte_array() == reference.sim.inputs.to_byte_array() and player.sim.continuous.to_byte_array() == reference.sim.continuous.to_byte_array())
	_check(suffix + " crash retains contact and damage outcomes", player.contact_events() == reference.contact_events() and player.scenery_damage() == reference.scenery_damage())
	_check(suffix + " crash samples only when eligible", adapter.samples > before_samples if eligible else adapter.samples == before_samples)
	var terminal_event := false
	for event: Dictionary in accepted_events.slice(before_events):
		terminal_event = terminal_event or bool(event.get("terminal", false))
	var after_crashes := 0
	for record: Dictionary in service.data.records:
		if record.get("kind") == "crash": after_crashes += 1
	_check(suffix + " crash event emission respects eligibility", terminal_event and after_crashes == before_crashes + 1 if eligible else accepted_events.size() == before_events and after_crashes == before_crashes)
