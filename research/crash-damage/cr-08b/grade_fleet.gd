## CR-08b evidence: grade standard impacts for every flyable aircraft with the previous (CR-08a, whole mass,
## joule bins) and current (CR-08b, effective mass, J/kg bins) estimators. The first-contact hull point is the
## lowest point in the scenario attitude. Rates are zero, so point velocity equals CG velocity (also the slapdown input).
## Run from the repository root:
##   .tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script ../research/crash-damage/cr-08b/grade_fleet.gd
extends SceneTree

const Severity = preload("res://render/crash/severity.gd")
const EffectiveMass = preload("res://physics/effective_mass.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Catalog = preload("res://app_state/aircraft_catalog.gd")
const M = preload("res://physics/math3d.gd")

# CR-08a constants, copied verbatim for the comparison only.
const OLD_CUTS_J := [1.0, 8.0, 100.0, 2000.0]
const OLD_TRANSFER := {"grass": 0.78, "runway": 0.95}
const OLD_TANGENTIAL := {"grass": 0.15, "runway": 0.28}

# [label, pitch deg, roll deg, forward m/s, sink m/s, surface]
const SCENARIOS := [
	["flat hard landing, sink 3 m/s, 15 m/s", 0.0, 0.0, 15.0, 3.0, "grass"],
	["banked 45 deg touch, sink 1 m/s, 15 m/s", 0.0, 45.0, 15.0, 1.0, "grass"],
	["belly slide, sink 0.5 m/s, 20 m/s", 0.0, 0.0, 20.0, 0.5, "runway"],
	["45 deg dive, 20 m/s", -45.0, 0.0, 20.0, 0.0, "grass"],
	["vertical nose-in, 20 m/s", -90.0, 0.0, 20.0, 0.0, "grass"],
]


func _initialize() -> void:
	print("| Aircraft | Scenario | Struck point (body, m) | m_eff / m | Previous | Current (eps, slapdown, abrasion) |")
	print("| --- | --- | --- | ---: | --- | --- |")
	for id: String in Catalog.flyable_ids():
		var loaded: Dictionary = AircraftData.load_file(Catalog.entry(id).data)
		if not loaded.ok:
			print("load failed: %s %s" % [id, loaded.errors])
			continue
		var model: Dictionary = loaded.model
		for scenario: Array in SCENARIOS:
			print(_row(id, model, scenario))
	quit(0)


func _row(id: String, model: Dictionary, scenario: Array) -> String:
	var mass: float = model.mass_kg
	var pitch := deg_to_rad(float(scenario[1]))
	var roll := deg_to_rad(float(scenario[2]))
	var q := _euler_q(roll, pitch, 0.0)
	var hull: PackedFloat64Array = model.crash_hull
	var best := -1
	var best_down := -INF
	for i in range(0, hull.size(), 3):
		var down: float = M.q_rotate(q, hull.slice(i, i + 3))[2]
		if down > best_down:
			best_down = down
			best = i
	var point := hull.slice(best, best + 3)
	# Flight path: forward speed along the pitched path for dives, plus the stated sink.
	var speed := float(scenario[3])
	var v_n := speed * sin(-pitch) + float(scenario[4])
	var v_t := speed * cos(-pitch)
	var m_eff := EffectiveMass.at_point(q, point, PackedFloat64Array([0.0, 0.0, -1.0]), mass, model.inertia)
	var surface: String = scenario[5]
	var old_j: float = OLD_TRANSFER[surface] * (0.5 * mass * v_n * v_n + 0.5 * mass * v_t * v_t * OLD_TANGENTIAL[surface])
	var old_class := 4
	for c in range(4):
		if old_j <= OLD_CUTS_J[c]:
			old_class = c
			break
	var now: Dictionary = Severity.estimate(mass, v_n, v_t, rad_to_deg(atan2(v_n, v_t)), surface, "unknown", m_eff, 1.0, v_n)
	return "| %s | %s | (%.2f, %.2f, %.2f) | %.2f | C%d (%.0f J) | C%d (%.2f, %.2f, %.2f J/kg) |" % [id, scenario[0],
		point[0], point[1], point[2], m_eff / mass, old_class, old_j, now["class"],
		now.specific_energy_j_per_kg, now.slapdown_j_per_kg, now.abrasion_j_per_kg]


static func _euler_q(roll: float, pitch: float, yaw: float) -> PackedFloat64Array:
	var cr := cos(roll * 0.5)
	var sr := sin(roll * 0.5)
	var cp := cos(pitch * 0.5)
	var sp := sin(pitch * 0.5)
	var cy := cos(yaw * 0.5)
	var sy := sin(yaw * 0.5)
	return PackedFloat64Array([cr * cp * cy + sr * sp * sy, sr * cp * cy - cr * sp * sy,
		cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy])
