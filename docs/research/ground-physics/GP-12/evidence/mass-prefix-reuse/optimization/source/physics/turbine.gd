# Turbojet propulsion (AV-05): a model-jet turbine such as the JetCat P100-RX. 64-bit floats only (guarded).
# Data: AircraftData model.propulsion with kind "turbine" (see aircraft_data.gd _turbine and
# docs/research/avanti-s-av05-turbine-dynamics.md). No propeller: no Ct/Cp, no reaction torque, no propwash.
#  - Throttle → shaft-rpm demand through the ECU's throttle map (a table, idle at 0, maximum at 1).
#  - Spool: the ECU's acceleration and deceleration schedules limit dN/dt (rpm/s, functions of N); near the demand a
#    governor closes the gap as a first-order lag: dN/dt = clamp((N_demand − N)/τ_gov, −R_dec(N), R_acc(N)).
#  - Thrust (momentum theory, NASA Glenn): gross ṁ·V_jet along the nozzle axis minus the momentum of the captured air
#    ṁ·v_air (the whole air-relative vector, applied at the intakes: its axial part is the ram drag, its cross part the
#    inlet normal force). Static: ṁ0(N)·V_j0 = k_inst·F_static(N), the installed bench thrust at STP. With airspeed u
#    the ram pressure rise lifts both, at fixed N: ṁ = ṁ0·(1 + c_ram·u²), V_jet = sqrt(V_j0² + k_jet(N)·u²)
#    (optional data fitted to a cycle model; absent = 0, the plain law F = k_inst·F_static − ṁ0·u). Densities scale
#    with σ = ρ/ρ0.
#  - Rotor: angular momentum I_rot·ω along the shaft, signed by the rotation sense (gyroscopic coupling).
# Not modelled: start-up/shutdown sequence, flameout, fuel burn (mass fixed, AV-10), EGT or inlet distortion.
# AV-14: transient mounting torque and exhaust swirl are unverified; rotor gyro is the only shaft moment modeled.
extends RefCounted

const M := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-mass-prefix-draft/optimized/physics/math3d.gd")

## ISA sea-level density, the density of the bench data (JetCat: 15 °C, 1013 mbar).
const RHO_REFERENCE := 1.225
## Below this the shaft is stopped: no thrust, no flow.
const STOPPED_RPM := 1.0
## AV-20 changes integration/sampling, not the empirical engine schedules or mounting-torque model.
const CONTINUOUS_LAW := "turbine-rpm-governor-rk4-v1"
const CONTINUOUS_LAYOUT := "turbine shaft rpm; RK4 coupled; prescribed fuel mass"
## F02/F07: experimental full-vector capture law with rigid-body intake-point velocity.
const LOADS_LAW := "turbine-capture-vector-signed-axial-local-intake-v3"
const MAX_STEP_RATIO := 0.25


static func is_turbine(prop: Dictionary) -> bool:
	return prop.get("kind", "") == "turbine"


static func is_continuous(prop: Dictionary) -> bool:
	return is_turbine(prop) and prop.get("spool_integrator", "sampled") == "rk4"


## Conservative explicit-stage envelope for the piecewise-linear closed-loop RPM law.
## A validated table can still have very steep adjacent knots. Reject before accepting a flight.
static func step_supported(prop: Dictionary, dt: float) -> bool:
	if not is_continuous(prop) or not is_finite(dt) or dt <= 0.0:
		return false
	var tau: float = prop.get("governor_tau", NAN)
	if not is_finite(tau) or tau <= 0.0:
		return false
	var fastest: float = 1.0 / tau
	for key: String in ["accel_limit", "decel_limit"]:
		var schedule: PackedFloat64Array = prop.get(key, PackedFloat64Array())
		if schedule.size() < 4 or schedule.size() % 2 != 0:
			return false
		for at: int in range(0, schedule.size(), 2):
			if not is_finite(schedule[at]) or not is_finite(schedule[at + 1]) or schedule[at + 1] <= 0.0:
				return false
			if at == 0:
				continue
			var span: float = schedule[at] - schedule[at - 2]
			if not is_finite(span) or span <= 0.0:
				return false
			var slope: float = absf((schedule[at + 1] - schedule[at - 1]) / span)
			if not is_finite(slope):
				return false
			fastest = maxf(fastest, slope)
	return is_finite(fastest * dt) and fastest * dt <= MAX_STEP_RATIO


## Piecewise-linear table [x0, y0, x1, y1, …] (x increasing), clamped to the end values outside its range.
static func table(t: PackedFloat64Array, x: float) -> float:
	var n := t.size() / 2
	if x <= t[0]:
		return t[1]
	for i in range(1, n):
		if x <= t[2 * i]:
			var x0 := t[2 * i - 2]
			return lerpf(t[2 * i - 1], t[2 * i + 1], (x - x0) / (t[2 * i] - x0))
	return t[2 * n - 1]


## Piecewise-linear table extended past both ends along its end segments. Only the trim solver reaches there (it probes
## throttle beyond 0…1 so Newton keeps a gradient and can report "needs throttle 1.03"); flight never leaves the table.
static func table_extrapolated(t: PackedFloat64Array, x: float) -> float:
	var n := t.size() / 2
	if x < t[0]:
		return t[1] + (t[3] - t[1]) / (t[2] - t[0]) * (x - t[0])
	if x > t[2 * n - 2]:
		return t[2 * n - 1] + (t[2 * n - 1] - t[2 * n - 3]) / (t[2 * n - 2] - t[2 * n - 4]) * (x - t[2 * n - 2])
	return table(t, x)


## Throttle 0…1 → the ECU's shaft-rpm demand.
static func demand_rpm(throttle: float, prop: Dictionary) -> float:
	return table(prop.throttle_map, clampf(throttle, 0.0, 1.0))


## dN/dt (rpm/s) at shaft speed rpm for a demand: governor lag, bounded by the acceleration/deceleration schedules.
static func spool_rate(rpm: float, demand: float, prop: Dictionary) -> float:
	var governed: float = (demand - rpm) / float(prop.governor_tau)
	return clampf(governed, -table(prop.decel_limit, rpm), table(prop.accel_limit, rpm))


## One tick of the spool. Inside the governor band the lag is integrated exactly (never overshoots the demand);
## on a schedule limit the rate is held for the tick and clipped at the demand. rpm never falls below 0.
static func spool_step(rpm: float, throttle: float, dt: float, prop: Dictionary) -> float:
	var demand := demand_rpm(throttle, prop)
	var rate := spool_rate(rpm, demand, prop)
	var governed: float = (demand - rpm) / float(prop.governor_tau)
	if rate == governed:
		return demand + (rpm - demand) * M.exp_(-dt / float(prop.governor_tau))
	var next := rpm + rate * dt
	return minf(next, demand) if rate > 0.0 else maxf(maxf(next, demand), 0.0)


## Steady shaft rpm for a throttle (the governor settles on the demand; airspeed does not change it). Inside 0…1 this is
## demand_rpm(); outside it extrapolates for the trim solver (see table_extrapolated).
static func steady_rpm(throttle: float, prop: Dictionary) -> float:
	return table_extrapolated(prop.throttle_map, throttle)


## Nonnegative captured-air mass flow (kg/s) at shaft rpm, local axial intake velocity u (m/s; ram rise for u > 0)
## and density rho. Reverse axial flow retains the static-flow endpoint; incidence-dependent capture is not identified.
static func mass_flow(rpm: float, prop: Dictionary, rho: float, u := 0.0) -> float:
	if rpm < STOPPED_RPM:
		return 0.0
	var uu := maxf(u, 0.0)
	return table_extrapolated(prop.mass_flow, rpm) * rho / RHO_REFERENCE * (1.0 + float(prop.get("ram_flow", 0.0)) * uu * uu)


## Installed gross thrust (N) along the nozzle axis at shaft rpm and axial airspeed u: ṁ·V_jet.
static func gross_thrust(rpm: float, prop: Dictionary, rho: float, u := 0.0) -> float:
	if rpm < STOPPED_RPM:
		return 0.0
	var static_gross: float = float(prop.installed_factor) * table_extrapolated(prop.static_thrust, rpm)
	var flow0 := table_extrapolated(prop.mass_flow, rpm)
	var vj0 := static_gross / flow0
	var uu := maxf(u, 0.0)
	var k_jet := table(prop.ram_jet, rpm) if prop.has("ram_jet") else 0.0
	return mass_flow(rpm, prop, rho, uu) * M.sqrt_(vj0 * vj0 + k_jet * uu * uu)


## Net axial thrust (N) at shaft rpm and local axial intake velocity u (m/s): gross exit force − ṁ_capture·u.
## The signed reverse-flow continuation is an experimental installed-force surrogate, not an identified inlet map.
static func thrust(rpm: float, u: float, prop: Dictionary, rho: float) -> float:
	return gross_thrust(rpm, prop, rho, u) - mass_flow(rpm, prop, rho, u) * u


## Convert the authored [aft, right, up] intake location to body FRD coordinates from the current reference CG.
## This is the same arm used for the captured-air force moment in loads().
static func intake_offset_body(prop: Dictionary) -> PackedFloat64Array:
	var ri: PackedFloat64Array = prop.get("intake_offset", PackedFloat64Array())
	if ri.size() != 3:
		return PackedFloat64Array([NAN, NAN, NAN])
	return M.v3(-ri[0], ri[1], -ri[2])


## Convert datum air-relative velocity to local air-relative velocity at the represented intake.
## Air.compute has already transformed uniform world NED wind into body axes; the remaining rigid-body term is omega×r.
## For the current constant-mass turbine route the datum is the CG. A future moving-CG model needs its R05 transform.
static func local_intake_velocity(v_air_at_datum: PackedFloat64Array, omega_body: PackedFloat64Array,
		prop: Dictionary) -> PackedFloat64Array:
	if v_air_at_datum.size() != 3 or omega_body.size() != 3:
		return PackedFloat64Array([NAN, NAN, NAN])
	return M.add(v_air_at_datum, M.cross(omega_body, intake_offset_body(prop)))


## Body loads about the current CG [Fx, Fy, Fz, Mx, My, Mz]. v_in_air is the air-relative body velocity at the
## represented intake. Gross exit force follows the nozzle axis; captured-air momentum −ṁ_capture·v_in_air acts at the
## intake for both signs of axial flow. This full-vector continuation is experimental off axis and in reverse flow.
## No mounting reaction torque is modeled. A transient term would require the open-system angular-momentum balance
## (rotor plus inlet/exhaust flux), not rotor acceleration alone; see AV-14.
static func loads(v_in_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var u := M.dot(v_in_air, prop.axis)
	var gross := M.scale(prop.axis, gross_thrust(rpm, prop, rho, u))
	var inlet_momentum := M.scale(v_in_air, -mass_flow(rpm, prop, rho, u))
	var r: PackedFloat64Array = prop.offset # [x_aft, y_right, z_up] from the CG
	var moment := M.add(M.cross(M.v3(-r[0], r[1], -r[2]), gross), M.cross(intake_offset_body(prop), inlet_momentum))
	var f := M.add(gross, inlet_momentum)
	return PackedFloat64Array([f[0], f[1], f[2], moment[0], moment[1], moment[2]])


## Angular momentum of the spool in body axes (N·m·s): I_rot·ω along the shaft, + = clockwise seen from behind.
static func rotor_momentum(rpm: float, prop: Dictionary) -> PackedFloat64Array:
	return M.scale(prop.axis, float(prop.rotor_inertia) * float(prop.rotor_sense) * rpm * TAU / 60.0)


## Fuel-flow map (kg/s) for accepted-endpoint observations. Mass stays fixed until AV-10.
static func fuel_flow(rpm: float, prop: Dictionary) -> float:
	return 0.0 if rpm < STOPPED_RPM else table(prop.fuel_flow, rpm)
