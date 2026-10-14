# HELI-07/08: drivetrain integration audit

**Date:** 2026-10-13. **Status:** source/interface audit; no rotorcraft drivetrain or geared-coupling kernel is implemented yet.

Gavrilets et al., [printed pp. 12–14](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), Eq. 28 includes body yaw acceleration in the rotor-speed equation. Eqs. 29–30 approximate engine power as throttle-proportional and torque as `Pe/Ω`; this airborne approximation is singular at stop. The source estimates total reflected inertia at about 2.5 main-blade inertias, without supplying a complete engine inertia/shaft-axis inventory. Governor step matching is calibration, not independent validation.

The existing [airplane coupling](../../../../app/physics/rotor_coupling.gd) uses locked assembly inertia `J`, additional rotor momentum, and an exact simultaneous body/spin solve. Its arithmetic and airplane call path must remain unchanged. The rotorcraft extension needs the geared form:

```text
IΩ = Σ nk² Ik
b  = Σ nk Ik ak                 (signed spin axes ak, positive speed ratios nk)
H  = J ω + Ω b
IΩ Ωdot + b · ωdot = Qnet
J ωdot = Mext − ω × H − b Ωdot
Qnet = ηg nes Qengine − Qmr − ntr Qtr − Qloss
```

If engine inertia contributes to `IΩ`, its signed momentum `nes Iengine aengine` must also contribute to `b`. Its shaft direction cannot be inferred from a positive speed-ratio magnitude. A truly disengaged engine cannot retain its inertia in a common rotor-speed state; actual clutch/freewheel slip needs the separate engine speed and engagement events. A single-speed hold may mean zero drive torque with explicitly lumped inertia, but it must not claim full engine decoupling.

The current main/tail kernels already emit external aerodynamic shaft moments. Include them once in `Mext`, and use the coupling result for both rotor acceleration and additional body reaction. Do not append another engine reaction or duplicate gyroscopic moment. A fixed-body single-axis check then recovers the expected drive reaction through `−Qaero − IΩ Ωdot`.

At zero speed, a torque- and power-limited drive proxy can remain finite without an RPM floor: `Qengine = min(Qavailable, Pcap/Ωengine)` for positive speed, and `Qavailable` at zero. Compute delivered power as `Qengine Ωengine`, not the command's power cap. Available startup torque needs data and an explicit drive/starter model; this proxy does not make a stopped nitro engine self-starting. HELI-07 must also handle main-rotor low-RPM advance-ratio refusal before connecting a spool-up route; the existing aerodynamic kernels are not qualified over that lifecycle.

For a clamped-body stand, verify `E = 0.5 IΩ Ω²` against integrated delivered shaft power minus aerodynamic/loss power, including startup, power limiting, hold and signed windmill torque. For body coupling, the correct energy is

```text
E = 0.5 ωᵀ J ω + Ω b · ω + 0.5 IΩ Ω²
Edot = Mext · ω + Qnet Ω
```

Verify world angular momentum `Rbody_to_world H` against external angular impulse. Rotor-only energy during body acceleration is insufficient because coupling transfers work between body and shafts. Locate the zero-speed event without clamping negative overshoot after integration. All of these are remaining HELI-07/08 gates in the [active plan](../../../plans/helicopter.md).
