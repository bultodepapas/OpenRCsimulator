extends RefCounted
class_name WindsockAudio

## Bounded presentation controller for a recorded windsock-fabric loop.
## The caller supplies accepted wind and visual state; this class owns no clock,
## RNG, callbacks, or simulation state.

const MIN_WIND_MPS: float = 1.2
const FULL_WIND_MPS: float = 12.0
const MAX_LINEAR_LEVEL: float = 0.22
const FULL_INFLATION_REDUCTION: float = 0.12
const LEVEL_TIME_CONSTANT_S: float = 0.15
const LEVEL_FLOOR: float = 0.0001

var player: AudioStreamPlayer3D
var _anchor: Vector3 = Vector3.ZERO
var _smoothed_level: float = 0.0
var _pending_start: bool = true
var _configured: bool = false


## Configure the spatial player without starting playback. `guarded_source` must
## already contain the caller's chosen loop metadata and wrap guard.
func configure(
		owner: Node3D,
		bus: StringName,
		guarded_source: AudioStreamWAV,
		anchor: Vector3) -> bool:
	if owner == null or not is_instance_valid(owner) or guarded_source == null \
			or not _finite_vector(anchor) or AudioServer.get_bus_index(bus) < 0:
		return false
	if player != null and is_instance_valid(player):
		stop()
		player.queue_free()
	_anchor = anchor
	_smoothed_level = 0.0
	_pending_start = true
	_configured = true
	player = AudioStreamPlayer3D.new()
	player.name = "WindsockFabric"
	player.stream = guarded_source
	player.bus = bus
	player.unit_size = 2.0
	player.max_distance = 55.0
	player.panning_strength = 0.75
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.max_db = 0.0
	player.volume_db = -80.0
	player.stream_paused = false
	owner.add_child(player)
	player.global_position = anchor
	return true


## Update from detached presentation values. Wind gates a quiet fabric level;
## loose fabric is slightly louder than a taut, fully inflated sock.
func update(snapshot: Dictionary, delta: float, mix_gain: float) -> void:
	if not _configured or player == null or not is_instance_valid(player):
		return
	var source: Variant = snapshot.get("fabric_source", _anchor)
	player.global_position = source if _finite_vector(source) else _anchor
	var wind_speed: float = _finite_or_zero(snapshot.get("wind_speed", 0.0))
	var inflation: float = clampf(_finite_or_zero(snapshot.get("windsock_inflation", 0.0)), 0.0, 1.0)
	var level_gain: float = clampf(_finite_or_zero(mix_gain), 0.0, 1.0)
	var dt: float = clampf(_finite_or_zero(delta), 0.0, 0.1)
	var wind_gate: float = smoothstep(MIN_WIND_MPS, FULL_WIND_MPS, maxf(wind_speed, 0.0))
	var slack_gain: float = 1.0 - FULL_INFLATION_REDUCTION * inflation
	var target_level: float = MAX_LINEAR_LEVEL * wind_gate * slack_gain
	if dt > 0.0:
		_smoothed_level = lerpf(_smoothed_level, target_level, 1.0 - exp(-dt / LEVEL_TIME_CONSTANT_S))
	var output_level: float = _smoothed_level * level_gain
	player.volume_db = linear_to_db(maxf(output_level, LEVEL_FLOOR))
	if level_gain <= 0.0:
		# Soundscape owns the envelope. Suspend only after its shared gain reaches zero.
		player.stream_paused = true
		return
	player.stream_paused = false
	if output_level > LEVEL_FLOOR and (_pending_start or not player.playing):
		player.play()
		_pending_start = false


## Stop the stream and make the next active update a fresh start.
func reset() -> void:
	stop()


## Stop before the environment bus is removed or the soundscape is detached.
func stop() -> void:
	_smoothed_level = 0.0
	_pending_start = true
	if player != null and is_instance_valid(player):
		player.stop()
		player.stream_paused = false
		player.volume_db = -80.0


## Move the player to a rebuilt scene-local bus and restart from silence.
func rebind(bus: StringName) -> bool:
	if player == null or not is_instance_valid(player) or AudioServer.get_bus_index(bus) < 0:
		return false
	stop()
	player.bus = bus
	return true


static func _finite_vector(value: Variant) -> bool:
	if not value is Vector3:
		return false
	var vector: Vector3 = value
	return is_finite(vector.x) and is_finite(vector.y) and is_finite(vector.z)


static func _finite_or_zero(value: Variant) -> float:
	var result: float = float(value)
	return result if is_finite(result) else 0.0
