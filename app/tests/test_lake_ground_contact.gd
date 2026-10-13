## LU-25: per-session lake terrain composes with field relief through wheel and legacy contact APIs.
## Run: godot --headless --path app --script res://tests/test_lake_ground_contact.gd
extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Loader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Wheels := preload("res://physics/ground_wheels.gd")
const Ground := preload("res://physics/ground_contact.gd")

var _failures: int = 0


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from(Loader.DEFAULT_PATH)
	_check("authored lake definition loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var lake: Dictionary = loaded.lake
	_test_sampler(lake)
	_test_wheel_and_legacy_contacts(lake)
	print("all lake ground contact checks passed" if _failures == 0 else "%d lake ground contact checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_sampler(lake: Dictionary) -> void:
	var surfaces := PackedFloat64Array([-INF, INF, -INF, INF, 0.7, 7.5])
	var no_lake: PackedFloat64Array = Terrain.sample_validated(110.0, 125.0, surfaces)
	var empty_lake: PackedFloat64Array = Terrain.sample_validated(110.0, 125.0, surfaces, {})
	_check("empty lake context preserves the original sampler bit-for-bit", _same3(no_lake, empty_lake))
	var outside_base: PackedFloat64Array = Terrain.sample_validated(200.0, 200.0, surfaces)
	var outside_lake: PackedFloat64Array = Terrain.sample_validated(200.0, 200.0, surfaces, lake)
	_check("outside the bank, field height and slopes are exactly unchanged", _same3(outside_base, outside_lake),
		"base=%s lake=%s" % [outside_base, outside_lake])
	var bad: PackedFloat64Array = Terrain.sample(110.0, 125.0, surfaces, {"invalid": true})
	_check("invalid lake context fails closed", bad.size() == 3 and is_nan(bad[0]) and is_nan(bad[1]) and is_nan(bad[2]))
	var center: PackedFloat64Array = Terrain.sample_validated(110.0, 125.0, surfaces, lake)
	_check("deep basin terrain uses the five-metre bed below mean water", center.size() == 3
		and absf(center[0] + 5.45) < 1e-12 and absf(center[1]) < 1e-8 and absf(center[2]) < 1e-8,
		str(center))
	var bank_core: Dictionary = LakeSurface.sample_terrain_validated(lake, 110.0, 173.0)
	var bank_base: PackedFloat64Array = Terrain.sample_validated(110.0, 173.0, surfaces)
	var bank_sample: PackedFloat64Array = Terrain.sample_validated(110.0, 173.0, surfaces, lake)
	var blend: float = bank_core.blend_fraction
	var expected := PackedFloat64Array([
		bank_base[0] * (1.0 - blend) - bank_core.ground_down_m,
		bank_base[1] * (1.0 - blend) - bank_base[0] * bank_core.blend_slope_north - bank_core.slope_north,
		bank_base[2] * (1.0 - blend) - bank_base[0] * bank_core.blend_slope_east - bank_core.slope_east,
	])
	_check("bank fades field relief and joins the lake slope continuously", bank_core.covered
		and blend > 0.0 and blend < 1.0 and _same3(expected, bank_sample),
		"blend=%.6f expected=%s actual=%s" % [blend, expected, bank_sample])


func _test_wheel_and_legacy_contacts(lake: Dictionary) -> void:
	var gear := {
		"contacts": [{
			"name": "test_wheel",
			"position": PackedFloat64Array([0.0, 0.0, 0.0]),
			"stiffness": 1000.0,
			"damping": 0.0,
			"damping_onset": 0.1,
			"max_compression": 0.2,
			"max_steering": 0.0,
			"wheel_radius": 0.0381,
			"wheel_inertia": 0.00003,
			"spin_relaxation": 0.03,
			"anchor_stiffness": 0.0,
			"anchor_damping": 0.0,
		}],
		"reach": 0.5,
		"side_friction": 0.6,
		"rolling_resistance": 0.02,
		"tan_peak_slip": 1.0,
	}
	var state: PackedFloat64Array = RB.make_state(M.v3(110.0, 125.0, 5.55), M.v3(0.0, 0.0, 0.0),
		M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var wheel: Dictionary = gear.contacts[0]
	var frame: Dictionary = Wheels.frame(state, wheel, 0.0, PackedFloat64Array(), PackedFloat64Array(), false, lake)
	_check("wheel frame uses the deep bed height and normal", absf(float(frame.compression) - 0.1) < 1e-12
		and absf(float(frame.normal[2]) + 1.0) < 1e-12, str(frame))
	var sloped_terrain: PackedFloat64Array = Terrain.sample_validated(110.0, 155.0, PackedFloat64Array(), lake)
	var sloped_norm := M.sqrt_(1.0 + sloped_terrain[1] * sloped_terrain[1] + sloped_terrain[2] * sloped_terrain[2])
	var sloped_state: PackedFloat64Array = RB.make_state(
		M.v3(110.0, 155.0, -sloped_terrain[0] + 0.1 * sloped_norm), M.v3(0.0, 0.0, 0.0),
		M.q_from_euler(0.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))
	var sloped_frame: Dictionary = Wheels.frame(sloped_state, wheel, 0.0, PackedFloat64Array(),
		PackedFloat64Array(), false, lake)
	var slope_matches: bool = absf(float(sloped_frame.normal[0]) + sloped_terrain[1] / sloped_norm) < 1e-12 \
		and absf(float(sloped_frame.normal[1]) + sloped_terrain[2] / sloped_norm) < 1e-12 \
		and absf(float(sloped_frame.normal[2]) + 1.0 / sloped_norm) < 1e-12
	_check("wheel contact normal follows the sloped lake bed", absf(sloped_terrain[2]) > 0.01
		and absf(float(sloped_frame.compression) - 0.1) < 1e-12 and slope_matches, str(sloped_frame))
	var comp_lake: PackedFloat64Array = Ground.compressions(state, gear, PackedFloat64Array(), lake)
	var comp_flat: PackedFloat64Array = Ground.compressions(state, gear)
	_check("gear compression follows the bed when context is present", comp_lake.size() == 1
		and absf(comp_lake[0] - 0.1) < 1e-12 and comp_flat.size() == 1 and absf(comp_flat[0] - 5.55) < 1e-12,
		"lake=%s flat=%s" % [comp_lake, comp_flat])
	_check("gear collapse checks bed support", not Ground.collapsed(state, gear, PackedFloat64Array(), lake)
		and Ground.collapsed(state, gear), "lake=%s flat=%s" % [Ground.collapsed(state, gear, PackedFloat64Array(), lake), Ground.collapsed(state, gear)])
	_check("spring energy follows the bed compression", absf(Ground.spring_energy(state, gear, lake) - 5.0) < 1e-10)
	var evaluated: Dictionary = Ground.evaluate(state, gear, 0.0, PackedFloat64Array(), PackedFloat64Array(),
		PackedFloat64Array([0.0]), 0.0, true, lake)
	_check("wheel evaluation produces a finite 100 N bed load", evaluated.loads.size() == 6
		and evaluated.wheels.size() == 1 and absf(float(evaluated.wheels[0].compression) - 0.1) < 1e-12
		and absf(float(evaluated.wheels[0].normal_load) - 100.0) < 1e-9
		and _finite_array(evaluated.loads), str(evaluated))
	var legacy_load: PackedFloat64Array = Ground.loads(state, gear, 0.0, PackedFloat64Array(),
		PackedFloat64Array(), PackedFloat64Array(), 0.0, lake)
	_check("legacy contact load also supports the sampled bed", legacy_load.size() == 6
		and _finite_array(legacy_load) and absf(legacy_load[2] + 100.0) < 1e-9, str(legacy_load))
	var anchors := PackedFloat64Array([0.0, 0.0, 0.0])
	var next_anchors: PackedFloat64Array = Ground.anchor_step(state, gear, 0.0, PackedFloat64Array(),
		anchors, true, PackedFloat64Array([0.0]), lake)
	_check("anchor support is evaluated against the lake bed", next_anchors.size() == 3
		and next_anchors[2] == 1.0 and absf(next_anchors[0] - 110.0) < 1e-12
		and absf(next_anchors[1] - 125.0) < 1e-12, str(next_anchors))


func _same3(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != 3 or b.size() != 3:
		return false
	for i in 3:
		if a[i] != b[i]:
			return false
	return true


func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
