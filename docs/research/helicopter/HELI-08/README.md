# HELI-08: signed geared rotor coupling

**Date:** 2026-10-13. **Status:** implemented and software-verified; physical validation remains open.

[geared_coupling.gd](../../../../app/physics/rotorcraft/geared_coupling.gd) prepares a finite inventory of shaft inertias, signed speed ratios, and unit spin axes in body FRD. It forms the generalized spin inertia and body momentum vector

```text
IΩ = Σ nk² Ik
b  = Σ nk Ik ak
H  = J ω + Ω b
```

For body external moment `Mext` and generalized shaft torque `Qnet`, it solves the body and rotor equations simultaneously:

```text
J ωdot + b Ωdot = Mext − ω × H
b · ωdot + IΩ Ωdot = Qnet
```

The equivalent closed form uses `d = 1 − b·J⁻¹b/IΩ`:

```text
Ωdot = [Qnet − b·J⁻¹(Mext − ω×H)] / (IΩ d)
ωdot = J⁻¹(Mext − ω×H − b Ωdot)
```

The runtime includes external aerodynamic shaft moments once in `Mext`, and uses the same coupling result for rigid-body acceleration, rotor acceleration, and `H`. Main-rotor and tail-rotor aerodynamic torques enter `Qnet` as `−Qmain − ntail Qtail`; engine drive torque and declared shaft losses enter once. The airplane coupling and its call path are unchanged.

The generated preset has two signed-axis members: main rotor about body `+Z` and tail rotor about body `+Y`. Its current total reflected inertia is about `0.0798 kg·m²`; engine spin inertia remains excluded because its signed axis is unknown. This inventory preserves arbitrary signed members in the kernel and does not infer axes from positive ratio magnitudes.

`test_heli_coupling.gd` passes 23/23 checks on Linux and Windows. The independent identities check the simultaneous body and shaft rows, stored angular momentum, world angular-momentum rate against external torque, the coupled kinetic-energy rate

```text
E = ½ ωᵀJω + Ω b·ω + ½ IΩΩ²
Edot = Mext·ω + QnetΩ
```

and a fixed-body shaft stand against integrated delivered work. Additional cases cover reversed signed axes, invalid axes, and a singular effective carrier inertia. These algebraic checks establish consistency of the implementation; they do not validate the estimated inertias against a physical helicopter.

The primary aircraft-model source is Gavrilets, Mettler and Feron, [*Dynamic Model for a Miniature Aerobatic Helicopter*](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), especially its rotor/body coupling discussion on printed pp. 12–14. The paper's source-specific approximation is not treated as calibration for this generated trainer profile.
