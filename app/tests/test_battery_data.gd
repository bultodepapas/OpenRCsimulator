# BAT-04/09: generated battery data and the pack_ecm aircraft contract. Every shipped pack loads with its pinned
# template; invalid aircraft battery data cannot fly (hash, mount mass, LVC presence, schema agreement).
extends SceneTree

const BatteryData: Script = preload("res://physics/battery/battery_data.gd")
const AircraftData: Script = preload("res://physics/aircraft_data.gd")
const Contract: Script = preload("res://physics/aircraft_contract.gd")
const Modules: Script = preload("res://physics/aircraft_modules.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")

const TIMBER := "turbo-lumber-evolution"

var checks: int = 0
var failures: int = 0


func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)


func _initialize() -> void:
	_shipped_packs()
	_pack_refusals()
	_aircraft_contract()
	print("BAT-04/09 battery data: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _shipped_packs() -> void:
	var dir := DirAccess.open(BatteryData.PACK_DIR)
	check("pack directory exists", dir != null)
	if dir == null:
		return
	var count: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		count += 1
		var id: String = file_name.trim_suffix(".json")
		var errors := PackedStringArray()
		var pack: Dictionary = BatteryData.load_pack(errors, id, id, BatteryData.file_sha256(BatteryData.PACK_DIR + file_name))
		check("shipped pack %s loads: %s" % [id, ", ".join(errors)], errors.is_empty() and not pack.is_empty())
		if pack.is_empty():
			continue
		check("%s OCV is monotone and inside its cell limits" % id, _ocv_inside_limits(pack))
		check("%s resistances positive after normalization" % id, pack.r0.size() > 0 and pack.r0[0] > 0.0)
		check("%s has a positive thermal capacity" % id, pack.thermal_capacity_j_per_k > 0.0)
	check("at least one shipped pack", count > 0)


func _ocv_inside_limits(pack: Dictionary) -> bool:
	var nz: int = pack.soc_knots.size()
	var ocv: PackedFloat64Array = pack.ocv
	for row: int in ocv.size() / nz:
		for i: int in nz:
			var value: float = ocv[row * nz + i]
			if value <= 0.0 or value > pack.cell_v_max + 0.05 or (i > 0 and value < ocv[row * nz + i - 1]):
				return false
	return true


func _pack_refusals() -> void:
	var errors := PackedStringArray()
	BatteryData.load_pack(errors, "p", "../escape", "0".repeat(64))
	check("path traversal refused", not errors.is_empty())
	errors = PackedStringArray()
	BatteryData.load_pack(errors, "p", "lipo-4s1p-3200-30c-class", "0".repeat(64))
	check("hash mismatch refused", not errors.is_empty() and "changed" in ", ".join(errors))
	errors = PackedStringArray()
	BatteryData.load_pack(errors, "p", "does-not-exist", "0".repeat(64))
	check("missing pack refused", not errors.is_empty())
	errors = PackedStringArray()
	BatteryData.load_pack(errors, "p", "lipo-4s1p-3200-30c-class", "NOT-A-HASH")
	check("malformed hash refused", not errors.is_empty())


func _raw_pack_aircraft() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(Catalog.data_for(TIMBER, "pack"))
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _aircraft_contract() -> void:
	var raw: Dictionary = _raw_pack_aircraft()
	check("pack aircraft file parses", not raw.is_empty())
	if raw.is_empty():
		return
	var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(TIMBER, "pack"))
	check("pack aircraft loads: " + str(loaded.get("errors", [])), loaded.get("ok", false))
	var issues: PackedStringArray = Contract.validate(raw)
	check("pack aircraft passes the structural contract: " + ", ".join(issues), issues.is_empty())
	var modules: Dictionary = Modules.classify(raw)
	check("module registry selects the pack law", str(modules).contains("energy.battery.pack_ecm.v1"))
	for mutation: Array in [
			["mount mass differs", func(d: Dictionary) -> void: _set_mount_mass(d, 0.34)],
			["mount item missing", func(d: Dictionary) -> void: d.propulsion.battery.mount_inventory_id = "no_such_item"],
			["pack hash stale", func(d: Dictionary) -> void: d.propulsion.battery.pack.sha256 = "1".repeat(64)],
			["LVC missing", func(d: Dictionary) -> void: d.propulsion.esc.erase("low_voltage_cutoff")],
			["energy capability disagrees", func(d: Dictionary) -> void: d.capabilities.energy = "ocv_resistance"],
			["unknown battery field", func(d: Dictionary) -> void: d.propulsion.battery["extra"] = 1],
			["weak offset above initial SOC", func(d: Dictionary) -> void: d.propulsion.battery.weak_cell.soc_offset.value = 0.49; d.propulsion.battery.initial_soc.value = 0.3],
			["filter faster than allowed", func(d: Dictionary) -> void: d.propulsion.esc.low_voltage_cutoff.voltage_filter_s.value = 0.001],
			["fixed cells without a count", func(d: Dictionary) -> void: d.propulsion.esc.low_voltage_cutoff.cell_detection = "fixed"],
	]:
		var bad: Dictionary = raw.duplicate(true)
		(mutation[1] as Callable).call(bad)
		check("mutation refused: " + str(mutation[0]), not _load_raw(bad).get("ok", false))
	var ideal_text: String = FileAccess.get_file_as_string(Catalog.data_for(TIMBER, "ideal"))
	var ideal: Dictionary = JSON.parse_string(ideal_text)
	ideal.propulsion.esc["low_voltage_cutoff"] = raw.propulsion.esc.low_voltage_cutoff.duplicate(true)
	check("LVC refused on a fixed-voltage battery", not _load_raw(ideal).get("ok", false))


func _set_mount_mass(data: Dictionary, mass: float) -> void:
	for item: Dictionary in data.inventory:
		if item.get("id") == "battery_main":
			item.mass.value = mass


## The in-memory loader runs the same contract, module and physics validation as a file load.
func _load_raw(data: Dictionary) -> Dictionary:
	return AircraftData.validate_and_derive(data.duplicate(true))
