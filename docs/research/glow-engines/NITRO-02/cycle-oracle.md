# Crank-angle cycle oracle for NITRO-02

Generated 2026-10-13. The runnable implementation is [`cycle_oracle.py`](../../../../research/glow-engines/cycle_oracle.py), the numerical checks are [`test_cycle_oracle.py`](../../../../research/glow-engines/test_cycle_oracle.py), and the machine-readable results are [`cycle-oracle.json`](cycle-oracle.json). The source SHA-256 is `17d2575922971bbb43d7af30159c57302796c322484792758437324a278cf19e`. The JSON also records full hashes for each candidate profile, installation, aircraft configuration, and runtime kernel used by the comparison.

## What the comparison establishes

This report separates three kinds of evidence.

1. **Numerical closure and convergence:** each closed compression/combustion/expansion segment satisfies the implemented ideal-gas first law to better than (10^{-13}) J. At a 0.5° event-aligned step, gross pressure work differs from the 0.0625° reference by 0.00275% for the MAX-55AX and 0.00216% for the FS-64V. This verifies the code's quadrature and closed-segment bookkeeping; it does not validate the assumed pressure history. Open-cycle mass and enthalpy exchange are imposed boundary approximations, so whole-cycle thermodynamic conservation is not established.

2. **Conditional averaging comparison:** an angle-averaged pressure-torque balance and a cycle-resolved rotor-energy map use the same prescribed pressure waveform, installed propeller surrogate, and losses. At the primary installed inertia, their static equilibrium speeds differ by 0.0099% for the 2T and 0.0127% for the 4T. The resolved maps predict about 1.03% and 2.54% peak-to-peak RPM ripple, respectively. The pressure waveform is generated at each candidate mean RPM and held fixed during its map; propeller and table-based losses vary with instantaneous RPM, while charge and combustion do not. These figures bound averaging error only for this declared inferred model. No pre-existing acceptance budget applies to production mean-cycle error, so they cannot establish a production-model pass against a physical target.

3. **Empirical accuracy:** no cylinder-pressure, propeller-map, aircraft-flight, or pilot measurements were used. AIAA-2016-5011 includes output and fuel measurements for the MAX-55AX and a four-stroke O.S. FS 56-a, but those outputs were not imported into this oracle; the tested FS 56-a is not an FS-64V. Physical-engine, propeller, held-out, and experienced-pilot validation remain **not performed**. The pressure oracle is a second engineering hypothesis, not empirical truth or a numerical oracle for a different ODE.

## Declared engine and installation inputs

The manufacturer dimensions are read from the candidate profiles. Bore and stroke are documented; connecting-rod ratio 3.5 and equivalent reciprocating mass (2.5% of dry engine mass) are estimated. The crank map adds the estimated piston mass as angle-dependent inertia (J_{eff}=J_{rot}+m_{rec}(dy/d\theta)^2), using the installed aircraft `rotating_inertia`; it omits connecting-rod angular kinetic energy and its mass distribution. One-cycle sensitivity cases span the profile's stated 1–5% dry-mass range without re-solving equilibrium RPM. Installed inertia is a configuration estimate, not a measured engine assembly inertia.

| Candidate | Cycle and assumed event timings | Primary installed propeller surrogate | Installed rotor inertia |
|---|---|---|---:|
| O.S. MAX-55AX | Ported 360°; EPO 100°, TPO 120°, TPC 240°, EPC 260° ATDC | APC Sport LP12070 12×7; 304.8 mm diameter, 177.8 mm pitch, fitted 21.1364 mm chord | 0.00035585373584 kg·m² |
| O.S. FS-64V | True 720° 4T; EVO 145° ATDC, IVO 10° before exhaust TDC, EVC 10° after exhaust TDC, IVC 35° ABDC | Master Airscrew K Series 14×6; 355.6 mm diameter, 152.4 mm pitch, estimated 30 mm chord | 0.00066538180000 kg·m² |

Compression ratio 8.0, γ = 1.34, trapped charge temperatures (350 K 2T, 330 K 4T), residual fractions (0.10, 0.08), heat-to-gas fractions (0.52, 0.62), combustion phasing, and burn duration are inferred. The pressure trace uses a normalized Wiebe burn law. Explicit low/high one-factor assumptions and the resulting unweighted work endpoints are retained in the JSON; those endpoints are scenario ranges, not confidence intervals or physical bounds. Fuel-property inputs use AIAA-2016-5011 Table 1 for the Omega 10% blend (72% methanol, 10% nitromethane, 18% castor oil by volume), which that study used with an O.S. MAX-55AX 2-cycle and an O.S. FS 56-a 4-cycle engine. The blend properties are borrowed; the measured engine outputs are not imported as calibration targets here, and FS 56-a is not FS-64V.

The fixed carrier has 0 m/s axial speed and air density 1.225 kg/m³, with full admission, mixture 1.15, and firing fraction 1.0. The independently implemented prop model uses 12 uniform-chord annuli and the current installation's section coefficients, then refuses loads below the positive-thrust actuator-disk ideal-power bound. It is not a measured propeller map.

## Results at the declared assumptions

The reported profile mean-cycle and pressure-cycle work use different closures. At the profile-rated points, the pressure integration gives gross indicated work of 6.0367 J/cycle for the 2T and 10.7981 J/cycle for the 4T, versus candidate-kernel work of 5.0151 J/cycle and 9.7930 J/cycle. The differences (+20.4%, +10.3%) are mismatches between inferred work closures, not measured errors and not the averaging error above. Peak pressure estimates (4.30 MPa, 5.24 MPa) are similarly conditional outputs.

| Static root comparison | MAX-55AX / 2T | FS-64V / 4T |
|---|---:|---:|
| Candidate profile mean-cycle root | 10,330 rpm | 7,785 rpm |
| Pressure-oracle angle-mean root | 12,239 rpm | 8,103 rpm |
| Pressure-oracle periodic-map time-average RPM | 12,238 rpm | 8,102 rpm |
| Angle-mean vs periodic-map difference | −0.0099% | −0.0127% |
| Peak-to-peak RPM ripple in periodic map | 126 rpm (1.03%) | 206 rpm (2.54%) |
| Profile burned-fuel flow at periodic-map mean RPM | 0.301 g/s | 0.135 g/s |
| Profile delivered-premix flow at periodic-map mean RPM | 0.571 g/s | 0.195 g/s |

The fuel rates are reconstructed from candidate-profile charge, mixture, and efficiency tables at the simulated mean RPM; they are not time-resolved oracle combustion measurements. The profile and pressure-root mismatch is about 18.5% for the 2T and 4.1% for the 4T. Since the two methods use different inferred indicated-work and gas-exchange closures, this result flags calibration uncertainty rather than demonstrating a failure or success of cycle averaging.

RPM constraints are reported separately from solver support. The MAX-55AX's 16,000 rpm manufacturer rating exceeds the APC Sport 12×7 limit of 15,833 rpm derived from APC's 190,000/diameter(in) Sport rule; that rated pressure-work point is an engine-reference calculation, not an allowed installed point. Its two static roots remain below the prop limit. The FS-64V roots are below both its 11,000 rpm manufacturer recommendation and the provisional 11,786 rpm prop limit, which applies a generic Master Airscrew 165,000/diameter(in) plastic-prop rule to a K-Series composite prop and is not SKU-specific. `operation.max_rpm` in the candidate profiles is interpolation support, not a runtime RPM cap.

## Quadrature and phase-sampling probe

The event-aligned work refinement and a separate unlocked-phase midpoint sampling probe are in the JSON. The latter samples the 0.0625° reference waveform on uniform grids at 16 phase offsets, using linear interpolation only to get coarse sample values; it deliberately does not align samples to burn or gas-exchange events.

| Uniform sample spacing | 2T max absolute cycle-work error | 4T max absolute cycle-work error |
|---:|---:|---:|
| 20° | 1.798% | 1.892% |
| 5° | 0.144% | 0.320% |
| 0.5° | 0.0144% | 0.0315% |

These values show phase-sensitive quadrature error for the assumed waveform. They do not model Godot's variable-Δt loop and do not establish aliasing against a physical engine. The resolved-map RPM root changes by 0.00155% (2T) and 0.00107% (4T) between 0.5° and 0.125° integration, compared with 0.103% and 0.0737% between 4° and 0.125°.

## Evidence and sources

- O.S. manufacturer data: [MAX-55AX](https://www.os-engines.co.jp/english/line_up/engine/air/aircraft/catalog/15612.htm) and [FS-64V](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html).
- Crank-angle single-zone model precedents: [SAE 2002-01-2193](https://saemobilus.sae.org/papers/modelling-methodology-a-spark-ignition-engine-experimental-validation-part-i-single-zone-combustion-model-2002-01-2193) and [single-cylinder four-stroke simulation paper](https://www.sciencedirect.com/science/article/pii/S0196890401000929). Their measured engine data are not imported.
- Two-stroke gas-exchange context: [2021 crankcase-scavenged SI working-process paper](https://doi.org/10.1016/j.ecmx.2021.100086) and [SAE 690135](https://saemobilus.sae.org/papers/simulation-a-crankcase-scavenged-two-stroke-si-engine-comparisons-with-experimental-data-690135). This oracle omits the coupled control-volume and scavenging detail those sources discuss.
- Fuel properties: [AIAA 2016-5011](https://doi.org/10.2514/6.2016-5011), Table 1's Omega 10% blend properties. Its engine tests include the MAX-55AX 2-cycle and FS 56-a 4-cycle; the latter is not FS-64V. [O.S. FSα-56 specification](https://www.os-engines.co.jp/english/line_up/fsalpha56/).
- Prop limits: [APC RPM limits](https://www.apcprop.com/technical-information/rpm-limits/) and [Master Airscrew downloads](https://www.masterairscrew.com/pages/downloads); the K-Series limit remains a provisional family-level estimate.

The report's input fingerprints are recorded here to make reruns auditable:

| Input | MAX-55AX / 2T SHA-256 | FS-64V / 4T SHA-256 |
|---|---|---|
| Candidate profile | `7cb92109c5e0f3f578c4b92eac21564d9e8a2761d98dafabcc8f295b91a18258` | `8f72dbcc3a81dd55d2de19dc0f7342cd6250ba88bc392fb0328e7bbb12edfd39` |
| Installation | `b227c394b3b5ac54dc10c0d40cf02dc886553237106b19cec512baac656fcc45` | `216e0d58f0aa4885160c39e556663a4170ac36e2b2a6831d66531003ed8fb3b4` |
| Aircraft configuration | `353413d403bb2749f22959636537eb1d702985af68aa4f096543f3227c7cd9d9` | `8d55e3f51d63f2bb6d2258941eabfe8bde52de3a21bff3e5ea31f2236b168bc5` |

The 11 Python tests check geometry, true 360°/720° cycles, Wiebe bounds, closed-segment energy bookkeeping, grid refinement, distinct work closures, phase-sampling behavior, installed prop power bounds, effective inertia, and periodic-map closure. These are software checks only.
