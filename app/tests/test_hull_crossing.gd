# CR-01b: independent analytic roots plus actual session/renderer interpolation contracts.
extends SceneTree
const Crossings = preload("res://physics/hull_crossing.gd")
const Snapshot = preload("res://physics/impact_snapshot.gd")
const Session = preload("res://sim/flight_session.gd")
const Sim = preload("res://sim/simulation.gd")
const M = preload("res://physics/math3d.gd")
const RB = preload("res://physics/rigid_body.gd")
var _failures: int = 0
var _count: int = 0

func _check(label: String, ok: bool) -> void:
	_count += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)

func _state(down: float, q: PackedFloat64Array = M.q_identity()) -> PackedFloat64Array:
	return RB.make_state(M.v3(10, 20, down), M.v3(3, 4, 2), q, M.v3(1, 2, 3))

func _initialize() -> void:
	var a: PackedFloat64Array = _state(-2)
	var b: PackedFloat64Array = _state(2)
	var hull: PackedFloat64Array = PackedFloat64Array([0, 0, 1, 0, 0, 0])
	var result: Crossings.Result = Crossings.reconstruct(a, b, hull)
	_check("linear descent exact quarter tick", result.available and absf(result.fraction-.25) < 1e-14)
	_check("earliest point selected", result.point_index == 0)
	_check("reconstructed point on plane", result.available and M.norm(M.sub(result.point_ned, M.v3(10,20,0))) < 1e-12)
	_check("CG pose preserves lever arm", result.available and result.position_ned[2] == -1)
	_check("method explicitly interpolation estimate", result.method == "position-lerp-shortest-nlerp-v1")
	_check("inputs unchanged", a == _state(-2) and b == _state(2) and hull[2] == 1)
	for scale in [1e-6, 1e6]:
		var scaled: Crossings.Result = Crossings.reconstruct(_state(-2*scale), _state(2*scale), PackedFloat64Array([0, 0, scale]))
		_check("length scaling %.6f" % scale, scaled.available and absf(scaled.fraction-.25) < 1e-13)

	# 180-degree roll: y-tip enters at sin(theta)=.8, tan(theta/2)=.5 => f=1/3.
	# The negative-z point enters later at tan(theta/2)=3 => f=3/4 and is down at tick end.
	a = _state(-.8)
	b = _state(-.8, M.quat(0,1,0,0))
	hull = PackedFloat64Array([0,0,-1, 0,1,0])
	result = Crossings.reconstruct(a,b,hull)
	_check("clear-at-end point can be first crossing", result.available and result.point_index == 1)
	_check("rotating enter/exit pair exact first root", result.available and absf(result.fraction-1.0/3.0) < 1e-12)
	var later: Crossings.Result = Crossings.reconstruct(a,b,PackedFloat64Array([0,0,-1]))
	_check("rotating endpoint bracket differs from depth chord", later.available and absf(later.fraction-.75) < 1e-12 and absf(later.fraction-.9) > .1)
	_check("rotating contact point residual", result.available and absf(result.point_ned[2]) < 1e-12)
	var sim: Node = Sim.new()
	sim.previous = a.duplicate()
	sim.state = b.duplicate()
	var pose: PackedFloat64Array = sim.interpolated(result.fraction)
	_check("pose matches existing renderer interpolation", pose.slice(RB.POS,RB.POS+3) == result.position_ned and pose.slice(RB.ATT,RB.ATT+4) == result.attitude)
	sim.free()

	a = _state(-.5)
	b = _state(-.5,M.q_from_euler(0,0,PI/2))
	hull = PackedFloat64Array([0,1,0])
	result = Crossings.reconstruct(a,b,hull)
	for i in 4:
		b[RB.ATT+i] *= -1
	var antipodal: Crossings.Result = Crossings.reconstruct(a,b,hull)
	_check("quaternion sign equivalent shortest path", antipodal.available and result.available and antipodal.fraction == result.fraction and antipodal.attitude == result.attitude)
	result = Crossings.reconstruct(_state(-1),_state(0),PackedFloat64Array([0,0,0]))
	_check("endpoint contact retained", result.available and result.fraction == 1)
	result = Crossings.reconstruct(_state(-1),_state(1),PackedFloat64Array([1,0,0, -1,0,0]))
	_check("simultaneous contacts select first data index", result.available and result.point_index == 0)
	result = Crossings.reconstruct(_state(0),_state(1),PackedFloat64Array([0,0,0]))
	_check("prior contact is unknown, not fraction zero", not result.available and result.reason == "previous_pose_in_contact")
	result = Crossings.reconstruct(_state(-2),_state(-1),PackedFloat64Array([0,0,0]))
	_check("clear interval has no crossing", not result.available and result.reason == "no_crossing")
	result = Crossings.reconstruct(_state(-1),_state(-1,M.quat(0,1,0,0)),PackedFloat64Array([0,1,0]))
	_check("tangent cannot claim a resolved crossing", not result.available and result.reason == "near_tangent_or_roundoff")
	var invalid: Array[PackedFloat64Array] = [PackedFloat64Array(), _state(NAN), _state(-1,M.quat(0,0,0,0)),_state(-1,M.quat(2,0,0,0))]
	for s in invalid:
		_check("invalid state refused", not Crossings.reconstruct(s,_state(1),PackedFloat64Array([0,0,0])).available)
	for h in [PackedFloat64Array(),PackedFloat64Array([0,0]),PackedFloat64Array([0,NAN,0])]:
		_check("invalid hull refused", not Crossings.reconstruct(_state(-1),_state(1),h).available)
	_check("overflowed coefficients unavailable", not Crossings.reconstruct(_state(-1e308),_state(1e308),PackedFloat64Array([0,0,0])).available)
	_mixed_attitudes()
	_roots()
	result = Crossings.reconstruct(_state(-1),_state(1),PackedFloat64Array([0,0,0, 0,0,2e-13]))
	_check("numerically simultaneous contacts keep data order", result.available and result.point_index == 0)
	result = Crossings.reconstruct(_state(-1),_state(1),PackedFloat64Array([0,0,0, 0,0,2e-10]))
	_check("resolved earlier contact wins", result.available and result.point_index == 1)
	result = Crossings.reconstruct(_state(-1),_state(1),PackedFloat64Array([1e200,0,0]))
	_check("overflowed residual scale refused", not result.available and result.reason == "nonfinite_reconstruction")
	_session()
	print("%d checks, %d failed" % [_count,_failures])
	quit(1 if _failures else 0)

func _roots() -> void:
	# Manufactured polynomials have independently specified roots; positive leading cubic.
	for roots in [[.2,.4,.7],[.1,.10001,.9],[.01,.5,.99]]:
		var x: float = roots[0]
		var y: float = roots[1]
		var z: float = roots[2]
		var c: PackedFloat64Array = PackedFloat64Array([-x*y*z,x*y+x*z+y*z,-x-y-z,1])
		var root: Dictionary = Crossings._first_root(c)
		_check("first of three cubic roots %s" % str(roots), not root.ambiguous and absf(root.fraction-x) < 1e-9)
	var narrow: Dictionary = Crossings._first_root(PackedFloat64Array([-.25+1e-8,1,-1,0]))
	_check("narrow same-sign-endpoint crossing is not missed", not narrow.ambiguous and absf(narrow.fraction-.4999) < 1e-9)
	var tangent: Dictionary = Crossings._first_root(PackedFloat64Array([-.25,1,-1,0]))
	_check("exact polynomial tangent unknown", tangent.ambiguous)
	var clear: Dictionary = Crossings._first_root(PackedFloat64Array([-.25-1e-8,1,-1,0]))
	_check("near tangent but clearly separated stays clear", not clear.ambiguous and clear.fraction < 0)

func _session() -> void:
	var session: Node = Session.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	session.sim.previous = _state(-.3)
	session.sim.state = _state(-.01)
	session.sim.tick = 1
	session.sim.set_paused(false)
	var saved: PackedFloat64Array = session.sim.state.duplicate()
	session._physics_process(session.sim.dt())
	_check("actual crash stores separate crossing estimate", not session.crash.is_empty() and session.crash.impact.crossing != null and session.crash.impact.crossing.available)
	_check("detected state and simulation remain unchanged", session.crash.impact.detected_state == saved and session.sim.state == saved and session.sim.tick == 1)
	var hit: Snapshot.Snapshot = session.crash.impact
	session.reset()
	_check("reset clears snapshot, retained pose remains owned", session.crash.is_empty() and hit.crossing.available and hit.detected_state == saved)
	session.free()

func _mixed_attitudes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 10107
	var sim: Node = Sim.new()
	var worst: float = 0.0
	var valid: bool = true
	# Translation dominates rotation: lever < .347 m, descent 4 m per fraction.
	# Reference evaluates the existing pose interpolation directly, with no polynomial.
	for case_index in 100:
		var a: PackedFloat64Array = _state(-2, M.q_from_euler(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI)))
		var b: PackedFloat64Array = _state(2, M.q_from_euler(rng.randf_range(-PI,PI),rng.randf_range(-PI,PI),rng.randf_range(-PI,PI)))
		var r: PackedFloat64Array = M.v3(rng.randf_range(-.2,.2),rng.randf_range(-.2,.2),rng.randf_range(-.2,.2))
		sim.previous = a
		sim.state = b
		var lo: float = 0.0
		var hi: float = 1.0
		for iteration in 50:
			var mid: float = (lo+hi)*.5
			var pose: PackedFloat64Array = sim.interpolated(mid)
			var down: float = pose[RB.POS+2] + M.q_rotate(RB._att(pose),r)[2]
			if down >= 0:
				hi = mid
			else:
				lo = mid
		var result: Crossings.Result = Crossings.reconstruct(a,b,r)
		valid = valid and result.available
		if result.available:
			worst = maxf(worst, absf(result.fraction-hi))
	_check("100 mixed attitudes match direct pose root", valid and worst < 1e-12)
	sim.free()
