## AFC-03: bounded, opt-in fleet. Player ticks remain owned by the existing session.
extends Node

const Config := preload("res://ai/companions/config.gd")
const Agent := preload("res://ai/companions/agent.gd")
const Math := preload("res://physics/math3d.gd")

signal changed
var config: Dictionary = Config.defaults()
var agents: Array[Node] = []
var error := ""
var last_tick_usec := 0
var accepted_ticks := 0
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
	return checked


func configure(player: Node, field: Dictionary, landscape: String, requested: Dictionary,
		visuals := true, audio_enabled := true) -> Dictionary:
	var checked: Dictionary = validate_context(player, field, landscape, requested)
	if not checked.ok:
		return checked
	if checked.config.enabled and player.sim.tick != 0:
		return _refuse("Start or restart the flight to enable companions.")
	var candidates: Array[Node] = []
	if checked.config.enabled:
		for slot: int in int(checked.config.count):
			var agent: Node = Agent.new()
			var prepared: Dictionary = agent.configure(player, field, slot, int(checked.config.count), int(checked.config.seed), visuals, audio_enabled)
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
	_disconnect()
	_clear_agents()
	_player = player
	config = checked.config.duplicate(true)
	error = ""
	_removed = false
	accepted_ticks = 0
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
	_snapshot.append({id = "player", is_player = true, state = _player.sim.state.duplicate(),
		command = _player.sim.inputs.duplicate()})
	for agent in agents:
		_snapshot.append(agent.observation())


func _after_step(tick: int, _time: float, _state: PackedFloat64Array,
		_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if _snapshot_tick != tick - 1 or _snapshot.is_empty() or _removed:
		return
	var started := Time.get_ticks_usec()
	# Plan every agent before advancing any of them. All observations are from tick N.
	var ready: Array[Node] = []
	for index in agents.size():
		var agent: Node = agents[index]
		if agent.prepare(_snapshot[index + 1], _snapshot_tick, _snapshot):
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
		last_tick_usec = last_tick_usec, ticks = accepted_ticks, config = config.duplicate(true)}


func remove_now() -> void:
	_removed = true
	_snapshot.clear()
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
	_disconnect()
