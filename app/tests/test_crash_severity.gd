extends SceneTree

const Severity = preload("res://render/crash/severity.gd")

class SnapshotFixture:
	extends RefCounted
	var trigger: String = "hull_contact"
	var has_kinematics: bool = true
	var velocity_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var normal_ned: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, -1.0])
	var component_name: String = ""

var _checks: int = 0
var _failures: int = 0

func _initialize() -> void:
	_mass_speed_angle_surface_checks()
	_component_and_bounds_checks()
	_invalid_input_checks()
	_snapshot_adapter_checks()
	_accumulation_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)

func _mass_speed_angle_surface_checks() -> void:
	var base: Dictionary = Severity.estimate(1.0, 2.0, 0.0, 90.0, "concrete", "fuselage")
	var heavier: Dictionary = Severity.estimate(2.0, 2.0, 0.0, 90.0, "concrete", "fuselage")
	var faster: Dictionary = Severity.estimate(1.0, 4.0, 0.0, 90.0, "concrete", "fuselage")
	_check("mass increases estimated energy", heavier.estimated_energy_j > base.estimated_energy_j)
	_check("normal speed increases estimated energy quadratically", faster.estimated_energy_j > base.estimated_energy_j)
	var shallow: Dictionary = Severity.estimate_from_speed_angle(2.0, 10.0, 20.0, "concrete", "fuselage")
	var steep: Dictionary = Severity.estimate_from_speed_angle(2.0, 10.0, 60.0, "concrete", "fuselage")
	_check("steeper incidence increases estimate at fixed point speed", steep.estimated_energy_j > shallow.estimated_energy_j)
	var grass: Dictionary = Severity.estimate(2.0, 5.0, 0.0, 90.0, "grass", "fuselage")
	var concrete: Dictionary = Severity.estimate(2.0, 5.0, 0.0, 90.0, "concrete", "fuselage")
	_check("hard surface estimate exceeds grass estimate", concrete.estimated_energy_j > grass.estimated_energy_j)
	var mown: Dictionary = Severity.estimate(2.0, 5.0, 0.0, 90.0, 'mown', 'wing')
	var rough: Dictionary = Severity.estimate(2.0, 5.0, 0.0, 90.0, 'rough', 'wing')
	_check('controller surface ids have explicit profiles', mown.surface == 'mown' and rough.surface == 'rough')
	var mown_slide: Dictionary = Severity.estimate(2.0, 0.0, 5.0, 0.0, 'mown', 'wing')
	var mown_grass_slide: Dictionary = Severity.estimate(2.0, 0.0, 5.0, 0.0, 'mown_grass', 'wing')
	var rough_slide: Dictionary = Severity.estimate(2.0, 0.0, 5.0, 0.0, 'rough', 'wing')
	var dirt_slide: Dictionary = Severity.estimate(2.0, 0.0, 5.0, 0.0, 'dirt', 'wing')
	_check('tangential surface aliases share their estimates', mown_slide.estimated_energy_j == mown_grass_slide.estimated_energy_j and rough_slide.estimated_energy_j == dirt_slide.estimated_energy_j)
	_check("raw kinematic energy is surface independent", grass.energy_j == concrete.energy_j)
	_check("class is within C0 to C4", base["class"] >= 0 and base["class"] <= 4)
	for fixture in [[0.5, 0], [2.0, 1], [20.0, 2], [500.0, 3], [2500.0, 4]]:
		var sample: Dictionary = Severity.estimate(2.0, sqrt(2.0 * fixture[0] / 2.0), 0.0, 90.0, 'concrete', 'fuselage')
		_check('class energy bin %d' % fixture[1], sample['class'] == fixture[1])

func _component_and_bounds_checks() -> void:
	var wing: Dictionary = Severity.estimate(3.0, 8.0, 1.0, 82.9, "grass", "wingtip_left")
	var propeller: Dictionary = Severity.estimate(3.0, 8.0, 1.0, 82.9, "grass", "propeller")
	_check("affected component is preserved", wing.component == "wingtip_left")
	_check("component group identifies wingtip", wing.component_group == "wingtip")
	var engine: Dictionary = Severity.estimate(3.0, 8.0, 1.0, 82.9, 'grass', 'engine')
	_check('controller engine id has an explicit group', engine.component_group == 'engine')
	_check("component susceptibility changes bounded damage", propeller.component_damage > wing.component_damage)
	_check("component damage stays in zero to one", wing.component_damage >= 0.0 and wing.component_damage <= 1.0)
	_check("severity stays in zero to one", propeller.severity >= 0.0 and propeller.severity <= 1.0)
	var unknown: Dictionary = Severity.estimate(2.0, 2.0, 0.0, 90.0, "mystery", "")
	_check("unknown surface and component use explicit fallbacks", unknown.surface == "mystery" and unknown.component == "unknown")

func _invalid_input_checks() -> void:
	_check("zero mass is rejected", not Severity.estimate(0.0, 1.0, 0.0, 90.0, "grass", "wing").valid)
	_check("negative velocity is rejected", not Severity.estimate(1.0, -1.0, 0.0, 90.0, "grass", "wing").valid)
	_check("negative tangential velocity is rejected", not Severity.estimate(1.0, 0.0, -1.0, 0.0, "grass", "wing").valid)
	_check("NaN mass is rejected", not Severity.estimate(NAN, 1.0, 0.0, 90.0, "grass", "wing").valid)
	_check('NaN angle is rejected', not Severity.estimate(1.0, 1.0, 0.0, NAN, 'grass', 'wing').valid)
	_check("infinite speed is rejected", not Severity.estimate(1.0, INF, 0.0, 90.0, "grass", "wing").valid)
	_check("overflowed energy is rejected", not Severity.estimate(1.0e308, 1.0e308, 0.0, 90.0, "grass", "wing").valid)
	_check("out-of-range angle is rejected", not Severity.estimate(1.0, 1.0, 0.0, 91.0, "grass", "wing").valid)
	_check("angle inconsistent with components is rejected", not Severity.estimate(1.0, 1.0, 1.0, 90.0, "grass", "wing").valid)
	var zero: Dictionary = Severity.estimate(1.0, 0.0, 0.0, 0.0, "unknown", "wing")
	_check("zero velocity is valid and finite", zero.valid and zero.energy_j == 0.0 and is_finite(zero.severity))

func _snapshot_adapter_checks() -> void:
	var hull := SnapshotFixture.new()
	hull.velocity_ned = PackedFloat64Array([0.0, 0.0, 5.0])
	var point_result: Dictionary = Severity.estimate_snapshot(hull, 2.0, "grass")
	_check("hull snapshot uses detected point kinematics", point_result.valid and not point_result.kinematics_is_proxy and point_result.sample_time == "detected_tick_point")
	_check("unlabelled hull uses labelled fuselage estimate", point_result.component == "fuselage_estimate" and point_result.component_is_estimate)
	_check("flat-ground normal gives downward impact speed", absf(point_result.speed_mps - 5.0) < 1e-12 and point_result.impact_angle_deg == 90.0)
	var departing := SnapshotFixture.new()
	departing.velocity_ned = PackedFloat64Array([0.0, 0.0, -5.0])
	var departing_result: Dictionary = Severity.estimate_snapshot(departing, 2.0, "grass")
	_check("separating normal motion has no tangent exposure", departing_result.valid and departing_result.energy_j == 0.0 and departing_result.component_damage == 0.0)
	var gear := SnapshotFixture.new()
	gear.trigger = "gear_limit"
	gear.has_kinematics = false
	gear.component_name = "left"
	var gear_without_proxy: Dictionary = Severity.estimate_snapshot(gear, 2.0, "grass")
	var gear_with_proxy: Dictionary = Severity.estimate_snapshot(gear, 2.0, "grass", "", PackedFloat64Array([0.0, 0.0, 5.0]))
	_check("gear estimate stays unavailable without a velocity proxy", not gear_without_proxy.valid)
	_check("gear uses CG velocity only as a marked proxy", gear_with_proxy.valid and gear_with_proxy.kinematics_is_proxy and gear_with_proxy.sample_time == "cg_proxy")
	_check("gear component keeps its leg name", gear_with_proxy.component == "gear_left")

func _accumulation_checks() -> void:
	var event: Dictionary = Severity.estimate(2.0, 6.0, 0.0, 90.0, "concrete", "wingtip_left")
	var empty: Dictionary = {}
	var first: Dictionary = Severity.accumulate_damage(empty, event)
	var first_damage: float = first.damage_by_component["wingtip_left"]
	var second: Dictionary = Severity.accumulate_damage(first, event)
	_check("accumulation does not mutate its input", empty.is_empty())
	_check("repeated event increases component damage", second.damage_by_component["wingtip_left"] > first_damage)
	_check("component damage never exceeds one", second.damage_by_component["wingtip_left"] <= 1.0)
	_check("event count advances", second.event_count == 2)
	var repeated: Dictionary = {}
	for index in range(60):
		repeated = Severity.accumulate_damage(repeated, event)
	_check("repeated impacts raise the cumulative class", repeated["class"] >= event.class)
	_check("cumulative exposure is finite", is_finite(repeated.accumulated_energy_j))
	_check("invalid events do not advance the state", Severity.accumulate_damage(second, {}).event_count == second.event_count)







