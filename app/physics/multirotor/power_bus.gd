# DR-05: signed motor torque with no net pack charging. This is an experimental averaged switching law,
# not a BLHeli implementation. Braking can supply other motors and auxiliaries; surplus uses a torque-preserving
# active-short/coast mixture and becomes effective motor-path resistive loss. No external dump resistor or hidden energy sink.
# Rm is the fitted motor/ESC/wiring lump, reused in every switching state; neither physical winding heat
# nor three-phase RMS current is identified. p_brake_loss_w is already included in p_motor_resistive_w.
# In that mixture, coast is admitted only for effective back-EMF <= bus voltage (a scalar domain proxy).
extends RefCounted

const LAW := "multirotor-damped-nonregenerative-bus-v1"
const BRAKING := "damped_nonregenerative"

static func solve(source_v: float, pack_r: float, auxiliary: float, duty: PackedFloat64Array,
		emf: PackedFloat64Array, resistance: PackedFloat64Array, enabled: PackedInt64Array) -> Dictionary:
	if not is_finite(source_v) or source_v <= 0.0 or not is_finite(pack_r) or pack_r < 0.0 \
			or not is_finite(auxiliary) or auxiliary < 0.0:
		return _failure("battery source, resistance or auxiliary current is outside the electrical domain")
	if duty.size() != 4 or emf.size() != 4 or resistance.size() != 4 or enabled.size() != 4:
		return _failure("four motor inputs are required")
	var draw := auxiliary
	var generation := 0.0
	var conductance := 0.0
	var currents := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		if not is_finite(duty[i]) or duty[i] < 0.0 or duty[i] > 1.0 or not is_finite(emf[i]) \
				or not is_finite(resistance[i]) or resistance[i] <= 0.0 or enabled[i] not in [0, 1]:
			return _failure("motor %d is outside the electrical domain" % i)
		if enabled[i] == 1:
			# Signed back-EMF admits a body-relative reverse shaft; only generating motors use coast below.
			currents[i] = (duty[i] * source_v - emf[i]) / resistance[i]
			var bridge_current: float = duty[i] * currents[i]
			if bridge_current < 0.0:
				generation -= bridge_current
			else:
				draw += bridge_current
			conductance += duty[i] * duty[i] / resistance[i]
	if not is_finite(draw) or not is_finite(generation) or not is_finite(conductance):
		return _failure("motor conductance or aggregate current overflow")
	# Decide and allocate with the same grouped terms: cancellation near zero cannot reverse the branch.
	var limited := generation > draw
	var pack_current := 0.0 if limited else (draw - generation) / (1.0 + pack_r * conductance)
	var voltage := source_v - pack_r * pack_current
	if not is_finite(voltage) or voltage <= 0.0 or not is_finite(pack_current):
		return _failure("battery sag leaves no finite positive bus voltage")
	var fraction := draw / generation if limited else 1.0
	if not limited:
		for i in 4:
			if enabled[i] == 1:
				currents[i] = (duty[i] * voltage - emf[i]) / resistance[i]
	var motor_bus := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var resistive := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var electromagnetic := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var rms := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var brake_heat := 0.0
	for i in 4:
		var current: float = currents[i]
		var bridge_power: float = voltage * duty[i] * current
		var extra_heat := 0.0
		if limited and bridge_power < 0.0:
			# beta=(E-dV)/E: short for beta, open for 1-beta. Mean current remains (dV-E)/R.
			# E>V would permit diode rectification in the open part; do not invent zero-current coast there.
			if emf[i] > voltage:
				return _failure("non-regenerative brake/coast domain: motor %d back-EMF exceeds bus voltage" % i)
			extra_heat = -(1.0 - fraction) * bridge_power
			bridge_power *= fraction
		motor_bus[i] = bridge_power
		resistive[i] = resistance[i] * current * current + extra_heat
		electromagnetic[i] = emf[i] * current
		rms[i] = sqrt(resistive[i] / resistance[i])
		brake_heat += extra_heat # Diagnostic subset of motor-path resistive heat; never count it twice.
		if not is_finite(current) or not is_finite(resistive[i]) or not is_finite(electromagnetic[i]) \
				or not is_finite(motor_bus[i]) or not is_finite(rms[i]):
			return _failure("motor current or power overflow")
	var pack_heat := pack_r * pack_current * pack_current
	var terminal := voltage * pack_current
	var auxiliary_power := voltage * auxiliary
	if not is_finite(pack_heat) or not is_finite(terminal) or not is_finite(brake_heat) or not is_finite(auxiliary_power):
		return _failure("pack or braking power overflow")
	return {ok = true, message = "", v_bus = voltage, i_pack = pack_current, i_motor = currents,
		i_motor_rms = rms, p_motor_bus_w = motor_bus, p_motor_resistive_w = resistive, p_em_w = electromagnetic,
		p_terminal_w = terminal, p_pack_loss_w = pack_heat, p_brake_loss_w = brake_heat,
		p_aux_w = auxiliary_power, regeneration_fraction = fraction, charge_limited = limited}

static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message}
