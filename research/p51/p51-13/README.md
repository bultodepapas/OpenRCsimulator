# P51-13: wing section and spanwise stall of the P-51D 1/4

2026-10-06. Report: [docs/research/p51-flight-realism.md](../../../docs/research/p51-flight-realism.md).

| File | What |
| --- | --- |
| `section_camber.py` | Thin-airfoil zero-lift angle and Cm_ac from the real UIUC root (BL17.5) and tip (BL215) ordinates of the NAA/NACA 45-100 (gitignored in `references/p51-mustang/airfoils/`; hashes in the output). |
| `section.json` | Root: t/c 16.5 %, camber 1.26 % at 68 % chord (aft-loaded), α0 −1.48°, Cm_ac −0.040. Tip: 11.4 %, 1.30 % at 46 %, α0 −1.22°, Cm_ac −0.031. Upper ordinate at 1.25 % chord: 2.15 % root, 1.19 % tip (Gault, NACA TN 3963: the tip is near the thin-airfoil/bubble stall boundary). |

How `derive_physics.py` uses it (section "stall" of [derivation.md](../p51-05/derivation.md)):

- Section lift slope 0.86·2π and clmax(Re) = 1.00 / 1.14 / 1.16 / 1.27 at Re 3e5 / 7e5 / 1e6 / 2e6 (NACA 66(2)-415, Loftin & Smith, NACA TN 1945), minus 0.05 for a painted model.
- Cm_ac = thin airfoil × 0.8 (measured/theory for the 66(2)-415 in TN 1945).
- Spanwise loading by Schrenk; a 40-term lifting line (research synthesis) gives the same peak cl/CL 1.05 at η 0.5 and puts the first stall at η 0.68 untwisted, η 0.49 with 2° washout.
- The three equal-area strips per side stall at wing CL 1.083 (root), 0.995 (mid), 0.986 (tip); with the 1.88° washout their angle offsets are −0.30°, +0.43°, −0.12°: the mid-span strip stalls first, as NACA saw in the XP-51's glide stalls (flow first broke down along the mid-semispan trailing edge).

Limits. Section data are for a smooth 66(2)-415, not the 45-100 itself; three strips per side resolve the spanwise stall coarsely; the tip's thinner section gets no clmax penalty beyond its lower Reynolds number.
