## AFC-03: bounded, opt-in fleet. Player ticks remain owned by the existing session.
extends Node

const Config := preload("res://ai/companions/config.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Math := preload("res://physics/math3d.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Profiles := preload("res://ai/companions/profile_loader.gd")
const Airspace := preload("res://ai/companions/airspace.gd")
const FleetRecord := preload("res://ai/companions/fleet_record.gd")
const WeatherConfig := preload("res://physics/wind_config.gd")
const SeedAllocator := preload("res://ai/companions/seed_allocator.gd")

signal changed
var config: Dictionary = Config.defaults()
var agents: Array[Node] = []
var error := ""
var last_tick_usec := 0
var accepted_ticks := 0
var observation_batches := 0
var _profile_identity: Dictionary = {}
var _airspace_report: Dictionary = {}
var _seed_allocation: Dictionary = {}
var _seed_weather: Dictionary = {}
var _record: RefCounted
var _player: Node
var _snapshot: Array = []
var _snapshot_tick := -1
var _removed := false
var _advancing := false
var _damage_dirty := false
# Diagnostics only. A before/after pair is timed separately to exclude the player
# solver between signals. Detailed phases are opt-in and never enter decisions.
var _detailed_timing := false
var _pending_timing_tick := -1
var _pending_before_usec := 0
var _last_before_usec := 0
var _last_after_usec := 0
var _last_prepare_usec := 0
var _last_advance_usec := 0
var _last_world_usec := 0
var _last_overhead_usec := 0
var _last_presentation_usec := 0


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
	if weather.get("format") == WeatherConfig.SPATIAL_FORMAT:
		reason = "Spatial weather needs a qualified companion circuit and shared world-clock policy."
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
	var seed_allocation: Dictionary = {}
	var seed_weather: Dictionary = {}
	if checked.config.enabled:
		var weather: Dictionary = player.weather_configuration()
		var resolved: Dictionary = SeedAllocator.new().resolve(int(weather.get("turbulence_seed", 0)),
			int(checked.config.seed), int(checked.config.count))
		if not resolved.ok:
			return resolved
		seed_allocation = resolved.record
		seed_weather = {weather_has_seed = weather.has("turbulence_seed"),
			turbulence_active = WeatherConfig.has_turbulence(weather)}
		# The canonical allocation is validated by each actor before any replacement.
		for slot: int in int(checked.config.count):
			var agent: Node = Agent.new()
			var prepared: Dictionary = agent.configure(player, field, slot, int(checked.config.count), int(checked.config.seed), visuals, audio_enabled, checked.qualification, seed_allocation)
			if not prepared.ok:
				agent.free()
				for candidate in candidates: candidate.free()
				return prepared
			agent.apply_presentation(checked.config)
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
	_seed_allocation = seed_allocation.duplicate(true)
	_seed_weather = seed_weather.duplicate(true)
	error = ""
	_removed = false
	accepted_ticks = 0
	observation_batches = 0
	_reset_timing()
	_snapshot_tick = -1
	agents = candidates
	for agent in agents: add_child(agent)
	_player.sim.before_step.connect(_before_step)
	_player.sim.stepped.connect(_after_step)
	_player.scenery_damage_changed.connect(_scenery_changed)
	_player.resetting.connect(_clear_pending_timing)
	_player.sim.faulted.connect(_timing_faulted)
	_damage_dirty = true
	set_process(not agents.is_empty())
	changed.emit()
	return {ok = true, config = config.duplicate(true), errors = PackedStringArray()}


func _refuse(message: String) -> Dictionary:
	return {ok = false, errors = PackedStringArray([message])}


## Presentation edits apply immediately without rebuilding or changing a flight.
func apply_presentation(requested: Dictionary) -> Dictionary:
	var checked: Dictionary = Config.validate(requested)
	if not checked.ok:
		return checked
	for key: String in ["engine_volume", "show_labels", "label_distance_m"]:
		config[key] = checked.config[key]
	for agent in agents:
		agent.apply_presentation(config)
	changed.emit()
	return {ok = true, errors = PackedStringArray()}


func _before_step(tick: int) -> void:
	_clear_pending_timing()
	var started := _clock_usec()
	_snapshot.clear()
	_snapshot_tick = tick
	if _removed or agents.is_empty():
		return
	var planning := false
	for agent in agents:
		planning = planning or agent.needs_command(tick)
	if not planning:
		_pending_timing_tick = tick
		_pending_before_usec = _clock_usec() - started
		return
	observation_batches += 1
	_snapshot.append({id = "player", is_player = true, state = _player.sim.state.duplicate(),
		command = _player.sim.inputs.duplicate()})
	for agent in agents:
		_snapshot.append(agent.observation())
	_pending_timing_tick = tick
	_pending_before_usec = _clock_usec() - started


func _after_step(tick: int, _time: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	# Simulation also publishes stepped(0) on reset; it has no accepted before_step.
	if _snapshot_tick < 0 or _snapshot_tick != tick - 1 or agents.is_empty() or _removed:
		_clear_pending_timing()
		return
	_advancing = true
	var started := _clock_usec()
	var phase_started := started
	var prepare_usec := 0
	var advance_usec := 0
	var world_usec := 0
	# Plan every agent before advancing any of them. All observations are from tick N.
	var ready: Array[Node] = []
	for index in agents.size():
		var agent: Node = agents[index]
		var observation: Dictionary = _snapshot[index + 1] if not _snapshot.is_empty() else {}
		if agent.prepare(observation, _snapshot_tick, _snapshot):
			ready.append(agent)
		if _removed:
			_advancing = false
			return
	if _detailed_timing:
		var now := _clock_usec()
		prepare_usec = now - phase_started
		phase_started = now
	for agent in ready:
		agent.advance()
		if _removed:
			_advancing = false
			return
	if _detailed_timing:
		var now := _clock_usec()
		advance_usec = now - phase_started
		phase_started = now
	# Player is the only world-damage author in the airborne MVP. The next mask
	# becomes visible to companions only after they finish this common tick.
	if _damage_dirty:
		var damage: Dictionary = _player.scenery_damage()
		for agent in agents:
			if agent.session.sim.tick == tick:
				var imported: bool = agent.session.import_external_scenery_damage(damage, tick)
				if _removed:
					_advancing = false
					return
				if not imported:
					agent.failure = "Shared scenery state was refused."
		_damage_dirty = false
	if _detailed_timing:
		world_usec = _clock_usec() - phase_started
	accepted_ticks += 1
	_snapshot_tick = -1
	_advancing = false
	var after_usec := _clock_usec() - started
	if _pending_timing_tick == tick - 1:
		_last_before_usec = _pending_before_usec
		_last_after_usec = after_usec
		last_tick_usec = _last_before_usec + _last_after_usec
		_last_prepare_usec = prepare_usec
		_last_advance_usec = advance_usec
		_last_world_usec = world_usec
		_last_overhead_usec = after_usec - prepare_usec - advance_usec - world_usec if _detailed_timing else 0
	_clear_pending_timing()


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var started := _clock_usec() if _detailed_timing else 0
	var frozen: bool = _player.sim.paused or not _player.holds.is_empty()
	for agent in agents:
		agent.render(delta, frozen)
	if _detailed_timing:
		_last_presentation_usec = _clock_usec() - started


func set_detailed_timing(enabled: bool) -> void:
	_detailed_timing = enabled
	_reset_timing()


func timing_status() -> Dictionary:
	var result := {format = "openrc-companion-timing v1", detailed = _detailed_timing,
		paired_tick_usec = last_tick_usec, before_usec = _last_before_usec, after_usec = _last_after_usec}
	if _detailed_timing:
		result.merge({prepare_usec = _last_prepare_usec, advance_usec = _last_advance_usec,
			world_publication_usec = _last_world_usec, after_overhead_usec = _last_overhead_usec,
			presentation_usec = _last_presentation_usec})
	return result


func _clock_usec() -> int:
	return Time.get_ticks_usec()


func _clear_pending_timing() -> void:
	_pending_timing_tick = -1
	_pending_before_usec = 0


func _timing_faulted(_reason: String) -> void:
	# Faults can also originate in postcommit observers before our stepped slot.
	# An accepted player tick still owns the matching companion timing pair.
	if not is_instance_valid(_player) or _player.sim.tick <= _pending_timing_tick:
		_clear_pending_timing()


func _reset_timing() -> void:
	_clear_pending_timing()
	last_tick_usec = 0
	_last_before_usec = 0
	_last_after_usec = 0
	_last_prepare_usec = 0
	_last_advance_usec = 0
	_last_world_usec = 0
	_last_overhead_usec = 0
	_last_presentation_usec = 0


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
		timing = timing_status(),
		config = config.duplicate(true), profile_identity = _profile_identity.duplicate(true),
		seed_allocation = _seed_allocation.duplicate(true),
		seed_weather = _seed_weather.duplicate(true),
		airspace_report = _airspace_report.duplicate(true), recording = recording_status()}


## Developer capture only; a capture failure never changes flight state or admission.
func start_recording(directory: String, max_ticks: int = FleetRecord.MAX_TICKS) -> Dictionary:
	if _record != null and _record.status().active:
		return _refuse("A companion capture is already active.")
	if not is_instance_valid(_player) or _removed or agents.is_empty():
		return _refuse("Enable companions before starting a fleet capture.")
	var candidate := FleetRecord.new()
	var result: Dictionary = candidate.start(_player, agents, {config = config.duplicate(true),
		profile_identity = _profile_identity.duplicate(true), airspace_report = _airspace_report.duplicate(true),
		seed_allocation = _seed_allocation.duplicate(true), seed_weather = _seed_weather.duplicate(true)},
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
	_reset_timing()
	_clear_agents(_advancing)
	set_process(false)
	changed.emit()


func _scenery_changed() -> void:
	_damage_dirty = true


func _clear_agents(deferred_disposal := false) -> void:
	for agent in agents:
		if agent.get_parent() == self: remove_child(agent)
		# A restore/removal can originate in this agent's stepped observer.
		# Logical removal is immediate; its active stack must unwind first.
		if deferred_disposal: agent.queue_free()
		else: agent.free()
	agents.clear()


func _disconnect() -> void:
	if not is_instance_valid(_player):
		return
	if _player.sim.before_step.is_connected(_before_step): _player.sim.before_step.disconnect(_before_step)
	if _player.sim.stepped.is_connected(_after_step): _player.sim.stepped.disconnect(_after_step)
	if _player.scenery_damage_changed.is_connected(_scenery_changed): _player.scenery_damage_changed.disconnect(_scenery_changed)
	if _player.resetting.is_connected(_clear_pending_timing): _player.resetting.disconnect(_clear_pending_timing)
	if _player.sim.faulted.is_connected(_timing_faulted): _player.sim.faulted.disconnect(_timing_faulted)


func _exit_tree() -> void:
	stop_recording("flight closed")
	_disconnect()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Detached research/test managers can be freed without ever entering the tree.
		stop_recording("fleet freed")
		_disconnect()
