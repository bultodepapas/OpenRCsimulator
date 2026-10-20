## AFC-03: bounded, opt-in fleet. Player ticks remain owned by the existing session.
extends Node

const Config := preload("res://ai/companions/config.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Math := preload("res://physics/math3d.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Profiles := preload("res://ai/companions/profile_loader.gd")
const Airspace := preload("res://ai/companions/airspace.gd")
const FleetRecord := preload("res://ai/companions/fleet_record.gd")

signal changed
var config: Dictionary = Config.defaults()
var agents: Array[Node] = []
var error := ""
var last_tick_usec := 0
var accepted_ticks := 0
var observation_batches := 0
var _profile_identity: Dictionary = {}
var _airspace_report: Dictionary = {}
var _record: RefCounted
var _player: Node
var _snapshot: Array = []
var _snapshot_tick := -1
var _removed := false
var _damage_dirty := false


static func validate_context(player: Node, field: Dictionary, landscape: String, requested: Dictionary) -> Dictionary:
	var checked: Dictionary = Config.validate(requested)
	if not checked.ok or not checked.config.enabled:
		return checked
	var reason := ""
	if landscape != "club_field" or str(field.get("id", "")) != "default":
		reason = "Flight companions currently require Club field."
	elif not player.atmosphere_is_reference():
		reason = "Companion circuits currently require the reference atmosphere."
	var weather: Dictionary = player.weather_configuration()
	if float(weather.get("speed_mps", 0.0)) > 1.5 or float(weather.get("gust_mps", 0.0)) > 0.6 \
			or absf(float(weather.get("gust_up_mps", 0.0))) > 0.15:
		reason = "Companion circuits currently support calm air or a gentle breeze."
	var rms: Array = Array(weather.get("turbulence_rms_mps", [0.0, 0.0, 0.0]))
	for axis in rms.size():
		if float(rms[axis]) > (0.08 if axis == 2 else 0.15):
			reason = "Turbulence exceeds the companion circuit profile."
	if not reason.is_empty():
		return {ok = false, errors = PackedStringArray([reason])}
	var source: String = str(Catalog.entry(str(checked.config.aircraft_id)).get("data", ""))
	var qualification: Dictionary = Profiles.load_profile(str(checked.config.aircraft_id),
		{format = "openrc-aircraft v2", sha256 = FileAccess.get_sha256(source)}, field)
	if not qualification.ok:
		return qualification
	checked.qualification = qualification
	return checked


func configure(player: Node, field: Dictionary, landscape: String, requested: Dictionary,
		visuals := true, audio_enabled := true) -> Dictionary:
	var checked: Dictionary = validate_context(player, field, landscape, requested)
	if not checked.ok:
		return checked
	if checked.config.enabled and player.sim.tick != 0:
		return _refuse("Start or restart the flight to enable companions.")
	var candidates: Array[Node] = []
	var airspace_report: Dictionary = {}
	if checked.config.enabled:
		for slot: int in int(checked.config.count):
			var agent: Node = Agent.new()
			var prepared: Dictionary = agent.configure(player, field, slot, int(checked.config.count), int(checked.config.seed), visuals, audio_enabled, checked.qualification)
			if not prepared.ok:
				agent.free()
				for candidate in candidates: candidate.free()
				return prepared
			var state: PackedFloat64Array = agent.session.sim.state
			var player_state: PackedFloat64Array = player.sim.state
			if Math.norm(Math.v3(state[0] - player_state[0], state[1] - player_state[1], state[2] - player_state[2])) < 30.0:
				agent.free()
				for candidate in candidates: candidate.free()
				return _refuse("Companion launch is too close to the player.")
			candidates.append(agent)
		# Check the accepted companion model/environment, not the player's aircraft.
		# Full inventory scanning is launch-only and precedes any roster replacement.
		var reference: Node = candidates[0].session
		var clearance: Dictionary = Airspace.validate(checked.qualification.field_profile, field,
			reference.collision_world(), reference.environment.surfaces, reference.lake_context(),
			reference.aircraft.model, int(checked.config.count))
		if not clearance.ok:
			for candidate in candidates: candidate.free()
			return clearance
		airspace_report = clearance.report
	stop_recording("fleet reconfigured")
	_disconnect()
	_clear_agents()
	_player = player
	config = checked.config.duplicate(true)
	_profile_identity = checked.qualification.identity.duplicate(true) if checked.config.enabled else {}
	_airspace_report = airspace_report.duplicate(true)
	error = ""
	_removed = false
	accepted_ticks = 0
	observation_batches = 0
	_snapshot_tick = -1
	agents = candidates
	for agent in agents: add_child(agent)
	_player.sim.before_step.connect(_before_step)
	_player.sim.stepped.connect(_after_step)
	_player.scenery_damage_changed.connect(_scenery_changed)
	_damage_dirty = true
	set_process(not agents.is_empty())
	changed.emit()
	return {ok = true, config = config.duplicate(true), errors = PackedStringArray()}


func _refuse(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}


func _before_step(tick: int) -> void:
	_snapshot.clear()
	_snapshot_tick = tick
	if _removed or agents.is_empty():
		return
	var planning := false
	for agent in agents:
		planning = planning or agent.needs_command(tick)
	if not planning:
		return
	observation_batches += 1
	_snapshot.append({id = "player", is_player = true, state = _player.sim.state.duplicate(),
		command = _player.sim.inputs.duplicate()})
	for agent in agents:
		_snapshot.append(agent.observation())


func _after_step(tick: int, _time: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	# Simulation also publishes stepped(0) on reset; it has no accepted before_step.
	if _snapshot_tick < 0 or _snapshot_tick != tick - 1 or agents.is_empty() or _removed:
		return
	var started := Time.get_ticks_usec()
	# Plan every agent before advancing any of them. All observations are from tick N.
	var ready: Array[Node] = []
	for index in agents.size():
		var agent: Node = agents[index]
		var observation: Dictionary = _snapshot[index + 1] if not _snapshot.is_empty() else {}
		if agent.prepare(observation, _snapshot_tick, _snapshot):
			ready.append(agent)
	for agent in ready:
		agent.advance()
	# Player is the only world-damage author in the airborne MVP. The next mask
	# becomes visible to companions only after they finish this common tick.
	if _damage_dirty:
		var damage: Dictionary = _player.scenery_damage()
		for agent in agents:
			if agent.session.sim.tick == tick and not agent.session.import_external_scenery_damage(damage, tick):
				agent.failure = "Shared scenery state was refused."
		_damage_dirty = false
	accepted_ticks += 1
	last_tick_usec = Time.get_ticks_usec() - started
	_snapshot_tick = -1


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var frozen: bool = _player.sim.paused or not _player.holds.is_empty()
	for agent in agents:
		agent.render(delta, frozen)


func status() -> Dictionary:
	var airborne := 0
	var failures := 0
	var crashed := 0
	for agent in agents:
		if not agent.failure.is_empty():
			failures += 1
		elif not agent.session.crash.is_empty(): crashed += 1
		else: airborne += 1
	var problems := PackedStringArray()
	for agent in agents:
		if not agent.failure.is_empty():
			problems.append("%s: %s" % [agent.name, agent.failure])
	return {active = agents.size(), airborne = airborne, requested = int(config.count) if config.enabled else 0,
		faulted = failures, crashed = crashed, seed = config.seed, error = "; ".join(problems), removed = _removed,
		last_tick_usec = last_tick_usec, ticks = accepted_ticks, observation_batches = observation_batches,
		config = config.duplicate(true), profile_identity = _profile_identity.duplicate(true),
		airspace_report = _airspace_report.duplicate(true), recording = recording_status()}


## Developer capture only; a capture failure never changes flight state or admission.
func start_recording(directory: String, max_ticks: int = FleetRecord.MAX_TICKS) -> Dictionary:
	if _record != null and _record.status().active:
		return _refuse("A companion capture is already active.")
	if not is_instance_valid(_player) or _removed or agents.is_empty():
		return _refuse("Enable companions before starting a fleet capture.")
	var candidate := FleetRecord.new()
	var result: Dictionary = candidate.start(_player, agents, {config = config.duplicate(true),
		profile_identity = _profile_identity.duplicate(true), airspace_report = _airspace_report.duplicate(true)},
		directory, max_ticks)
	_record = candidate
	return result


func recording_status() -> Dictionary:
	return _record.status() if _record != null else {active = false, complete = false, error = "", directory = ""}


func stop_recording(reason := "stopped") -> Dictionary:
	return _record.stop(reason) if _record != null else recording_status()


func mark_recording(label := "pilot marker") -> void:
	if _record != null: _record.mark(label)


func remove_now() -> void:
	stop_recording("companions removed")
	_removed = true
	_disconnect()
	_player = null
	_snapshot.clear()
	_snapshot_tick = -1
	_clear_agents()
	set_process(false)
	changed.emit()


func _scenery_changed() -> void:
	_damage_dirty = true


func _clear_agents() -> void:
	for agent in agents:
		if agent.get_parent() == self: remove_child(agent)
		agent.free()
	agents.clear()


func _disconnect() -> void:
	if not is_instance_valid(_player):
		return
	if _player.sim.before_step.is_connected(_before_step): _player.sim.before_step.disconnect(_before_step)
	if _player.sim.stepped.is_connected(_after_step): _player.sim.stepped.disconnect(_after_step)
	if _player.scenery_damage_changed.is_connected(_scenery_changed): _player.scenery_damage_changed.disconnect(_scenery_changed)


func _exit_tree() -> void:
	stop_recording("flight closed")
	_disconnect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Detached research/test managers can be freed without ever entering the tree.
		stop_recording("fleet freed")
		_disconnect()
