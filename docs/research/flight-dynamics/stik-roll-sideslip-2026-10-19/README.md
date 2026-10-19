# D10-R5: Ugly Stik roll due to sideslip across the load regimes (2026-10-19)

**Status: implemented; opt-in law, adopted for the Stik family.** The Stik and its five glow variants declare `aero.surfaces.wing_body_cl_beta`. Other aircraft are unchanged, and the oracle's `Clb` is unchanged.

The local strip law had no dihedral effect. Wherever it carries the loads, the Stik's static roll due to sideslip (Clβ) fell to the fin's share: one sixth of the small-angle oracle's value, and a quarter of what the measured Ultra Stick 120 keeps. This step adds the missing wing-body term as a calibrated couple. The method is the same as [P51-25](../../p51-realism/P51-25/README.md) used for the fuselage yaw (`body_cn_beta`).

Scripts are in [`research/flight-dynamics/stik-lateral-directional/`](../../../../research/flight-dynamics/stik-lateral-directional/); outputs are in [`results/`](results/).

## 1. The regime collapse

[`roll_regimes.gd`](../../../../research/flight-dynamics/stik-lateral-directional/roll_regimes.gd) differentiates the body-axis rolling moment about the CG over β = ±1° at 25 m/s. It does so for the oracle, the local law and the production blend at each angle of attack. FASER is the NASA Ultra Stick 120, static wind-tunnel Clβ (Owens, Cox, Morelli 2006, Fig. 2b), [digitized](../../../../research/flight-robustness/d8b-r2/analog/faser_clb.csv) by `faser_cl.py`. Values are per rad ([before](results/roll-regimes-before.md), [after](results/roll-regimes-after.md)):

| α | Blend weight | Oracle | Local, before | Production, before | Production, after | FASER |
| --- | --- | --- | --- | --- | --- | --- |
| 0° | 0 | −0.079 | −0.012 | −0.079 | −0.079 | −0.040 |
| 4° | 0 | −0.079 | −0.012 | −0.079 | −0.079 | −0.053 |
| 8° | 0 | −0.080 | −0.012 | −0.080 | −0.080 | −0.064 |
| 10° | 0.48 | −0.081 | −0.012 | −0.048 | −0.073 | −0.070 |
| 12° | 1 | −0.082 | −0.012 | **−0.012** | −0.065 | −0.054 |
| 16° | 1 | −0.083 | −0.012 | **−0.012** | −0.064 | −0.118 |
| 20° | 1 | −0.085 | −0.012 | **−0.012** | −0.062 | −0.211 |
| 30° | 1 | −0.093 | −0.011 | **−0.011** | −0.057 | −0.220 |

- Past α 8° (and past β 15°, or under fast rolls) the local law takes over. Before this step, the roll stability then fell by 85 % within 4°.
- FASER keeps it and strengthens it past the stall; its report states static lateral stability up to α 30°.
- The local law's −0.012 is the fin alone: CYβ_v −0.250 at 0.075 m above the CG.
- The same collapse exists elsewhere in the fleet (oracle / local): Timber −0.080 / −0.008 and P-51 −0.064 / −0.027. On the Extra the two are close (−0.024 / −0.033). Their owners decide whether to adopt the term.

## 2. Cause

The strips compute their angle from the chordwise and normal velocity only. A flat strip therefore sees no change of angle in sideslip. On a real wing with dihedral Γ, sideslip changes each panel's normal velocity by ±v·sin Γ, so the windward panel lifts more. A high wing adds the fuselage crossflow: upwash at the windward root and downwash at the leeward root. The oracle's `Clb` carries both; the local law carried neither.

## 3. How large the term should be

| Term (Stik, per rad, zero lift) | Value | Source |
| --- | --- | --- |
| Geometric dihedral, lifting line | −0.0382 | −0.01335 per degree of Γ through this wing's calibrated induced map (`roll_regimes.gd`, antisymmetric strip incidence), times Γ = 2.86° (estimated from the plan's 1.5 in tip rise) |
| Geometric dihedral, strip theory (upper bound) | −0.0531 | −CLα·Γ/4, Helmbold CLα 4.25; the method of the P-51 and Avanti generators, which ignores the antisymmetric induced flow |
| High-wing interference | −0.0155 | DATCOM 1.2·√AR·(z_w/b)·(2D/b), z_w −0.0595 m, D 0.113 m ([`directional_prediction.py`](../../../../research/flight-dynamics/stik-lateral-directional/directional_prediction.py)) |
| **Predicted wing-body term** | **−0.0537** | lifting line + interference |
| Closure from the data | **−0.0537** | borrowed `Clb` −0.0545 less the fin about the ARP −0.0008 |

- The closure keeps the oracle as it is and makes the local law agree with it. An independent prediction from the Stik's own geometry gives the same value.
- **Cross-check against FASER.** FASER has Γ 0.7°, against the Stik's 2.86°. Adding the extra 2.16° at −0.0134/° to FASER's −0.053 at 4° gives −0.082 for a Stik-like airframe, against the oracle's −0.079 about the CG. The borrowed `Clb` is therefore plausible about the CG for this dihedral.
- The flight-identified Ultra Stick 25e value (−0.039, Dorobantu) belongs to a different airframe with an unknown dihedral.
- The dihedral angle is the dominant uncertainty: ±1° moves the predicted term by ±0.013.

## 4. Law

- **Couple.** `aero.surfaces.wing_body_cl_beta` (1/rad, −0.3…0.1) adds the pure rolling couple ½ρ·S·b·Clβ_WB·u·v·(1 − w_β) in `Aero._local_loads`.
  - u·v is the panel-normal velocity change times the chordwise speed, so it is linear in β at small angles and zero at zero flow and broadside.
  - w_β fades the couple out over the declared linear-sideslip range (15–25°), as `body_cn_beta` does: neither term is evidenced at large sideslip.
- **Loader rule.** When the field is declared, `Clb` must equal the fin's term about the ARP plus the declared term. This is the same rule as `Cnb` = fin + body. Absent means no couple and no rule, bit-identical.
- **Constant in α.** The term is a consistency closure, not a post-stall model. FASER's growth to −0.21 past the stall is not represented in either regime.

## 5. Effect

**Static.** The local Clβ is now −0.066 at α 0° (82 % of the oracle's) and −0.057 at 30°. The remaining 0.013 at the blend is the fuselage side force: the oracle applies the whole −0.489 at the ARP, 0.07 m above the CG, while the local law has only the fin. That gap is a known open item (side-force consistency, see section 6).

**Linear modes** ([before](results/modes-before.txt), [after](results/modes-after.txt)), by `modes_fleet.gd --speeds`. From 12 m/s up they are bit-identical, because the oracle carries the trim there. Near the stall the spiral divergence slows:

| Speed | Spiral τ before → after | Dutch roll before → after |
| --- | --- | --- |
| 10 m/s | −2.4 → −4.1 s | 0.45 Hz ζ 0.37 → 0.52 Hz ζ 0.30 |
| 10.5 m/s | −4.4 → −7.5 s | 0.47 Hz ζ 0.31 → 0.49 Hz ζ 0.29 |
| 11 m/s | −17 → −37 s | unchanged |

**Flight-test card** (`ft-card-v3`, Stik, same tree with and without the term; [comparison](results/ft-compare.md)):
- **Knife-edge:** the opposite aileron the pilot holds rises from 0.22–0.28 to 0.32–0.37 of full stick. This is the high-wing roll coupling that real knife-edge needs. Height loss is 1–8 % larger; sustained knife-edge was already impossible (side-force gap).
- **Rudder step:** bank after 2.75 s grows from ±78…85° to ±94…104°. Rudder rolls the airplane through the dihedral effect, as on a high-wing trainer.
- **Roll at 1.3 Vs:** peak sideslip falls from 19° to 17°, and the 360° roll takes 0.2–0.3 s longer. The dihedral effect opposes adverse-yaw sideslip.
- **Stall:** the wing drop barely changes (−78° → −76° bank in the first second). It is driven by the strip law's post-stall roll instability ([D8b-R2d](../../flight-robustness/D8b-R2/analog/README.md)), not by the dihedral effect.
- **Spin:** still develops, at 3.05–3.16 turns in 6 s (was 2.85–2.98). Recovery takes 0.25–0.94 s (was 0.31–0.68), within one turn on both sides.

**Long spin** ([before](results/spin-long-before.md), [after](results/spin-long-after.md), `long_spin.gd`, right spin, 15–20 s): α 20.5° → 20.0°, |β| 19.9° → 18.8°, θ −65° → −62°, Ωb/2V 0.161 → 0.174, sink 22.9 → 22.1 m/s. The spin keeps its character. At |β| ≈ 19° the couple is partly faded.

**Tests.** [`test_wing_body_roll.gd`](../../../../app/tests/test_wing_body_roll.gd) has 16 checks:
- byte identity when absent or zero;
- the exact law;
- oracle/local agreement at small sideslip;
- the regime ratio (local/oracle Clβ 0.157 without the term, 0.818 with it);
- zero-flow, broadside and fade continuity;
- three loader rejections.

`test_wing_polar.gd` excludes the couple from its strip-telemetry identity, as it does `body_cn_beta`.

**Regression references (re-recorded for this intentional change).**
- `test_modes.gd`: only the three 10 m/s lateral centres move: Dutch roll 0.447 → 0.515 Hz, ζ 0.366 → 0.302, spiral 0.423 → 0.244 1/s. All other centres stay within 3 %.
- Goldens: `roll_15`, `pull_throttle` and `rudder_doublet` enter the local regime and move by at most 1.2 m, 4.1 m and 0.5 m over their 2.5–3 s. `glide_15` is unchanged.
- The goldens were recorded on a frozen copy of the tree and replay exactly on the integrated tree.
- On the frozen copy, the unit tests showed no other failures, apart from wall-clock checks: scuff build time and audio queue. Those also failed on the unchanged copy under the same machine load.

## 6. Limits and open items

- **Side-force consistency between the regimes (pending, D10-R3 candidate).** The local law has no fuselage side force. That gap leaves Clβ 18 % weaker in the local regime and Cnβ 12 % stronger (0.069 against 0.061 about the CG), and it makes sustained knife-edge impossible.
- **Post-stall growth.** FASER's Clβ grows to −0.21 past 18°; the law holds about −0.06.
- **Data.** The dihedral angle is estimated, and `Clb` is borrowed from the Ultra Stick 25e model. A measured tip rise on the owner's Jensen, or a filmed rudder-roll test, would replace both.
- **Fleet.** The P-51, Timber and Avanti generators already compute a wing-body Clβ by handbook methods. Their local laws lack it in the same way. Adoption belongs to those tracks.

## 7. Reproduction

From the repository root, with the [pinned Godot](../../../TOOLS.md#developer-setup) as `$GD`:

```bash
python3 -I research/flight-dynamics/stik-lateral-directional/directional_prediction.py
$GD --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/roll_regimes.gd" -- \
  res://data/aircraft/jensen_ugly_stik_60.json --csv=<dir>
$GD --headless --path app --script "$PWD/research/flight-dynamics/stik-lateral-directional/modes_fleet.gd" -- \
  --only=jensen-das-ugly-stik-60 --speeds=10,10.5,11,11.5,12,15
$GD --headless --path app --audio-driver Dummy --script res://tests/test_wing_body_roll.gd
```

The "before" rows come from the same commands on a copy of `app/` whose Stik file omits the field.
