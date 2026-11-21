## A36 R5-F01: cyclic trim must not move the applied swash angles outside the linkage's feasible set. Every applied
## (collective, forward, right) triple is mapped back through the 120-degree mixer independently of the production
## code and must need servo positions within [-1, 1]. Below saturation the trimmed result keeps the original
## angle-space sum bit for bit; at full collective a nonzero trim is now allocated within travel.
extends SceneTree

const Electronics := preload("res://physics/rotorcraft/electronics.gd")
const Fixture := preload("res://tests/test_heli_flight.gd")

const TOLERANCE := 1.0e-12

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


## Independent inverse: servo positions [front, rear-right, rear-left] needed for applied angles.
func _required_servos(output: Dictionary, linkage: Dictionary) -> PackedFloat64Array:
	var c: float = float(output.collective_75_rad) / float(linkage.collective_rad_per_unit)
	var l: float = float(output.cyclic_forward_rad) / float(linkage.longitudinal_rad_per_unit)
	var r: float = float(output.cyclic_right_rad) / float(linkage.lateral_rad_per_unit)
	var half_root_three := sqrt(3.0) / 2.0
	return PackedFloat64Array([c + l, c - 0.5 * l + half_root_three * r, c - 0.5 * l - half_root_three * r])


func _feasible(servos: PackedFloat64Array) -> bool:
	for value in servos:
		if absf(value) > 1.0 + TOLERANCE:
			return false
	return true


func _run() -> void:
	var prepared: Dictionary = Electronics.prepare(Fixture.electronics_parameters())
	check("electronics fixture prepares", prepared.ok, prepared.get("message", ""))
	if not prepared.ok:
		_finish()
		return
	var model: Dictionary = prepared.model
	var linkage: Dictionary = model.linkage
	var state: PackedFloat64Array = Fixture.state_at_hover()
	# R5 witness: full collective (pitch curve 1.0 -> targets [1, 1, 1]) with the stock air-start trim biases.
	var witness_trim := {"cyclic_forward_bias_rad": -0.000390410174688138, "cyclic_right_bias_rad": 0.00180194001566469}
	var full := PackedFloat64Array([0.0, 0.0, 0.0, 1.0])
	var direct: Dictionary = Electronics.evaluate(model, state, full, "normal", false, witness_trim)
	check("full-collective trimmed evaluation succeeds", direct.ok, direct.get("message", ""))
	if direct.ok:
		var servos := _required_servos(direct, linkage)
		check("R5 witness applied angles need servo travel within [-1, 1]", _feasible(servos), servos)
		check("R5 witness reports the clamped trimmed allocation", direct.servo_travel_limited
			and _feasible(direct.swash_servo_targets), direct.swash_servo_targets)
		var reconstructed := _required_servos(direct, linkage)
		var targets: PackedFloat64Array = direct.swash_servo_targets
		var agrees := true
		for i in 3:
			agrees = agrees and absf(reconstructed[i] - targets[i]) < 1.0e-12
		check("reported servo targets reproduce the applied angles", agrees, [reconstructed, targets])
		# Per-servo end stops are the linkage's physical travel law (also used for pilot sticks): at a stop the achieved
		# cyclic is whatever the clamped triple produces, within the declared cyclic limit and below full collective.
		check("full-collective allocation stays within cyclic limit and collective travel",
			absf(float(direct.cyclic_forward_rad)) <= float(linkage.cyclic_max_rad)
			and absf(float(direct.cyclic_right_rad)) <= float(linkage.cyclic_max_rad)
			and float(direct.collective_75_rad) < 0.22 and float(direct.collective_75_rad) > 0.21,
			[direct.collective_75_rad, direct.cyclic_forward_rad, direct.cyclic_right_rad])
	# Sweep collective, stick and trim, both laws of evaluation, trainer off/on: every result stays feasible.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5101
	var infeasible := 0
	var mismatched := 0
	var cases := 0
	for index in 600:
		var sticks := PackedFloat64Array([rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), 0.0,
			rng.randf_range(-1.0, 1.0)])
		if index % 5 == 0:
			sticks[3] = 1.0 if index % 10 == 0 else -1.0
		var trim := {"cyclic_forward_bias_rad": rng.randf_range(-0.06, 0.06),
			"cyclic_right_bias_rad": rng.randf_range(-0.06, 0.06)}
		var trainer := index % 3 == 0
		var safe: Dictionary = Electronics.evaluate(model, state, sticks, "normal" if index % 2 == 0 else "idle_up", trainer, trim)
		var fast: Dictionary = Electronics.fast_evaluate(model, state, sticks, "normal" if index % 2 == 0 else "idle_up", trainer, trim)
		if not safe.ok or not fast.ok:
			continue
		cases += 1
		if safe != fast:
			mismatched += 1
		if not _feasible(_required_servos(safe, linkage)):
			infeasible += 1
	check("random sweep evaluates", cases > 500, cases)
	check("every trimmed result is within servo travel", infeasible == 0, "%d of %d" % [infeasible, cases])
	check("safe and prepared evaluation agree", mismatched == 0, mismatched)
	# Below saturation the angle-space sum is kept bit for bit.
	var hover := PackedFloat64Array([0.1, -0.2, 0.0, 0.0])
	var small_trim := {"cyclic_forward_bias_rad": 0.004, "cyclic_right_bias_rad": -0.003}
	var untrimmed: Dictionary = Electronics.evaluate(model, state, hover, "normal", false)
	var trimmed: Dictionary = Electronics.evaluate(model, state, hover, "normal", false, small_trim)
	check("unsaturated trim keeps the original angle-space sum exactly", untrimmed.ok and trimmed.ok
		and not trimmed.servo_travel_limited
		and trimmed.cyclic_forward_rad == clampf(float(untrimmed.cyclic_forward_rad) + 0.004, -0.06, 0.06)
		and trimmed.cyclic_right_rad == clampf(float(untrimmed.cyclic_right_rad) - 0.003, -0.06, 0.06)
		and trimmed.collective_75_rad == untrimmed.collective_75_rad, [untrimmed, trimmed])
	var zero: Dictionary = Electronics.evaluate(model, state, full, "normal", false, {})
	check("zero trim at full collective is unchanged and unlimited", zero.ok and not zero.servo_travel_limited
		and float(zero.cyclic_forward_rad) == 0.0 and float(zero.cyclic_right_rad) == 0.0
		and absf(float(zero.collective_75_rad) - 0.22) < 1.0e-15, zero)
	_finish()


func _finish() -> void:
	print("heli trim feasibility: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
