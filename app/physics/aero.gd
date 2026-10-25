# Float64 aerodynamic loads about CG [Fx,Fy,Fz,Mx,My,Mz], gravity excluded.
# The corrected empirical model remains the exact small-angle oracle. Outside its local-flow
# validity region, loads blend to local wing/tail elements plus declared body terms: flow = v + omega cross r,
# section lift perpendicular to its plane flow, drag against that flow, moment = r cross F. No independently scaled
# stall deficits or residual damping moments. The tail replaces global derivatives, never adds them.
# Parameters/provenance: aero.surfaces in aircraft JSON. See docs/research/flight-repair-implementation.md.
# coefficients() describes the reference empirical curve, not summed nonlinear surface loads.
# No propwash or dynamic stall memory. M5-GE-1: an opt-in aero.ground_effect module (physics/ground_effect.gd)
# scales the strips' induced angle/drag and the tail's downwash by their height above the ground the caller supplies.
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const WingPolar := preload("res://physics/wing_polar.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
const Flaps := preload("res://physics/flaps.gd")

## Equal-area elements per wing side (numerical resolution, not an aircraft parameter).
const WING_STATIONS_PER_SIDE := 3
const LOADS_LAW := "section-plane-source-weighted-wake-velocity-v2"
const WAKE_STATE_UNIT := "m/s (equal-area mean of section Vp*CL)"
## Experimental unwashed ambient-gradient bridge; not a saved weather or aircraft law.
const SPATIAL_LOADS_LAW := "matched-unwashed-station-delta-v1"
## Provisional eligibility limits, not clamps or calibrated RC turbulence parameters.
const SPATIAL_MAX_ANGLE_RAD := 3.0 * PI / 180.0
const SPATIAL_MAX_PRESSURE_FRACTION := 0.25


## Our pilot-side surface angles (degrees, trailing edge UP for ailerons/elevator, RIGHT for rudder,
## as in input/commands.gd surface_deflections_deg) → the data's conventions (radians, +TE down / +TE left).
## The only place where the two sign conventions meet.
static func deflections_from_surfaces(surfaces_deg: Dictionary) -> Dictionary:
	return ControlSurfaces.deflections_from_surfaces(surfaces_deg)


## Stall blend weight at angle of attack α (rad): 0 in attached flow, 1 in separated (flat-plate) flow.
## env: { a1, a2 (positive stall start/end), n1, n2 (negative, magnitudes), b1, b2 (sideslip), CD90 }; {} = linear.
static func stall_weight(alpha: float, env: Dictionary) -> float:
	if env.is_empty():
		return 0.0
	if alpha >= 0.0:
		return _smoothstep((alpha - env.a1) / (env.a2 - env.a1))
	return _smoothstep((-alpha - env.n1) / (env.n2 - env.n1))


static func sideslip_weight(beta: float, env: Dictionary) -> float:
	return 0.0 if env.is_empty() else _smoothstep((absf(beta) - env.b1) / (env.b2 - env.b1))


static func _smoothstep(x: float) -> float:
	if x <= 0.0:
		return 0.0
	if x >= 1.0:
		return 1.0
	return x * x * (3.0 - 2.0 * x)


static func _tail_plane_speed(s: PackedFloat64Array, air: Dictionary, model: Dictionary, tail: Dictionary) -> float:
	var flow := M.add(air.v_air, M.cross(s.slice(RB.RATE, RB.RATE+3), _arm(tail.position, model.cg_le)))
	return M.sqrt_(flow[0]*flow[0] + flow[2]*flow[2])


## The α-dependent part of the lift coefficient (no control terms), attached → flat plate.
static func lift_alpha(alpha: float, a: Dictionary, env: Dictionary) -> float:
	var base: float = a.CL0 + a.CLa * alpha
	var w := stall_weight(alpha, env)
	return base if w == 0.0 else (1.0 - w) * base + w * 0.5 * float(env.CD90) * M.sin_(2.0 * alpha)


## Nondimensional coefficients for the given air data, body rates (rad/s) and deflections (data conventions).
## Rate damping is dimensionalized separately in _global_loads to avoid division by zero.
## This reference curve is not a force/power diagnostic for the local model.
static func coefficients(air: Dictionary, rates: PackedFloat64Array, d: Dictionary, a: Dictionary, env := {}) -> Dictionary:
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var w := stall_weight(alpha, env)
	var wb := sideslip_weight(beta, env)
	var sb := beta if wb == 0.0 else (1.0 - wb) * beta + wb * M.sin_(beta) # effective sideslip for the β terms
	var cl_controls: float = a.CLde * de + a.CLda_each * (dar + dal)
	var cl: float = a.CL0 + a.CLa * alpha + cl_controls
	var cd_aero: float = a.CD0 + a.k_induced * M.pow_(cl - a.CL_minD, 2)
	if not env.is_empty():
		cl = lift_alpha(alpha, a, env) + cl_controls
		cd_aero = (1.0 - w) * cd_aero + w * (a.CD0 + env.CD90 * M.sin_(alpha) * M.sin_(alpha))
	var cd: float = cd_aero + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	var cm_alpha: float = a.Cm0 + a.Cma * alpha
	if w != 0.0:
		cm_alpha = (1.0 - w) * cm_alpha + w * (a.Cm0 + a.Cma * M.sin_(alpha))
	var cl_total: float = a.Clb * sb + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr
	var cn_total: float = a.Cnb * sb + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr
	return {
		CL = cl, CD = cd,
		CY = a.CYb * sb + a.CYdr * dr,
		Cl = cl_total,
		Cm = cm_alpha + a.Cmde * de + a.Cmda_each * (dar + dal),
		Cn = cn_total,
	}


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz], gravity excluded.
## model: AircraftData model (reference S, b, c, arp_le; cg_le; aero).
static func _global_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float,
		downwash_cl := NAN, ge := PackedFloat64Array()) -> PackedFloat64Array:
	var ref: Dictionary = model.reference
	var a: Dictionary = model.aero
	var S: float = ref.S
	var b: float = ref.b
	var c: float = ref.c
	var qbar: float = air.qbar
	var p := s[RB.RATE]
	var q := s[RB.RATE + 1]
	var r := s[RB.RATE + 2]
	# H15: coefficients() inlined in its own operation order (no Dictionary result); see
	# tests/attached_flow_reference.gd. coefficients() stays the public reference curve for trim and linearization.
	var env: Dictionary = model.get("envelope", {})
	var alpha: float = air.alpha
	var beta: float = air.beta
	var de: float = d.elevator
	var dar: float = d.aileron_right
	var dal: float = d.aileron_left
	var dr: float = d.rudder
	var w := stall_weight(alpha, env)
	var wb := sideslip_weight(beta, env)
	var beta_eff := beta if wb == 0.0 else (1.0 - wb) * beta + wb * M.sin_(beta)
	var cl_controls: float = a.CLde * de + a.CLda_each * (dar + dal)
	var cl0: float = a.CL0
	var cla: float = a.CLa
	var cd0: float = a.CD0
	var co_cl: float = cl0 + cla * alpha + cl_controls
	var cd_aero: float = cd0 + a.k_induced * M.pow_(co_cl - a.CL_minD, 2)
	if not env.is_empty():
		var base: float = cl0 + cla * alpha
		var cd90: float = env.CD90
		co_cl = (base if w == 0.0 else (1.0 - w) * base + w * 0.5 * cd90 * M.sin_(2.0 * alpha)) + cl_controls
		var sin_alpha := M.sin_(alpha)
		cd_aero = (1.0 - w) * cd_aero + w * (cd0 + cd90 * sin_alpha * sin_alpha)
	var co_cd: float = cd_aero + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
	var cm0: float = a.Cm0
	var cma: float = a.Cma
	var cm_alpha: float = cm0 + cma * alpha
	if w != 0.0:
		cm_alpha = (1.0 - w) * cm_alpha + w * (cm0 + cma * M.sin_(alpha))
	var co_cy: float = a.CYb * beta_eff + a.CYdr * dr
	var co_roll: float = a.Clb * beta_eff + a.Clda_right * dar + a.Clda_left * dal + a.Cldr * dr
	var co_pitch: float = cm_alpha + a.Cmde * de + a.Cmda_each * (dar + dal)
	var co_yaw: float = a.Cnb * beta_eff + a.Cnda_right * dar + a.Cnda_left * dal + a.Cndr * dr
	if not ge.is_empty():
		# M5-GE-1: ground effect in the oracle (GroundEffect.factors: σ per strip, mean σ, σ_ε). At uniform α strip i's
		# induced angle is a0·(α + α_s)·(1 − Σ_k E_ik); the image system frees (1 − σ_i) of it: more attached lift at the
		# same α and a roll moment when one wing is lower. Induced drag at the same CL scales by the mean σ. The tail's
		# static free-air downwash k_ε·CL_free becomes k_ε·σ_ε·CL_ge: a free-slope increment at the tail's arm, as the
		# D11g lag term below. The local strips apply the same law; test_ground_effect.gd pins the two regimes together.
		var ys: PackedFloat64Array = env.station_ys
		var stations := ys.size()
		var a0: float = env.strip_slope
		var alpha_zero: float = env.strip_alpha_zero
		var row_sum: PackedFloat64Array = env.strip_row_sum
		var attached: float = 1.0 - w
		var wing_gain := 0.0
		var roll_gain := 0.0
		for i in stations:
			var dcl: float = a0 * (alpha + alpha_zero) * (1.0 - ge[i]) * (1.0 - row_sum[i])
			wing_gain += dcl / stations
			roll_gain -= dcl * ys[i] / stations / b
		co_cl += attached * wing_gain
		co_roll += attached * roll_gain
		var cd_ge: float = cd0 + ge[stations] * a.k_induced * M.pow_(co_cl - a.CL_minD, 2)
		if w != 0.0:
			var sin_ge := M.sin_(alpha)
			cd_ge = (1.0 - w) * cd_ge + w * (cd0 + float(env.CD90) * sin_ge * sin_ge)
		co_cd = cd_ge + absf(a.CDda_each * dar) + absf(a.CDda_each * dal) + absf(a.CDdr * dr) + absf(a.CDde * de)
		# The oracle's static tail sees the free-air downwash k_ε·CL_free(now); the ground leaves k_ε·σ_ε·CL_ge(now), so the
		# tail's angle grows by k_ε·(CL_free − σ_ε·CL_ge) on the free slope. The strips' tail law gives the same difference.
		var ge_tail: Dictionary = model.surfaces.horizontal
		var wake_free := _wing_lift_coefficient_with(s, air, d, model, PackedFloat64Array(), true)
		var wake_ge := _wing_lift_coefficient_with(s, air, d, model, ge, true)
		var tail_speed := _tail_plane_speed(s, air, model, ge_tail)
		var tail_cl: float = float(ge_tail.free_slope) * float(ge_tail.area) / S * (
			downwash_angle(wake_free, float(ge_tail.downwash_per_cl), tail_speed)
			- downwash_angle(wake_ge * ge[stations+1], float(ge_tail.downwash_per_cl), tail_speed))
		co_cl += tail_cl
		co_pitch -= tail_cl * (float(ge_tail.position[0]) - float(ref.arp_le[0])) / c
	if not is_nan(downwash_cl):
		# D11g: the tail's downwash lag (E0a2b) in the oracle. Its static coefficients hold the settled downwash; a lagged
		# wing CL turns the tail's angle by k_ε·(CL_wing − lag) on the free slope, at the tail's arm: the oracle's CLα̇ and
		# Cmα̇, the same as the local tail's. Zero once settled; NAN (trim, static solves) adds nothing.
		# M5-GE-1: in ground effect the lag acts on the reduced downwash, k_ε·σ_ε·(CL_ge − lag), as in the strips' tail.
		var tail: Dictionary = model.surfaces.horizontal
		var source := _wing_lift_coefficient_with(s, air, d, model, ge, true)
		var scale: float = 1.0 if ge.is_empty() else ge[ge.size()-1]
		var tail_speed := _tail_plane_speed(s, air, model, tail)
		var lag_cl: float = float(tail.free_slope) * float(tail.area) / S * (
			downwash_angle(source * scale, float(tail.downwash_per_cl), tail_speed)
			- downwash_angle(downwash_cl * scale, float(tail.downwash_per_cl), tail_speed))
		co_cl += lag_cl
		co_pitch -= lag_cl * (float(tail.position[0]) - float(ref.arp_le[0])) / c

	# Rate (damping) terms in dimensional form: qbar·x̂ = ½ρV²·(rate·L/2V) = ¼ρ·V·rate·L. Finite as V → 0.
	var k := 0.25 * rho * float(air.V)
	var cl_rate: float = k * c * a.CLq * q # = qbar·CLq·q̂
	var cy_rate: float = k * b * (a.CYp * p + a.CYr * r)
	var roll_rate: float = k * b * (a.Clp * p + a.Clr * r)
	var pitch_rate: float = k * c * a.Cmq * q
	var yaw_rate: float = k * b * (a.Cnp * p + a.Cnr * r)

	var lift: float = (qbar * co_cl + cl_rate) * S
	var drag: float = qbar * co_cd * S
	var side: float = (qbar * co_cy + cy_rate) * S

	# Wind axes → body axes. Wind-axis force = [-D, Y, -L].
	var ca := M.cos_(alpha)
	var sa := M.sin_(alpha)
	var cb := M.cos_(beta)
	var sb := M.sin_(beta)
	var fx: float = ca * cb * (-drag) - ca * sb * side + sa * lift
	var fy: float = sb * (-drag) + cb * side
	var fz: float = sa * cb * (-drag) - sa * sb * side - ca * lift

	# Moments about the aero reference point, then transferred to the CG: M_cg = M_arp + r × F, r = arp − cg (body).
	var mx: float = (qbar * co_roll + roll_rate) * S * b
	var my: float = (qbar * co_pitch + pitch_rate) * S * c
	var mz: float = (qbar * co_yaw + yaw_rate) * S * b
	var arp: PackedFloat64Array = ref.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var rx: float = -(arp[0] - cg[0]) # le frame → body FRD
	var ry: float = arp[1] - cg[1]
	var rz: float = -(arp[2] - cg[2])
	return PackedFloat64Array([fx, fy, fz, mx + (ry * fz - rz * fy), my + (rz * fx - rx * fz), mz + (rx * fy - ry * fx)])


## Two-dimensional section loads in the chord/normal plane. No spanwise coefficient
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
static func _wing_flow(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		station_delta_body := PackedFloat64Array()) -> Dictionary:
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
	var flap_shifts := PackedFloat64Array()
	var flap_model: Dictionary = model.get("flaps", {})
	var flap_angle: float = float(d.get("flap", 0.0))
	var flap_active := Flaps.enabled(model) and flap_angle != 0.0 and float(flap_model.get("aerodynamic_gain", 1.0)) != 0.0
	var flap_coverage: PackedFloat64Array = flap_model.get("station_coverage", PackedFloat64Array())
	var reference_speed := 0.0
	for i in ys.size():
		var y: float = arm[1] + ys[i]
		var f0: float = v[0] + (q*arm[2] - r*y)
		var f1: float = v[1] + (r*arm[0] - p*arm[2])
		var f2: float = v[2] + (p*y - q*arm[0])
		if not station_delta_body.is_empty():
			f0 += station_delta_body[3*i]
			f1 += station_delta_body[3*i+1]
			f2 += station_delta_body[3*i+2]
		var vp := M.sqrt_(f0*f0 + f2*f2)
		var control: float = d.aileron_right if ys[i] > 0.0 else d.aileron_left
		var angle := wrapf(M.atan2_(f2, f0) + float(model.surfaces.wing_aileron_effectiveness)*control, -PI, PI)
		if not twist.is_empty():
			angle = wrapf(angle + twist[i], -PI, PI)
		var flap_shift := 0.0
		if flap_active and i < flap_coverage.size():
			# A plain flap changes section camber only while air flows over the wing's forward-facing plane.
			# Thin-airfoil effectiveness is smoothly limited beyond small deflections before area coverage is applied.
			# The strip stall/polar and induced-flow laws see this shift; reverse flow sees none.
			var limit := deg_to_rad(float(flap_model.effective_angle_limit_deg))
			var raw_shift := flap_angle * float(flap_model.lift_effectiveness)
			var bounded_shift := limit * M.tanh_(raw_shift / limit)
			flap_shift = bounded_shift * flap_coverage[i] * float(flap_model.aerodynamic_gain) * maxf(M.cos_(angle), 0.0)
			angle = wrapf(angle + flap_shift, -PI, PI)
		angles.append(angle)
		speeds.append(vp)
		flap_shifts.append(flap_shift)
		reference_speed = maxf(reference_speed, M.sqrt_(f0*f0 + f1*f1 + f2*f2))
	# P51-11a (optional flaps.stall_shift_fraction): a flapped strip's stall onset moves by only this fraction of its
	# camber shift; absent keeps the whole shift without any added arithmetic.
	var stall_back := 1.0 - float(flap_model.stall_shift_fraction) if flap_active and flap_model.has("stall_shift_fraction") else 0.0
	for i in ys.size():
		var source_angle: float = angles[i] if stall_back == 0.0 else angles[i] - stall_back * flap_shifts[i]
		sources.append((speeds[i]/reference_speed) * (1.0-stall_weight(source_angle, model.envelope)) if reference_speed > 0.0 else 0.0)
	return {angles = angles, speeds = speeds, sources = sources, flap_shifts = flap_shifts, reference_speed = reference_speed}


static func _tail_curve(alpha: float, slope: float, surfaces: Dictionary) -> float:
	# Continuous periodic flat-plate blend. No raw alpha survives the reverse-flow seam.
	var blend := _smoothstep((absf(alpha) - surfaces.tail_local_limit)/(surfaces.tail_stall_end - surfaces.tail_local_limit))
	return (1.0 - blend)*slope*alpha + blend*0.5*float(surfaces.tail_CD90)*M.sin_(2.0*alpha)


## Existing local section law evaluated at a clean reference angle. Flap moments use this independent
## coefficient difference so the pressure increment and its application point stay consistent.
static func _section_coefficients(alpha: float, base: float, env: Dictionary, polar: Dictionary,
		cd0: float, cd90: float, k_induced: float, cl_min_d: float, induced_scale: float) -> PackedFloat64Array:
	var a1: float = env.a1
	var a_span: float = env.a2 - env.a1
	var n1: float = env.n1
	var n_span: float = env.n2 - env.n1
	var weight := _smoothstep((alpha - a1) / a_span) if alpha >= 0.0 \
		else _smoothstep((-alpha - n1) / n_span)
	var cl: float
	var cd: float
	if not polar.is_empty():
		var sample := WingPolar.evaluate(alpha, base, polar)
		cl = sample[0]
		weight = 1.0 - sample[2]
		cd = sample[1] + sample[2] * induced_scale * k_induced * M.pow_(cl - cl_min_d, 2)
	else:
		cl = base if weight == 0.0 else (1.0 - weight) * base + weight * 0.5 * cd90 * M.sin_(2.0 * alpha)
		cd = cd0 + (1.0-weight)*induced_scale*k_induced*M.pow_(cl-cl_min_d, 2) + weight*cd90*M.pow_(M.sin_(alpha), 2)
	return PackedFloat64Array([cl, cd, weight])


## Local section law. H12 parity applies only in its unchanged planar legacy domain.
## downwash_cl is the historical argument name; v2 carries the dimensional wake driver in m/s.
## NAN selects the instantaneous source; FlightSession holds the same driver through RK stages.
static func _local_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float,
		downwash_cl := NAN, strip_diagnostics: Variant = null, ge := PackedFloat64Array(),
		station_delta_body := PackedFloat64Array(), include_body := true) -> PackedFloat64Array:
	var ge_active := not ge.is_empty() # M5-GE-1: σ per strip (station order), then mean σ and the tail's σ_ε
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var v: PackedFloat64Array = air.v_air
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var a: Dictionary = model.aero
	var env: Dictionary = model.envelope
	var ref: Dictionary = model.reference
	var surfaces: Dictionary = model.surfaces
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = ref.arp_le
	var ax: float = -(arp[0]-cg[0]) + 0.0
	var ay: float = arp[1]-cg[1]
	var az: float = -(arp[2]-cg[2]) + 0.0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var has_twist := not twist.is_empty()
	var ys: PackedFloat64Array = env.station_ys
	var stations := ys.size()
	var station_area: float = ref.S / stations
	var aileron_effect: float = surfaces.wing_aileron_effectiveness
	var da_right: float = d.aileron_right
	var da_left: float = d.aileron_left
	var cl0: float = a.CL0
	var cla: float = a.CLa
	var cd0: float = a.CD0
	var k_induced: float = a.k_induced
	var cl_min_d: float = a.CL_minD
	var cd90: float = env.CD90
	var a1: float = env.a1
	var a_span: float = env.a2 - env.a1
	var n1: float = env.n1
	var n_span: float = env.n2 - env.n1
	var lift_q := 0.5*rho
	var drag_q := -0.5*rho
	var fx_sum := 0.0
	var fy_sum := 0.0
	var fz_sum := 0.0
	var mx_sum := 0.0
	var my_sum := 0.0
	var mz_sum := 0.0
	var wing_cl := 0.0 # Historical local name: dimensional mean Vp*CL, m/s.
	# D11d: geometric strip angles first, then the induced-flow map (AircraftData._induced_map) couples them.
	var wing_flow := _wing_flow(s, air, d, model, station_delta_body)
	var angles: PackedFloat64Array = wing_flow.angles
	var plane_speeds: PackedFloat64Array = wing_flow.speeds
	var source_weights: PackedFloat64Array = wing_flow.sources
	var e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())
	var flap_shifts: PackedFloat64Array = wing_flow.flap_shifts
	var flap_model: Dictionary = model.get("flaps", {})
	var flap_angle: float = float(d.get("flap", 0.0))
	var flap_active := Flaps.enabled(model) and flap_angle != 0.0 and float(flap_model.get("aerodynamic_gain", 1.0)) != 0.0
	var stall_back := 1.0 - float(flap_model.stall_shift_fraction) if flap_active and flap_model.has("stall_shift_fraction") else 0.0
	var flap_coverage: PackedFloat64Array = flap_model.get("station_coverage", PackedFloat64Array())
	var reference_speed: float = float(wing_flow.reference_speed)
	var coupled := e_map.size() == stations * stations
	var strip_slope: float = env.get("strip_slope", cla)
	var strip_cl0: PackedFloat64Array = env.get("strip_cl0", PackedFloat64Array())
	var flap_chords: PackedFloat64Array = env.get("station_chords", PackedFloat64Array())
	var polar: Dictionary = env.get("wing_polar", {})
	# D8b-R2d (optional): spanwise stall progression; strip i reads the table at its angle times strip_factor[i].
	var strip_factor: PackedFloat64Array = polar.get("strip_factor", PackedFloat64Array())
	# D11j: the section's pitching moment about its aerodynamic centre as a pure couple per strip (q_i·S_i·c_i·Cm_ac);
	# 0 (absent) adds no arithmetic, so aircraft without it stay byte-identical to the frozen oracle.
	var cm_ac: float = surfaces.get("wing_cm_ac", 0.0)
	var station_chords: PackedFloat64Array = env.get("station_chords", PackedFloat64Array()) if cm_ac != 0.0 else PackedFloat64Array()
	for i in stations:
		var y: float = ys[i]
		var arm_y: float = ay + y
		var f0: float = v0 + (q*az - r*arm_y)
		var f1: float = v1 + (r*ax - p*az)
		var f2: float = v2 + (p*arm_y - q*ax)
		if not station_delta_body.is_empty():
			f0 += station_delta_body[3*i]
			f1 += station_delta_body[3*i+1]
			f2 += station_delta_body[3*i+2]
		var effective: float = angles[i]
		# Stall and the flat plate follow the geometric angle; attached lift uses the induced (effective) angles.
		var stall_angle: float = effective if stall_back == 0.0 else effective - stall_back * flap_shifts[i]
		var weight := _smoothstep((stall_angle - a1) / a_span) if stall_angle >= 0.0 \
			else _smoothstep((-stall_angle - n1) / n_span)
		var base: float
		if coupled:
			var mapped := 0.0
			for k in stations:
				mapped += e_map[i * stations + k] * angles[k] * (1.0 if k == i else source_weights[k])
			base = strip_cl0[i] + strip_slope * mapped
		else:
			base = cl0 + cla * effective
		var cl: float
		var cd: float
		if ge_active:
			# Ground effect frees (1 − σ_i) of the strip's induced angle a0·(α_i + α_s) − base/a0 and scales its
			# induced drag at the same CL by σ_i; the flat-plate (separated) share is unchanged.
			base += (1.0 - ge[i]) * (strip_slope * (effective + float(env.strip_alpha_zero)) - base)
			cl = base if weight == 0.0 else (1.0 - weight) * base + weight * 0.5 * cd90 * M.sin_(2.0 * effective)
			cd = cd0 + (1.0-weight)*ge[i]*k_induced*M.pow_(cl-cl_min_d, 2) + weight*cd90*M.pow_(M.sin_(effective), 2)
			if not polar.is_empty():
				var sample := WingPolar.evaluate(effective if strip_factor.is_empty() else effective * strip_factor[i], base, polar)
				cl = sample[0]
				weight = 1.0-sample[2]
				cd = sample[1] + sample[2]*ge[i]*k_induced*M.pow_(cl-cl_min_d, 2)
		else:
			cl = base if weight == 0.0 else (1.0 - weight) * base + weight * 0.5 * cd90 * M.sin_(2.0 * effective)
			cd = cd0 + (1.0-weight)*k_induced*M.pow_(cl-cl_min_d, 2) + weight*cd90*M.pow_(M.sin_(effective), 2)
			if not polar.is_empty():
				var sample := WingPolar.evaluate(effective if strip_factor.is_empty() else effective * strip_factor[i], base, polar)
				cl = sample[0]
				weight = 1.0-sample[2]
				cd = sample[1] + sample[2]*k_induced*M.pow_(cl-cl_min_d, 2)
		var flap_lift_delta := 0.0
		var flap_profile_drag := 0.0
		var flap_delta_cl := 0.0
		if flap_active and i < flap_shifts.size() and i < flap_coverage.size() and flap_shifts[i] != 0.0:
			# Increase the separated positive lift plateau with flap camber. The smooth stall blend
			# retains this bounded gain past stall, while cos(alpha) removes it at edge-on/reverse flow.
			# `weight` is separation for both laws: the tabulated polar's attached fraction
			# is converted to 1 - attached immediately above.
			flap_lift_delta = strip_slope * flap_shifts[i] * weight * maxf(M.cos_(effective), 0.0)
			var pre_extension_cl: float = cl
			cl += flap_lift_delta
			var induced_factor: float = ge[i] if ge_active else 1.0
			# The post-stall extension is added after the clean polar/plate blend; carry its
			# incremental induced cost through the same separation fraction and GE factor.
			var induced_cl_delta: float = M.pow_(cl - cl_min_d, 2) - M.pow_(pre_extension_cl - cl_min_d, 2)
			cd += maxf(induced_cl_delta, 0.0) * (1.0 - weight) * induced_factor * k_induced
			# Hinge/pressure drag estimate, quadratic with deflection and absent at zero.
			# The coefficient is normalized to covered wing-strip reference area, not panel surface area.
			flap_profile_drag = float(flap_model.profile_drag_coefficient) * flap_coverage[i] * float(flap_model.aerodynamic_gain) \
				* M.pow_(M.sin_(flap_angle), 2) * maxf(M.cos_(effective), 0.0)
			cd += flap_profile_drag
			# Independently evaluate the same strip with flap camber removed so pitch
			# follows the actual nonlinear ΔCL after coupling, stall, and separation.
			var clean_effective: float = effective - flap_shifts[i]
			var clean_base: float
			if coupled:
				var clean_mapped := 0.0
				for k in stations:
					var clean_angle_k: float = angles[k] - flap_shifts[k]
					var clean_weight_k := _smoothstep((clean_angle_k - a1) / a_span) if clean_angle_k >= 0.0 \
						else _smoothstep((-clean_angle_k - n1) / n_span)
					var clean_source_k: float = (plane_speeds[k] / reference_speed) * (1.0 - clean_weight_k) if reference_speed > 0.0 else 0.0
					clean_mapped += e_map[i * stations + k] * clean_angle_k * (1.0 if k == i else clean_source_k)
				clean_base = strip_cl0[i] + strip_slope * clean_mapped
			else:
				clean_base = cl0 + cla * clean_effective
			if ge_active:
				clean_base += (1.0 - ge[i]) * (strip_slope * (clean_effective + float(env.strip_alpha_zero)) - clean_base)
			var clean_coeff := _section_coefficients(clean_effective if strip_factor.is_empty() else clean_effective * strip_factor[i],
				clean_base, env, polar, cd0, cd90,
				k_induced, cl_min_d, induced_factor)
			flap_delta_cl = cl - clean_coeff[0]
		wing_cl += (plane_speeds[i] * cl) / stations
		var speed := M.sqrt_(f0 * f0 + f1 * f1 + f2 * f2)
		if plane_speeds[i] == 0.0:
			if strip_diagnostics != null:
				strip_diagnostics.append({y_m = y, alpha_geometric_rad = effective,
					alpha_effective_rad = (base - strip_cl0[i]) / strip_slope if coupled else effective,
					stall_weight = weight, cl = cl, cd = cd, speed_mps = speed, plane_speed_mps = plane_speeds[i], degenerate_section = true, pressure_convention = "section-plane",
					lift_velocity_mps = 0.0, section_pitch_couple_nm = 0.0, lift_n = 0.0, drag_n = 0.0,
					force_body_n = PackedFloat64Array([0., 0., 0.]), moment_body_nm = PackedFloat64Array([0., 0., 0.])})
			continue # the oracle adds +0.0, which never changes a sum that starts at +0.0
		var plane_speed := M.sqrt_(f0*f0 + f2*f2)
		var force_scale: float = drag_q*plane_speed*station_area*cd
		var fx: float = f0 * force_scale
		var fy := 0.0
		var fz: float = f2 * force_scale
		if plane_speed > 0.0:
			var lift: float = lift_q*plane_speed*plane_speed*station_area*cl
			fx += lift*f2/plane_speed
			fz -= lift*f0/plane_speed
		fx_sum += fx
		fy_sum += fy
		fz_sum += fz
		mx_sum += arm_y * fz - az * fy
		my_sum += az * fx - ax * fz
		mz_sum += ax * fy - arm_y * fx
		var section_my := 0.0
		if cm_ac != 0.0 and plane_speed > 0.0:
			section_my = lift_q * plane_speed * plane_speed * station_area * station_chords[i] * cm_ac
			my_sum += section_my
		if flap_active and plane_speed > 0.0 and i < flap_shifts.size() and flap_shifts[i] != 0.0:
			# Thin-airfoil theory treats flap lift increment as a pressure change over
			# the section, not as whole-wing Δlift acting at the aft panel. Apply the
			# Glauert quarter-chord ΔCm/ΔCL to actual nonlinear ΔCL as a pure couple.
			var chord_i: float = flap_chords[i] if i < flap_chords.size() else float(ref.c)
			var lift_q_area: float = lift_q * plane_speed * plane_speed * station_area
			var flap_couple: float = lift_q_area * chord_i * flap_delta_cl * float(flap_model.thin_airfoil_moment_per_cl)
			# P51-11a (optional): camber lift acts at the wing section's own quarter chord, this far aft of the strip force
			# point (the wing-body ARP); absent = no added term.
			if flap_model.has("lift_reference_offset_m"):
				flap_couple -= lift_q_area * flap_delta_cl * float(flap_model.lift_reference_offset_m)
			# Estimated incremental profile/hinge drag acts at the panel centre;
			# account for its chordwise and deflected-z arms separately.
			var flap_center := float(flap_model.hinge_fraction) + 0.5 * float(flap_model.chord_fraction) * M.cos_(flap_angle)
			var arm_x := -(flap_center - 0.25) * chord_i
			var arm_z := 0.5 * float(flap_model.chord_fraction) * chord_i * M.sin_(flap_angle)
			var profile_drag_scale: float = drag_q * plane_speed * station_area * flap_profile_drag
			var profile_drag_fx := f0 * profile_drag_scale
			var profile_drag_fz := f2 * profile_drag_scale
			flap_couple += arm_z * profile_drag_fx - arm_x * profile_drag_fz
			section_my += flap_couple
			my_sum += flap_couple
		if strip_diagnostics != null:
			strip_diagnostics.append({y_m = y, alpha_geometric_rad = effective,
				alpha_effective_rad = (base - strip_cl0[i]) / strip_slope if coupled else effective,
				stall_weight = weight, cl = cl, cd = cd, speed_mps = speed,
				plane_speed_mps = plane_speed, degenerate_section = false,
				pressure_convention = "section-plane", lift_velocity_mps = plane_speed*cl, section_pitch_couple_nm = section_my,
				lift_n = lift_q * plane_speed * plane_speed * station_area * cl,
				drag_n = -drag_q * plane_speed * plane_speed * station_area * cd,
				force_body_n = PackedFloat64Array([fx, fy, fz]),
				moment_body_nm = PackedFloat64Array([arm_y * fz - az * fy, az * fx - ax * fz + section_my, ax * fy - arm_y * fx])})
	var wake: float = wing_cl if is_nan(downwash_cl) else downwash_cl
	if ge_active:
		wake *= ge[stations + 1]
	for tail_index in 2:
		var vertical := tail_index == 1
		var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
		var arm := _arm(tail.position, cg)
		var flow := M.add(v, M.cross(M.v3(p, q, r), arm))
		if not station_delta_body.is_empty():
			for axis in 3:
				flow[axis] += station_delta_body[3*(stations+tail_index)+axis]
		var result := _tail_surface_from_flow(flow, arm, d, tail, surfaces, float(tail.area), vertical, rho, wake)
		fx_sum += result[0]
		fy_sum += result[1]
		fz_sum += result[2]
		mx_sum += result[3]
		my_sum += result[4]
		mz_sum += result[5]
	if not include_body:
		return PackedFloat64Array([fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum])
	# P51-25 (optional): the fuselage's destabilizing yaw as a Munk-type pure couple ½ρ·S·b·Cnβ_B·u·v (body-axis air
	# velocity). Linear in β at small angles, where the oracle's Cnb carries the same term; zero at zero flow and broadside.
	# Calibrated on attached crossflow at small β, it fades out over the aircraft's declared linear-sideslip range
	# (envelope b1→b2) instead of extrapolating Munk's sin 2β peak to 45° past a stalled fin.
	var body_cn: float = surfaces.get("body_cn_beta", 0.0)
	if body_cn != 0.0:
		mz_sum += 0.5 * rho * float(ref.S) * float(ref.b) * body_cn * v0 * v1 * (1.0 - sideslip_weight(air.beta, env))
	# D10-R5 (optional): the wing-body dihedral effect the flat strips lack (they see no spanwise flow), as the same
	# u·v couple: a panel's normal velocity changes by v·sinΓ, its lift by u·v·sinΓ. The oracle's Clb carries it at small
	# angles; it fades out over the declared linear-sideslip range like the body yaw term.
	var wing_body_cl: float = surfaces.get("wing_body_cl_beta", 0.0)
	if wing_body_cl != 0.0:
		mx_sum += 0.5 * rho * float(ref.S) * float(ref.b) * wing_body_cl * v0 * v1 * (1.0 - sideslip_weight(air.beta, env))
	# D10-R3 (optional): the fuselage side force the strips and the fin lack, at the ARP where the oracle's CYb puts it.
	# The attached forward-flight slope ½ρ·S·CYβ_B·u·v agrees with the oracle at small β. D10-R3-R1 limits that
	# derivative to u > 0: its signed extrapolation is unsupported in tail-first flow. This is a conservative domain
	# limit, not a calibrated reverse-flow law. Crossflow drag −½ρ·(η·c_d·S_side)·√(v²+w²)·v stays active in either
	# direction and neither term fades with sideslip. The empirical resultant retains its reference-velocity convention;
	# it is not a resolved body-strip model or a claim of passivity for arbitrary rotation. No body yaw couple is implied.
	var body_cy: float = surfaces.get("body_cy_beta", 0.0)
	var body_cda: float = surfaces.get("body_crossflow_area", 0.0)
	if body_cy != 0.0 or body_cda != 0.0:
		var fy_body: float = 0.5 * rho * (float(ref.S) * body_cy * maxf(v0, 0.0) * v1 - body_cda * M.sqrt_(v1 * v1 + v2 * v2) * v1)
		fy_sum += fy_body
		mx_sum += -az * fy_body
		mz_sum += ax * fy_body
	return PackedFloat64Array([fx_sum, fy_sum, fz_sum, mx_sum, my_sum, mz_sum])


## D8b-R2b: opt-in diagnostics from the actual strip evaluation, never a second aerodynamic law.
## Rows describe the LOCAL wing before the global/local blend and exclude tail/propulsion/gyro.
## alpha_geometric_rad includes control/incidence offsets, alpha_effective_rad is induced attached flow.
static func wing_strip_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float,
		downwash_cl := NAN, ground_up := NAN) -> Array:
	var rows: Array = []
	if model.get("envelope", {}).is_empty() or not model.envelope.has("station_ys"):
		return rows
	_local_loads(s, air, d, model, rho, downwash_cl, rows, GroundEffect.factors(s, model, ground_up))
	return rows


## One tail surface's load about the CG with the law of _local_loads, on `area` (m2), its arm moved by `shift` and
## its velocity through the air changed by `extra` (both body axes). For the slipstream increment (E0b, opt-in).
## downwash_cl is the dimensional wing lift-velocity supplied by the caller (held or instantaneous). The default means zero
## wing downwash, not a quasi-static solve: this helper has no wing state. Legacy tails ignore it.
## VAL-AUD-R02: historical downwash_cl argument carries the m/s source, not a coefficient.
static func tail_surface_load(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		name: String, area: float, shift: PackedFloat64Array, extra: PackedFloat64Array, rho: float,
		downwash_cl: float = 0.0) -> PackedFloat64Array:
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces[name]
	var vertical := name == "vertical"
	var arm := M.add(_arm(tail.position, model.cg_le), shift)
	var flow_v := M.add(v, extra)
	if not vertical and tail.has("free_slope"):
		return _tail_surface_from_flow(M.add(flow_v, M.cross(rates, arm)), arm, d, tail, surfaces,
			area, vertical, rho, downwash_cl)
	var effective := _tail_angle(flow_v, rates, arm, d, tail, vertical)
	var cl := _tail_curve(effective, tail.lift_slope, surfaces)
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
	return _surface(flow_v, rates, arm, area, cl, cd, vertical, rho)


## Washed-minus-free load for one immersed tail piece. The two evaluations share their arm and rate cross product.
## E0b3a: both evaluations use the same supplied downwash_cl and E0a2 tail law; see tail_surface_load().
static func tail_surface_increment(v: PackedFloat64Array, rates: PackedFloat64Array, d: Dictionary, model: Dictionary,
		name: String, area: float, shift: PackedFloat64Array, extra: PackedFloat64Array, rho: float,
		downwash_cl: float = 0.0) -> PackedFloat64Array:
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces[name]
	var vertical := name == "vertical"
	var arm := M.add(_arm(tail.position, model.cg_le), shift)
	var rate_arm := M.cross(rates, arm)
	var free_velocity := M.add(v, M.v3(0.0, 0.0, 0.0))
	var free_flow := M.add(free_velocity, rate_arm)
	var washed_velocity := M.add(v, extra)
	var washed_flow := M.add(washed_velocity, rate_arm)
	var free := _tail_surface_from_flow(free_flow, arm, d, tail, surfaces, area, vertical, rho, downwash_cl)
	var washed := _tail_surface_from_flow(washed_flow, arm, d, tail, surfaces, area, vertical, rho, downwash_cl)
	for k in 6:
		washed[k] -= free[k]
	return washed


static func _tail_surface_from_flow(flow: PackedFloat64Array, arm: PackedFloat64Array, d: Dictionary,
		tail: Dictionary, surfaces: Dictionary, area: float, vertical: bool, rho: float,
		downwash_cl: float = 0.0) -> PackedFloat64Array:
	var control: float = -d.rudder if vertical else d.elevator
	var effective: float
	var slope: float
	if not vertical and tail.has("free_slope"):
		effective = wrapf(M.atan2_(flow[2], flow[0]) - downwash_angle(downwash_cl, float(tail.downwash_per_cl),
			M.sqrt_(flow[0]*flow[0] + flow[2]*flow[2]))
			+ float(tail.elevator_tau) * control + float(tail.free_incidence), -PI, PI)
		slope = tail.free_slope
	else:
		effective = wrapf(M.atan2_(flow[1 if vertical else 2], flow[0])
			+ tail.control_effectiveness*control + tail.incidence, -PI, PI)
		slope = tail.lift_slope
	var cl := _tail_curve(effective, slope, surfaces)
	var cd: float = surfaces.tail_CD0 + surfaces.tail_k*cl*cl + surfaces.tail_CD90*M.pow_(M.sin_(effective), 2)
	return _surface_with_flow(flow, arm, area, cl, cd, vertical, rho)


## LE datum [aft,right,up] to a body-axis arm about the current CG.
static func _arm(position: PackedFloat64Array, cg: PackedFloat64Array) -> PackedFloat64Array:
	return M.v3(-(position[0]-cg[0]), position[1]-cg[1], -(position[2]-cg[2]))


static func _tail_angle(v: PackedFloat64Array, rates: PackedFloat64Array, arm: PackedFloat64Array,
		d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var flow := M.add(v, M.cross(rates, arm))
	return _tail_angle_from_flow(flow, d, tail, vertical)


static func _tail_angle_from_flow(flow: PackedFloat64Array, d: Dictionary, tail: Dictionary, vertical: bool) -> float:
	var control: float = -d.rudder if vertical else d.elevator
	return wrapf(M.atan2_(flow[1 if vertical else 2], flow[0]) + tail.control_effectiveness*control + tail.incidence, -PI, PI)


## 0 = empirical attached oracle; 1 = complete local model. Includes tail/control angles,
## not just body alpha: a rapid pitch, lagged downwash or ground effect can leave the oracle while the wing is attached.
## NAN/empty inputs preserve the static trim selector; flight loads pass their actual downwash state and ground factors.
static func local_flow_weight(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		downwash_cl := NAN, ge := PackedFloat64Array()) -> float:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var limit: float = surfaces.attached_limit
	var v: PackedFloat64Array = air.v_air
	# Only angle components are needed; preserve vector-form product/sum order.
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var a1: float = env.a1
	var a1_span: float = a1 - limit
	var blend := maxf(_smoothstep((absf(air.alpha)-limit)/a1_span), sideslip_weight(air.beta, env))
	if blend == 1.0:
		return blend
	# H15: dictionary reads hoisted out of the loops; every product, sum and comparison is unchanged.
	var v0: float = v[0]
	var v1: float = v[1]
	var v2: float = v[2]
	var n1_span: float = float(env.n1) - limit
	var position: PackedFloat64Array = model.reference.arp_le
	var cg: PackedFloat64Array = model.cg_le
	var arm_x: float = -(position[0]-cg[0]) + 0.0
	var arm_y: float = position[1]-cg[1]
	var arm_z: float = -(position[2]-cg[2]) + 0.0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var has_twist := not twist.is_empty()
	var ys: PackedFloat64Array = env.station_ys
	var aileron_effect: float = surfaces.wing_aileron_effectiveness
	var da_right: float = d.aileron_right
	var da_left: float = d.aileron_left
	for i in ys.size():
		var y: float = ys[i]
		var station_y: float = arm_y + y
		var flow_x: float = v0 + (q*arm_z - r*station_y)
		var flow_z: float = v2 + (p*station_y - q*arm_x)
		var da: float = da_right if y > 0 else da_left
		# Explicit squares keep this Euclidean norm on basic float64 arithmetic;
		# generic pow(x, 2) can differ by an ulp across platform math libraries.
		var rate_x := q*arm_z - r*station_y
		var rate_y := r*arm_x - p*arm_z
		var rate_z := p*station_y - q*arm_x
		var rate_speed := M.sqrt_(rate_x*rate_x + rate_y*rate_y + rate_z*rate_z)
		blend = maxf(blend, _smoothstep((M.atan2_(rate_speed, float(air.V))-limit)/a1_span))
		if blend == 1.0:
			return blend
		var angle := wrapf(M.atan2_(flow_z, flow_x) + aileron_effect*da, -PI, PI)
		if has_twist:
			angle = wrapf(angle + twist[i], -PI, PI)
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/(a1_span if angle >= 0.0 else n1_span)))
		if blend == 1.0:
			return blend
	var tail_span: float = float(surfaces.tail_local_limit) - limit
	for tail_index in 2: # horizontal, then vertical
		var vertical := tail_index == 1
		var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
		var tail_position: PackedFloat64Array = tail.position
		var tx: float = -(tail_position[0]-cg[0])
		var ty: float = tail_position[1]-cg[1]
		var tz: float = -(tail_position[2]-cg[2])
		var flow_x: float = v0 + (q*tz - r*ty)
		var component: float = v1 + (r*tx - p*tz) if vertical else v2 + (p*ty - q*tx)
		var rate_x := q*tz - r*ty
		var rate_y := r*tx - p*tz
		var rate_z := p*ty - q*tx
		var rate_speed := M.sqrt_(rate_x*rate_x + rate_y*rate_y + rate_z*rate_z)
		blend = maxf(blend, _smoothstep((M.atan2_(rate_speed, float(air.V))-limit)/a1_span))
		if blend == 1.0:
			return blend
		var control: float = -float(d.rudder) if vertical else float(d.elevator)
		var angle: float
		if not vertical and tail.has("free_slope"):
			var wake: float = downwash_cl
			if is_nan(wake):
				wake = _wing_lift_coefficient_with(s, air, d, model, ge, true)
			var scale: float = ge[ys.size()+1] if not ge.is_empty() else 1.0
			angle = wrapf(M.atan2_(component, flow_x) - downwash_angle(wake * scale,
				float(tail.downwash_per_cl), M.sqrt_(flow_x*flow_x + component*component))
				+ float(tail.elevator_tau)*control + float(tail.free_incidence), -PI, PI)
		else:
			angle = wrapf(M.atan2_(component, flow_x) + tail.control_effectiveness*control + tail.incidence, -PI, PI)
		blend = maxf(blend, _smoothstep((absf(angle)-limit)/tail_span))
	return blend


## Coefficient diagnostic only. It is undefined physically at zero section flow;
## do not use this normalized value as a wake state. wing_wake_velocity is the dynamic source.
## ground_up: M5-GE-1 ground height under the CG (m above the NED datum); NAN = out of ground effect.
static func wing_lift_coefficient(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		ground_up := NAN) -> float:
	return _wing_lift_coefficient_with(s, air, d, model, GroundEffect.factors(s, model, ground_up))


## Equal-area mean Vp*CL (m/s) from the force-producing strip law. This is an
## equivalent-lift velocity proxy, not measured circulation in separated flow.
static func wing_wake_velocity(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		ground_up := NAN) -> float:
	return _wing_lift_coefficient_with(s, air, d, model, GroundEffect.factors(s, model, ground_up), true)


static func _wing_lift_coefficient_with(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		ge: PackedFloat64Array, dimensional := false) -> float:
	var ge_active := not ge.is_empty()
	var p: float = s[RB.RATE]
	var q: float = s[RB.RATE+1]
	var r: float = s[RB.RATE+2]
	var v: PackedFloat64Array = air.v_air
	var v0: float = v[0]
	var v2: float = v[2]
	var a: Dictionary = model.aero
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = model.reference.arp_le
	var ax: float = -(arp[0]-cg[0]) + 0.0
	var ay: float = arp[1]-cg[1]
	var az: float = -(arp[2]-cg[2]) + 0.0
	var twist: PackedFloat64Array = surfaces.get("station_incidence", PackedFloat64Array())
	var ys: PackedFloat64Array = env.station_ys
	var stations := ys.size()
	var aileron_effect: float = surfaces.wing_aileron_effectiveness
	var wing_flow := _wing_flow(s, air, d, model)
	var angles: PackedFloat64Array = wing_flow.angles
	var plane_speeds: PackedFloat64Array = wing_flow.speeds
	var source_weights: PackedFloat64Array = wing_flow.sources
	var flap_shifts: PackedFloat64Array = wing_flow.flap_shifts
	var flap_model: Dictionary = model.get("flaps", {})
	var flap_angle: float = float(d.get("flap", 0.0))
	var flap_active := Flaps.enabled(model) and flap_angle != 0.0 and float(flap_model.get("aerodynamic_gain", 1.0)) != 0.0
	var stall_back := 1.0 - float(flap_model.stall_shift_fraction) if flap_active and flap_model.has("stall_shift_fraction") else 0.0
	var e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())
	var coupled := e_map.size() == stations * stations
	var strip_slope: float = env.get("strip_slope", a.CLa)
	var strip_cl0: PackedFloat64Array = env.get("strip_cl0", PackedFloat64Array())
	var cd90: float = env.CD90
	var a1: float = env.a1
	var a_span: float = env.a2 - env.a1
	var n1: float = env.n1
	var n_span: float = env.n2 - env.n1
	var wing_cl := 0.0
	var polar: Dictionary = env.get("wing_polar", {})
	var strip_factor: PackedFloat64Array = polar.get("strip_factor", PackedFloat64Array()) # D8b-R2d, as in _local_loads
	for i in stations:
		var effective: float = angles[i]
		var stall_angle: float = effective if stall_back == 0.0 else effective - stall_back * flap_shifts[i]
		var weight := _smoothstep((stall_angle - a1) / a_span) if stall_angle >= 0.0 \
			else _smoothstep((-stall_angle - n1) / n_span)
		var base: float
		if coupled:
			var mapped := 0.0
			for k in stations:
				mapped += e_map[i * stations + k] * angles[k] * (1.0 if k == i else source_weights[k])
			base = strip_cl0[i] + strip_slope * mapped
		else:
			base = float(a.CL0) + float(a.CLa) * effective
		if ge_active: # M5-GE-1, exactly _local_loads' strip law
			base += (1.0 - ge[i]) * (strip_slope * (effective + float(env.strip_alpha_zero)) - base)
		var cl: float = base if weight == 0.0 else (1.0 - weight) * base + weight * 0.5 * cd90 * M.sin_(2.0 * effective)
		if not polar.is_empty():
			var sample := WingPolar.evaluate(effective if strip_factor.is_empty() else effective * strip_factor[i], base, polar)
			cl = sample[0]
			weight = 1.0 - sample[2]
		if flap_active and i < flap_shifts.size():
			# Match the strip's bounded separated-lift extension when producing the dimensional wake state.
			cl += strip_slope * flap_shifts[i] * weight * maxf(M.cos_(effective), 0.0)
		wing_cl += (plane_speeds[i] * cl if dimensional else cl) / stations
	return wing_cl


## ground_up: M5-GE-1 ground height under the CG (m above the NED datum) for an aircraft with aero.ground_effect;
## NAN (trim, linearisation, static solves, aircraft without the module) leaves every path byte-identical.
static func loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary, rho: float,
		downwash_cl := NAN, ground_up := NAN) -> PackedFloat64Array:
	# Keep the clean-aircraft path and its arithmetic exactly intact. Flap increments are local,
	# strip-resolved differences from that clean path, so they remain active in the small-angle oracle
	# domain without changing any aircraft that has no simulated flap command.
	var flap_config: Dictionary = model.get("flaps", {})
	if Flaps.enabled(model) and float(d.get("flap", 0.0)) != 0.0 \
			and float(flap_config.get("aerodynamic_gain", 1.0)) != 0.0 \
			and not model.get("envelope", {}).is_empty():
		var clean_d := d.duplicate(true)
		clean_d.erase("flap")
		var ge_flap := GroundEffect.factors(s, model, ground_up)
		var blend_clean: float = local_flow_weight(s, air, clean_d, model, downwash_cl, ge_flap)
		if blend_clean == 1.0:
			return _local_loads(s, air, d, model, rho, downwash_cl, null, ge_flap)
		var loads_clean := _global_loads(s, air, clean_d, model, rho, downwash_cl, ge_flap)
		var local_clean := _local_loads(s, air, clean_d, model, rho, downwash_cl, null, ge_flap)
		var local_flapped := _local_loads(s, air, d, model, rho, downwash_cl, null, ge_flap)
		for i in 6:
			loads_clean[i] = local_flapped[i] + (1.0 - blend_clean) * (loads_clean[i] - local_clean[i])
		return loads_clean
	if model.get("envelope", {}).is_empty():
		return _global_loads(s, air, d, model, rho)
	var ge := GroundEffect.factors(s, model, ground_up)
	var blend := local_flow_weight(s, air, d, model, downwash_cl, ge)
	if blend == 0.0:
		return _global_loads(s, air, d, model, rho, downwash_cl, ge)
	var local := _local_loads(s, air, d, model, rho, downwash_cl, null, ge)
	if blend == 1.0:
		return local
	var global := _global_loads(s, air, d, model, rho, downwash_cl, ge)
	for k in 6:
		global[k] = lerpf(global[k], local[k], blend)
	return global


## M5-W05c-R1: experimental UNWASHED ambient-gradient wrench in the same datum as loads().
## Inputs model/air/deflections must be normalized as for loads(). Deltas are body-axis air-relative
## increments R^T(W_O-W_i), NOT point velocity or omega cross arm: six wing stations, horizontal, vertical.
## No atmospheric state, propulsion, slipstream or live-CG shift is owned here. Live scenarios are not admitted
## until their matched wash/hub paths and persisted law identity exist. Refusal has no usable partial loads.
static func ambient_spatial_loads(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		rho: float, station_delta_body: PackedFloat64Array, downwash_cl := NAN, ground_up := NAN) -> Dictionary:
	if not _spatial_finite(s, RB.SIZE) or not is_finite(rho) or rho <= 0.0 \
			or is_inf(downwash_cl) or is_inf(ground_up):
		return _spatial_failure("invalid body, density, wake or ground input")
	var quaternion_norm := 0.0
	for axis in 4:
		quaternion_norm += s[RB.ATT+axis]*s[RB.ATT+axis]
	if not is_finite(quaternion_norm) or quaternion_norm <= 1e-24:
		return _spatial_failure("invalid body quaternion")
	var v: Variant = air.get("v_air")
	if not v is PackedFloat64Array or not _spatial_finite(v, 3):
		return _spatial_failure("invalid reference air velocity")
	for key: String in ["V", "alpha", "beta", "qbar"]:
		var value: Variant = air.get(key)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			return _spatial_failure("invalid reference air data")
	for key: String in ["elevator", "aileron_left", "aileron_right", "rudder"]:
		var value: Variant = d.get(key)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)):
			return _spatial_failure("invalid surface deflection")
	if not is_finite(float(d.get("flap", 0.0))):
		return _spatial_failure("invalid flap deflection")
	var env: Dictionary = model.get("envelope", {})
	var ys: PackedFloat64Array = env.get("station_ys", PackedFloat64Array())
	if ys.is_empty() or not _spatial_finite(station_delta_body, 3*(ys.size()+2)):
		return _spatial_failure("spatial air needs one finite delta per wing and tail station")
	var uniform := true
	for value: float in station_delta_body:
		if value != 0.0:
			uniform = false
			break
	# Do not subtract equal local loads and then add zero: preserve the exact legacy arithmetic in every regime.
	if uniform:
		var legacy := loads(s, air, d, model, rho, downwash_cl, ground_up)
		if not _spatial_finite(legacy, 6):
			return _spatial_failure("reference aerodynamic evaluation is nonfinite")
		return {ok = true, errors = PackedStringArray(), law = SPATIAL_LOADS_LAW, uniform = true,
			loads = legacy, delta = PackedFloat64Array([0., 0., 0., 0., 0., 0.]), held_wake_mps = downwash_cl}
	var ge := GroundEffect.factors(s, model, ground_up)
	# Resolve the reference source once. Each raw pass applies GE's tail scale once internally.
	var wake: float = _wing_lift_coefficient_with(s, air, d, model, ge, true) if is_nan(downwash_cl) else downwash_cl
	if not is_finite(wake):
		return _spatial_failure("reference wing wake is nonfinite")
	var domain := _spatial_domain(s, air, d, model, station_delta_body, wake, ge)
	if not domain.ok:
		return domain
	# Body residuals stay at O in the baseline. Exclude them from BOTH passes rather than
	# subtracting the same body terms after large sums and losing a small surface correction.
	var reference := _local_loads(s, air, d, model, rho, wake, null, ge, PackedFloat64Array(), false)
	var spatial := _local_loads(s, air, d, model, rho, wake, null, ge, station_delta_body, false)
	var out := loads(s, air, d, model, rho, downwash_cl, ground_up)
	var delta := PackedFloat64Array()
	delta.resize(6)
	for axis in 6:
		delta[axis] = spatial[axis] - reference[axis]
		out[axis] += delta[axis]
	if not _spatial_finite(delta, 6) or not _spatial_finite(out, 6):
		return _spatial_failure("spatial aerodynamic evaluation is nonfinite")
	return {ok = true, errors = PackedStringArray(), law = SPATIAL_LOADS_LAW, uniform = false,
		loads = out, delta = delta, held_wake_mps = wake, domain = domain}


## Deliberately conservative initial domain: both paired local flows must remain attached.
## The provisional 3-degree/25-percent limits measure weather changes at the SAME station, so
## ordinary rigid-body rotation is not mistaken for an ambient gradient. No flow is clamped.
static func _spatial_domain(s: PackedFloat64Array, air: Dictionary, d: Dictionary, model: Dictionary,
		deltas: PackedFloat64Array, wake: float, ge: PackedFloat64Array) -> Dictionary:
	var env: Dictionary = model.envelope
	var surfaces: Dictionary = model.surfaces
	var ys: PackedFloat64Array = env.station_ys
	var n := ys.size()
	var rates := s.slice(RB.RATE, RB.RATE+3)
	var reference_wing := _wing_flow(s, air, d, model)
	var spatial_wing := _wing_flow(s, air, d, model, deltas)
	var polar: Dictionary = env.get("wing_polar", {})
	var strip_factors: PackedFloat64Array = polar.get("strip_factor", PackedFloat64Array())
	var flap_config: Dictionary = model.get("flaps", {})
	var stall_back := 1.0 - float(flap_config.stall_shift_fraction) if flap_config.has("stall_shift_fraction") else 0.0
	var max_alpha := 0.0
	var max_beta := 0.0
	var max_pressure := 0.0
	for i in n+2:
		var vertical := i == n+1
		var arm: PackedFloat64Array
		if i < n:
			arm = _arm(model.reference.arp_le, model.cg_le)
			arm[1] += ys[i]
		else:
			arm = _arm(surfaces.vertical.position if vertical else surfaces.horizontal.position, model.cg_le)
		var before := M.add(air.v_air, M.cross(rates, arm))
		var after := before.duplicate()
		for axis in 3:
			after[axis] += deltas[3*i+axis]
		if not _spatial_finite(before, 3) or not _spatial_finite(after, 3) or before[0] <= 0.0 or after[0] <= 0.0:
			return _spatial_failure("spatial bridge requires forward flow at every station")
		var alpha0 := M.atan2_(before[2], before[0])
		var alpha1 := M.atan2_(after[2], after[0])
		var beta0 := M.atan2_(before[1], M.sqrt_(before[0]*before[0]+before[2]*before[2]))
		var beta1 := M.atan2_(after[1], M.sqrt_(after[0]*after[0]+after[2]*after[2]))
		var normal: int = 1 if vertical else 2
		var plane0 := before[0]*before[0]+before[normal]*before[normal]
		var plane1 := after[0]*after[0]+after[normal]*after[normal]
		var pressure_change := absf(plane1-plane0)/plane0
		if not is_finite(pressure_change):
			return _spatial_failure("invalid section-plane pressure")
		max_alpha = maxf(max_alpha, absf(wrapf(alpha1-alpha0, -PI, PI)))
		max_beta = maxf(max_beta, absf(beta1-beta0))
		max_pressure = maxf(max_pressure, pressure_change)
		if max_alpha > SPATIAL_MAX_ANGLE_RAD or max_beta > SPATIAL_MAX_ANGLE_RAD \
				or max_pressure > SPATIAL_MAX_PRESSURE_FRACTION:
			return _spatial_failure("ambient gradient exceeds the provisional angle/pressure domain")
		if absf(beta0) >= float(env.b1) or absf(beta1) >= float(env.b1):
			return _spatial_failure("station sideslip is outside the attached domain")
		if i < n:
			for wing: Dictionary in [reference_wing, spatial_wing]:
				var angle: float = wing.angles[i]
				var stall_angle: float = angle - stall_back * wing.flap_shifts[i]
				if stall_weight(stall_angle, env) != 0.0:
					return _spatial_failure("wing station is outside the attached domain")
				if not polar.is_empty():
					var polar_angle: float = angle if strip_factors.is_empty() else angle*strip_factors[i]
					if WingPolar.evaluate(polar_angle, 0.0, polar)[2] != 1.0:
						return _spatial_failure("tabulated wing station is outside the attached domain")
		else:
			var tail: Dictionary = surfaces.vertical if vertical else surfaces.horizontal
			var tail_wake: float = wake * (ge[n+1] if not ge.is_empty() else 1.0)
			for flow: PackedFloat64Array in [before, after]:
				var angle: float
				if not vertical and tail.has("free_slope"):
					angle = wrapf(M.atan2_(flow[2], flow[0]) - downwash_angle(tail_wake, float(tail.downwash_per_cl),
						M.sqrt_(flow[0]*flow[0]+flow[2]*flow[2])) + float(tail.elevator_tau)*float(d.elevator)
						+ float(tail.free_incidence), -PI, PI)
				else:
					angle = _tail_angle_from_flow(flow, d, tail, vertical)
				if absf(angle) >= float(surfaces.tail_local_limit):
					return _spatial_failure("tail station is outside the attached domain")
	return {ok = true, max_alpha_change_rad = max_alpha, max_beta_change_rad = max_beta,
		max_plane_pressure_fraction = max_pressure}


static func _spatial_finite(values: PackedFloat64Array, size: int) -> bool:
	if values.size() != size:
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


static func _spatial_failure(message: String) -> Dictionary:
	return {ok = false, law = SPATIAL_LOADS_LAW, errors = PackedStringArray([message])}
