# D11f — Yaw damping through the oracle/local transition

2026-10-07 · **Status: verified; no model change needed. The local fin is consistent and the local Cnr matches the Stik's own consistent value within 3.7%; the ×0.7 gap to the oracle is borrowed data (owner/DATA decision).** Main-line ROADMAP M1 follow-up D11f.

## Question

D11b showed the local model's yaw damping Cnr at ×0.72–0.75 of the oracle's −0.1833 across the blend. The roadmap asks to resolve it "with consistent local velocity, force and moment arm".

## Findings

**1. The local fin is consistent.** A fin's yaw-rate damping and its sideslip stiffness come from the same lift slope, area and arm: Cnr_fin = −2·(l_v/b)·Cnβ_fin. The loader already derives the oracle's Cnβ (0.1214) from the fin data. The local fin's measured yaw damping is −0.1163 to −0.1185 against that invariant's −0.1179 (within 1.3% at α 0–11°), and local Cnβ is 0.123–0.124 (within 2.2%). Velocity (v + ω×r), force (perpendicular to the local flow) and moment arm (r × F) are therefore consistent; nothing to fix.

**2. The wing's physical yaw damping is profile drag.** An independent Weissinger solution under yaw rate ([`research/aero/d11f/wing_yaw_damping.py`](../../../../research/aero/d11f/wing_yaw_damping.py), [output](../../../../research/aero/d11f/output.txt)) uses per-strip angle W/u_i and Kutta–Joukowski forces with the trailing downwash. For the Stik's 3-strip AR 5 wing it gives Cnr_wing = −0.0141, constant in CL. That is −CD0/3·(1 − 1/(4n²)); the lift-induced part is +0.0004·CL². Circulation stays nearly symmetric under yaw (Γ ∝ W on both wings), so neither lift tilt nor induced drag adds damping here.

**3. The local wing deviates slightly, and the cause is data, not the strip mechanics.** The local wing (with the tail) contributes −0.016 at α 0 and −0.011 at α 11. The trend comes from applying the **whole-airplane polar** CD0 + k·(cl − CL_minD)², with k 0.0815 (mostly induced drag), to each strip: under yaw rate its CL_minD cross term makes strip drag depend on the onset speed. The proper split is explicit induced drag from the D11d map plus a per-strip profile polar. But the induced factor of this wing is k_i ≈ 0.064 (e ≈ 1.0 at 40 strips per side), and subtracting it from the borrowed polar leaves a "profile" parabola whose minimum sits at CL ≈ 1.2. That is not a plausible section drag bucket. The borrowed polar cannot be decomposed for the Stik without Stik data; the effect is under 4% of total Cnr. Deferred to the same DATA decision.

**4. The oracle's Cnr is inconsistent with the oracle's own fin.** Its Cnβ (Stik fin) implies a fin Cnr of −0.118; adding the wing's −0.014 gives −0.132. The borrowed Cnr −0.1833 (OpenFlightSim UltraStick 25e) would need −0.065 from wing and fuselage, about 4.6 times what the wing provides. It is another airplane's value.

## Proof

- [`test_yaw_damping.gd`](../../../../app/tests/test_yaw_damping.gd), 3 checks across α 0–11°:
  - fin invariant within 2% (worst 1.34%);
  - Cnβ within 3% (worst 2.16%);
  - local Cnr within 7% of the Stik-consistent −0.132 (worst 3.67%).
- **Mutation:** a fin that ignores yaw rate in its local flow fails two checks.
- **Regressions:** the rudder doublet (golden), dutch roll and spiral (`test_modes`), reverse-flow continuity and passive-load tests are unchanged, because there is no model change.
- **Full suite:** `app/test.sh` with its own `XDG_DATA_HOME` exits 0 (103 sections, other tracks' work in progress included). [Summary](suite-summary.log).

## Outcome

D11b keeps Cnr pinned at ×0.72 against the borrowed oracle. Acceptance is against the Stik-consistent value, like E0a2b. All four D11b responses now have a justified status:

| Derivative | Status |
| --- | --- |
| Clp | Accepted (D11d) |
| CLα | Accepted (D11d) |
| Cmq | Matches Stik geometry, ×0.81 of the borrowed oracle (E0a2b) |
| Cnr | Matches the Stik-consistent value, ×0.72 of the borrowed oracle |

Closing the oracle side is one decision: [oracle data decision brief](../oracle-data-decision.md).
