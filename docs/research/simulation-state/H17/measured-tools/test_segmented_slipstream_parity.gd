# Draft exact-output parity check for the pass-4 scalar-cache candidate.
# Run under the frozen project so res://physics/slipstream.gd resolves to base/app.
# The candidate is loaded from its absolute scratch-copy path; this file is intentionally outside app/.
extends SceneTree

const BaseSlipstream = preload("res://physics/slipstream.gd")
const AD = preload("res://physics/aircraft_data.gd")
const Air = preload("res://physics/air_data.gd")
const M = preload("res://physics/math3d.gd")
const Propulsion = preload("res://physics/propulsion.gd")
const RB = preload("res://physics/rigid_body.gd")

const CANDIDATE_PATH := "C:/DEVELOPMENT/OpenRCsimulator/tmp/perf-pass4-20261019/candidate/physics/slipstream.gd"
const P51_PATH := "res://data/aircraft/p51d_mustang_120.json"
const RHO := 1.225
const DIRECT_SUBDIVISIONS := [1, 2, 4, 8]
const DIRECT_CUT_CASES := [
	{name = "core_pair_and_center", a = 0.1, b = 2.9, along = -1.5, d2 = 0.01, internal = 3},
	{name = "center_only", a = 0.1, b = 2.9, along = -1.5, d2 = 0.2, internal = 1},
	{name = "single_core_edge", a = 1.65, b = 1.95, along = -1.5, d2 = 0.01, internal = 1},
	{name = "no_internal_cuts", a = 0.1, b = 2.9, along = -4.0, d2 = 0.2, internal = 0},
]

var _candidate: Script
var _p51: Dictionary
var _checks: int = 0
var _failures: int = 0
var _direct_calls: int = 0
var _load_calls: int = 0
var _multi_cut_cases: int = 0
var _zero_area_cases: int = 0
var _negative_area_cases: int = 0
var _stik_models: int = 0
var _stik_load_calls: int = 0
var _surface_cases := {"horizontal": 0, "vertical": 0}
var _cut_coverage := {"core_pair_and_center": 0, "center_only": 0, "single_core_edge": 0, "no_internal_cuts": 0}
var _swirl_controls: int = 0
var _seeded_calls: int = 0
var _seeded_nonzero: int = 0


func _initialize() -> void:
	_candidate = load(CANDIDATE_PATH) as Script
	_expect(_candidate != null, "candidate script loads from the requested absolute path")
	if _candidate == null:
		_finish()
		return

	var loaded: Dictionary = AD.load_file(P51_PATH)
	_expect(bool(loaded.get("ok", false)), "P-51 source loads through AircraftData")
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	_p51 = loaded.model
	_expect(_p51.propulsion.slipstream.has("propeller_sidewash"), "P-51 fixture selects the segmented slipstream")

	_comparator_selftest()
	_direct_segment_parity()
	_direct_mutation_parity()
	_whole_load_parity()
	_seeded_load_parity()
	_finish()


func _finish() -> void:
	_expect(_multi_cut_cases >= 2, "core-pair-plus-center fixtures cover both surfaces")
	_expect(_surface_cases["horizontal"] > 0 and _surface_cases["vertical"] > 0, "direct helper covers both tail surfaces")
	_expect(_cut_coverage["center_only"] >= 2 and _cut_coverage["single_core_edge"] >= 2 and _cut_coverage["no_internal_cuts"] >= 2,
		"center-only, single-core-edge, and no-internal-cut fixtures cover both surfaces")
	_expect(_zero_area_cases > 0 and _negative_area_cases > 0, "zero and negative chord-area earlyouts are exercised")
	_expect(_swirl_controls == 2, "nonzero swirl changes the direct helper output on both surfaces")
	_expect(_direct_calls >= 48, "direct helper coverage floor (at least 48 parity comparisons)")
	_expect(_load_calls >= 30, "whole-load coverage floor (P-51 segmented/legacy and Stik routes)")
	_expect(_stik_models >= 3 and _stik_load_calls >= 12, "at least three Stik models and twelve Stik load cases are covered")
	_expect(_seeded_calls == 256 and _seeded_nonzero > 128, "seeded sweep executes 256 comparisons with nonzero-load coverage")
	print("seeded sweep: comparisons=%d nonzero=%d" % [_seeded_calls, _seeded_nonzero])
	print("segmented slipstream parity: checks=%d failures=%d direct=%d loads=%d multi_cut=%d zero_area=%d negative_area=%d horizontal=%d vertical=%d stik_models=%d stik_loads=%d swirl_controls=%d" % [
		_checks, _failures, _direct_calls, _load_calls, _multi_cut_cases, _zero_area_cases, _negative_area_cases,
		_surface_cases["horizontal"], _surface_cases["vertical"], _stik_models, _stik_load_calls, _swirl_controls,
	])
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	if _failures <= 20:
		printerr("FAIL ", label)


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _all_positive_zero(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if value != 0.0 or is_nan(value):
			return false
	return true


func _same_bytes(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	return a.size() == b.size() and a.to_byte_array() == b.to_byte_array()


func _comparator_selftest() -> void:
	var one := PackedFloat64Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
	var adjacent := one.duplicate()
	adjacent[4] = 5.000000000000001 # The next representable float64 above 5.0 (one ULP).
	_expect(adjacent[4] - one[4] == 8.881784197001252e-16, "comparator self-test fixture is exactly one ULP")
	_expect(not _same_bytes(one, adjacent), "byte comparator rejects a one-ULP change")


func _compare(label: String, baseline: PackedFloat64Array, candidate: PackedFloat64Array) -> void:
	_checks += 1
	if baseline.size() != 6 or candidate.size() != 6:
		_failures += 1
		if _failures <= 20:
			printerr("FAIL ", label, ": expected six loads, got ", baseline.size(), " and ", candidate.size())
		return
	if not _all_finite(baseline) or not _all_finite(candidate):
		_failures += 1
		if _failures <= 20:
			printerr("FAIL ", label, ": non-finite result; exact NaN matches are rejected")
		return
	if not _same_bytes(baseline, candidate):
		_failures += 1
		if _failures <= 20:
			printerr("FAIL ", label, ": float64 result bytes differ; baseline=", baseline, " candidate=", candidate)


func _internal_cut_count(case: Dictionary, core: float = 0.3) -> int:
	var count: int = 0
	if core * core > float(case.d2):
		var core_half: float = M.sqrt_(core * core - float(case.d2))
		for cut: float in [-float(case.along) - core_half, -float(case.along) + core_half]:
			if cut > float(case.a) and cut < float(case.b):
				count += 1
	if -float(case.along) > float(case.a) and -float(case.along) < float(case.b):
		count += 1
	return count


func _make_direct_fixture(surface: String, case: Dictionary, chord_mode: String = "normal") -> Dictionary:
	var model: Dictionary = _p51.duplicate(true)
	var vertical: bool = surface == "vertical"
	var span: float = 3.0
	var c0: float = 0.78
	var slope: float = -0.08
	if chord_mode == "zero":
		c0 = 0.0
		slope = 0.0
	elif chord_mode == "negative":
		c0 = -0.78
		slope = -0.08
	var full: float = c0 * span + 0.5 * slope * span * span
	var root := PackedFloat64Array([1.43, -0.31, 0.12])
	var span_dir := PackedFloat64Array([0.0, 0.0, 1.0]) if vertical else PackedFloat64Array([0.0, 1.0, 0.0])
	var piece := {
		"surface": surface,
		"area": full,
		"root": root,
		"span_dir": span_dir,
		"span": span,
	}
	var perpendicular := PackedFloat64Array([M.sqrt_(float(case.d2)), 0.0, 0.0])
	var centre := PackedFloat64Array([
		root[0] - span_dir[0] * float(case.along) - perpendicular[0],
		root[1] - span_dir[1] * float(case.along) - perpendicular[1],
		root[2] - span_dir[2] * float(case.along) - perpendicular[2],
	])
	var ax := PackedFloat64Array([1.0, 0.12, -0.07])
	var inv_axis_length: float = 1.0 / M.sqrt_(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2])
	for component in 3:
		ax[component] *= inv_axis_length
	var state := RB.make_state(M.v3(0.0, 0.0, -100.0), M.v3(21.0, 1.3, -2.1), M.q_identity(), M.v3(0.13, -0.21, 0.08))
	var d := {elevator = -0.07, rudder = 0.11, aileron_right = 0.0, aileron_left = 0.0}
	return {
		"piece": piece,
		"tail": model.surfaces[surface],
		"a": float(case.a),
		"b": float(case.b),
		"c0": c0,
		"slope": slope,
		"along": float(case.along),
		"d2": float(case.d2),
		"centre": centre,
		"ax": ax,
		"core": 0.3,
		"swirl": 0.42,
		"wash": PackedFloat64Array([1.8, -0.7, 0.9]),
		"state": state,
		"v": M.v3(23.0, 1.1, -1.7),
		"d": d,
		"model": model,
		"rho": RHO,
		"wing_cl": 0.43,
	}


func _segment_args(fixture: Dictionary, subdivisions: int) -> Array:
	return [
		fixture.piece, fixture.tail, fixture.a, fixture.b, fixture.c0, fixture.slope, fixture.along, fixture.d2,
		fixture.centre, fixture.ax, fixture.core, fixture.swirl, fixture.wash, fixture.state, fixture.v, fixture.d,
		fixture.model, fixture.rho, fixture.wing_cl, subdivisions,
	]


func _segment_call(script: Script, fixture: Dictionary, subdivisions: int) -> PackedFloat64Array:
	var result: PackedFloat64Array = script.callv("_segmented_increment", _segment_args(fixture, subdivisions))
	return result


func _direct_segment_parity() -> void:
	for surface: String in ["horizontal", "vertical"]:
		for case: Dictionary in DIRECT_CUT_CASES:
			var observed_cuts: int = _internal_cut_count(case)
			_expect(observed_cuts == int(case.internal), "fixture cut geometry: %s/%s expected %d got %d" % [surface, case.name, case.internal, observed_cuts])
			if observed_cuts == int(case.internal):
				_cut_coverage[case.name] += 1
			if observed_cuts >= 2:
				_multi_cut_cases += 1
			for subdivisions: int in DIRECT_SUBDIVISIONS:
				var fixture: Dictionary = _make_direct_fixture(surface, case)
				var baseline := _segment_call(BaseSlipstream, fixture, subdivisions)
				var candidate := _segment_call(_candidate, fixture, subdivisions)
				_compare("direct/%s/%s/sub%d" % [surface, case.name, subdivisions], baseline, candidate)
				_surface_cases[surface] += 1
				_direct_calls += 1

		for chord_mode: String in ["zero", "negative"]:
			for subdivisions: int in DIRECT_SUBDIVISIONS:
				var fixture: Dictionary = _make_direct_fixture(surface, DIRECT_CUT_CASES[0], chord_mode)
				var baseline := _segment_call(BaseSlipstream, fixture, subdivisions)
				var candidate := _segment_call(_candidate, fixture, subdivisions)
				_compare("direct/%s/%s-area/sub%d" % [surface, chord_mode, subdivisions], baseline, candidate)
				_expect(_all_positive_zero(baseline) and _all_positive_zero(candidate), "direct/%s/%s-area earlyout returns finite zero" % [surface, chord_mode])
				if chord_mode == "zero":
					_zero_area_cases += 1
				else:
					_negative_area_cases += 1
				_direct_calls += 1

		var swirl_fixture: Dictionary = _make_direct_fixture(surface, DIRECT_CUT_CASES[0])
		var with_swirl := _segment_call(_candidate, swirl_fixture, 1)
		var zero_swirl_fixture: Dictionary = _make_direct_fixture(surface, DIRECT_CUT_CASES[0])
		zero_swirl_fixture.swirl = 0.0
		var without_swirl := _segment_call(_candidate, zero_swirl_fixture, 1)
		_expect(_all_finite(with_swirl) and _all_finite(without_swirl), "direct/%s swirl-control outputs are finite" % surface)
		if not _same_bytes(with_swirl, without_swirl):
			_swirl_controls += 1
		else:
			_expect(false, "direct/%s fixture must have a measurable nonzero swirl effect" % surface)


func _mutate_fixture(fixture: Dictionary) -> void:
	var piece: Dictionary = fixture.piece
	var root: PackedFloat64Array = piece.root
	root[0] += 0.17
	root[2] -= 0.09
	piece.root = root
	var span_dir: PackedFloat64Array = piece.span_dir
	span_dir[0] = 0.035
	span_dir[1] = 0.998
	span_dir[2] = -0.041
	piece.span_dir = span_dir
	fixture.piece = piece

	var centre: PackedFloat64Array = fixture.centre
	centre[0] -= 0.12
	centre[2] += 0.08
	fixture.centre = centre
	var ax: PackedFloat64Array = fixture.ax
	ax[1] -= 0.025
	ax[2] += 0.031
	fixture.ax = ax
	var wash: PackedFloat64Array = fixture.wash
	wash[1] += 1.4
	fixture.wash = wash
	var state: PackedFloat64Array = fixture.state
	state[RB.RATE] += 0.19
	state[RB.RATE + 1] -= 0.11
	fixture.state = state
	fixture.d.elevator -= 0.035
	fixture.d.rudder += 0.04
	var model: Dictionary = fixture.model
	var cg: PackedFloat64Array = model.cg_le
	cg[1] += 0.013
	model.cg_le = cg
	fixture.model = model
	fixture.tail = model.surfaces.horizontal


func _direct_mutation_parity() -> void:
	var fixture: Dictionary = _make_direct_fixture("horizontal", DIRECT_CUT_CASES[0])
	var first_baseline := _segment_call(BaseSlipstream, fixture, 2)
	var first_candidate := _segment_call(_candidate, fixture, 2)
	_compare("direct/mutation/warm", first_baseline, first_candidate)
	_mutate_fixture(fixture)
	var mutated_baseline := _segment_call(BaseSlipstream, fixture, 2)
	var mutated_candidate := _segment_call(_candidate, fixture, 2)
	_compare("direct/mutation/changed-inputs", mutated_baseline, mutated_candidate)
	_expect(_all_finite(mutated_candidate), "direct mutation result remains finite")
	_expect(not _same_bytes(first_candidate, mutated_candidate), "candidate result changes after its input arrays and dictionaries mutate")
	_direct_calls += 2


func _state(velocity: PackedFloat64Array, rates: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -100.0), velocity, M.q_identity(), rates)


func _transported_values(model: Dictionary) -> PackedFloat64Array:
	var count: int = model.propulsion.get("slipstream", {}).get("pieces", []).size()
	var values := PackedFloat64Array()
	for index in count:
		values.append(0.72 - 0.14 * float(index))
	return values


func _load_case(model: Dictionary, label: String, velocity: PackedFloat64Array, rates: PackedFloat64Array,
		rpm: float, use_transport: bool = false) -> void:
	var state: PackedFloat64Array = _state(velocity, rates)
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var deflections := {elevator = -0.035, aileron_right = 0.0, aileron_left = 0.0, rudder = 0.07}
	var transported := _transported_values(model) if use_transport else PackedFloat64Array()
	var baseline: PackedFloat64Array = BaseSlipstream.loads(state, air, deflections, model, rpm, RHO, 0.44, transported, 1)
	var candidate: PackedFloat64Array = _candidate.callv("loads", [state, air, deflections, model, rpm, RHO, 0.44, transported, 1])
	_compare("loads/" + label, baseline, candidate)
	_load_calls += 1


func _whole_load_parity() -> void:
	var cases: Array = [
		{name = "static-powered", velocity = M.v3(0.0, 0.0, 0.0), rates = M.v3(0.03, -0.04, 0.02), rpm = 5200.0},
		{name = "cruise-sideslip", velocity = M.v3(22.0, 1.4, -1.7), rates = M.v3(0.11, -0.17, 0.08), rpm = 4800.0},
		{name = "slow-climb", velocity = M.v3(9.0, -0.8, -1.2), rates = M.v3(-0.06, 0.09, -0.03), rpm = 2600.0},
		{name = "reverse-flow", velocity = M.v3(-6.0, 0.6, 1.1), rates = M.v3(0.04, 0.07, -0.05), rpm = 5200.0},
		{name = "stopped-prop-forward-flow", velocity = M.v3(18.0, 0.5, -0.9), rates = M.v3(0.02, -0.03, 0.01), rpm = 0.0},
		{name = "stopped-residual-dv", velocity = M.v3(10.0, -0.3, 0.7), rates = M.v3(0.05, -0.08, 0.03), rpm = 0.5, transport = true},
		{name = "transported-powered", velocity = M.v3(19.0, -1.0, 1.5), rates = M.v3(-0.08, 0.12, 0.06), rpm = 3900.0, transport = true},
		{name = "transported-reverse-fade", velocity = M.v3(-7.0, 0.4, -0.5), rates = M.v3(0.02, 0.03, 0.04), rpm = 3900.0, transport = true},
		{name = "stopped-rpm-boundary", velocity = M.v3(24.0, 0.7, -1.3), rates = M.v3(0.06, -0.1, 0.03), rpm = Propulsion.STOPPED_RPM},
	]
	var segmented: Dictionary = _p51.duplicate(true)
	var legacy: Dictionary = _p51.duplicate(true)
	legacy.propulsion.slipstream.erase("propeller_sidewash")
	for case: Dictionary in cases:
		var rates: PackedFloat64Array = case.rates
		var use_transport: bool = bool(case.get("transport", false))
		_load_case(segmented, "p51-segmented/" + str(case.name), case.velocity, rates, float(case.rpm), use_transport)
		_load_case(legacy, "p51-legacy-centroid/" + str(case.name), case.velocity, rates, float(case.rpm), use_transport)

	for stik_path: String in [
		"res://data/aircraft/jensen_ugly_stik_60.json",
		"res://data/aircraft/stik_glow_61fx_2t.json",
		"res://data/aircraft/stik_glow_fs64v_4t.json",
	]:
		var loaded: Dictionary = AD.load_file(stik_path)
		_expect(bool(loaded.get("ok", false)), "legacy Stik model loads: " + stik_path)
		if not bool(loaded.get("ok", false)):
			continue
		_stik_models += 1
		var stik: Dictionary = loaded.model
		for case: Dictionary in [cases[0], cases[1], cases[3], cases[4]]:
			_load_case(stik, "stik/" + stik.id + "/" + str(case.name), case.velocity, case.rates, float(case.rpm))
			_stik_load_calls += 1


func _seeded_load_parity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 170426
	for index in 128:
		var velocity := M.v3(rng.randf_range(5.0, 40.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		if index % 16 == 0:
			velocity = M.v3(0.0, 0.0, 0.0)
		var state := _state(velocity, M.v3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)))
		var density: float = rng.randf_range(0.9, 1.3)
		var air := Air.compute(state, M.v3(0.0, 0.0, 0.0), density)
		var controls := {elevator = rng.randf_range(-0.2, 0.2), rudder = rng.randf_range(-0.2, 0.2), aileron_right = 0.0, aileron_left = 0.0}
		var rpm: float = rng.randf_range(3500.0, 7000.0)
		var downwash: float = rng.randf_range(-1.0, 2.0)
		for subdivisions: int in [1, 4]:
			var baseline: PackedFloat64Array = BaseSlipstream.loads(state, air, controls, _p51, rpm, density, downwash, PackedFloat64Array(), subdivisions)
			var candidate: PackedFloat64Array = _candidate.callv("loads", [state, air, controls, _p51, rpm, density, downwash, PackedFloat64Array(), subdivisions])
			_compare("seeded/%d/sub%d" % [index, subdivisions], baseline, candidate)
			_seeded_calls += 1
			if not _all_positive_zero(baseline):
				_seeded_nonzero += 1
