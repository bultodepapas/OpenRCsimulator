extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const PACK_PATH := "res://data/aircraft/battery/turbo_lumber_evolution_4s_pack.json"

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loaded: Dictionary = AircraftData.load_file(PACK_PATH)
	_check("Turbo Lumber pack fixture loads", loaded.get("ok", false), str(loaded.get("errors", [])))
	if not loaded.get("ok", false):
		_finish()
		return
	var prop: Dictionary = loaded.model.propulsion
	var prop_variant: Dictionary = prop.duplicate(true)
	var battery_variant: Dictionary = prop_variant["battery"]
	battery_variant["initial_soc"] = 0.82
	battery_variant["weak_soc_offset"] = 0.015
	prop_variant["battery"] = battery_variant
	var failed_pack: Dictionary = prop.duplicate(true)
	var failed_battery: Dictionary = failed_pack["battery"]
	failed_battery["initial_soc"] = NAN
	failed_pack["battery"] = failed_battery
	var failed_esc: Dictionary = prop.duplicate(true)
	var failed_esc_data: Dictionary = failed_esc["esc"]
	failed_esc_data["command_mapping"] = "unsupported"
	failed_esc["esc"] = failed_esc_data
	var cases: Array[Dictionary] = [
		{"id": "default pack, zero inflow", "prop": prop, "duty": 0.5, "u": 0.0, "rho": 1.225, "status": "equilibrium"},
		{"id": "default pack, forward inflow", "prop": prop, "duty": 0.75, "u": 8.0, "rho": 1.0, "status": "equilibrium"},
		{"id": "default pack, thin air", "prop": prop, "duty": 0.35, "u": 5.0, "rho": 0.9, "status": "equilibrium"},
		{"id": "changed initial pack SOC", "prop": prop_variant, "duty": 0.6, "u": 11.0, "rho": 0.95, "status": "equilibrium"},
		{"id": "zero-duty pack", "prop": prop, "duty": 0.0, "u": 0.0, "rho": 1.225, "status": "unbracketed"},
		{"id": "invalid pack SOC", "prop": failed_pack, "duty": 0.5, "u": 0.0, "rho": 1.225, "status": "invalid"},
		{"id": "invalid ESC mapping", "prop": failed_esc, "duty": 0.5, "u": 0.0, "rho": 1.225, "status": "invalid"},
		{"id": "invalid duty", "prop": prop, "duty": 1.1, "u": 0.0, "rho": 1.225, "status": "invalid"},
	]
	for fixture: Dictionary in cases:
		var result: Dictionary = Propulsion.steady_operating_point(
			float(fixture.duty), float(fixture.u), fixture.prop, float(fixture.rho))
		var expected_status: String = str(fixture.status)
		var label: String = str(fixture.id)
		_check(label + " retains its root status", str(result.get("status", "")) == expected_status,
			str(result.get("message", "")))
		if expected_status == "equilibrium":
			var residual: float = float(result.get("residual", NAN))
			_check(label + " has finite RPM and small equilibrium residual",
				result.get("ok", false) and is_finite(float(result.get("rpm", NAN)))
					and float(result.rpm) > 0.0 and is_finite(residual) and absf(residual) < 1e-8,
				"rpm=%s residual=%s" % [str(result.get("rpm", NAN)), String.num_scientific(residual)])

	_check_pack_source_context(prop, prop_variant, failed_pack)
	_check_fused_torque_probes(prop, prop_variant, failed_pack)
	_finish()


func _check_pack_source_context(prop: Dictionary, prop_variant: Dictionary, failed_pack: Dictionary) -> void:
	var context_a: Dictionary = {uses_pack_ecm = true}
	var rpm_a: float = 5600.0
	var duty_a: float = 0.55
	var full_public_a: Dictionary = Propulsion.electric_source_state(rpm_a, duty_a, prop)
	var prop_a_bytes: PackedByteArray = var_to_bytes(prop)
	var full_prepared_a: Dictionary = Propulsion._electric_equilibrium_source_state(
		rpm_a, duty_a, prop, context_a)
	_check("prepared full pack source succeeds", full_public_a.get("ok", false) and full_prepared_a.get("ok", false))
	_check("prepared full pack source matches the public result byte-for-byte",
		var_to_bytes(full_prepared_a) == var_to_bytes(full_public_a))
	_check("first source call stores a rested pack block",
		context_a.has("pack_trim_block") and not context_a.pack_trim_block.is_empty())
	var block_a_bytes: PackedByteArray = var_to_bytes(context_a.pack_trim_block)

	var compact_a: Dictionary = Propulsion._electric_equilibrium_source_state(
		rpm_a, duty_a, prop, context_a, true)
	_check("compact pack source preserves every field the equilibrium root consumes",
		compact_a.get("ok", false) == full_public_a.get("ok", false)
			and float(compact_a.get("shaft_torque_nm", NAN)) == float(full_public_a.get("shaft_torque_nm", NAN))
			and float(compact_a.get("motor_current_a", NAN)) == float(full_public_a.get("motor_current_a", NAN))
			and float(compact_a.get("pack_current_a", NAN)) == float(full_public_a.get("pack_current_a", NAN)))
	_check("compact pack source omits telemetry-only voltage and source fields",
		not compact_a.has("bus_voltage_v") and not compact_a.has("source_kind"))

	var context_b: Dictionary = {uses_pack_ecm = true}
	var full_public_b: Dictionary = Propulsion.electric_source_state(rpm_a, duty_a, prop_variant)
	var prop_b_bytes: PackedByteArray = var_to_bytes(prop_variant)
	var full_prepared_b: Dictionary = Propulsion._electric_equilibrium_source_state(
		rpm_a, duty_a, prop_variant, context_b)
	_check("a second context prepares the changed pack independently",
		context_b.has("pack_trim_block")
			and var_to_bytes(context_a.pack_trim_block) != var_to_bytes(context_b.pack_trim_block)
			and var_to_bytes(full_prepared_b) == var_to_bytes(full_public_b))
	var rpm_next: float = 6200.0
	var duty_next: float = 0.7
	var full_public_a_next: Dictionary = Propulsion.electric_source_state(rpm_next, duty_next, prop)
	var full_prepared_a_next: Dictionary = Propulsion._electric_equilibrium_source_state(
		rpm_next, duty_next, prop, context_a)
	_check("A/B contexts and repeated inputs do not contaminate the first pack result",
		var_to_bytes(full_prepared_a_next) == var_to_bytes(full_public_a_next)
			and var_to_bytes(context_a.pack_trim_block) == block_a_bytes)

	var failed_context: Dictionary = {uses_pack_ecm = true}
	var failed_public: Dictionary = Propulsion.electric_source_state(5000.0, 0.5, failed_pack)
	var failed_prop_bytes: PackedByteArray = var_to_bytes(failed_pack)
	var failed_prepared: Dictionary = Propulsion._electric_equilibrium_source_state(
		5000.0, 0.5, failed_pack, failed_context)
	var failed_compact: Dictionary = Propulsion._electric_equilibrium_source_state(
		5000.0, 0.5, failed_pack, {uses_pack_ecm = true}, true)
	_check("prepared pack failure retains the public status and message",
		var_to_bytes(failed_prepared) == var_to_bytes(failed_public)
			and var_to_bytes(failed_compact) == var_to_bytes(failed_public))
	_check("prepared full, compact, and repeated A/B calls leave every input prop unchanged",
		var_to_bytes(prop) == prop_a_bytes and var_to_bytes(prop_variant) == prop_b_bytes
			and var_to_bytes(failed_pack) == failed_prop_bytes)


func _check_fused_torque_probes(prop: Dictionary, prop_variant: Dictionary, failed_pack: Dictionary) -> void:
	var context: Dictionary = {uses_pack_ecm = true}
	var original_prop: PackedByteArray = var_to_bytes(prop)
	var retained_sample: PackedFloat64Array = PackedFloat64Array()
	var retained_bytes := PackedByteArray()
	# Compare each consumed value with the independently evaluated public source/load arithmetic.
	for inputs: PackedFloat64Array in [PackedFloat64Array([5600.0, 0.55, 5.0, 1.225]),
			PackedFloat64Array([5601.0, 0.55, 5.0, 1.225]), PackedFloat64Array([5601.0, 0.56, 5.0, 1.225]),
			PackedFloat64Array([5601.0, 0.56, 6.0, 1.225]), PackedFloat64Array([5601.0, 0.56, 6.0, 1.1])]:
		var source: Dictionary = Propulsion.electric_source_state(inputs[0], inputs[1], prop)
		var load: float = Propulsion.prop_torque(inputs[0], inputs[2], prop, inputs[3])
		var expected_residual: float = float(source.shaft_torque_nm) - load
		var expected_tolerance: float = Propulsion.ELECTRIC_ROOT_TORQUE_TOL \
			* maxf(1.0, maxf(absf(float(source.shaft_torque_nm)), absf(load)))
		var probe: PackedFloat64Array = Propulsion._electric_residual_and_tolerance(
			inputs[0], inputs[1], inputs[2], prop, inputs[3], context)
		_check("fused torque probe matches independent residual/tolerance arithmetic for " + str(inputs),
			var_to_bytes(probe) == var_to_bytes(PackedFloat64Array([expected_residual, expected_tolerance])))
		if retained_sample.is_empty():
			retained_sample = probe
			retained_bytes = var_to_bytes(retained_sample)
	_check("later probes leave a returned pair and the source model unchanged",
		var_to_bytes(retained_sample) == retained_bytes and var_to_bytes(prop) == original_prop)
	var changed_context: Dictionary = {uses_pack_ecm = true}
	var changed_source: Dictionary = Propulsion.electric_source_state(5600.0, 0.55, prop_variant)
	var changed_load: float = Propulsion.prop_torque(5600.0, 5.0, prop_variant, 1.225)
	var changed_probe: PackedFloat64Array = Propulsion._electric_residual_and_tolerance(
		5600.0, 0.55, 5.0, prop_variant, 1.225, changed_context)
	_check("a changed pack produces its independent fused residual/tolerance",
		changed_probe[0] == float(changed_source.shaft_torque_nm) - changed_load \
			and changed_probe[1] == Propulsion.ELECTRIC_ROOT_TORQUE_TOL \
				* maxf(1.0, maxf(absf(float(changed_source.shaft_torque_nm)), absf(changed_load))))
	var failed_context: Dictionary = {uses_pack_ecm = true}
	var failed_probe: PackedFloat64Array = Propulsion._electric_residual_and_tolerance(
		5600.0, 0.55, 5.0, failed_pack, 1.225, failed_context)
	_check("invalid source retains both nonfinite fused values",
		failed_probe.size() == 2 and is_nan(failed_probe[0]) and is_nan(failed_probe[1]))


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("ok    " + label)
		return
	_failures += 1
	printerr("FAIL  " + label + (" — " + detail if not detail.is_empty() else ""))


func _finish() -> void:
	print("Electric equilibrium preparation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
