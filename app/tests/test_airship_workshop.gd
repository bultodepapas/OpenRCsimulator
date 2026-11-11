# BL-19a/b: the RC blimp as a Workshop family. Similarity compiler (exact s-power laws, refusals), derived
# descriptor and empty dependency manifest, frozen trial identity, library save/update/load round trip, and a
# session that flies the frozen in-memory variant. Fixed-wing Workshop paths are covered by their own suites.
extends SceneTree

const Compiler := preload("res://workshop/compiler.gd")
const AirshipCompiler := preload("res://workshop/airship_compiler.gd")
const Descriptor := preload("res://workshop/descriptor.gd")
const Dependencies := preload("res://workshop/dependencies.gd")
const Trial := preload("res://workshop/trial.gd")
const Store := preload("res://workshop/store.gd")
const Catalog := preload("res://vehicles/airship/airship_catalog.gd")
const Session := preload("res://sim/airship/session.gd")

var _count := 0
var _failures := 0
var _root := ""


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


static func _near(a: float, b: float, rel := 1e-9) -> bool:
	return absf(a - b) <= rel * maxf(absf(b), 1e-12)


func _initialize() -> void:
	var bytes := FileAccess.get_file_as_bytes(Catalog.DATA_PATH)
	var base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	_check("stock entry names the generated data", Catalog.stock_entry().data == Catalog.DATA_PATH and base.id == Catalog.STOCK_ID)
	_compiler(base)
	_descriptor(bytes)
	var frozen := _trial(bytes)
	_store(bytes)
	_flies(frozen)
	_finish()


func _compiler(base: Dictionary) -> void:
	var caps: Dictionary = Compiler.capabilities(base)
	_check("shared compiler reports airship capabilities", caps.get("vehicle") == "airship" and caps.scale and caps.weight and caps.power
		and caps.controls and not caps.control_rudder and not caps.tank_capacity, str(caps))
	var stock: Dictionary = Compiler.compile(base, {})
	_check("stock recipe compiles through the shared entry point", stock.ok, "; ".join(stock.errors))
	if not stock.ok:
		return
	var s0: Dictionary = stock.summary
	var big: Dictionary = Compiler.compile(base, {scale = 2.0})
	var small: Dictionary = Compiler.compile(base, {scale = 0.4})
	_check("size scales length by s and volume, mass, ballast and weigh-off by s^3", big.ok and small.ok
		and _near(big.summary.envelope_length_m, 2.0 * s0.envelope_length_m) and _near(big.summary.envelope_volume_m3, 8.0 * s0.envelope_volume_m3, 1e-6)
		and _near(big.summary.mass_kg, 8.0 * s0.mass_kg, 1e-6) and _near(big.summary.ballast_kg, 8.0 * s0.ballast_kg, 1e-6)
		and _near(small.summary.weigh_off_kg, 0.064 * s0.weigh_off_kg, 1e-6),
		"L %.2f m, mass %.3f kg" % [big.summary.envelope_length_m, big.summary.mass_kg] if big.ok else "")
	_check("size preserves the static trim (CG under CB)", big.ok and absf(float(big.summary.static_trim_deg) - float(s0.static_trim_deg)) < 1e-6
		and absf(float(small.summary.static_trim_deg) - float(s0.static_trim_deg)) < 1e-6,
		"%s / %s / %s deg" % [s0.static_trim_deg, big.summary.static_trim_deg, small.summary.static_trim_deg] if big.ok else "")
	var data: Dictionary = big.data.data
	_check("Froude laws: thrust s^3, power s^3.5, servo time sqrt(s), stiffness s^2", big.ok
		and _near(big.summary.static_thrust_n, 8.0 * s0.static_thrust_n, 1e-6) and _near(big.summary.static_power_w, pow(2.0, 3.5) * s0.static_power_w, 1e-6)
		and _near(float(data.fins[0].response_time), sqrt(2.0) * float(stock.data.data.fins[0].response_time), 1e-9)
		and _near(float(data.contacts.gear[0].stiffness), 4.0 * float(stock.data.data.contacts.gear[0].stiffness), 1e-9))
	var power: Dictionary = Compiler.compile(base, {power_multiplier = 2.0})
	_check("power doubles shaft power and raises thrust by 2^(2/3)", power.ok and _near(power.summary.static_power_w, 2.0 * s0.static_power_w, 1e-9)
		and _near(power.summary.static_thrust_n, pow(2.0, 2.0 / 3.0) * s0.static_thrust_n, 1e-9))
	var travel: Dictionary = Compiler.compile(base, {control_multiplier = 1.5})
	_check("control travel scales the fin throw", travel.ok and _near(travel.summary.fin_travel_deg, 1.5 * s0.fin_travel_deg))
	_check("summary reports the reachable weigh-off range", float(s0.get("weigh_off_min_kg", 1.0)) < float(s0.weigh_off_kg)
		and float(s0.get("weigh_off_max_kg", -1.0)) > float(s0.weigh_off_kg), "%s..%s kg" % [s0.get("weigh_off_min_kg"), s0.get("weigh_off_max_kg")])
	var heavier: Dictionary = Compiler.compile(base, {weight_multiplier = 1.2})
	_check("heavier equipment keeps the weigh-off with less ballast and reports its trim", heavier.ok
		and _near(heavier.summary.weigh_off_kg, s0.weigh_off_kg, 1e-6) and float(heavier.summary.ballast_kg) < float(s0.ballast_kg)
		and absf(float(heavier.summary.static_trim_deg)) > 0.1, "trim %.2f deg" % float(heavier.summary.static_trim_deg) if heavier.ok else str(heavier.errors))
	for refused: Dictionary in [{scale = 2.5}, {weight_multiplier = 1.4}, {control_multiplier_rudder = 1.2}, {tank_capacity_multiplier = 1.5},
			{scale = 1.5, mass_edits = [{id = "battery", mass_kg = 0.25, source = "scale"}]}]:
		var result: Dictionary = Compiler.compile(base, refused)
		_check("refuses %s" % str(refused.keys()), not result.ok and not result.errors.is_empty(), "; ".join(result.errors))
	var measured: Dictionary = Compiler.compile(base, {mass_edits = [{id = "battery", mass_kg = 0.25, source = "kitchen scale"}]})
	var battery_mass := 0.0
	for item: Dictionary in measured.get("raw", {}).get("masses", []):
		if item.id == "battery":
			battery_mass = float(item.mass.value)
	_check("a measured component mass replaces its inventory entry", measured.ok and battery_mass == 0.25
		and Compiler.version_for(base, {mass_edits = [{id = "battery", mass_kg = 0.25, source = "x"}]}) == AirshipCompiler.MEASURED_MASS_COMPILER_VERSION)
	var unknown := base.duplicate(true)
	unknown.envelope.volume.unit = "furlong^3"
	_check("an unknown unit is refused instead of guessed", not AirshipCompiler.compile(unknown, {scale = 1.2}).ok)


func _descriptor(bytes: PackedByteArray) -> void:
	var loaded: Dictionary = Descriptor.load_for(Catalog.STOCK_ID, bytes)
	_check("derived airship descriptor", loaded.ok and loaded.descriptor.format == "openrc-airship-workshop v1"
		and loaded.descriptor.presentation.visual_family == Catalog.VISUAL_FAMILY, str(loaded.get("errors", "")))
	if not loaded.ok:
		return
	_check("descriptor validates against its exact base", Descriptor.validate(loaded.descriptor, Catalog.STOCK_ID, bytes).ok)
	var changed := bytes.duplicate()
	changed.append(32)
	_check("descriptor refuses a different base snapshot", not Descriptor.validate(loaded.descriptor, Catalog.STOCK_ID, changed).ok)
	_check("presentation verification resolves the blimp model", Descriptor.verify_presentation(loaded.descriptor).ok)
	var stik := FileAccess.get_file_as_bytes("res://data/aircraft/jensen_ugly_stik_60.json")
	var forged: Dictionary = loaded.descriptor.duplicate(true)
	forged.base_id = "jensen-das-ugly-stik-60"
	_check("an airship descriptor is refused for a fixed-wing base", not Descriptor.validate(forged, "jensen-das-ugly-stik-60", stik).ok)
	var base: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var deps: Dictionary = Dependencies.capture(base)
	_check("empty dependency manifest round-trips", deps.ok and Dependencies.verify(base, deps.manifest).ok
		and not Dependencies.verify(base, {format = deps.manifest.format, files = {x = "y"}}).ok)


func _trial(bytes: PackedByteArray) -> Dictionary:
	var frozen: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes, recipe = {scale = 0.6, power_multiplier = 1.2}})
	_check("trial freezes an airship candidate", frozen.get("ok", false) and frozen.get("vehicle") == "airship"
		and frozen.identity.format == "openrc-airship-trial v1" and frozen.identity.compiler == AirshipCompiler.COMPILER_VERSION,
		str(frozen.get("errors", "")))
	if not frozen.get("ok", false):
		return {}
	var again: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes, recipe = {scale = 0.6, power_multiplier = 1.2}})
	_check("frozen trial identity is reproducible", again.identity.trial_id == frozen.identity.trial_id and again.raw_bytes == frozen.raw_bytes)
	var other: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes, recipe = {scale = 0.7}})
	_check("a different recipe has a different identity", other.ok and other.identity.trial_id != frozen.identity.trial_id)
	var ignored: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes,
		recipe = {scale = 0.6, power_multiplier = 1.2, mass_policy = "geometric", size_model = "virtual_similarity_v1"}})
	_check("fixed-wing size options the blimp ignores leave its identity unchanged", ignored.ok and ignored.identity.trial_id == frozen.identity.trial_id)
	var tiny: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes, recipe = {scale = 0.4}})
	var parsed: Variant = JSON.parse_string(tiny.raw_bytes.get_string_from_utf8())
	_check("frozen bytes are a JSON fixed point at 40 %", tiny.ok and JSON.stringify(parsed, "", true, true).to_utf8_buffer() == tiny.raw_bytes)
	return frozen


func _store(bytes: PackedByteArray) -> void:
	_root = "user://test_airship_workshop_%d" % Time.get_ticks_usec()
	var saved: Dictionary = Store.save_variant("Indoor blimp", Catalog.STOCK_ID, bytes, _recipe(0.5), "", _root)
	_check("library saves an airship build", saved.get("ok", false), "; ".join(saved.get("errors", PackedStringArray())))
	if not saved.get("ok", false):
		return
	var id: String = saved.variant.id
	var loaded: Dictionary = Store.load_variant(id, _root)
	_check("saved build reloads with its pins", loaded.ok and loaded.variant.compiler_version == AirshipCompiler.COMPILER_VERSION
		and loaded.variant.workshop_descriptor.format == "openrc-airship-workshop v1" and float(loaded.variant.recipe.scale) == 0.5)
	var updated: Dictionary = Store.save_variant("Indoor blimp", Catalog.STOCK_ID, bytes, _recipe(0.55), id, _root,
		loaded.variant.workshop_descriptor, loaded.variant.dependencies, 1)
	_check("an update creates revision 2", updated.get("ok", false) and Store.load_variant(id, _root).variant.revision == 2,
		"; ".join(updated.get("errors", PackedStringArray())))
	var trial: Dictionary = Trial.freeze({base_id = Catalog.STOCK_ID, base_bytes = bytes, recipe = Store.load_variant(id, _root).variant.recipe,
		workshop_descriptor = loaded.variant.workshop_descriptor, dependencies = loaded.variant.dependencies,
		compiler_version = loaded.variant.compiler_version, variant_id = id, variant_revision = 2})
	_check("a saved build test-flies from its pins", trial.get("ok", false), str(trial.get("errors", "")))
	Store.delete_variant(id, _root)
	_remove_tree(ProjectSettings.globalize_path(_root))


func _flies(frozen: Dictionary) -> void:
	if frozen.is_empty():
		return
	var s: Node = Session.new()
	root.add_child(s)
	_check("session prepares the frozen variant", s.prepare({}, {data = frozen.data.data_raw if frozen.data.has("data_raw") else _raw(frozen)}), str(s.load_error))
	_check("the flown data is exactly the frozen variant (identity matches the trial pin)",
		str(s.identity().data_sha256) == str(frozen.identity.resolved_sha256), "%s vs %s" % [s.identity().data_sha256, frozen.identity.resolved_sha256])
	_check("session flies the scaled blimp", is_equal_approx(float(s.data.envelope.length), 0.6 * 5.0) and s.resume(PackedFloat64Array([0, 0, 0, 0])))
	for i in 480:
		s.tick_once(PackedFloat64Array([0.0, 0.0, 0.0, 0.7]))
	var t: Dictionary = s.telemetry()
	_check("scaled blimp cruises without a fault", s.fault_reason.is_empty() and s.crash.is_empty() and float(t.ground_speed_mps) > 0.5,
		"%.2f m/s" % float(t.ground_speed_mps))
	s.free()


## A complete editor-shaped recipe (String keys, every default present), as the library stores them.
static func _recipe(scale: float) -> Dictionary:
	var recipe := {}
	var defaults: Dictionary = load("res://workshop/parameters.gd").defaults()
	for key: Variant in defaults:
		recipe[str(key)] = defaults[key]
	recipe["scale"] = scale
	recipe["control_multiplier"] = 1.2
	return recipe


static func _raw(frozen: Dictionary) -> Dictionary:
	return JSON.parse_string(frozen.raw_bytes.get_string_from_utf8())


func _remove_tree(path: String) -> void:
	if not path.begins_with(ProjectSettings.globalize_path("user://test_airship_workshop_")) or not DirAccess.dir_exists_absolute(path):
		return
	for child in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(child))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	print("%d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)
