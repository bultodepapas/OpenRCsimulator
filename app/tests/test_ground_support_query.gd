## GP-10: detached solid height-field observations and virtual-work consistency.
extends SceneTree

const Support := preload("res://physics/ground_support.gd")
const Terrain := preload("res://physics/ground_terrain.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const SimEnvironment := preload("res://sim/environment.gd")
const Session := preload("res://sim/flight_session.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const Lake := preload("res://physics/lake_surface.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_geometry_and_work()
	_test_legacy_and_explicit_profiles()
	_test_validation()
	_test_precedence_and_detachment()
	_test_environment_and_lake()
	_test_field_integration()
	_test_long_field_identity()
	_test_lake_law_identity()
	print("GP-10 support query: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL ", label, " ", detail)


func _rows() -> PackedFloat64Array:
	return PackedFloat64Array([-2, 2, -2, 2, 0.8, 2.5, -10, 10, -10, 10, 0.6, 5.0,
		-INF, INF, -INF, INF, 0.5, 7.5])


func _regions() -> Array:
	return [{"region_id": "runway_1", "usage_id": "runway", "material_id": "mown_grass"},
		{"region_id": "mown_1", "usage_id": "mown", "material_id": "short_grass"},
		{"region_id": "outside", "usage_id": "rough", "material_id": "rough_grass"}]


func _dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


func _shift(p: PackedFloat64Array, v: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	return PackedFloat64Array([p[0] + dt * v[0], p[1] + dt * v[1], p[2] + dt * v[2]])


func _geometry_case(label: String, prepared: Dictionary, p: PackedFloat64Array,
		lake: Dictionary = {}, tolerance := 1e-7) -> void:
	var v := PackedFloat64Array([0.73, -0.29, 0.41])
	var q := Support.sample(prepared, p, v, 1.5, lake)
	_check(label + " valid solid query", bool(q.get("ok", false)), str(q))
	if not q.get("ok", false): return
	var eps := 0.00001
	var plus := Support.sample(prepared, _shift(p, v, eps), v, 1.5 + eps, lake)
	var minus := Support.sample(prepared, _shift(p, v, -eps), v, 1.5 - eps, lake)
	var numerical_rate: float = (plus.signed_gap_m - minus.signed_gap_m) / (2.0 * eps)
	_check(label + " gap rate matches independent moving-point difference",
		absf(q.gap_rate_mps - numerical_rate) < tolerance,
		"reported=%s finite_difference=%s" % [q.gap_rate_mps, numerical_rate])
	var gradient: PackedFloat64Array = q.gap_gradient_ned
	var normal: PackedFloat64Array = q.normal_ned
	_check(label + " normal has unit length and points out of ground",
		absf(_dot(normal, normal) - 1.0) < 1e-12 and normal[2] < 0.0)
	_check(label + " vertical gap gradient is deliberately not a unit normal",
		gradient[2] == -1.0 and absf(q.normal_velocity_mps * sqrt(_dot(gradient, gradient)) - q.gap_rate_mps) < 1e-12)
	var lambda := 3.7
	var generalized_force := PackedFloat64Array([lambda * gradient[0], lambda * gradient[1], lambda * gradient[2]])
	_check(label + " generalized support force satisfies finite-difference virtual power",
		absf(_dot(generalized_force, v) - lambda * numerical_rate) < lambda * tolerance)
	var displacement := PackedFloat64Array([0.000003, -0.000004, 0.000002])
	var displaced := Support.sample(prepared, _shift(p, displacement, 1.0), v, 1.5, lake)
	_check(label + " virtual work matches actual signed-gap variation",
		absf(_dot(generalized_force, displacement) - lambda * (displaced.signed_gap_m - q.signed_gap_m)) < 1e-8)
	_check(label + " footpoint is vertical and makes no closest-point claim",
		q.gap_kind == "vertical_height" and not q.closest_point_valid
		and q.vertical_footpoint_ned[0] == p[0] and q.vertical_footpoint_ned[1] == p[1]
		and absf(q.vertical_footpoint_ned[2] + q.height_up_m) < 1e-12
		and absf(q.signed_gap_m - (q.vertical_footpoint_ned[2] - p[2])) < 1e-12)
	_check(label + " static surface supplies no artificial motion",
		q.surface_velocity_ned == PackedFloat64Array([0, 0, 0])
		and Support.sample(prepared, p, v, 9.0, lake).signed_gap_m == q.signed_gap_m)


func _test_geometry_and_work() -> void:
	_geometry_case("flat", Support.prepare_legacy(PackedFloat64Array()), PackedFloat64Array([1.2, 2.3, -0.4]))
	var rough := Support.prepare_explicit(PackedFloat64Array([-INF, INF, -INF, INF, 0.6, 7.5]), PackedFloat64Array([0.007]))
	_geometry_case("curved relief", rough, PackedFloat64Array([0.123, 0.287, -0.4]))
	var query := Support.sample(rough, PackedFloat64Array([0.123, 0.287, -0.4]), PackedFloat64Array([1, 0, 0]), 0.0)
	_check("analytic relief reports its derivative coverage", query.derivative_method == "analytic" and query.derivative_stencil_m == 0.0)
	_check("curved fixture has a resolved slope and nonunit gap gradient",
		absf(query.slopes_up[0]) > 0.001 and _dot(query.gap_gradient_ned, query.gap_gradient_ned) > 1.000001)
	var lake := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("sloped basin fixture loads", lake.ok)
	if lake.ok:
		_geometry_case("lake bank slope", Support.prepare_legacy(PackedFloat64Array()),
			PackedFloat64Array([110, 174, -0.4]), lake.lake, 0.0005)


func _test_legacy_and_explicit_profiles() -> void:
	var rows := _rows()
	var legacy := Support.prepare_legacy(rows, _regions())
	for p: PackedFloat64Array in [PackedFloat64Array([0.123, 0.287, -0.4]),
			PackedFloat64Array([1.8, 0.12, 0.0]), PackedFloat64Array([6.2, 3.1, -1.0]),
			PackedFloat64Array([99.1, -7.3, 0.2])]:
		var old := Terrain.sample(p[0], p[1], rows)
		var q := Support.sample(legacy, p, PackedFloat64Array([0, 0, 0]), 0.0)
		_check("legacy query retains exact height and slope bytes at %s" % str(p),
			PackedFloat64Array([q.height_up_m, q.slopes_up[0], q.slopes_up[1]]).to_byte_array() == old.to_byte_array())
	var relief := PackedFloat64Array([0.002, 0.004, 0.007])
	var explicit := Support.prepare_explicit(rows, relief, _regions())
	var changed := rows.duplicate()
	for row in range(0, changed.size(), 6):
		changed[row + 4] = 0.95
		changed[row + 5] = 0.5
	var other := Support.prepare_explicit(changed, relief, _regions())
	var p := PackedFloat64Array([0.123, 0.287, -0.4])
	var a := Support.sample(explicit, p, PackedFloat64Array([0, 0, 0]), 0.0)
	var b := Support.sample(other, p, PackedFloat64Array([0, 0, 0]), 0.0)
	_check("explicit roughness remains independent of both friction channels",
		a.height_up_m == b.height_up_m and a.slopes_up == b.slopes_up)
	_check("changed friction still changes configuration identity", explicit.identity != other.identity)
	var larger := Support.prepare_explicit(rows, PackedFloat64Array([0.004, 0.004, 0.007]), _regions())
	var c := Support.sample(larger, p, PackedFloat64Array([0, 0, 0]), 0.0)
	_check("explicit amplitude independently changes geometry", absf(c.height_up_m - 2.0 * a.height_up_m) < 1e-15
		and absf(c.height_up_m - a.height_up_m) > 1e-6)


func _test_validation() -> void:
	var valid := Support.prepare_legacy(_rows(), _regions())
	var p := PackedFloat64Array([0, 0, -1])
	var v := PackedFloat64Array([0, 0, 0])
	for bad: PackedFloat64Array in [PackedFloat64Array(), PackedFloat64Array([1, 2]),
			PackedFloat64Array([0, 0, NAN]), PackedFloat64Array([INF, 0, 0])]:
		_check("invalid position dimension/finiteness is rejected: %s" % str(bad), not Support.sample(valid, bad, v, 0).ok)
		_check("invalid velocity dimension/finiteness is rejected: %s" % str(bad), not Support.sample(valid, p, bad, 0).ok)
	for time: float in [-1.0, NAN, INF]:
		_check("invalid stage time rejected: %s" % str(time), not Support.sample(valid, p, v, time).ok)
	_check("incomplete surface stride rejected", not Support.prepare_legacy(PackedFloat64Array([0, 1])).ok)
	var no_catchall := PackedFloat64Array([0, 1, 0, 1, 0.5, 5])
	_check("unbounded outside profile required", not Support.prepare_legacy(no_catchall).ok)
	var bad_factor := _rows()
	bad_factor[4] = NAN
	_check("nonfinite physical profile rejected", not Support.prepare_legacy(bad_factor).ok)
	var inverted := _rows()
	inverted[1] = inverted[0]
	_check("zero-width rectangle rejected", not Support.prepare_legacy(inverted).ok)
	for amplitudes: PackedFloat64Array in [PackedFloat64Array([0.001]), PackedFloat64Array([0, -0.1, 0]),
			PackedFloat64Array([0, NAN, 0]), PackedFloat64Array([0, 0.008, 0])]:
		_check("invalid explicit profile rejected: %s" % str(amplitudes), not Support.prepare_explicit(_rows(), amplitudes).ok)
	_check("registry count mismatch rejected", not Support.prepare_legacy(_rows(), [_regions()[0]]).ok)
	var regions := _regions()
	regions[1].region_id = regions[0].region_id
	_check("duplicate region identity rejected", not Support.prepare_legacy(_rows(), regions).ok)
	regions = _regions()
	regions[0].material_id = ""
	_check("blank material identity rejected", not Support.prepare_legacy(_rows(), regions).ok)
	regions = _regions()
	regions[0].usage_id = 7
	_check("nonstring usage identity rejected", not Support.prepare_legacy(_rows(), regions).ok)
	regions = _regions()
	regions[0].region_id = "x".repeat(129)
	_check("unbounded region identity rejected", not Support.prepare_legacy(_rows(), regions).ok)
	regions = _regions()
	regions[0] = "not a region object"
	_check("nonobject registry row rejected", not Support.prepare_legacy(_rows(), regions).ok)
	var unsupported := valid.duplicate(true)
	unsupported.geometry_law = "road-without-adapter"
	_check("unknown geometry fails explicitly", Support.sample(unsupported, p, v, 0).status == "unsupported_geometry")
	_check("malformed lake fails closed", not Support.sample(valid, p, v, 0, {"wrong": true}).ok)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Surfaces.DEFAULT_PATH))
	raw.surfaces.runway.material_id = "test_material"
	raw.surfaces.runway.erase("material_source")
	_check("authored material identity requires provenance", not Surfaces.validate(raw).ok)
	raw.surfaces.runway.material_source = "explicit unit fixture"
	_check("material identity with provenance is accepted", Surfaces.validate(raw).ok)
	for invalid_id: Variant in [7, " ", "x".repeat(129)]:
		var invalid_material := raw.duplicate(true)
		invalid_material.surfaces.runway.material_id = invalid_id
		_check("invalid authored material ID rejected: %s" % str(invalid_id), not Surfaces.validate(invalid_material).ok)
	for invalid_source: Variant in [7, " "]:
		var invalid_material := raw.duplicate(true)
		invalid_material.surfaces.runway.material_source = invalid_source
		_check("invalid material provenance rejected: %s" % str(invalid_source), not Surfaces.validate(invalid_material).ok)


func _test_precedence_and_detachment() -> void:
	var rows := _rows()
	var regions := _regions()
	var prepared := Support.prepare_legacy(rows, regions)
	var p := PackedFloat64Array([0, 0, -1])
	var v := PackedFloat64Array([0, 0, 0])
	for point: PackedFloat64Array in [PackedFloat64Array([-2, -2, -1]), PackedFloat64Array([2, 2, -1]),
			PackedFloat64Array([0, 0, -1])]:
		_check("inclusive overlapping runway edges preserve first-row precedence: %s" % str(point),
			Support.sample(prepared, point, v, 0).region_id == "runway_1")
	_check("outside runway falls through to mown", Support.sample(prepared, PackedFloat64Array([2.00001, 0, -1]), v, 0).region_id == "mown_1")
	_check("outside all bounded rows has explicit catchall identity", Support.sample(prepared, PackedFloat64Array([100, 100, -1]), v, 0).region_id == "outside")
	var identity: String = prepared.identity
	var before := Support.sample(prepared, p, v, 0)
	rows[5] = 0.5
	regions[0].material_id = "tampered"
	_check("prepared data detach setup arrays and dictionaries", Support.sample(prepared, p, v, 0) == before and prepared.identity == identity)
	var relief := PackedFloat64Array([0.001, 0.004, 0.007])
	var explicit := Support.prepare_explicit(_rows(), relief, _regions())
	var explicit_before := Support.sample(explicit, p, v, 0)
	relief[0] = 0.007
	_check("prepared explicit profile detaches amplitude input", Support.sample(explicit, p, v, 0) == explicit_before)
	before.normal_ned[0] = 100.0
	_check("returned sample arrays are detached", Support.sample(prepared, p, v, 0).normal_ned[0] != 100.0)
	var fixture := Support.sample(Support.prepare_legacy(PackedFloat64Array()), p, v, 0)
	var unknown := Support.sample(Support.prepare_legacy(_rows()), p, v, 0)
	_check("empty flat fixture is explicitly dry pavement", fixture.material_resolved and fixture.material_id == "dry_pavement")
	_check("numeric friction is not evidence of material identity", not unknown.material_resolved and unknown.material_id == "unspecified")
	_check("same prepared setup has stable identity", Support.prepare_legacy(_rows(), _regions()).identity == identity)
	var renamed := _regions()
	renamed[0].material_id = "other_authored_material"
	_check("authored material identity contributes to registry identity", Support.prepare_legacy(_rows(), renamed).identity != identity)


func _test_environment_and_lake() -> void:
	var env := SimEnvironment.new()
	env.surfaces = _rows()
	_check("environment installs matching registry", env.install_ground_registry(_regions()))
	var p := PackedFloat64Array([0.123, 0.287, -0.4])
	var v := PackedFloat64Array([0, 0, 0])
	var before := env.sample_support(p, v, 0)
	_check("failed registry install preserves previously accepted names",
		not env.install_ground_registry([_regions()[0]]) and env.sample_support(p, v, 0) == before)
	_check("environment query publishes installed identity", before.material_id == "mown_grass")
	var changed := env.surfaces.duplicate()
	changed[4] = 0.9
	env.surfaces = changed
	var stale := env.sample_support(p, v, 0)
	_check("legacy table mutation invalidates material provenance", stale.material_id == "unspecified"
		and stale.environment_identity != before.environment_identity)
	_check("replacement registry reinstalls identity", env.install_ground_registry(_regions())
		and env.sample_support(p, v, 0).material_id == "mown_grass")
	env.road = func(_north: float, _east: float) -> Dictionary: return {"height": 99.0}
	_check("road cannot silently receive underlying field support", env.sample_support(p, v, 0).status == "unsupported_geometry")
	env.road = func(_north: float, _east: float) -> Dictionary: return {}
	_check("malformed road provider cannot fall back to field support", env.sample_support(p, v, 0).status == "unsupported_geometry")
	env.road = Callable()
	var loaded := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("normalized lake loads for support test", loaded.ok)
	if not loaded.ok: return
	env.lake = loaded.lake
	var center := PackedFloat64Array([110, 125, 0])
	var solid := env.sample_support(center, v, 0.3)
	var bed := Lake.sample_terrain(loaded.lake, 110, 125)
	var water := Lake.water_height_down(loaded.lake, 110, 125, 0.3)
	_check("lake support is solid bed, not moving water", solid.ok and solid.surface_kind == "solid"
		and solid.coverage == "lake_bed" and absf(solid.vertical_footpoint_ned[2] - bed.ground_down_m) < 1e-12
		and absf(solid.vertical_footpoint_ned[2] - water) > 4.0)
	_check("lake coverage cannot borrow grass material from underlying field", solid.material_id == "unspecified" and not solid.material_resolved)
	_check("lake definition participates in geometry identity", loaded.lake.identity in solid.geometry_id)
	_check("lake derivative reports provider approximation and actual stencil",
		solid.derivative_method == "provider_finite_difference" and solid.derivative_stencil_m == Lake.SAMPLE_EPSILON_M)
	var outside := env.sample_support(PackedFloat64Array([200, 200, 0]), v, 0)
	_check("outside lake retains original field geometry", outside.coverage == "field")
	env.lake = {}
	var without_lake := env.sample_support(PackedFloat64Array([200, 200, 0]), v, 0)
	_check("lake provider identity persists even outside coverage",
		outside.environment_identity != without_lake.environment_identity
		and outside.height_up_m == without_lake.height_up_m)


func _test_field_integration() -> void:
	var field := FieldLoader.load_from()
	var table := Surfaces.load_table()
	_check("current field and material table load", field.ok and table.ok)
	if not field.ok or not table.ok: return
	var built := Surfaces.build(table.table, field.field)
	var player := Session.new()
	player.input_enabled = false
	player.setup()
	_check("real session installs built field provenance", player.set_field(field.field))
	var checkpoint := var_to_bytes(player.sim.checkpoint())
	var session_checkpoint := var_to_bytes(player.checkpoint())
	var found := false
	for region: Dictionary in field.field.surfaces:
		if region.type != "runway": continue
		var p := PackedFloat64Array([region.center_north, region.center_east, -1])
		var q := player.environment.sample_support(p, PackedFloat64Array([1, 0, 0]), 0)
		found = true
		_check("actual field retains runway identity and authored material", q.ok and q.region_id == "field:" + str(region.id)
			and q.usage_id == "runway" and q.material_resolved and q.material_id == "maintained_turf" and q.material_id == table.table.runway.material_id)
		var legacy := Terrain.sample(p[0], p[1], built.rects)
		_check("actual field support remains byte-identical legacy geometry",
			PackedFloat64Array([q.height_up_m, q.slopes_up[0], q.slopes_up[1]]).to_byte_array() == legacy.to_byte_array())
		break
	_check("actual field provides a runway fixture", found)
	_check("support queries leave entire solver checkpoint unchanged", var_to_bytes(player.sim.checkpoint()) == checkpoint)
	_check("support queries leave entire session checkpoint unchanged", var_to_bytes(player.checkpoint()) == session_checkpoint)
	player.free()


func _test_lake_law_identity() -> void:
	var player := Session.new()
	player.input_enabled = false
	player.soft_hull_contacts = true
	player.setup()
	_check("no-lake trace does not declare the lake-only hull law", not player.trace_meta().has("hull_lake_normal_model"))
	var loaded := LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("lake context installs at the accepted launch boundary", loaded.ok and player.set_lake_context(loaded.lake))
	_check("lake trace declares corrected positive-down normal law",
		player.trace_meta().get("hull_lake_normal_model", "") == "positive-down-bank-gradient-normal-v2")
	var snapshot: Dictionary = player.checkpoint()
	_check("current lake checkpoint retains configuration identity", not snapshot.is_empty()
		and typeof(snapshot.get("configuration")) == TYPE_STRING and not str(snapshot.configuration).is_empty())
	_check("current lake checkpoint round-trips under its declared law", player.restore_checkpoint(snapshot))
	_check("restored lake trace keeps the same hull normal law",
		player.trace_meta().get("hull_lake_normal_model", "") == "positive-down-bank-gradient-normal-v2")
	player.free()


func _test_long_field_identity() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FieldLoader.DEFAULT_PATH))
	var long_id := "s".repeat(123)
	raw.runway = long_id
	for surface: Dictionary in raw.surfaces:
		if surface.type == "runway": surface.id = long_id
	var field := FieldLoader.validate(raw)
	_check("historically valid long surface ID still passes the field contract", field.ok, str(field.get("errors", [])))
	if not field.ok: return
	var table := Surfaces.load_table()
	var built := Surfaces.build(table.table, field.field)
	_check("observational registry cannot reject a valid long field ID", built.ok, str(built.get("errors", [])))
	if not built.ok: return
	var expected := "field_sha256:" + long_id.sha256_text()
	_check("long field identity has a deterministic bounded encoding",
		built.regions[0].region_id == expected and expected.length() <= 128
		and Surfaces.build(table.table, field.field).regions[0].region_id == expected)
	var boundary: Dictionary = field.field.duplicate(true)
	for surface: Dictionary in boundary.surfaces:
		if surface.type == "runway": surface.id = "s".repeat(122)
	_check("maximum direct field identity retains its authored name",
		Surfaces.build(table.table, boundary).regions[0].region_id == "field:" + "s".repeat(122))
	var literal: Dictionary = field.field.duplicate(true)
	for surface: Dictionary in literal.surfaces:
		if surface.type == "runway": surface.id = "sha256:" + long_id.sha256_text()
	var literal_built := Surfaces.build(table.table, literal)
	_check("builder literal encoded-looking ID has a disjoint namespace",
		literal_built.ok and literal_built.regions[0].region_id != expected
		and literal_built.regions[0].region_id == "field:sha256:" + long_id.sha256_text())
	var player := Session.new()
	player.input_enabled = false
	player.setup()
	_check("valid long field ID remains installable in a real flight session", player.set_field(field.field) and player.is_flyable())
	for surface: Dictionary in field.field.surfaces:
		if surface.type != "runway": continue
		var p := PackedFloat64Array([surface.center_north, surface.center_east, -1])
		var q := player.environment.sample_support(p, PackedFloat64Array([0, 0, 0]), 0)
		_check("real field query publishes the bounded long identity and material",
			q.ok and q.region_id == expected and q.material_id == "maintained_turf")
		break
	player.free()
