## Body-following manual gimbal. An accepted session tick drives the joints;
## render interpolation samples the last two joint positions without advancing them.
extends RefCounted

## Per-axis rate of the simulated look servos, in degrees per accepted second.
const RATE_DEG_S := 90.0

var limits_deg: Vector2
var _requested_deg := Vector2.ZERO
var _input_dirty := false
var _eligible_tick := -1
var _eligible_deg := Vector2.ZERO
var _target_deg := Vector2.ZERO
var _yaw_deg := 0.0
var _pitch_deg := 0.0
var _prev_yaw := 0.0
var _prev_pitch := 0.0
var _tick := -1
var _time_s := 0.0


func _init(travel: Vector2) -> void:
	limits_deg = travel


static func valid_limits(travel: Vector2) -> bool:
	return travel.is_finite() and travel.x >= 0.0 and travel.x <= 180.0 and travel.y >= 0.0 and travel.y <= 90.0


func aim_by(delta_deg: Vector2) -> void:
	if delta_deg.is_finite():
		_requested_deg = (_requested_deg + delta_deg).clamp(-limits_deg, limits_deg)
		_input_dirty = true


func recenter() -> void:
	_requested_deg = Vector2.ZERO
	_input_dirty = true


## The frame owner stamps input after the current batch of fixed steps. More
## events before the same next tick replace this one slot in arrival order.
func seal_input_after(accepted_tick: int) -> void:
	if _input_dirty and accepted_tick >= 0 and accepted_tick >= _tick:
		_eligible_tick = accepted_tick + 1
		_eligible_deg = _requested_deg
		_input_dirty = false


## Release outstanding motion on focus loss/menu entry. Keep the attained aim.
func hold() -> void:
	_target_deg = Vector2(_yaw_deg, _pitch_deg)
	_requested_deg = _target_deg
	_input_dirty = false
	_eligible_tick = -1
	_prev_yaw = _yaw_deg
	_prev_pitch = _pitch_deg


func reset() -> void:
	_tick = -1
	_yaw_deg = 0.0
	_pitch_deg = 0.0
	hold()


## Called once per accepted tick. A repeated or stale publication cannot drive
## the joints twice. After a gap, seed the new endpoint and discard queued aim
## rather than applying a recent mouse event across missing observations.
func accept(tick: int, time_s: float, step_s: float) -> void:
	if tick < 1 or tick <= _tick or not is_finite(time_s) or not is_finite(step_s) or time_s < 0.0 or step_s <= 0.0:
		return
	if (_tick >= 0 and (tick != _tick + 1 or not is_equal_approx(time_s - _time_s, step_s))) \
			or (_eligible_tick >= 0 and tick > _eligible_tick):
		hold()
	else:
		if tick == _eligible_tick:
			_target_deg = _eligible_deg
			_eligible_tick = -1
		_prev_yaw = _yaw_deg
		_prev_pitch = _pitch_deg
		_yaw_deg = move_toward(_yaw_deg, _target_deg.x, RATE_DEG_S * step_s)
		_pitch_deg = move_toward(_pitch_deg, _target_deg.y, RATE_DEG_S * step_s)
	_tick = tick
	_time_s = time_s


## Positive yaw looks right, positive pitch looks up. Pitch follows the yawed
## mount's local right axis, including through a bank or an inverted body.
func orientation(fraction: float) -> Basis:
	var t := clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 1.0
	var yaw := lerpf(_prev_yaw, _yaw_deg, t)
	var pitch := lerpf(_prev_pitch, _pitch_deg, t)
	return Basis(Vector3.DOWN, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
