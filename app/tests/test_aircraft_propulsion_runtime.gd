extends SceneTree

const Runtime: Script = preload("res://sim/aircraft_propulsion_runtime.gd")
const Flight: Script = preload("res://sim/flight_session.gd")
const Catalog: Script = preload("res://app_state/aircraft_catalog.gd")
const Propulsion: Script = preload("res://physics/propulsion.gd")

const CALLBACK_FIELDS: PackedStringArray = [
	"continuous_step",
	"continuous_evaluate",
	"continuous_loads",
	"continuous_derivative",
	"continuous_rotor_momentum",
	"continuous_aux",
]

const AVANTI_PATH: String = "res://data/aircraft/sebart_avanti_s_a200.json"
const AVANTI_ID: String = "sebart-avanti-s-a200-p100rx"
const P51_PATH: String = "res://data/aircraft/p51d_mustang_120.json"
const P51_ID: String = "p51d-mustang-120"
const BATTERY_PATH: String = "res://data/aircraft/synthetic_stik_electric_4s_battery.json"
const GLOW_PATH: String = "res://data/aircraft/stik_glow_55ax_2t.json"
const GLOW_ID: String = "stik-glow-55ax-2t"


class PreparationProbe:
	extends Node
	var aircraft: Dictionary = {}
	var sim: Node
	var glow_active: bool = false
	var turbine_continuous: bool = false
	var coupled: bool = false
	var wheel_total: int = 0
	var trace_meta_calls: int = 0

	func trace_meta() -> Dictionary:
		trace_meta_calls += 1
		return {}

	func glow_is_active() -> bool:
		return glow_active

	func turbine_is_continuous() -> bool:
		return turbine_continuous

	func shaft_is_coupled() -> bool:
		return coupled

	func wheel_count() -> int:
		return wheel_total

	func _electric_step() -> void: pass
	func _turbine_evaluate() -> void: pass
	func _turbine_aux() -> void: pass
	func _coupled_evaluate() -> void: pass
	func _wheel_evaluate() -> void: pass
	func _coupled_loads() -> void: pass
	func _wash_loads() -> void: pass
	func _coupled_derivative() -> void: pass
	func _wash_derivative() -> void: pass
	func _coupled_rotor() -> void: pass
	func _coupled_aux() -> void: pass

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog_routes()
	_test_replay_specimen("finite-battery electric", BATTERY_PATH, "", "electric_finite_battery")
	_test_replay_specimen("continuous turbine", AVANTI_PATH, AVANTI_ID, "turbine_continuous")
	_test_replay_specimen("coupled P-51 shaft", P51_PATH, P51_ID, "propeller_shaft_coupled", "coupled-rk4")
	_test_preparation_before_endpoint_state()
	_test_invalid_session()
	print("aircraft propulsion runtime: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_catalog_routes() -> void:
	for entry_value: Variant in Catalog.airplane_flyable_entries():
		if typeof(entry_value) != TYPE_DICTIONARY:
			_check("catalog entry shape", false, str(entry_value))
			continue
		var entry: Dictionary = entry_value
		var flight: Node = _new_flight(str(entry.get("data", "")), str(entry.get("id", "")))
		if flight == null:
			continue
		var label: String = str(entry.get("id", "catalog"))
		_check(label + " session flies", flight.is_flyable(), str(flight.start.get("message", "")))
		if flight.is_flyable():
			_check_contract_and_purity(label, flight, "")
		flight.free()


func _test_replay_specimen(label: String, path: String, aircraft_id: String, expected_family: String,
		integrator: String = "") -> void:
	var reference: Node = _new_flight(path, aircraft_id, integrator)
	var adapted: Node = _new_flight(path, aircraft_id, integrator)
	if reference == null or adapted == null:
		if reference != null:
			reference.free()
		if adapted != null:
			adapted.free()
		return
	_check(label + " paired sessions fly", reference.is_flyable() and adapted.is_flyable())
	if not reference.is_flyable() or not adapted.is_flyable():
		reference.free()
		adapted.free()
		return

	var prepared: Dictionary = Runtime.prepare_callbacks(adapted)
	_check(label + " reports expected physical family", prepared.get("ok", false)
		and prepared.get("family", "") == expected_family, str(prepared))
	_check_callback_set(label, adapted, prepared)
	var initial_state: PackedByteArray = var_to_bytes(adapted.checkpoint())
	var initial_observation: Dictionary = Runtime.observe(adapted)
	_check(label + " observation is available", initial_observation.get("ok", false), str(initial_observation.get("errors", [])))
	_check(label + " preparation and observation leave the complete family checkpoint unchanged",
		initial_state == var_to_bytes(adapted.checkpoint()))
	_check_observation(label, adapted, initial_observation)
	_install_callbacks(adapted, prepared)
	_check(label + " callback installation leaves checkpoint unchanged",
		initial_state == var_to_bytes(adapted.checkpoint()))

	for _tick: int in 24:
		reference.sim.step()
		adapted.sim.step()
		if not reference.sim.fault_reason.is_empty() or not adapted.sim.fault_reason.is_empty():
			break
	_check(label + " oracle and adapter advance without faults",
		reference.sim.fault_reason.is_empty() and adapted.sim.fault_reason.is_empty(),
		reference.sim.fault_reason + " / " + adapted.sim.fault_reason)
	_check(label + " callback adapter preserves exact replay checkpoint",
		var_to_bytes(reference.checkpoint()) == var_to_bytes(adapted.checkpoint()))
	var after_observation: Dictionary = Runtime.observe(adapted)
	_check(label + " family state after accepted ticks remains observable", after_observation.get("ok", false),
		str(after_observation.get("errors", [])))
	_check_observation(label + " after ticks", adapted, after_observation)
	_check(label + " repeated observation keeps installation ID stable",
		initial_observation.get("installation_id", "") == after_observation.get("installation_id", ""))
	reference.free()
	adapted.free()


func _check_contract_and_purity(label: String, flight: Node, expected_family: String) -> void:
	var before: PackedByteArray = var_to_bytes(flight.checkpoint())
	var prepared: Dictionary = Runtime.prepare_callbacks(flight)
	_check(label + " callback contract is prepared", prepared.get("ok", false), str(prepared.get("errors", [])))
	_check_callback_set(label, flight, prepared)
	var observed: Dictionary = Runtime.observe(flight)
	_check(label + " observes current propulsion", observed.get("ok", false), str(observed.get("errors", [])))
	if not expected_family.is_empty():
		_check(label + " physical family is stable", observed.get("family", "") == expected_family)
	_check(label + " preparation and observation are read-only", before == var_to_bytes(flight.checkpoint()))
	_check_observation(label, flight, observed)


func _check_callback_set(label: String, flight: Node, prepared: Dictionary) -> void:
	var sim: Node = flight.sim
	for field: String in CALLBACK_FIELDS:
		_check(label + " callback matches current FlightSession route: " + field,
			prepared.has(field) and prepared[field] == sim.get(field))


func _install_callbacks(flight: Node, prepared: Dictionary) -> void:
	for field: String in CALLBACK_FIELDS:
		flight.sim.set(field, prepared.get(field, Callable()))


func _check_observation(label: String, flight: Node, observed: Dictionary) -> void:
	if not observed.get("ok", false):
		return
	var metadata: Dictionary = flight.trace_meta()
	var state_layout: Dictionary = observed.get("state_layout", {})
	var body: Variant = JSON.parse_string(str(metadata.get("state_layout", "null")))
	var auxiliary: Variant = JSON.parse_string(str(metadata.get("aux_layout", "null")))
	_check(label + " reuses existing body and auxiliary layout", state_layout.get("body") == body
		and state_layout.get("aux") == auxiliary)
	_check(label + " reports the existing continuous layout and size",
		state_layout.get("continuous_description", "") == metadata.get("continuous_layout", "")
		and state_layout.get("continuous_size", -1) == flight.sim.continuous.size())
	_check(label + " reports existing law identity and source kind",
		observed.get("law_identity", "") == metadata.get("propulsion_model", "")
		and observed.get("kind", "") == Propulsion.source_kind(flight.aircraft.model.propulsion))
	_check(label + " has one stable model-scoped propulsion installation",
		observed.get("installation_id", "") == "aircraft/%s/propulsion/%s" % [flight.aircraft.model.id, flight.aircraft.model.propulsion.get("id", "single")]
		and observed.get("installation_scope", "") == "current_single_installation")
	var telemetry: Dictionary = observed.get("telemetry", {})
	if telemetry.has("rpm"):
		_check(label + " actual RPM comes from family telemetry",
			is_equal_approx(float(observed.get("actual_rpm", NAN)), float(telemetry.rpm)))
	else:
		var rpm_index: int = auxiliary.find("engine_rpm") if typeof(auxiliary) == TYPE_ARRAY else -1
		_check(label + " actual RPM resolves through the declared auxiliary layout",
			rpm_index >= 0 and rpm_index < flight.sim.aux.size()
			and float(observed.get("actual_rpm", NAN)) == flight.sim.aux[rpm_index])
	var expected_family_state: Dictionary = _family_state(flight, observed.get("family", ""))
	if not expected_family_state.is_empty():
		_check(label + " telemetry preserves existing family observation",
			telemetry == expected_family_state)


func _family_state(flight: Node, family: String) -> Dictionary:
	if family.begins_with("glow_"):
		return flight.glow_state()
	if family.begins_with("turbine_"):
		return flight.turbine_state()
	if family.begins_with("electric_"):
		return flight.electrical_state()
	return {}


func _new_flight(path: String, aircraft_id: String, integrator: String = "") -> Node:
	if path.is_empty():
		_check("flight fixture has a data path", false)
		return null
	var flight: Node = Flight.new()
	if not integrator.is_empty() and not flight.setup_shaft_integrator(integrator):
		_check("fixture accepts the requested shaft integrator", false, str(flight.shaft_error))
		flight.free()
		return null
	flight.setup(path, aircraft_id)
	flight.input_enabled = false
	return flight


func _test_invalid_session() -> void:
	var prepared: Dictionary = Runtime.prepare_callbacks(null)
	var observed: Dictionary = Runtime.observe(null)
	_check("null session preparation returns a diagnostic", not prepared.get("ok", true)
		and not prepared.get("errors", PackedStringArray()).is_empty())
	_check("null session observation returns a diagnostic", not observed.get("ok", true)
		and not observed.get("errors", PackedStringArray()).is_empty())


func _test_preparation_before_endpoint_state() -> void:
	var old_glow: Node = _new_flight(GLOW_PATH, GLOW_ID)
	var incoming: Node = _new_flight(P51_PATH, P51_ID, "coupled-rk4")
	if old_glow == null or incoming == null:
		if old_glow != null:
			old_glow.free()
		if incoming != null:
			incoming.free()
		return
	if not old_glow.is_flyable() or not incoming.is_flyable():
		_check("preparation boundary fixtures fly", false)
		old_glow.free()
		incoming.free()
		return

	var original_aux: PackedFloat64Array = incoming.sim.aux.duplicate()
	var original_continuous: PackedFloat64Array = incoming.sim.continuous.duplicate()
	incoming.sim.aux = PackedFloat64Array()
	incoming.sim.continuous = PackedFloat64Array()
	var before_reset: Dictionary = Runtime.prepare_callbacks(incoming)
	_check("pre-reset preparation accepts empty sampled and continuous arrays", before_reset.get("ok", false),
		str(before_reset.get("errors", [])))
	_check("pre-reset preparation leaves endpoint arrays empty",
		incoming.sim.aux.is_empty() and incoming.sim.continuous.is_empty())
	_check("preparation defers law identity until endpoint observation", not before_reset.has("law_identity"))
	incoming.sim.aux = original_aux
	incoming.sim.continuous = original_continuous

	var blank_probe: PreparationProbe = _probe_for(incoming)
	blank_probe.sim = Node.new()
	var blank_result: Dictionary = Runtime.prepare_callbacks(blank_probe)
	_check("uninitialized session probe prepares callbacks without a trace snapshot",
		blank_result.get("ok", false) and blank_probe.trace_meta_calls == 0)
	_check("preparation binds the selected coupled route",
		blank_result.get("continuous_evaluate") == Callable(blank_probe, "_coupled_evaluate")
		and blank_result.get("continuous_rotor_momentum") == Callable(blank_probe, "_coupled_rotor"))
	blank_probe.sim.free()
	blank_probe.free()

	var reload_probe: PreparationProbe = _probe_for(incoming)
	reload_probe.sim = old_glow.sim
	_check("cross-family reload fixture has incompatible continuous layout lengths",
		old_glow.sim.continuous.size() != incoming.sim.continuous.size(),
		"old glow=%d; incoming coupled P-51=%d" % [
		old_glow.sim.continuous.size(), incoming.sim.continuous.size()])
	var reload_result: Dictionary = Runtime.prepare_callbacks(reload_probe)
	_check("cross-family reload prepares against the previous family's live state",
		reload_result.get("ok", false) and reload_probe.trace_meta_calls == 0,
		"old glow continuous=%d; incoming coupled P-51=%d" % [
		old_glow.sim.continuous.size(), incoming.sim.continuous.size()])
	_check("cross-family preparation does not include a trace law snapshot",
		not reload_result.has("law_identity"))
	reload_probe.free()
	old_glow.free()
	incoming.free()


func _probe_for(flight: Node) -> PreparationProbe:
	var probe: PreparationProbe = PreparationProbe.new()
	probe.aircraft = flight.aircraft
	probe.glow_active = flight.glow_is_active()
	probe.turbine_continuous = flight.turbine_is_continuous()
	probe.coupled = flight.shaft_is_coupled()
	probe.wheel_total = flight.wheel_count()
	return probe


func _check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label, " ", detail)
