extends SceneTree

const Thermal := preload("res://physics/wind_thermal_field.gd")

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _cell(changes: Dictionary = {}) -> Dictionary:
	var cell := {
		"id": "cell-a",
		"birth_s": 100.0,
		"duration_s": 240.0,
		"center_ne_m": [500.0, 600.0],
		"drift_ne_mps": [1.0, -0.5],
		"radius_m": 30.0,
		"top_agl_m": 300.0,
		"peak_updraft_mps": 1.2,
	}
	for key: Variant in changes:
		cell[key] = changes[key]
	return cell


func _agenda(cells: Array = []) -> Dictionary:
	var config: Dictionary = Thermal.defaults()
	config.cells = cells
	return config


func _field(config: Dictionary) -> Variant:
	var built: Dictionary = Thermal.build(config)
	if not built.ok:
		printerr("thermal field fixture rejected: ", built.errors)
		return null
	return built.field


func _at(field: Variant, north: float, east: float, height: float, time_s: float) -> Dictionary:
	return field.sample_world(PackedFloat64Array([north, east, -height]), time_s)


func _near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance := 1e-12) -> bool:
	if actual.size() != expected.size():
		return false
	for axis: int in actual.size():
		if not is_finite(actual[axis]) or absf(actual[axis] - expected[axis]) > tolerance:
			return false
	return true


func _norm(value: PackedFloat64Array) -> float:
	return sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2])


func _schema_identity_and_input_safety() -> void:
	var defaults: Dictionary = Thermal.defaults()
	var resolved: Dictionary = Thermal.resolve(defaults)
	_check("complete zero-agenda config resolves", resolved.ok and resolved.config == defaults, str(resolved.errors))
	_check("empty resolved agenda builds a stable zero field", Thermal.build(defaults).ok)
	_check("canonical content hash repeats", Thermal.resolve(resolved.config).content_hash == resolved.content_hash)
	var precision_a: Dictionary = defaults.duplicate(true)
	precision_a.identity.epoch_offset_s = 1.0
	var precision_b: Dictionary = defaults.duplicate(true)
	precision_b.identity.epoch_offset_s = 1.0000000000001
	var precise_a: Dictionary = Thermal.resolve(precision_a)
	var precise_b: Dictionary = Thermal.resolve(precision_b)
	var precision_roundtrip: Dictionary = Thermal.resolve(JSON.parse_string(JSON.stringify(precise_b.config, "", true, true)))
	_check("sub-picosecond thermal clock offsets retain distinct full-precision hashes", precise_a.ok and precise_b.ok
		and precise_a.content_hash != precise_b.content_hash)
	_check("full-precision thermal JSON roundtrip preserves the authored float64 identity", precision_roundtrip.ok
		and precision_roundtrip.config.identity.epoch_offset_s == precise_b.config.identity.epoch_offset_s
		and precision_roundtrip.content_hash == precise_b.content_hash)
	var active: Variant = _field(_agenda([_cell()]))
	var before: PackedFloat64Array = _at(active, 620.0, 540.0, 150.0, 220.0).wind_ned_mps
	var original_hash: String = active.content_hash()
	var exposed: Dictionary = active.configuration()
	exposed.identity.agenda_seed_u32 = 9
	exposed.cells[0].center_ne_m[0] = 0.0
	_check("returned configuration cannot mutate provider", active.content_hash() == original_hash
		and _near(_at(active, 620.0, 540.0, 150.0, 220.0).wind_ned_mps, before, 0.0))
	var changed_seed := _agenda([_cell()])
	changed_seed.identity.agenda_seed_u32 = 77
	_check("agenda source seed changes identity without query randomness", Thermal.resolve(changed_seed).content_hash != original_hash
		and _near(_field(changed_seed).sample_world(PackedFloat64Array([620.0, 540.0, -150.0]), 220.0).wind_ned_mps, before, 0.0))

	var bad_missing := defaults.duplicate(true)
	bad_missing.erase("cells")
	_check("missing root key is rejected", not Thermal.resolve(bad_missing).ok)
	var bad_unknown := defaults.duplicate(true)
	bad_unknown.future = true
	_check("unknown root key is rejected", not Thermal.resolve(bad_unknown).ok)
	var bad_cell_key := _agenda([_cell()])
	bad_cell_key.cells[0].height = 20.0
	_check("unknown cell key is rejected", not Thermal.resolve(bad_cell_key).ok)
	for mutation: Dictionary in [
		{"name": "boolean birth", "key": "birth_s", "value": true},
		{"name": "NaN radius", "key": "radius_m", "value": NAN},
		{"name": "infinite top", "key": "top_agl_m", "value": INF},
		{"name": "zero radius", "key": "radius_m", "value": 0.0},
		{"name": "oversized peak", "key": "peak_updraft_mps", "value": 3.1},
		{"name": "negative lifetime", "key": "duration_s", "value": -1.0},
	]:
		var bad := _agenda([_cell()])
		bad.cells[0][mutation.key] = mutation.value
		_check("reject %s" % mutation.name, not Thermal.resolve(bad).ok)
	var overflow := _agenda([_cell({"center_ne_m": [1.0e308, 0.0]})])
	_check("reject finite overflow-scale centers", not Thermal.resolve(overflow).ok)
	var vertical_array := _agenda([_cell({"center_ne_m": [0.0, 0.0, 0.0]})])
	_check("strict center uses exactly two horizontal components", not Thermal.resolve(vertical_array).ok)
	var invalid_radius_height := _agenda([_cell({"radius_m": 80.01, "top_agl_m": 200.0})])
	_check("reject radius outside authored thermal envelope", not Thermal.resolve(invalid_radius_height).ok)
	var lifetime_end := _agenda([_cell({"birth_s": 86300.0, "duration_s": 240.0})])
	_check("reject lifetime past fixed horizon", not Thermal.resolve(lifetime_end).ok)
	var duplicate := _agenda([_cell(), _cell()])
	_check("reject duplicate cell IDs", not Thermal.resolve(duplicate).ok)
	var reverse_tie := _agenda([
		_cell({"id": "b", "peak_updraft_mps": 0.0}),
		_cell({"id": "a", "peak_updraft_mps": 0.0}),
	])
	_check("agenda requires canonical tie ordering", not Thermal.resolve(reverse_tie).ok)
	var too_many := _agenda([])
	for index: int in 5:
		too_many.cells.append(_cell({"id": "cell-%d" % index, "peak_updraft_mps": 0.0}))
	_check("overlapping cell count is bounded", not Thermal.resolve(too_many).ok)
	var too_strong := _agenda([
		_cell({"id": "a", "peak_updraft_mps": 3.0}),
		_cell({"id": "b", "peak_updraft_mps": -3.1}),
	])
	_check("overlapping circulation amplitude is bounded", not Thermal.resolve(too_strong).ok)


func _analytic_velocity_oracles() -> void:
	var field: Variant = _field(_agenda([_cell()]))
	var center: Dictionary = _at(field, 620.0, 540.0, 150.0, 220.0)
	_check("center updraft matches analytic axis limit", center.ok and _near(center.wind_ned_mps,
		PackedFloat64Array([0.0, 0.0, -1.2]), 1e-12), str(center.wind_ned_mps))
	var zero_crossing: Dictionary = _at(field, 650.0, 540.0, 150.0, 220.0)
	_check("vertical velocity is zero at the declared core radius", absf(zero_crossing.wind_ned_mps[2]) < 1e-12)
	var ring_offset := sqrt(2.0) * 30.0
	var sink_ring: Dictionary = _at(field, 620.0 + ring_offset, 540.0, 150.0, 220.0)
	_check("balanced cell has a sinking annulus", sink_ring.wind_ned_mps[2] > 0.0)
	var expected_ring_down := 1.2 * exp(-2.0)
	_check("annular vertical velocity matches independent streamfunction derivative", absf(sink_ring.wind_ned_mps[2] - expected_ring_down) < 1e-12,
		str(sink_ring.wind_ned_mps[2]))
	var lower_radial: Dictionary = _at(field, 650.0, 540.0, 75.0, 220.0)
	var expected_inflow := -0.5 * 1.2 * PI / 300.0 * 30.0 * exp(-1.0)
	_check("lower-level horizontal convergence differentiates w(z)", absf(lower_radial.wind_ned_mps[0] - expected_inflow) < 1e-12,
		str(lower_radial.wind_ned_mps[0]))
	var floor: Dictionary = _at(field, 620.0, 540.0, 0.0, 220.0)
	var top: Dictionary = _at(field, 620.0, 540.0, 300.0, 220.0)
	_check("floor velocity is exactly zero", floor.ok and _near(floor.wind_ned_mps, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	_check("cell top velocity is exactly zero", top.ok and _near(top.wind_ned_mps, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	var zero_peak: Variant = _field(_agenda([_cell({"peak_updraft_mps": 0.0})]))
	_check("zero-strength cell is valid and exactly calm", _near(_at(zero_peak, 620.0, 540.0, 100.0, 220.0).wind_ned_mps,
		PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	var descending: Variant = _field(_agenda([_cell({"peak_updraft_mps": -0.8})]))
	var down_center: Dictionary = _at(descending, 620.0, 540.0, 150.0, 220.0)
	_check("negative signed cell is a valid descending circulation", down_center.ok and absf(down_center.wind_ned_mps[2] - 0.8) < 1e-12)


func _lifecycle_and_drift() -> void:
	var config := _agenda([_cell()])
	var field: Variant = _field(config)
	var before_birth: PackedFloat64Array = _at(field, 620.0, 540.0, 150.0, 99.99).wind_ned_mps
	var at_birth: PackedFloat64Array = _at(field, 500.0, 600.0, 150.0, 100.0).wind_ned_mps
	var just_after_birth: PackedFloat64Array = _at(field, 500.0001, 599.99995, 150.0, 100.0001).wind_ned_mps
	var at_end: PackedFloat64Array = _at(field, 740.0, 480.0, 150.0, 340.0).wind_ned_mps
	var just_before_end: PackedFloat64Array = _at(field, 739.9999, 480.00005, 150.0, 339.9999).wind_ned_mps
	_check("pre-birth and exact birth are zero", _near(before_birth, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
		and _near(at_birth, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	_check("C2 lifecycle growth begins continuously", _norm(just_after_birth) < 1e-8, str(just_after_birth))
	_check("C2 lifecycle death reaches zero continuously", _near(at_end, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
		and _norm(just_before_end) < 1e-8, str(just_before_end))

	var offset_config := _agenda([_cell()])
	offset_config.identity.epoch_offset_s = 30.0
	var offset_field: Variant = _field(offset_config)
	var shifted_birth: Dictionary = _at(offset_field, 500.0, 600.0, 150.0, 70.0)
	var shifted_mid: Dictionary = _at(offset_field, 620.0, 540.0, 150.0, 190.0)
	_check("fixed epoch offset addresses the same explicit event", shifted_birth.ok
		and _near(shifted_birth.wind_ned_mps, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
		and shifted_mid.wind_ned_mps[2] < 0.0)

	var still_config := _agenda([_cell({"drift_ne_mps": [0.0, 0.0]})])
	var moving_field: Variant = _field(config)
	var still_field: Variant = _field(still_config)
	var moved_center_n := 620.0
	var moved_center_e := 540.0
	var still_center_n := 500.0
	var still_center_e := 600.0
	var moving_sample: PackedFloat64Array = _at(moving_field, moved_center_n + 12.0, moved_center_e - 7.0, 80.0, 220.0).wind_ned_mps
	var still_sample: PackedFloat64Array = _at(still_field, still_center_n + 12.0, still_center_e - 7.0, 80.0, 220.0).wind_ned_mps
	_check("cell drift translates the whole circulation at one constant horizontal rate", _near(moving_sample, still_sample, 1e-12))


func _divergence(field: Variant, north: float, east: float, height: float, time_s: float, step: float) -> float:
	var north_plus: PackedFloat64Array = _at(field, north + step, east, height, time_s).wind_ned_mps
	var north_minus: PackedFloat64Array = _at(field, north - step, east, height, time_s).wind_ned_mps
	var east_plus: PackedFloat64Array = _at(field, north, east + step, height, time_s).wind_ned_mps
	var east_minus: PackedFloat64Array = _at(field, north, east - step, height, time_s).wind_ned_mps
	var down_plus: PackedFloat64Array = _at(field, north, east, height - step, time_s).wind_ned_mps
	var down_minus: PackedFloat64Array = _at(field, north, east, height + step, time_s).wind_ned_mps
	return (north_plus[0] - north_minus[0] + east_plus[1] - east_minus[1] + down_plus[2] - down_minus[2]) / (2.0 * step)


func _complete_flux_divergence_and_bounds() -> void:
	var config := _agenda([_cell()])
	var field: Variant = _field(config)
	var center_n := 620.0
	var center_e := 540.0
	for offset: PackedFloat64Array in [
		PackedFloat64Array([15.0, 10.0, 120.0]),
		PackedFloat64Array([100.0, 0.0, 90.0]),
		PackedFloat64Array([135.0, 0.0, 150.0]),
	]:
		var coarse := absf(_divergence(field, center_n + offset[0], center_e + offset[1], offset[2], 220.0, 0.01))
		var fine := absf(_divergence(field, center_n + offset[0], center_e + offset[1], offset[2], 220.0, 0.005))
		_check("streamfunction circulation has convergent zero divergence at %s" % str(offset), fine < 2e-6 and fine <= coarse * 0.6 + 1e-8,
			"coarse " + str(coarse) + " fine " + str(fine))

	# Independent composite Simpson integration of vertical flux across the full compact disk.
	const N := 4000
	const RADIUS := 30.0
	var h := 150.0
	var step := 5.0 * RADIUS / float(N)
	var flux_integral := 0.0
	var rising_flux := 0.0
	for index: int in N + 1:
		var radius := float(index) * step
		var velocity: PackedFloat64Array = _at(field, center_n + radius, center_e, h, 220.0).wind_ned_mps
		var up := -velocity[2]
		var simpson_weight := 1.0 if index == 0 or index == N else (4.0 if index % 2 == 1 else 2.0)
		flux_integral += simpson_weight * up * radius
		if up > 0.0:
			rising_flux += simpson_weight * up * radius
	flux_integral *= 2.0 * PI * step / 3.0
	rising_flux *= 2.0 * PI * step / 3.0
	_check("core and sinking ring have zero integrated vertical flux", rising_flux > 0.0 and absf(flux_integral) < rising_flux * 1e-6,
		str([flux_integral, rising_flux]))
	_check("finite cell samples remain below conservative speed envelope", _norm(_at(field, center_n + 15.0, center_e + 10.0, 120.0, 220.0).wind_ned_mps)
		<= field.absolute_speed_bound_mps() + 1e-12)

	var method_args: Array = []
	for method: Dictionary in field.get_method_list():
		if method.get("name", "") == "sample_world":
			method_args = method.get("args", [])
	var argument_names := PackedStringArray()
	for argument: Dictionary in method_args:
		argument_names.append(str(argument.get("name", "")))
	_check("thermal sampling has only position and time inputs", argument_names == PackedStringArray(["position_ned", "simulation_time_s"]))


func _radial_support_continuity() -> void:
	var field: Variant = _field(_agenda([_cell()]))
	var center_n := 620.0
	var center_e := 540.0
	var time_s := 220.0
	var height := 150.0
	var support := 150.0
	var edge: PackedFloat64Array = _at(field, center_n + support, center_e, height, time_s).wind_ned_mps
	var inside: PackedFloat64Array = _at(field, center_n + support - 1e-4, center_e, height, time_s).wind_ned_mps
	var outside: PackedFloat64Array = _at(field, center_n + support + 1e-4, center_e, height, time_s).wind_ned_mps
	_check("potential taper reaches exact zero at 5R", _near(edge, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0)
		and _near(outside, PackedFloat64Array([0.0, 0.0, 0.0]), 0.0))
	_check("C2 radial taper approaches zero velocity at its support edge", _norm(inside) < 1e-9, str(inside))


func _invalid_samples() -> void:
	var field: Variant = _field(_agenda([_cell()]))
	_check("wrong position dimension is structured failure", not field.sample_world(PackedFloat64Array([0.0, 0.0]), 0.0).ok)
	_check("NaN position is structured failure", not field.sample_world(PackedFloat64Array([NAN, 0.0, 0.0]), 0.0).ok)
	_check("infinite position is structured failure", not field.sample_world(PackedFloat64Array([0.0, INF, 0.0]), 0.0).ok)
	_check("NaN time is structured failure", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), NAN).ok)
	_check("infinite time is structured failure", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), INF).ok)
	_check("overflow-scale time is rejected", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), 1e308).ok)
	_check("negative time is rejected", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), -0.1).ok)
	_check("below-ground sample fails closed", not field.sample_world(PackedFloat64Array([0.0, 0.0, 0.001]), 220.0).ok)
	_check("outside-horizontal-domain sample fails closed", not field.sample_world(PackedFloat64Array([10000.1, 0.0, -1.0]), 220.0).ok)
	_check("above-domain sample fails closed", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1200.1]), 220.0).ok)
	_check("time after agenda domain fails closed", not field.sample_world(PackedFloat64Array([0.0, 0.0, -1.0]), 86400.1).ok)


func _initialize() -> void:
	_schema_identity_and_input_safety()
	_analytic_velocity_oracles()
	_lifecycle_and_drift()
	_complete_flux_divergence_and_bounds()
	_radial_support_continuity()
	_invalid_samples()
	print("balanced thermal field: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
