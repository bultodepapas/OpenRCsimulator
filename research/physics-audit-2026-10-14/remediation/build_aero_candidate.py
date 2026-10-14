"""Construct the reviewable R02 draft outside app; never edit aircraft inputs."""
from pathlib import Path

root = Path(__file__).resolve().parents[3]
src = (root / "app/physics/aero.gd").read_text(encoding="utf-8")
src = src.replace('const WING_STATIONS_PER_SIDE := 3', 'const WING_STATIONS_PER_SIDE := 3\nconst LOADS_LAW := "section-plane-source-weighted-wake-velocity-v2"\nconst WAKE_STATE_UNIT := "m/s (equal-area mean of section Vp*CL)"')
start = src.index('# Local surface loads:')
end = src.index('static func _tail_curve', start)
src = src[:start] + '''## Two-dimensional section loads in the chord/normal plane. No spanwise coefficient
## is inferred from CD90. The unresolved spanwise/body-drag domain stays unvalidated.
static func _surface(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	return _surface_with_flow(M.add(v, M.cross(rates, arm)), arm, area, cl, cd, vertical, rho)


static func _surface_with_flow(flow: PackedFloat64Array, arm: PackedFloat64Array,
		area: float, cl: float, cd: float, vertical: bool, rho: float) -> PackedFloat64Array:
	var normal: float = flow[1 if vertical else 2]
	var plane_speed := M.sqrt_(flow[0]*flow[0] + normal*normal)
	if plane_speed == 0.0:
		return PackedFloat64Array([0., 0., 0., 0., 0., 0.])
	var force_scale := -0.5*rho*plane_speed*area*cd
	var fx: float = flow[0] * force_scale
	var fy: float = normal * force_scale if vertical else 0.0
	var fz: float = 0.0 if vertical else normal * force_scale
	var lift := 0.5*rho*plane_speed*plane_speed*area*cl
	fx += lift*normal/plane_speed
	if vertical:
		fy -= lift*flow[0]/plane_speed
	else:
		fz -= lift*flow[0]/plane_speed
	return PackedFloat64Array([fx, fy, fz, arm[1]*fz-arm[2]*fy,
		arm[2]*fx-arm[0]*fz, arm[0]*fy-arm[1]*fx])


## Reduced downwash closure, not a validated separated-flow circulation model.
## A dimensional source has a unique zero-flow limit, including an actively washed tail.
static func downwash_angle(wake_velocity: float, gain: float, plane_speed: float) -> float:
	return M.atan2_(gain * wake_velocity, plane_speed) if wake_velocity != 0.0 else 0.0


## Common strip kinematics for loads and wake. Only off-diagonal induced sources
## are attenuated: a stagnant or fully separated strip cannot export its undefined
## angle to a loaded neighbour. Uniform attached planar flow retains the old map.
## The max speed is homogeneous; its exact-zero branch needs no epsilon denominator.
static func _wing_flow(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary) -> Dictionary:
	var arm := _arm(model.reference.arp_le, model.cg_le)
	var v: PackedFloat64Array = air.v_air
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var ys: PackedFloat64Array = model.envelope.station_ys
	var twist: PackedFloat64Array = model.surfaces.get("station_incidence", PackedFloat64Array())
	var angles := PackedFloat64Array()
	var speeds := PackedFloat64Array()
	var sources := PackedFloat64Array()
	var reference_speed := 0.0
	for i in ys.size():
		var y: float = arm[1] + ys[i]
		var f0: float = v[0] + (q*arm[2] - r*y)
		var f1: float = v[1] + (r*arm[0] - p*arm[2])
		var f2: float = v[2] + (p*y - q*arm[0])
		var vp := M.sqrt_(f0*f0 + f2*f2)
		var control: float = d.aileron_right if ys[i] > 0.0 else d.aileron_left
		var angle := wrapf(M.atan2_(f2, f0) + float(model.surfaces.wing_aileron_effectiveness)*control, -PI, PI)
		if not twist.is_empty():
			angle = wrapf(angle + twist[i], -PI, PI)
		angles.append(angle)
		speeds.append(vp)
		reference_speed = maxf(reference_speed, M.sqrt_(f0*f0 + f1*f1 + f2*f2))
	for i in ys.size():
		sources.append((speeds[i]/reference_speed) * (1.0-stall_weight(angles[i], model.envelope)) if reference_speed > 0.0 else 0.0)
	return {angles = angles, speeds = speeds, sources = sources}


''' + src[end:]
src = src.replace('## H12: scalar form of the frozen vector oracle in tests/aero_flow_reference.gd. Every product and sum keeps the\n## oracle\'s order (including the + 0.0 arm terms, which turn -0.0 into +0.0); test_aero_flow.gd compares bytes.\n## downwash_cl: E0a2b\'s lagged wing CL for the tail\'s downwash (FlightSession aux); NAN = the instantaneous wing CL.', '## Local section law. H12 parity applies only in its unchanged planar legacy domain.\n## downwash_cl is the historical argument name; v2 carries the dimensional wake driver in m/s.\n## NAN selects the instantaneous source; FlightSession holds the same driver through RK stages.')
# Replace duplicated geometric-angle preparation in both wing evaluators.
for func in ['_local_loads', '_wing_lift_coefficient_with']:
    a = src.index('static func ' + func + '(')
    b = src.index('\n\tvar angles := PackedFloat64Array()', a)
    e = src.index('\n\tvar e_map:', b)
    src = src[:b] + '\n\tvar wing_flow := _wing_flow(s, air, d, model)\n\tvar angles: PackedFloat64Array = wing_flow.angles\n\tvar plane_speeds: PackedFloat64Array = wing_flow.speeds\n\tvar source_weights: PackedFloat64Array = wing_flow.sources' + src[e:]
src = src.replace('mapped += e_map[i * stations + k] * angles[k]', 'mapped += e_map[i * stations + k] * angles[k] * (1.0 if k == i else source_weights[k])')
src = src.replace('wing_cl += cl / stations\n\t\tvar speed', 'wing_cl += (plane_speeds[i] * cl) / stations\n\t\tvar speed', 1)
src = src.replace('var force_scale: float = drag_q*speed*station_area*cd', 'var force_scale: float = drag_q*plane_speed*station_area*cd')
src = src.replace('var fy: float = f1 * force_scale\n\t\tvar fz: float = f2 * force_scale', 'var fy := 0.0\n\t\tvar fz: float = f2 * force_scale', 1)
src = src.replace('if speed < 1e-10:', 'if plane_speeds[i] == 0.0:', 1)
src = src.replace('speed_mps = speed, lift_n = 0.0', 'speed_mps = speed, plane_speed_mps = plane_speeds[i], degenerate_section = true, lift_n = 0.0', 1)
src = src.replace('stall_weight = weight, cl = cl, cd = cd, speed_mps = speed,\n', 'stall_weight = weight, cl = cl, cd = cd, speed_mps = speed,\n\t\t\t\tplane_speed_mps = plane_speed, degenerate_section = false,\n', 1)
src = src.replace('drag_n = -drag_q * speed * speed * station_area * cd', 'drag_n = -drag_q * plane_speed * plane_speed * station_area * cd')
src = src.replace('if plane_speed > 1e-10:', 'if plane_speed > 0.0:')
src = src.replace('and plane_speed > 1e-10:', 'and plane_speed > 0.0:')
# One tail coefficient/force law for the local path and both slipstream evaluations.
a = src.index('\n\tvar tail_limit:', src.index('static func _local_loads('))
e = src.index('\n\treturn PackedFloat64Array([fx_sum', a)
src = src[:a] + '''
	var wake: float = wing_cl if is_nan(downwash_cl) else downwash_cl
	if ge_active:
		wake *= ge[stations + 1]
	for tail_index in 2:
		var vertical := tail_index == 1
		var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
		var arm := _arm(tail.position, cg)
		var flow := M.add(v, M.cross(M.v3(p, q, r), arm))
		var result := _tail_surface_from_flow(flow, arm, d, tail, surfaces, float(tail.area), vertical, rho, wake)
		fx_sum += result[0]
		fy_sum += result[1]
		fz_sum += result[2]
		mx_sum += result[3]
		my_sum += result[4]
		mz_sum += result[5]''' + src[e:]
src = src.replace('M.atan2_(flow[2], flow[0]) - float(tail.downwash_per_cl) * downwash_cl', 'M.atan2_(flow[2], flow[0]) - downwash_angle(downwash_cl, float(tail.downwash_per_cl),\n\t\t\tM.sqrt_(flow[0]*flow[0] + flow[2]*flow[2]))')
# The diagnostic CL remains separate from the dimensional wake state.
src = src.replace('ge: PackedFloat64Array) -> float:\n\tvar ge_active', 'ge: PackedFloat64Array, dimensional := false) -> float:\n\tvar ge_active')
src = src.replace('wing_cl += cl / stations\n\treturn wing_cl', 'wing_cl += (plane_speeds[i] * cl if dimensional else cl) / stations\n\treturn wing_cl')
pos = src.index('\n\nstatic func _wing_lift_coefficient_with(')
src = src[:pos] + '''

## Equal-area mean Vp*CL (m/s) from the force-producing strip law. This is an
## equivalent-lift velocity proxy, not measured circulation in separated flow.
static func wing_wake_velocity(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		ground_up := NAN) -> float:
	return _wing_lift_coefficient_with(s, air, d, model, GroundEffect.factors(s, model, ground_up), true)
''' + src[pos:]
# Global attached coefficients still own the settled reference. A displaced lag adds
# only the difference of bounded downwash angles, exactly zero when settled.
a = src.index('\n\t\tvar cl_free_now:')
e = src.index('\n\t\tco_cl += tail_cl', a)
src = src[:a] + '''
		var wake_free := _wing_lift_coefficient_with(s, air, d, model, PackedFloat64Array(), true)
		var wake_ge := _wing_lift_coefficient_with(s, air, d, model, ge, true)
		var tail_speed := _tail_plane_speed(s, air, model, ge_tail)
		var tail_cl: float = float(ge_tail.free_slope) * float(ge_tail.area) / S * (
			downwash_angle(wake_free, float(ge_tail.downwash_per_cl), tail_speed)
			- downwash_angle(wake_ge * ge[stations+1], float(ge_tail.downwash_per_cl), tail_speed))''' + src[e:]
a = src.index('\n\t\tvar lag_cl: float')
e = src.index('\n\t\tco_cl += lag_cl', a)
src = src[:a] + '''
		var source := _wing_lift_coefficient_with(s, air, d, model, ge, true)
		var scale: float = 1.0 if ge.is_empty() else ge[ge.size()-1]
		var tail_speed := _tail_plane_speed(s, air, model, tail)
		var lag_cl: float = float(tail.free_slope) * float(tail.area) / S * (
			downwash_angle(source * scale, float(tail.downwash_per_cl), tail_speed)
			- downwash_angle(downwash_cl * scale, float(tail.downwash_per_cl), tail_speed))''' + src[e:]
# Selector: high nonuniform rate flow leaves the attached empirical domain before a
# strip stagnates; undefined individual angles can no longer toggle the whole blend.
needle = '\t\tvar angle := wrapf(M.atan2_(flow_z, flow_x) + aileron_effect*da, -PI, PI)'
src = src.replace(needle, '''		var rate_speed := M.sqrt_(M.pow_(q*arm_z-r*station_y, 2) + M.pow_(r*arm_x-p*arm_z, 2) + M.pow_(p*station_y-q*arm_x, 2))
		blend = maxf(blend, _smoothstep((M.atan2_(rate_speed, float(air.V))-limit)/a1_span))
		if blend == 1.0:
			return blend
''' + needle)
a = src.index('\n\t\t\tif not is_nan(downwash_cl)', src.index('static func local_flow_weight('))
e = src.index('\n\t\telse:', a)
src = src[:a] + '''
			var wake: float = downwash_cl
			if is_nan(wake):
				wake = _wing_lift_coefficient_with(s, air, d, model, ge, true)
			var scale: float = ge[ys.size()+1] if not ge.is_empty() else 1.0
			angle = wrapf(M.atan2_(component, flow_x) - downwash_angle(wake * scale,
				float(tail.downwash_per_cl), M.sqrt_(flow_x*flow_x + component*component))
				+ float(tail.elevator_tau)*control + float(tail.free_incidence), -PI, PI)''' + src[e:]
needle = '\t\tvar control: float = -float(d.rudder) if vertical else float(d.elevator)\n\t\tvar angle: float'
src = src.replace(needle, '''		var rate_speed := M.sqrt_(M.pow_(q*tz-r*ty, 2) + M.pow_(r*tx-p*tz, 2) + M.pow_(p*ty-q*tx, 2))
		blend = maxf(blend, _smoothstep((M.atan2_(rate_speed, float(air.V))-limit)/a1_span))
		if blend == 1.0:
			return blend
''' + needle)
pos = src.index('\n\n## The α-dependent part')
src = src[:pos] + '''

static func _tail_plane_speed(s: PackedFloat64Array, air: Dictionary, model: Dictionary, tail: Dictionary) -> float:
	var flow := M.add(air.v_air, M.cross(s.slice(RB.RATE, RB.RATE+3), _arm(tail.position, model.cg_le)))
	return M.sqrt_(flow[0]*flow[0] + flow[2]*flow[2])
''' + src[pos:]
(Path(__file__).parent / 'aero_candidate.gd').write_text(src, encoding='utf-8', newline='\n')
