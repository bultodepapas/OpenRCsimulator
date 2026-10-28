## NK-3 prepared Ct/Cp propeller components, independent of source-stage admission.
## Actual catalog axes/tables plus stopped, reverse, crossflow and malformed stage inputs.
extends "stage_oracle.gd"

const Dynamics := preload("res://physics/dynamics.gd")


func _checks() -> void:
	_report.format = "openrc-nk3-propeller-oracle v1"
	var context := _session_context()
	if context.is_empty():
		return
	for id: String in Catalog.airplane_flyable_ids():
		var loaded: Dictionary = AircraftData.load_file(Catalog.data_for(id))
		if not loaded.ok:
			_failures.append("propeller catalog model failed: " + id)
			continue
		var prop: Dictionary = loaded.model.propulsion
		if not prop.has("ct") or not prop.has("cp") or Propulsion.is_glow(prop):
			continue # Turbine and glow blade-element laws require their own source oracle.
		var geometry := {}
		for key: String in ["diameter", "offset", "ct", "cp", "rotor_inertia", "cp_min", "axis", "normal_force", "pfactor_moment"]:
			if prop.has(key):
				geometry[key] = prop[key]
		var prepared: Dictionary = _native.prepare_propeller(geometry)
		if not prepared.ok:
			_failures.append("propeller prepare %s: %s" % [id, prepared.error])
			continue
		var local_hub: bool = Propulsion.is_electric(prop)
		for i in _states:
			var input := _aero_inputs(context, context.surfaces)
			var body: PackedFloat64Array = input.s
			var air: Dictionary = Air.compute(body, input.wind, input.rho)
			var explicit_air := PackedFloat64Array()
			if i % 4 == 0:
				explicit_air = PackedFloat64Array([_rng.randf_range(-20.0, 40.0), _rng.randf_range(-9.0, 9.0), _rng.randf_range(-9.0, 9.0)])
				air[Propulsion.STAGE_PROPULSION_AIR_KEY] = explicit_air
			var rpm: float = _rng.randf_range(-30.0, 22000.0)
			if i % 19 == 0:
				rpm = _special()
			elif i % 13 == 0:
				rpm = [0.0, 0.5, 1.0, 1.00001][i % 4]
			var flow: Dictionary = Propulsion.stage_air_velocity(body, air, prop)
			var got: Dictionary = _native.propeller_component(body, air.v_air, input.rho, rpm, local_hub, explicit_air)
			_compare("propeller_flow_validity", PackedFloat64Array([1.0 if flow.ok else 0.0]),
				PackedFloat64Array([1.0 if got.ok else 0.0]), [id, i])
			if not flow.ok or not got.ok:
				continue
			var velocity: PackedFloat64Array = flow.velocity_body
			_compare("propeller_velocity", velocity, got.velocity, [id, i])
			_compare("propeller_thrust_torque", Propulsion.thrust_torque(velocity, rpm, prop, input.rho), got.thrust_torque, [id, i])
			_compare("propeller_loads", Propulsion.loads(velocity, rpm, prop, input.rho), got.loads, [id, i])
			_compare("propeller_rotor", Dynamics.rotor_momentum(loaded.model, rpm), got.rotor_momentum, [id, i])
			_compare("propeller_normal", Propulsion.normal_force(velocity, rpm, prop, input.rho), got.normal_force, [id, i])
			_compare("propeller_pfactor", Propulsion.pfactor_moment(velocity, rpm, prop, input.rho), got.pfactor_moment, [id, i])
			_tally("propeller_" + id, "states")
		var malformed: Dictionary = geometry.duplicate(true)
		malformed.axis = PackedFloat64Array([1.0, 0.0])
		if _native.prepare_propeller(malformed).ok:
			_failures.append("short propeller axis admitted")
		if _native.propeller_component(context.rest, PackedFloat64Array([0.0, 0.0, 0.0]), 1.225, 5000.0,
				false, PackedFloat64Array()).ok:
			_failures.append("failed propeller prepare retained usable stale model")
