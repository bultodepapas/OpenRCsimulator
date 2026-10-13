# TT-07: the generated Timber estimate loads as its own openrc-aircraft v2 record,
# preserves its inventory balance, and keeps the borrowed propeller evidence explicit.
# Run: godot --headless --path . --script res://tests/test_timber_data.gd
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const RB := preload("res://physics/rigid_body.gd")

const ID := "turbo-lumber-evolution"
const DATA := "res://data/aircraft/turbo_lumber_evolution.json"

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var entry: Dictionary = Catalog.entry(ID)
	_check("catalog offers the generated Timber data as experimental", not entry.is_empty()
		and entry.status == Catalog.EXPERIMENTAL and entry.data == DATA)
	var loaded: Dictionary = AircraftData.load_file(DATA)
	_check("TT-07 v2 file passes production validation", loaded.get("ok", false), "; ".join(loaded.get("errors", PackedStringArray())))
	if not loaded.get("ok", false):
		print("%d checks, %d failed" % [_checks, _failures + 1])
		quit(1)
		return

	var model: Dictionary = loaded.model
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	_check("loader keeps Timber identity and measured reference span", model.id == ID
		and absf(float(model.reference.b) - 1.555) < 1e-9, "%s, %.3f m" % [model.id, model.reference.b])
	_check("estimated inventory totals the declared 2.190 kg flight mass",
		absf(float(model.mass_kg) - 2.190) < 0.001, "%.6f kg" % model.mass_kg)

	var inventory_mass := 0.0
	var moment := PackedFloat64Array([0.0, 0.0, 0.0])
	for part: Dictionary in raw.inventory:
		var mass: float = float(part.mass.value)
		inventory_mass += mass
		for axis in 3:
			moment[axis] += mass * float(part.position.value[axis])
	var inventory_cg := PackedFloat64Array([moment[0] / inventory_mass, moment[1] / inventory_mass, moment[2] / inventory_mass])
	var derived_cg: PackedFloat64Array = model.cg_inventory_le
	var plan_cg: Array = raw.balance.plan_cg.value
	var cg_error := 0.0
	var plan_error := 0.0
	for axis in 3:
		cg_error = maxf(cg_error, absf(inventory_cg[axis] - derived_cg[axis]))
		plan_error = maxf(plan_error, absf(inventory_cg[axis] - float(plan_cg[axis])))
	_check("inventory COM is preserved by the loader", absf(inventory_mass - model.mass_kg) < 1e-9
		and cg_error < 1e-10, "mass %.9f kg, max CG error %.9f m" % [inventory_mass, cg_error])
	_check("inventory COM matches the declared balanced CG tolerance", plan_error <= float(raw.balance.cg_tolerance.value),
		"max error %.6f m" % plan_error)

	var inertia: PackedFloat64Array = model.inertia
	var determinant: float = inertia[0] * inertia[1] * inertia[2] + 2.0 * inertia[3] * inertia[4] * inertia[5] \
		- inertia[0] * inertia[5] * inertia[5] - inertia[1] * inertia[4] * inertia[4] - inertia[2] * inertia[3] * inertia[3]
	_check("estimated body inertia is finite and positive definite", inertia.size() == 6
		and RB.inertia_inverse(inertia).size() == 6 and determinant > 0.0,
		"diag %.6f, %.6f, %.6f kg·m²; determinant %.9f" % [inertia[0], inertia[1], inertia[2], determinant])

	var prop: Dictionary = raw.propulsion
	var propeller_source: String = str(prop.propeller.ct_table.source)
	_check("motor and fixed 4S bus retain the stated 800 Kv / 14.8 V inputs",
		float(prop.motor.kv_rpm_per_volt.value) == 800.0 and float(prop.battery.voltage_v.value) == 14.8)
	_check("borrowed two-blade propeller map names the three-blade mismatch",
		prop.propeller.ct_table.kind == "borrowed" and propeller_source.contains("two-blade")
		and propeller_source.contains("three-blade") and propeller_source.contains("no same-propeller"))
	_check("data labels the estimate as unvalidated", str(raw.description).contains("Not physical validation")
		and str(raw.description).contains("no battery depletion"))

	print("TT-07 Timber data: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
