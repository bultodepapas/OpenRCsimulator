# One flight of one aircraft: its data, the trimmed start, the pilot's commands, the fixed-step simulation, reset.
# 64-bit floats only (guarded). Pilot commands are sampled once per PHYSICS TICK, before the simulation steps
# (process_physics_priority), so a flight depends only on the per-tick input samples, never on the frame rate.
# Input device: the radio/joystick while one is connected (positions, unshaped, armed throttle), else the keyboard
# (virtual stick: rate-limited, self-centering). Unplugging the radio triggers the failsafe: idle, sticks centred,
# visible pause; resuming is an explicit action (resume()).
extends Node

const Commands := preload("res://input/commands.gd")
const Keyboard := preload("res://input/keyboard.gd")
const RcInput := preload("res://input/rc_input.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const Sim := preload("res://sim/simulation.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const RB := preload("res://physics/rigid_body.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")

## Emitted at the start of reset(), before the simulation restarts (recorders close their file here).
signal resetting

## Auxiliary simulation state (advanced once per tick in _pre_step): engine rpm, then the servos' actual positions
## (roll, pitch, yaw in command units, −1…1 of each surface's throw, trims included).
const AUX_RPM := 0
const AUX_SERVO := 1

## The fixed-step simulation: a child node, stepped after this node on every tick.
var sim: Node
var aircraft := {} # AircraftData result: { ok, errors, warnings, model }
var start := {} # trimmed starting condition (Trim result); empty without valid data
## Trims in pilot units (−1…1), like radio trim tabs: solved at the start, added to the sticks.
var trims := { roll = 0.0, pitch = 0.0, yaw = 0.0 }
## Stick commands after shaping (−1…1, throttle 0…1), and the raw input sample they came from.
var commands := Commands.neutral_commands()
var raw := Commands.neutral_raw()
## read_raw() -> { roll, pitch, yaw, throttle }: the keyboard, sampled once per physics tick.
var read_raw: Callable = func() -> Dictionary: return Keyboard.read_raw()
## The radio (or joystick): flies instead of the keyboard while connected.
var radio := RcInput.new()
## read_axis(device, axis) -> float and device_info(device) -> { guid, name, vendor_id, product_id }. Replaceable in
## tests: Input.get_joy_guid on a device that does not exist prints an engine error.
var read_axis: Callable = func(device: int, axis: int) -> float: return Input.get_joy_axis(device, axis as JoyAxis)
var device_info: Callable = func(device: int) -> Dictionary:
	var info := Input.get_joy_info(device)
	return { guid = Input.get_joy_guid(device), name = Input.get_joy_name(device),
		vendor_id = info.get("vendor_id", 0), product_id = info.get("product_id", 0), known = Input.is_joy_known(device) }
## Saved radio calibrations, one per device key.
var profiles_path := "user://rc_calibration.cfg"
## The calibration wizard while it runs, else null.
var calibration: RefCounted = null
## Why the session paused the simulation ("" = it did not), for the panel.
var pause_reason := ""
## false: commands hold still (captures, headless traces).
var input_enabled := true
## false: no aircraft physics (the Stage 0/1 scripted circle). The simulation is disabled; input still shapes commands.
var physics_enabled := true


func _init() -> void:
	process_physics_priority = -1 # lower runs first: shape this tick's commands before the simulation steps


## Loads the aircraft, solves the trimmed start and creates the simulation. Call once, before adding to the tree.
func setup(path := Scenarios.AIRCRAFT) -> void:
	sim = Sim.new()
	aircraft = AircraftData.load_file(path)
	for w in aircraft.warnings:
		print("aircraft data warning: ", w)
	if aircraft.ok:
		var m: Dictionary = aircraft.model
		sim.mass = m.mass_kg
		sim.inertia = m.inertia
		sim.loads = _loads
		sim.pre_step = _pre_step
		start = Scenarios.trimmed_level_across_view(m, sim.gravity, m.controls.throw_rad)
		if start.ok:
			trims = { roll = start.roll_command, pitch = start.pitch_command, yaw = start.yaw_command }
		else:
			push_error("trim: " + start.message)
	else:
		for e in aircraft.errors:
			push_error("aircraft data: " + e)
	if not physics_enabled:
		sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_on_joy_connection_changed(pads[0], true)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		radio.on_motion(event.device, event.axis, event.axis_value)


func _on_joy_connection_changed(device: int, is_connected: bool) -> void:
	if is_connected and not radio.connected:
		var info: Dictionary = device_info.call(device)
		radio.connect_device(device, info, RcCalibration.load_profile(profiles_path, RcInput.key_for(device, info)))
		print("radio connected: %s (%s profile)" % [radio.device_key, radio.profile_source])
	elif not is_connected and radio.connected and device == radio.device_id:
		calibration = null
		radio.disconnect_device()
		_failsafe("radio disconnected")


## [K]: start the radio calibration wizard. The simulation pauses and the engine idles until it is done.
func start_calibration() -> bool:
	if not radio.connected:
		return false
	calibration = RcCalibration.new()
	_failsafe("calibrating radio")
	return true


## [Enter]: next calibration step. When the wizard finishes, the profile is used and saved for this device.
func advance_calibration() -> void:
	if calibration == null:
		return
	if calibration.advance(radio.axes):
		radio.use_profile(calibration.profile, "calibrated")
		var err := RcCalibration.save_profile(profiles_path, radio.device_key, calibration.profile)
		calibration = null
		pause_reason = "radio calibrated%s" % ("" if err == OK else ", NOT saved (error %d)" % err)
		print(pause_reason, ": ", radio.device_key)


## [Esc]: abandon the wizard; the previous profile stays.
func cancel_calibration() -> void:
	if calibration != null:
		calibration = null
		pause_reason = "calibration cancelled"


## Engine to idle, sticks centred (trims stay, like a hands-off airplane), simulation paused until resume().
func _failsafe(reason: String) -> void:
	commands = Commands.neutral_commands()
	commands.throttle = 0.0
	raw = Commands.neutral_raw()
	sim.inputs = _inputs()
	sim.set_paused(true)
	pause_reason = reason
	print("failsafe: ", reason)


## The pilot's explicit "continue" (never automatic).
func resume() -> void:
	pause_reason = ""
	sim.set_paused(false)


func _physics_process(_delta: float) -> void:
	if input_enabled:
		if radio.connected and calibration != null:
			radio.poll(read_axis, sim.dt())
			calibration.sample(radio.axes)
		elif radio.connected:
			radio.poll(read_axis, sim.dt())
			commands = radio.sticks()
			raw = commands.duplicate()
			raw.throttle = radio.throttle_position() # the stick, even while the throttle is held at idle
		else:
			raw = read_raw.call()
			commands = Commands.step_commands(commands, raw, sim.dt())
		sim.inputs = _inputs()
	# Temporary ground until crash detection (ROADMAP D9d): below the ground, start over.
	if physics_enabled and not sim.paused and sim.state.size() == RB.SIZE and sim.state[RB.POS + 2] > 0.0:
		reset()


func reset() -> void:
	resetting.emit()
	commands = Commands.neutral_commands()
	if start.get("ok", false):
		commands.throttle = start.throttle
	# Inputs first: synchronous paths (capture, --trace) never tick this node, so they must start trimmed too.
	sim.inputs = _inputs()
	# Engine at its trimmed rpm and servos already at the trimmed surface positions.
	sim.aux = PackedFloat64Array([start.get("rpm", 0.0), sim.inputs[0], sim.inputs[1], sim.inputs[2]])
	sim.reset(start.state if start.get("ok", false) else Scenarios.throw_across_view())
	# Never fly on invalid aircraft data: stay paused and show why.
	sim.set_paused(not aircraft.ok)


## Stick commands plus trims: what the surfaces actually do (and what the physics sees).
func flown_commands() -> Dictionary:
	var c := commands.duplicate()
	c.roll = clampf(c.roll + trims.roll, -1.0, 1.0)
	c.pitch = clampf(c.pitch + trims.pitch, -1.0, 1.0)
	c.yaw = clampf(c.yaw + trims.yaw, -1.0, 1.0)
	return c


## The surfaces' actual positions (servo outputs) as commands { roll, pitch, yaw, throttle }: what the airplane flies
## with and what the renderer should draw. Without physics (scripted mode): the flown commands.
func surfaces() -> Dictionary:
	if not physics_enabled or not aircraft.get("ok", false):
		return flown_commands()
	var a: PackedFloat64Array = sim.aux
	return { roll = a[AUX_SERVO], pitch = a[AUX_SERVO + 1], yaw = a[AUX_SERVO + 2], throttle = sim.inputs[3] }


## Maximum surface throws in degrees from the loaded aircraft ({} without valid data: Commands' default).
func throws_deg() -> Dictionary:
	return aircraft.model.controls.throw_deg if aircraft.get("ok", false) else {}


func _inputs() -> PackedFloat64Array:
	var f := flown_commands()
	return PackedFloat64Array([f.roll, f.pitch, f.yaw, f.throttle])


## Simulation loads: aerodynamics (D3) + propulsion (D5) from the servos' actual positions, in calm air.
func _loads(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	var a: PackedFloat64Array = sim.aux
	var surfaces := Commands.surface_deflections_deg({ roll = a[AUX_SERVO], pitch = a[AUX_SERVO + 1], yaw = a[AUX_SERVO + 2] }, throws_deg())
	var air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]))
	var l := Aero.loads(s, air, Aero.deflections_from_surfaces(surfaces), aircraft.model, Air.RHO_SEA_LEVEL)
	var p := Propulsion.loads(air.v_air, a[AUX_RPM], aircraft.model.propulsion, Air.RHO_SEA_LEVEL)
	for k in 6:
		l[k] += p[k]
	return l


## Once per physics tick, before integration (deterministic): engine rpm follows the throttle with its lag (D5);
## each servo slews toward its command at the servo's rate (D6c), a full throw in servo_full_throw_time.
func _pre_step(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([Propulsion.rpm_step(aux[AUX_RPM], inputs[3], dt, aircraft.model.propulsion), 0.0, 0.0, 0.0])
	var rate: float = aircraft.model.controls.servo_rate
	for k in 3:
		out[AUX_SERVO + k] = Commands.rate_limit(aux[AUX_SERVO + k], inputs[k], rate, dt)
	return out


## Header lines for a flight trace of this session.
func trace_meta() -> Dictionary:
	return {
		scenario = "trimmed level flight across view at 15 m/s (D5: engine, six-axis trim, calm air)",
		aircraft = "%s (%s)" % [aircraft.model.get("id", "?"), Scenarios.AIRCRAFT],
		created_utc = Time.get_datetime_string_from_system(true),
		engine = "Godot " + Engine.get_version_info().string,
		dt_s = sim.dt(),
		mass_kg = sim.mass,
		inertia_kgm2 = "Jxx Jyy Jzz Jxy Jxz Jyz = %s" % " ".join(Array(sim.inertia).map(func(v): return str(v))),
		gravity_mps2 = sim.gravity,
		frames = "world NED (north, east, down); body FRD (forward, right, down); quaternion body->NED [w,x,y,z]",
		loads = "Fx..Mz are body-axis loads at the start of each step, excluding gravity",
	}
