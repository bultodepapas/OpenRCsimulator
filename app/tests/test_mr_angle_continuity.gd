## A36 R2-F02: the Angle-mode rate target must change continuously with attitude. The R2 witness (roll 90 deg, yaw 0,
## pitch 78.462 vs 78.464 deg) once switched the heading reference by 90 deg and the pre-gain error by 1.2467 rad.
## Gains are left unclipped here so the comparison sees the raw error.
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Fixtures := preload("res://tests/mr_fixtures.gd")
const Plant := preload("res://physics/multirotor/controlled_plant.gd")
const FC := preload("res://physics/multirotor/flight_controller.gd")
const Rates := preload("res://physics/multirotor/rates.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _body(q: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -50.0), M.v3(0.0, 0.0, 0.0), q, M.v3(0.0, 0.0, 0.0))


func _target(config: Dictionary, q: PackedFloat64Array, roll := 0.0, pitch := 0.0) -> PackedFloat64Array:
	return FC._angle_rate_target(config, _body(q), roll, pitch)


func _distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]))


func _run() -> void:
	var made: Dictionary = Plant.create(Fixtures.lab(), Rates.default_profile(), FC.THROTTLE_ABSOLUTE)
	if not made.get("ok", false):
		check("laboratory plant prepares", false, made.get("message", ""))
		_finish()
		return
	var config: Dictionary = made.plant.config.duplicate(true)
	config.angle_rate_limit = 1.0e9
	var gain := float(config.angle_gain)
	# R2 witness across the old 0.2 nose-projection threshold.
	var below: PackedFloat64Array = _target(config, M.q_from_euler(0.0, deg_to_rad(78.462), PI / 2.0))
	var above: PackedFloat64Array = _target(config, M.q_from_euler(0.0, deg_to_rad(78.464), PI / 2.0))
	var jump := _distance(below, above) / gain
	check("the R2 witness no longer jumps (pre-gain error change <= 1e-4 rad for 0.002 deg)", jump < 1.0e-4,
		"%.9f rad (was 1.246702)" % jump)
	# Random attitudes, a 1e-6 rad rotation apart: the change is of that order away from the declared inverted set.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2602
	var worst := 0.0
	var cases := 0
	for i in 4000:
		var q := M.q_from_euler(rng.randf_range(-PI, PI), rng.randf_range(-PI / 2.0, PI / 2.0), rng.randf_range(-PI, PI))
		var roll := rng.randf_range(-1.0, 1.0)
		var pitch := rng.randf_range(-1.0, 1.0)
		var down: PackedFloat64Array = M.q_rotate(M.q_conj(q), M.v3(0.0, 0.0, 1.0))
		var tilt := float(config.angle_max_tilt)
		var aim := M.v3(-sin(pitch * tilt), sin(roll * tilt) * cos(pitch * tilt), cos(roll * tilt) * cos(pitch * tilt))
		if M.dot(down, aim) < -0.99:
			continue # within ~8 deg of the declared singular (fully opposite) set
		var nudge := M.q_from_euler(rng.randf_range(-1.0, 1.0) * 1.0e-6, rng.randf_range(-1.0, 1.0) * 1.0e-6,
			rng.randf_range(-1.0, 1.0) * 1.0e-6)
		var a := _target(config, q, roll, pitch)
		var b := _target(config, M.q_mul(q, nudge), roll, pitch)
		worst = maxf(worst, _distance(a, b) / gain)
		cases += 1
	check("random attitude sweep evaluates", cases > 3000, cases)
	check("a 1e-6 rad attitude change moves the pre-gain error by < 1e-4 rad everywhere sampled", worst < 1.0e-4,
		"%s rad over %d cases" % [str(worst), cases])
	# Small-angle agreement with the attitude error: a 5 deg roll at zero stick asks for a 5 deg roll-back.
	var rolled := _target(config, M.q_from_euler(0.8, 0.0, deg_to_rad(5.0)))
	check("a small roll is corrected about the roll axis by its own angle", absf(rolled[0] / gain + deg_to_rad(5.0)) < 1.0e-12
		and absf(rolled[1]) < 1.0e-12, rolled)
	var pitched := _target(config, M.q_from_euler(-2.0, deg_to_rad(4.0), 0.0))
	check("a small nose-up pitch is corrected nose down by its own angle", absf(pitched[1] / gain + deg_to_rad(4.0)) < 1.0e-12
		and absf(pitched[0]) < 1.0e-12, pitched)
	var held := _target(config, M.q_from_euler(1.3, 0.0, 0.5 * float(config.angle_max_tilt)), 0.5, 0.0)
	check("half roll stick at half the tilt limit, any heading, asks for nothing", absf(held[0]) < 1.0e-12 and absf(held[1]) < 1.0e-12,
		held)
	var inverted := _target(config, M.q_from_euler(0.7, 0.0, PI))
	check("exactly inverted uses the declared roll-axis recovery", absf(inverted[0] / gain - PI) < 1.0e-12 and inverted[1] == 0.0,
		inverted)
	_finish()


func _finish() -> void:
	print("multirotor Angle continuity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
