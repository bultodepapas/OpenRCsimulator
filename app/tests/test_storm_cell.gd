extends SceneTree

const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyAppearance := preload("res://render/weather/sky_appearance.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")
const StormEvents := preload("res://environment/storm_events.gd")
const StormCell := preload("res://render/weather/storm_cell.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_cardinal_transport_oracle()
	_test_event_identity_and_local_geometry()
	_test_query_order_and_rebase()
	_test_nearest_periodic_copy()
	_test_malformed_and_empty_context()
	_test_global_rng_isolation()
	print("storm cell checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_cardinal_transport_oracle() -> void:
	var base: Dictionary = _base_context()
	var spec: Dictionary = base.spec
	var resolved: Dictionary = base.resolved
	var layers: Array = resolved.cloud_layers
	var reference := Vector3(123456.0, 400.0, -234567.0)
	var test_time: float = 1.23
	var quantized_elapsed: float = 1.0 # floor(1.23 / 0.5) * 0.5, anchored at 0 s.
	var cell_m: float = float(layers[int(spec.advection_layer)].scale_m)
	var period_m: float = 64.0 * cell_m
	var calm_transport: Dictionary = _transport(layers, [0.0, 0.0, 0.0])
	var calm_center: Vector3 = StormCell.center_at(spec, calm_transport, test_time, reference)

	for cardinal: Dictionary in [
		{"name": "north", "wind": [8.0, 0.0, 0.0]},
		{"name": "east", "wind": [0.0, 8.0, 0.0]},
	]:
		var state: Dictionary = _transport(layers, cardinal.wind)
		var transport_layer: Dictionary = state.layers[int(spec.advection_layer)]
		var velocity: Array = transport_layer.velocity_cells_s
		var anchor_offset: Array = transport_layer.anchor_offset
		var offset_x: float = fposmod(float(anchor_offset[0]) + float(velocity[0]) * quantized_elapsed, 64.0)
		var offset_y: float = fposmod(float(anchor_offset[1]) + float(velocity[1]) * quantized_elapsed, 64.0)
		var raw_x: float = float(spec.east_m) - offset_x * cell_m
		var raw_z: float = -float(spec.north_m) - offset_y * cell_m
		var expected := Vector3(_nearest(raw_x, reference.x, period_m), 0.0,
			_nearest(raw_z, reference.z, period_m))
		var observed: Vector3 = StormCell.center_at(spec, state, test_time, reference)
		_check("%s wind uses the quantized scalar offset and bank-axis mapping" % cardinal.name,
			observed.is_equal_approx(expected))
		if cardinal.name == "north":
			_check("northward wind moves the storm bank toward negative world Z", observed.z < calm_center.z)
		else:
			_check("eastward wind moves the storm bank toward positive world X", observed.x > calm_center.x)


func _test_event_identity_and_local_geometry() -> void:
	var context: Dictionary = _base_context()
	var legacy: StormEvents = _configured("full")
	var contextual: StormEvents = _configured("full")
	contextual.set_cell_context(context.spec, context.transport, Vector3(0.0, 0.0, -9000.0))
	var legacy_events: Array[Dictionary] = legacy.events_for_window(0, 60 * 240)
	var contextual_events: Array[Dictionary] = contextual.events_for_window(0, 60 * 240)
	_check("cell placement preserves event identity, times, modes, and geometry seeds",
		_identity_projection(legacy_events) == _identity_projection(contextual_events))
	_check("cell placement marks contextual records without changing schedule version",
		not contextual_events.is_empty() and contextual_events[0].get("placement_mode", "") == "storm_cell"
		and int(contextual_events[0].version) == StormEvents.SCHEDULE_VERSION)
	if legacy_events.is_empty() or contextual_events.is_empty():
		return
	var before: Dictionary = legacy_events[0]
	var placed: Dictionary = contextual_events[0]
	var raw_source: Vector3 = _as_vector3(before.source_world)
	var raw_ground: Vector3 = _as_vector3(before.ground_world)
	var source_offset_x: float = raw_source.x
	var source_offset_z: float = raw_source.z - StormEvents.DEFAULT_ANCHOR_WORLD.z
	var ground_offset_x: float = raw_ground.x - raw_source.x
	var ground_offset_z: float = raw_ground.z - raw_source.z
	var reference := Vector3(0.0, 0.0, -9000.0)
	var center: Vector3 = StormCell.center_at(context.spec, context.transport,
		float(placed.start_time_s), reference)
	var source := Vector3(
		center.x + source_offset_x / 1500.0 * float(context.spec.width_m) * 0.12,
		float(context.spec.base_m) + (float(context.spec.top_m) - float(context.spec.base_m)) * 0.65,
		center.z + source_offset_z / 1200.0 * float(context.spec.depth_m) * 0.16)
	var ground := Vector3(
		center.x + source_offset_x / 1500.0 * float(context.spec.width_m) * 0.12
			+ ground_offset_x / 500.0 * float(context.spec.width_m) * 0.08,
		0.0,
		center.z + source_offset_z / 1200.0 * float(context.spec.depth_m) * 0.16
			+ ground_offset_z / 500.0 * float(context.spec.depth_m) * 0.08)
	var expected_channel: Vector3 = source.lerp(ground, 0.48) if str(placed.kind) == "cloud_to_ground" \
		else source + Vector3(850.0, -170.0, -240.0)
	_check("event source uses the emission-time bank centre and specified source altitude",
		_as_vector3(placed.source_world).is_equal_approx(source))
	_check("event ground stays on y=0 and channel follows the existing path rule",
		_as_vector3(placed.ground_world).is_equal_approx(ground)
		and _as_vector3(placed.channel_world).is_equal_approx(expected_channel))
	var reduced: StormEvents = _configured("reduced")
	var off: StormEvents = _configured("off")
	reduced.set_cell_context(context.spec, context.transport, reference)
	off.set_cell_context(context.spec, context.transport, reference)
	_check("Full, Reduced, and Off retain contextual event identities",
		_identity_projection(contextual_events) == _identity_projection(reduced.events_for_window(0, 60 * 240))
		and _identity_projection(contextual_events) == _identity_projection(off.events_for_window(0, 60 * 240)))
	var other_seed: StormEvents = _configured("full", 71)
	other_seed.set_cell_context(context.spec, context.transport, reference)
	var other_seed_events: Array[Dictionary] = other_seed.events_for_window(0, 60 * 240)
	_check("a different visual seed changes contextual event identity",
		not other_seed_events.is_empty()
		and str(other_seed_events[0].event_id) != str(contextual_events[0].event_id)
		and int(other_seed_events[0].appearance_generation) != int(contextual_events[0].appearance_generation))


func _test_query_order_and_rebase() -> void:
	var context: Dictionary = _base_context()
	var reference := Vector3(2500.0, 200.0, -7000.0)
	var first_schedule: StormEvents = _configured("full")
	first_schedule.set_cell_context(context.spec, context.transport, reference)
	var broad: Array[Dictionary] = first_schedule.events_for_window(0, 60 * 240)
	if broad.is_empty():
		_check("query order test has a scheduled event", false)
		return
	var target: Dictionary = broad[0]
	var second_schedule: StormEvents = _configured("full")
	second_schedule.set_cell_context(context.spec, context.transport, reference)
	second_schedule.events_for_window(int(target.start_tick) - 20, int(target.start_tick) + 20)
	var after_narrow_first: Dictionary = _find_event(second_schedule.events_for_window(0, 60 * 240), str(target.event_id))
	_check("narrow-first and broad-first queries produce the same event placement",
		_event_positions_equal(target, after_narrow_first))

	var rebased: Dictionary = CloudTransport.rebase(context.transport, 2400.0)
	var rebased_schedule: StormEvents = _configured("full")
	rebased_schedule.set_cell_context(context.spec, rebased, reference)
	var after_rebase: Dictionary = _find_event(rebased_schedule.events_for_window(0, 60 * 240), str(target.event_id))
	_check("rebasing transport keeps the emission-time anchor stable for a fixed reference",
		_event_positions_equal(target, after_rebase))
	var event_center: Vector3 = StormCell.center_at(context.spec, rebased,
		float(target.start_time_s), reference)
	var event_source: Vector3 = _as_vector3(after_rebase.get("source_world", PackedFloat64Array()))
	_check("event placement evaluates transport at start_time_s, not the query horizon",
		absf(event_source.y - (float(context.spec.base_m)
			+ (float(context.spec.top_m) - float(context.spec.base_m)) * 0.65)) < 0.001
		and event_center.y == 0.0)


func _test_nearest_periodic_copy() -> void:
	var context: Dictionary = _base_context()
	var reference := Vector3(9876543.0, 1000.0, -8765432.0)
	var center: Vector3 = StormCell.center_at(context.spec, context.transport, 0.0, reference)
	var layer: Dictionary = context.transport.layers[int(context.spec.advection_layer)]
	var period_m: float = 64.0 * float(layer.scale_m)
	_check("remote reference selects the nearest periodic storm-bank copy",
		absf(center.x - reference.x) <= period_m * 0.5 + 0.01
		and absf(center.z - reference.z) <= period_m * 0.5 + 0.01)


func _test_malformed_and_empty_context() -> void:
	var context: Dictionary = _base_context()
	var schedule: StormEvents = _configured("full")
	var expected: Array[Dictionary] = _configured("full").events_for_window(0, 60 * 240)
	schedule.set_cell_context(context.spec, context.transport, Vector3.ZERO)
	var contextual: Array[Dictionary] = schedule.events_for_window(0, 60 * 240)
	_check("valid bank and accepted transport enable cell placement",
		not contextual.is_empty() and contextual[0].get("placement_mode", "") == "storm_cell")
	schedule.set_cell_context({"layout_version": 99}, context.transport, Vector3.ZERO)
	_check("malformed context safely clears back to legacy geometry",
		not schedule._cell_context_valid and schedule.events_for_window(0, 60 * 240) == expected)
	schedule.set_cell_context(context.spec, context.transport, Vector3.ZERO)
	schedule.set_cell_context({}, {}, Vector3.ZERO)
	_check("empty context clears back to byte-for-byte legacy records",
		not schedule._cell_context_valid and schedule.events_for_window(0, 60 * 240) == expected)
	schedule.set_cell_context(context.spec, context.transport, Vector3.ZERO)
	schedule.configure({"preset": "electrical_storm", "seed": 90210,
		"tick_rate_hz": 60, "flashes": "full"})
	_check("reconfigure clears a previously valid cell context",
		not schedule._cell_context_valid and schedule.events_for_window(0, 60 * 240) == expected)


func _test_global_rng_isolation() -> void:
	var context: Dictionary = _base_context()
	seed(712367)
	var expected: int = randi()
	seed(712367)
	var schedule: StormEvents = _configured("full")
	schedule.set_cell_context(context.spec, context.transport, Vector3.ZERO)
	schedule.events_for_window(0, 60 * 240)
	var observed: int = randi()
	_check("storm-cell event placement does not advance global RNG", observed == expected)


func _base_context() -> Dictionary:
	var selection: Dictionary = SkyConfig.for_preset("distant_storm")
	var checked: Dictionary = SkyConfig.validate(selection)
	var profile: Dictionary = checked.profile
	var resolved: Dictionary = SkyAppearance.resolve(profile, selection)
	var layers: Array = resolved.cloud_layers
	return {
		"spec": profile.renderer.storm_bank.duplicate(true),
		"resolved": resolved,
		"transport": _transport(layers, [0.0, 0.0, 0.0]),
	}


func _transport(layers: Array, wind: Array) -> Dictionary:
	return CloudTransport.build({"motion": "follow_wind"}, layers, wind, 0.0, 0.5,
		Vector2.ZERO, [Vector2(12.0, 25.0)])


func _configured(flashes: String, visual_seed: int = 90210) -> StormEvents:
	var schedule: StormEvents = StormEvents.new()
	schedule.configure({"preset": "electrical_storm", "seed": visual_seed,
		"tick_rate_hz": 60, "flashes": flashes})
	return schedule


func _identity_projection(events: Array[Dictionary]) -> Array:
	var result: Array = []
	for event: Dictionary in events:
		result.append([
			event.event_id, event.appearance_generation, event.start_tick, event.start_time_s,
			event.kind, event.geometry_seed, event.pulse_envelope, event.duration_s,
			event.intensity, event.thunder_asset_id,
		])
	return result


func _find_event(events: Array[Dictionary], event_id: String) -> Dictionary:
	for event: Dictionary in events:
		if str(event.get("event_id", "")) == event_id:
			return event
	return {}


func _event_positions_equal(first: Dictionary, second: Dictionary) -> bool:
	if second.is_empty():
		return false
	return _as_vector3(first.source_world).is_equal_approx(_as_vector3(second.source_world)) \
		and _as_vector3(first.ground_world).is_equal_approx(_as_vector3(second.ground_world)) \
		and _as_vector3(first.channel_world).is_equal_approx(_as_vector3(second.channel_world))


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _nearest(coordinate: float, reference_coordinate: float, period_m: float) -> float:
	return coordinate + floor((reference_coordinate - coordinate) / period_m + 0.5) * period_m


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s" % label)
