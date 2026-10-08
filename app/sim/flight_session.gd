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
const M := preload("res://physics/math3d.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const GroundStart := preload("res://physics/ground_start.gd")
const Turbine := preload("res://physics/turbine.gd")
const WashTransport := preload("res://physics/wash_transport.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Ground := preload("res://physics/ground_contact.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")

## Emitted at the start of reset(), before the simulation restarts (recorders close their file here).
signal resetting

## Auxiliary simulation state (advanced once per tick in _pre_step): engine rpm, then the servos' actual positions
## (roll, pitch, yaw in command units, −1…1 of each surface's throw, trims included).
const AUX_RPM := 0
const AUX_SERVO := 1
const AUX_LAYOUT := ["engine_rpm", "srv_roll", "srv_pitch", "srv_yaw"]
## E3b1: with stiction data the per-wheel anchors follow AUX_LAYOUT ([north, east, stuck] per contact, gear order).
## AUX_LAYOUT stays the trace's four auxiliary columns.
const AUX_ANCHORS := 4
## E0a2b: with a tail downwash lag the lagged wing CL follows the anchors (downwash_index()).

## The fixed-step simulation: a child node, stepped after this node on every tick.
var sim: Node
## The aircraft data file ([F5] reloads it).
var aircraft_path := Scenarios.AIRCRAFT
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
## false: the engine is stopped (dead stick: no thrust, no torque, rpm 0) until restarted. A power-off glide start
## stops it; every other start runs it. (Starting and stopping in flight: ROADMAP G2.)
var engine_running: bool:
	get:
		return true if sim == null else sim.modes[0] == 1
	set(value):
		if sim != null:
			sim.modes[0] = 1 if value else 0
## After a crash the scene freezes this long (s, counted in physics ticks), showing the impact, then restarts.
const CRASH_HOLD_S := 1.5
## The last crash while it is shown: { speed, sink (m/s), ticks_left }; empty when flying.
var crash := {}
## Why the session paused the simulation ("" = it did not), for the panel.
var pause_reason := ""
## false: commands hold still (captures, headless traces).
var input_enabled := true
## Holds by name (UI-02: "menu"). While any is set the session is frozen: no input sampling, no crash countdown,
## the simulation paused. Releasing the last hold does not resume: continuing stays the pilot's explicit resume().
var holds := {}
## E3a: the field's surfaces as a flat table for the tyre forces (set_field); empty = dry pavement everywhere.
var ground_surfaces := PackedFloat64Array()
## H2: last deflections built by _deflections() and the servo positions they belong to (cleared with each aircraft).
var _deflection_key := PackedFloat64Array()
var _deflection_cache := {}
## The field id the surfaces came from ("" = none: pavement), and why they could not be built ("" = fine).
var ground_field_id := ""
var surface_error := ""
## false: no aircraft physics (the Stage 0/1 scripted circle). The simulation is disabled; input still shapes commands.
var physics_enabled := true


func _init() -> void:
	process_physics_priority = -1 # lower runs first: shape this tick's commands before the simulation steps


## Loads the aircraft, solves the trimmed start and creates the simulation. Call once, before adding to the tree.
func setup(path := Scenarios.AIRCRAFT) -> void:
	aircraft_path = path
	sim = Sim.new()
	sim.modes = PackedInt64Array([1])
	sim.faulted.connect(_on_sim_faulted)
	var prepared := _prepare_aircraft(AircraftData.load_file(path))
	if prepared.ok:
		_commit_aircraft(prepared)
	else:
		_set_initial_failure(prepared)
	if not physics_enabled:
		sim.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(sim)
	reset()


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


## Freezes the session for `reason` (a menu): inputs, crash countdown and simulation all stop where they are.
func hold(reason: String) -> void:
	holds[reason] = true
	sim.set_paused(true)


## Lifts one hold. The flight stays paused until resume() (or the crash hold ends and restarts it).
func release(reason: String) -> void:
	holds.erase(reason)


## E3a: the wheels roll on this field's surfaces (a validated FieldLoader field). Invalid surface data refuses the
## flight (like invalid aircraft data). Returns false on failure; call reset() afterwards to restart on them.
func set_field(field: Dictionary, table_path := GroundSurfaces.DEFAULT_PATH) -> bool:
	var table := GroundSurfaces.load_table(table_path)
	var built := GroundSurfaces.build(table.table, field) if table.ok else table
	if not built.ok:
		surface_error = "ground surfaces invalid: " + str(built.errors[0] if not built.errors.is_empty() else "unknown")
		ground_surfaces = PackedFloat64Array()
		pause_reason = surface_error
		sim.set_paused(true)
		printerr(surface_error)
		return false
	surface_error = ""
	ground_surfaces = built.rects
	ground_field_id = str(field.get("id", "?"))
	return true


## Whether this flight can fly at all: valid aircraft and start, no simulation fault (menus disable Continue).
func is_flyable() -> bool:
	return _flight_ready()


## Whether resume() would fly now: flyable, not held, not showing a crash.
func can_resume() -> bool:
	return holds.is_empty() and crash.is_empty() and _flight_ready()


## The pilot's explicit "continue" (never automatic). Refused while a menu holds the session or a crash is shown
## (the crash restarts by itself; flying on would pass through the ground).
func resume() -> void:
	if not holds.is_empty() or not crash.is_empty():
		return
	if not _has_valid_start():
		sim.set_paused(true)
		if pause_reason.is_empty():
			pause_reason = _start_failure_reason()
		return
	if not sim.fault_reason.is_empty():
		sim.set_paused(true)
		pause_reason = "simulation fault: " + sim.fault_reason
		return
	pause_reason = ""
	sim.set_paused(false)


## Prepares the complete aircraft/trim candidate without changing the active flight.
func _prepare_aircraft(data: Dictionary) -> Dictionary:
	var neutral_trims := { roll = 0.0, pitch = 0.0, yaw = 0.0 }
	if not data.get("ok", false):
		var error_text := "aircraft data invalid"
		if not data.get("errors", []).is_empty():
			error_text += ": " + str(data.errors[0])
		return { ok = false, data = data, start = { ok = false, message = error_text }, trims = neutral_trims, message = error_text }
	var model: Dictionary = data.get("model", {})
	if not _model_is_valid(model):
		var invalid_model := "aircraft model has invalid mass properties or control throws"
		return { ok = false, data = data, start = { ok = false, message = invalid_model }, trims = neutral_trims, message = invalid_model }
	# Each aircraft declares its own start speed (the Stik's 15 m/s is the loader's default).
	var candidate_start := Scenarios.trimmed_level_across_view(model, sim.gravity, model.controls.throw_rad, model.get("start_speed", 15.0))
	if not candidate_start.get("ok", false):
		var trim_error := "trim: " + str(candidate_start.get("message", "trim failed"))
		return { ok = false, data = data, start = candidate_start, trims = neutral_trims, message = trim_error }
	if not Sim.state_is_valid(candidate_start.state):
		var invalid_state := "trim produced a nonfinite or malformed starting state"
		return { ok = false, data = data, start = { ok = false, message = invalid_state }, trims = neutral_trims, message = invalid_state }
	var candidate_trims := {
		roll = float(candidate_start.roll_command),
		pitch = float(candidate_start.pitch_command),
		yaw = float(candidate_start.get("yaw_command", 0.0)),
	}
	for value in [candidate_start.get("throttle", NAN), candidate_start.get("rpm", NAN), candidate_trims.roll, candidate_trims.pitch, candidate_trims.yaw]:
		if not is_finite(value):
			var nonfinite_trim := "trim produced a nonfinite throttle, rpm, or control trim"
			return { ok = false, data = data, start = { ok = false, message = nonfinite_trim }, trims = neutral_trims, message = nonfinite_trim }
	if not _candidate_loads_are_valid(model, candidate_start, candidate_trims):
		var bad_loads := "trimmed aircraft produces nonfinite or malformed initial loads"
		return { ok = false, data = data, start = { ok = false, message = bad_loads }, trims = neutral_trims, message = bad_loads }
	return { ok = true, data = data, start = candidate_start, trims = candidate_trims, message = "prepared" }


## Compatibility helper for in-memory callers. Invalid candidates leave the active flight untouched.
func _apply(data: Dictionary) -> bool:
	var prepared := _prepare_aircraft(data)
	if not prepared.ok:
		return false
	_commit_aircraft(prepared)
	return true


func _commit_aircraft(prepared: Dictionary) -> void:
	aircraft = prepared.data
	start = prepared.start
	trims = prepared.trims.duplicate(true)
	sim.mass = aircraft.model.mass_kg
	sim.inertia = aircraft.model.inertia.duplicate()
	_deflection_key = PackedFloat64Array()
	sim.loads = _loads
	sim.continuous_loads = _wash_loads
	sim.continuous_derivative = _wash_derivative
	sim.pre_step = _pre_step
	sim.rotor_momentum = rotor_momentum
	for warning in aircraft.warnings:
		print("aircraft data warning: ", warning)


func _set_initial_failure(prepared: Dictionary) -> void:
	aircraft = prepared.get("data", {})
	start = prepared.get("start", { ok = false, message = prepared.get("message", "aircraft unavailable") })
	trims = prepared.get("trims", { roll = 0.0, pitch = 0.0, yaw = 0.0 }).duplicate(true)
	engine_running = false
	pause_reason = str(prepared.get("message", "aircraft unavailable"))
	printerr(pause_reason)


func _model_is_valid(model: Dictionary) -> bool:
	if not model.has("mass_kg") or not is_finite(float(model.mass_kg)) or model.mass_kg <= 0.0:
		return false
	var inertia: PackedFloat64Array = model.get("inertia", PackedFloat64Array())
	if inertia.size() != 6:
		return false
	for value in inertia:
		if not is_finite(value):
			return false
	var minor2 := inertia[0] * inertia[1] - inertia[3] * inertia[3]
	var determinant := inertia[0] * (inertia[1] * inertia[2] - inertia[5] * inertia[5]) \
		- inertia[3] * (inertia[3] * inertia[2] - inertia[4] * inertia[5]) \
		+ inertia[4] * (inertia[3] * inertia[5] - inertia[4] * inertia[1])
	if inertia[0] <= 0.0 or minor2 <= 0.0 or determinant <= 0.0 \
			or not is_finite(minor2) or not is_finite(determinant):
		return false
	var controls: Dictionary = model.get("controls", {})
	var throws: Dictionary = controls.get("throw_rad", {})
	for axis in ["aileron", "elevator", "rudder"]:
		if not throws.has(axis) or not is_finite(float(throws[axis])) or throws[axis] <= 0.0:
			return false
	return true


func _candidate_loads_are_valid(model: Dictionary, candidate_start: Dictionary, candidate_trims: Dictionary) -> bool:
	var f := Commands.neutral_commands()
	f.roll = candidate_trims.roll
	f.pitch = candidate_trims.pitch
	f.yaw = candidate_trims.yaw
	f.throttle = candidate_start.throttle
	var surfaces := Commands.surface_deflections_deg(f, model.controls.throw_deg)
	var deflections := Aero.deflections_from_surfaces(surfaces)
	var wind := PackedFloat64Array([0.0, 0.0, 0.0])
	var result: PackedFloat64Array = Dynamics.loads(candidate_start.state, model, deflections,
		candidate_start.rpm, Air.RHO_SEA_LEVEL, wind)
	if result.size() != 6:
		return false
	for value in result:
		if not is_finite(value):
			return false
	var rotor := Dynamics.rotor_momentum(model, candidate_start.rpm)
	for value in rotor:
		if not is_finite(value):
			return false
	return true


func _start_failure_reason() -> String:
	if not surface_error.is_empty():
		return surface_error
	if not aircraft.get("ok", false):
		return "aircraft data is invalid"
	return "trimmed starting condition is invalid: " + str(start.get("message", "no valid trim"))


func _on_sim_faulted(reason: String) -> void:
	pause_reason = "simulation fault: " + reason


## Re-trims at another condition ("level" at `speed`, or "glide" power-off) and makes it the start. For scripted
## maneuvers (tests, golden flights). Returns the Trim result.
func trim_at(speed: float, mode := "level") -> Dictionary:
	var m: Dictionary = aircraft.model
	var t := Scenarios.trimmed_level_across_view(m, sim.gravity, m.controls.throw_rad, speed) if mode == "level" \
		else Scenarios.trimmed_glide_across_view(m, sim.gravity, m.controls.throw_rad, speed)
	if t.ok:
		start = t
		trims = { roll = t.roll_command, pitch = t.pitch_command, yaw = t.get("yaw_command", 0.0) }
	return t


## Moves the trimmed start to another altitude (m above ground), same trim. For captures and scripted checks.
func set_start_altitude(altitude: float) -> void:
	if start.get("ok", false) and is_finite(altitude) and Sim.state_is_valid(start.state):
		var s: PackedFloat64Array = start.state
		s[RB.POS + 2] = -altitude
		start.state = s


## [F5] Reloads the aircraft data file, re-trims and restarts: tune a coefficient without restarting the app.
## Invalid data keeps the current aircraft flying. Returns a message for the panel.
func reload() -> String:
	var prepared := _prepare_aircraft(AircraftData.load_file(aircraft_path))
	if not prepared.ok:
		return "reload failed; previous aircraft and flight retained: %s" % prepared.message
	var old_flight := { data = aircraft, start = start, trims = trims.duplicate(true) }
	var old_snapshot: Dictionary = sim.checkpoint()
	var old_commands := commands.duplicate(true)
	var old_raw := raw.duplicate(true)
	var old_crash := crash.duplicate(true)
	var old_reason := pause_reason
	var old_paused: bool = sim.paused
	_commit_aircraft(prepared)
	reset()
	if not sim.fault_reason.is_empty():
		var reason: String = sim.fault_reason
		if old_snapshot.is_empty():
			return "aircraft reload failed during reset; simulation paused: %s" % reason
		_commit_aircraft(old_flight)
		if not old_snapshot.is_empty() and sim.restore_checkpoint(old_snapshot):
			commands = old_commands
			raw = old_raw
			crash = old_crash
			pause_reason = old_reason
			sim.set_paused(old_paused)
			return "reload failed; previous aircraft and flight retained: " + reason
		return "aircraft reload failed during reset; simulation paused: %s" % reason
	return "aircraft reloaded: trimmed at %.0f m/s, throttle %d %%" % [start.V, roundi(start.throttle * 100.0)]


func _physics_process(_delta: float) -> void:
	if not holds.is_empty():
		return # frozen by a menu: no sampling (navigation keys never reach the flight), no crash countdown
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
	# D9d: any crash-hull point at or below the ground is a crash. E1: the wheels are spring-damper contacts instead
	# (aircraft with a landing_gear section); a leg pushed past its travel is a crash too.
	if not crash.is_empty():
		crash.ticks_left -= 1
		if crash.ticks_left <= 0:
			reset()
		return
	if physics_enabled and not sim.paused and _flight_ready() and Sim.state_is_valid(sim.state):
		if touches_ground(sim.state):
			_crash("")
		elif gear_collapsed(sim.state):
			_crash("gear collapsed")


## True when any landing-gear contact at state `s` is compressed past its travel (E1). Always false without gear.
func gear_collapsed(s: PackedFloat64Array) -> bool:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return false
	return Ground.collapsed(s, aircraft.model.landing_gear)


## Compression of each landing-gear contact at state `s` (m, ≤ 0 in the air), in data order; empty without gear.
func gear_compressions(s: PackedFloat64Array) -> PackedFloat64Array:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return PackedFloat64Array()
	return Ground.compressions(s, aircraft.model.landing_gear)


## True when any crash-hull point of the airplane at state `s` is at or below the ground (NED down ≥ 0).
## Wheels are not hull points on aircraft with landing gear (E1): a wheel on the ground is a landing.
func touches_ground(s: PackedFloat64Array) -> bool:
	if not Sim.state_is_valid(s) or not aircraft.get("ok", false):
		return false
	var hull: PackedFloat64Array = aircraft.model.crash_hull
	var q := PackedFloat64Array([s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3]])
	for i in range(0, hull.size(), 3):
		# down component of R(q)·p: third row of the body→NED rotation matrix
		var down := 2.0 * (q[1] * q[3] - q[0] * q[2]) * hull[i] + 2.0 * (q[2] * q[3] + q[0] * q[1]) * hull[i + 1] \
			+ (1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2])) * hull[i + 2]
		if s[RB.POS + 2] + down >= 0.0:
			return true
	return false


func _crash(why: String) -> void:
	var s: PackedFloat64Array = sim.state
	var speed := M.sqrt_(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var prev: PackedFloat64Array = sim.previous
	var sink: float = (s[RB.POS + 2] - prev[RB.POS + 2]) / sim.dt()
	crash = { speed = speed, sink = sink, ticks_left = roundi(CRASH_HOLD_S / sim.dt()), why = why }
	sim.set_paused(true)
	pause_reason = "CRASH at %.1f m/s (sink %.1f m/s%s) - restarting" % [speed, sink, "" if why.is_empty() else ", " + why]
	print(pause_reason)


func reset() -> void:
	resetting.emit()
	crash = {}
	if pause_reason.begins_with("CRASH"):
		pause_reason = ""
	commands = Commands.neutral_commands()
	if _has_valid_start():
		commands.throttle = start.throttle
		engine_running = start.get("mode", "level") != "glide"
	else:
		engine_running = false
	# Inputs first: synchronous paths (capture, --trace) never tick this node, so they must start trimmed too.
	sim.inputs = _inputs()
	# Engine at its trimmed rpm and servos already at the trimmed surface positions.
	var aux := PackedFloat64Array([start.get("rpm", 0.0) if _has_valid_start() else 0.0, sim.inputs[0], sim.inputs[1], sim.inputs[2]])
	aux.resize(AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE) # E3b1: every wheel starts sliding
	if downwash_index() >= 0 and _has_valid_start():
		aux.append(_wing_cl(start.state, aux)) # E0a2b: start settled, no downwash transient
	sim.aux = aux
	if _has_valid_start():
		sim.continuous = _settled_wash(start.state, aux)
		if not sim.reset(start.state):
			sim.set_paused(true)
			return
		pause_reason = ""
		sim.set_paused(false)
	else:
		# An invalid initial candidate is parked in a valid, inert state. It never enters the throw/flying fallback.
		if not Sim.state_is_valid(sim.state):
			sim.reset(PackedFloat64Array([0.0, 0.0, -1000.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
		if pause_reason.is_empty():
			pause_reason = _start_failure_reason()
		sim.set_paused(true)
		# Trace/capture helpers may call step() directly, so the invalid initial condition must also block raw stepping.
		sim.fault_reason = pause_reason


func _has_valid_start() -> bool:
	return aircraft.get("ok", false) and start.get("ok", false) and sim != null and surface_error.is_empty()


func _flight_ready() -> bool:
	return _has_valid_start() and sim.fault_reason.is_empty()


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


## Simulation loads: aerodynamics (D3) + propulsion (D5) from the servos' actual positions, in calm air, plus the
## landing gear's ground contacts (E1) while a wheel pushes on the ground (nothing is added in the air), with tyre
## friction and the nose wheel steered by the rudder servo's actual position (E2), scaled by the surface under each
## wheel (E3a).
func _loads(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
	return _wash_loads(s, sim.continuous, t)


func _wash_loads(s: PackedFloat64Array, transported_dv: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	var prop: Dictionary = aircraft.model.propulsion
	var expected: int = prop.slipstream.pieces.size() if WashTransport.enabled(prop) else 0
	if transported_dv.size() != expected:
		return PackedFloat64Array([NAN, NAN, NAN, NAN, NAN, NAN]) # Simulation rejects before any piece indexing.
	var a: PackedFloat64Array = sim.aux
	var lag := downwash_index()
	var out := Dynamics.loads(s, aircraft.model, _deflections(a), a[AUX_RPM],
		Air.RHO_SEA_LEVEL, PackedFloat64Array([0.0, 0.0, 0.0]), a[lag] if lag >= 0 and lag < a.size() else NAN, transported_dv)
	var ground := Ground.loads(s, aircraft.model.landing_gear, a[AUX_SERVO + 2], ground_surfaces,
		a.slice(AUX_ANCHORS) if a.size() > AUX_ANCHORS else PackedFloat64Array())
	for i in ground.size():
		out[i] += ground[i]
	return out


## Continuous wash uses stage airspeed and state, with the existing sampled RPM/servo policy.
func _wash_derivative(s: PackedFloat64Array, lagged: PackedFloat64Array, _t: float) -> PackedFloat64Array:
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	return WashTransport.derivative(air.v_air, sim.aux[AUX_RPM], aircraft.model.propulsion, Air.RHO_SEA_LEVEL, lagged)


func _settled_wash(s: PackedFloat64Array, aux: PackedFloat64Array) -> PackedFloat64Array:
	if not WashTransport.enabled(aircraft.model.propulsion):
		return PackedFloat64Array()
	var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	return WashTransport.settled(air.v_air, aux[AUX_RPM], aircraft.model.propulsion, Air.RHO_SEA_LEVEL)


## Aerodynamic-convention deflections from the servos' actual positions. The servos change once per tick (in
## _pre_step), while the loads run five times per tick (H2), so the last result is reused while the positions match.
## Callers only read the dictionary.
func _deflections(a: PackedFloat64Array) -> Dictionary:
	if _deflection_key.size() == 3 and _deflection_key[0] == a[AUX_SERVO] and _deflection_key[1] == a[AUX_SERVO + 1] \
			and _deflection_key[2] == a[AUX_SERVO + 2]:
		return _deflection_cache
	var surfaces := Commands.surface_deflections_deg({ roll = a[AUX_SERVO], pitch = a[AUX_SERVO + 1], yaw = a[AUX_SERVO + 2] }, throws_deg())
	_deflection_cache = Aero.deflections_from_surfaces(surfaces)
	_deflection_key = PackedFloat64Array([a[AUX_SERVO], a[AUX_SERVO + 1], a[AUX_SERVO + 2]])
	return _deflection_cache


## Propeller angular momentum (D9c): J_p·ω along body +x (clockwise seen from behind).
func rotor_momentum(aux: PackedFloat64Array) -> PackedFloat64Array:
	return Dynamics.rotor_momentum(aircraft.model, aux[AUX_RPM])


## Once per physics tick, before integration (deterministic): engine rpm follows the throttle with its lag (D5), or
## the shaft torque balance when the aircraft declares one (P51-06);
## each servo slews toward its command at the servo's rate (D6c), a full throw in servo_full_throw_time.
func _pre_step(aux: PackedFloat64Array, inputs: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var prop: Dictionary = aircraft.model.propulsion
	var rpm := 0.0
	if engine_running and Turbine.is_turbine(prop):
		# AV-05: the turbine spools toward the ECU demand within its acceleration/deceleration schedules.
		rpm = Turbine.spool_step(aux[AUX_RPM], inputs[3], dt, prop)
	elif engine_running and Propulsion.has_shaft(prop):
		# G2 first slice (P51-06): torque balance at the current axial airspeed (calm air, as _loads).
		var s: PackedFloat64Array = sim.state
		var u := M.dot(M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]), Propulsion.axis(prop))
		rpm = Propulsion.shaft_step(aux[AUX_RPM], inputs[3], u, dt, prop, Air.RHO_SEA_LEVEL)
	elif engine_running:
		rpm = Propulsion.rpm_step(aux[AUX_RPM], inputs[3], dt, prop)
	var out := PackedFloat64Array([rpm, 0.0, 0.0, 0.0])
	var rate: float = aircraft.model.controls.servo_rate
	for k in 3:
		out[AUX_SERVO + k] = Commands.rate_limit(aux[AUX_SERVO + k], inputs[k], rate, dt)
	var lag := downwash_index()
	var anchors_end := aux.size() - (1 if lag >= 0 and lag < aux.size() else 0)
	if anchors_end > AUX_ANCHORS:
		# E3b1: stick/slip transitions from the committed state, with the steer the last tick used.
		out.append_array(Ground.anchor_step(sim.state, aircraft.model.landing_gear, aux[AUX_SERVO + 2], ground_surfaces,
			aux.slice(AUX_ANCHORS, anchors_end)))
	if lag >= 0 and lag < aux.size():
		# E0a2b: the tail's downwash follows the wing's lift l/V late. Exact first-order lag over the tick, from the
		# committed state and the servos the last tick used; held through the RK stages like rpm.
		var s: PackedFloat64Array = sim.state
		var cl_now := _wing_cl(s, aux)
		var speed: float = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL).V
		var length: float = aircraft.model.surfaces.horizontal.downwash_lag_length
		out.append(cl_now + (aux[lag] - cl_now) * M.exp_(-dt * speed / length))
	return out


## E0a2b: aux index of the lagged wing CL (after the anchors), or −1 without a tail downwash lag.
func downwash_index() -> int:
	# The lag feeds only the local (strip) model's tail: none without an envelope (a pure-oracle model).
	if not aircraft.get("ok", false) or aircraft.model.get("envelope", {}).is_empty() \
			or not aircraft.model.get("surfaces", {}).get("horizontal", {}).has("downwash_lag_length"):
		return -1
	return AUX_ANCHORS + anchor_count() * Ground.ANCHOR_STRIDE


## Replay-tolerance component of aux entry i (H9 policy): rpm, servo, anchor or downwash.
func aux_component(i: int) -> String:
	if i == AUX_RPM:
		return "rpm"
	if i < AUX_ANCHORS:
		return "servo"
	return "downwash" if i == downwash_index() else "anchor"


## The wing strips' mean section lift coefficient at state s with the servos in aux (E0a2b lag input).
func _wing_cl(s: PackedFloat64Array, aux: PackedFloat64Array) -> float:
	var air := Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
	return Aero.wing_lift_coefficient(s, air, _deflections(aux), aircraft.model)


## E3b2: restart standing on the runway at (north, east) facing `heading` (rad, 0 = north), engine idling at closed
## throttle, every wheel stuck, in static equilibrium (GroundStart.solve). Needs stiction data. On failure the flight is
## reset to its normal start and false is returned.
func reset_on_runway(north: float, east: float, heading: float) -> bool:
	reset()
	if not _has_valid_start() or anchor_count() == 0:
		return false
	commands.throttle = 0.0
	engine_running = true
	sim.inputs = _inputs()
	var prop: Dictionary = aircraft.model.propulsion
	var rpm := Propulsion.steady_rpm(0.0, 0.0, prop, Air.RHO_SEA_LEVEL)
	var aux := PackedFloat64Array([rpm, sim.inputs[0], sim.inputs[1], sim.inputs[2]])
	var solved := GroundStart.solve(aircraft.model, ground_surfaces, north, east, heading, _deflections(aux), aux[AUX_SERVO + 2],
		rpm, Air.RHO_SEA_LEVEL, sim.gravity)
	if not solved.ok:
		printerr("runway start: " + str(solved.message))
		reset()
		return false
	aux.append_array(solved.anchors)
	if downwash_index() >= 0:
		aux.append(_wing_cl(solved.state, aux)) # E0a2b: at rest, settled
	sim.aux = aux
	sim.continuous = _settled_wash(solved.state, aux)
	if not sim.reset(solved.state):
		reset()
		return false
	return true


## E3b1: wheels with a stiction anchor (0 when the gear has no breakaway_factor).
func anchor_count() -> int:
	var gear: Dictionary = aircraft.get("model", {}).get("landing_gear", {}) if aircraft.get("ok", false) else {}
	return gear.contacts.size() if gear.has("breakaway_factor") else 0


## Header lines for a flight trace of this session.
func trace_meta() -> Dictionary:
	var model: Dictionary = aircraft.model
	var prop: Dictionary = model.propulsion
	var turbine: bool = Turbine.is_turbine(prop)
	var propulsion_model: String = "turbine-ecu-spool-v1" if turbine else (
		"propeller-shaft-balance-v1" if Propulsion.has_shaft(prop) else "propeller-rpm-lag-v1")
	return {
		metadata_schema = "openrc-flight-meta v2",
		scenario = "trimmed %s across view at %.1f m/s (D5: six-axis trim, calm air)" % ["level flight (engine running)" if start.get("mode", "level") == "level" else "power-off glide", float(start.get("V", NAN))],
		aircraft = "%s (%s)" % [aircraft.model.get("id", "?"), aircraft_path],
		aircraft_input_format = AircraftData.FORMAT,
		aircraft_input_sha256 = aircraft.get("input_identity", {}).get("sha256", "unavailable: in-memory input"),
		aircraft_input_hash_convention = "sha256 of exact aircraft input file bytes",
		aircraft_semantic_sha256 = model.get("data_sha256", "unavailable"),
		aircraft_semantic_hash_convention = "sha256 of Godot JSON.stringify(parsed_input, indent=empty, sort_keys=true, full_precision=false); not file bytes",
		configuration = aircraft.model.get("configuration", "unspecified"),
		aero_model = "global-derivatives-v1" if model.get("envelope", {}).is_empty() else "local-surfaces-v1 with bounded attached oracle",
		propulsion_model = propulsion_model,
		propwash_model = "tail-slipstream-axial-transport-v1" if WashTransport.enabled(prop) else (
			"none" if prop.get("slipstream", {}).is_empty() else "tail-slipstream-increment-v1"),
		continuous_layout = "axial wash increment m/s, slipstream.pieces order; RK4 coupled; checkpoint only" if WashTransport.enabled(prop) else "none",
		propulsion_features = JSON.stringify({
			propeller_normal_force = not turbine and prop.has("axis") and not prop.get("normal_force", PackedFloat64Array()).is_empty(),
			propeller_pfactor = not turbine and prop.has("axis") and not prop.get("pfactor_moment", PackedFloat64Array()).is_empty(),
			rotor_gyroscopic_coupling = float(prop.rotor_inertia) != 0.0,
			turbine_ram_flow = turbine and float(prop.get("ram_flow", 0.0)) != 0.0,
			turbine_ram_jet = turbine and prop.has("ram_jet"),
		}),
		engine_rpm_semantics = "turbine spool rpm" if turbine else "propeller shaft rpm",
		state_layout = JSON.stringify(RB.STATE_LAYOUT),
		aux_layout = JSON.stringify(AUX_LAYOUT),
		recording_start_tick = sim.tick,
		# The trace's sampled aux columns (aux_layout); E3b1 anchors are exact only in checkpoints (H8).
		recording_start_aux = JSON.stringify(Array(sim.aux.slice(0, AUX_LAYOUT.size())), "", true, true),
		recording_start_engine_running = JSON.stringify(engine_running),
		ground = "flat at 0 m; %s" % ("%d spring-damper gear contacts (E1) with tyre friction and nose-wheel steering, brakes off (E2)%s, on %s" % [aircraft.model.landing_gear.contacts.size(), ", stiction anchors (E3b1)" if anchor_count() > 0 else "", "field '%s' surfaces (E3a)" % ground_field_id if not ground_surfaces.is_empty() else "dry pavement"] if not aircraft.model.landing_gear.is_empty() else "no landing gear: any wheel contact is a crash (D9d)"),
		created_utc = Time.get_datetime_string_from_system(true),
		engine = "Godot " + Engine.get_version_info().string,
		dt_s = sim.dt(),
		mass_kg = sim.mass,
		inertia_kgm2 = "Jxx Jyy Jzz Jxy Jxz Jyz = %s" % " ".join(Array(sim.inertia).map(func(v): return str(v))),
		gravity_mps2 = sim.gravity,
		frames = "world NED (north, east, down); body FRD (forward, right, down); quaternion body->NED [w,x,y,z]",
		loads = "Fx..Mz: body-axis loads excluding gravity; tick 0 evaluates reset state/aux; tick k>0 evaluates state k-1 with aux k (after pre_step)",
		state_timing = "state and aux at tick k; aux advances before RK4 and is held through its stages; cmd_* drives that step (reset commands at tick 0)",
	}


## Physics replay boundary, deliberately downstream of live input conditioning and menus.
## Owner configuration is fingerprinted in exact Variant encoding; derived caches are excluded.
func checkpoint() -> Dictionary:
	if not _flight_ready():
		return {}
	var snapshot: Dictionary = sim.checkpoint()
	if snapshot.is_empty() or snapshot.modes.size() != 1 or snapshot.modes[0] < 0 or snapshot.modes[0] > 1:
		return {}
	return { format = "openrc-flight-checkpoint v1", configuration = _checkpoint_configuration(), simulation = snapshot }


func _checkpoint_configuration() -> String:
	var config_hash := HashingContext.new()
	config_hash.start(HashingContext.HASH_SHA256)
	config_hash.update(var_to_bytes([aircraft.model, ground_surfaces]))
	return config_hash.finish().hex_encode()


## Restoring switches to recorded-input replay and stays paused. No raw radio state is deserialized.
## A caller feeds sim.inputs and calls sim.step(); live-session saves are a separate future feature.
func restore_checkpoint(candidate: Dictionary) -> bool:
	if not _has_valid_start() or typeof(candidate.get("format")) != TYPE_STRING \
			or candidate.format != "openrc-flight-checkpoint v1" or typeof(candidate.get("configuration")) != TYPE_STRING \
			or candidate.configuration != _checkpoint_configuration() \
			or not candidate.get("simulation") is Dictionary:
		return false
	var snapshot: Dictionary = candidate.simulation
	if not sim.can_restore_checkpoint(snapshot) or snapshot.modes.size() != 1 \
			or snapshot.modes[0] < 0 or snapshot.modes[0] > 1:
		return false
	for at in range(AUX_ANCHORS + 2, snapshot.aux.size(), Ground.ANCHOR_STRIDE):
		if snapshot.aux[at] != 0.0 and snapshot.aux[at] != 1.0:
			return false # an anchor is stuck or sliding, nothing in between
	resetting.emit() # close recording before the clock moves backwards
	if not sim.restore_checkpoint(snapshot):
		return false
	input_enabled = false
	crash = {}
	pause_reason = "checkpoint restored (recorded inputs)"
	_deflection_key = PackedFloat64Array()
	return true
