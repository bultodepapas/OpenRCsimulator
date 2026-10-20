## Exact regression for the stage-local layout-query hoist in _ground_evaluation.
## Run from the app project with: godot --headless --path . --script <absolute-draft-path>
extends SceneTree

const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const LakeLoader := preload("res://data/lake_loader.gd")
const GroundStart := preload("res://physics/ground_start.gd")

const DRAFT_DIR := "C:/DEVELOPMENT/OpenRCsimulator/tmp/perf-pass2-20261019"
const AIRCRAFT_CASES := [
	{"id": "jensen-das-ugly-stik-60", "label": "Stik"},
	{"id": "p51d-mustang-120", "label": "P-51"},
	{"id": "turbo-lumber-evolution", "label": "Lumber"},
	{"id": "stik-glow-61fx-2t", "label": "Glow Stik"},
	{"id": "sebart-avanti-s-a200-p100rx", "label": "Avanti"},
]

var _failures: int = 0
var _checks: int = 0
var _wheel_layouts_seen: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _initialize() -> void:
	var reference_script: Script = load(DRAFT_DIR.path_join("ground_stage_reference.gd"))
	var candidate_script: Script = load(DRAFT_DIR.path_join("flight_session_offset_mutation.gd"))
	_check("reference and candidate scripts load", reference_script != null and candidate_script != null)
	if reference_script == null or candidate_script == null:
		quit(1)
		return
	var field_result: Dictionary = FieldLoader.load_from()
	var lake_result: Dictionary = LakeLoader.load_from(LakeLoader.DEFAULT_PATH)
	_check("field and lake definitions load", field_result.get("ok", false) and lake_result.get("ok", false))
	if not field_result.get("ok", false) or not lake_result.get("ok", false):
		quit(1)
		return
	var runway_ne: PackedFloat64Array = _runway_start(field_result.field)
	var lake_ne := PackedFloat64Array([
		float(lake_result.lake.origin_north_m), float(lake_result.lake.origin_east_m)])
	_check("field fixture contains a runway", runway_ne.size() == 2)
	if runway_ne.size() != 2:
		quit(1)
		return
	for aircraft_case: Dictionary in AIRCRAFT_CASES:
		_run_aircraft_case(reference_script, candidate_script, aircraft_case,
			field_result.field, lake_result.lake, runway_ne, lake_ne)
	_check("catalog cases exercise a rotating-wheel layout", _wheel_layouts_seen > 0)
	print("%d ground-stage checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_aircraft_case(reference_script: Script, candidate_script: Script, aircraft_case: Dictionary,
		field: Dictionary, lake: Dictionary, runway_ne: PackedFloat64Array, lake_ne: PackedFloat64Array) -> void:
	var aircraft_id: String = str(aircraft_case.id)
	var label: String = str(aircraft_case.label)
	var entry: Dictionary = Catalog.entry(aircraft_id)
	if entry.is_empty() or str(entry.get("data", "")).is_empty():
		_check("%s catalog entry is available" % label, false, aircraft_id)
		return
	var reference: Node = _new_session(reference_script, str(entry.data), aircraft_id, field, lake)
	var candidate: Node = _new_session(candidate_script, str(entry.data), aircraft_id, field, lake)
	if reference == null or candidate == null:
		if reference != null:
			reference.free()
		if candidate != null:
			candidate.free()
		return
	candidate._ground_offset_mutation_armed = true
	var initial_equal: bool = var_to_bytes(_session_numeric_state(reference)) == var_to_bytes(_session_numeric_state(candidate))
	_check("%s initial simulation state is byte-identical" % label, initial_equal)
	_check("%s stage has live inputs and aux" % label,
		reference.sim.inputs.size() == reference._input_count()
		and candidate.sim.inputs.size() == candidate._input_count()
		and reference.sim.aux.size() == candidate.sim.aux.size())

	var runway_airborne: PackedFloat64Array = _state_at(reference.sim.state, runway_ne, -8.0)
	_compare_case("%s airborne over field" % label, reference, candidate, runway_airborne, false)
	var runway_contact: PackedFloat64Array = _state_at(reference.sim.state, runway_ne, 0.20)
	_compare_case("%s compressed gear on field" % label, reference, candidate, runway_contact, false)
	var lake_contact: PackedFloat64Array = _state_at(reference.sim.state, lake_ne, 0.70)
	_compare_case("%s ground evaluation with lake context" % label, reference, candidate, lake_contact, false)
	var reference_soft_hull: bool = reference.soft_hull_contacts
	var candidate_soft_hull: bool = candidate.soft_hull_contacts
	reference.soft_hull_contacts = false
	candidate.soft_hull_contacts = false
	_compare_case("%s contact with soft hull disabled" % label, reference, candidate, runway_contact, false)
	reference.soft_hull_contacts = reference_soft_hull
	candidate.soft_hull_contacts = candidate_soft_hull

	var wheel_total: int = candidate.wheel_count()
	var first_wheel: int = candidate.wheel_index()
	if wheel_total > 0 and first_wheel >= 0 and first_wheel + wheel_total <= candidate.sim.continuous.size():
		_wheel_layouts_seen += 1
		var valid_values: PackedFloat64Array = _evaluation_values(candidate)
		_check("%s reference and candidate wheel layouts match" % label,
			first_wheel == reference.wheel_index() and wheel_total == reference.wheel_count()
			and valid_values.size() == first_wheel + wheel_total)
		_compare_values_case("%s valid wheel speeds" % label, reference, candidate, runway_contact,
			_evaluation_values(reference), valid_values, false)
		if reference.liquid_fuel_is_active() and candidate.liquid_fuel_is_active():
			var reference_properties: Dictionary = reference._liquid_properties(reference.sim.continuous)
			var candidate_properties: Dictionary = candidate._liquid_properties(candidate.sim.continuous)
			_check("%s supplied liquid mass properties are valid and match" % label,
				bool(reference_properties.get("ok", false)) and bool(candidate_properties.get("ok", false))
				and var_to_bytes(reference_properties) == var_to_bytes(candidate_properties))
			_compare_values_case("%s supplied liquid properties" % label, reference, candidate, runway_contact,
				_evaluation_values(reference), _evaluation_values(candidate), false,
				PackedFloat64Array(), PackedFloat64Array(), reference_properties, candidate_properties)
		var short_values: PackedFloat64Array = valid_values.duplicate()
		short_values.resize(first_wheel + wheel_total - 1)
		_compare_values_case("%s short wheel state is rejected" % label, reference, candidate, runway_contact,
			short_values.duplicate(), short_values.duplicate(), true)
		var nonfinite_values: PackedFloat64Array = valid_values.duplicate()
		nonfinite_values[first_wheel] = INF
		_compare_values_case("%s non-finite wheel speed is rejected" % label, reference, candidate, runway_contact,
			nonfinite_values.duplicate(), nonfinite_values.duplicate(), true)
		if candidate.gear_is_retractable():
			var gear_index: int = candidate.gear_aux_index()
			for extension: float in [0.0, 0.5, 1.0]:
				var reference_aux: PackedFloat64Array = reference.sim.aux.duplicate()
				var candidate_aux: PackedFloat64Array = candidate.sim.aux.duplicate()
				reference_aux[reference.gear_aux_index()] = extension
				candidate_aux[gear_index] = extension
				reference_aux[reference.gear_aux_index() + 1] = 1.0 if extension >= 0.5 else 0.0
				candidate_aux[gear_index + 1] = 1.0 if extension >= 0.5 else 0.0
				_compare_values_case("%s gear extension %.1f" % [label, extension], reference, candidate,
					runway_contact, _evaluation_values(reference), _evaluation_values(candidate), false,
					reference_aux, candidate_aux)

	var candidate_profile: Dictionary = candidate.aircraft.model.get("wheel_profile", {})
	if wheel_total > 0 and str(candidate_profile.get("status", "")) == "applied":
		_profile_edit_and_reset_probe(label, reference, candidate, runway_ne, runway_contact)
	reference.free()
	candidate.free()


func _new_session(script: Script, aircraft_path: String, aircraft_id: String,
		field: Dictionary, lake: Dictionary) -> Node:
	var session: Node = script.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.external_controller_selection = true
	session.crash_auto_restart = false
	session.soft_hull_contacts = true
	session.setup(aircraft_path, aircraft_id)
	if not session.aircraft.get("ok", false):
		_check("%s aircraft data loads" % aircraft_id, false, str(session.aircraft.get("errors", [])))
		session.free()
		return null
	var field_ok: bool = session.set_field(field)
	var lake_ok: bool = session.set_lake_context(lake)
	_check("%s receives field and lake context" % aircraft_id, field_ok and lake_ok,
		"field=%s lake=%s" % [field_ok, lake_ok])
	if not field_ok or not lake_ok:
		session.free()
		return null
	session.reset()
	return session


func _session_numeric_state(session: Node) -> Array:
	return [session.sim.state, session.sim.aux, session.sim.continuous, session.sim.inputs,
		session.sim.last_loads, session.sim.modes]


func _runway_start(field: Dictionary) -> PackedFloat64Array:
	var spot: Dictionary = GroundStart.threshold(field)
	if not spot.get("ok", false):
		return PackedFloat64Array()
	return PackedFloat64Array([float(spot.north), float(spot.east)])


func _state_at(source: PackedFloat64Array, north_east: PackedFloat64Array, down_m: float) -> PackedFloat64Array:
	var result: PackedFloat64Array = source.duplicate()
	result[RB.POS] = north_east[0]
	result[RB.POS + 1] = north_east[1]
	result[RB.POS + 2] = down_m
	return result


func _evaluation_values(session: Node) -> PackedFloat64Array:
	var continuous: PackedFloat64Array = session.sim.continuous
	var first_wheel: int = session.wheel_index()
	var wheel_total: int = session.wheel_count()
	var required: int = first_wheel + wheel_total
	var result: PackedFloat64Array = continuous.slice(0, required) if required <= continuous.size() else continuous.duplicate()
	for index in wheel_total:
		result[first_wheel + index] = 0.75 * float(index + 1)
	return result


func _stage_air(session: Node, state: PackedFloat64Array) -> Dictionary:
	var air: Dictionary = session.air_data(state, 0.0)
	return {v_air = air.get("v_air", PackedFloat64Array([0.0, 0.0, 0.0]))}


func _compare_case(label: String, reference: Node, candidate: Node, state: PackedFloat64Array,
		expect_rejection: bool) -> void:
	_compare_values_case(label, reference, candidate, state,
		_evaluation_values(reference), _evaluation_values(candidate), expect_rejection)


func _compare_values_case(label: String, reference: Node, candidate: Node, state: PackedFloat64Array,
		reference_values: PackedFloat64Array, candidate_values: PackedFloat64Array, expect_rejection: bool,
		reference_aux_input: PackedFloat64Array = PackedFloat64Array(),
		candidate_aux_input: PackedFloat64Array = PackedFloat64Array(),
		reference_properties_input: Dictionary = {}, candidate_properties_input: Dictionary = {}) -> void:
	var reference_state: PackedFloat64Array = state.duplicate()
	var candidate_state: PackedFloat64Array = state.duplicate()
	var reference_aux: PackedFloat64Array = reference_aux_input.duplicate() if not reference_aux_input.is_empty() else reference.sim.aux.duplicate()
	var candidate_aux: PackedFloat64Array = candidate_aux_input.duplicate() if not candidate_aux_input.is_empty() else candidate.sim.aux.duplicate()
	var reference_air: Dictionary = _stage_air(reference, reference_state)
	var candidate_air: Dictionary = _stage_air(candidate, candidate_state)
	# Finite-liquid sessions prepare mass properties before entering the ground stage.
	# Match that caller contract even for deliberately malformed wheel subarrays.
	var reference_properties: Dictionary = reference_properties_input.duplicate(true)
	var candidate_properties: Dictionary = candidate_properties_input.duplicate(true)
	if reference_properties.is_empty() and reference.liquid_fuel_is_active():
		reference_properties = reference._liquid_properties(reference.sim.continuous)
	if candidate_properties.is_empty() and candidate.liquid_fuel_is_active():
		candidate_properties = candidate._liquid_properties(candidate.sim.continuous)
	var reference_before: PackedByteArray = var_to_bytes([reference_state, reference_aux, reference_values, reference_air, reference_properties])
	var candidate_before: PackedByteArray = var_to_bytes([candidate_state, candidate_aux, candidate_values, candidate_air, candidate_properties])
	var reference_inputs_before: PackedByteArray = var_to_bytes(reference.sim.inputs)
	var candidate_inputs_before: PackedByteArray = var_to_bytes(candidate.sim.inputs)
	var reference_result: Dictionary = reference._ground_evaluation(reference_state, reference_aux,
		reference_values, reference_air, reference_properties)
	var candidate_result: Dictionary = candidate._ground_evaluation(candidate_state, candidate_aux,
		candidate_values, candidate_air, candidate_properties)
	_check("%s result dictionary is byte-identical" % label,
		var_to_bytes(reference_result) == var_to_bytes(candidate_result))
	_check("%s caller arrays and maps stay unchanged" % label,
		var_to_bytes([reference_state, reference_aux, reference_values, reference_air, reference_properties]) == reference_before
		and var_to_bytes([candidate_state, candidate_aux, candidate_values, candidate_air, candidate_properties]) == candidate_before
		and var_to_bytes(reference.sim.inputs) == reference_inputs_before
		and var_to_bytes(candidate.sim.inputs) == candidate_inputs_before)
	if expect_rejection:
		_check("%s preserves fail-closed result" % label,
			_not_ok(reference_result) and _not_ok(candidate_result))
	else:
		_check("%s remains an accepted stage" % label,
			bool(reference_result.get("ok", false)) and bool(candidate_result.get("ok", false)))


func _not_ok(result: Dictionary) -> bool:
	var loads: PackedFloat64Array = result.get("loads", PackedFloat64Array())
	return not result.get("ok", false) and loads.size() == 1 and is_nan(loads[0])


func _profile_edit_and_reset_probe(label: String, reference: Node, candidate: Node,
		runway_ne: PackedFloat64Array, contact_state: PackedFloat64Array) -> void:
	# There is no public wheel-profile edit API: this test-only valid status transition exercises fresh per-call
	# layout reads without adding a persistent cache. Restore the accepted profile before reset.
	# Preserve the stage's already-evaluated mass properties across this test-only layout edit.
	var reference_properties: Dictionary = reference._liquid_properties(reference.sim.continuous) if reference.liquid_fuel_is_active() else {}
	var candidate_properties: Dictionary = candidate._liquid_properties(candidate.sim.continuous) if candidate.liquid_fuel_is_active() else {}
	var reference_model: Dictionary = reference.aircraft.model
	var candidate_model: Dictionary = candidate.aircraft.model
	var reference_profile: Dictionary = reference_model.get("wheel_profile", {}).duplicate(true)
	var candidate_profile: Dictionary = candidate_model.get("wheel_profile", {}).duplicate(true)
	var reference_fallback: Dictionary = reference_profile.duplicate(true)
	var candidate_fallback: Dictionary = candidate_profile.duplicate(true)
	reference_fallback.status = "legacy_fallback"
	candidate_fallback.status = "legacy_fallback"
	reference_model.wheel_profile = reference_fallback
	candidate_model.wheel_profile = candidate_fallback
	reference.aircraft.model = reference_model
	candidate.aircraft.model = candidate_model
	var state_ref: PackedFloat64Array = _state_at(reference.sim.state, runway_ne, contact_state[RB.POS + 2])
	_compare_values_case("%s after live wheel-profile edit" % label, reference, candidate, state_ref,
		_evaluation_values(reference), _evaluation_values(candidate), false,
		PackedFloat64Array(), PackedFloat64Array(), reference_properties, candidate_properties)
	# Restore the applied profile, then reset both sessions before the next evaluation to test reset-boundary reuse.
	reference_model = reference.aircraft.model
	candidate_model = candidate.aircraft.model
	reference_model.wheel_profile = reference_profile
	candidate_model.wheel_profile = candidate_profile
	reference.aircraft.model = reference_model
	candidate.aircraft.model = candidate_model
	reference.reset()
	candidate._ground_offset_mutation_armed = false
	candidate.reset()
	candidate._ground_offset_mutation_armed = true
	_check("%s profile restore and reset state are byte-identical" % label,
		var_to_bytes(_session_numeric_state(reference)) == var_to_bytes(_session_numeric_state(candidate)))
	var reset_state: PackedFloat64Array = _state_at(reference.sim.state, runway_ne, 0.20)
	_compare_case("%s after reset" % label, reference, candidate, reset_state, false)
