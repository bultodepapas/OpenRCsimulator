extends SceneTree

const WorldBuilder := preload("res://render/world/world.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const StormEvents := preload("res://environment/storm_events.gd")
const Lightning := preload("res://render/weather/lightning.gd")
const StormAudio := preload("res://audio/storm_audio.gd")
const StormBank := preload("res://render/weather/storm_bank.gd")
const CloudTransport := preload("res://render/weather/cloud_transport.gd")

const SEED := 1253
const TICK_RATE_HZ := 60
const FIRST_PULSE_PEAK_S := 0.0375
const SECOND_PULSE_S := 0.20
const THIRD_PULSE_PEAK_S := 0.6575
const NIGHT_OPTIONS := {"field_lighting": "off", "campfire": false}

var _checks := 0
var _failures := 0
var _field: Dictionary = {}
var _transport: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	_check("production field validates", loaded.get("ok", false))
	if not loaded.get("ok", false):
		_finish()
		return
	_field = loaded.field
	var appearance: Dictionary = SkyConfig.for_preset("electrical_storm")
	appearance.seed = SEED
	appearance.motion = "still"
	_check("electrical_storm profile loads", not appearance.is_empty())
	_check("Still electrical storm appearance configures", 
		Atmosphere.configure_appearance(appearance, [0.0, 0.0, 0.0], 0.0))
	_transport = Atmosphere.cloud_transport_checkpoint()
	_check("cloud transport checkpoint validates as Still",
		CloudTransport.validate(_transport) and str(_transport.get("motion", "")) == "still")
	if _failures > 0:
		_finish()
		return

	var first_world: Dictionary = _build_world("ElectricalBankSceneA")
	var second_world: Dictionary = _build_world("ElectricalBankSceneB")
	var bank_a: StormBank = first_world.get("bank") as StormBank
	var bank_b: StormBank = second_world.get("bank") as StormBank
	_check("World exposes two independent live storm banks", bank_a != null and bank_b != null
		and bank_a != bank_b and bank_a.cell_spec() == bank_b.cell_spec())
	if bank_a == null or bank_b == null:
		_finish()
		return

	var event: Dictionary = _first_cloud_to_ground(bank_a)
	_check("seed 1253 has a scheduled cloud-to-ground event", not event.is_empty())
	if event.is_empty():
		_finish()
		return
	var event_id := str(event.event_id)
	var start_s := float(event.start_time_s)
	var listener := Vector3.ZERO
	var lightning := Lightning.new()
	lightning.name = "ElectricalBankRuntimeTestLightning"
	root.add_child(lightning)
	lightning.configure(_storm_config("full"))
	lightning.bind_storm_bank(bank_a)
	lightning.set_cell_transport(_transport)
	lightning.set_cloud_state(Atmosphere.cloud_state_snapshot())

	var peak_time := start_s + FIRST_PULSE_PEAK_S
	lightning.update_at(peak_time, listener, false, 1.0)
	var full_snapshot: Dictionary = lightning.snapshot()
	var full_flash: Dictionary = _bank_flash(bank_a)
	var full_level := float(full_flash.get("level", 0.0))
	var full_radiance := float(full_flash.get("radiance", 0.0))
	_check("Full routes the scheduled event into its World bank",
		str(full_snapshot.get("event_id", "")) == event_id
		and str(full_flash.get("event_id", "")) == event_id and full_level > 0.0 and full_level <= 1.0)
	_check("bank flash radiance is positive and finite", is_finite(full_radiance) and full_radiance > 0.0)
	_check("separate World bank remains dark", float(_bank_flash(bank_b).get("level", 0.0)) == 0.0)
	var original_source := _as_vector3(full_snapshot.get("source_world", []))
	var original_channel := _as_vector3(event.get("channel_world", []))

	lightning.configure(_storm_config("reduced"))
	lightning.bind_storm_bank(bank_a)
	lightning.set_cell_transport(_transport)
	lightning.update_at(peak_time, listener, false, 1.0)
	var reduced_snapshot: Dictionary = lightning.snapshot()
	var reduced_flash: Dictionary = _bank_flash(bank_a)
	var reduced_level := float(reduced_flash.get("level", 0.0))
	_check("Reduced keeps the same event with a smaller bounded bank flash",
		str(reduced_snapshot.get("event_id", "")) == event_id
		and str(reduced_flash.get("event_id", "")) == event_id
		and reduced_level > 0.0 and reduced_level < full_level and reduced_level <= 1.0)

	lightning.configure(_storm_config("off"))
	lightning.bind_storm_bank(bank_a)
	lightning.set_cell_transport(_transport)
	lightning.update_at(peak_time, listener, false, 1.0)
	_check("Off clears the bank flash while preserving the scheduled event record",
		float(_bank_flash(bank_a).get("level", 0.0)) == 0.0
		and _event_id_at(lightning._events, start_s) == event_id)
	_check("flash mode does not alter event identity or geometry",
		_event_at(lightning._events, start_s).get("source_world", []) == event.get("source_world", [])
		and _event_at(lightning._events, start_s).get("channel_world", []) == event.get("channel_world", []))

	# Reconfigure Full and create the actual pending-thunder record before a 100 km camera cut.
	lightning.configure(_storm_config("full"))
	lightning.bind_storm_bank(bank_a)
	lightning.set_cell_transport(_transport)
	lightning.update_at(peak_time, listener, false, 1.0)
	var audio: StormAudio = lightning.get_node("StormAudio") as StormAudio
	var pending_before: Dictionary = _pending_event(audio, event_id)
	var queued_channel := _as_vector3(pending_before.get("channel_world", []))
	_check("visible pulse queues thunder at the event channel",
		not pending_before.is_empty() and queued_channel.distance_to(original_channel) < 0.01)
	var original_placement: Dictionary = lightning._event_placement.duplicate(true)
	var listener_after_small_cut := listener + Vector3(100.0, 0.0, 0.0)
	lightning.update_at(start_s + 0.12, listener_after_small_cut, false, 1.0)
	var pending_after_small_cut: Dictionary = _pending_event(audio, event_id)
	_check("100 m camera cut preserves the pending thunder channel",
		not pending_after_small_cut.is_empty()
		and _same_world_point(_as_vector3(pending_after_small_cut.get("channel_world", [])), queued_channel))
	var cut_listener := listener_after_small_cut + Vector3(100000.0, 0.0, 0.0)
	var cut_time := start_s + 0.14
	_check("100 km cut follows the small cut without a seek-sized time gap",
		cut_time - (start_s + 0.12) <= 0.5)
	lightning.update_at(cut_time, cut_listener, false, 1.0)
	var cut_schedule_event := _event_at(lightning._events, start_s)
	_check("camera cut keeps event identity while placement is recomputed for that camera",
		str(cut_schedule_event.get("event_id", "")) == event_id
		and not _same_world_point(_as_vector3(cut_schedule_event.get("source_world", [])), original_source))
	_check("active event source and thunder channel stay anchored through the cut",
		_same_world_point(_as_vector3(lightning._event_placement.get("source_world", [])), original_source)
		and _same_world_point(_as_vector3(lightning._event_placement.get("channel_world", [])), queued_channel)
		and _same_world_point(_as_vector3(original_placement.get("channel_world", [])), queued_channel))
	lightning.update_at(start_s + SECOND_PULSE_S, cut_listener, false, 1.0)
	var after_cut_snapshot: Dictionary = lightning.snapshot()
	var pending_after: Dictionary = _pending_event(audio, event_id)
	var audio_channel_unchanged := pending_after.is_empty() or _same_world_point(
		_as_vector3(pending_after.get("channel_world", [])), queued_channel)
	_check("next pulse reuses the emitted source and event id after the 100 km cut",
		str(after_cut_snapshot.get("event_id", "")) == event_id
		and _same_world_point(_as_vector3(after_cut_snapshot.get("source_world", [])), original_source))
	_check("100 km cut prunes inaudible thunder without retargeting or replaying it",
		audio_channel_unchanged and pending_after.is_empty() and audio._seen.has(event_id)
		and int(after_cut_snapshot.get("pending_thunder", -1)) == 0)

	var child_count_after_first_flash := lightning.get_child_count()
	lightning.update_at(start_s + 0.24, cut_listener, false, 1.0)
	lightning.update_at(start_s + 0.65, cut_listener, false, 1.0)
	lightning.update_at(start_s + THIRD_PULSE_PEAK_S, cut_listener, false, 1.0)
	_check("repeated pulses reuse Lightning nodes", lightning.get_child_count() == child_count_after_first_flash)
	_check("same event identity persists across all three scheduled pulses",
		str(lightning.snapshot().get("event_id", "")) == event_id)

	# Rebinding must clear the old scene and write only into the new World's bank.
	lightning.bind_storm_bank(bank_b)
	_check("rebinding clears the previous World's transient flash",
		float(_bank_flash(bank_a).get("level", 0.0)) == 0.0)
	lightning.update_at(start_s + THIRD_PULSE_PEAK_S + 0.01, listener, false, 1.0)
	_check("bound Lightning writes the flash only into the second World",
		float(_bank_flash(bank_b).get("level", 0.0)) > 0.0
		and float(_bank_flash(bank_a).get("level", 0.0)) == 0.0)

	lightning.update_at(start_s + THIRD_PULSE_PEAK_S + 0.02, listener, true, 1.0)
	_check("pause clears a live bank pulse", float(_bank_flash(bank_b).get("level", 0.0)) == 0.0)
	lightning.update_at(start_s + THIRD_PULSE_PEAK_S + 0.03, listener, false, 1.0)
	_check("resume still uses the scheduled event", str(lightning.snapshot().get("event_id", "")) == event_id)
	lightning.reset()
	_check("reset clears the bank pulse and event placement",
		float(_bank_flash(bank_b).get("level", 0.0)) == 0.0 and lightning._event_placement.is_empty())

	lightning.update_at(start_s + THIRD_PULSE_PEAK_S, listener, false, 1.0)
	_check("post-reset pulse can be replayed", float(_bank_flash(bank_b).get("level", 0.0)) > 0.0)
	lightning.configure(_storm_config("full"))
	_check("reconfigure clears the prior scene pulse", float(_bank_flash(bank_b).get("level", 0.0)) == 0.0)
	lightning.bind_storm_bank(bank_b)
	lightning.set_cell_transport(_transport)
	lightning.update_at(start_s + THIRD_PULSE_PEAK_S, listener, false, 1.0)
	lightning.update_at(start_s + 0.30, listener, false, 1.0)
	_check("backseek restore clears pulse and placement", float(_bank_flash(bank_b).get("level", 0.0)) == 0.0
		and lightning._event_placement.is_empty())
	_check("reconfigure, replay, pause and restore allocate no extra nodes",
		lightning.get_child_count() == child_count_after_first_flash)

	lightning.configure(_storm_config("full"))
	lightning.bind_storm_bank(bank_b)
	lightning.set_cell_transport(_transport)
	lightning.update_at(start_s + FIRST_PULSE_PEAK_S, listener, false, 1.0)
	_check("scene-exit lifecycle starts from a visible bank pulse",
		float(_bank_flash(bank_b).get("level", 0.0)) > 0.0)
	lightning.queue_free()
	await process_frame
	_check("Lightning scene exit clears its World's transient bank flash",
		float(_bank_flash(bank_b).get("level", 0.0)) == 0.0)
	(first_world.get("root") as Node).queue_free()
	(second_world.get("root") as Node).queue_free()
	await process_frame
	_finish()


func _build_world(world_name: String) -> Dictionary:
	var scene_root := Node3D.new()
	scene_root.name = world_name
	root.add_child(scene_root)
	var built: Dictionary = WorldBuilder.build(scene_root, _field, Callable(self, "_skip_field"), {}, {}, NIGHT_OPTIONS)
	var environment: Environment = built.get("environment") as Environment
	if environment == null:
		return {"root": scene_root}
	WorldBuilder.update(environment, 0.0, Vector3.ZERO)
	WorldBuilder.refresh_weather_appearance(environment, 0.0)
	return {
		"root": scene_root,
		"environment": environment,
		"bank": WorldBuilder.storm_bank_node(environment) as StormBank,
	}


func _skip_field() -> void:
	pass


func _first_cloud_to_ground(bank: StormBank) -> Dictionary:
	var schedule := StormEvents.new()
	schedule.configure(_storm_config("full"))
	schedule.set_cell_context(bank.cell_spec(), _transport, Vector3.ZERO)
	var end_tick := int(round(64.0 * StormEvents.SLOT_SECONDS * float(TICK_RATE_HZ)))
	for event: Dictionary in schedule.events_started_in_window(0, end_tick):
		if str(event.get("kind", "")) == "cloud_to_ground":
			return event
	return {}


func _event_at(schedule: StormEvents, time_s: float) -> Dictionary:
	var tick := schedule.tick_for_time(time_s)
	for event: Dictionary in schedule.events_for_window(tick, tick):
		if str(event.get("kind", "")) == "cloud_to_ground":
			return event
	return {}


func _event_id_at(schedule: StormEvents, time_s: float) -> String:
	return str(_event_at(schedule, time_s).get("event_id", ""))


func _storm_config(flashes: String) -> Dictionary:
	return {
		"preset": "electrical_storm",
		"seed": SEED,
		"tick_rate_hz": TICK_RATE_HZ,
		"flashes": flashes,
		"thunder_volume": 0.7,
	}


func _bank_flash(bank: StormBank) -> Dictionary:
	return bank.snapshot().get("flash", {})


func _pending_event(audio: StormAudio, event_id: String) -> Dictionary:
	for event: Dictionary in audio._pending:
		if str(event.get("event_id", "")) == event_id:
			return event
	return {}


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is PackedFloat64Array and value.size() >= 3:
		return Vector3(value[0], value[1], value[2])
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _same_world_point(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.01


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s" % label)


func _finish() -> void:
	print("electrical bank checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
