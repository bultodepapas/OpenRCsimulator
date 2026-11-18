# DR-19c (docs/plans/drone-racing.md §17.2): graded crashes of the FPV quad. A gentle touch or armed idle on the pad
# does nothing; a hard landing chips spinning props and the flight goes on; only an extreme impact ends it; a spinning
# prop wears in contact and breaks; obstacles bounce the quad with bounded energy, a prop clip is never terminal and a
# frame hit ends the flight only above its material's speed; damaged props lose thrust; the strict law keeps the old
# outcomes and the graded law replays exactly. Expected values are closed forms and the declared law constants, not
# the implementation's own results. A declared gameplay law on estimated data: no measured crash damage.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")
const Session := preload("res://sim/multirotor/session.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")

var _count := 0
var _failures := 0
var _wall_north := 0.0
var _class := ""
var _ceiling_down := 0.0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_sessions()
	_prop_wear()
	_obstacles()
	_thrust_scaling()
	_broken_prop_flight()
	_flat_touchdown()
	_grazes()
	_world_swap()
	print("graded crashes: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _session(model: String, options: Dictionary = {}) -> Node:
	var s: Node = Session.new()
	root.add_child(s)
	var opts := {crash_model = model}
	opts.merge(options, true)
	if not s.prepare({}, opts):
		_check("%s session prepares" % model, false, str(s.load_error))
	s.resume()
	return s


## Ticks until the flight crashes or `limit` passes; returns the number of accepted ticks.
func _fly(s: Node, pilot: PackedFloat64Array, limit: int) -> int:
	var n := 0
	while n < limit and s.crash.is_empty() and s.tick_once(pilot):
		n += 1
	return n


func _sessions() -> void:
	# Armed idle on the pad: the props spin below the strike speed; no damage, no event.
	var pad := _session("graded")
	var events: Array = []
	pad.impact.connect(func(event: Dictionary) -> void: events.append(event))
	_fly(pad, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 2)
	_fly(pad, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 1), 240)
	var health: PackedFloat64Array = pad.sim.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4)
	_check("armed idle on the pad: no damage and no impact event", pad.crash.is_empty() and events.is_empty()
		and health == PackedFloat64Array([1.0, 1.0, 1.0, 1.0]) and pad.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED, str(health))
	pad.free()

	# A disarmed drop from 3 m lands at about 7.7 m/s: above crash_speed (5), below 3 × crash_speed (15).
	var graded := _session("graded", {start = "air", altitude_m = 3.0})
	var impacts: Array = []
	graded.impact.connect(func(event: Dictionary) -> void: impacts.append(event))
	var flown := _fly(graded, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 480)
	_check("graded: a 3 m disarmed drop is a hard landing, not a crash; the flight goes on", graded.crash.is_empty()
		and flown == 480 and _hard_landing(impacts), str(impacts))
	_check("graded: stopped props are not chipped by a hard landing", graded.sim.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4)
		== PackedFloat64Array([1.0, 1.0, 1.0, 1.0]))
	graded.free()
	var strict := _session("strict", {start = "air", altitude_m = 3.0})
	_fly(strict, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 480)
	_check("strict: the same drop still ends the flight (the original law)", str(strict.crash.get("reason", "")) == "Hard impact")
	strict.free()

	# A disarmed drop from 20 m lands at about 19.8 m/s: above 3 × crash_speed, terminal under both laws.
	var high := _session("graded", {start = "air", altitude_m = 20.0})
	_fly(high, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 960)
	_check("graded: a 20 m drop (about 20 m/s) is a hard impact that ends the flight", str(high.crash.get("reason", "")) == "Hard impact")
	high.free()

	# The graded law is part of the identity and replays exactly: the same tape gives the same frames.
	var tape_a := _session("graded", {start = "air", altitude_m = 3.0})
	var tape_b := _session("graded", {start = "air", altitude_m = 3.0})
	var arm := Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0)
	_fly(tape_a, arm, 300)
	_fly(tape_b, arm, 300)
	_check("graded: identical tapes give bit-identical frames (deterministic law)", var_to_bytes(tape_a.frame()) == var_to_bytes(tape_b.frame()))
	var strict_identity: Dictionary = _session("strict").sim.model.identity
	_check("the impact law is part of the model identity", str(tape_a.sim.model.identity.get("impacts", "")) == Plant.IMPACT_GRADED
		and str(strict_identity.get("impacts", "")) == Plant.IMPACT_STRICT)
	tape_a.free()
	tape_b.free()


func _hard_landing(events: Array) -> bool:
	for e: Dictionary in events:
		if e.type == "impact" and e.surface == "ground" and float(e.normal_speed_mps) > 5.0 and float(e.normal_speed_mps) < 15.0:
			return true
	return false


func _plant() -> RefCounted:
	var made: Dictionary = Plant.create(Fixtures.electric(), Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	var p: RefCounted = made.plant
	p.graded_impacts = true
	return p


func _speeds(p: RefCounted, body: PackedFloat64Array, speed: float) -> PackedFloat64Array:
	var continuous: PackedFloat64Array = p.initial_frame(body).continuous
	for i in 4:
		continuous[i] = speed
	return continuous


## A spinning prop in the ground wears by PROP_WEAR_PER_TICK × ω/ω_hover per tick and breaks below PROP_BROKEN_HEALTH.
func _prop_wear() -> void:
	var p := _plant()
	var tilt := M.q_from_euler(0.0, deg_to_rad(35.0), 0.0) # nose up: the rear props dig into flat ground
	var body := RB.make_state(M.v3(0.0, 0.0, -0.02), M.v3(0.0, 0.0, 0.0), tilt, M.v3(0.0, 0.0, 0.0))
	var hover: float = p._hover_speed
	var continuous := _speeds(p, body, hover)
	# Terrain (grass and soil) is half as hard on a blade as wood or concrete; this prop bites deeper than a full bite.
	var expected := 1.0 - Plant.PROP_WEAR_PER_TICK * float(Plant.PROP_MATERIAL.ground)
	var once: Dictionary = p._graded_impacts(body, body, continuous, 0.0)
	var worn: Array = []
	for i in 4:
		if once.continuous[Plant.C_HEALTH + i] < 1.0:
			worn.append(i)
	_check("one tick in the ground at hover speed wears the digging props by 10 % (terrain 0.5 × 20 %), not terminal", once.reason == ""
		and not worn.is_empty() and worn.size() < 4 and absf(once.continuous[Plant.C_HEALTH + int(worn[0])] - expected) < 1.0e-12,
		str(once.continuous.slice(Plant.C_HEALTH, Plant.C_HEALTH + 4)))
	_check("DR-19d: the strike also brakes the digging prop's shaft by half (the ground stops the blade)",
		absf(once.continuous[int(worn[0])] - 0.5 * hover) < 1.0e-9)
	var single := _speeds(p, body, 0.0)
	single[int(worn[0])] = hover
	var lone: Dictionary = p._graded_impacts(body, body, single, 0.0)
	_check("DR-19d: a lone striking prop kicks the airframe (body rates change), with no energy gained", _kick_ok(p, body, lone.body))
	_check("two mirror-image counter-rotating strikes cancel (no net kick)", once.body.slice(RB.VEL, RB.RATE + 3) == body.slice(RB.VEL, RB.RATE + 3)
		or worn.size() != 2)
	# A motor that keeps driving the prop back to speed (as in flight) grinds it away.
	var state: PackedFloat64Array = once.continuous
	var ticks := 1
	while state[Plant.C_HEALTH + int(worn[0])] > 0.0 and ticks < 40:
		for i in 4:
			state[i] = hover
		state = p._graded_impacts(body, body, state, 0.0).continuous
		ticks += 1
	# 0.8^n < 0.3 first at n = 6: the prop breaks on the sixth tick of grinding.
	_check("grinding breaks the prop after twelve ticks (0.9^12 < 0.3), health 0", state[Plant.C_HEALTH + int(worn[0])] == 0.0 and ticks == 12,
		"%d ticks" % ticks)
	var slow := _speeds(p, body, 0.5 * hover)
	var half: Dictionary = p._graded_impacts(body, body, slow, 0.0)
	# (the half-speed case starts from intact props)
	_check("wear scales with shaft speed (half speed: 5 %)", absf(half.continuous[Plant.C_HEALTH + int(worn[0])] - 0.95) < 1.0e-12)
	var idle := _speeds(p, body, float(p.prepared.contacts.rotor_strike_speed_rad_s) - 1.0)
	_check("props below the strike speed are never worn", p._graded_impacts(body, body, idle, 0.0).events.is_empty())


## The strike kick changed the body rates, and the airframe's kinetic energy did not grow beyond the rotor energy lost.
func _kick_ok(p: RefCounted, before: PackedFloat64Array, after: PackedFloat64Array) -> bool:
	var rate_change := 0.0
	for k in 3:
		rate_change += absf(after[RB.RATE + k] - before[RB.RATE + k])
	var mass: float = p.prepared.mass_kg
	var inertia: PackedFloat64Array = p.prepared.inertia_kg_m2
	var energy_before := 0.0
	var energy_after := 0.0
	for k in 3:
		energy_before += 0.5 * mass * before[RB.VEL + k] * before[RB.VEL + k] + 0.5 * inertia[k] * before[RB.RATE + k] * before[RB.RATE + k]
		energy_after += 0.5 * mass * after[RB.VEL + k] * after[RB.VEL + k] + 0.5 * inertia[k] * after[RB.RATE + k] * after[RB.RATE + k]
	var hover: float = p._hover_speed
	var rotor_energy_lost: float = 0.5 * float(p.prepared.rotors[0].inertia_kg_m2) * (hover * hover - 0.25 * hover * hover) * 4.0
	return rate_change > 0.0 and energy_after - energy_before < rotor_energy_lost


func _wall(n: float, _e: float, _d: float) -> float:
	return _wall_north - n


func _class_hard(_n: float, _e: float, _d: float) -> String:
	return "hard_terminal"


func _class_foliage(_n: float, _e: float, _d: float) -> String:
	return "soft_foliage_impulse"


func _class_named(_n: float, _e: float, _d: float) -> String:
	return _class


## A flat wall ahead (clearance = wall north − point north). The frame box's front face is the front hubs; prop clips
## reach farther.
func _obstacles() -> void:
	var p := _plant()
	p.obstacle = Callable(self, "_wall")
	p.obstacle_class = Callable(self, "_class_hard")
	var frame_radius: float = p._frame_box_centre[0] + p._frame_box_half[0]
	var hub_front := -INF
	for rotor: Dictionary in p.prepared.rotors:
		hub_front = maxf(hub_front, float(rotor.hub_frd[0]))
	_check("the frame box's front face is the front hubs", absf(frame_radius - hub_front) < 1.0e-12)
	var level := M.q_identity()
	# Frame contact at 3 m/s: a bounce (restitution 0.2), pushed out of the wall, not terminal.
	_wall_north = frame_radius - 0.01
	var body := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(3.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var hit: Dictionary = p._graded_impacts(body, body, _speeds(p, body, 0.0), 0.0)
	# Restitution acts at the contact point (the box face's centre, a few mm off the CG: some of the impulse pitches).
	var contact: PackedFloat64Array = p._box_support(M.v3(-1.0, 0.0, 0.0)).point
	var vn: float = p._closing_speed(hit.body, contact, M.v3(-1.0, 0.0, 0.0)) # negative: separating
	# DR-19f: the pitch the off-centre hit induces makes the contact point slide, so friction takes a little more.
	_check("a 3 m/s frame hit on a wall bounces the contact point back, at most 0.2 × 3 m/s, and is not terminal",
		hit.reason == "" and vn < -0.4 and vn >= -0.6 - 1.0e-9 and hit.body[RB.VEL] < 0.0, "v %.4f" % vn)
	_check("the bounce leaves the frame outside the wall", _wall_north - hit.body[RB.POS] >= frame_radius - 1.0e-9)
	_check("the bounce dissipates energy", hit.body[RB.VEL] * hit.body[RB.VEL] < 9.0)
	# Resting against the wall (no closing speed): pushed out, but no chipped props and no impact event.
	var resting := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var spinning := _speeds(p, resting, p._hover_speed)
	var leaned: Dictionary = p._graded_impacts(resting, resting, spinning, 0.0)
	var frame_events := 0
	for event: Dictionary in leaned.events:
		if event.type == "impact" or str(event.get("cause", "")) == "frame":
			frame_events += 1
	_check("a frame resting on a wall raises no impact event and no frame chip (only its touching props grind)",
		leaned.reason == "" and frame_events == 0, str(leaned.events))
	# Above the material's speed: 9 m/s into a hard solid ends the flight; into foliage it does not.
	var fast := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(9.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	_check("a 9 m/s frame hit on a hard solid is an obstacle strike", p._graded_impacts(fast, fast, _speeds(p, fast, 0.0), 0.0).reason
		== "Obstacle strike")
	p.obstacle_class = Callable(self, "_class_foliage")
	_check("the same 9 m/s into foliage bounces (foliage ends the flight from 12 m/s)",
		p._graded_impacts(fast, fast, _speeds(p, fast, 0.0), 0.0).reason == "")
	for kind: String in ["frangible_impulse", "light_airframe_impulse", "gate_frame"]:
		_class = kind
		p.obstacle_class = Callable(self, "_class_named")
		var at_nine: String = p._graded_impacts(fast, fast, _speeds(p, fast, 0.0), 0.0).reason
		var limit: float = float(Plant.FRAME_TERMINAL_SPEED_MPS[kind])
		var over := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(limit + 0.5, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
		_check("9 m/s into %s bounces; %.1f m/s ends the flight" % [kind, limit + 0.5], at_nine == ""
			and p._graded_impacts(over, over, _speeds(p, over, 0.0), 0.0).reason == "Obstacle strike")
	p.obstacle_class = Callable(self, "_class_hard")
	# Prop clip: the wall reaches the front prop discs but not the frame.
	var front_reach: float = 0.0
	for rotor: Dictionary in p.prepared.rotors:
		front_reach = maxf(front_reach, float(rotor.hub_frd[0]))
	var prop_radius: float = 0.5 * float(p.prepared.rotors[0].diameter_m)
	_wall_north = front_reach + prop_radius - 0.005
	var clip := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(2.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var hover: float = p._hover_speed
	var clipped: Dictionary = p._graded_impacts(clip, clip, _speeds(p, clip, hover), 0.0)
	var damaged := 0
	for i in 4:
		if clipped.continuous[Plant.C_HEALTH + i] < 1.0:
			damaged += 1
	_check("a 2 m/s prop clip wears the front props only and is never terminal", clipped.reason == "" and damaged == 2
		and clipped.body[RB.VEL] < 2.0, "%d damaged, v %.3f" % [damaged, clipped.body[RB.VEL]])
	var hard_clip := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(7.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var broken: Dictionary = p._graded_impacts(hard_clip, hard_clip, _speeds(p, hard_clip, hover), 0.0)
	var zero := 0
	for i in 4:
		if broken.continuous[Plant.C_HEALTH + i] == 0.0:
			zero += 1
	_check("a 7 m/s prop clip (above 6 m/s) breaks the front props, still not terminal", broken.reason == "" and zero == 2)
	# The broken props keep spinning (stubs) but have no blade left to strike: the same wall touches nothing.
	var stubs: PackedFloat64Array = broken.continuous.duplicate()
	for i in 4:
		stubs[i] = hover
	var after: Dictionary = p._graded_impacts(hard_clip, hard_clip, stubs, 0.0)
	_check("broken props spinning at the wall no longer push or bounce the quad", after.reason == "" and after.body == hard_clip
		and after.events.is_empty(), str(after.events))
	# Strict law: any touch of the airframe sphere is the original obstacle strike.
	p.graded_impacts = false
	_check("strict: the 2 m/s prop clip is the original obstacle strike", p.crash_reason(clip, clip, _speeds(p, clip, hover))
		== "Obstacle strike")
	p.graded_impacts = true
	_shapes(p, hover)


## Horizontal surface above the quad (a roof or a gate's top bar wider than the quad): clearance = point down − ceiling
## down. Box and disc shapes (v2): v1's spheres reached 7.7 cm above the body and 6.5 cm above each prop disc.
func _ceiling(_n: float, _e: float, d: float) -> float:
	return d - _ceiling_down


func _shapes(p: RefCounted, hover: float) -> void:
	p.obstacle = Callable(self, "_ceiling")
	var level := M.q_identity()
	var top: float = p._frame_box_centre[2] - p._frame_box_half[2] # FRD z of the hull's top point (negative: up)
	var climbing := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, -1.0), level, M.v3(0.0, 0.0, 0.0))
	# 2 cm above the body's top and the prop discs: no contact (v1 bounced the frame and ground every prop).
	_ceiling_down = -5.0 + top - 0.02
	var clear: Dictionary = p._graded_impacts(climbing, climbing, _speeds(p, climbing, hover), 0.0)
	_check("a roof 2 cm above the body is not touched (box, not a 10 cm sphere)", clear.reason == "" and clear.events.is_empty()
		and clear.body == climbing, str(clear.events))
	# 5 mm into the body's top at 1 m/s: a frame contact, pushed down below the roof, bouncing (not terminal).
	_ceiling_down = -5.0 + top + 0.005
	var touched: Dictionary = p._graded_impacts(climbing, climbing, _speeds(p, climbing, 0.0), 0.0)
	_check("a roof 5 mm into the body's top is a frame contact: pushed out below it, rising no more",
		touched.reason == "" and touched.body[RB.POS + 2] + top >= _ceiling_down - 1.0e-9 and touched.body[RB.VEL + 2] >= 0.0,
		"%.4f %.4f" % [touched.body[RB.POS + 2] + top - _ceiling_down, touched.body[RB.VEL + 2]])
	# Yawed 30 degrees into a wall: the leading edge takes the hit, so the bounce spins the quad (v1's sphere hit
	# through the CG and never did).
	p.obstacle = Callable(self, "_wall")
	var yawed := M.q_from_euler(deg_to_rad(30.0), 0.0, 0.0)
	var reach: float = p._box_support(M.q_rotate(M.q_conj(yawed), M.v3(-1.0, 0.0, 0.0))).extent
	_wall_north = p._frame_box_centre[0] + reach - 0.005
	var oblique := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0), yawed, M.v3(0.0, 0.0, 0.0))
	var world_v := M.q_rotate(M.q_conj(yawed), M.v3(3.0, 0.0, 0.0))
	for k in 3:
		oblique[RB.VEL + k] = world_v[k]
	var spun: Dictionary = p._graded_impacts(oblique, oblique, _speeds(p, oblique, 0.0), 0.0)
	_check("a frame edge hit on a wall spins the quad about its vertical axis", spun.reason == ""
		and absf(spun.body[RB.RATE + 2]) > 0.5, "r %.3f rad/s" % spun.body[RB.RATE + 2])


## A broken prop on a motor driven at full throttle: the flight keeps running (no runaway shaft beyond the law's
## domain, no fault), and the damaged state replays bit for bit from the same checkpoint and tape.
func _broken_prop_flight() -> void:
	var runs: Array = []
	for run in 2:
		var s := _session("graded", {start = "air", altitude_m = 30.0})
		var envelope: Dictionary = s.checkpoint()
		var continuous: PackedFloat64Array = envelope.kernel.continuous.duplicate()
		continuous[Plant.C_HEALTH] = 0.0
		continuous[Plant.C_HEALTH + 1] = 0.6
		envelope.kernel.continuous = continuous
		var restored: bool = s.restore_checkpoint(envelope) and s.resume()
		_fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0), 2)
		var ticks := _fly(s, Fixtures.pilot(0.0, 0.0, 0.0, 1.0, 1), 600)
		var top := 0.0
		for i in 4:
			top = maxf(top, absf(s.sim.continuous[i]))
		_check("run %d: full throttle with a broken prop keeps the flight valid (no fault), shafts inside the domain" % run,
			restored and s.fault_reason.is_empty() and (ticks == 600 or not s.crash.is_empty())
			and top <= 1.5 * float(s.plant.prepared.rotor_law.max_speed_rad_s), "%d ticks, top %.0f rad/s, fault '%s'" % [ticks, top, s.fault_reason])
		runs.append(var_to_bytes(s.frame()))
		s.free()
	_check("the damaged flight replays bit for bit from the same checkpoint and tape", runs[0] == runs[1])


## Damaged props lose thrust in proportion to their health (h = 1 is the undamaged law).
func _thrust_scaling() -> void:
	var p := _plant()
	var body := RB.make_state(M.v3(0.0, 0.0, -20.0), M.v3(0.0, 0.0, 0.0), M.q_identity(), M.v3(0.0, 0.0, 0.0))
	var frame: Dictionary = p.initial_frame(body)
	for i in 4:
		frame.continuous[i] = p._hover_speed
	var whole: Dictionary = p._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	for i in 4:
		frame.continuous[Plant.C_HEALTH + i] = 0.5
	var half: Dictionary = p._evaluate(frame.body, frame.continuous, 0.0, frame.aux, frame.modes)
	_check("half-health props make half the thrust", absf(half.loads[2] - 0.5 * whole.loads[2]) < 1.0e-9 * absf(whole.loads[2]),
		"%s vs %s" % [half.loads[2], whole.loads[2]])


## DR-19d: a level touchdown at 10 m/s (props stopped, no pre-tilt) is resolved at the contact patch: the pad springs do
## not sink the quad deep or throw it into a spin, and the flight goes on.
func _flat_touchdown() -> void:
	var s := _session("graded", {start = "air", altitude_m = 0.3})
	var envelope: Dictionary = s.checkpoint()
	var state: PackedFloat64Array = envelope.kernel.state.duplicate()
	state[RB.VEL + 2] = 10.0
	envelope.kernel.state = state
	envelope.kernel.previous = state.duplicate()
	var continuous: PackedFloat64Array = envelope.kernel.continuous.duplicate()
	for i in 4:
		continuous[i] = 0.0
	envelope.kernel.continuous = continuous
	s.restore_checkpoint(envelope)
	s.resume()
	var rest := float(s.data.start.rest_height_m)
	var lowest := INF
	var max_tilt := 0.0
	for i in 720:
		s.tick_once(Fixtures.pilot(0.0, 0.0, 0.0, 0.0, 0))
		lowest = minf(lowest, -float(s.sim.state[RB.POS + 2]))
		var q := RB._att(s.sim.state)
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(1.0 - 2.0 * (q[1] * q[1] + q[2] * q[2]), -1.0, 1.0))))
	var q_end := RB._att(s.sim.state)
	var up_end := 1.0 - 2.0 * (q_end[1] * q_end[1] + q_end[2] * q_end[2])
	# The shipped CG sits 0.6 mm ahead of the feet's centre: the patch impulse pitches the bounce slightly (real
	# geometry, about 1.4 rad/s); the quad must not flip and must settle on its feet.
	_check("a level 10 m/s touchdown sinks under 6 mm, never flips (tilt < 35°) and settles on its feet",
		s.crash.is_empty() and rest - lowest < 0.006 and max_tilt < 35.0 and up_end > 0.95,
		"sink %.1f mm, max tilt %.1f°, final up %.3f" % [1000.0 * (rest - lowest), max_tilt, up_end])
	s.free()


## Kinetic energy of the airframe (J).
func _energy(p: RefCounted, body: PackedFloat64Array) -> float:
	var energy := 0.0
	var inertia: PackedFloat64Array = p.prepared.inertia_kg_m2
	for k in 3:
		energy += 0.5 * float(p.prepared.mass_kg) * body[RB.VEL + k] * body[RB.VEL + k] \
			+ 0.5 * inertia[k] * body[RB.RATE + k] * body[RB.RATE + k]
	return energy


func _events_of(result: Dictionary, kind: String) -> Array:
	var out: Array = []
	for event: Dictionary in result.events:
		if event.type == kind:
			out.append(event)
	return out


## DR-19f (§20): grazes and material. Expected values are closed forms and the declared constants.
func _grazes() -> void:
	var p := _plant()
	p.obstacle = Callable(self, "_wall")
	p.obstacle_class = Callable(self, "_class_hard")
	var level := M.q_identity()
	var front: float = p._frame_box_centre[0] + p._frame_box_half[0]
	var hover: float = p._hover_speed
	# A high-speed graze: 15 m/s along a wall, 1 m/s into it, props stopped (the frame alone).
	_wall_north = front - 0.005
	var graze := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(1.0, 15.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var grazed: Dictionary = p._graded_impacts(graze, graze, _speeds(p, graze, 0.0), 0.0)
	var scrapes := _events_of(grazed, "scrape")
	_check("a 15 m/s graze survives, slows along the wall (friction) and yaws the quad", grazed.reason == ""
		and grazed.body[RB.VEL + 1] < 15.0 and grazed.body[RB.VEL + 1] > 13.0 and absf(grazed.body[RB.RATE + 2]) > 0.1,
		"v_e %.3f r %.3f" % [grazed.body[RB.VEL + 1], grazed.body[RB.RATE + 2]])
	# Coulomb bound: the friction impulse is at most mu × the normal impulse (≈ m × (1 + e) × 1 m/s at the CG).
	var mass: float = p.prepared.mass_kg
	var normal_impulse: float = mass * (1.0 - grazed.body[RB.VEL])
	var friction_impulse: float = mass * (15.0 - grazed.body[RB.VEL + 1])
	_check("the graze's friction impulse stays within mu × the normal impulse (hard surface 0.5)",
		friction_impulse <= float(Plant.OBSTACLE_FRICTION.hard_terminal) * normal_impulse * (1.0 + 1.0e-9) + 1.0e-12,
		"%.4f vs %.4f" % [friction_impulse, normal_impulse])
	_check("the graze only removes energy", _energy(p, grazed.body) < _energy(p, graze))
	_check("a graze raises one scrape event at about the sliding speed and chips no prop", scrapes.size() == 1
		and absf(float(scrapes[0].slip_speed_mps) - 15.0) < 0.5 and _events_of(grazed, "prop_damage").is_empty(), str(grazed.events))
	var contact_after: PackedFloat64Array = p._box_support(M.v3(-1.0, 0.0, 0.0)).point
	_check("after the graze the contact still separates (friction never turns the rebound back into closing)",
		p._closing_speed(grazed.body, contact_after, M.v3(-1.0, 0.0, 0.0)) <= 1.0e-12)
	# Overlapping but moving away from the wall (no normal force): no friction, no scrape.
	var receding := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(-1.0, 15.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var left: Dictionary = p._graded_impacts(receding, receding, _speeds(p, receding, 0.0), 0.0)
	_check("a receding overlap keeps its velocity and raises no scrape", _events_of(left, "scrape").is_empty()
		and left.body.slice(RB.VEL, RB.RATE + 3) == receding.slice(RB.VEL, RB.RATE + 3))
	# A frame hit away from the props (the battery top on a roof at 4 m/s): an impact, but no prop is chipped.
	p.obstacle = Callable(self, "_ceiling")
	var top: float = p._frame_box_centre[2] - p._frame_box_half[2]
	_ceiling_down = -5.0 + top + 0.003
	var climb := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, -4.0), level, M.v3(0.0, 0.0, 0.0))
	var roofed: Dictionary = p._graded_impacts(climb, climb, _speeds(p, climb, hover), 0.0)
	_check("a 4 m/s battery hit on a roof is an impact that chips no prop (v2 chipped the two nearest)",
		roofed.reason == "" and _events_of(roofed, "impact").size() == 1 and _events_of(roofed, "prop_damage").is_empty(),
		str(roofed.events))
	# The same speed into the front face (at the front hubs' discs) chips the front props only.
	p.obstacle = Callable(self, "_wall")
	_wall_north = front - 0.005
	var nose := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(4.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var nosed: Dictionary = p._graded_impacts(nose, nose, _speeds(p, nose, hover), 0.0)
	var damaged := {}
	for event: Dictionary in _events_of(nosed, "prop_damage"):
		damaged[int(event.rotor)] = true
	var front_only := true
	for i: int in damaged:
		front_only = front_only and float(p.prepared.rotors[i].hub_frd[0]) > 0.0
	_check("a 4 m/s nose hit damages the front props only", nosed.reason == "" and damaged.size() == 2 and front_only, str(damaged))
	# Material and bite: a prop tip brushing foliage 3 mm deep at hover speed against a full bite into a hard wall.
	var rotor: Dictionary = p.prepared.rotors[0]
	for rotor_index in 4:
		if float(p.prepared.rotors[rotor_index].hub_frd[0]) > 0.0:
			rotor = p.prepared.rotors[rotor_index]
	var radius: float = 0.5 * float(rotor.diameter_m)
	var reach: float = float(rotor.hub_frd[0]) + radius
	var still := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(0.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var lone := _speeds(p, still, 0.0)
	var lone_index: int = p.prepared.rotors.find(rotor)
	lone[lone_index] = hover
	_class = "soft_foliage_impulse"
	p.obstacle_class = Callable(self, "_class_named")
	_wall_north = reach - 0.0045
	var brushed: Dictionary = p._graded_impacts(still, still, lone, 0.0)
	var expected_brush := 1.0 - Plant.PROP_WEAR_PER_TICK * float(Plant.PROP_MATERIAL.soft_foliage_impulse) * 0.0045 / Plant.PROP_FULL_BITE_M
	_check("a prop tip brushing leaves 4.5 mm deep loses 0.2 × 0.15 × (4.5 / 15) = 0.9 % (a full bite into a wall: 20 %)",
		absf(brushed.continuous[Plant.C_HEALTH + lone_index] - expected_brush) < 1.0e-9,
		str(brushed.continuous[Plant.C_HEALTH + lone_index]))
	_check("the brushing prop is braked and kicks the airframe (an obstacle prop strike)", brushed.continuous[lone_index] < hover
		and _kick_ok(p, still, brushed.body))
	# Break speed by material: 7 m/s into leaves keeps the prop (breaks above 6 / sqrt(0.15) = 15.5 m/s), into a hard
	# wall it breaks (above 6 m/s).
	_wall_north = reach - 0.01
	var fast := RB.make_state(M.v3(0.0, 0.0, -5.0), M.v3(7.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var leaves: Dictionary = p._graded_impacts(fast, fast, lone, 0.0)
	p.obstacle_class = Callable(self, "_class_hard")
	var hard: Dictionary = p._graded_impacts(fast, fast, lone, 0.0)
	_check("a 7 m/s prop strike into leaves wears the prop; into a hard wall it breaks it",
		leaves.continuous[Plant.C_HEALTH + lone_index] > 0.0 and hard.continuous[Plant.C_HEALTH + lone_index] == 0.0,
		"%.3f %.3f" % [leaves.continuous[Plant.C_HEALTH + lone_index], hard.continuous[Plant.C_HEALTH + lone_index]])
	# A skid on the ground: a contact point already touching and sliding at 8 m/s raises a scrape event.
	var q := _plant()
	var rest_height: float = q._frame_box_centre[2] + q._frame_box_half[2] # the lowest foot (FRD z)
	var skid := RB.make_state(M.v3(0.0, 0.0, -rest_height + 0.002), M.v3(8.0, 0.0, 0.0), level, M.v3(0.0, 0.0, 0.0))
	var skidded: Dictionary = q._graded_impacts(skid, skid, _speeds(q, skid, 0.0), 0.0)
	var ground_scrapes := _events_of(skidded, "scrape")
	_check("an 8 m/s skid on the ground raises a ground scrape event", ground_scrapes.size() == 1
		and str(ground_scrapes[0].surface) == "ground" and absf(float(ground_scrapes[0].slip_speed_mps) - 8.0) < 0.1, str(skidded.events))
	# A sustained skid reports once per SCRAPE_EVENT_PERIOD_S: 24 ticks at 240 Hz give one event per 0.1 s.
	var reported := 0
	for tick in range(1, 241):
		reported += _events_of(q._graded_impacts(skid, skid, _speeds(q, skid, 0.0), float(tick) / 240.0), "scrape").size()
	_check("a one-second skid reports ten scrapes, not 240 (bounded event and flight-log volume)", reported == 10, str(reported))
	# A fast skid-landing: the touchdown impulse carries ground friction (contacts.friction), slowing the slide.
	var above := RB.make_state(M.v3(0.0, 0.0, -rest_height - 0.05), M.v3(10.0, 0.0, 6.0), level, M.v3(0.0, 0.0, 0.0))
	var landing := RB.make_state(M.v3(0.0, 0.0, -rest_height + 0.004), M.v3(10.0, 0.0, 6.0), level, M.v3(0.0, 0.0, 0.0))
	var landed: Dictionary = q._graded_impacts(above, landing, _speeds(q, landing, 0.0), 0.0)
	_check("a 6 m/s skid-landing at 10 m/s loses forward speed to ground friction and only energy",
		landed.reason == "" and landed.body[RB.VEL] < 10.0 and landed.body[RB.VEL] > 0.0 and _energy(q, landed.body) < _energy(q, landing),
		"v_n %.3f" % landed.body[RB.VEL])


## Audit 2026-11-17: a collision world installed after prepare (paused) also replaces the class query, so the graded
## law reads the new world's terminal speeds, friction and materials.
func _world_swap() -> void:
	var s := _session("graded")
	var before: bool = s.plant.obstacle_class.is_valid()
	s.pause()
	var proxies: Array[Dictionary] = []
	CollisionWorld._add_box_at_down(proxies, "hedge", "hedge", "hedge", "soft_foliage_impulse", 3.0, 0.0, -1.0, 4.0, 2.0, 0.5, 0.0)
	var world := {format = CollisionWorld.FORMAT, identity = "graded-swap", cell_size_m = CollisionWorld.CELL_SIZE_M,
		proxies = proxies, bins = CollisionWorld._build_bins(proxies)}
	var installed: bool = s.set_collision_world(world)
	_check("a world installed after prepare refreshes the class query (a hedge reads as foliage)", not before and installed
		and s.plant.obstacle_class.is_valid() and str(s.plant.obstacle_class.call(3.0, 0.0, -1.0)) == "soft_foliage_impulse")
	s.free()

