# DR-16b: the dedicated headless multirotor session. Prepare on the default field with the shipped document and on
# flat fixture ground with in-memory fixtures; holds, refused pilot frames, arming, a scripted flight that ends in a
# crash with a running aftermath, pad reset, TX-06 refusal without touching the running flight, TX-08/REPLAY-02
# checkpoint/restore with byte-identical continuation, identity scope, kernel faults, obstacle strike, focus loss and
# telemetry. Software checks on estimated data; exact replay is same build and platform only.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const ActuatorMap := preload("res://physics/multirotor/actuator_map.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const AirfieldTrack := preload("res://physics/ground_vehicle/airfield_track.gd")
const CollisionSetup := preload("res://scenery/collision_setup.gd")

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _session(field: Dictionary, options: Dictionary) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	if not s.prepare(field, options):
		print("prepare refused: ", s.load_error)
	return s


func _electric(extra: Dictionary = {}) -> Node:
	var options := {prepared_data = Fixtures.electric()}
	options.merge(extra, true)
	return _session({}, options)


## Absolute throttle stick that holds the weight at the current pack voltage (static map, symmetric rotors).
func _hover_throttle(s: Node) -> float:
	var map: Dictionary = s.plant.config.actuator
	var command: float = ActuatorMap.command_for_thrust(map, float(s.data.mass_kg) * 9.80665 / 4.0, s.plant.supply_voltage(s.sim.continuous))
	return (command - float(map.idle)) / (float(map.top) - float(map.idle))


## Run `ticks` accepted ticks with one pilot frame; false at the first refusal.
func _fly(s: Node, pilot: PackedFloat64Array, ticks: int) -> bool:
	for _i in ticks:
		if not s.tick_once(pilot):
			return false
	return true


## Arm switch OFF then ON at zero throttle.
func _arm(s: Node, mode := 0) -> bool:
	return _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0, mode), 1) and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, mode), 1) \
		and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED


## The document with every proportional gain scaled by 1.5.
func _stiffer(doc: Dictionary) -> Dictionary:
	var kp: PackedFloat64Array = doc.controller.kp.duplicate()
	for i in kp.size():
		kp[i] *= 1.5
	doc.controller.kp = kp
	return doc


func _frame_bytes(s: Node) -> PackedByteArray:
	return var_to_bytes(s.frame())


func _finite_values(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_PACKED_FLOAT64_ARRAY:
			for item: float in value:
				if not is_finite(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not _finite_values(value[key]):
					return false
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _finite_values(item):
					return false
			return true
	return true


func _run() -> void:
	await _default_field()
	await _rc_circuit()
	_holds_and_refusals()
	_flight_crash_and_reset()
	_tx06()
	_checkpoint_replay()
	_identity_scope()
	_kernel_fault()
	_obstacle_strike()
	_focus_loss()
	_telemetry()
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _default_field() -> void:
	var loaded: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH)
	var field: Dictionary = loaded.field
	var s := _session(field, {})
	_check("the shipped document prepares on the default field", loaded.ok and s.prepared and s.load_error.is_empty(), s.load_error)
	if not s.prepared:
		return
	var t: Dictionary = s.telemetry()
	var rest: float = s.data.start.rest_height_m
	_check("starts paused, disarmed, at rest on the ground at the document's rest height",
		s.paused and s.pause_reason == "prepared" and s.sim.tick == 0 and not t.armed and t.arm_block == FC.BLOCK_SWITCH
		and absf(float(t.altitude_agl_m) - rest) < 1e-9 and float(t.speed_mps) == 0.0 and s.tape().is_empty(),
		"agl %.6f rest %.6f" % [t.altitude_agl_m, rest])
	var pilot: Dictionary = field.pilot
	_check("the start is the pilot station plus the default offsets", absf(s.sim.state[RB.POS] - (float(pilot.north) + 12.0)) < 1e-12
		and absf(s.sim.state[RB.POS + 1] - float(pilot.east)) < 1e-12)
	_check("the kernel never steps on its own", s.sim.process_mode == Node.PROCESS_MODE_DISABLED)
	s.resume()
	var tick: int = s.sim.tick
	for _i in 6:
		await physics_frame
	_check("an unpaused session still advances only through tick_once", s.sim.tick == tick and s.tape().is_empty())
	var settled := _fly(s, FC.neutral_input(), 240)
	t = s.telemetry()
	_check("the disarmed airframe stays on its feet on the field", settled and absf(float(t.altitude_agl_m) - rest) < 0.004
		and float(t.speed_mps) < 0.01 and s.crash.is_empty(), "agl %.4f speed %.4f" % [t.altitude_agl_m, t.speed_mps])
	_check("the electrical document reports its pack", t.has_battery and float(t.soc) > 0.99)
	s.queue_free()



## RC-TRACK: with the club's RC car circuit shown, the quad's ground is the circuit's relief (the same float64 overlay
## the airplanes and cars use) and its obstacle inventory holds the circuit dressing; bad circuit data refuses.
func _rc_circuit() -> void:
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var circuit: Dictionary = AirfieldTrack.load_default().track
	# The highest point of the tabletop ramp on the south straight.
	var at := Vector2(39.0, -6.0)
	var best := -INF
	for i in 81:
		var east: float = -6.0 + 0.05 * float(i)
		var lift: float = AirfieldTrack.composed(PackedFloat64Array([0.0, 0.0, 0.0]), circuit, 39.0, east)[0]
		if lift > best:
			best = lift
			at = Vector2(39.0, east)
	var options := {north_offset_m = at.x, east_offset_m = at.y}
	var plain := _session(field, options)
	var with_options := options.duplicate()
	with_options.rc_track = circuit
	var s := _session(field, with_options)
	var lift := 0.0
	if s.prepared and plain.prepared:
		lift = s.environment.ground(at.x, at.y)[0] - plain.environment.ground(at.x, at.y)[0]
	_check("RC-TRACK the circuit raises the quad's ground by its relief (tabletop deck)", s.prepared and lift > 0.4
		and absf(lift - best) < 1e-9 and str(s.identity().environment.get("rc_track", "")) == AirfieldTrack.identity(circuit),
		"lift %.3f m (overlay %.3f m)" % [lift, best])
	if s.prepared:
		var rest: float = s.data.start.rest_height_m
		s.resume()
		var settled := _fly(s, FC.neutral_input(), 240)
		var t: Dictionary = s.telemetry()
		var height: float = -s.sim.state[RB.POS + 2]
		_check("RC-TRACK the disarmed quad stands on the ramp deck, not the field under it", settled and s.crash.is_empty()
			and absf(float(t.altitude_agl_m) - rest) < 0.004 and height > plain.environment.ground(at.x, at.y)[0] + 0.4,
			"agl %.4f height %.3f" % [t.altitude_agl_m, height])
	var world: Dictionary = CollisionSetup.build(field, circuit)
	var dressed := 0
	if world.ok:
		for proxy: Dictionary in world.world.proxies:
			dressed += 1 if str(proxy.get("id", "")).contains("rc_track:") else 0
	# Installed before a flight (the flown session above refuses an inventory change mid-flight).
	_check("RC-TRACK the obstacle inventory with the circuit holds its barriers and signs and installs",
		world.ok and dressed > 0 and plain.set_collision_world(world.world), "%d circuit proxies" % dressed)
	var bad := options.duplicate()
	bad.rc_track = {format = "openrc-airfield-track v0"}
	var refused := _session(field, bad)
	var flat := _session({}, {rc_track = circuit})
	_check("RC-TRACK an invalid circuit, or one on another field, refuses", not refused.prepared and not flat.prepared
		and refused.load_error.contains("rc_track") and flat.load_error.contains("rc_track"), refused.load_error)
	for node: Node in [plain, s, refused, flat]:
		node.queue_free()


func _holds_and_refusals() -> void:
	var s := _electric({throttle_policy = "rate"})
	_check("a fixture document prepares on flat fixture ground", s.prepared and absf(s.sim.state[RB.POS + 2] + Fixtures.REST_HEIGHT_M) < 1e-12, s.load_error)
	_check("a paused session refuses ticks", not s.tick_once(FC.neutral_input()) and s.sim.tick == 0)
	s.resume()
	var armed := _arm(s)
	var climbing := _fly(s, Fixtures.pilot(0.1, 0.0, 0.0, 0.6, 1), 90)
	var virtual: float = s.sim.aux[FC.AUX_VIRTUAL_THROTTLE]
	_check("rate throttle: armed, the accumulator integrates while flying", armed and climbing and virtual > 0.1, "virtual %.4f" % virtual)
	s.pause("pilot pause")
	var held := _frame_bytes(s)
	var held_tape: PackedFloat64Array = s.tape()
	var charge: float = s.sim.continuous[Plant.C_CHARGE]
	var refused := true
	for _i in 30:
		refused = refused and not s.tick_once(Fixtures.pilot(0.5, 0.5, 0.5, 1.0, 1))
	_check("INPUT-07 a hold integrates nothing: no tick, controller block, accumulator or pack charge advances",
		refused and _frame_bytes(s) == held and s.tape() == held_tape and s.sim.continuous[Plant.C_CHARGE] == charge
		and s.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == virtual and s.paused and s.pause_reason == "pilot pause")
	s.resume()
	var before_tick: int = s.sim.tick
	var before_tape: int = s.tape().size()
	var bad_frames: Array[PackedFloat64Array] = [Fixtures.pilot(1.5, 0.0, 0.0, 0.0, 1), PackedFloat64Array([0.0, 0.0, 0.0]),
		Fixtures.pilot(0.0, 0.0, 0.0, NAN, 1), Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1, 3)]
	var all_refused := true
	for bad: PackedFloat64Array in bad_frames:
		all_refused = all_refused and not s.tick_once(bad)
	_check("an invalid pilot frame is refused before the kernel: no fault, no tick, no tape row",
		all_refused and s.sim.fault_reason.is_empty() and s.fault_reason.is_empty() and s.sim.tick == before_tick
		and s.tape().size() == before_tape and not s.paused)
	_check("a valid frame after a refused one flies on", s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)) and s.sim.tick == before_tick + 1
		and s.tape().size() == before_tape + FC.INPUT_SIZE)
	var reset_action: PackedFloat64Array = Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1)
	reset_action[FC.IN_ACTIONS] = float(FC.ACTION_THROTTLE_RESET)
	_check("INPUT-08 the zero-throttle action clears the accumulator in its sample", s.tick_once(reset_action)
		and s.sim.aux[FC.AUX_VIRTUAL_THROTTLE] == 0.0)
	s.queue_free()


func _flight_crash_and_reset() -> void:
	var s := _electric()
	var crashes: Array = []
	s.crashed.connect(func(reason: String) -> void: crashes.append(reason))
	s.resume()
	var hover := _hover_throttle(s)
	var ok := _arm(s)
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.62, 1), 480)
	var climbed: float = -s.sim.state[RB.POS + 2]
	_check("arm OFF then ON at low throttle, then take off and climb", ok and climbed > 4.0, "height %.2f" % climbed)
	var peak_rate := 0.0
	for _i in 120:
		ok = ok and s.tick_once(Fixtures.pilot(1.0, 0.0, 0.0, hover + 0.15, 1))
		peak_rate = maxf(peak_rate, s.sim.state[RB.RATE])
	ok = ok and _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover + 0.1, 1), 240)
	_check("a scripted Acro roll reaches a high roll rate and the centred stick stops it", ok and peak_rate > 8.0
		and absf(s.sim.state[RB.RATE]) < 0.1 and crashes.is_empty(), "peak %.2f rad/s now %.4f" % [peak_rate, s.sim.state[RB.RATE]])
	var fell := true
	for _i in 2400:
		fell = fell and s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0))
		if not crashes.is_empty():
			break
	var crash_tick: int = s.sim.tick
	_check("a disarmed fall ends in exactly one crash signal with a reason", fell and crashes.size() == 1 and not str(crashes[0]).is_empty()
		and s.crash.get("reason", "") == crashes[0] and int(s.crash.tick) == crash_tick, str(crashes))
	var aftermath := _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 120)
	_check("the session keeps running after the crash with the drive cut; no second signal", aftermath and not s.paused
		and s.sim.tick == crash_tick + 120 and crashes.size() == 1 and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_CRASHED
		and s.sim.continuous[Plant.C_CUT_LATCH] == 1.0)
	s.pause("crashed")
	_check("resume is refused after a crash: a pad reset is required", not s.resume() and s.paused)
	var resets := [0]
	s.resetting.connect(func() -> void: resets[0] += 1)
	_check("reset_to_pad publishes a fresh disarmed frame and clears crash and tape", s.reset_to_pad() and resets[0] == 1
		and s.crash.is_empty() and s.tape().is_empty() and s.sim.tick == 0 and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and s.sim.continuous[Plant.C_CUT_LATCH] == 0.0 and absf(s.sim.state[RB.POS + 2] + Fixtures.REST_HEIGHT_M) < 1e-12 and s.paused)
	s.resume()
	var held := _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 120)
	_check("an arm switch held high through the reset does not rearm", held and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED
		and s.sim.modes[FC.MODE_ARM_BLOCK] == FC.BLOCK_SWITCH)
	s.queue_free()


func _tx06() -> void:
	var s := _electric()
	s.resume()
	_arm(s)
	_fly(s, Fixtures.pilot(0.2, 0.0, 0.0, 0.6, 1), 120)
	var frame := _frame_bytes(s)
	var tape: PackedFloat64Array = s.tape()
	var identity: PackedByteArray = var_to_bytes(s.identity())
	var resets := [0]
	s.resetting.connect(func() -> void: resets[0] += 1)
	var malformed: Dictionary = Fixtures.electric()
	malformed.erase("controller")
	var unshaped: Dictionary = Fixtures.electric()
	unshaped.rotors = unshaped.rotors.slice(0, 3)
	var cases := [
		["a path to a document that is not multirotor data", {data_path = "res://data/fields/default.json"}],
		["a data path that does not exist", {data_path = "res://data/multirotors/does-not-exist.json"}],
		["a prepared document without its controller block", {prepared_data = malformed}],
		["a prepared document with three rotors", {prepared_data = unshaped}],
		["wind above the admitted steady limit", {prepared_data = Fixtures.electric(), wind_speed_mps = 20.0}],
		["a start outside the field", {prepared_data = Fixtures.electric(), north_offset_m = INF}],
		["an unknown throttle policy", {prepared_data = Fixtures.electric(), throttle_policy = "auto"}],
		["an invalid rates profile", {prepared_data = Fixtures.electric(), rates = {format = "nope"}}],
	]
	for item: Array in cases:
		var refused: bool = not s.prepare({}, item[1])
		_check("TX-06 %s is refused and the running flight is untouched" % item[0], refused and not s.load_error.is_empty()
			and s.prepared and _frame_bytes(s) == frame and s.tape() == tape and var_to_bytes(s.identity()) == identity
			and resets[0] == 0 and not s.paused, s.load_error.left(120))
	_check("the untouched flight keeps flying", s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.5, 1)) and s.tape().size() == tape.size() + FC.INPUT_SIZE)
	s.queue_free()


func _scripted(i: int, throttle: float) -> PackedFloat64Array:
	var t := float(i) / 240.0
	return Fixtures.pilot(0.6 * sin(3.0 * t), 0.4 * sin(2.0 * t + 0.5), 0.3 * cos(1.5 * t), clampf(throttle + 0.1 * sin(t), 0.0, 1.0), 1)


func _checkpoint_replay() -> void:
	var s := _electric()
	s.resume()
	_arm(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.62, 1), 360)
	var hover := _hover_throttle(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, hover, 1), 480)
	_fly(s, Fixtures.pilot(0.8, 0.0, 0.0, hover, 1), 50)
	var rolling: float = s.sim.state[RB.RATE]
	var target: float = s.sim.aux[FC.AUX_SETPOINT]
	var envelope: Dictionary = s.checkpoint()
	_check("TX-08 a mid-roll checkpoint carries the full envelope", not envelope.is_empty() and rolling > 0.5 * target and target > 3.0
		and envelope.format == Session.FORMAT and envelope.kernel.has("aux") and envelope.kernel.has("continuous")
		and envelope.kernel.has("modes") and envelope.tape_ticks == s.tape().size() / FC.INPUT_SIZE,
		"roll rate %.2f of %.2f rad/s" % [rolling, target])
	var pilots: Array[PackedFloat64Array] = []
	var frames: Array[PackedByteArray] = []
	for i in 240:
		var pilot := _scripted(i, hover)
		pilots.append(pilot)
		s.tick_once(pilot)
		frames.append(_frame_bytes(s))
	var resets := [0]
	s.resetting.connect(func() -> void: resets[0] += 1)
	var restored: bool = s.restore_checkpoint(envelope)
	_check("the checkpoint restores into the same session, running, tape restarted", restored and resets[0] == 1 and not s.paused
		and s.tape().is_empty() and s.sim.tick == int(envelope.kernel.tick))
	var same := restored
	for i in 240:
		same = same and s.tick_once(pilots[i]) and _frame_bytes(s) == frames[i]
	_check("REPLAY-02 the same pilot frames continue byte-identically after restore", same)
	var second := _electric()
	var restored_second: bool = second.restore_checkpoint(envelope)
	var same_second := restored_second
	for i in 240:
		same_second = same_second and second.tick_once(pilots[i]) and _frame_bytes(second) == frames[i]
	_check("REPLAY-02 a second identically prepared session continues byte-identically", same_second)
	var tape_ok := true
	var replayed: PackedFloat64Array = second.tape()
	for i in 240:
		tape_ok = tape_ok and replayed.slice(FC.INPUT_SIZE * i, FC.INPUT_SIZE * (i + 1)) == pilots[i]
	_check("the tape holds exactly the accepted pilot frames since the restore", tape_ok and replayed.size() == 240 * FC.INPUT_SIZE)
	var other_rates: Dictionary = Rates.default_profile()
	other_rates.axes.roll.rc_rate = 25
	var different := _electric({rates = other_rates})
	var before := _frame_bytes(different)
	_check("a checkpoint from another rates profile is refused with nothing changed", different.prepared
		and not different.restore_checkpoint(envelope) and _frame_bytes(different) == before and different.sim.tick == 0)
	var gains := _stiffer(Fixtures.electric())
	var other_data := _session({}, {prepared_data = gains})
	before = _frame_bytes(other_data)
	_check("a checkpoint from another document is refused with nothing changed", other_data.prepared
		and not other_data.restore_checkpoint(envelope) and _frame_bytes(other_data) == before)
	var tampered: Dictionary = envelope.duplicate(true)
	tampered.kernel.state[RB.POS] = NAN
	before = _frame_bytes(second)
	_check("a damaged kernel checkpoint is refused before anything changes", not second.restore_checkpoint(tampered)
		and _frame_bytes(second) == before)
	tampered = envelope.duplicate(true)
	tampered.collision_identity = "another-world"
	_check("a checkpoint from another obstacle inventory is refused", not second.restore_checkpoint(tampered))
	for node: Node in [s, second, different, other_data]:
		node.queue_free()


func _identity_scope() -> void:
	var base := _electric()
	var identity: PackedByteArray = var_to_bytes(base.identity())
	var twin := _electric({hud_theme = "dark", camera_tilt_deg = 35.0})
	_check("identity ignores options that do not affect physics", var_to_bytes(twin.identity()) == identity)
	base.resume()
	_arm(base)
	_fly(base, Fixtures.pilot(0.0, 0.0, 0.0, 0.4, 1), 60)
	base.pause("p")
	base.reset_to_pad()
	_check("identity is unchanged by flying, pausing and a pad reset", var_to_bytes(base.identity()) == identity)
	var other_rates: Dictionary = Rates.default_profile()
	other_rates.axes.yaw.srate = 60
	var gains := _stiffer(Fixtures.electric())
	var variants := [["rates", {rates = other_rates}], ["wind", {wind_speed_mps = 2.0, wind_from_deg = 90.0}],
		["data", {prepared_data = gains}], ["throttle policy", {throttle_policy = "rate"}], ["start", {start = "air"}],
		["heading", {heading_deg = 45.0}], ["initial charge", {initial_soc = 0.5}]]
	for item: Array in variants:
		var other := _electric(item[1])
		_check("identity changes with %s" % item[0], other.prepared and var_to_bytes(other.identity()) != identity, other.load_error)
		other.queue_free()
	base.queue_free()
	twin.queue_free()


func _kernel_fault() -> void:
	var s := _electric()
	var faults: Array = []
	s.faulted.connect(func(reason: String) -> void: faults.append(reason))
	s.resume()
	_arm(s)
	_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.3, 1), 30)
	var tick: int = s.sim.tick
	var tape_size: int = s.tape().size()
	var frame := _frame_bytes(s)
	s.sim.mass = NAN
	var refused: bool = not s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.3, 1))
	_check("a corrupted kernel refuses the tick, pauses with one faulted signal and keeps the accepted frame",
		refused and faults.size() == 1 and not s.fault_reason.is_empty() and s.paused and s.sim.tick == tick
		and _frame_bytes(s) == frame and is_finite(s.sim.mass), str(faults))
	_check("the tape excludes the refused tick", s.tape().size() == tape_size)
	_check("a faulted session refuses resume, ticks and a checkpoint", not s.resume() and not s.tick_once(FC.neutral_input())
		and s.checkpoint().is_empty())
	_check("reset_to_pad clears the sticky fault", s.reset_to_pad() and s.fault_reason.is_empty() and s.sim.fault_reason.is_empty()
		and s.resume() and s.tick_once(FC.neutral_input()))
	s.queue_free()


func _world(proxies: Array[Dictionary]) -> Dictionary:
	return {format = CollisionWorld.FORMAT, identity = "multirotor-test-wall", cell_size_m = CollisionWorld.CELL_SIZE_M,
		proxies = proxies, bins = CollisionWorld._build_bins(proxies)}


func _obstacle_strike() -> void:
	var proxies: Array[Dictionary] = []
	# A wall across the course 6 m north of the start, 30 m wide and 20 m tall, 0.3 m thick.
	CollisionWorld._add_box_at_down(proxies, "wall", "wall", "wall", "hard_terminal", 18.0, 0.0, -10.0, 30.0, 20.0, 0.3, 0.0)
	var s: Node = Session.new()
	root.add_child(s)
	_check("a synthetic obstacle inventory installs before prepare", s.set_collision_world(_world(proxies)))
	var prepared: bool = s.prepare({}, {prepared_data = Fixtures.electric(), start = "air", altitude_m = 10.0})
	_check("an air start prepares with pre-spun shafts, disarmed", prepared and s.sim.continuous[0] > 1000.0
		and s.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_DISARMED and s.collision_identity() == "multirotor-test-wall", s.load_error)
	s.resume()
	var crashes: Array = []
	s.crashed.connect(func(reason: String) -> void: crashes.append(reason))
	_check("set_collision_world is refused mid-flight", _arm(s, 1) and not s.set_collision_world({}))
	var hover := _hover_throttle(s)
	for _i in 2400:
		if not s.tick_once(Fixtures.pilot(0.0, -0.4, 0.0, clampf(hover + 0.05, 0.0, 1.0), 1, 1)):
			break
		if not crashes.is_empty():
			break
	_check("DR-19 flying into the wall is one obstacle strike before the centre reaches it", crashes.size() == 1
		and crashes[0] == "Obstacle strike" and s.sim.state[RB.POS] < 17.85 and s.sim.state[RB.POS] > 16.5,
		"north %.3f %s" % [s.sim.state[RB.POS], str(crashes)])
	s.queue_free()


func _focus_loss() -> void:
	var s := _electric()
	var reasons: Array = []
	s.pause_changed.connect(func(value: bool, reason: String) -> void: reasons.append([value, reason]))
	s.resume()
	_fly(s, FC.neutral_input(), 10)
	s.sim.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("INPUT-07 focus loss pauses the session with its reason", s.paused and s.pause_reason == Session.FOCUS_PAUSE
		and not s.tick_once(FC.neutral_input()) and reasons.back() == [true, Session.FOCUS_PAUSE])
	_check("resume after focus loss is explicit and flies on", s.resume() and s.tick_once(FC.neutral_input()) and not s.sim.paused)
	s.sim.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check("a second focus loss pauses again", s.paused and s.pause_reason == Session.FOCUS_PAUSE)
	s.queue_free()


func _telemetry() -> void:
	for item: Array in [["electrical", Fixtures.electric(), true], ["laboratory", Fixtures.lab(), false]]:
		var s := _session({}, {prepared_data = item[1]})
		s.resume()
		_arm(s)
		var finite := true
		var shaped := true
		for i in 240:
			s.tick_once(Fixtures.pilot(0.2 * sin(0.05 * i), 0.0, 0.0, 0.5, 1))
			var t: Dictionary = s.telemetry()
			finite = finite and _finite_values(t)
			shaped = shaped and t.has_battery == item[2] and t.has("soc") == item[2] and t.has("bus_voltage_v") == item[2] \
				and t.tick == s.sim.tick and t.has("altitude_agl_m") and t.has("speed_mps") and t.armed
		_check("240 ticks of %s telemetry stay finite; battery values only for the electrical law" % item[0],
			finite and shaped and s.fault_reason.is_empty(), s.fault_reason)
		var body: PackedFloat64Array = s.interpolated(0.5)
		_check("%s interpolation returns a finite 13-value body; a nonfinite fraction never faults" % item[0], body.size() == 13
			and _finite_values(body) and s.interpolated(NAN).size() == 13 and s.sim.fault_reason.is_empty())
		s.queue_free()
