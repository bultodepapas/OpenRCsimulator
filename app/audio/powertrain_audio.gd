## AUD-15: recorded powertrain banks. Detached presentation only; never owns shaft dynamics.
extends Node3D

const EngineSound = preload("res://render/engine_sound.gd")
const Model = preload("res://audio/soundscape_model.gd")
const ASSET_PATH := "res://assets/audio/powertrains/"
const MANIFEST_PATH := ASSET_PATH + "BANKS.json"
const BUS_TRIM_DB := 12.0
const GUARD_FRAMES := 64
const MAX_LAYERS := 3
var profile: Dictionary = {}
var layers: Array[Dictionary] = []
var players: Array[AudioStreamPlayer3D] = []
var levels := PackedFloat64Array()
var last_targets: Dictionary = {}
var _started: bool = false
var _rpm: float = 0.0
var _primed: bool = false
var _bus: StringName


## Installed identity, independent of visual mesh and the legacy glow_prop schema name.
static func profile_for(aircraft_id: String, propulsion: Dictionary) -> Dictionary:
	var kind: String = str(propulsion.get("kind", "glow_prop"))
	var family: String = str(propulsion.get("glow", {}).get("profile", {}).get("family", "glow_2t"))
	if kind == "electric_prop":
		family = "electric"
	elif kind == "turbine":
		family = "turbine"
	elif aircraft_id == "p51d-mustang-120" or str(propulsion.get("fuel_consumption", {}).get("law", "")) == "gasoline_bsfc_v1":
		family = "gasoline"
	elif aircraft_id == "xcell-60-research":
		family = "rotor"
	var blades: int = 4 if aircraft_id == "p51d-mustang-120" else (3 if aircraft_id == "turbo-lumber-evolution" else 2)
	# A .55 installation is slightly lighter voiced than the .61; no fabricated recording identity.
	var trim: float = -1.0 if aircraft_id == "stik-glow-55ax-2t" else (0.7 if aircraft_id == "gp-extra-300s-60" else 0.0)
	return {id = aircraft_id, family = family, max_rpm = EngineSound.reference_rpm(propulsion),
		blades = blades, trim_db = trim}


func configure(voice_profile: Dictionary, bus: StringName) -> bool:
	profile = voice_profile.duplicate(true)
	_bus = bus
	if not FileAccess.file_exists(MANIFEST_PATH):
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary:
		return false
	var bank: Array = manifest.get(str(profile.get("family", "")), [])
	for entry: Dictionary in bank:
		if layers.size() == MAX_LAYERS:
			break
		var source := load(ASSET_PATH + str(entry.file)) as AudioStreamWAV
		if source == null:
			continue
		var player := AudioStreamPlayer3D.new()
		player.name = "RecordedEngine%d" % players.size()
		player.stream = guarded_loop(source)
		player.bus = bus
		# One bounded distance law avoids Godot's near-field max_db clamp bypassing a quiet envelope.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 0.0
		player.max_db = 6.0
		player.attenuation_filter_db = 0.0
		player.panning_strength = 0.75
		player.volume_db = -100.0
		add_child(player)
		players.append(player)
		layers.append(entry.duplicate(true))
	levels.resize(players.size())
	return not players.is_empty()


static func guarded_loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var loop := source.duplicate() as AudioStreamWAV
	var stride: int = (2 if source.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if source.stereo else 1)
	var frames: int = source.data.size() / stride
	var bytes: PackedByteArray = source.data.duplicate()
	bytes.append_array(bytes.slice(0, mini(GUARD_FRAMES, frames) * stride))
	loop.data = bytes
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = frames
	return loop


static func distance_gain(distance_m: float) -> float:
	return 8.0 / maxf(distance_m, 3.0) * (1.0 - smoothstep(1200.0, 1500.0, distance_m))


## Adjacent equal-power bands, no random pitch or cyclic volume wobble.
static func band_weights(rpm: float, references: PackedFloat64Array) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	weights.resize(references.size())
	if references.is_empty():
		return weights
	if rpm <= references[0]:
		weights[0] = 1.0
		return weights
	for index: int in range(references.size() - 1):
		if rpm <= references[index + 1]:
			var fraction: float = clampf(log(rpm / references[index]) / log(references[index + 1] / references[index]), 0.0, 1.0)
			weights[index] = cos(fraction * PI * 0.5)
			weights[index + 1] = sin(fraction * PI * 0.5)
			return weights
	weights[-1] = 1.0
	return weights


func update_sound(snapshot: Dictionary, delta: float, mix_gain: float = 1.0, doppler: float = 1.0) -> void:
	if players.is_empty():
		return
	var dt: float = clampf(delta, 0.0, 0.1)
	var paused: bool = bool(snapshot.get("paused", false))
	var accepted_rpm: float = maxf(float(snapshot.get("rpm", 0.0)), 0.0)
	var maximum: float = maxf(float(snapshot.get("max_rpm", profile.get("max_rpm", 12000.0))), 1.0)
	var running: bool = bool(snapshot.get("running", false))
	var source: Vector3 = snapshot.get("source", Vector3.ZERO)
	var listener: Vector3 = snapshot.get("listener", Vector3.ZERO)
	var family: String = str(profile.family)
	if not _primed:
		_rpm = accepted_rpm
		_primed = true
	if not paused:
		_rpm = lerpf(_rpm, accepted_rpm, 1.0 - exp(-dt / 0.055))
	var ratio: float = clampf(_rpm / maximum, 0.0, 1.3)
	var throttle: float = clampf(float(snapshot.get("throttle", 0.0)), 0.0, 1.0)
	var load_amount: float = clampf(float(snapshot.get("load", throttle)), 0.0, 1.0)
	var spin: float = smoothstep(25.0, 450.0 if family != "turbine" else 18000.0, accepted_rpm)
	# Running combustion depends on power, not windmilling RPM alone. Electric has no combustion idle.
	var drive: float = (0.24 + 0.76 * sqrt(ratio)) * (0.28 + 0.42 * throttle + 0.30 * load_amount)
	var level: float = 0.5 * drive * spin if running else 0.0
	if family == "electric":
		level = 0.30 * pow(ratio, 1.25) * (0.45 + 0.55 * load_amount) * spin
	elif family == "rotor":
		# Rotor inertia/autorotation remain audible with the drive in hold.
		level = 0.40 * pow(ratio, 1.5) * (0.35 + 0.65 * load_amount) * spin
	elif family == "turbine":
		level = 0.7 * (0.20 + 0.80 * pow(ratio, 1.7)) * spin if running else 0.0
		level *= db_to_linear(Model.table_db(Model.ROAR_DIRECTIVITY, Model.exhaust_angle_deg(snapshot)) * 0.45)
	var references := PackedFloat64Array()
	for layer: Dictionary in layers:
		references.append(float(layer.get("rpm", maximum * 0.65)))
	var weights: PackedFloat64Array = band_weights(maxf(_rpm, 1.0), references)
	var path_gain: float = distance_gain(source.distance_to(listener))
	level *= db_to_linear(float(profile.get("trim_db", 0.0))) * path_gain
	var scene_gain: float = clampf(mix_gain, 0.0, 1.0)
	for index: int in players.size():
		var player: AudioStreamPlayer3D = players[index]
		player.global_position = source
		var target: float = level * weights[index] * float(layers[index].get("gain", 1.0))
		levels[index] = lerpf(levels[index], target, 1.0 - exp(-dt / (0.08 if target > levels[index] else 0.12)))
		player.volume_db = linear_to_db(maxf(levels[index] * scene_gain, 0.00001)) - BUS_TRIM_DB
		var pitch: float = clampf(_rpm / references[index], 0.35, 2.5) * clampf(doppler, 0.65, 1.5)
		player.pitch_scale = lerpf(player.pitch_scale, pitch, 1.0 - exp(-dt / 0.035)) if _started else pitch
		if not _started:
			player.play(float(index) * 0.173)
		player.stream_paused = paused and mix_gain <= 0.001
	_started = true
	last_targets = {rpm = _rpm, accepted_rpm = accepted_rpm, running = running, family = family,
		weights = weights, level = level, distance_gain = path_gain, paused = paused}


func rebind(bus: StringName) -> void:
	_bus = bus
	for player: AudioStreamPlayer3D in players:
		player.bus = bus
	reset_observer()


func reset_observer() -> void:
	_primed = false
	_started = false
	_rpm = 0.0
	levels.fill(0.0)
	for player: AudioStreamPlayer3D in players:
		player.stop()
		player.volume_db = -100.0


func _exit_tree() -> void:
	reset_observer()
