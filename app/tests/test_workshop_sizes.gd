extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Parameters := preload("res://workshop/parameters.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const Trial := preload("res://workshop/trial.gd")
const Session := preload("res://sim/flight_session.gd")
const Workshop := preload("res://ui/workshop.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var _checks := 0
var _failures := 0
var _store_root := ""
var _ui: RefCounted


func _initialize() -> void:
	_store_root = "user://workshop_sizes_test_%d" % int(Time.get_ticks_usec())
	_ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find(node: Node, child_name: String) -> Node:
	return node.find_child(child_name, true, false)


func _run() -> void:
	TranslationServer.set_locale("en")
	var base_bytes := FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	var parsed: Variant = JSON.parse_string(base_bytes.get_string_from_utf8())
	_check("stock aircraft fixture parses", parsed is Dictionary)
	if not parsed is Dictionary:
		_finish()
		return
	var base: Dictionary = parsed
	var base_snapshot: Dictionary = base.duplicate(true)
	var baseline: Dictionary = Compiler.compile(base, {})
	_check("stock baseline compiles", bool(baseline.get("ok", false)), str(baseline.get("errors", [])))
	if not baseline.get("ok", false):
		_finish()
		return

	_test_compile_bounds(base, baseline)
	_test_rejections(base)
	_test_persistence_endpoints(base, base_bytes, baseline)
	await _test_workshop_ui()
	_check("size tests leave the source aircraft unchanged", base == base_snapshot)
	_finish()


func _test_compile_bounds(base: Dictionary, baseline: Dictionary) -> void:
	var base_span := float(baseline.summary.wing_span_m)
	var base_area := float(baseline.summary.wing_area_m2)
	var base_mass := float(baseline.data.model.mass_kg)
	var base_liquid_mass := _liquid_kg(baseline.data.model)
	var base_wheel_radius := float(baseline.data.model.landing_gear.contacts[0].wheel_radius)
	for scale_value: float in [Parameters.MIN_SCALE, Parameters.MAX_SCALE]:
		var recipe := {"scale": scale_value}
		var result: Dictionary = Compiler.compile(base, recipe)
		_check("%.0f%% default-policy recipe compiles" % (scale_value * 100.0),
			bool(result.get("ok", false)) and result.get("summary", {}).get("mass_policy", "") == "constant_wing_loading",
			str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		_check("%.0f%% reports wingspan scaled from the compiled stock span" % (scale_value * 100.0),
			is_equal_approx(float(result.summary.wing_span_m), base_span * scale_value),
			"actual=%s expected=%s" % [result.summary.wing_span_m, base_span * scale_value])
		_check("%.0f%% scales wing area by squared size" % (scale_value * 100.0),
			is_equal_approx(float(result.summary.wing_area_m2), base_area * pow(scale_value, 2.0)))
		var liquid_mass := _liquid_kg(result.data.model)
		var dry_mass := float(result.data.model.mass_kg) - liquid_mass
		_check("%.0f%% applies the documented dry s² and liquid s³ mass laws" % (scale_value * 100.0),
			is_equal_approx(dry_mass, (base_mass - base_liquid_mass) * pow(scale_value, 2.0))
				and is_equal_approx(liquid_mass, base_liquid_mass * pow(scale_value, 3.0)),
			"dry=%s liquid=%s" % [dry_mass, liquid_mass])
		_check("%.0f%% scales the derived wheel radius" % (scale_value * 100.0),
			is_equal_approx(float(result.data.model.landing_gear.contacts[0].wheel_radius),
				base_wheel_radius * scale_value))


func _liquid_kg(model: Dictionary) -> float:
	var total := 0.0
	for tank: Dictionary in model.get("fuel_system", {}).get("tanks", []):
		total += float(tank.liquid_mass_kg)
	return total


func _session_accepts(trial: Dictionary) -> bool:
	if not bool(trial.get("ok", false)) or not trial.get("data", {}).has("input_identity"):
		return false
	var session: Node = Session.new()
	session.physics_enabled = false
	session.setup("", str(trial.data.model.id), trial.data)
	var accepted: bool = bool(session.aircraft.get("ok", false)) \
		and bool(session.start.get("ok", false)) and session.is_flyable()
	session.free()
	return accepted


func _test_rejections(base: Dictionary) -> void:
	for invalid_scale: Variant in [
		Parameters.MIN_SCALE - 0.0001,
		Parameters.MAX_SCALE + 0.0001,
		NAN,
		true,
	]:
		var checked: Dictionary = Parameters.validate({"scale": invalid_scale})
		var compiled: Dictionary = Compiler.compile(base, {"scale": invalid_scale})
		_check("invalid scale %s is rejected by shared validation and compile" % str(invalid_scale),
			not bool(checked.get("ok", false)) and not bool(compiled.get("ok", false)),
			"parameters=%s compiler=%s" % [checked.get("errors", []), compiled.get("errors", [])])
	var geometric_recipe := {"scale": 2.25, "mass_policy": "geometric"}
	_check("legacy 225% geometric request is inside the parameter contract",
		bool(Parameters.validate(geometric_recipe).get("ok", false)))
	var geometric: Dictionary = Compiler.compile(base, geometric_recipe)
	_check("legacy 225% geometric request still fails full aircraft validation",
		not bool(geometric.get("ok", false))
			and (str(geometric.get("errors", [])).contains("inventory")
				or str(geometric.get("errors", [])).contains("mass_range")),
		str(geometric.get("errors", [])))


func _test_persistence_endpoints(base: Dictionary, base_bytes: PackedByteArray, baseline: Dictionary) -> void:
	for scale_value: float in [Parameters.MIN_SCALE, Parameters.MAX_SCALE]:
		var expected: Dictionary = Compiler.compile(base, {"scale": scale_value})
		if not expected.get("ok", false):
			continue
		var endpoint_recipe: Dictionary = Compiler.defaults()
		endpoint_recipe["scale"] = scale_value
		var saved: Dictionary = Store.save_variant("Scale endpoint %s%%" % String.num(scale_value * 100.0, 0),
			Catalog.DEFAULT_ID, base_bytes, endpoint_recipe, "", _store_root)
		_check("%.0f%% endpoint saves as a variant" % (scale_value * 100.0),
			bool(saved.get("ok", false)), str(saved.get("errors", [])))
		if not saved.get("ok", false):
			continue
		var original: Dictionary = saved.variant
		var loaded_result: Dictionary = Store.load_variant(str(original.id), _store_root)
		_check("%.0f%% endpoint reloads with exact recipe scale" % (scale_value * 100.0),
			bool(loaded_result.get("ok", false))
				and float(loaded_result.variant.recipe.scale) == scale_value,
			str(loaded_result.get("errors", [])))
		if not loaded_result.get("ok", false):
			continue
		var loaded: Dictionary = loaded_result.variant
		var loaded_base: Variant = JSON.parse_string((loaded.base_bytes as PackedByteArray).get_string_from_utf8())
		var loaded_compile: Dictionary = Compiler.compile(loaded_base, loaded.recipe)
		_check("%.0f%% loaded variant preserves the compiled physical projection" % (scale_value * 100.0),
			bool(loaded_compile.get("ok", false))
				and _physical_projection(loaded_compile.data.model) == _physical_projection(expected.data.model),
			str(loaded_compile.get("errors", [])))
		_check("%.0f%% loaded variant retains its scaled wheel radius" % (scale_value * 100.0),
			bool(loaded_compile.get("ok", false))
				and is_equal_approx(float(loaded_compile.data.model.landing_gear.contacts[0].wheel_radius),
					float(expected.data.model.landing_gear.contacts[0].wheel_radius)))

		var stored_trial: Dictionary = Trial.freeze(_trial_payload(loaded))
		_check("%.0f%% stored variant freezes into the compiled physical projection" % (scale_value * 100.0),
			bool(stored_trial.get("ok", false))
				and float(stored_trial.get("scale", -1.0)) == scale_value
				and _physical_projection(stored_trial.data.model) == _physical_projection(expected.data.model),
			str(stored_trial.get("errors", [])))
		if stored_trial.get("ok", false):
			_check("%.0f%% stored trial keeps scaled wheel radius" % (scale_value * 100.0),
				is_equal_approx(float(stored_trial.data.model.landing_gear.contacts[0].wheel_radius),
					float(expected.data.model.landing_gear.contacts[0].wheel_radius)))
			_check("%.0f%% authentic stored trial data passes session start qualification" % (scale_value * 100.0),
				_session_accepts(stored_trial), str(stored_trial.get("errors", [])))

		var exported: Dictionary = Bundle.export_variant(loaded)
		_check("%.0f%% endpoint exports to a portable bundle" % (scale_value * 100.0),
			bool(exported.get("ok", false)), str(exported.get("errors", [])))
		if not exported.get("ok", false):
			continue
		var decoded: Dictionary = Bundle.decode(exported.bytes)
		_check("%.0f%% portable endpoint decodes with exact scale" % (scale_value * 100.0),
			bool(decoded.get("ok", false))
				and float(decoded.get("payload", {}).get("recipe", {}).get("scale", -1.0)) == scale_value,
			str(decoded.get("errors", [])))
		if not decoded.get("ok", false):
			continue
		var portable_trial: Dictionary = Trial.freeze(decoded.payload)
		_check("%.0f%% portable endpoint freezes into the compiled physical projection" % (scale_value * 100.0),
			bool(portable_trial.get("ok", false))
				and float(portable_trial.get("scale", -1.0)) == scale_value
				and _physical_projection(portable_trial.data.model) == _physical_projection(expected.data.model),
			str(portable_trial.get("errors", [])))
		if portable_trial.get("ok", false):
			_check("%.0f%% portable trial preserves scaled wheel radius" % (scale_value * 100.0),
				is_equal_approx(float(portable_trial.data.model.landing_gear.contacts[0].wheel_radius),
					float(expected.data.model.landing_gear.contacts[0].wheel_radius)))
		if stored_trial.get("ok", false) and portable_trial.get("ok", false):
			_check("%.0f%% bundle freeze exactly matches saved-trial data and identity" % (scale_value * 100.0),
				stored_trial.data == portable_trial.data
					and stored_trial.identity.trial_id == portable_trial.identity.trial_id)


func _trial_payload(variant: Dictionary) -> Dictionary:
	return {
		"base_id": variant.base_id,
		"base_bytes": variant.base_bytes,
		"recipe": variant.recipe,
		"workshop_descriptor": variant.workshop_descriptor,
		"dependencies": variant.dependencies,
		"compiler_version": variant.compiler_version,
		"variant_id": variant.id,
		"variant_revision": variant.revision,
		"presentation_profile": variant.presentation_profile,
	}


func _test_workshop_ui() -> void:
	root.size = Vector2i(1280, 720)
	var workshop: Variant = Workshop.new()
	workshop.initial_aircraft_id = Catalog.DEFAULT_ID
	workshop.variants_root = _store_root.path_join("ui-library")
	root.add_child(workshop)
	await _ui.settle()

	var scale_selector: OptionButton = _find(workshop, "Scale") as OptionButton
	var smaller: Button = _find(workshop, "ScaleSmaller") as Button
	var larger: Button = _find(workshop, "ScaleLarger") as Button
	var readout: Label = _find(workshop, "ScaleReadout") as Label
	var shortcut_ids: Array[String] = ["Tiny", "Mini", "Original", "Large", "Giant"]
	var shortcut_values: Array[float] = [
		Parameters.MIN_SCALE, 0.5, 1.0, 2.0, Parameters.MAX_SCALE,
	]
	_check("Workshop displays selector, step controls and actual-size readout",
		scale_selector != null and smaller != null and larger != null and readout != null)
	if scale_selector == null or smaller == null or larger == null or readout == null:
		workshop.queue_free()
		await _ui.settle()
		return
	_check("legacy size selector presets remain available",
		[0.75, 1.25, 2.0].all(func(value: float) -> bool: return workshop.call("_scale_option_values").has(value)))

	var other_recipe := {
		"weight_multiplier": 1.1,
		"power_multiplier": 1.1,
		"control_multiplier": 1.1,
		"tank_capacity_multiplier": 1.1,
	}
	workshop.set_recipe(other_recipe, false)
	workshop.call("_clear_history")
	var non_scale_before: Dictionary = workshop.get_recipe()
	non_scale_before.erase("scale")
	for index in shortcut_ids.size():
		var shortcut: Button = _find(workshop, "Scale" + shortcut_ids[index]) as Button
		_check("named %s size shortcut exists" % shortcut_ids[index], shortcut != null)
		if shortcut == null:
			continue
		shortcut.pressed.emit()
		var current: Dictionary = workshop.get_recipe()
		_check("%s shortcut selects its named multiplier" % shortcut_ids[index],
			float(current.scale) == shortcut_values[index], str(current.scale))
		current.erase("scale")
		current.erase("size_model")
		_check("%s shortcut leaves every other recipe setting unchanged" % shortcut_ids[index],
			current == non_scale_before, str(current))
	var giant_span := float(workshop.get_compiled().summary.wing_span_m)
	_check("size readout reports the current percentage and accepted wingspan",
		readout.text.contains(String.num(Parameters.MAX_SCALE * 100.0, 4) + "%")
			and readout.text.contains("wingspan: " + String.num(giant_span, 4) + " m"),
		readout.text)

	workshop.set_recipe({"scale": 1.0}, false)
	workshop.call("_clear_history")
	larger.pressed.emit()
	_check("Larger steps up by ten percent", is_equal_approx(float(workshop.get_recipe().scale), 1.1))
	_check("one size click creates one Undo entry", workshop.get("_undo_history").size() == 1)
	workshop.call("_undo")
	_check("Undo restores the exact preceding size", float(workshop.get_recipe().scale) == 1.0)
	workshop.call("_redo")
	_check("Redo reapplies the exact size step", is_equal_approx(float(workshop.get_recipe().scale), 1.1)
		and workshop.get("_undo_history").size() == 1)

	smaller.pressed.emit()
	_check("opposite size steps restore the starting size", float(workshop.get_recipe().scale) == 1.0)
	workshop.call("_apply_scale", 1.0)
	_check("selecting current size is a no-op for history", workshop.get("_undo_history").size() == 2)

	workshop.call("_apply_scale", Parameters.MIN_SCALE)
	_check("Tiny lands exactly on the shared lower endpoint", float(workshop.get_recipe().scale) == Parameters.MIN_SCALE)
	_check("smaller step disables at the lower endpoint", smaller.disabled)
	var lower_history: int = workshop.get("_undo_history").size()
	workshop.call("_step_scale", -1)
	workshop.call("_apply_scale", Parameters.MIN_SCALE)
	_check("lower endpoint actions are no-op for history", workshop.get("_undo_history").size() == lower_history)
	workshop.call("_apply_scale", Parameters.MAX_SCALE)
	_check("Giant lands exactly on the shared upper endpoint", float(workshop.get_recipe().scale) == Parameters.MAX_SCALE)
	_check("larger step disables at the upper endpoint", larger.disabled)
	var upper_history: int = workshop.get("_undo_history").size()
	workshop.call("_step_scale", 1)
	workshop.call("_apply_scale", Parameters.MAX_SCALE)
	_check("upper endpoint actions are no-op for history", workshop.get("_undo_history").size() == upper_history)

	var intermediate := 1.33791
	workshop.set_recipe({"scale": intermediate}, false)
	var selected_scale := float(scale_selector.get_item_metadata(scale_selector.selected))
	_check("selector preserves an exact loaded intermediate scale", selected_scale == intermediate)
	_check("legacy option values coexist with the loaded intermediate",
		workshop.call("_scale_option_values").has(0.75)
			and workshop.call("_scale_option_values").has(1.25)
			and workshop.call("_scale_option_values").has(2.0)
			and workshop.call("_scale_option_values").has(intermediate))

	var invalid_weight: LineEdit = workshop.get("_factor_inputs")["weight_multiplier"]
	invalid_weight.text = "invalid weight"
	invalid_weight.text_changed.emit(invalid_weight.text)
	var pending_before: Dictionary = workshop.get("_pending_numbers").duplicate(true)
	workshop.call("_step_scale", 1)
	_check("size edit preserves invalid numeric text and blocking state",
		invalid_weight.text == "invalid weight"
			and workshop.get("_invalid_fields").has("weight_multiplier")
			and workshop.get("_pending_numbers") == pending_before
			and workshop.save_button.disabled
			and is_equal_approx(float(workshop.get_recipe().scale), intermediate * 1.1))
	_check("invalid numeric draft shows proposed size rather than claiming acceptance",
		readout.text.contains("Proposed size:") and readout.text.contains("wingspan pending validation."), readout.text)

	workshop.set_aircraft("gp-extra-300s-60", true)
	await _ui.settle()
	var unsupported_scale: Dictionary = workshop.get_recipe().duplicate(true)
	var unsupported_history: Array = workshop.get("_undo_history").duplicate(true)
	var shortcut: Button = _find(workshop, "ScaleGiant") as Button
	_check("unsupported aircraft disables size selector, steps and shortcuts",
		scale_selector.disabled and smaller.disabled and larger.disabled and shortcut.disabled)
	var prior_scale_index := scale_selector.selected
	workshop.call("_on_scale_selected", prior_scale_index)
	workshop.call("_apply_scale", Parameters.MAX_SCALE)
	workshop.call("_step_scale", 1)
	_check("unsupported size actions cannot change recipe or history",
		workshop.get_recipe() == unsupported_scale and workshop.get("_undo_history") == unsupported_history)
	workshop.queue_free()
	await _ui.settle()


## Compare physical model values across trial IDs and provenance-only metadata.
func _physical_projection(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value.keys():
			var name := str(key)
			if name == "id" or name == "data_sha256" or name == "wheel_profile" \
					or name.ends_with("_provenance"):
				continue
			result[key] = _physical_projection(value[key])
		return result
	if value is Array:
		var result: Array = []
		for element: Variant in value:
			result.append(_physical_projection(element))
		return result
	return value


func _finish() -> void:
	var store_root_absolute := ProjectSettings.globalize_path(_store_root)
	_remove_tree(store_root_absolute, store_root_absolute)
	print("Workshop sizes: %d checks, %d failures" % [_checks, _failures])
	TranslationServer.set_locale("en")
	quit(1 if _failures else 0)


func _remove_tree(path: String, fixture_root: String) -> void:
	var root_prefix := fixture_root.trim_suffix("/") + "/"
	assert(path == fixture_root or path.begins_with(root_prefix))
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		var child: String = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child, fixture_root)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	DirAccess.remove_absolute(path)


