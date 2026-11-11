# DR-05 (foundation slice): four ESC/motor loads on one battery bus, FPV/03 §5. Each load is the same one-quadrant
# averaged DC equivalent as physics/electric_motor.gd behind an ideal lossless bridge of effective duty d_i:
# I_i = max(0, (d_i·Vbus − E_i)/R_i) when enabled and d_i > 0, else 0; the pack is Voc − Rp·Ipack with a pack-side
# auxiliary current, Ipack = Iaux + Σ d_i·I_i. One shared bus is solved per stage by active-set enumeration.
# Not modeled: regeneration or negative current, ESC loss/current limit/timing, phase inductance or RMS phase current,
# battery polarization, temperature or SOC/OCV lookup (the caller supplies Voc), shaft loss torque (the caller applies
# the motor's Kt·I0 law to I_i), and any hidden state. Back-EMF is an input: E_i = rpm_i / Kv_i [rpm/V], as in
# electric_motor.gd.
extends RefCounted

const LAW := "multirotor-four-load-one-quadrant-bus-v1"
## Candidate active sets in the fixed tie order: fewest active loads first, then lowest bitmask (bit i = load i).
const MASK_ORDER: Array[int] = [0, 1, 2, 4, 8, 3, 5, 6, 9, 10, 12, 7, 11, 13, 14, 15]


## One stage-local solve of the shared bus.
## voc_v: pack open-circuit voltage; r_pack_ohm >= 0; i_aux_a >= 0 pack-side auxiliary current;
## duty: effective bridge duty in [0, 1]; back_emf_v (>= 0); resistance_ohm (> 0); enabled (0/1); four loads each.
## Active set S = {i | enabled and d_i > 0 and d_i·Vbus > E_i}. Equality convention: a load with d_i·Vbus == E_i is
## inactive (current 0). Every one of the 16 candidate sets is tested against its own Vbus in MASK_ORDER and the first
## self-consistent one is returned, so if rounding makes two sets consistent the one with the fewest active loads,
## then the lowest bitmask, wins. Returns {ok, message, v_bus, i_motor, i_pack, active, p_ocv_w, p_pack_loss_w,
## p_terminal_w, p_bridge_w, p_copper_w, p_em_w}; ok = false (with `message`) for non-finite/out-of-domain input
## or when no consistent active set exists.
static func solve(voc_v: float, r_pack_ohm: float, i_aux_a: float, duty: PackedFloat64Array,
		back_emf_v: PackedFloat64Array, resistance_ohm: PackedFloat64Array, enabled: PackedInt64Array) -> Dictionary:
	if not is_finite(voc_v) or voc_v <= 0.0:
		return _failure("voc_v must be finite and > 0")
	if not is_finite(r_pack_ohm) or r_pack_ohm < 0.0:
		return _failure("r_pack_ohm must be finite and >= 0")
	if not is_finite(i_aux_a) or i_aux_a < 0.0:
		return _failure("i_aux_a must be finite and >= 0")
	if duty.size() != 4 or back_emf_v.size() != 4 or resistance_ohm.size() != 4 or enabled.size() != 4:
		return _failure("duty, back_emf_v, resistance_ohm and enabled must hold 4 values")
	var eligible: int = 0
	for i in 4:
		if not is_finite(duty[i]) or duty[i] < 0.0 or duty[i] > 1.0:
			return _failure("duty[%d] must be finite in [0,1]" % i)
		if not is_finite(back_emf_v[i]) or back_emf_v[i] < 0.0:
			return _failure("back_emf_v[%d] must be finite and >= 0" % i)
		if not is_finite(resistance_ohm[i]) or resistance_ohm[i] <= 0.0:
			return _failure("resistance_ohm[%d] must be finite and > 0" % i)
		if enabled[i] != 0 and enabled[i] != 1:
			return _failure("enabled[%d] must be 0 or 1" % i)
		if enabled[i] == 1 and duty[i] > 0.0:
			eligible |= 1 << i
	var bus_without_motors: float = voc_v - r_pack_ohm * i_aux_a
	if not is_finite(bus_without_motors) or bus_without_motors <= 0.0:
		return _failure("auxiliary load leaves no positive feasible bus voltage")

	for mask: int in MASK_ORDER:
		if (mask & ~eligible) != 0:
			continue
		var numerator: float = bus_without_motors
		var denominator: float = 1.0
		for i in 4:
			if (mask & (1 << i)) != 0:
				numerator += r_pack_ohm * duty[i] * back_emf_v[i] / resistance_ohm[i]
				denominator += r_pack_ohm * duty[i] * duty[i] / resistance_ohm[i]
		var v_bus: float = numerator / denominator
		if not is_finite(v_bus) or v_bus <= 0.0:
			continue
		var consistent: bool = true
		for i in 4:
			if (eligible & (1 << i)) == 0:
				continue
			var drives: bool = duty[i] * v_bus > back_emf_v[i]
			if drives != ((mask & (1 << i)) != 0):
				consistent = false
				break
		if consistent:
			return _assemble(voc_v, r_pack_ohm, i_aux_a, v_bus, mask, duty, back_emf_v, resistance_ohm)
	return _failure("no self-consistent active set (rounding at a branch threshold)")


static func _assemble(voc_v: float, r_pack_ohm: float, i_aux_a: float, v_bus: float, mask: int,
		duty: PackedFloat64Array, back_emf_v: PackedFloat64Array, resistance_ohm: PackedFloat64Array) -> Dictionary:
	var i_motor := PackedFloat64Array()
	i_motor.resize(4)
	var active := PackedInt64Array()
	active.resize(4)
	var p_bridge := PackedFloat64Array()
	p_bridge.resize(4)
	var p_copper := PackedFloat64Array()
	p_copper.resize(4)
	var p_em := PackedFloat64Array()
	p_em.resize(4)
	var i_pack: float = i_aux_a
	for i in 4:
		if (mask & (1 << i)) == 0:
			continue
		var current: float = (duty[i] * v_bus - back_emf_v[i]) / resistance_ohm[i]
		i_motor[i] = current
		active[i] = 1
		i_pack += duty[i] * current
		p_bridge[i] = v_bus * duty[i] * current
		p_copper[i] = (resistance_ohm[i] * current) * current
		p_em[i] = back_emf_v[i] * current
		if not is_finite(current) or current <= 0.0 or not is_finite(p_bridge[i]) or not is_finite(p_copper[i]) \
				or not is_finite(p_em[i]):
			return _failure("load %d current or power is not finite and positive" % i)
	var p_ocv: float = voc_v * i_pack
	var p_pack_loss: float = (r_pack_ohm * i_pack) * i_pack
	var p_terminal: float = v_bus * i_pack
	if not is_finite(i_pack) or not is_finite(p_ocv) or not is_finite(p_pack_loss) or not is_finite(p_terminal):
		return _failure("pack current or power overflowed")
	return {
		ok = true,
		message = "",
		v_bus = v_bus,
		i_motor = i_motor,
		i_pack = i_pack,
		active = active,
		p_ocv_w = p_ocv,
		p_pack_loss_w = p_pack_loss,
		p_terminal_w = p_terminal,
		p_bridge_w = p_bridge,
		p_copper_w = p_copper,
		p_em_w = p_em,
	}


static func _failure(message: String) -> Dictionary:
	return {ok = false, message = message}
