## TRA-10: F4U Corsair deck-to-air sequence for capture_flight.gd (--shot=corsair-deck --start=runway).
## Uses only the production actions a pilot has (wing fold [O], canopy [U], flaps [F], gear [G]) and ordinary stick
## and throttle commands; the wing fold, canopy and flap/gear motion are the game's own. The camera is presentation:
## a low orbit around the parked aircraft that becomes an orbiting chase through the takeoff.
extends "flight_director.gd"

const SPREAD_AT_S := 9.5
const TAKEOFF_FLAPS := 1.0 / 3.0 # 10 of the model's 30 degrees (its manual advises 0; requested for the sequence)
const ROTATE_MPS := 17.0
const CLIMB_PITCH_RAD := 0.14
var events: Array[Dictionary] = []
var _fired := {}
var _heading0 := NAN
var _liftoff_s := NAN
var _gear_up_s := NAN


func _physics_process(delta: float) -> void:
	if main != null and main.session != null and main.session.crash.is_empty() and not main.session.sim.paused:
		_run_schedule(float(main.session.sim.tick) * main.session.sim.dt())
	super(delta)


func _run_schedule(t: float) -> void:
	_once("fold", t >= 0.3, func() -> bool: main._toggle_wing_fold(); return main._wing_fold_target > 0.5)
	_once("canopy_open", t >= 1.0, func() -> bool: main._toggle_mechanism("canopy"); return true)
	_once("flaps_full", t >= 4.0, func() -> bool: return main._request_flaps_amount(1.0))
	_once("spread", t >= SPREAD_AT_S, func() -> bool: main._toggle_wing_fold(); return main._wing_fold_target < 0.5)
	_once("canopy_close", t >= 15.5, func() -> bool: main._toggle_mechanism("canopy"); return true)
	_once("flaps_takeoff", t >= 17.8, func() -> bool: return main._request_flaps_amount(TAKEOFF_FLAPS))
	if is_nan(_liftoff_s) and t > 18.0 and not _on_wheels():
		_liftoff_s = t
		events.append({event = "liftoff", time_s = t})
		print("DECK_EVENT liftoff t=%.3f" % t)
	# Gear up once clear of the runway: the weight-on-wheels interlock refuses it after a touch-and-bounce, so retry
	# every tick while airborne until the production request is accepted; flaps come up after the gear cycle (2.5 s).
	if not is_nan(_liftoff_s) and not _fired.has("gear_up") and t >= _liftoff_s + 0.8 and not _on_wheels():
		# The explicit request, not the [G] toggle: gear_state() reads the solver's aux one tick late, so a toggle retry
		# would cycle the gear back down.
		main.session.input_enabled = true
		var accepted: bool = main.session.set_gear_down(false)
		main.session.input_enabled = false
		if accepted:
			_fired["gear_up"] = true
			_gear_up_s = t
			events.append({event = "gear_up", time_s = t, accepted = true})
			print("DECK_EVENT gear_up t=%.3f accepted=true" % t)
	if not is_nan(_gear_up_s):
		_once("flaps_up", t >= _gear_up_s + 2.6, func() -> bool: return main._request_flaps_amount(0.0))


func _once(key: String, due: bool, action: Callable) -> void:
	if not due or _fired.has(key):
		return
	_fired[key] = true
	# Production requests admit only pilot input; the director disables live devices, so admit for this call only.
	main.session.input_enabled = true
	var accepted: bool = bool(action.call())
	main.session.input_enabled = false
	var t: float = float(main.session.sim.tick) * main.session.sim.dt()
	events.append({event = key, time_s = t, accepted = accepted, note = str(main._note)})
	print("DECK_EVENT %s t=%.3f accepted=%s note=%s" % [key, t, accepted, main._note])


func _on_wheels() -> bool:
	for compression: float in main.session.gear_compressions(main.session.sim.state):
		if compression > 0.0:
			return true
	return false


func _commands_at(t: float) -> Dictionary:
	var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	if t < 18.0 or _last_state.size() < RB.ATT + 4:
		return c # Parked at idle; the wing-fold interlock also holds idle until spread and locked.
	c.throttle = clampf((t - 18.0) / 1.0, 0.0, 1.0)
	var w: float = _last_state[RB.ATT]
	var x: float = _last_state[RB.ATT + 1]
	var y: float = _last_state[RB.ATT + 2]
	var z: float = _last_state[RB.ATT + 3]
	var heading: float = atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
	if is_nan(_heading0):
		_heading0 = heading
	var speed: float = Vector3(_last_state[RB.VEL], _last_state[RB.VEL + 1], _last_state[RB.VEL + 2]).length()
	var pitch_target: float = 0.0 if speed < ROTATE_MPS and is_nan(_liftoff_s) else CLIMB_PITCH_RAD
	c = _corsair_run_up(c, pitch_target)
	# Directional hold on the roll: rudder against heading drift (torque and P-factor), eased off once airborne.
	c.yaw = clampf(-2.5 * wrapf(heading - _heading0, -PI, PI), -0.7, 0.7) * (1.0 if is_nan(_liftoff_s) else 0.4)
	return c


func _place_camera(t: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var center: Vector3 = aircraft.global_position
	var forward: Vector3 = -aircraft.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP)
	var angle_deg: float
	var radius: float
	var height: float
	if t < 18.0:
		# Parked: a slow low orbit from the front-left quarter round the nose to the right and tail.
		var p: float = smoothstep(0.0, 18.0, t)
		angle_deg = -40.0 + 200.0 * p
		radius = lerpf(6.5, 5.2, p)
		height = lerpf(0.6, 1.1, p)
	else:
		# Takeoff: keep orbiting behind the tail to the left side, where the gear and flaps read in profile.
		var q: float = smoothstep(18.0, 30.0, t)
		angle_deg = 160.0 + 120.0 * q
		radius = lerpf(5.2, 9.0, q)
		height = lerpf(1.1, 2.0, q)
	var angle: float = deg_to_rad(angle_deg) # 0 = ahead of the nose, positive toward the right wing.
	main._camera.global_position = center + (forward * cos(angle) + right * sin(angle)) * radius + Vector3.UP * height
	main._camera.look_at(center + Vector3.UP * 0.35, Vector3.UP)
	main._camera.fov = 36.0
