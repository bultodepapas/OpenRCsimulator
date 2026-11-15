extends SceneTree

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Loader := preload("res://data/lake_loader.gd")
const LakeSurface := preload("res://physics/lake_surface.gd")
const HullContact := preload("res://physics/hull_contact.gd")
const LakeCollision := preload("res://sim/lake_collision.gd")

const MASS := 5.0
const PI_VALUE := 3.14159265358979323846

var _failures: int = 0
var _inertia := PackedFloat64Array([1.0, 1.0, 1.0, 0.0, 0.0, 0.0])


func _initialize() -> void:
	var loaded: Dictionary = Loader.load_from("res://data/fields/lake.json")
	_check("authored lake definition loads", bool(loaded.get("ok", false)), str(loaded.get("errors", [])))
	if not bool(loaded.get("ok", false)):
		quit(1)
		return
	var lake: Dictionary = loaded.lake
	_test_invalid_and_outside(lake)
	_test_vertical_airborne_reject(lake)
	_test_water_and_hull_first(lake)
	_test_water_grazing(lake)
	_test_bank_policy_and_gear(lake)
	_test_rotating_wing(lake)
	_test_prop_disc(lake)
	_test_hull_contact_context(lake)
	_test_surface_normals()
	_test_aircraft_bank_tolerance(lake)
	print("all lake collision checks passed" if _failures == 0 else "%d lake collision checks failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_invalid_and_outside(lake: Dictionary) -> void:
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var previous := _state([400.0, 400.0, -1.0], [0.0, 0.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var candidate := _state([401.0, 400.0, 1.0], [10.0, 0.0, 20.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	_check("empty lake context has no collision", LakeCollision.first_hit({}, previous, candidate,
		hull, {}, 1, 0.1, MASS, _inertia) == null)
	_check("invalid lake definition fails closed", LakeCollision.first_hit({"format": "bad"}, previous,
		candidate, hull, {}, 1, 0.1, MASS, _inertia) == null)
	_check("flight outside the bounded bank keeps the no-event result", LakeCollision.first_hit(lake,
		previous, candidate, hull, {}, 1, 0.1, MASS, _inertia) == null)
	var outside_polygon_previous := _state([143.0, 150.0, -1.0], [0.0, 0.0, 20.0],
		M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var outside_polygon_candidate := _state([143.0, 150.0, 1.0], [0.0, 0.0, 20.0],
		M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	_check("path inside lake bounds but outside the irregular bank polygon remains clear",
		LakeCollision.first_hit(lake, outside_polygon_previous, outside_polygon_candidate,
			hull, {}, 1, 0.1, MASS, _inertia) == null)


func _test_vertical_airborne_reject(lake: Dictionary) -> void:
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var previous := _state([110.0, 40.0, -0.001], [0.0, 18000.0, 0.0],
		M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var candidate := _state([110.0, 190.0, -0.001], [0.0, 18000.0, 0.0],
		M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	_check("high-speed airborne hull path stays above water and bank without a false event",
		LakeCollision.first_hit(lake, previous, candidate, hull, {}, 1, 1.0 / 240.0,
			MASS, _inertia) == null)
	var wing := PackedFloat64Array([0.0, 0.0, 15.0])
	var deep_altitude_previous := _state([110.0, 125.0, -20.0], [0.0, 0.0, 0.0],
		M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var deep_altitude_candidate := _state([110.0, 125.0, -20.0], [0.0, 0.0, 0.0],
		M.q_from_euler(PI_VALUE, 0.0, 0.0), [0.0, 0.0, 0.0])
	_check("rotating probe whose conservative radius stays above the bank remains clear",
		LakeCollision.first_hit(lake, deep_altitude_previous, deep_altitude_candidate,
			wing, {}, 1, 1.0 / 240.0, MASS, _inertia) == null)


func _test_water_and_hull_first(lake: Dictionary) -> void:
	var previous := _state([110.0, 80.0, -1.0], [0.0, 90.0, 20.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var candidate := _state([110.0, 170.0, 1.0], [0.0, 90.0, 20.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var gear := {"contacts": [{"name": "nose", "position": PackedFloat64Array([0.0, 0.0, 0.0])}]}
	var event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
		hull, gear, 7, 0.1, MASS, _inertia)
	_check("high-speed hull sweep enters water", event != null and event.trigger == "water"
		and event.obstacle_kind == "water" and event.response_class == "hard_terminal"
		and event.damage_profile == "none" and event.terminal,
		str(event))
	if event == null:
		return
	var event_time: float = 0.6 + event.time_fraction * 0.1
	var matching_surface: float = LakeSurface.water_height_down(lake, event.point_ned[0],
		event.point_ned[1], event_time)
	_check("water event carries shared wave surface and sim-clock time", is_finite(matching_surface)
		and absf(event.surface_down_m - matching_surface) < 1.0e-7
		and absf(event.surface_down_m - 0.45) < 0.08,
		"time=%.9f expected_surface=%.9f event_surface=%.9f" % [event_time, matching_surface, event.surface_down_m])
	_check("water event reports local water depth and contact kinematics", event.depth_m > 3.0
		and event.penetration_m >= 0.0 and event.has_kinematics and event.normal_speed_mps > 10.0
		and event.point_index == 0 and event.probe_kind == "hull",
		"depth=%.3f penetration=%.8f speed=%.3f" % [event.depth_m, event.penetration_m, event.normal_speed_mps])
	var epsilon: float = LakeCollision.WATER_SLOPE_EPSILON_M
	var dn: float = (LakeSurface.water_height_down(lake, event.point_ned[0] + epsilon, event.point_ned[1], event_time)
		- LakeSurface.water_height_down(lake, event.point_ned[0] - epsilon, event.point_ned[1], event_time)) / (2.0 * epsilon)
	var de: float = (LakeSurface.water_height_down(lake, event.point_ned[0], event.point_ned[1] + epsilon, event_time)
		- LakeSurface.water_height_down(lake, event.point_ned[0], event.point_ned[1] - epsilon, event_time)) / (2.0 * epsilon)
	_check("water sweep normal is orthogonal to both positive-down surface tangents",
		absf(M.dot(event.normal_ned, PackedFloat64Array([1.0, 0.0, dn]))) < 1.0e-10
		and absf(M.dot(event.normal_ned, PackedFloat64Array([0.0, 1.0, de]))) < 1.0e-10)
	_check("simultaneous hull and gear water contact deterministically favors hull", event.probe_order == 0
		and event.probe_kind == "hull" and event.point_index == 0)
	var off_water_hull := PackedFloat64Array([200.0, 0.0, 0.0])
	var gear_event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
		off_water_hull, gear, 7, 0.1, MASS, _inertia)
	_check("undeformed gear bottom independently reports water contact", gear_event != null
		and gear_event.trigger == "water" and gear_event.probe_kind == "gear"
		and gear_event.point_index == 0 and gear_event.component_name == "nose",
		"kind=%s index=%d" % [gear_event.probe_kind if gear_event != null else "",
			gear_event.point_index if gear_event != null else -1])


func _test_water_grazing(lake: Dictionary) -> void:
	var calm_lake: Dictionary = lake.duplicate(true)
	calm_lake["waves"] = []
	var previous := _state([110.0, 150.0, 0.45], [0.0, -10.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var candidate := _state([110.0, 145.0, 0.45], [0.0, -10.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var event: LakeCollision.WaterEvent = LakeCollision.first_hit(calm_lake, previous, candidate,
		PackedFloat64Array([0.0, 0.0, 0.0]), {}, 3, 0.5, MASS, _inertia)
	_check("grazing point on the water plane remains a deterministic contact", event != null
		and event.trigger == "water" and event.normal_speed_mps <= 1.0e-8
		and is_finite(event.surface_down_m),
		"event=%s speed=%.12f" % [str(event), event.normal_speed_mps if event != null else -1.0])


func _test_bank_policy_and_gear(lake: Dictionary) -> void:
	var low_previous := _state([110.0, 177.0, 0.01], [0.0, -0.03, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var low_candidate := _state([110.0, 174.0, 0.01], [0.0, -0.03, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	_check("soft low-speed bank touch remains a ground contact", LakeCollision.first_hit(lake,
		low_previous, low_candidate, hull, {}, 1, 0.1, MASS, _inertia, true) == null)
	var bank_previous := _state([110.0, 177.0, 0.5], [0.0, -100.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var bank_candidate := _state([110.0, 174.0, 0.5], [0.0, -100.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var bank_event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, bank_previous,
		bank_candidate, hull, {}, 1, 0.1, MASS, _inertia, false)
	_check("terminal bank mode reports a dry-bank hull strike", bank_event != null
		and bank_event.trigger == "lake_bank" and bank_event.obstacle_kind == "lake_bank"
		and bank_event.material == "bank_ground" and bank_event.depth_m > 0.08,
		str(bank_event))
	var gear := {"contacts": [{"name": "main", "position": PackedFloat64Array([0.0, 0.0, 0.0])}]}
	var off_bank_hull := PackedFloat64Array([200.0, 0.0, 0.0])
	var gear_event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake,
		bank_previous, bank_candidate, off_bank_hull, gear, 1, 0.1, MASS, _inertia, false)
	_check("gear traversing dry bank does not become a terminal water event", gear_event == null,
		"trigger=%s material=%s point=%s fraction=%s" % [gear_event.trigger if gear_event != null else "",
			gear_event.material if gear_event != null else "", gear_event.point_ned if gear_event != null else PackedFloat64Array(),
			gear_event.time_fraction if gear_event != null else -1.0])


func _test_rotating_wing(lake: Dictionary) -> void:
	var q0: PackedFloat64Array = M.q_from_euler(0.0, 0.0, 0.0)
	var q1: PackedFloat64Array = M.q_from_euler(0.0, 0.0, PI_VALUE * 0.5)
	var previous := _state([110.0, 125.0, -1.0], [0.0, 0.0, 3.0], q0, [PI_VALUE, 0.0, 0.0])
	var candidate := _state([110.0, 125.0, 1.0], [0.0, 0.0, 3.0], q1, [PI_VALUE, 0.0, 0.0])
	var wing := PackedFloat64Array([0.0, 20.0, 0.0])
	var event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
		wing, {}, 1, 0.5, MASS, _inertia)
	_check("rotating wing probe sweeps through water", event != null and event.trigger == "water"
		and event.point_index == 0 and event.time_fraction > 0.0 and event.time_fraction < 1.0,
		str(event))
	if event != null:
		_check("rotating wing event preserves point angular velocity", M.norm(event.velocity_ned) > 25.0
			and event._state_at_contact.size() == RB.SIZE and event.crossing.available,
			"velocity=%s fraction=%.6f" % [event.velocity_ned, event.time_fraction])
		_check("rotating point impact speed projects its complete velocity", absf(event.normal_speed_mps
			- maxf(0.0, -M.dot(event.velocity_ned, event.normal_ned))) < 1.0e-10)


func _test_prop_disc(lake: Dictionary) -> void:
	var previous := _state([110.0, 125.0, -1.0], [0.0, 0.0, 20.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var candidate := _state([110.0, 125.0, 1.0], [0.0, 0.0, 20.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var off_water_hull := PackedFloat64Array([200.0, 0.0, 0.0])
	var disc := {"hub": PackedFloat64Array([0.0, 0.0, 0.0]),
		"axis": PackedFloat64Array([1.0, 0.0, 0.0]), "radius": 0.1}
	var event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
		off_water_hull, {}, 1, 0.1, MASS, _inertia, true, disc)
	_check("optional propeller disc is a swept water probe", event != null and event.trigger == "water"
		and event.probe_kind == "propeller" and event.point_index == -1
		and event.component_name == "propeller",
		"kind=%s fraction=%s" % [event.probe_kind if event != null else "",
			event.time_fraction if event != null else -1.0])


func _test_hull_contact_context(lake: Dictionary) -> void:
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var prepared_flat: Dictionary = HullContact.prepare(hull, MASS, _inertia)
	var prepared_lake: Dictionary = HullContact.prepare(hull, MASS, _inertia, lake)
	var outside_previous := _state([400.0, 400.0, 0.0], [0.0, 0.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var outside_current := _state([400.0, 400.0, 0.01], [0.0, 0.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var flat_load: PackedFloat64Array = HullContact.loads(outside_current, prepared_flat)
	var lake_load: PackedFloat64Array = HullContact.loads(outside_current, prepared_lake)
	_check("HullContact lake context keeps outside-bank loads bit-identical", _same_packed(flat_load, lake_load))
	_check("HullContact lake context keeps outside-bank terminal result identical",
		HullContact.terminal(outside_previous, outside_current, prepared_flat)
		== HullContact.terminal(outside_previous, outside_current, prepared_lake))
	_check("HullContact lake context keeps outside-bank contacts identical",
		HullContact.contacts(outside_previous, outside_current, prepared_flat)
		== HullContact.contacts(outside_previous, outside_current, prepared_lake))
	var bed_previous := _state([110.0, 125.0, 5.44], [0.0, 0.0, 3.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var bed_current := _state([110.0, 125.0, 5.46], [0.0, 0.0, 3.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var bed_contacts: Array = HullContact.contacts(bed_previous, bed_current, prepared_lake)
	var bed_load: PackedFloat64Array = HullContact.loads(bed_current, prepared_lake)
	var bed_terminal: Dictionary = HullContact.terminal(bed_previous, bed_current, prepared_lake)
	_check("HullContact soft load, contact, and crash thresholds use basin bed", bed_contacts.size() == 1
		and absf(float(bed_contacts[0].depth_m) - 0.01) < 1.0e-8
		and bed_load.size() == 6 and bed_load[2] < 0.0
		and str(bed_terminal.get("rule", "")) == "impact",
		"contacts=%s loads=%s terminal=%s" % [bed_contacts, bed_load, bed_terminal])
	var prop_disc := {"hub": PackedFloat64Array([0.0, 0.0, 0.0]),
		"axis": PackedFloat64Array([1.0, 0.0, 0.0]), "radius": 0.1}
	var prop_state := _state([110.0, 125.0, 0.2], [0.0, 0.0, 0.0], M.q_from_euler(0.0, 0.0, 0.0), [0.0, 0.0, 0.0])
	var prop_depth: Dictionary = HullContact.prop_disc_depth(prop_state, prop_disc, lake, 0.0)
	_check("prop depth is measured from the moving lake surface, avoiding false wet prop strikes",
		float(prop_depth.depth) < 0.0 and absf(float(prop_depth.depth)
			- (float(prop_depth.point_ned[2]) - LakeSurface.water_height_down(lake,
				float(prop_depth.point_ned[0]), float(prop_depth.point_ned[1]), 0.0))) < 1.0e-12,
		str(prop_depth))


func _test_surface_normals() -> void:
	for slopes: Array in [[0.2, 0.0], [-0.2, 0.0], [0.0, 0.3], [0.0, -0.3], [0.2, -0.3], [-0.2, 0.3]]:
		var normal: PackedFloat64Array = LakeCollision._surface_normal(slopes[0], slopes[1])
		var tangent_n := PackedFloat64Array([1.0, 0.0, slopes[0]])
		var tangent_e := PackedFloat64Array([0.0, 1.0, slopes[1]])
		_check("swept normal follows independent down-plane tangents %s" % str(slopes),
			absf(M.dot(normal, tangent_n)) < 1.0e-14 and absf(M.dot(normal, tangent_e)) < 1.0e-14
			and absf(M.norm(normal) - 1.0) < 1.0e-14 and normal[2] < 0.0)
	_check("invalid swept gradients reject", LakeCollision._surface_normal(NAN, 0.0).is_empty()
		and LakeCollision._surface_normal(0.0, INF).is_empty())


func _test_aircraft_bank_tolerance(lake: Dictionary) -> void:
	var hull := PackedFloat64Array([0.0, 0.0, 0.0])
	var q := M.q_from_euler(0.0, 0.0, 0.0)
	var terrain: Dictionary = LakeSurface.sample_terrain_validated(lake, 110.0, 174.0)
	var down: float = terrain.ground_down_m
	var length: float = sqrt(1.0 + terrain.slope_north * terrain.slope_north + terrain.slope_east * terrain.slope_east)
	var normal := PackedFloat64Array([terrain.slope_north / length, terrain.slope_east / length, -1.0 / length])
	var properties := {mass_kg = MASS, cg_body_m = PackedFloat64Array([0.0, 0.0, 0.0]),
		inertia = _inertia, inverse = RB.inertia_inverse(_inertia)}
	var sampler := func(_fraction: float) -> Dictionary:
		return properties
	for tolerance: Dictionary in [{}, {terminal_specific_energy = 12.5, crash_depth = 0.12}]:
		var prepared: Dictionary = HullContact.prepare(hull, MASS, _inertia, lake, PackedFloat64Array(), tolerance)
		var threshold: float = HullContact.terminal_energy(prepared)
		for energy: float in [threshold - 0.00001, threshold + 0.00001]:
			var velocity: PackedFloat64Array = M.scale(normal, -sqrt(2.0 * energy))
			var previous := _state([110.0, 174.0, down - 0.005], Array(velocity), q, [0.0, 0.0, 0.0])
			var candidate := _state([110.0, 174.0, down + 0.005], Array(velocity), q, [0.0, 0.0, 0.0])
			var event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
				hull, {}, 1, 0.01, MASS, _inertia, true, {}, prepared)
			var sampled: Dictionary = LakeCollision.first_hit_sampled(lake, previous, candidate,
				hull, {}, 1, 0.01, sampler, true, {}, prepared)
			var terminal: bool = energy > threshold
			_check("fixed/sampled bank energy boundary %s / %s" % [threshold, energy], sampled.ok
				and (event != null) == terminal and (sampled.event != null) == terminal)
			if event != null and sampled.event != null:
				_check("bank severity uses the geometric normal and coherent mass", absf(event.specific_j_per_kg - energy) < 1.0e-9
					and absf(sampled.event.specific_j_per_kg - energy) < 1.0e-9)
		for depth: float in [0.07999, 0.08001, 0.11999, 0.12001]:
			var candidate := _state([110.0, 174.0, down + depth], [0.0, 0.0, -0.1], q, [0.0, 0.0, 0.0])
			# Starting deep exercises the separating guard. Starting shallow exercises the final crush fallback.
			for initial_depth: float in [depth, 0.001]:
				var previous := _state([110.0, 174.0, down + initial_depth], [0.0, 0.0, -0.1], q, [0.0, 0.0, 0.0])
				var event: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, previous, candidate,
					hull, {}, 1, 0.01, MASS, _inertia, true, {}, prepared)
				var sampled: Dictionary = LakeCollision.first_hit_sampled(lake, previous, candidate,
					hull, {}, 1, 0.01, sampler, true, {}, prepared)
				var terminal: bool = depth > HullContact.crash_depth(prepared)
				_check("fixed/sampled separating and fallback bank depth %s / %s / %s" % [HullContact.crash_depth(prepared), depth, initial_depth],
					sampled.ok and (event != null) == terminal and (sampled.event != null) == terminal)
		var water_previous := _state([110.0, 125.0, 0.4], [0.0, 0.0, 0.1], q, [0.0, 0.0, 0.0])
		var water_candidate := _state([110.0, 125.0, 0.5], [0.0, 0.0, 0.1], q, [0.0, 0.0, 0.0])
		var water: LakeCollision.WaterEvent = LakeCollision.first_hit(lake, water_previous, water_candidate,
			hull, {}, 1, 0.01, MASS, _inertia, true, {}, prepared)
		_check("aircraft bank tolerance retains terminal water contact", water != null and water.trigger == "water")
		var hard_previous := _state([110.0, 174.0, down - 0.005], [0.0, 0.0, 0.1], q, [0.0, 0.0, 0.0])
		var hard_candidate := _state([110.0, 174.0, down + 0.005], [0.0, 0.0, 0.1], q, [0.0, 0.0, 0.0])
		_check("aircraft tolerance retains non-soft bank terminal policy", LakeCollision.first_hit(lake,
			hard_previous, hard_candidate, hull, {}, 1, 0.01, MASS, _inertia, false, {}, prepared) != null)
		var separating := _state([110.0, 174.0, down + 0.10], [0.0, 0.0, -0.1], q, [0.0, 0.0, 0.0])
		var hard_sampled: Dictionary = LakeCollision.first_hit_sampled(lake, separating, separating,
			hull, {}, 1, 0.01, sampler, false, {}, prepared)
		_check("non-soft separating depth retains its shared policy in both APIs", hard_sampled.ok
			and hard_sampled.event != null and LakeCollision.first_hit(lake, separating, separating,
				hull, {}, 1, 0.01, MASS, _inertia, false, {}, prepared) != null)


func _state(pos: Array, vel: Array, attitude: PackedFloat64Array, rate: Array) -> PackedFloat64Array:
	return RB.make_state(PackedFloat64Array(pos), PackedFloat64Array(vel), attitude,
		PackedFloat64Array(rate))


func _same_packed(a: PackedFloat64Array, b: PackedFloat64Array) -> bool:
	if a.size() != b.size():
		return false
	for index: int in a.size():
		if a[index] != b[index]:
			return false
	return true


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])
