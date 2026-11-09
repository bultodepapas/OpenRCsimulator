## AFC-00/02: seed provenance and diagnostic timing at production boundaries.
extends SceneTree

const Seeds := preload("res://ai/companions/seed_allocator.gd")
const Wind := preload("res://physics/wind_turbulence.gd")
const Weather := preload("res://physics/wind_config.gd")
const Manager := preload("res://ai/companions/manager.gd")
const Flight := preload("res://sim/flight_session.gd")
const Config := preload("res://ai/companions/config.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Field := preload("res://data/field_loader.gd")

class Collisions extends Seeds:
	func _candidate_seed(player_seed: int, _traffic: int, slot: int, nonce: int) -> int:
		# First collide with player, then with slot zero. Finally resolve.
		return player_seed if nonce == 0 else (10 if nonce == 1 else 10 + slot)

class Exhausted extends Seeds:
	func _candidate_seed(player_seed: int, _traffic: int, _slot: int, _nonce: int) -> int:
		return player_seed

class ClockedManager extends Manager:
	var clock := 0
	func _clock_usec() -> int:
		return clock

class FakeAgent extends Node:
	var clock: Node
	var planning := true
	func needs_command(_tick: int) -> bool:
		return planning
	func observation() -> Dictionary:
		clock.clock += 5
		return {}
	func prepare(_snapshot: Dictionary, _tick: int, _traffic: Array) -> bool:
		clock.clock += 7
		return true
	func advance() -> bool:
		clock.clock += 11
		return true

var _checks := 0
var _failures := 0

func _check(label: String, passed: bool, detail := "") -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL ", label, " ", detail)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_seed_cases()
	_timing_cases()
	_flight_cases()
	print("companions seeds and timing: %d checks, %d failed" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)

func _seed_cases() -> void:
	var allocator := Seeds.new()
	for pair: Array in [[0, 0], [4294967295, 4294967295], [20261011, 0], [0, 4294862567]]:
		var resolved: Dictionary = allocator.resolve(pair[0], pair[1], 3)
		_check("uint32 endpoint/wrap roster resolves", resolved.ok, str(pair))
		if not resolved.ok:
			continue
		var seen := {int(pair[0]): true}
		var states := {Seeds.initial_state_hex(int(pair[0])): true}
		for allocation: Dictionary in resolved.record.allocations:
			_check("resolved seed and actual engine initial state are unique",
				not seen.has(allocation.seed) and not states.has(allocation.initial_rng_state_hex))
			seen[allocation.seed] = true
			states[allocation.initial_rng_state_hex] = true
		_check("same fixed roster has identical provenance", allocator.resolve(pair[0], pair[1], 3).record == resolved.record)
		_check("extending ordered roster preserves slot zero", allocator.resolve(pair[0], pair[1], 1).record.allocations[0] == resolved.record.allocations[0])
		_check("canonical record validates", allocator.validate_record(resolved.record, pair[0], pair[1], 3).ok)
		var json_record: Variant = JSON.parse_string(JSON.stringify(resolved.record))
		_check("JSON provenance preserves exact seed and RNG identity", allocator.validate_record(json_record, pair[0], pair[1], 3).ok)
		var altered: Dictionary = resolved.record.duplicate(true)
		altered.allocations[0].nonce += 1
		_check("altered nonce refuses", not allocator.validate_record(altered, pair[0], pair[1], 3).ok)
		json_record.allocations[0].seed = float(resolved.record.allocations[0].seed) + 0.5
		_check("fractional JSON seed refuses", not allocator.validate_record(json_record, pair[0], pair[1], 3).ok)
	for invalid: Array in [[-1, 0, 1], [4294967296, 0, 1], [0.0, 0, 1], [0, 0, 0], [0, 0, 4]]:
		_check("invalid allocation input refuses", not allocator.resolve(invalid[0], invalid[1], invalid[2]).ok)
	var forced: Dictionary = Collisions.new().resolve(7, 0, 3)
	_check("forced player and earlier-actor collisions resolve with stored nonces",
		forced.ok and forced.record.allocations[0].nonce == 1 and forced.record.allocations[1].nonce == 2 \
		and forced.record.allocations[2].nonce == 2 and forced.record.allocations[2].seed == 12)
	_check("bounded collision exhaustion refuses", not Exhausted.new().resolve(7, 0, 3).ok)
	var record: Dictionary = allocator.resolve(20261011, 0, 3).record
	var sigma := PackedFloat64Array([0.15, 0.15, 0.08])
	var streams: Array = [Wind.initial(sigma, 20261011)]
	var seed_values := [20261011]
	for allocation: Dictionary in record.allocations:
		streams.append(Wind.initial(sigma, allocation.seed))
		seed_values.append(allocation.seed)
	var unique := true
	var valid := true
	for tick in 240:
		var states := {}
		var values := {}
		for index in streams.size():
			var previous: Dictionary = streams[index]
			var next: Dictionary = Wind.step(previous.values, sigma, 3.0, 1.0 / 240.0, seed_values[index], previous.rng_state)
			valid = valid and next.ok
			var value_key: String = next.values.to_byte_array().hex_encode()
			unique = unique and not states.has(next.rng_state) and not values.has(value_key)
			states[next.rng_state] = true
			values[value_key] = true
			streams[index] = next
	_check("actual OU module accepts all 240 transitions", valid)
	_check("player and three companions never share a tested OU state/value", unique)

func _timing_cases() -> void:
	var manager := ClockedManager.new()
	var player := Flight.new()
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	var agent := FakeAgent.new()
	agent.clock = manager
	manager._player = player
	manager.agents.append(agent)
	manager.set_detailed_timing(true)
	manager._before_step(0)
	manager.clock += 1000000 # Deterministic stand-in for player solver/callback gap.
	manager._after_step(1, 0.0, PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array())
	var timing: Dictionary = manager.timing_status()
	_check("paired callback total includes observation and excludes player gap", timing.paired_tick_usec == 23 and timing.before_usec == 5 and timing.after_usec == 18, str(timing))
	_check("exclusive after phases sum to after total", timing.prepare_usec == 7 and timing.advance_usec == 11 and timing.after_usec == timing.prepare_usec + timing.advance_usec + timing.world_publication_usec + timing.after_overhead_usec)
	agent.planning = false
	manager._before_step(1)
	manager.clock += 2000000
	manager._after_step(2, 0.0, PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array())
	_check("nonplanning tick replaces earlier observation cost", manager.timing_status().paired_tick_usec == 18 and manager.timing_status().before_usec == 0)
	manager._before_step(2)
	manager._timing_faulted("rejected player tick")
	_check("rejected player tick discards pending cost", manager._pending_timing_tick == -1 and manager._pending_before_usec == 0)
	manager._before_step(2)
	manager._after_step(0, 0.0, PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array())
	_check("reset publication discards pending cost", manager._pending_timing_tick == -1)
	manager.remove_now()
	_check("removal clears prior roster diagnostics", manager.last_tick_usec == 0 and manager._pending_timing_tick == -1)
	manager.set_detailed_timing(false)
	_check("disabled detailed timing omits unavailable phase buckets", not manager.timing_status().has("prepare_usec") and not manager.timing_status().has("after_overhead_usec"))
	manager.free()
	player.free()

func _fixture(field: Dictionary, weather: Dictionary, detailed: bool, postcommit_fault := false) -> Dictionary:
	var player := Flight.new()
	player.input_enabled = false
	player.crash_auto_restart = false
	player.setup(Catalog.entry(Catalog.DEFAULT_ID).data, Catalog.DEFAULT_ID)
	_check("player weather and field install", player.setup_weather(weather) and player.set_field(field))
	player.reset()
	root.add_child(player)
	player.set_physics_process(false)
	player.sim.set_physics_process(false)
	if postcommit_fault:
		player.sim.stepped.connect(func(_tick: int, _time: float, _state: PackedFloat64Array,
				_loads: PackedFloat64Array, _inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
			player.sim._fail_safe("injected postcommit observer fault"), CONNECT_ONE_SHOT)
	var manager := Manager.new()
	var config: Dictionary = Config.defaults()
	config.enabled = true
	config.count = 3
	config.seed = 0
	var prepared: Dictionary = manager.configure(player, field, "club_field", config, false, false)
	_check("fixed-roster flight admits", prepared.ok, str(prepared))
	root.add_child(manager)
	manager.set_detailed_timing(detailed)
	return {player = player, manager = manager}

func _flight_cases() -> void:
	var loaded: Dictionary = Field.load_from()
	_check("field loads", loaded.ok)
	if not loaded.ok:
		return
	var weather: Dictionary = Weather.preset("gentle-practice")
	var left: Dictionary = _fixture(loaded.field, weather, false)
	var right: Dictionary = _fixture(loaded.field, weather, true)
	if left.manager.agents.size() != 3 or right.manager.agents.size() != 3:
		_dispose(left)
		_dispose(right)
		return
	var provenance: Dictionary = right.manager.status().seed_allocation
	_check("active turbulence allocation is reported", provenance.format == Seeds.FORMAT and right.manager.status().seed_weather.turbulence_active and right.manager.status().seed_weather.weather_has_seed)
	_check("persisted allocation can be canonically validated", Seeds.new().validate_record(provenance, 20261011, 0, 3).ok)
	for slot in 3:
		var agent: Node = right.manager.agents[slot]
		_check("actual session installs allocated turbulence seed", agent.session.weather_configuration().turbulence_seed == provenance.allocations[slot].seed and agent.seed_allocation().seed == provenance.allocations[slot].seed)
	provenance.allocations[0].seed = -1
	_check("status allocation is detached", right.manager.status().seed_allocation.allocations[0].seed >= 0)
	var capture_path := ProjectSettings.globalize_path("res://../tmp/afc-r11-capture-%d" % Time.get_ticks_usec())
	_check("allocation capture starts", right.manager.start_recording(capture_path, 240).ok)
	var parity := true
	var healthy := true
	for tick in 240:
		for fixture: Dictionary in [left, right]:
			fixture.player._physics_process(fixture.player.sim.dt())
			fixture.player.sim._physics_process(fixture.player.sim.dt())
		for slot in 3:
			var a: Node = left.manager.agents[slot].session
			var b: Node = right.manager.agents[slot].session
			parity = parity and var_to_bytes([a.sim.state, a.sim.previous, a.sim.aux, a.sim.continuous, a.sim.inputs, a.sim.modes, a.sim.last_loads]) == var_to_bytes([b.sim.state, b.sim.previous, b.sim.aux, b.sim.continuous, b.sim.inputs, b.sim.modes, b.sim.last_loads])
			healthy = healthy and b.sim.tick == tick + 1 and b.sim.fault_reason.is_empty() and b.crash.is_empty()
	_check("timing toggle and read-only capture preserve all tested flight bytes", parity)
	_check("three new-seed sessions complete every accepted player tick", healthy)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(capture_path.path_join("manifest.json")))
	var persisted: Dictionary = Seeds.new().validate_record(manifest.admission.seed_allocation, 20261011, 0, 3)
	_check("capture persists the exact detached allocation", persisted.ok and persisted.record == right.manager.status().seed_allocation)
	print("SEED CAPTURE ", capture_path)
	var before: Array[Node] = right.manager.agents.duplicate()
	var capture_status: Dictionary = right.manager.recording_status()
	var bad: Dictionary = right.manager.config.duplicate(true)
	bad.seed = -1
	_check("invalid next admission refuses without replacing roster", not right.manager.configure(right.player, loaded.field, "club_field", bad, false, false).ok and before == right.manager.agents and capture_status == right.manager.recording_status())
	_dispose(left)
	_dispose(right)
	var zero_rms: Dictionary = Weather.preset("gentle-practice")
	zero_rms.turbulence_rms_mps = [0.0, 0.0, 0.0]
	for inactive: Dictionary in [Weather.defaults(), zero_rms]:
		var fixture: Dictionary = _fixture(loaded.field, inactive, false)
		if not fixture.manager.agents.is_empty():
			_check("inactive weather remains inactive", not fixture.manager.status().seed_weather.turbulence_active)
			_check("weather schema and seed presence are preserved", fixture.manager.agents[0].session.weather_configuration().format == inactive.format and fixture.manager.agents[0].session.weather_configuration().has("turbulence_seed") == inactive.has("turbulence_seed"))
		_dispose(fixture)
	var faulted: Dictionary = _fixture(loaded.field, weather, true, true)
	faulted.manager.last_tick_usec = 999999999
	faulted.player._physics_process(faulted.player.sim.dt())
	faulted.player.sim._physics_process(faulted.player.sim.dt())
	_check("postcommit player fault retains accepted timing pair", faulted.player.sim.tick == 1 \
		and faulted.manager.accepted_ticks == 1 and faulted.manager.last_tick_usec != 999999999 \
		and faulted.manager._pending_timing_tick == -1)
	_dispose(faulted)

func _dispose(fixture: Dictionary) -> void:
	fixture.manager.remove_now()
	fixture.manager.free()
	fixture.player.free()
