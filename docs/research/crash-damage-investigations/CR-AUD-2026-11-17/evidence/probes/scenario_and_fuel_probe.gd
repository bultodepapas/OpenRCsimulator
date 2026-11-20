## Audit of the production estimator and effect handoff, not flight or material validation.
extends SceneTree
const Severity = preload("res://render/crash/severity.gd")
const Effects = preload("res://render/crash/effects.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const Data = preload("res://physics/aircraft_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool, details := "") -> void:
	checks += 1
	if not passed: failures += 1
	print("PROBE ", label, " ", "PASS" if passed else "FAIL", " ", details)

func _run() -> void:
	print("ENGINE_IDENTITY ", JSON.stringify({"version": Engine.get_version_info(), "platform": OS.get_name(),
		"physics_3d_setting": ProjectSettings.get_setting("physics/3d/physics_engine", "unrecorded"),
		"tick_hz": Engine.physics_ticks_per_second}))
	var speed := 300.0 / 3.6
	var count := 0
	for entry: Dictionary in Catalog.flyable_entries():
		if Catalog.is_rotorcraft(str(entry.id)): continue
		var data := Data.load_file(str(entry.data))
		check(str(entry.id) + " data admitted", bool(data.get("ok", false)))
		if not data.get("ok", false): continue
		count += 1
		var mass: float = data.model.mass_kg
		var cases := [
			["wing brush", 0.5, 15.0, 0.07, "wing", 0, 0],
			["belly slide", 1.0, 25.0, 0.94, "fuselage", 0, 1],
			["300 kph frontal", speed, 0.0, 1.0, "fuselage", 4, 4],
			["300 kph grazing", 0.5, sqrt(speed * speed - 0.25), 0.07, "wing", 0, 1],
		]
		for row: Array in cases:
			var grade := Severity.estimate(mass, row[1], row[2], rad_to_deg(atan2(row[1], row[2])),
				"grass", row[4], mass * row[3], 1.0, row[1])
			var level: int = int(grade.get("class", -1))
			check(str(entry.id) + " " + str(row[0]), bool(grade.get("valid", false)) and level >= row[5] and level <= row[6],
				"mass=%.5f class=%d normal_specific=%.6f abrasion=%.6f" % [mass, level,
				grade.get("specific_energy_j_per_kg", -1.0), grade.get("abrasion_j_per_kg", -1.0)])
	check("all registered fixed-wing configurations covered", count == 11, str(count))
	var impact := {"class": 4, "severity": 1.0, "component_group": "fuselage", "tank_ruptured": true}
	var cold := Effects.energy_outcome({"kerosene": 1.28}, impact, false, false)
	var glow := Effects.energy_outcome({"glow_fuel": 0.15}, impact, true, false)
	var lipo := Effects.energy_outcome({"lipo": 0.6}, impact, true, false)
	check("C4 cold kerosene has no ignition", cold.fire_kind.is_empty() and not cold.flash)
	check("C4 glow produces stain without a fireball", glow.stain and glow.fire_kind.is_empty() and not glow.flash)
	check("C4 LiPo is delayed venting without ignition flash", lipo.vent_delay_s >= 5.0 and not lipo.flash)
	var fx := Effects.new()
	root.add_child(fx)
	fx.prepare()
	fx.start(Vector3.ZERO, Vector3(20.0, -5.0, 0.0), impact, 1.28, true, Vector3.ZERO)
	var live := Effects.energy_outcome({"kerosene": 0.035}, impact, true, true)
	check("live fuel outcome uses remaining mass", absf(float(live.fire_s) - 1.0) < 1.0e-9)
	fx.apply_energy(live)
	check("visible kerosene duration agrees with live fuel outcome", absf(fx._fire_duration - float(live.fire_s)) < 1.0e-6,
		"declared_kg=1.28 live_kg=0.035 report_duration_s=%.6f visible_duration_s=%.6f" % [live.fire_s, fx._fire_duration])
	fx.free()
	print("SCENARIO_FUEL_PROBE: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
