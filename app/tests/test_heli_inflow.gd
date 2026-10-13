# HELI-04: published anchors and independent physical/mathematical invariants.
extends SceneTree

const Inflow = preload("res://physics/rotorcraft/inflow.gd")
const M = preload("res://physics/math3d.gd")
var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func close(label: String, actual: float, expected: float, tolerance: float = 1e-12) -> void:
	check(label, is_finite(actual) and absf(actual - expected) <= tolerance * maxf(1.0, absf(expected)))


func _initialize() -> void:
	_anchors()
	_momentum()
	_continuity()
	_signed_and_ground()
	_lag()
	_invalid()
	_oracle()
	print("HELI-04 inflow: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _anchors() -> void:
	close("ideal hover", Inflow.normalized(0.0, 0.0).ratio, 1.0)
	close("Johnson N total velocity Table 4", -0.45 + Inflow.normalized(-0.45, 0.0).ratio, 0.85)
	close("Johnson X total velocity Table 4", -1.5 + Inflow.normalized(-1.5, 0.0).ratio, 1.25)
	close("instability disabled at N", Inflow.normalized(-0.45, 0.0, 0.0).ratio, 1.25)
	close("instability disabled at X", Inflow.normalized(-1.5, 0.0, 0.0).ratio, 2.0)
	close("climb golden ratio", Inflow.normalized(1.0, 0.0).ratio, 0.6180339887498948)
	close("windmill golden ratio", Inflow.normalized(-3.0, 0.0).ratio, 0.38196601125010515)
	close("induced loss scales mean inflow", Inflow.normalized(-1.5, 0.0, 1.0, 1.15).ratio, 2.75 * 1.15)
	var mid: float = Inflow.normalized(-1.0, 0.0, 0.5).ratio
	close("instability is affine in f", mid,
		0.5 * (Inflow.normalized(-1.0, 0.0, 0.0).ratio + Inflow.normalized(-1.0, 0.0).ratio))
	var eps: float = 1e-5
	var total_slope: float = 1.0 + (Inflow.normalized(-1.0 + eps, 0.0).ratio - Inflow.normalized(-1.0 - eps, 0.0).ratio) / (2.0 * eps)
	check("VRS has negative total inflow slope", total_slope < 0.0)


func _momentum() -> void:
	for z: float in [-6.0, -3.0, -2.2, 0.0, 0.5, 2.0, 10.0]:
		for x: float in [0.0, 0.2, 0.8, 2.0, 10.0]:
			var r: Dictionary = Inflow.normalized(z, x, 0.0)
			check("momentum evaluation valid", r.ok)
			if r.ok:
				close("actuator disc momentum residual", r.ratio * M.sqrt_(x * x + (z + r.ratio) * (z + r.ratio)), 1.0, 2e-12)
	check("translational lift reduces ideal hover inflow", Inflow.normalized(0.0, 2.0).ratio < 1.0)
	for z: float in [-1e6, -20.0, 0.0, 20.0, 1e6]:
		for x: float in [1e-8, 0.5, 1e6]:
			var r: Dictionary = Inflow.normalized(z, x, 0.0)
			check("extreme accepted ratios remain finite", r.ok)
			if r.ok:
				close("extreme momentum residual", r.ratio * M.sqrt_(x * x + (z + r.ratio) * (z + r.ratio)), 1.0, 2e-12)


func _continuity() -> void:
	# C0 is required. Johnson deliberately leaves slopes free at B and E.
	for x: float in [0.0, 0.2, 0.5, 0.749, 0.75, 0.8, 0.949, 0.95, 1.0]:
		for i: int in range(401):
			var z: float = -3.0 + float(i) / 100.0
			var r: Dictionary = Inflow.normalized(z, x)
			check("dense descent envelope remains finite and positive", r.ok and r.ratio > 0.0)
		var u: float = minf(x / 0.75, 1.0)
		var a: float = -1.5 + 0.2 * u * u
		var b: float = -2.1 + 0.2 * u * u
		if u > 0.5:
			b += 0.7 * (a - b) * M.pow_(2.0 * u - 1.0, 3.0)
		var e: float = -2.0
		var n: float = -0.45
		var peak: float = -1.5
		if x < 0.95:
			var edge: float = 1.0 - (x / 0.95) * (x / 0.95)
			n = -0.975 + 0.525 * M.pow_(edge, 0.2)
			peak = -0.975 - 0.525 * M.pow_(edge, 1.5)
			e += peak + 1.5
		for boundary: float in [a, b, -0.2, n, peak, e, 0.0, -2.0]:
			var left: Dictionary = Inflow.normalized(boundary - 1e-8, x)
			var right: Dictionary = Inflow.normalized(boundary + 1e-8, x)
			check("axial segment boundary continuous", left.ok and right.ok and absf(left.ratio - right.ratio) < 2e-6)
	for z: float in [-3.0, -2.0, -1.5, -1.428, -1.3, -1.0, -0.975, -0.7, -0.2, 0.0]:
		for boundary: float in [0.75, 0.95]:
			var left: Dictionary = Inflow.normalized(z, boundary - 1e-10)
			var right: Dictionary = Inflow.normalized(z, boundary + 1e-10)
			if boundary == 0.75 and z != -1.428:
				check("baseline crossflow boundary continuous", left.ok and right.ok and absf(left.ratio - right.ratio) < 2e-5)
			else:
				# The literal Table 3 model's N/X slopes do not taper to zero
				# at M. Document this source discontinuity; do not silently fit it.
				check("published crossflow cut remains finite", left.ok and right.ok)
	var below_m: float = Inflow.normalized(-1.3, 0.95 - 1e-10).ratio
	var above_m: float = Inflow.normalized(-1.3, 0.95 + 1e-10).ratio
	check("source M discontinuity retained as explicit integration gate", below_m - above_m > 0.13 and below_m - above_m < 0.15)
	var below_c: float = Inflow.normalized(-1.428, 0.75 - 1e-9, 0.0).ratio
	var above_c: float = Inflow.normalized(-1.428, 0.75 + 1e-9, 0.0).ratio
	check("source C discontinuity retained as explicit integration gate", above_c - below_c > 0.0035 and above_c - below_c < 0.0037)


func _signed_and_ground() -> void:
	var hover: Dictionary = Inflow.target(8.2 * 9.80665, 1.225, 0.775, 0.0, 0.0)
	check("X-Cell target valid", hover.ok)
	close("X-Cell ideal induced hover velocity", hover.hover, 4.170686852391147, 1e-12)
	for climb: float in [-12.0, -6.0, -2.0, 0.0, 4.0]:
		for crossflow: float in [0.0, 2.0, 10.0]:
			for height: float in [-1.0, 0.5, 2.0]:
				var upright: Dictionary = Inflow.target(80.0, 1.225, 0.775, climb, crossflow, height, 1.15)
				var reverse: Dictionary = Inflow.target(-80.0, 1.225, 0.775, -climb, crossflow, height, 1.15)
				check("mirrored thrust valid", upright.ok and reverse.ok)
				close("inverted sign symmetry with declared ground geometry", reverse.velocity, -upright.velocity)
	close("ground disabled is unity", Inflow.ground_factor(-1.0), 1.0)
	close("Hayden ground floor", Inflow.ground_factor(0.0), 0.9926 / 1.59964)
	close("below floor matches floor", Inflow.ground_factor(0.2), Inflow.ground_factor(0.5))
	check("far field approaches OGE", Inflow.ground_factor(100.0) > 0.9999 and Inflow.ground_factor(100.0) <= 1.0)
	for height: float in [0.61, 1.0, 2.0, 4.0]:
		var cb: float = M.sqrt_(1.0 - 1.0 / (16.0 * height * height))
		var hayden: float = Inflow.ground_factor(height)
		check("CB and Hayden reduce induced velocity", cb > 0.0 and cb < 1.0 and hayden > 0.0 and hayden <= 1.0)
		# Different empirical laws: report/qualify their difference rather than
		# assert identical lift. At these heights disagreement stays below 25%.
		check("independent CB cross-check bounds", absf(hayden - cb) / cb < 0.25)
	var zero: Dictionary = Inflow.target(0.0, 1.225, 0.775, -10.0, 2.0, 0.5)
	check("zero thrust produces zero target", zero.ok and zero.velocity == 0.0 and zero.hover == 0.0)


func _lag() -> void:
	var r: Dictionary = Inflow.derivative(0.032, 0.05, 167.0, 0.032)
	check("dynamic inflow derivative valid", r.ok)
	close("hover lag is 39.72 ms", r.tau, 0.03971744011976048)
	close("dynamic derivative closes lag equation", r.rate * r.tau, 0.018)
	close("steady target has zero derivative", Inflow.derivative(0.05, 0.05, 167.0, 0.032).rate, 0.0)
	close("mirrored dynamic derivative", Inflow.derivative(-0.032, -0.05, 167.0, 0.032).rate, -r.rate)
	var floor_result: Dictionary = Inflow.derivative(0.0, 0.0, 167.0, 0.0, 0.001)
	check("effective inflow floor keeps lag finite", floor_result.ok and is_finite(floor_result.tau))
	var stopped: Dictionary = Inflow.derivative(0.032, 0.0, 0.0, 0.032)
	check("stopped rotor freezes ratio state", stopped.ok and stopped.rate == 0.0 and stopped.tau == INF)


func _invalid() -> void:
	for bad: float in [NAN, INF, -INF]:
		check("nonfinite axial ratio refused", not Inflow.normalized(bad, 0.0).ok)
		check("nonfinite lateral ratio refused", not Inflow.normalized(0.0, bad).ok)
		check("nonfinite thrust refused", not Inflow.target(bad, 1.225, 0.775, 0.0, 0.0).ok)
		check("nonfinite lag state refused", not Inflow.derivative(bad, 0.0, 167.0, 0.032).ok)
	check("negative crossflow magnitude refused", not Inflow.normalized(0.0, -0.1).ok)
	check("normalized domain limit enforced", not Inflow.normalized(1e7, 0.0).ok)
	check("instability outside range refused", not Inflow.normalized(0.0, 0.0, 1.1).ok)
	check("induced loss below unity refused", not Inflow.normalized(0.0, 0.0, 1.0, 0.9).ok)
	check("zero density refused", not Inflow.target(80.0, 0.0, 0.775, 0.0, 0.0).ok)
	check("zero radius refused", not Inflow.target(80.0, 1.225, 0.0, 0.0, 0.0).ok)
	check("invalid height sentinel refused", not Inflow.target(80.0, 1.225, 0.775, 0.0, 0.0, -0.5).ok)
	check("invalid ground factor is nonfinite", not is_finite(Inflow.ground_factor(NAN)))
	check("negative rotor speed refused", not Inflow.derivative(0.0, 0.0, -1.0, 0.032).ok)
	check("negative effective flow refused", not Inflow.derivative(0.0, 0.0, 1.0, -0.032).ok)
	check("zero inflow floor refused", not Inflow.derivative(0.0, 0.0, 1.0, 0.032, 0.0).ok)


func _oracle() -> void:
	# A --oracle=/absolute/path argument is opt-in: exported apps do not ship research.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--oracle="):
			var json: JSON = JSON.new()
			check("oracle parses", json.parse(FileAccess.get_file_as_string(arg.substr(9))) == OK)
			if typeof(json.data) != TYPE_DICTIONARY:
				check("oracle is dictionary", false)
				return
			check("oracle format recognized", json.data.get("format") == "openrc-johnson-inflow-oracle-v1")
			for row: Dictionary in json.data.normalized_cases:
				var inputs: Dictionary = row.inputs
				var r: Dictionary = Inflow.normalized(inputs.vz, inputs.vx, inputs.get("instability", 1.0), inputs.get("loss", 1.0))
				check("independent Python oracle valid", r.ok)
				if r.ok:
					close("independent Python oracle " + row.name, r.ratio, row.expected_ratio, 1e-10)
			for row: Dictionary in json.data.dimensional_target_cases:
				var inputs: Dictionary = row.inputs
				var r: Dictionary = Inflow.target(inputs.thrust, inputs.density, inputs.radius, inputs.climb,
					inputs.crossflow, inputs.get("height_over_radius", -1.0), inputs.get("loss", 1.0), inputs.get("instability", 1.0))
				check("independent dimensional oracle valid", r.ok)
				if r.ok:
					close("independent target velocity " + row.name, r.velocity, row.expected.velocity, 1e-10)
					close("independent hover velocity " + row.name, r.hover, row.expected.hover, 1e-10)
					close("independent ground multiplier " + row.name, r.ground_factor, row.expected.ground_factor, 1e-10)
