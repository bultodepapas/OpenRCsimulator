# Primary research source index

The nine domain specialists consulted scientific papers, original experimental reports, manufacturer data, official engineering documentation and source implementations. This index collates the external URLs actually cited by their reports, plus the lead’s common benchmark references. Multiple URLs or reports can refer to one publication; the URL count is not a count of independent experiments. Internal code, baseline receipts and project contracts are linked in the reports.

For the precise claim supported, original table/section where recorded, hardware/configuration, units, uncertainty and transfer limitations, follow the **Used in** column. A publication on another airframe or propeller is an equation or test-design reference unless the report explicitly establishes a hardware match. Catalog ratings and fitted anchors are not independent validation. A source implementation is a design precedent; proposed production code remains project-owned native C++.

## Evidence selection

- **Mechanisms and limits:** NASA/NACA, MIT, UIUC, original rotorcraft/propeller/turbine studies and numerical-analysis papers support equations, asymptotes, conservation and event behavior.
- **Named measurements:** F50/F5146, Scorpion, O.S., JetCat, cell-test and rotor/EDF datasets retain their measured boundary and model identity. The source reports document where the simulator uses estimates.
- **Implementation precedent:** official PX4/Rotorflight, compiler, contact-engine and profiling references help choose bounded algorithms. They do not qualify OpenRC’s gain values, replay or target speed.
- **Reusable checks:** the lead reopened NASA NESC check-case material and the standard-atmosphere reference. The numerical fixtures in this audit are explicitly identified; no unexecuted external benchmark is claimed as passed.

## Referenced URLs (61)

| Source | Used in |
| --- | --- |
| [Chrono 10 ChTire](https://api.projectchrono.org/10.0.0/classchrono_1_1vehicle_1_1_ch_tire.html) | [mechanics](domains/mechanics.md) |
| [Erin Catto, Determinism](https://box2d.org/posts/2024/08/determinism/) | [native engine](domains/native-engine.md) |
| [Deters, Ananda and Selig, seven-hole-probe tests](https://commons.erau.edu/publication/957/) | [fixed wing](domains/fixed-wing.md) |
| [SUNDIALS usage notes](https://computing.llnl.gov/projects/sundials/usage-notes) | [native engine](domains/native-engine.md) |
| [Authors' paper and benchmarks](https://continuous-collision-detection.github.io/tight_inclusion/) | [mechanics](domains/mechanics.md) |
| [Galeotti et al., measured cell data and operating protocol](https://data.mendeley.com/datasets/stcppt2r68/1) | [electric edf](domains/electric-edf.md) |
| [Phillips and Hunsaker](https://digitalcommons.usu.edu/mae_facpub/87/) | [fixed wing](domains/fixed-wing.md) |
| [Rotorflight governor reference](https://doc.rotorflight.org/stable/contributing/tech/governor/) | [flight controls](domains/flight-controls.md) |
| [Author's paper](https://doi.org/10.1002/cpa.22238) | [mathematics](domains/mathematics.md) |
| [Original paper](https://doi.org/10.1016/S0898-1221(00)00045-6) | [mathematics](domains/mathematics.md) |
| [Ground-effect experiments](https://doi.org/10.1155/2017/1823056) | [multirotor](domains/multirotor.md) |
| [Original study](https://doi.org/10.3390/en14144074) | [mathematics](domains/mathematics.md) |
| [Rotor interaction experiments](https://doi.org/10.4050/F-0078-2022-1182) | [multirotor](domains/multirotor.md) |
| [Moulton, University of Maryland, 2007](https://drum.lib.umd.edu/items/64e1f066-f9d5-4247-8eab-5c59dac3b498) | [combustion turbine](domains/combustion-turbine.md) |
| [Original experiment](https://dspace-erf.nlr.nl/server/api/core/bitstreams/bb3ec185-4a96-4066-9fcf-ba9ee7194e69/content) | [helicopter](domains/helicopter.md) |
| [Dorobantu et al.](https://experts.umn.edu/en/publications/frequency-domain-system-identification-for-a-small-low-cost-fixed/) | [fixed wing](domains/fixed-wing.md) |
| [GCC 13.3 optimization options](https://gcc.gnu.org/onlinedocs/gcc-13.3.0/gcc/Optimize-Options.html) | [native engine](domains/native-engine.md) |
| [PX4 MulticopterRateControl.cpp](https://github.com/PX4/PX4-Autopilot/blob/main/src/modules/mc_rate_control/MulticopterRateControl.cpp) | [flight controls](domains/flight-controls.md) |
| [Hitec HS-311 specification](https://hitecrcd.co.jp/products/hs311/) | [flight controls](domains/flight-controls.md) |
| [UIUC report](https://m-selig.ae.illinois.edu/props/volume-1/uiuc-props-wind-tunnel-correction-new.pdf) | [mathematics](domains/mathematics.md) |
| [UIUC wind-tunnel data](https://m-selig.ae.illinois.edu/props/volume-2/data/da4002_5x4.92_1195ga_6041.txt) | [multirotor](domains/multirotor.md) |
| [Ananda, Deters and Selig, wing/propeller experiments](https://m-selig.ae.illinois.edu/pubs/AnandaDetersSelig-2014-AIAA-2014-2152.pdf) | [fixed wing](domains/fixed-wing.md) |
| [UIUC low-Re finite-wing experiments](https://m-selig.ae.illinois.edu/pubs/AnandaSukumarSelig-2015-AeroSciTech-LowReWings.pdf) | [fixed wing](domains/fixed-wing.md) |
| [Selig, Full-Envelope Aerodynamics Modeling, §III](https://m-selig.ae.illinois.edu/pubs/Selig-2010-AIAA-2010-7635-FullEnvelopeAeroSim.pdf) | [fixed wing](domains/fixed-wing.md) |
| [UIUC Low-Speed Airfoil Tests, volumes 1–5](https://m-selig.ae.illinois.edu/uiuc_lsat.html) | [fixed wing](domains/fixed-wing.md) |
| [MuJoCo computation, primal problem](https://mujoco.readthedocs.io/en/3.8.0/computation/) | [mechanics](domains/mechanics.md) |
| [MuJoCo simulation initialization](https://mujoco.readthedocs.io/en/stable/programming/simulation.html#initialization) | [native engine](domains/native-engine.md) |
| [NACA TN 4044, figures 13–20](https://ntrs.nasa.gov/api/citations/19930084743/downloads/19930084743.pdf) | [fixed wing](domains/fixed-wing.md) |
| [NACA RM L51H15, figures 24–26](https://ntrs.nasa.gov/api/citations/19930086886/downloads/19930086886.pdf) | [fixed wing](domains/fixed-wing.md) |
| [Hartman and Biermann, NACA Report 641](https://ntrs.nasa.gov/api/citations/19930091716/downloads/19930091716.pdf?attachment=true) | [combustion turbine](domains/combustion-turbine.md) |
| [NASA technical publication](https://ntrs.nasa.gov/api/citations/20250010468/downloads/Johnson%20TP-202510468.pdf) | [helicopter](domains/helicopter.md) |
| [U.S. Standard Atmosphere 1976](https://ntrs.nasa.gov/citations/19770009539) | [baseline and scope](baseline-and-scope.md) |
| [NACA report](https://ntrs.nasa.gov/citations/19930091277) | [mathematics](domains/mathematics.md) |
| [NASA technical report](https://ntrs.nasa.gov/citations/19980210404) | [mathematics](domains/mathematics.md) |
| [Klein, NASA/CR-1999-209547](https://ntrs.nasa.gov/citations/19990100653) | [fixed wing](domains/fixed-wing.md) |
| [NASA TP-2005-213477](https://ntrs.nasa.gov/citations/20060024029) | [helicopter](domains/helicopter.md), [multirotor](domains/multirotor.md) |
| [Weinstein and Simmons, Tables 1, 6, 16–17 and Figure 5](https://ntrs.nasa.gov/citations/20230017299) | [electric edf](domains/electric-edf.md) |
| [Perfetto CPU profiling](https://perfetto.dev/docs/quickstart/callstack-sampling) | [native engine](domains/native-engine.md) |
| [Author publication record](https://portal.research.lu.se/en/publications/integrator-windup-and-how-to-avoid-it/) | [flight controls](domains/flight-controls.md) |
| [CMU-RI-TR-00-03](https://publications.ri.cmu.edu/storage/publications/pub_files/pub2/mettler_bernard_2000_1/mettler_bernard_2000_1.pdf) | [flight controls](domains/flight-controls.md) |
| [PX4 AttitudeControl.cpp](https://px4.github.io/Firmware-Doxygen/db/de4/_attitude_control_8cpp_source.html) | [flight controls](domains/flight-controls.md) |
| [UZH data and frames](https://rpg.ifi.uzh.ch/neuro_bem/Readme.html) | [multirotor](domains/multirotor.md) |
| [maxon, controller input and motor current](https://support.maxongroup.com/hc/en-us/articles/360016161594-Motor-controllers-Input-current-versus-Motor-current-Power-Conversion) | [electric edf](domains/electric-edf.md) |
| [General multibody impact equations](https://underactuated.mit.edu/multibody.html) | [multirotor](domains/multirotor.md) |
| [Author paper](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf) | [helicopter](domains/helicopter.md) |
| [MIT propulsion derivation](https://web.mit.edu/16.unified/www/SPRING/propulsion/notes/node86.html) | [multirotor](domains/multirotor.md) |
| [MIT Marine Hydrodynamics, Lecture 20](https://web.mit.edu/fluids-modules/www/potential_flows/Lectures/lec20/lecture20.pdf) | [mechanics](domains/mechanics.md) |
| [Waterloo stall/reattachment experiments](https://www.cambridge.org/core/journals/journal-of-fluid-mechanics/article/transient-dynamics-of-stall-and-reattachment-at-low-reynolds-number/F97A76B0038B843B58BDC6625B67A8F2) | [fixed wing](domains/fixed-wing.md) |
| [Many et al., DLRK 2021, §§2–4](https://www.dglr.de/publikationen/2022/550281.pdf) | [combustion turbine](domains/combustion-turbine.md) |
| [FAA handbook chapter](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/helicopter_flying_handbook/hfh_ch04.pdf) | [helicopter](domains/helicopter.md) |
| [Fossen's model](https://www.fossen.biz/html/marineCraftModel.html) | [mechanics](domains/mechanics.md) |
| [Geometric Tools IntrLine3Capsule3](https://www.geometrictools.com/GTE/Mathematics/IntrLine3Capsule3.h) | [mechanics](domains/mechanics.md) |
| [Rasines Mazo et al., ICAS 2026, §2.2 and Tables 2–3](https://www.icas.org/icas_archive/icas2026/data/papers/icas2026_0801_paper.pdf) | [fixed wing](domains/fixed-wing.md) |
| [JetCat 2019 catalog, P100-RX column](https://www.jetcat.de/jetcat/Kataloge/190501%20JetCat%20ENGINES%202019.pdf) | [combustion turbine](domains/combustion-turbine.md) |
| [Manufacturer's ten F50 2150 KV/F5146 measurements](https://www.ligpower.com/product/f50-5inch-racing-drone-motor.html) | [electric edf](domains/electric-edf.md), [multirotor](domains/multirotor.md) |
| [NASA NESC 6DOF check cases](https://www.nasa.gov/centers-and-facilities/nesc/6dof-check-cases/) | [baseline and scope](baseline-and-scope.md) |
| [NXP MC3PHAC application note, regeneration control and resistive braking](https://www.nxp.com/docs/en/application-note/AN2988.pdf) | [electric edf](domains/electric-edf.md) |
| [O.S. FS-64V manufacturer specification](https://www.os-engines.co.jp/english/line_up/engine/air/single/catalog/3AY00.html) | [combustion turbine](domains/combustion-turbine.md) |
| [Scorpion manufacturer bench table](https://www.scorpionsystem.com/files/i2%2C653_data_chart.htm) | [electric edf](domains/electric-edf.md) |
| [Manufacturer sheet archive](https://www.vrhc.co.uk/images/RC_Helicopters/USA/Miniature_Aircraft/X-Cell/Instruction_upgrades.pdf) | [helicopter](domains/helicopter.md) |
| [NASA Glenn, general thrust equation](https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/thrust-force/) | [combustion turbine](domains/combustion-turbine.md), [electric edf](domains/electric-edf.md) |
