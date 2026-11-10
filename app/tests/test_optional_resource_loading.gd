extends SceneTree
## Optional resources stay unloaded until a selected builder or audio event needs them.
const Field := preload("res://render/field.gd")
const TrackField := preload("res://render/rc_track_field.gd")
const LakeWorld := preload("res://render/lake/lake_world.gd")
const WaterEffects := preload("res://render/lake/water_effects.gd")
const RcGround := preload("res://render/rc_ground_material.gd")
const Equipment := preload("res://aircraft/ugly_stik_equipment.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array = RcGround.TEXTURES.values()
	paths.append_array([Equipment.ENGINE_SCENE_PATH, WaterEffects.SPLASH_ONE_PATH,
		WaterEffects.SPLASH_TWO_PATH, WaterEffects.VISTULA_AMBIENCE_PATH,
		"res://assets/landscape/pond-plants/nymphaea_leaf.glb",
		"res://assets/landscape/pond-plants/white_waterlily_flower.glb",
		"res://assets/landscape/track-barrier/concrete-road-barrier-lod2.glb",
		"res://assets/landscape/track-tyre/old-tyre-1k.glb"])
	for path: String in paths:
		check("field, lake and aircraft scripts leave optional resource unloaded: " + path,
			not ResourceLoader.has_cached(path))
	check("empty circuit returns without building", TrackField.build({}, {}, {}, null) == null)
	var owner := Node3D.new()
	check("empty lake returns without building", LakeWorld.attach(owner, {}, null, {}, {}, false) == null)
	var ambient := WaterEffects.ambient_player({}, false)
	check("disabled lake audio has no stream", ambient.stream == null)
	for path: String in paths:
		check("disabled builders do not load " + path, not ResourceLoader.has_cached(path))
	ambient.free()
	owner.free()
	var lake := {water_level_down_m = 0.45}
	var effects := WaterEffects.new()
	root.add_child(effects)
	check("audio-off effect configures without splash resources", effects.configure(lake, false)
		and effects._splash_streams.is_empty() and not ResourceLoader.has_cached(WaterEffects.SPLASH_ONE_PATH)
		and not ResourceLoader.has_cached(WaterEffects.SPLASH_TWO_PATH))
	var hit := {point_ned = PackedFloat64Array([1.0, 2.0, 0.5]), tick = 1}
	check("audio-off impact still loads no splash resources", effects.begin(hit)
		and not ResourceLoader.has_cached(WaterEffects.SPLASH_ONE_PATH)
		and not ResourceLoader.has_cached(WaterEffects.SPLASH_TWO_PATH))
	check("audio-on configure preloads both splashes before impact", effects.configure(lake, true)
		and effects._splash_streams.size() == 2 and ResourceLoader.has_cached(WaterEffects.SPLASH_ONE_PATH)
		and ResourceLoader.has_cached(WaterEffects.SPLASH_TWO_PATH))
	check("audio-off reconfiguration releases the real WAV resources", effects.configure(lake, false)
		and effects._splash_streams.is_empty() and not ResourceLoader.has_cached(WaterEffects.SPLASH_ONE_PATH)
		and not ResourceLoader.has_cached(WaterEffects.SPLASH_TWO_PATH))
	check("audio-on can prepare splash streams again", effects.configure(lake, true)
		and effects._splash_streams.size() == 2 and ResourceLoader.has_cached(WaterEffects.SPLASH_ONE_PATH)
		and ResourceLoader.has_cached(WaterEffects.SPLASH_TWO_PATH))
	# Synthetic cached streams distinguish lookup from a hidden load(path) at impact.
	effects._splash_streams.assign([AudioStreamWAV.new(), AudioStreamWAV.new()])
	check("first impact uses the already prepared stream", effects.begin(hit)
		and effects._impact_voice.stream == effects._splash_streams[effects._impact_audio_source_index])
	effects.clear()
	check("event clear retains the prepared streams", effects._splash_streams.size() == 2)
	effects._splash_streams.assign([AudioStreamWAV.new(), AudioStreamWAV.new()])
	check("a second impact also uses only prepared streams", effects.begin(hit)
		and effects._impact_voice.stream == effects._splash_streams[effects._impact_audio_source_index])
	var checkpoint: Dictionary = effects.checkpoint()
	effects._splash_streams.assign([AudioStreamWAV.new(), AudioStreamWAV.new()])
	check("checkpoint restore uses only the prepared stream", effects.restore(checkpoint)
		and effects._impact_voice.stream == effects._splash_streams[effects._impact_audio_source_index])
	check("audio-off reconfiguration releases prepared splash streams", effects.configure(lake, false)
		and effects._splash_streams.is_empty() and effects._impact_voice.stream == null)
	effects.free()
	var material := ShaderMaterial.new()
	material.shader = RcGround.GROUND_SHADER
	RcGround.configure(material)
	for key: String in RcGround.TEXTURES:
		check("selected circuit binds " + key, material.get_shader_parameter(key) is Texture2D
			and ResourceLoader.has_cached(RcGround.TEXTURES[key]))
	var active_ambient := WaterEffects.ambient_player({}, true)
	check("enabled lake ambience binds its stream", active_ambient.stream is AudioStreamMP3 and (active_ambient.stream as AudioStreamMP3).loop)
	active_ambient.free()
	var anchor: Vector3 = Equipment.engine_anchor("engine_firewall_face")
	check("selected engine loads its scene and finite anchor", anchor.is_finite() and anchor.length() > 0.0)
	print("optional resource loading: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)
