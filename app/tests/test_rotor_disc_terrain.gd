extends SceneTree

const Disc := preload("res://physics/rotorcraft/rotor_disc_terrain.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Lake := preload("res://physics/lake_surface.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Pose := preload("res://sim/scenery_collision.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const GroundSurfaces := preload("res://physics/ground_surfaces.gd")
const RotorcraftData := preload("res://physics/rotorcraft_data.gd")
const GroundStart := preload("res://physics/rotorcraft/ground_start.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var flat := PackedFloat64Array()
	var hub := M.v3(0.0, 0.0, 0.0)
	var main_axis := M.v3(0.0, 0.0, -1.0)
	var tail_axis := M.v3(0.0, 1.0, 0.0)
	var a := _state(0.0, 0.0, -0.3, M.q_identity())
	var b := _state(0.0, 0.0, -0.05, M.q_identity())
	var clear := Disc.first(a, a, hub, main_axis, 0.775, flat)
	_check("level main disc clears flat ground", clear.ok and is_inf(clear.fraction))
	var hit := Disc.first(a, b, hub, tail_axis, 0.13, flat)
	_check("flat tail sweep reports actual crossing", hit.ok and is_finite(hit.fraction) and _witness(hit, flat))
	if hit.ok and is_finite(hit.fraction):
		var exact := (0.3 - 0.13) / 0.25
		_check("flat tail onset lies in returned interval", hit.fraction - hit.uncertainty <= exact \
			and exact <= hit.fraction and hit.uncertainty <= Disc.FRACTION_TOLERANCE)
	var early_stop := Disc.first(a, b, hub, tail_axis, 0.13, flat, {}, 0.5)
	var later_stop := Disc.first(a, b, hub, tail_axis, 0.13, flat, {}, 0.75)
	_check("bounded sweep stop excludes only later contact", early_stop.ok and is_inf(early_stop.fraction) \
		and later_stop.ok and is_finite(later_stop.fraction) and _witness(later_stop, flat))
	var qflip := M.q_from_axis_angle(M.v3(1.0, 0.0, 0.0), PI)
	var swing_a := _state(0.0, 0.0, -0.5, M.q_identity())
	var swing_b := _state(0.0, 0.0, -0.5, qflip)
	var endpoint_a := Disc.first(swing_a, swing_a, hub, main_axis, 1.0, flat)
	var endpoint_b := Disc.first(swing_b, swing_b, hub, main_axis, 1.0, flat)
	var swung := Disc.first(swing_a, swing_b, hub, main_axis, 1.0, flat)
	_check("clear endpoints can hide a swept disc strike", endpoint_a.ok and is_inf(endpoint_a.fraction) \
		and endpoint_b.ok and is_inf(endpoint_b.fraction) and swung.ok and is_finite(swung.fraction) \
		and swung.fraction > 0.0 and swung.fraction < 1.0 and _witness(swung, flat))
	var near := _state(0.0, 0.0, -0.130001, M.q_identity())
	var near_clear := Disc.first(near, near, hub, tail_axis, 0.13, flat)
	_check("near-flat clear tail needs no sampling guess", near_clear.ok and is_inf(near_clear.fraction))
	var almost_horizontal := _state(0.0, 0.0, -4.0e-9, M.q_identity())
	var tiny_tilt := M.v3(1.0e-8, 0.0, 1.0)
	var tiny_hit := Disc.first(almost_horizontal, almost_horizontal, hub, tiny_tilt, 0.775, flat)
	_check("near-horizontal support does not cancel to zero", tiny_hit.ok and tiny_hit.fraction == 0.0 \
		and _witness(tiny_hit, flat) and _in_disc(tiny_hit, hub, tiny_tilt, 0.775))
	var tangent := _state(0.0, 0.0, -0.13, M.q_identity())
	var unresolved := Disc.first(tangent, tangent, hub, tail_axis, 0.13, flat, {}, 1.0, 1)
	_check("budget exhaustion refuses a boundary, never fabricates impact", not unresolved.ok)
	var rough := PackedFloat64Array([-INF, INF, -INF, INF, 0.8, 7.5])
	var crest := _state(200.0, 200.274, -0.003, M.q_identity())
	var center_depth := crest[2] + Terrain.sample_validated(crest[0], crest[1], rough)[0]
	var crest_point := Terrain.sample_validated(200.0 - 0.58125, 200.274 + 0.34875, rough)[0] + crest[2]
	var crest_result := Disc.first(crest, crest, hub, main_axis, 0.775, rough)
	_check("interior crest witness is above a clear center", center_depth < 0.0 and crest_point > 0.0)
	_check("stationary horizontal disc detects interior crest", crest_result.ok and crest_result.fraction == 0.0 \
		and _witness(crest_result, rough))
	var wave_a := _state(200.0, 199.75, -0.002, M.q_identity())
	var wave_b := _state(200.0, 200.25, -0.002, M.q_identity())
	var wave_a_check := Disc.first(wave_a, wave_a, hub, main_axis, 0.001, rough)
	var wave_b_check := Disc.first(wave_b, wave_b, hub, main_axis, 0.001, rough)
	var wave_sweep := Disc.first(wave_a, wave_b, hub, main_axis, 0.001, rough)
	_check("clear endpoints do not hide a swept relief crest", wave_a_check.ok and is_inf(wave_a_check.fraction) \
		and wave_b_check.ok and is_inf(wave_b_check.fraction) and wave_sweep.ok \
		and is_finite(wave_sweep.fraction) and wave_sweep.fraction > 0.0 and wave_sweep.fraction < 1.0 \
		and _witness(wave_sweep, rough))
	var tilt := M.q_from_axis_angle(M.v3(1.0, 0.0, 0.0), 0.03)
	var tilted := _state(200.0, 200.274, -0.01, tilt)
	var tilted_result := Disc.first(tilted, tilted, hub, main_axis, 0.775, rough)
	_check("tilted main disc uses bounded support on relief", tilted_result.ok and tilted_result.fraction == 0.0 \
		and _witness(tilted_result, rough))
	_test_a15_reconstructed_tick(rough)
	_test_stock_pad()
	var loaded := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("stock lake loads", loaded.ok)
	if loaded.ok:
		var lake: Dictionary = loaded.lake
		var lake_state := _state(110.0, 125.0, 0.10, M.q_identity())
		var lake_clear := Disc.first(lake_state, lake_state, hub, main_axis, 0.1, flat, lake)
		_check("lake bed does not create a dry-datum impact", lake_clear.ok and is_inf(lake_clear.fraction))
		var displaced := lake.duplicate(true)
		for i: int in range(0, displaced.bank_ne_m.size(), 2): displaced.bank_ne_m[i] += 1000.0
		displaced.identity = LakeLoader.identity(displaced)
		_check("nonnested lake is structurally admitted", Lake.is_valid_definition(displaced))
		var exposed := Disc.first(lake_state, lake_state, hub, main_axis, 0.1, flat, displaced)
		_check("shore without bank cannot hide dry contact", exposed.ok and exposed.fraction == 0.0 \
			and _witness(exposed, flat, displaced))
		var narrow := lake.duplicate(true)
		narrow.shoreline_ne_m = PackedFloat64Array([38.0, -5.0, 38.5, -5.0, 39.0, -5.0,
			39.0, -4.5, 39.0, -3.0, 38.5, -3.0, 38.0, -3.0, 38.0, -4.0])
		var bank_edge := 39.0 + 1.5e-8
		narrow.bank_ne_m = PackedFloat64Array([37.0, -6.0, 38.0, -6.0, bank_edge, -6.0,
			bank_edge, -4.5, bank_edge, -2.0, 38.0, -2.0, 37.0, -2.0, 37.0, -4.0])
		narrow.identity = LakeLoader.identity(narrow)
		var edge_a := _state(39.0 - 1.0e-6, -4.0, 0.3, M.q_identity())
		var edge_b := _state(39.0 + 1.0e-6, -4.0, 0.3, M.q_identity())
		var edge_hit := Disc.first(edge_a, edge_b, hub, main_axis, 1.0e-9, flat, narrow)
		_check("epsilon-width bank is admitted and cannot hide an observed dry point",
			Lake.is_valid_definition(narrow) and Terrain.sample_validated(edge_b[0], edge_b[1], flat, narrow)[0] + edge_b[2] > 0.0 \
			and (not edge_hit.ok or (is_finite(edge_hit.fraction) and _witness(edge_hit, flat, narrow))))
	var malformed := Disc.first(a, b, hub, M.v3(0.0, 0.0, 0.0), 1.0, flat)
	_check("invalid axis is refused", not malformed.ok)
	print("H05 rotor disc terrain: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _state(n: float, e: float, d: float, q: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(n, e, d), M.v3(0.0, 0.0, 0.0), q, M.v3(0.0, 0.0, 0.0))


func _witness(result: Dictionary, surfaces: PackedFloat64Array, lake: Dictionary = {}) -> bool:
	var point: PackedFloat64Array = result.point_world_ned
	var terrain := Terrain.sample_validated(point[0], point[1], surfaces, lake)
	return point[2] + terrain[0] > 0.0 and absf(point[2] + terrain[0] - float(result.depth_m)) < 1.0e-10


func _in_disc(result: Dictionary, hub: PackedFloat64Array, axis: PackedFloat64Array, radius: float) -> bool:
	var arm := M.sub(result.point_body_frd, hub)
	var normal := M.scale(axis, 1.0 / M.norm(axis))
	return absf(M.dot(arm, normal)) < 1.0e-10 and M.norm(arm) <= radius + 1.0e-10


func _test_a15_reconstructed_tick(rough: PackedFloat64Array) -> void:
	# Production 240 Hz X-Cell tick reconstructed from A15's inverted reset;
	# the accepted end flap defines this collision proxy throughout the pose sweep.
	var initial := PackedFloat64Array([200.0, 200.274, -0.245, 0.0, 0.0, -1.68,
		0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var endpoint := PackedFloat64Array([200.00000000290902, 200.27400734997218, -0.23787687888699313,
		-6.232500111808289e-06, -0.00349406132642931, -1.7395374679499014,
		1.6010461213943333e-05, 0.9999999998156428, 1.032508455176577e-05, -2.402523881449241e-06,
		-0.016653583080729308, -0.0027559710992543004, -0.009734793896632723])
	var flap_a := -0.0001905803869617313
	var flap_b := -0.005736219462627656
	var axis := M.v3(-M.sin_(flap_a), M.sin_(flap_b), -M.cos_(flap_a) * M.cos_(flap_b))
	var hub := M.v3(0.0, 0.0, -0.235)
	var endpoint_hit := Disc.first(endpoint, endpoint, hub, axis, 0.775, rough)
	_check("A15 inverted endpoint has a real rotor-disc penetration", endpoint_hit.ok \
		and endpoint_hit.fraction == 0.0 and _witness(endpoint_hit, rough) and _in_disc(endpoint_hit, hub, axis, 0.775))
	var swept_hit := Disc.first(initial, endpoint, hub, axis, 0.775, rough)
	_check("A15 inverted sweep has a bounded, observed strike", swept_hit.ok \
		and is_finite(swept_hit.fraction) and swept_hit.uncertainty <= Disc.FRACTION_TOLERANCE \
		and _witness(swept_hit, rough) and _in_disc(swept_hit, hub, axis, 0.775))


func _test_stock_pad() -> void:
	var loaded_field := FieldLoader.load_from()
	var aircraft := RotorcraftData.load_file("res://data/aircraft/xcell_60_research.json")
	_check("stock pad and X-Cell load", loaded_field.ok and aircraft.ok)
	if not loaded_field.ok or not aircraft.ok: return
	var table := GroundSurfaces.build(GroundSurfaces.load_table().table, loaded_field.field)
	var ground := GroundStart.resolve(loaded_field.field, aircraft)
	_check("stock pad geometry prepares", table.ok and ground.ok)
	if not table.ok or not ground.ok: return
	var surfaces: PackedFloat64Array = table.rects
	var rest: PackedFloat64Array = ground.state
	var yaw := M.q_to_euler(rest.slice(6, 10))[0]
	var q := M.q_from_euler(yaw, 0.4, PI)
	for i: int in 4: rest[6 + i] = q[i]
	rest[2] = -0.65
	var end := rest.duplicate()
	end[2] += 0.15
	end[5] = 2.5
	var tail: Dictionary = aircraft.context.tail_model
	var tail_hub := M.v3(-float(tail.hub_distance_aft_m), 0.0, -float(tail.hub_height_above_cg_m))
	var tail_axis := M.v3(0.0, 1.0, 0.0)
	var tail_radius: float = tail.tail_rotor_radius_m
	var stock_hit := Disc.first(rest, end, tail_hub, tail_axis, tail_radius, surfaces)
	var planar_hit := Disc.first(rest, end, tail_hub, tail_axis, tail_radius, PackedFloat64Array())
	_check("stock pad tail strike matches exact plane sweep", stock_hit.ok and planar_hit.ok \
		and is_finite(stock_hit.fraction) and stock_hit.fraction == planar_hit.fraction \
		and stock_hit.uncertainty == planar_hit.uncertainty and _witness(stock_hit, surfaces))
	var main: Dictionary = aircraft.context.main_model
	var main_hub := M.v3(main.hub_x_m, main.hub_y_m, main.hub_z_m)
	var main_axis := M.v3(0.0, 0.0, -1.0)
	var main_q := M.q_from_euler(yaw, -PI / 2.0, 0.0)
	for i: int in 4: rest[6 + i] = main_q[i]
	var rotated_hub := M.q_rotate(main_q, main_hub)
	rest[2] = -rotated_hub[2] - float(main.rotor_radius_m) - 0.002
	end = rest.duplicate()
	end[2] += 0.004
	var main_hit := Disc.first(rest, end, main_hub, main_axis, main.rotor_radius_m, surfaces)
	var plane_main := Disc.first(rest, end, main_hub, main_axis, main.rotor_radius_m, PackedFloat64Array())
	_check("stock pad main strike matches exact plane sweep", main_hit.ok and plane_main.ok \
		and is_finite(main_hit.fraction) and main_hit.fraction == plane_main.fraction \
		and main_hit.uncertainty == plane_main.uncertainty and _witness(main_hit, surfaces))
	var bounds := PackedFloat64Array()
	var edge := _state(8.45, 0.0, -0.1, M.q_identity())
	_check("pad feather crossing cannot enter flat fast path", not Disc._flat_over_sweep(edge, edge,
		M.v3(0.0, 0.0, 0.0), 0.1, surfaces, bounds, 1.0))
	var outside := _state(9.1, 0.0, -0.1, M.q_identity())
	var middle := _state(6.0, 0.0, -0.1, M.q_identity())
	_check("swept footprint leaving the pad cannot enter flat fast path", not Disc._flat_over_sweep(middle, outside,
		M.v3(0.0, 0.0, 0.0), 0.1, surfaces, bounds, 1.0))
	var rotating := outside.duplicate()
	var rotated := M.q_from_euler(0.7, 0.9, 1.1)
	for i: int in 4: rotating[6 + i] = rotated[i]
	var offset_hub := M.v3(0.2, 0.3, -0.4)
	_check("partial sweep with offset rotating hub is admitted only while its whole bound fits",
		Disc._flat_over_sweep(middle, rotating, offset_hub, 0.1, surfaces, bounds, 0.5) \
		and not Disc._flat_over_sweep(middle, rotating, offset_hub, 0.1, surfaces, bounds, 1.0))
	var overlap := PackedFloat64Array([5.4, 5.6, -0.4, 0.4, 0.8, 7.5,
		3.0, 9.0, -3.0, 3.0, 0.8, 0.5, -INF, INF, -INF, INF, 0.8, 7.5])
	var overlay := _state(5.5, 0.0, -0.1, M.q_identity())
	_check("higher-precedence partial mask prevents a false flat proof", Terrain.is_valid_surface_table(overlap) \
		and absf(Terrain.sample_validated(5.5, 0.0, overlap)[0]) > 1.0e-12 \
		and not Disc._flat_over_sweep(overlay, overlay, M.v3(0.0, 0.0, 0.0), 0.05, overlap, bounds, 1.0))
	var shifted: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH).lake
	for key: String in ["shoreline_ne_m", "bank_ne_m"]:
		for i: int in range(0, shifted[key].size(), 2):
			shifted[key][i] -= 104.0
			shifted[key][i + 1] -= 125.0
	shifted.identity = LakeLoader.identity(shifted)
	var bed := _state(6.0, 0.0, 0.1, M.q_identity())
	var edge_lake := shifted.duplicate(true)
	var bank_min: float = Disc._bank_bounds(edge_lake)[0]
	var shift_north := 6.0 + 0.05 - 0.0001 - bank_min
	for key: String in ["shoreline_ne_m", "bank_ne_m"]:
		for i: int in range(0, edge_lake[key].size(), 2): edge_lake[key][i] += shift_north
	_check("overlap with a lake bank AABB edge prevents flat admission",
		not Disc._flat_over_sweep(bed, bed, M.v3(0.0, 0.0, 0.0), 0.05, surfaces, Disc._bank_bounds(edge_lake), 1.0))
	var dry_hit := Disc.first(bed, bed, M.v3(0.0, 0.0, 0.0), main_axis, 0.05, surfaces)
	var wet_clear := Disc.first(bed, bed, M.v3(0.0, 0.0, 0.0), main_axis, 0.05, surfaces, shifted)
	_check("lake overlapping the pad cannot use a dry flat plane", dry_hit.ok and is_finite(dry_hit.fraction) \
		and wet_clear.ok and is_inf(wet_clear.fraction))


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)
