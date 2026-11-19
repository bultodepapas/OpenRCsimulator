## Draft, source-level diagnostic for the crash director; copy into a disposable
## app res:// path before running with the project's checked Godot runner.
## No contact or flight tick is simulated: both cases are prescribed snapshots.
## The inert Wreck/Effects subclasses isolate Director._start's actual report.
extends SceneTree

const Director := preload("res://render/crash/director.gd")
const PresentationContext := preload("res://render/crash/presentation_context.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const Simulation := preload("res://sim/simulation.gd")
const ImpactSnapshot := preload("res://physics/impact_snapshot.gd")
const RB := preload("res://physics/rigid_body.gd")


class QuietWreck extends "res://render/crash/wreck.gd":
	var starts := 0
	func start(_pose: Transform3D, _velocity: Vector3, _angular_velocity: Vector3, _severity: Dictionary) -> void:
		starts += 1


class QuietEffects extends "res://render/crash/effects.gd":
	var starts := 0
	func start(_point: Vector3, _velocity: Vector3, _severity: Dictionary, _kerosene: float, _hot: bool, _wind: Vector3) -> void:
		starts += 1
	func apply_energy(_outcome: Dictionary) -> void:
		pass


var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(label: String, passed: bool, detail: String = "") -> void:
	checks += 1
	if not passed:
		failures += 1
	print("PROBE ", label, " ", "PASS" if passed else "FAIL", " ", detail)


func _run() -> void:
	# Constant mass and diagonal inertia are shared by both snapshots. The contact
	# arm (1,0,0) makes the normal affect effective mass as well as closing speed.
	var session := FlightSession.new()
	var sim := Simulation.new()
	sim.mass = 2.0
	sim.inertia = PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])
	sim.modes = PackedInt64Array([0])
	sim.tick = 1
	session.sim = sim
	# No aircraft load or tick is performed; this minimal model supplies only
	# Director._start's read-only fields and suppresses unrelated propulsion paths.
	session.aircraft = {ok = false, model = {
		propulsion = {kind = "electric"}, reference = {b = 2.0, c = 1.0},
		start_speed = 10.0, crash_hull_components = PackedStringArray(["nose"]),
	}}
	var source := Node3D.new()
	var bindings := PresentationContext.ModelBindings.new()
	bindings.root = source
	bindings.empty = false
	var context := PresentationContext.new()
	context.session = session
	context.model_bindings = bindings
	context.field = {} # surface_at falls back to rough: transfer 0.88, friction 0.55.
	context.cg_model = Vector3.ZERO
	context.pose_provider = func() -> Dictionary:
		return {basis = Basis.IDENTITY, pos = Vector3(0.0, 2.0, 0.0)}
	context.wind_provider = func(_t: float) -> Vector3: return Vector3.ZERO
	var director := Director.new()
	director.context = context
	director._audio_enabled = false
	var wreck := QuietWreck.new()
	var effects := QuietEffects.new()
	director.wreck = wreck
	director.effects = effects

	var velocity := PackedFloat64Array([7.0, 0.0, 7.2])
	var state := RB.make_state(PackedFloat64Array([0.0, 0.0, -2.0]), velocity,
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var hull := PackedFloat64Array([1.0, 0.0, 0.0])
	var snapshot := ImpactSnapshot.hull_point(state, 1, hull, 0)
	_check("snapshot carries the prescribed point and velocity", snapshot.has_kinematics
		and snapshot.body_point == hull and snapshot.velocity_ned == velocity and snapshot.soft_rule.is_empty())
	_check("constant live mass sample is available", bool(session.mass_properties().get("ok", false)))
	session.crash = {impact = snapshot}

	# Flat control, then the same prescribed state and point with a 45-degree
	# upward normal, as populated by FlightSession._rc_track_hit. The state is
	# nearly tangent to that slope and closes at 0.2/sqrt(2) m/s.
	snapshot.normal_ned = PackedFloat64Array([0.0, 0.0, -1.0])
	director._start()
	var flat: Dictionary = director.report.duplicate(true)
	snapshot.normal_ned = PackedFloat64Array([1.0 / sqrt(2.0), 0.0, -1.0 / sqrt(2.0)])
	director._start()
	var slope: Dictionary = director.report.duplicate(true)
	_check("both starts reach the report and presentation handoff", wreck.starts == 2 and effects.starts == 2
		and bool(flat.get("valid", false)) and bool(slope.get("valid", false)))
	_check("both cases retain rough surface, component and mass", flat.get("surface") == "rough"
		and slope.get("surface") == "rough" and flat.get("component") == "nose"
		and slope.get("component") == "nose" and float(flat.get("mass_kg", -1.0)) == 2.0
		and float(slope.get("mass_kg", -1.0)) == 2.0)

	# Independent analytic point-mass oracle: 1/m_eff = 1/m + (r x n)^T I^-1 (r x n).
	# With r=(1,0,0), m=2 and Iyy=1, flat m_eff=2/3 and slope m_eff=1.
	var flat_eff := 2.0 / 3.0
	var slope_eff := 1.0
	var flat_normal_energy := 0.5 * flat_eff * 7.2 * 7.2
	var slope_vn := 0.2 / sqrt(2.0)
	var slope_normal_energy := 0.5 * slope_eff * slope_vn * slope_vn
	var detail := "flat eff=%.6f energy=%.6f class=%d; slope eff=%.6f energy=%.6f class=%d" % [
		float(flat.get("effective_mass_kg", -1.0)), float(flat.get("normal_energy_j", -1.0)), int(flat.get("class", -1)),
		float(slope.get("effective_mass_kg", -1.0)), float(slope.get("normal_energy_j", -1.0)), int(slope.get("class", -1))]
	_check("flat control uses vertical effective mass and normal energy", absf(float(flat.get("effective_mass_kg", -1.0)) - flat_eff) < 1.0e-6
		and absf(float(flat.get("normal_energy_j", -1.0)) - flat_normal_energy) < 1.0e-6
		and int(flat.get("class", -1)) == 2, detail)
	# These are desired-behavior assertions, expected to fail on the reviewed main.
	_check("slope report uses effective mass along the supplied slope normal", absf(float(slope.get("effective_mass_kg", -1.0)) - slope_eff) < 1.0e-6, detail)
	_check("slope report uses the contact-normal energy", absf(float(slope.get("normal_energy_j", -1.0)) - slope_normal_energy) < 1.0e-6, detail)
	_check("nearly tangent slope input does not reuse the flat C2 grade", int(slope.get("class", -1)) == 0, detail)

	director.wreck = null
	director.effects = null
	session.sim = null
	wreck.free()
	effects.free()
	director.free()
	source.free()
	sim.free()
	session.free()
	print("SLOPE_SEVERITY_PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
