# SF-05: stiff-contact substepping. The loader derives the substep count that keeps the E1 rule ω·dt < 0.1 per
# substep; the kernel integrates n full RK4 pieces of dt/n while a wheel is within reach of the ground. Known answers:
# a 240 Hz tick with two substeps is byte-identical to two 480 Hz ticks, it refines toward a 960 Hz reference better
# than a single stiff step, and a drop never gains energy. The current fleet derives one substep and is unchanged.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Sim := preload("res://sim/simulation.gd")
const VehicleModel := preload("res://sim/vehicle_model.gd")
const Ground := preload("res://physics/ground_contact.gd")
const AD := preload("res://physics/aircraft_data.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const AircraftCatalog := preload("res://app_state/aircraft_catalog.gd")

const PATH := "res://data/aircraft/jensen_ugly_stik_60.json"
const G := 9.80665

var _count := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_run.call_deferred()


func _stiffened(factor: float) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for contact in raw.landing_gear.contacts:
		contact.stiffness.value = float(contact.stiffness.value) * factor
		contact.damping.value = float(contact.damping.value) * sqrt(factor) # keeps each damping ratio
	return AD.validate_and_derive(raw)


func _level(alt: float, vel_down := 0.0) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -alt), M.v3(0.0, 0.0, vel_down), M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _run() -> void:
	var base: Dictionary = AD.load_file(PATH)
	_check("Ugly Stik loads with one derived substep", base.ok and int(base.model.landing_gear.substeps) == 1,
		str(base.model.landing_gear.get("substeps")))
	var stiff: Dictionary = _stiffened(4.0)
	_check("four times stiffer gear loads with two derived substeps (ω·dt %.3f)" % (float(stiff.model.landing_gear.heave_omega) / 240.0) if stiff.ok else "stiff gear loads",
		stiff.ok and int(stiff.model.landing_gear.substeps) == 2, str(stiff.get("errors", [])) + " " + str(stiff.model.landing_gear.get("substeps") if stiff.ok else ""))
	var extreme: Dictionary = _stiffened(100.0)
	_check("a hundred times stiffer gear is refused with the substep count in the message",
		not extreme.ok and str(extreme.errors).contains("substeps per tick"), str(extreme.get("errors", [])))
	if not stiff.ok:
		_finish()
		return
	var model: Dictionary = stiff.model
	var gear: Dictionary = model.landing_gear
	var single: Dictionary = gear.duplicate(true)
	single.substeps = 1
	# Within-reach rule: airborne the plan is one piece, near the ground it is the derived count.
	var dt := 1.0 / 240.0
	_check("substeps are one far above the ground", Ground.substeps(_level(5.0), gear, dt) == 1)
	_check("substeps engage within reach of the ground", Ground.substeps(_level(0.2), gear, dt) == 2)
	_check("a fast sink engages substeps earlier by the distance covered in a tick",
		Ground.substeps(_level(float(gear.reach) + 0.06, 0.0), gear, dt) == 1 and Ground.substeps(_level(float(gear.reach) + 0.06, 5.0), gear, dt) == 2)

	var touch := -INF
	for c in Ground.compressions(_level(1.0), gear):
		touch = maxf(touch, 1.0 + c)
	var start := _level(touch + 0.002, 1.5)
	var a: Dictionary = _drop(model, gear, start, 0.4, 240)
	var b: Dictionary = _drop(model, single, start, 0.4, 480)
	_check("240 Hz with two substeps equals two 480 Hz ticks byte for byte", a.trajectory == b.trajectory and a.s.to_byte_array() == b.s.to_byte_array(),
		"|Δz| %s" % String.num_scientific(absf(a.s[RB.POS + 2] - b.s[RB.POS + 2])))
	var c: Dictionary = _drop(model, single, start, 0.4, 240)
	var r: Dictionary = _drop(model, single, start, 0.4, 960)
	var err_sub: float = absf(a.s[RB.POS + 2] - r.s[RB.POS + 2]) + absf(a.s[RB.VEL + 2] - r.s[RB.VEL + 2])
	var err_single: float = absf(c.s[RB.POS + 2] - r.s[RB.POS + 2]) + absf(c.s[RB.VEL + 2] - r.s[RB.VEL + 2])
	_check("substeps refine toward the 960 Hz reference better than one stiff step", err_sub < err_single,
		"substeps %s, single %s" % [String.num_scientific(err_sub), String.num_scientific(err_single)])
	_check("the drop never gains energy in a tick (≤ 1e-6 J)", a.max_gain < 1e-6, String.num_scientific(a.max_gain) + " J")
	_check("the drop rebounds below its release height", a.highest < touch + 0.002, "%.4f m" % a.highest)
	_check("the kernel reports the tick's substeps only while in reach", a.first_substeps == 2 and a.airborne_substeps == 1)

	# The session installs the rule; the catalog Stik derives one substep airborne and on the runway.
	var session: Node = FlightSession.new()
	session.input_enabled = false
	session.physics_enabled = false
	session.setup(str(AircraftCatalog.entry("jensen-das-ugly-stik-60").data))
	root.add_child(session)
	if session.is_flyable():
		session.reset()
		var body: PackedFloat64Array = session.sim.state
		_check("the fixed-wing model declares its substep rule and the catalog Stik plans one piece",
			session.sim.model.substeps.is_valid() and int(session.sim.model.substeps.call(body, session.sim.continuous, 0.0)) == 1)
		session.sim.step()
		_check("a catalog tick still steps", session.sim.fault_reason.is_empty() and session.sim.tick == 1, session.sim.fault_reason)
	else:
		_check("catalog Stik flies", false, session.pause_reason)
	session.free()
	_finish()


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


## Gear only (no air) from `start` for `seconds` at `hz` through the kernel with the gear's substep rule.
func _drop(model: Dictionary, gear: Dictionary, start: PackedFloat64Array, seconds: float, hz: int) -> Dictionary:
	var saved := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = hz
	var sim: Node = Sim.new()
	var vehicle := VehicleModel.new()
	vehicle.loads = func(s: PackedFloat64Array, _t: float) -> PackedFloat64Array:
		var g := Ground.loads(s, gear)
		return g if not g.is_empty() else PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	vehicle.substeps = func(body: PackedFloat64Array, _c: PackedFloat64Array, _t: float) -> int:
		return Ground.substeps(body, gear, 1.0 / float(hz))
	sim.set_model(vehicle)
	sim.mass = model.mass_kg
	sim.inertia = model.inertia.duplicate()
	sim.aux = PackedFloat64Array()
	sim.reset(start)
	var out := { max_gain = -INF, highest = -INF, first_substeps = int(vehicle.substeps.call(start, PackedFloat64Array(), 0.0)),
		airborne_substeps = int(vehicle.substeps.call(_level(5.0), PackedFloat64Array(), 0.0)), trajectory = PackedByteArray() }
	var e_prev := _energy(sim.state, sim.mass, sim.inertia, gear)
	var sample_every: int = hz / 240
	for i in roundi(seconds * hz):
		sim.step()
		if (i + 1) % sample_every == 0:
			out.trajectory.append_array(sim.state.to_byte_array())
		out.highest = maxf(out.highest, -sim.state[RB.POS + 2])
		var e := _energy(sim.state, sim.mass, sim.inertia, gear)
		out.max_gain = maxf(out.max_gain, e - e_prev)
		e_prev = e
	out.s = sim.state.duplicate()
	out.fault = sim.fault_reason
	sim.free()
	Engine.physics_ticks_per_second = saved
	return out


func _energy(s: PackedFloat64Array, mass: float, j: PackedFloat64Array, gear: Dictionary) -> float:
	var v := M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2])
	var w := M.v3(s[RB.RATE], s[RB.RATE + 1], s[RB.RATE + 2])
	return 0.5 * mass * M.dot(v, v) + 0.5 * M.dot(w, RB.inertia_mul(j, w)) - mass * G * s[RB.POS + 2] + Ground.spring_energy(s, gear)
