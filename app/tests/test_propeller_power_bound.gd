## A36 R6-G01: tabulated Ct/Cp propellers must satisfy the steady axial energy balance Cp(J) >= J·Ct(J) on the runtime
## interpolation/extrapolation law. Covers the interior-only violation, exact equality, an unbounded tail, the windmill
## branch, the R6 admitted witnesses (refused now) and every stock propeller table (still admitted).
extends SceneTree

const Bound := preload("res://physics/propeller_power_bound.gd")
const Data := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")

const LUMBER := "res://data/aircraft/turbo_lumber_evolution.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL %s — %s" % [label, str(detail)])


func _table(rows: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for row: Array in rows:
		out.append(float(row[0]))
		out.append(float(row[1]))
	return out


func _run() -> void:
	_unit_cases()
	_cursor_parity_and_scale()
	_r6_witnesses()
	_stock_catalog()
	print("propeller power bound: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _unit_cases() -> void:
	# R6 oracle: both rows pass even the ideal-disk bound, the linear interior at J = 0.5 does not (J·Ct = 0.002125 > 0.00195).
	var ct := _table([[0.0, 0.0050], [0.2, 0.0050], [0.8, 0.0035], [1.2, -0.05]])
	var cp := _table([[0.0, 0.00108], [0.2, 0.00108], [0.8, 0.00282], [1.2, 0.001]])
	for j: float in [0.2, 0.8]:
		check("R6 interior case passes at row J=%.1f" % j,
			Propulsion.coefficient(cp, j, 0.0) - j * Propulsion.coefficient(ct, j, Propulsion.CT_FLOOR) >= 0.0)
	var interior := Bound.check(ct, cp, 0.0)
	check("R6 interior case is refused between passing rows", not interior.ok and interior.j > 0.2 and interior.j < 0.8, interior)
	var expected_j := 0.5 # independent: g = -aJ^2 + (c-b)J + d on [0.2, 0.8] is minimised where g' = 0.
	var a := (0.0035 - 0.0050) / 0.6
	var b := 0.0050 - a * 0.2
	var c := (0.00282 - 0.00108) / 0.6
	expected_j = (c - b) / (2.0 * a)
	check("interior minimum is located at the analytic stationary point", absf(float(interior.j) - expected_j) < 1.0e-12,
		"%s vs %s" % [interior.j, expected_j])
	# Equality: Cp = J·Ct exactly at J = 0.5 (ideal efficiency, the piecewise minimum of the margin) is admitted; a 1e-6
	# deficit is not. Equal rows on both ends of an interval would fail inside it, because J·Ct is quadratic.
	var ct_eq := _table([[0.0, 0.1], [0.5, 0.05], [1.0, -0.05]])
	var cp_ideal := PackedFloat64Array([0.0, 0.05, 0.5, 0.025, 1.0, 0.0])
	var ideal := Bound.check(ct_eq, cp_ideal, 0.0)
	check("an efficiency of exactly one is admitted", ideal.ok and absf(float(ideal.margin)) < 1.0e-15
		and absf(float(ideal.efficiency) - 1.0) < 1.0e-12, ideal)
	var cp_short := PackedFloat64Array([0.0, 0.05, 0.5, 0.025 - 1.0e-6, 1.0, 0.0])
	check("a 1e-6 power deficit at a row is refused", not Bound.check(ct_eq, cp_short, 0.0).ok)
	# Windmill branch: Ct < 0 and Cp < 0 must extract no more than the air's work (-Cp <= -J·Ct).
	var ct_wind := _table([[0.0, 0.1], [0.8, 0.0], [1.2, -0.06]])
	var cp_ok := _table([[0.0, 0.05], [0.8, 0.01], [1.2, -0.05]])
	var cp_over := _table([[0.0, 0.05], [0.8, 0.01], [1.2, -0.08]])
	check("a windmill branch within the air's work is admitted", Bound.check(ct_wind, cp_ok, -0.05).ok, Bound.check(ct_wind, cp_ok, -0.05))
	check("a windmill branch extracting more than the air's work is refused", not Bound.check(ct_wind, cp_over, -0.08).ok)
	# Tail: a last segment with rising positive Ct grows J·Ct without bound while Cp is clamped at its floor.
	var ct_rise := _table([[0.0, 0.1], [0.5, 0.06], [0.6, 0.07]])
	var cp_rise := _table([[0.0, 0.06], [0.5, 0.05], [0.6, 0.049]])
	var rising := Bound.check(ct_rise, cp_rise, 0.0)
	check("an unbounded extrapolated tail is refused", not rising.ok and float(rising.margin) == -INF, rising)
	var message := Bound.error("cp", ct_rise, cp_rise, 0.0)
	check("the tail refusal names the extrapolation", message.contains("extrapolation"), message)
	# Tail floor kinks: Cp reaches its 0 floor while Ct is still positive beyond the last row.
	var ct_floor := _table([[0.0, 0.1], [0.5, 0.06], [0.6, 0.05]])
	var cp_floor := _table([[0.0, 0.06], [0.5, 0.05], [0.6, 0.032]])
	var floored := Bound.check(ct_floor, cp_floor, 0.0)
	check("a tail that hits the Cp floor before Ct falls is refused", not floored.ok and float(floored.j) > 0.6, floored)
	for j: float in [0.65, 0.7, 0.75, 0.8]:
		var direct := Propulsion.coefficient(cp_floor, j, 0.0) - j * Propulsion.coefficient(ct_floor, j, Propulsion.CT_FLOOR)
		check("tail certificate never exceeds a sampled runtime margin at J=%.2f" % j, float(floored.margin) <= direct + 1.0e-15)


## The bound's forward cursor reproduces Propulsion.coefficient bit for bit, and a 524,289-row table (the native
## admission snapshot size) is certified in linear passes rather than one table scan per breakpoint.
func _cursor_parity_and_scale() -> void:
	var table := _table([[0.0, 0.12], [0.2, 0.11], [0.45, 0.07], [0.7, 0.01], [0.9, -0.04]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 6201
	var samples := PackedFloat64Array()
	for i in 400:
		samples.append(rng.randf_range(-0.2, 2.0))
	samples.sort()
	var cursor := 1
	var same := true
	for j: float in samples:
		var value: Array = Bound._value(table, j, Propulsion.CT_FLOOR, cursor)
		cursor = int(value[1])
		same = same and float(value[0]) == Propulsion.coefficient(table, j, Propulsion.CT_FLOOR)
	check("forward cursor equals Propulsion.coefficient exactly", same)
	var rows := 524289
	var big_ct := PackedFloat64Array()
	var big_cp := PackedFloat64Array()
	for i in rows:
		var j := float(i) / float(rows - 1)
		big_ct.append(j)
		big_ct.append(0.1 - 0.12 * j)
		big_cp.append(j)
		big_cp.append(0.05 - 0.02 * j)
	var started := Time.get_ticks_msec()
	var result := Bound.check(big_ct, big_cp, 0.0)
	var elapsed := Time.get_ticks_msec() - started
	check("a 524,289-row table is certified in linear time", result.ok and elapsed < 30000, "%d ms %s" % [elapsed, str(result)])


func _lumber(mutate: Callable) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LUMBER))
	mutate.call(raw.propulsion.propeller)
	return Data.validate_and_derive(raw)


func _r6_witnesses() -> void:
	var stock: Dictionary = _lumber(func(_prop: Dictionary) -> void: pass)
	check("stock Turbo Lumber data is admitted", stock.ok, stock.errors)
	var minimal: Dictionary = _lumber(func(prop: Dictionary) -> void:
		for row: Array in prop.cp_table.value:
			if is_equal_approx(float(row[0]), 0.655):
				row[1] = 0.020
		prop.cp_table.kind = "estimated"
		prop.cp_table.source = "A36 R6 synthetic single-knot power deficit")
	check("R6 single-knot witness (TV/QΩ = 1.30 at J = 0.655) is refused", not minimal.ok
		and "\n".join(minimal.errors).contains("thrust work exceeds shaft power"), minimal.errors)
	var trim: Dictionary = _lumber(func(prop: Dictionary) -> void:
		var ct: Array = prop.ct_table.value
		var cp: Array = prop.cp_table.value
		for i in mini(ct.size(), cp.size()):
			if float(ct[i][0]) == float(cp[i][0]) and float(ct[i][0]) >= 0.373:
				cp[i][1] = minf(float(cp[i][1]), maxf(0.001, snappedf(0.8 * float(ct[i][0]) * float(ct[i][1]), 1.0e-8)))
		prop.cp_table.kind = "estimated"
		prop.cp_table.source = "A36 R6 synthetic energy-deficit trim witness")
	check("R6 ordinary-trim witness map is refused", not trim.ok
		and "\n".join(trim.errors).contains("propulsion.propeller.cp_table"), trim.errors)


func _stock_catalog() -> void:
	var dirs: Array[String] = ["res://data/aircraft", "res://data/aircraft/battery"]
	var tested := 0
	for dir: String in dirs:
		for file: String in DirAccess.get_files_at(dir):
			if not file.ends_with(".json"):
				continue
			var path := dir.path_join(file)
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not raw is Dictionary or not raw.get("propulsion") is Dictionary:
				continue
			var prop: Variant = raw.propulsion.get("propeller", {})
			if not prop is Dictionary or not prop.has("ct_table") or not prop.has("cp_table"):
				continue
			tested += 1
			var loaded: Dictionary = Data.load_file(path)
			var power_errors := PackedStringArray()
			for message: String in loaded.get("errors", PackedStringArray()):
				if message.contains("thrust work") or message.contains("Cp - J·Ct"):
					power_errors.append(message)
			check("stock %s satisfies the propeller power bound" % file, power_errors.is_empty(), power_errors)
	check("the stock propeller catalog was found", tested >= 15, tested)
