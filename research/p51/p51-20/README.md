# P51-20 ground-effect tools

2026-10-14 · **Status: reusable tools.** [Plan](../../../docs/P51-REALISM-PLAN.md) · [Evidence](../../../docs/research/p51-realism/P51-20/README.md)

| File | Purpose |
| --- | --- |
| `ground_effect_vlm.py` | Image-method Weissinger vortex lattice of the P-51 wing (80 cosine-spaced panels, taper, 5° dihedral, washout, swept LE), with the ground as a mirror plane. Writes `vlm_ground_effect.json`: same-CL induced-drag ratio, same-α lift ratio, and tail downwash ratio per unit lift against x = ARP height / span, plus least-squares fits of the faded runtime law `GroundEffect.law()`. Standard library only, about 20 s. |
| `ge_probe.gd` | Runtime `Aero.loads` at the 1.3 Vs trim with α held fixed, as the CG descends to the main-wheel contact height: σ factors, lift, drag and pitch-moment increments. |

The P51-05 generator reads `vlm_ground_effect.json` into `aero.ground_effect`. Run from the repository root:

```powershell
python research/p51/p51-20/ground_effect_vlm.py --check
python research/p51/p51-05/derive_physics.py --check
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script "$PWD/research/p51/p51-20/ge_probe.gd"
```

Regenerate both JSON files if the wing or tail geometry changes. The VLM has no fuselage, no rolled-up wake and no viscous effects. Its ratios are a planform-specific estimate, not a measurement.
