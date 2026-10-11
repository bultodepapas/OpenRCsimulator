# EL1f — Timber physics handoff

2026-10-10 · **Status: reusable software available; Timber data/flight acceptance open. Step prefix: EL.**

The electric interfaces are exercised by two synthetic configurations. TT-07 can now supply a provenance-complete `electric_prop` dataset; TT-08/09 can use the same coupled session, trim, stop/replay and v7 telemetry. No aircraft ID or Timber-specific constant belongs in the shared motor/propeller code.

The selected reference remains EFL105250B, an 800 Kv motor, Avian 70 A controller, three-blade 11×7.3 propeller and 4S 3200 mAh pack class. The [hardware revision/source matrix](../EL1a/timber-reference.md) distinguishes documented labels from unavailable physical parameters; it is not evidence of sales rank or proof of the external mesh's revision.

| Required input | Current state | Integration consequence |
| --- | --- | --- |
| Equivalent winding resistance and I0 with voltage/RPM/temperature context | Not identified | Do not copy synthetic source losses into a Timber dataset |
| Propeller + spinner + rotor inertia; locked aircraft mass/CG/tensor for the same loadout | Not measured/closed | Reconcile TT geometry/loadout and verify positive carrier inertia plus timestep envelope |
| Matched stock three-blade Ct/Cp versus advance ratio and RPM | Not supplied | Existing two-blade data does not validate this propeller or windmilling |
| Exact pack SKU/condition, loaded voltage, OCV/resistance/capacity and auxiliary draw | Pack class only | Fixed-voltage assumption must be labeled; EL2/6 remain open |
| Installed ESC firmware/settings, command response, brake, LVC and recovery | Not read back | Identity duty/ideal coast is a simulator baseline, not an Avian preset |
| Assistance configuration and independent observations | Not supplied | Disable/identify AS3X as well as SAFE; reserve held-out runs for EL5/6 |

TT retains model, catalog, audio and native-package acceptance. Until those dependencies close, the explicit synthetic demo is the integration practice aircraft. Sources, numerical qualification and measurement requirements are preserved in [the owning plan](../../../ELECTRIC-PROPULSION-PLAN.md); no guessed parameter has been promoted to measured Timber data.
