# FUEL-03: the optional fuel_system block, balance.fuel_state and balance.cg_range of openrc-aircraft v2.
# The current fleet loads unchanged; a tank bound to inventory ids derives its registry masses; an empty-tank
# balance is checked against the dry CG; every rule has a refusal.
# Run: godot --headless --path app --script res://tests/test_fuel_system_contract.gd
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Fuels := preload("res://physics/fuel_properties.gd")

## The prescribed-fuel base Stik declares no tanks; its point-mass liquid gets a 0.225 l box in _raw().
const STIK := "res://data/aircraft/jensen_ugly_stik_60.json"
const GLOW_WITH_TANKS := ["stik_glow_55ax_2t.json", "stik_glow_55ax_2t_apc_13x6.json", "stik_glow_61fx_2t.json",
	"stik_glow_fs64v_4t.json", "stik_glow_fs64v_4t_apc_13x6.json"]
const TIMBER := "res://data/aircraft/turbo_lumber_evolution.json"

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	_fleet_unchanged()
	_accepted()
	_empty_tank_balance()
	_refusals()
	print("FUEL-03 fuel system contract: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)


func _raw(path: String) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	if path == STIK:
		for item: Dictionary in raw.inventory:
			if item.get("id") == "item_fuel_main":
				item.size.value = [0.09, 0.05, 0.05]  # size changes inertia only, never the CG check
	return raw


func _q(value: Variant, unit: String) -> Dictionary:
	return {"value": value, "unit": unit, "kind": "estimated", "source": "FUEL-03 test fixture"}


func _tank(overrides := {}) -> Dictionary:
	var tank := {"id": "main_tank", "fuel": "glow_10n_18castor", "liquid_inventory_id": "item_fuel_main",
		"shell_inventory_id": "item_fuel_tank", "capacity": _q(0.225, "l"), "unusable": _q(0.005, "l"),
		"pickup": "clunk", "feed": "suction_muffler"}
	tank.merge(overrides, true)
	return tank


func _with_tank(overrides := {}) -> Dictionary:
	var raw: Dictionary = _raw(STIK)
	raw["fuel_system"] = {"tanks": [_tank(overrides)]}
	return raw


func _load(raw: Dictionary) -> Dictionary:
	return AD.validate_and_derive(raw)


func _errors(result: Dictionary) -> String:
	return "; ".join(result.get("errors", PackedStringArray()))


func _fleet_unchanged() -> void:
	var dir := DirAccess.open("res://data/aircraft")
	var loaded := 0
	var with_block: Array = []
	for name: String in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var raw: Variant = _raw("res://data/aircraft/" + name)
		if not raw is Dictionary or raw.get("format") != AD.FORMAT or not raw.has("balance"):
			continue
		var result: Dictionary = _load(raw)
		if result.get("ok", false):
			loaded += 1
			if result.model.has("fuel_system"):
				with_block.append(name)
	with_block.sort()
	_check("current fixed-wing data loads; only the FUEL-05a glow Stiks declare tanks (%d files)" % loaded,
		loaded >= 10 and with_block == GLOW_WITH_TANKS, str(with_block))


func _accepted() -> void:
	var raw := _with_tank()
	raw.balance["fuel_state"] = "as_inventory"
	var x: float = raw.balance.plan_cg.value[0]
	raw.balance["cg_range"] = {"forward": _q(x - 0.01, "m"), "aft": _q(x + 0.01, "m")}
	var result: Dictionary = _load(raw)
	_check("a tank bound to inventory ids loads with a CG range", result.get("ok", false), _errors(result))
	if not result.get("ok", false):
		return
	var system: Dictionary = result.model.get("fuel_system", {})
	var registry: Dictionary = Fuels.load_file()
	var density: float = registry.blends.glow_10n_18castor.density_kg_m3
	var tank: Dictionary = system.tanks[0] if system.has("tanks") else {}
	_check("model.fuel_system carries the registry density and identity",
		system.get("format") == "openrc-fuel-system v1" and system.registry_sha256 == registry.identity.sha256
		and tank.get("density_kg_m3") == density and tank.get("family") == "glow")
	_check("capacity, unusable and start fill derive from litres x density",
		absf(tank.capacity_kg - 0.225e-3 * density) < 1e-12 and absf(tank.unusable_kg - 0.005e-3 * density) < 1e-12
		and absf(tank.start_fill - 0.12 / (0.225e-3 * density)) < 1e-12 and tank.liquid_mass_kg == 0.12,
		"capacity %.6f kg, start fill %.4f" % [tank.capacity_kg, tank.start_fill])
	var plain: Dictionary = _load(_raw(STIK))  # same fixture without fuel_system
	_check("the block changes no derived mass property", plain.ok and plain.model.mass_kg == result.model.mass_kg
		and plain.model.cg_le == result.model.cg_le and plain.model.inertia == result.model.inertia)


func _dry_cg(raw: Dictionary, liquid_id: String) -> Array:
	var mass := 0.0
	var first := [0.0, 0.0, 0.0]
	for item: Dictionary in raw.inventory:
		if item.get("id", "") == liquid_id:
			continue
		mass += float(item.mass.value)
		for k in 3:
			first[k] += float(item.mass.value) * float(item.position.value[k])
	return [first[0] / mass, first[1] / mass, first[2] / mass]


func _empty_tank_balance() -> void:
	var raw := _with_tank()
	raw.balance["fuel_state"] = "empty_tanks"
	var wet: Dictionary = _load(raw)
	_check("an empty-tank balance refuses the authored (wet) plan CG", not wet.get("ok", true)
		and _errors(wet).contains("CG with empty tanks disagrees"), _errors(wet))
	var dry := raw.duplicate(true)
	dry.balance.plan_cg.value = _dry_cg(raw, "item_fuel_main")
	var result: Dictionary = _load(dry)
	_check("an empty-tank balance accepts the dry CG; the body datum stays the authored inventory CG",
		result.get("ok", false) and result.model.fuel_system.fuel_state == "empty_tanks"
		and result.model.cg_le == _load(_raw(STIK)).model.cg_le, _errors(result))
	var shifted: Array = dry.balance.plan_cg.value.duplicate()
	var x: float = shifted[0]
	dry.balance["cg_range"] = {"forward": _q(x - 0.02, "m"), "aft": _q(x - 0.01, "m")}
	_check("the CG range applies at the declared fuel state", not _load(dry).get("ok", true))


func _refusals() -> void:
	var cases := {
		"an unknown blend": [_with_tank({"fuel": "nitro_99"}), "is not a fuel registry blend"],
		"a feed that does not match the fuel family": [_with_tank({"feed": "pumped_diaphragm"}), "glow fuel uses"],
		"a missing liquid item": [_with_tank({"liquid_inventory_id": "item_missing"}), "must name inventory items"],
		"the same item as liquid and shell": [_with_tank({"shell_inventory_id": "item_fuel_main"}), "one tank role only"],
		"a liquid of another family": [_with_tank({"fuel": "gasoline_premix_40_1", "feed": "pumped_diaphragm"}), "must declare energy_source 'gasoline'"],
		"liquid mass above capacity": [_with_tank({"capacity": _q(0.1, "l")}), "exceeds capacity"],
		"a liquid box smaller than the capacity": [_with_tank({"capacity": _q(0.3, "l")}), "cannot hold"],
		"unusable volume at capacity": [_with_tank({"unusable": _q(0.225, "l")}), "unusable < capacity"],
		"a capacity in millilitres": [_with_tank({"capacity": _q(225.0, "ml")}), "expected 'l'"],
		"an unknown pickup": [_with_tank({"pickup": "sponge"}), "pickup: must be one of"],
		"an unknown tank field": [_with_tank({"colour": "red"}), "colour: unknown field"],
	}
	var duplicate := _with_tank()
	duplicate.fuel_system.tanks.append(_tank())
	cases["two tanks with one id and the same items"] = [duplicate, "duplicate tank id"]
	var empty := _raw(STIK)
	empty.fuel_system = {"tanks": []}
	cases["an empty tank list"] = [empty, "at least 1 item"]
	var shell := _with_tank()
	for item: Dictionary in shell.inventory:
		if item.get("id") == "item_fuel_tank":
			item["energy_source"] = "lipo"
	cases["a shell that carries energy"] = [shell, "carries no energy"]
	var stray := _with_tank()
	var plan: Array = stray.balance.plan_cg.value
	stray.inventory.append({"id": "item_spare_fuel", "name": "spare fuel", "energy_source": "glow_fuel",
		"mass": _q(0.001, "kg"), "position": _q(plan.duplicate(), "m"), "size": _q([0.0, 0.0, 0.0], "m")})
	cases["a liquid fuel item outside every tank"] = [stray, "belongs to no declared tank"]
	var no_system := _raw(STIK)
	no_system.balance["fuel_state"] = "empty_tanks"
	cases["an empty-tank balance without tanks"] = [no_system, "needs a fuel_system"]
	var inverted := _raw(STIK)
	var x: float = inverted.balance.plan_cg.value[0]
	inverted.balance["cg_range"] = {"forward": _q(x + 0.01, "m"), "aft": _q(x - 0.01, "m")}
	cases["a CG range with forward behind aft"] = [inverted, "must lie ahead of aft"]
	var electric := _raw(TIMBER)
	electric.fuel_system = {"tanks": [_tank({"liquid_inventory_id": "battery_main", "shell_inventory_id": "esc_main"})]}
	cases["tanks on an electric aircraft"] = [electric, "combustion energy capability"]
	var state := _raw(STIK)
	state.balance["fuel_state"] = "half"
	cases["an unknown balance fuel state"] = [state, "fuel_state: must be one of"]
	for label: String in cases:
		var result: Dictionary = _load(cases[label][0])
		_check("refuses %s for that reason" % label, not result.get("ok", true) and _errors(result).contains(cases[label][1]), _errors(result))
