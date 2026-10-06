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
# Not modelled: start-up sequence, flameout, fuel burn (mass is fixed, AV-10), EGT, ram rise of ṁ, inlet distortion.
extends RefCounted

const M := preload("res://physics/math3d.gd")

## ISA sea-level density, the density of the bench data (JetCat: 15 °C, 1013 mbar).
const RHO_REFERENCE := 1.225
## Below this the shaft is stopped: no thrust, no flow.
const STOPPED_RPM := 1.0


static func is_turbine(prop: Dictionary) -> bool:
	return prop.get("kind", "") == "turbine"


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


## Steady shaft rpm for a throttle (the governor settles on the demand; airspeed does not change it).
static func steady_rpm(throttle: float, prop: Dictionary) -> float:
	return demand_rpm(throttle, prop)


## Engine air mass flow (kg/s) at shaft rpm, axial airspeed u (m/s; ram rise for u > 0) and density rho.
static func mass_flow(rpm: float, prop: Dictionary, rho: float, u := 0.0) -> float:
	if rpm < STOPPED_RPM:
		return 0.0
	var uu := maxf(u, 0.0)
	return table(prop.mass_flow, rpm) * rho / RHO_REFERENCE * (1.0 + float(prop.get("ram_flow", 0.0)) * uu * uu)


## Installed gross thrust (N) along the nozzle axis at shaft rpm and axial airspeed u: ṁ·V_jet.
static func gross_thrust(rpm: float, prop: Dictionary, rho: float, u := 0.0) -> float:
	if rpm < STOPPED_RPM:
		return 0.0
	var static_gross: float = float(prop.installed_factor) * table(prop.static_thrust, rpm)
	var flow0 := table(prop.mass_flow, rpm)
	var vj0 := static_gross / flow0
	var uu := maxf(u, 0.0)
	var k_jet := table(prop.ram_jet, rpm) if prop.has("ram_jet") else 0.0
	return mass_flow(rpm, prop, rho, uu) * sqrt(vj0 * vj0 + k_jet * uu * uu)


## Net axial thrust (N) at shaft rpm and axial airspeed u (m/s): gross thrust minus ram drag ṁ·u.
static func thrust(rpm: float, u: float, prop: Dictionary, rho: float) -> float:
	return gross_thrust(rpm, prop, rho, u) - mass_flow(rpm, prop, rho, u) * maxf(u, 0.0)


## Body loads about the CG [Fx, Fy, Fz, Mx, My, Mz] for air-relative body velocity v_air. Gross thrust along the fixed
## nozzle axis through the thrust line; the captured air's momentum −ṁ·v_air at the intakes (forward-moving air only:
## flying backwards the ram term is dropped). No reaction torque (the spool's torques balance inside the engine).
static func loads(v_air: PackedFloat64Array, rpm: float, prop: Dictionary, rho: float) -> PackedFloat64Array:
	if rpm < STOPPED_RPM:
		return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var u := M.dot(v_air, prop.axis)
	var gross := M.scale(prop.axis, gross_thrust(rpm, prop, rho, u))
	var ram := M.scale(v_air, -mass_flow(rpm, prop, rho, u)) if u > 0.0 else M.v3(0.0, 0.0, 0.0)
	var r: PackedFloat64Array = prop.offset # [x_aft, y_right, z_up] from the CG
	var ri: PackedFloat64Array = prop.intake_offset
	var moment := M.add(M.cross(M.v3(-r[0], r[1], -r[2]), gross), M.cross(M.v3(-ri[0], ri[1], -ri[2]), ram))
	var f := M.add(gross, ram)
	return PackedFloat64Array([f[0], f[1], f[2], moment[0], moment[1], moment[2]])


## Angular momentum of the spool in body axes (N·m·s): I_rot·ω along the shaft, + = clockwise seen from behind.
static func rotor_momentum(rpm: float, prop: Dictionary) -> PackedFloat64Array:
	return M.scale(prop.axis, float(prop.rotor_inertia) * float(prop.rotor_sense) * rpm * TAU / 60.0)


## Fuel flow (kg/s) at shaft rpm, for telemetry and the endurance check (mass stays fixed until AV-10).
static func fuel_flow(rpm: float, prop: Dictionary) -> float:
	return 0.0 if rpm < STOPPED_RPM else table(prop.fuel_flow, rpm)
