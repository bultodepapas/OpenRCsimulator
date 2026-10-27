## CR-08b: proportional, size-consistent crash grading (docs/plans/crash-realism.md §3.1).
## Effective-mass ratios are the CR-00 measurements (research/crash-damage/cr-00/results.txt).
extends SceneTree

const Severity = preload("res://render/crash/severity.gd")
const EffectiveMass = preload("res://physics/effective_mass.gd")
const CollisionWorld := preload("res://scenery/collision_world.gd")
const Collision := preload("res://sim/scenery_collision.gd")
const RB := preload("res://physics/rigid_body.gd")

const STIK_KG := 2.89
const P51_KG := 21.5
const AVANTI_KG := 11.71

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_plan_cases()
	_size_invariance()
	_slapdown()
	_channels_and_inputs()
	_effective_mass_helper()
	_scenery_parity()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("ok   " if ok else "FAIL ") + label)


func _grade(mass: float, ratio: float, v_n: float, v_t: float, surface: String, component: String) -> Dictionary:
	return Severity.estimate(mass, v_n, v_t, rad_to_deg(atan2(v_n, v_t)), surface, component, mass * ratio)


func _plan_cases() -> void:
	# [label, mass, m_eff/m, v_n, v_t, surface, component, expected class]
	var cases := [
		["Stik wingtip brush in a low pass", STIK_KG, 0.07, 0.5, 15.0, "grass", "wing", 0],
		["Stik firm belly touch", STIK_KG, 1.0, 1.5, 12.0, "grass", "fuselage", 1],
		["Stik wingtip, cartwheel entry", STIK_KG, 0.07, 10.0, 8.0, "grass", "wing", 2],
		["Stik vertical nose-in 15 m/s", STIK_KG, 1.0, 15.0, 0.0, "grass", "engine", 3],
		["Stik vertical nose-in 30 m/s", STIK_KG, 1.0, 30.0, 0.0, "grass", "engine", 4],
		# GP-07d: these landings are on a paved runway; the club field's "runway" is a mown grass strip.
		["P-51 belly landing", P51_KG, 0.94, 1.0, 25.0, "asphalt", "fuselage", 1],
		["P-51 vertical nose-in 15 m/s", P51_KG, 1.0, 15.0, 0.0, "grass", "engine", 3],
		["Avanti wingtip on landing", AVANTI_KG, 0.07, 1.0, 30.0, "asphalt", "wing", 1],
	]
	for item: Array in cases:
		var result := _grade(item[1], item[2], item[3], item[4], item[5], item[6])
		print("     %s: eps %.3f J/kg, abrasion %.3f J/kg -> C%d" % [item[0], result.specific_energy_j_per_kg, result.abrasion_j_per_kg, result["class"]])
		_check("%s grades C%d" % [item[0], item[7]], result.valid and result["class"] == item[7])
	var belly := _grade(P51_KG, 0.94, 1.0, 25.0, "asphalt", "fuselage")
	_check("P-51 belly landing is a scrape from abrasion, not a normal-channel break", belly.normal_class == 0 and belly.abrasion_class == 1)


func _slapdown() -> void:
	# Zero body rates: the CG's normal velocity equals the struck point's.
	var dive_v := 20.0 * sqrt(0.5)
	var nose_only := Severity.estimate(AVANTI_KG, dive_v, dive_v, 45.0, "grass", "engine", AVANTI_KG * 0.20)
	var with_slap := Severity.estimate(AVANTI_KG, dive_v, dive_v, 45.0, "grass", "engine", AVANTI_KG * 0.20, 1.0, dive_v)
	_check("Vantage Jet 45 deg dive at 20 m/s: nose contact alone grades C2", nose_only["class"] == 2 and nose_only.slapdown_class == 0)
	_check("Vantage Jet 45 deg dive at 20 m/s: slapdown raises it to C3", with_slap["class"] == 3 and with_slap.slapdown_class == 3)
	var expected := (0.5 * AVANTI_KG * dive_v * dive_v - 0.5 * AVANTI_KG * 0.20 * dive_v * dive_v) * Severity.SURFACE_TRANSFER["grass"]
	_check("slapdown energy is the CG normal energy left after the first contact", absf(with_slap.slapdown_energy_j - expected) < 1e-9)
	var cartwheel := Severity.estimate(STIK_KG, 10.0, 8.0, rad_to_deg(atan2(10.0, 8.0)), "grass", "wing", STIK_KG * 0.07, 1.0, 10.0)
	_check("Stik wingtip-first hit at 10 m/s sink cartwheels into C3", cartwheel["class"] == 3 and cartwheel.normal_class == 2)
	var brush := Severity.estimate(STIK_KG, 0.5, 15.0, rad_to_deg(atan2(0.5, 15.0)), "grass", "wing", STIK_KG * 0.07, 1.0, 0.5)
	_check("a wingtip brush stays C0 with its slapdown", brush["class"] == 0)
	var at_cg := Severity.estimate(STIK_KG, 5.0, 0.0, 90.0, "grass", "fuselage", STIK_KG, 1.0, 5.0)
	_check("a contact at the CG leaves no slapdown", at_cg.slapdown_energy_j == 0.0)
	var spinning := Severity.estimate(STIK_KG, 6.0, 0.0, 90.0, "grass", "wing", STIK_KG * 0.5, 1.0, 1.0)
	_check("a point faster than the CG (rotation) leaves no slapdown", spinning.slapdown_energy_j == 0.0)
	_check("severity follows the worse of contact and slapdown", with_slap.severity > nose_only.severity)
	_check("NaN CG normal velocity is rejected", not Severity.estimate(1.0, 1.0, 0.0, 90.0, "grass", "wing", -1.0, 1.0, NAN).valid)
	_check("separating CG disables the slapdown", Severity.estimate(STIK_KG, 5.0, 0.0, 90.0, "grass", "wing", STIK_KG * 0.1, 1.0, -2.0).slapdown_energy_j == 0.0)


func _size_invariance() -> void:
	var stik := _grade(STIK_KG, 1.0, 15.0, 0.0, "grass", "engine")
	var p51 := _grade(P51_KG, 1.0, 15.0, 0.0, "grass", "engine")
	_check("same nose-in speed gives the same specific energy for Stik and P-51", absf(stik.specific_energy_j_per_kg - p51.specific_energy_j_per_kg) < 1e-9)
	_check("same nose-in speed gives the same class for Stik and P-51", stik["class"] == p51["class"])
	_check("absolute struck-point energy still scales with mass", p51.estimated_energy_j > stik.estimated_energy_j * 7.0)
	var tip := _grade(STIK_KG, 0.07, 10.0, 0.0, "grass", "wing")
	var nose := _grade(STIK_KG, 1.0, 10.0, 0.0, "grass", "engine")
	_check("a wingtip at the same normal speed grades lower than a nose-in", tip.specific_energy_j_per_kg < nose.specific_energy_j_per_kg and tip["class"] < nose["class"])


func _channels_and_inputs() -> void:
	var slide := _grade(STIK_KG, 1.0, 0.4, 60.0, "concrete", "fuselage")
	_check("sliding alone never grades above C1", slide.valid and slide["class"] <= Severity.ABRASION_MAX_CLASS and slide.normal_class == 0)
	var no_normal := _grade(STIK_KG, 1.0, 0.0, 30.0, "concrete", "fuselage")
	_check("no normal impulse means no friction work", no_normal.valid and no_normal.friction_work_j == 0.0 and no_normal["class"] == 0)
	var capped := _grade(STIK_KG, 1.0, 50.0, 0.5, "concrete", "fuselage")
	_check("friction work is bounded by the point's tangential energy", capped.friction_work_j <= 0.5 * STIK_KG * 0.25 + 1e-12)
	var base := Severity.estimate(STIK_KG, 8.0, 0.0, 90.0, "grass", "wing", STIK_KG * 0.5, 1.0)
	var strong := Severity.estimate(STIK_KG, 8.0, 0.0, 90.0, "grass", "wing", STIK_KG * 0.5, 2.0)
	_check("durability 2 halves the specific energy", absf(strong.specific_energy_j_per_kg * 2.0 - base.specific_energy_j_per_kg) < 1e-12)
	_check("durability does not change the struck-point joules", strong.estimated_energy_j == base.estimated_energy_j)
	_check("supplied effective mass is reported with its basis", base.effective_mass_kg == STIK_KG * 0.5 and base.mass_basis.begins_with("rigid-body effective mass"))
	var whole := Severity.estimate(STIK_KG, 8.0, 0.0, 90.0, "grass", "wing")
	_check("missing effective mass falls back to whole mass and says so", whole.effective_mass_kg == STIK_KG and whole.mass_basis.begins_with("whole aircraft mass"))
	_check("effective mass above the aircraft mass is rejected", not Severity.estimate(1.0, 1.0, 0.0, 90.0, "grass", "wing", 1.5).valid)
	_check("NaN effective mass is rejected", not Severity.estimate(1.0, 1.0, 0.0, 90.0, "grass", "wing", NAN).valid)
	_check("zero durability is rejected", not Severity.estimate(1.0, 1.0, 0.0, 90.0, "grass", "wing", -1.0, 0.0).valid)
	_check("infinite durability is rejected", not Severity.estimate(1.0, 1.0, 0.0, 90.0, "grass", "wing", -1.0, INF).valid)
	for cut_index in range(Severity.CLASS_CUTS_J_PER_KG.size()):
		var cut: float = Severity.CLASS_CUTS_J_PER_KG[cut_index]
		var at := Severity.estimate(1.0, sqrt(2.0 * cut * 0.999), 0.0, 90.0, "concrete", "fuselage")
		var above := Severity.estimate(1.0, sqrt(2.0 * cut * 1.001), 0.0, 90.0, "concrete", "fuselage")
		_check("cut %.1f J/kg separates C%d and C%d" % [cut, cut_index, cut_index + 1], at["class"] == cut_index and above["class"] == cut_index + 1)


func _effective_mass_helper() -> void:
	var level := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	var up := PackedFloat64Array([0.0, 0.0, -1.0])
	var inertia := PackedFloat64Array([0.4, 0.6, 0.9, 0.0, 0.0, 0.0])
	_check("point at the CG engages the whole mass", absf(EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.0, 0.0]), up, 3.0, inertia) - 3.0) < 1e-12)
	var tip := EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.8, 0.0]), up, 3.0, inertia)
	_check("level wingtip matches 1/(1/m + y^2/Ixx)", absf(tip - 1.0 / (1.0 / 3.0 + 0.64 / 0.4)) < 1e-12)
	var nose_down := PackedFloat64Array([cos(-PI / 4.0), 0.0, sin(-PI / 4.0), 0.0]) # pitch -90 degrees
	var nose := EffectiveMass.at_point(nose_down, PackedFloat64Array([0.45, 0.0, 0.0]), up, 3.0, inertia)
	_check("vertical nose-in on the spinner axis engages the whole mass", absf(nose - 3.0) < 1e-9)
	_check("normal length does not matter", absf(EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.8, 0.0]), PackedFloat64Array([0.0, 0.0, -7.0]), 3.0, inertia) - tip) < 1e-12)
	_check("singular inertia is rejected", EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.8, 0.0]), up, 3.0, PackedFloat64Array([0.0, 0.6, 0.9, 0.0, 0.0, 0.0])) == -1.0)
	_check("zero normal is rejected", EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.8, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]), 3.0, inertia) == -1.0)
	_check("zero mass is rejected", EffectiveMass.at_point(level, PackedFloat64Array([0.0, 0.8, 0.0]), up, 0.0, inertia) == -1.0)


func _scenery_parity() -> void:
	# Same contact through the LU-05 swept path and through the shared helper must agree.
	var built: Dictionary = CollisionWorld.build({id = "cr-08b", pilot = {north = 0.0, east = 0.0, down = 0.0}, objects = []},
		{groups = []}, {fixtures = [{id = "parity-lamp", type = "flood", north = 5.0, east = 0.0, height = 8.0}]})
	_check("parity world builds", built.ok)
	if not built.ok:
		return
	var mass := 2.0
	var inertia := PackedFloat64Array([1.0, 1.2, 1.4, 0.0, 0.0, 0.0])
	var hull := PackedFloat64Array([0.2, 0.6, 0.0])
	var start := RB.make_state(PackedFloat64Array([0.0, -0.6, -4.0]), PackedFloat64Array([20.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var finish := RB.make_state(PackedFloat64Array([10.0, -0.6, -4.0]), PackedFloat64Array([20.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), PackedFloat64Array([0.0, 0.0, 0.0]))
	var hit: Collision.Event = Collision.first_hit(start, finish, hull, built.world, 1, mass, inertia)
	_check("parity contact found", hit != null)
	if hit == null:
		return
	var s := hit.contact_state()
	var helper := EffectiveMass.at_point(s.slice(RB.ATT, RB.ATT + 4), hit.body_point, hit.normal_ned, mass, inertia)
	_check("offset contact engages less than the whole mass", hit.effective_mass_kg < mass)
	_check("shared helper equals the scenery effective mass", absf(helper - hit.effective_mass_kg) < 1e-12)
