extends SceneTree

const Effects = preload("res://render/lake/water_effects.gd")
const LakeLoader = preload("res://data/lake_loader.gd")
const Impact = preload("res://physics/impact_snapshot.gd")

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var loaded := LakeLoader.load_from()
	_check("normalized lake fixture loads", bool(loaded.get("ok", false)))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var lake: Dictionary = loaded.lake
	var effects := Effects.new()
	root.add_child(effects)
	_check("lake configuration accepts canonical water level", effects.configure(lake, true))
	_check("fixed visual pool is bounded", effects._rings.size() == Effects.RING_COUNT \
		and effects._droplet_multimesh.instance_count == Effects.MAX_DROPLETS)
	_check("pool meshes have no shadow casting", effects._plume.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and effects._droplets.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)

	var aircraft := Node3D.new()
	aircraft.name = "VisualAircraftRoot"
	aircraft.position = Vector3(12.0, 1.2, -7.0)
	root.add_child(aircraft)
	var aircraft_base: Transform3D = aircraft.global_transform
	var hit := Impact.Snapshot.new()
	hit.trigger = "hull_contact"
	hit.tick = 240
	hit.has_kinematics = true
	hit.point_ned = PackedFloat64Array([112.0, 129.0, 0.65])
	hit.velocity_ned = PackedFloat64Array([0.0, 0.0, 12.0])
	_check("snapshot starts one water event", effects.begin(hit, aircraft))
	_check("impact lands on mean water surface at world NED point",
		effects._impact_voice.global_position.is_equal_approx(Vector3(129.0, -0.45, -112.0)))
	_check("declarative depth is measured below mean water level", absf(effects._impact_depth_m - 0.20) < 1e-6)
	_check("one CC0 source voice is selected per begin", effects._impact_audio_emitted \
		and effects._impact_audio_requests_this_event == 1 and effects._impact_audio_source_index in [0, 1])
	_check("selected voice is one of the downloaded source clips", effects._impact_voice.stream == Effects.SPLASH_ONE \
		or effects._impact_voice.stream == Effects.SPLASH_TWO)
	_check("impact does not modify the immutable physics snapshot", hit.point_ned == PackedFloat64Array([112.0, 129.0, 0.65]) \
		and hit.velocity_ned == PackedFloat64Array([0.0, 0.0, 12.0]))

	effects.update(0.12, false)
	var advanced_time: float = effects._elapsed_s
	var advanced_root: Transform3D = aircraft.global_transform
	_check("local visual clock advances through crash freeze when user is not paused", advanced_time > 0.0)
	_check("only aircraft render root sinks", advanced_root.origin.y < aircraft_base.origin.y \
		and not advanced_root.origin.is_equal_approx(aircraft_base.origin))
	_check("render root stays above the declared visual sink limit", aircraft_base.origin.y - advanced_root.origin.y <= Effects.SINK_DEPTH_M)
	_check("rings stay small and muted rather than broad white foam", effects._rings.size() == 2 \
		and effects._ring_materials[0].get_shader_parameter("tint").a < 0.5)
	var droplet_data_finite := true
	for index: int in Effects.MAX_DROPLETS:
		var pose: Transform3D = effects._droplet_multimesh.get_instance_transform(index)
		droplet_data_finite = droplet_data_finite and pose.origin.is_finite() \
			and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite()
	_check("pooled droplet transforms remain finite", droplet_data_finite)

	var before_pause: Dictionary = effects.checkpoint()
	var paused_pose: Transform3D = aircraft.global_transform
	effects.update(0.20, true)
	_check("user pause freezes effect phase", effects._elapsed_s == advanced_time)
	_check("user pause freezes the visual aircraft sink", aircraft.global_transform == paused_pose)
	_check("checkpoint records emitted audio without replay state", bool(before_pause.get("impact_audio_emitted", false)) \
		and int(before_pause.get("impact_audio_source_index", -1)) in [0, 1])
	effects.update(0.10, false)
	_check("unpaused visual phase resumes", effects._elapsed_s > advanced_time)
	var before_cap: float = effects._elapsed_s
	effects.update(10.0, false)
	_check("frame delta and event clock remain bounded", effects._elapsed_s == before_cap + 0.25 \
		and effects._elapsed_s <= Effects.MAX_EFFECT_DURATION_S)
	for step: int in 20:
		effects.update(0.25, false)
	_check("finite event clock retires every effect mesh", effects._elapsed_s == Effects.MAX_EFFECT_DURATION_S \
		and not effects._plume.visible and effects._rings.all(func(ring: MeshInstance3D) -> bool: return not ring.visible) \
		and not effects._droplets.visible)

	var checkpoint: Dictionary = effects.checkpoint()
	var prepared: Dictionary = effects.prepare_restore(checkpoint)
	_check("valid phase state prepares for restore", not prepared.is_empty() \
		and is_equal_approx(float(prepared.elapsed_s), effects._elapsed_s))
	var unconfigured := Effects.new()
	_check("event restore requires an already configured lake", not unconfigured.restore(checkpoint) \
		and not unconfigured._has_event)
	unconfigured.free()
	var restored := Effects.new()
	root.add_child(restored)
	_check("restore target configures independently", restored.configure(lake, true))
	var restored_aircraft := Node3D.new()
	root.add_child(restored_aircraft)
	var restored_base: Transform3D = restored_aircraft.global_transform
	_check("restore rebuilds visuals and sink phase", restored.restore(checkpoint, restored_aircraft) \
		and is_equal_approx(restored._elapsed_s, effects._elapsed_s) \
		and restored_aircraft.global_position.y <= restored_base.origin.y)
	_check("restore retains source selection but does not replay impact audio",
		restored._impact_audio_emitted and restored._impact_audio_requests_this_event == 0 \
		and not restored._impact_voice.playing)
	var unchanged_elapsed: float = restored._elapsed_s
	var bad_checkpoint := checkpoint.duplicate(true)
	bad_checkpoint["elapsed_s"] = NAN
	_check("nonfinite phase is rejected before mutation", restored.prepare_restore(bad_checkpoint).is_empty() \
		and not restored.restore(bad_checkpoint) and restored._elapsed_s == unchanged_elapsed)
	bad_checkpoint = checkpoint.duplicate(true)
	bad_checkpoint["point_ned"] = [0.0, INF, 0.0]
	_check("nonfinite impact coordinates are rejected", restored.prepare_restore(bad_checkpoint).is_empty())
	bad_checkpoint = checkpoint.duplicate(true)
	bad_checkpoint["impact_depth_m"] = Effects.MAX_LAKE_DEPTH_M + 1.0
	_check("impossible lake depth is rejected", restored.prepare_restore(bad_checkpoint).is_empty())

	var dict_fx := Effects.new()
	root.add_child(dict_fx)
	_check("audio-off configuration accepts the same lake", dict_fx.configure(lake, false))
	_check("dictionary impact starts with no audio event", dict_fx.begin({
		"trigger": "water", "tick": 31, "point_ned": PackedFloat64Array([115.0, 122.0, 0.45]),
		"simulation_frozen": true,
	}))
	_check("audio-off event has no stream or playback request", not dict_fx._impact_audio_emitted \
		and dict_fx._impact_audio_source_index == -1 and dict_fx._impact_audio_requests_this_event == 0 \
		and dict_fx._impact_voice.stream == null)
	var dict_start: float = dict_fx._elapsed_s
	dict_fx.update(0.10, false)
	_check("simulation freeze is ignored by render clock", dict_fx._elapsed_s > dict_start)
	_check("invalid impact leaves current render event unchanged", not dict_fx.begin({"point_ned": [0.0, NAN, 0.0]}) \
		and dict_fx._elapsed_s == dict_start + 0.10)

	var ambience := Effects.ambient_player(lake, true)
	_check("ambient uses the verified MP3 source as a loop", ambience.stream is AudioStreamMP3 \
		and (ambience.stream as AudioStreamMP3).loop)
	_check("ambient is quiet and localized to the lake", ambience.volume_db == -28.0 \
		and ambience.max_distance == 120.0 and is_equal_approx(ambience.position.y, -0.45))
	var disabled_ambience := Effects.ambient_player(lake, false)
	_check("disabled ambience has no stream", disabled_ambience.stream == null and disabled_ambience.volume_db <= -80.0)
	ambience.free()
	disabled_ambience.free()

	effects.clear()
	_check("clear restores the visual model and clears the event", not effects._has_event \
		and aircraft.global_transform == aircraft_base and effects._impact_voice.stream == null and not effects._plume.visible)
	var clean := effects.checkpoint()
	_check("cleared checkpoint is safely restorable", effects.restore(clean) and not effects._has_event)

	effects.free()
	restored.free()
	dict_fx.free()
	aircraft.free()
	restored_aircraft.free()
	_finish()


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if passed:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label)


func _finish() -> void:
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
