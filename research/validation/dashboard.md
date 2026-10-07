# VAL-3 — Related-airframe comparison dashboard

**Status:** generated, report-only. This does not validate the owner's Stik or close Gate 2.

Engine: `4.7.2-stable (official)`. Input inventory SHA-256: `289118878f9ad245395a03371bf3ed7e2a590c16f12a17cd974d005226f1f171`.

Regenerate: `python3 research/validation/dashboard.py`; verify freshness: append `--check`.

Ratios are simulation / reference. Bands are estimated class-comparison screens, not source uncertainty, statistical confidence or qualification tolerances. Red rows do not fail software checks. Damping has no invented band. Unknown tuning history is not held-out validation.

| Reference | Metric | Sim | Reference | Unit | Ratio | Estimated band | Status | Kind | Used for tuning |
| --- | --- | ---: | ---: | --- | ---: | --- | --- | --- | --- |
| us120 | Short-period frequency | 8.33752 | 8.16814 | rad/s | 1.0207 | 6.9429–9.3934 | 🟢 IN BAND | derived | unknown |
| us120 | Short-period damping | 0.777769 | 0.55 | 1 | 1.4141 | not assigned | ⚪ UNASSESSED | derived | unknown |
| us120 | Roll decay rate | 17.8795 | 8.62069 | 1/s | 2.0740 | 7.7586–9.4828 | 🔴 OUTSIDE | derived | unknown |
| us120 | Dutch-roll frequency | 4.47986 | 3.58142 | rad/s | 1.2509 | 3.0442–4.1186 | 🔴 OUTSIDE | derived | unknown |
| us120 | Dutch-roll damping | 0.248241 | 0.31 | 1 | 0.8008 | not assigned | ⚪ UNASSESSED | derived | unknown |
| us25e | Short-period frequency | 0.089512 | 0.107434 | 1 | 0.8332 | 0.091319–0.12355 | 🔴 OUTSIDE | measured | unknown |
| us25e | Short-period damping | 0.797722 | 0.83 | 1 | 0.9611 | not assigned | ⚪ UNASSESSED | measured | unknown |
| us25e | Roll decay rate | 0.994116 | 0.418766 | 1 | 2.3739 | 0.37689–0.46064 | 🔴 OUTSIDE | derived | unknown |
| us25e | Dutch-roll frequency | 0.239715 | 0.165768 | 1 | 1.4461 | 0.1409–0.19063 | 🔴 OUTSIDE | measured | unknown |
| us25e | Dutch-roll damping | 0.233592 | 0.33 | 1 | 0.7079 | not assigned | ⚪ UNASSESSED | measured | unknown |

## Ultra Stick 120 — legacy Froude-scaled comparison

Source: [primary document](https://conservancy.umn.edu/server/api/core/bitstreams/3eaa84c3-81fc-41ed-ae56-65f3ea700347/content); Lie, Synthetic Air Data Estimation Method, Appendix D, Tables D.1-D.2 and section D.3, printed pp. 85–86. Provenance: **inherited_derivation**.

The modal scalars come from the rounded repository derivation in RESEARCH.md, D8b, not values printed verbatim in the thesis. Its matrix extraction/eigenvalue calculation has not been independently reproduced in VAL-3. Frequencies 1.30/0.57 Hz are converted to rad/s; roll tau 0.116 s is inverted. Damping 0.55/0.31 is retained without a diagnostic band. Treat these provisional derived rows as historical context.

Retains D8b fixed Stik speed 13.8 m/s and already Froude-scaled modal scalars for 1.524 m span. The old scaling used rounded lengths (about 0.79 ratio); this is not full dynamic similarity or a new equal-CL solve. Relative density, airfoil and trim differ. Re-derivation is required if the target span changes.

Simulation: 13.8 m/s, nominal CL 0.522169. Reference: 19.2 m/s; mass 8.338 kg; span 1.9172 m; chord 0.4336 m; area 0.7692 m²; throttle unknown.

Source airframe/trim properties, not Stik properties. Throttle fraction, CG relative to our datum and wind are unknown. Appendix D gives alpha 4.47°, beta −1.01°, bank −1.35°, pitch 5.47° and 1974.15 rpm; it does not state CL.

4×4 modal estimates are diagonal-block projections; cross-axis couplings are omitted

## Ultra Stick 25e — equal-CL reduced modes

Source: [primary document](https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20(spring%202013)/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf); Dorobantu et al., System Identification for Small, Low-Cost, Fixed-Wing Unmanned Aircraft; Table 1, section IV, Tables 4–5 and identified lateral matrix. Provenance: **source_checked**.

Flight-identified modal frequencies and damping. The roll entry 12.53 is used as real-pole magnitude in 1/s, consistent with the printed lateral matrix pole near −12.537. Table 5 also lists a conflicting 0.50 s time constant; that number is not used. This is another airframe, not a Stik acceptance dataset.

Solve the Stik speed at the reference nominal CL using the same assumed density. Compare wn*c/(2V) for pitch and wn*b/(2V) or pole*b/(2V) laterally; damping is unchanged. Each aircraft uses its own span/chord/speed. This removes kinematic scale only, not mass/inertia/airfoil differences.

Simulation: 18.8363 m/s, nominal CL 0.280272. Reference: 19 m/s; mass 1.959 kg; span 1.27 m; chord 0.25 m; area 0.31 m²; throttle 70%.

Source Table 1 dimensions and section IV nominal flight speed/throttle; CG relative to our datum and wind unknown. CL is derived with assumed sea-level density 1.225 kg/m³ and gravity 9.80665 m/s², not a reported measurement.

4×4 modal estimates are diagonal-block projections; cross-axis couplings are omitted

## Provenance and limits

Exact input hashes, full-precision samples, estimated bands and tuning flags are in [snapshot.json](snapshot.json). The 15 m/s software regression matches the existing `test_modes.gd` bands; it is separate from the external comparisons. Controls/engine are frozen in this modal analysis; diagonal projections omit cross-axis coupling. The Stik's borrowed derivatives and differing mass, inertia, airfoil and actuation prevent treating another airframe's rows as acceptance targets.
