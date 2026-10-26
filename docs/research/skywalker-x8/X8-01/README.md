# X8-01: Skywalker X8 sources

Research snapshot 2026-10-25. Sources for the [X8 integration](../../../X8-PLAN.md): the NTNU Skywalker X8 studies, retail data, propeller data and EPO material data. [sources.json](sources.json) lists all 36 records (S01–S34, X01–X02) with URL, access date, what each supports and the local copy. Local copies are in the ignored `references/` folder: `references/skywalker-x8/` (with `SHA256SUMS`) and the [2026-10-18 flying-wing library](../../flight-dynamics/rc-validation-library-2026-10-18/flying-wings/README.md). Public availability does not grant redistribution. Nothing behind a paywall or bot challenge was bypassed; the X8 manual pages (X01) and Sekisui foam datasheets (X02) returned 403 or required a login.

## What the physics uses

| Quantity | Value used | Source | Kind |
| --- | --- | --- | --- |
| Coefficient reference | S 0.75 m², b 2.10 m, c̄ 0.36 m (contract chord S/b = 0.3571 m; pitch terms × 1.008, Cmq × 1.016) | S05 | borrowed / derived |
| Lift and pitch | CL0 0.1523, CLα 4.3993, CLq 0.444, CLδe 0.5011; Cm0 0.0067, Cmα −0.3307, Cmq −0.8042, Cmδe −0.2316 | S05 Tables 11–12 (clean, 3.73 kg, 18 m/s, measured rpm; CC BY 4.0) | borrowed |
| Lateral | CYβ −0.270, CYp −0.192, Clβ −0.0644, Clp −0.2124, Clr 0.1135, Clδa 0.0865, Cnβ 0.0198, Cnp −0.0204, Cnr −0.1069, Cnδa −0.0043 | S05 | borrowed |
| CYr | 0.108 | S04 Table 8; S05's 0.539 is five times XFLR5's 0.084 (S01) and 2024's 0.186 (S03), treated as an outlier | borrowed |
| Control definitions | δe = (δel + δer)/2, δa = (δel − δer)/2, rad; signs imply trailing edge down positive | S03 eq. 14, S04 eq. 14, S05 eq. 13 | borrowed |
| Drag | CD0 + k·CL² with k = 1/(π·0.85·AR), CD0 through S05's flight drag at its trim CL 0.246 (L/D 5.8) | S05 + estimate | derived |
| Lift range | linear to ≈12° (tunnel); CLmax 1.1 at 18° (CFD); CL_max 1.05 used | S01, S02, S06 | estimated |
| Moment reference | 425 mm from the nose: puts S05's aerodynamic centre (7.5 % c̄ aft) at 452 mm, within 1 mm of the tunnel neutral point (≈451 mm, S01 transferred) | S01, S05, S07 | estimated |
| Inertia check | Ixx 0.335, Iyy 0.140, Izz 0.40 kg·m², J13 −0.029 at 3.364 kg (bifilar, includes air added mass) | S12 Table 6.1 | measured |
| Airframe parts | wings 464/454 g incl. winglets, painted body 439 g | S11 Table 6.2 | measured |
| CG | 430–440 mm from the nose | S20–S23 | manual |
| Elevon travel | NTNU physical −30°/+35°, flown ±19°; servo ωn 100 rad/s | S11, S05, S03 | measured |
| Drive | retail PNP 3530 520 Kv, 6S 5000–6000 mAh, 60 A ESC; kit recommendation 12x6E | S20–S22 | manual |
| Propeller | APC 12x6E, UIUC Vol. 4 static and 6044 rpm tunnel tables (local `references/rc-propellers-12x6/uiuc`) | S18 | borrowed |
| EPO foam | density 25 kg/m³; compressive 0.16 MPa at 25 % strain (the sheet's footnote says 60 g/L: inconsistent) | S30 | manual |

## Conflicts and gaps

- **Flight-identified sets differ.** CLα ranges from 2.5 (2024–2025, EKF angles and a 2.8 m/s vertical-wind correction) to 4.40 (2026). Roll damping Clp is −0.21 in 2026, −0.31 in 2024–2025, −0.40 in XFLR5 (S01) and CFD (S06), and −0.47 in the KhAI identification (S08). The simulator's tailless strip model predicts −0.45 from geometry (X8-06).
- **Gryte 2018 rate derivatives are XFLR5, not tunnel data.** Use Winter's author-corrected paper (S06); the published 2019 conference paper has numerical errors.
- **The NTNU X8 is a research build** (4S Hacker A40, 14x8 folding propeller, sensors, 3.36–3.73 kg). Its drag includes the research payload.
- **Elevon span conflict.** The NTNU scan puts the elevons at 500–987.5 mm span (S11). The repository asset's author places them at 242–878 mm (S33). The physics follows the asset, which is what the pilot sees; an owner measurement would settle it.
- **Not found:** measured stall speed, top speed or spin data; the manual's throws, expo and rates; elevon chord and hinge; winglet area; airfoil; EPO impact thresholds for the X8 foam grade.
- The superseded MSc inertia set (1.229/0.1702/0.8808/0.9343) still circulates in the S14/S15 simulators; S12 replaces it.
- **Model licences.** The `krisgry/x8` model (S14) has no licence. The FW-JSBGym `x8.xml` (S15) is GPL inside an MIT repository, and its mesh has unknown provenance. ArduPilot SITL (S27) is GPLv3 with generic coefficients. None was copied into the simulator.
