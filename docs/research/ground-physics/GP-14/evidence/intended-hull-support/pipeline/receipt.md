# GP-14 optional hull-intent pipeline receipt

2026-10-26. Resource, v2 contract/registry/schema generator and loader registration
implemented. No stock aircraft authoring, force law, state or statistics eligibility
changed. ContactContract/session/adapter consumption is a separate pending slice.

Exact registry identities: `aircraft.ground.intended_hull.v1`, plus
`aircraft.ground.intended_hull.belly.v1` or `.skid.v1`. They are observational
modules; no installed force law is added/replaced. Compiler transforms are disabled
until source-aware rebinding is qualified. Runtime resource law:
`authored-hull-role-pose-observation-v1`; selected force law remains `HullContact.law()`.

V2 root `intended_hull_support` and optional capability
`landing_support: authored_hull_v1` require one another. The initial domain requires
complete authored physical hull IDs, locked-up/no-installed-gear and no wheel ground
module. Invalid present data fails load without a partial model. Absent data adds
no normalized intent field and retains stock behavior. The normalized resource is
compiled after PhysicalIdentity binding and pins existing hull IDs/coordinates/law.

`AircraftData.legacy_v1_input` explicitly strips the new module and capabilities
before the existing numerical derivation. Synthetic opt-in has byte-identical
legacy numerical input. Historical v1's permissive ignored root metadata remains
permissive, but cannot produce normalized v2 intent. Old history is not reclassified.

Verification:

- Promoted resource first passed 149/149. Final expanded resource/pipeline suite:
  **174/174**, complete/ok, exit 0, zero diagnostics, 1.516 s.
  `tmp/gp14-hull-role-checks/final-main/godot-7n14_mb4/report.json`.
- Generated schema freshness check passed. Actual-file schema/public-loader corpus:
  **150 cases, zero failures**, including 16 valid fleet controls, 3 historical v1
  cases and 11 explicit schema-pass/runtime-fail semantic counterexamples.
  `tmp/gp14-hull-role-checks/schema-v2-final.json`.
- Existing baseline contract suite: **5 tests passed**, 2070 schema/loader cases,
  142 valid controls and 23 runtime-only checks (99.003 s).
- Shared module registry: **7 tests passed**, including existing Python/GDScript
  classification parity. Fleet statistics detector: **111/111**.
  `tmp/gp14-hull-role-checks/fleet-statistics/` contains the checked engine receipt.
- Structural preflight: **16 aircraft, zero failures**. X8 source generator
  `research/skywalker-x8/X8-06/derive_physics.py --check`: both generated files current.
- `app/test.sh` discovers `tests/test_*.gd` automatically in its unit loop; the new
  script needs no additional partition registration.

Final SHA-256:

- `app/physics/intended_hull_support.gd`:
  `ae9ece8ea78f96265046f702abe2d178c28b907d79207c098e45930ad242a61f`
- `app/tests/test_intended_hull_support.gd`:
  `2dcaac9e0fb60cb7ceb70a57e87be43c52fa68d33a15bb3f692386d70a450cc9`
- generated `app/data/schema/openrc-aircraft-v2.schema.json`:
  `c340b34cf215f51713e9352cc5e29e54e3d5b01a953a56b9a0bf932f2bb6526e`

External commit `61e1dd989` captured part of this work while in progress; remaining
targeted diffs complete runtime capability enumeration, whitespace-safe IDs and
the expanded tests. Reviewer must assess the final tree, not only the final diff.
No files were staged or committed by this specialist.
