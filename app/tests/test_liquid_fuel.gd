## FUEL-08 finite-liquid loader, fixed-datum mass properties and flow-law checks.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const LiquidFuel := preload("res://physics/liquid_fuel.gd")
const Turbine := preload("res://physics/turbine.gd")

var checks := 0
var failures := 0


func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL FUEL-08 " + label + ": " + str(detail))


func close(a: float, b: float, tolerance := 1.0e-10) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance * maxf(1.0, maxf(absf(a), absf(b)))


func same_array(a: Variant, b: Variant, tolerance := 1.0e-10) -> bool:
	if not a is PackedFloat64Array or not b is PackedFloat64Array or a.size() != b.size():
		return false
	for i: int in a.size():
		if not close(float(a[i]), float(b[i]), tolerance):
			return false
	return true


func read_raw(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _initialize() -> void:
	var p51_path := "res://data/aircraft/p51d_mustang_120.json"
	var p51_raw := read_raw(p51_path)
	var p51_load: Dictionary = AD.load_file(p51_path)
	check("P-51 finite-liquid contract loads", p51_load.ok, p51_load.errors)
	if p51_load.ok:
		var p51: Dictionary = p51_load.model
		var gas: Dictionary = p51.propulsion.liquid_fuel
		check("P-51 law and stable tank binding", gas.law == "gasoline_bsfc_v1" and gas.tank_id == "main_tank")
		var gas_reference: Dictionary = LiquidFuel.properties(gas, {})
		check("P-51 authored mass is the fixed-datum reference", gas_reference.ok and close(gas_reference.mass_kg, p51.mass_kg) and same_array(gas_reference.inertia, p51.inertia), gas_reference)
		check("P-51 reference CG is the authored body datum", gas_reference.ok and same_array(gas_reference.cg_body_m, PackedFloat64Array([0.0, 0.0, 0.0])))
		var gas_store: Dictionary = gas_reference.get("store_amounts_by_id", {}).get("main_tank", {})
		check("P-51 reference fill is distinct from full capacity", gas_store.get("onboard_kg", NAN) == gas.reference_kg and gas.capacity_kg > gas.reference_kg)
		var gas_unusable: float = float(gas.unusable_kg)
		var gas_residue: Dictionary = LiquidFuel.properties(gas, {"main_tank": 0.0})
		check("P-51 zero usable fill preserves onboard residue", gas_residue.ok and close(gas_residue.store_amounts_by_id.main_tank.onboard_kg, gas_unusable) and gas_residue.store_amounts_by_id.main_tank.usable_kg == 0.0 and gas_residue.mass_kg > p51.mass_kg - gas.reference_kg)
		check("P-51 unknown store is refused", not LiquidFuel.properties(gas, {"missing_tank": 0.1}).get("ok", false))
		check("P-51 negative onboard amount is refused", not LiquidFuel.properties(gas, {"main_tank": -0.001}).get("ok", false))
		check("P-51 amount above capacity is refused", not LiquidFuel.properties(gas, {"main_tank": gas.capacity_kg + 0.001}).get("ok", false))
		var idle: float = float(gas.idle_flow_kg_s)
		check("gasoline stopped source consumes zero", LiquidFuel.flow_rate_kg_s(gas, {"running": false}) == 0.0)
		check("gasoline idle baseline covers negative shaft power", close(LiquidFuel.flow_rate_kg_s(gas, {"running": true, "shaft_power_w": -100.0}), idle))
		var powered_flow: float = LiquidFuel.flow_rate_kg_s(gas, {"running": true, "shaft_power_w": gas.idle_power_w + 3600.0})
		check("gasoline BSFC converts delivered shaft power to flow", close(powered_flow, idle + gas.bsfc_kg_kwh * 3600.0 / 3600000.0))
		check("gasoline missing operating power is not silently accepted", is_nan(LiquidFuel.flow_rate_kg_s(gas, {"running": true})))

	var broken_gas: Dictionary = p51_raw.duplicate(true)
	broken_gas.propulsion.fuel_consumption.tank_id = "unknown_tank"
	var broken_gas_load: Dictionary = AD.validate_and_derive(broken_gas)
	check("P-51 invalid tank binding is refused by the loader", not broken_gas_load.ok and not broken_gas_load.errors.is_empty())
	broken_gas = p51_raw.duplicate(true)
	broken_gas.propulsion.engine.erase("shaft")
	var shaftless_gas: Dictionary = AD.validate_and_derive(broken_gas)
	check("gasoline law requires the authored shaft model", not shaftless_gas.ok and not shaftless_gas.errors.is_empty())

	var turbine_path := "res://data/aircraft/sebart_avanti_s_a200.json"
	var turbine_raw := read_raw(turbine_path)
	var turbine_load: Dictionary = AD.load_file(turbine_path)
	check("Ventage continuous-turbine contract loads", turbine_load.ok, turbine_load.errors)
	if turbine_load.ok:
		var turbine_model: Dictionary = turbine_load.model
		var turbine: Dictionary = turbine_model.propulsion.liquid_fuel
		check("Ventage law binds the main tank", turbine.law == "turbine_map_v1" and turbine.tank_id == "main_tank")
		check("Ventage loader uses continuous RPM integration", Turbine.is_continuous(turbine_model.propulsion))
		var turbine_reference: Dictionary = LiquidFuel.properties(turbine, {})
		check("Ventage authored mass is the fixed-datum reference", turbine_reference.ok and close(turbine_reference.mass_kg, turbine_model.mass_kg) and same_array(turbine_reference.inertia, turbine_model.inertia), turbine_reference)
		var flow_table: PackedFloat64Array = turbine.fuel_flow_kg_s_by_rpm
		var turbine_flow: float = LiquidFuel.flow_rate_kg_s(turbine, {"running": true, "rpm": flow_table[0]})
		check("turbine consumption uses the existing RPM flow map", close(turbine_flow, flow_table[1]))
		check("turbine stopped source consumes zero", LiquidFuel.flow_rate_kg_s(turbine, {"running": false}) == 0.0)
		check("turbine missing RPM is not silently accepted", is_nan(LiquidFuel.flow_rate_kg_s(turbine, {"running": true})))
	var sampled_turbine: Dictionary = turbine_raw.duplicate(true)
	sampled_turbine.propulsion.engine.spool_integrator = "sampled"
	var sampled_load: Dictionary = AD.validate_and_derive(sampled_turbine)
	check("finite turbine map refuses non-continuous RPM integration", not sampled_load.ok and not sampled_load.errors.is_empty(), sampled_load.errors)

	var malformed := {"format": LiquidFuel.FORMAT, "law": "unknown"}
	check("unknown flow law returns invalid sample", is_nan(LiquidFuel.flow_rate_kg_s(malformed, {"running": true})))
	print("FUEL-08 liquid adapter: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
