# X8-06: X8 physics data

2026-10-25. At the time of this study, [derive_physics.py](../../../../research/skywalker-x8/X8-06/derive_physics.py) generated [skywalker_x8.json](https://github.com/bultodepapas/OpenRCsimulator/blob/e1e9bcf6c117823c2f4357e1d04bfe6de94eeb08/app/data/aircraft/skywalker_x8.json) (ideal 22.2 V bus) and [skywalker_x8_6s_pack.json](https://github.com/bultodepapas/OpenRCsimulator/blob/e1e9bcf6c117823c2f4357e1d04bfe6de94eeb08/app/data/aircraft/battery/skywalker_x8_6s_pack.json) (finite 6S 5000 mAh `pack_ecm`, the catalog default). [probe.gd](../../../../research/skywalker-x8/X8-06/probe.gd) loaded both through `AircraftData` and printed the derived tailless law, trims and strip-against-oracle coefficients. Sources: [X8-01](../X8-01/README.md).

The current generator writes `app/data/aircraft/moonrunner_x99.json` and `app/data/aircraft/battery/moonrunner_x99_6s_pack.json`; `--check` compares the generated CRLF bytes against those files. Do not hand-edit generated aircraft data. The links above preserve the earlier named files, not a claim that the present checkout still contains them.

## Inputs and choices

| Area | Data | Evidence |
| --- | --- | --- |
| Frame | LE frame = the delivery's D0 (root-rib leading edge, thrust-axis height), [x_aft, y_right, z_up] | derived |
| Reference | S 0.75 m², b 2.10 m, c = S/b 0.3571 m (NTNU reference); tapered strip split root 0.544 m, tip 0.17 m | borrowed / derived |
| Aerodynamics | Løw-Hansen 2026 clean flight identification, converted from c̄ 0.36 m to S/b; CYr from the 2025 set (2026 outlier); elevon terms split into symmetric `elevator` and per-elevon antisymmetric `aileron` terms | borrowed / derived |
| Drag | CD0 0.0387 + 0.0637·CL², k from span efficiency 0.85 at AR 5.88, CD0 through the 2026 flight drag at its trim point | derived |
| Moment reference | 425 mm from the nose: the flight-identified aerodynamic centre then sits at the tunnel neutral point | estimated |
| Planform, stations | the author's leading/trailing-edge tables digitised from the Skywalker three-view; strip quarter chords −40/165/315 mm aft of D0 (root → tip; −47/158/308 mm after the loader's shift) | derived |
| Elevons | span 244–878 mm: strip coverage 0.025 / 1.0 / 0.647; chord fraction 0.221 | derived |
| Winglets | one centreline element of both winglets: 0.0679 m², quarter chord 0.485 m aft of D0, 0.101 m up; lift slope 1.28/rad solved for Cnβ 0.0198 | derived |
| Side force and dihedral | body CYβ −0.154 (CYβ minus the winglets), wing-body Clβ −0.0592 (Clβ minus the winglets), crossflow area 0.057 m² | derived / estimated |
| Washout | −2.5° linear from root rib to tip, zero-mean per strip (+0.84°/+0.26°/−1.10° per strip, root → tip) | derived |
| Envelope | CL_max 1.05, CL_min −0.70, 8° blend, CD90 1.2, sideslip blend 15–25° | estimated |
| Mass | 3.132 kg: measured NTNU wings (2 × 459 g) and body (439 g), the author's equipment ledger, 6S pack 773 g, 69 g nose lead | measured / estimated |
| CG | 435 mm from the nose, the middle of the manual 430–440 mm range (declared `cg_range`); pack at the front of its tray, then lead | derived |
| Controls | per-elevon roll share 23.26°, pitch share 19.47°, end point 26.76° (the author's radio rig); servo full throw 0.075 s; expo 0.3 | estimated |
| Drive | 520 Kv, 0.06 Ω, 1.0 A no-load; APC 12x6E(P) UIUC tables; rotor 2.2×10⁻⁴ kg·m²; hub 846 mm, on the body axis | manual / estimated / borrowed |
| Crash hull | 28 points from the drawn model (GP-07 method), worst sink 11.7 mm over 6000 attitudes, propeller excluded | derived |
| Crash tolerance | 12.5 J/kg, 0.12 m, presentation durability 4 | estimated |

## What the loader derives and how it compares

| Quantity | Value | Comparison |
| --- | --- | --- |
| Inertia (inventory) | Jxx 0.329, Jyy 0.155, Jzz 0.479 kg·m² | NTNU bifilar 0.335 / 0.140 / 0.40 (S12, includes air added mass) |
| Station shift for the oracle's neutral point | −7.2 mm | the author's planform and the flight-identified Cmα agree |
| Elevon effectiveness τ | 0.194 | 0.34 of thin-airfoil 0.575 for E 0.22 (low, as flight-identified CLδe is) |
| Section moment (Cm0) | +0.003 | a reflexed section carries almost no moment |
| Elevon camber couple | −0.282 per rad | — |
| Static margin | 4.4 % MAC at 435 mm (neutral point 452 mm) | NTNU flew 7.5 % c̄ |
| Strip vs oracle at 15 m/s | CLα 4.398/4.399, Cmα −0.213/−0.211, CLδe and Cmδe equal, Cmq −0.874/−0.805, Clδa −0.100/−0.087, Clp −0.450/−0.213, Cnr −0.016/−0.106 | Clp and Cnr predictions match XFLR5/CFD (−0.40/−0.41, −0.012/−0.022), not the 2026 flight values |
| Level trim | 12.8 m/s: α 3.3°, throttle 0.50; 18 m/s: α 0.4°, δe 2.7°, 6.3 N, throttle 0.68 (ideal bus) | NTNU drag power at 18 m/s 113.9 W; here 113 W |
| Rudderless trim | bank 0.08–0.25°, β 0.11°, aileron −0.5° (propeller torque) | — |
| Glide at 12 m/s | γ −6.5°, L/D 8.8 | 2026 flight drag gives 10.9 (lower k), CFD 17 (optimistic) |

## Open items

- Roll damping and yaw damping in the strip model (−0.45, −0.016) differ from the 2026 flight identification (−0.21, −0.107). The blended model leaves the oracle only at large angles or rates. Pilot review should decide which roll response is realistic; other flight sets lie between.
- The drive (Kv, resistance, no-load current, rotor inertia) and the throws are estimates; measured static thrust and current would calibrate the drive.
- The X8 manual's CG marks and throws were unreadable (403). The elevon span differs between the NTNU scan and the asset.
- The crash thresholds are estimates for EPO until drop tests exist.
