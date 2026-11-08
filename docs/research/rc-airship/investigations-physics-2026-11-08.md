# RC airship investigations I01–I08

**Date:** 2026-11-08. Read against [the 5 m generic blimp plan](../../plans/rc-airship.md) and [earlier physics research](physics-2026-11-08.md), at observed repository HEAD `4bda2e4540fc07ebe8eb63d35072fd5aead39cbe`. These are proposed plan changes, not implemented or physically validated behavior. The 5 m length is user-specified; diameter, shape, mass, fill and hardware are not. All example numbers below are illustrative calculations, not aircraft specifications.

## I01 — How sensitive is the lift budget to unknown shape?

**Question.** Is one maximum diameter enough to establish the generic airship's usable lift?

**Method and source.** Independently integrated an illustrative prolate ellipsoid and compared the method with [Abbott, NACA TR-394](https://digital.library.unt.edu/ark:/67531/metadc66051/m2/1/high_res_d/19930091467.pdf), apparatus and Table III, which reports volumes and CB positions for actual tested hull profiles. For an axis `x`, the general displaced volume is `V = ∫ A(x) dx`; an ellipsoid gives `V = pi L D² / 6` only for its specific profile.

**Finding.** At `L = 5 m`, `D = 1.8 m` gives 8.482 m³. If only the assumed diameter changes by ±0.1 m, the volumes are 7.566 and 9.451 m³: −10.8% and +11.4%, respectively. With the plan's illustrative densities 1.225 and 0.169 kg/m³, non-gas mass allowance spans 7.990–9.980 kg, roughly a 2 kg spread before envelope, equipment or ballast. Equal length and maximum diameter still do not fix volume or CB: taper, nose/tail shape and section width/height matter. This is a sensitivity calculation, not a measured operating envelope.

**Plan change.** At BL-01/02, retain independent length, width, height and section/shape uncertainties; calculate volume and CB from a closed envelope-only proxy or measured cross-sections, and propagate their correlated uncertainty into net lift and trim. Keep visual mesh bounds, gas volume and displaced volume distinct.

**Discriminator/acceptance.** Integrate two profiles with identical length and maximum width but different taper and show that the reported volume and longitudinal CB differ; check the ellipsoid against the exact expression above. Admit a specific lift budget only with its inputs and uncertainty. The actual envelope geometry and fill remain unavailable.

## I02 — What thermodynamics are consistent with the admitted fill?

**Question.** Can the same constant-volume law describe a fully taut sealed envelope and an underfilled compliant balloon, and what do ambient conditions change?

**Method and source.** Applied the ideal mixture law in [NOAA's flux handbook, Appendix A1](https://downloads.psl.noaa.gov/psd3/cruises/VOCALS_2008/RHB/Fairall-Revised-TM-4-23-07.pdf), its saturation-pressure expression, and the separate balloon modes in [NASA's Scientific Balloon FAQs](https://www.nasa.gov/scientificballoons/faqs/). [NASA's buoyancy derivation](https://www.grc.nasa.gov/WWW/K-12/WindTunnel/Activities/buoy_Archimedes) relates lift to the ambient hydrostatic pressure gradient.

**Finding.** For fixed `m_g`, `V` and gas temperature, sealed gas pressure follows `p_g V = n R T`; a rising external pressure difference may exceed membrane limits. A partially filled, freely expanding ideal envelope has approximately ambient gas pressure and `V ∝ T_g/p_g`, only until its shape/volume or pressure limit is reached. Under pure-gas, isothermal, pressure-equilibrated conditions, changing pressure expands/contracts the gas while displaced-air mass approximately cancels that pressure dependence; this is not the sealed fixed-volume result.

For the I01 8.482 m³ example at 20 °C and 101325 Pa, ideal dry air is 1.204 kg/m³ and helium 0.166 kg/m³. At 50% relative humidity, the displaced-air mass is about **45 g less**. If gas is 95% helium by mole with air as the remaining 5%, its non-gas support allowance falls from about 8.80 to 8.36 kg. At the hypothetical same temperature, lowering ambient pressure to 89874 Pa reduces displaced-air mass by 1.15 kg for fixed volume and gas mass, but would also create about 11.45 kPa internal overpressure if starting at equal pressure. The pressure is a [standard-atmosphere 1 km reference](https://ntrs.nasa.gov/api/citations/19930090991/downloads/19930090991.pdf), not a real site's temperature or weather.

**Plan change and discriminator.** BL-02 must name the fill regime, admissible pressure/shape range and gas composition; BL-16 needs conservation and regime transitions before dynamic fill. Treat pressure and density as representative constant *property inputs* in the first release while retaining the implicit hydrostatic gradient behind `B = rho V g`: literally uniform static pressure gives no buoyancy. At the above density the gradient is about 11.8 Pa per vertical metre. Test mass conservation and the two limiting laws separately; the membrane tolerance, altitude and purity of the target remain unknown.

## I03 — Which oscillation does a free blimp actually measure?

**Question.** Can the CB–CG pendulum period alone identify the craft's pitch inertia?

**Method and source.** Reduced the coupled 6-DOF mass matrix to a small-angle horizontal/rotational two-coordinate model and compared its structure with [Tao et al., 2020, Eq. 17 and §III](https://par.nsf.gov/servlets/purl/10212088), which explicitly couples translation and pitch for a miniature blimp.

**Finding.** For a neutral symmetric body in still air, CB–CG vertical separation `d`, physical mass `m`, horizontal added mass `a_x`, actual CG pitch inertia plus added pitch inertia about CB `I_0`, no drag and small tilt, the CB-fixed pitch inertia is `I_fixed = I_0 + m d²`. For a freely translating release with zero initial horizontal momentum, eliminating translation gives `I_free = I_0 + m d² - (m d)² / (m + a_x)`, and `omega_free² = m g d / I_free`. Signs of cross terms depend on the axes; the squared correction does not. For a purely synthetic `m=10 kg`, `d=0.2 m`, `a_x=5 kg`, `I_0=0.5 kg m²`, the constrained period is about **19% longer** than the free period. It is not a predicted target response. Drag, finite angles, horizontal CG offset and non-diagonal added inertia change the result.

**Plan change.** BL-04 and BL-T01/03 should distinguish a free, tracked release from a constrained pendulum; fit translation and attitude jointly. Record the constraint and measurement datum. Separately determine physical mass and ballast displacement before interpreting apparent inertia or damping.

**Discriminator/acceptance.** Under the stated ideal assumptions, independently compare constrained and free numerical modes to both formulas and verify the horizontal-momentum constraint. In a real test, repeat at two known ballast offsets and use held-out oscillations; no inference of separate inertia, added mass and damping is valid from one period alone. No target measurements exist.

## I04 — Do the full added-mass signs survive a datum shift?

**Question.** Does the prior report's restricted 6-DOF formulation agree with the source, and what fails if inertia is moved without its coupling?

**Method and source.** Re-read [Peddiraju, Liesk and Nahon 2009, Eqs. 11, 23–25](https://citeseerx.ist.psu.edu/document?doi=dcae888ebecf2d93e3badeafa68cad9869ad424f&repid=rep1&type=pdf) in the indexed full-text copy, then compared [Liesk 2010, Eqs. 5–8](https://www.researchgate.net/publication/269217692_Integral_backstepping_control_of_an_unmanned_unstable_fin-less_airship), and independently checked kinetic energy, reference shifts and frame limits. Direct fresh access to the 2009 PDF returned HTTP 403; the search-indexed source text and 2010 author-posted text were available. The second source shares an author and is corroboration, not an independent experimental derivation.

**Finding.** With `C a = c × a`, `c = CB→CG`, the source's symmetric-envelope matrix at CB is `M_CB = [[mI+A, -mC], [mC, J_CB+J_A]]`. The source uses world-to-body rotation; the prior report uses its transpose, body-to-world. Their wind and transport terms agree after that translation. Liesk writes the Munk matrix as `A + rho V I` whereas Peddiraju uses `A`; the difference vanishes exactly because `u × (rho V I u) = 0`.

For `v_CB = v_CG + C omega`, define `H = [[I,C],[0,I]]`; then `M_CG = Hᵀ M_CB H` and `tau_CG = Hᵀ tau_CB`. The added-air part acquires off-diagonal `A C` and `−C A` blocks. Dropping them at CG changes kinetic energy. A manufactured calm-air case with `m=10`, `c=(0,0,-0.2)`, `A=diag(1,5,5)`, `J_A=diag(0.1,0.2,0.2)`, `J_CG=diag(0.5,0.5,0.7)`, `v_CB=(0.1,0,0.05)` and `omega=(0,1,0)` has generalized kinetic energy **0.42375 J** at either datum. This is an analytic fixture, not a blimp parameter set.

**Plan change and discriminator.** Add this congruence, wrench/velocity shift, frame transport and positive-energy fixture to BL-03, with scaled matrix conditioning and explicit symmetric-added-matrix validation. Test zero added mass, zero velocity, nonzero rotation and nonzero offset. General asymmetric hull coupling, spatial wind, flexible gas and a separate independent full numerical transcription remain unverified; passing the fixture is software evidence only.

## I05 — What Reynolds numbers should the 5 m plan actually use?

**Question.** Is it accurate to call every part of a five-metre blimp a low-Reynolds-number vehicle?

**Method and source.** Calculated `Re = U L_ref / nu` with an illustrative `nu = 1.5×10⁻⁵ m²/s`, consistent in order with [NASA's temperature-dependent air-viscosity relation](https://www.grc.nasa.gov/www/BGH/viscosity.html). Inspected [Abbott TR-394, pp. 583–584 and figures 18/20](https://digital.library.unt.edu/ark:/67531/metadc66051/m2/1/high_res_d/19930091467.pdf): its model tests span approximately 10⁶–4×10⁷ in hull-length Reynolds number and compare surface finish, appendages and tunnel turbulence.

**Finding.** At assumed relative speeds 0.5, 1 and 3 m/s, a 5 m hull has `Re_L ≈ 0.17, 0.33 and 1.0 million`; an illustrative 0.30 m fin chord simultaneously has `Re_c ≈ 10,000, 20,000 and 60,000`. A hypothetical 0.254 m propeller at 3000 rpm and 0.025 m chord at 75% radius has rotational-chord `Re ≈ 50,000`, excluding axial inflow. None of those speeds, chord lengths or RPMs is known for the target. Similarity at the hull length does not guarantee similarity of fin separation or propeller sections. At unchanged coefficient and area, drag varies as speed squared; a threefold speed gives ninefold drag, but the coefficient can itself vary with Reynolds number, roughness and angle.

**Plan change.** BL-02/05/06 should record separately the hull-length, fin-chord and blade-section Reynolds domains and surface condition. Abbott's tested fins and cars added 15–20% of bare-hull drag at zero pitch at its larger test Reynolds numbers; this shows that installations matter, not that 15–20% applies here.

**Discriminator/acceptance.** Evaluate displayed Reynolds numbers from each component's own local airspeed and dimensions, reproduce the arithmetic above, and reject silent extrapolation outside data coverage. Measurements of hull seams, fin shape and installed flow remain open.

## I06 — How are Munk moment and fin stability counted once?

**Question.** Can a bare-hull moment table, added-mass dynamics and tail-fin law be summed without qualification?

**Method and source.** Compared [Peddiraju 2009, Eqs. 23 and 27–31](https://citeseerx.ist.psu.edu/document?doi=dcae888ebecf2d93e3badeafa68cad9869ad424f&repid=rep1&type=pdf), including its explicit removal of the duplicated potential-flow moment, against [Yamasaki and Goto 2003, §2](https://www.jstage.jst.go.jp/article/tjsass/46/153/46_153_195/_pdf) and [Abbott TR-394, Fig. 16](https://digital.library.unt.edu/ark:/67531/metadc66051/m2/1/high_res_d/19930091467.pdf). The latter compares tested bare and fitted hulls; Sky Probe-J's low-speed fins were in its particular hull wake.

**Finding.** For diagonal translational added mass `A=diag(a_x,a_y,a_z)` and relative flow `(u_x,u_y,0)`, the source's yaw component from `−u × A u` is `−(a_y−a_x)u_x u_y`; it is zero for isotropic `A` or zero incidence, and generally nonzero for an elongated body. It is already present in the coupled dynamics. A whole-hull empirical moment can contain that same effect, while its residual may also include separation and viscosity. Removing an assumed ideal term from a total table is only defensible within that table's domain and chosen convention.

With zero **local** flow, an ordinary unblown fin produces no aerodynamic control force; rotation, crosswind or propwash can produce local flow even at zero ground speed. Reverse direction and a hull wake invalidate a universal forward small-angle slope. The measured 5.48 m example does not prove all 5 m blimp fins lack authority.

**Plan change and discriminator.** BL-05 must declare whether the hull table is total or residual, its datum, and how any ideal Munk contribution is removed. Test isotropic and asymmetric synthetic `A`, a table with a deliberately included potential term, and unblown versus locally blown fins, including reverse. Target-specific fin/wake coverage and nonlinear derivatives remain unmeasured.

## I07 — Which wind derivative is admissible first?

**Question.** Is sampling a wind velocity at each RK stage enough for a buoyant body in gusts or shear?

**Method and source.** Rechecked [Peddiraju 2009, Eqs. 3–11 and 23–25](https://citeseerx.ist.psu.edu/document?doi=dcae888ebecf2d93e3badeafa68cad9869ad424f&repid=rep1&type=pdf), [Liesk 2010, Eq. 6](https://www.researchgate.net/publication/269217692_Integral_backstepping_control_of_an_unmanned_unstable_fin-less_airship) and the independent potential-flow sphere in [Brennen, §§5.6–5.7](https://media.library.caltech.edu/CaltechBOOK:1995.001/chap5.htm). Derived a one-axis limiting case and the rigid-frame velocity transport independently.

**Finding.** At zero angular rate in spatially uniform accelerating wind, the source's constant-property model gives `(m+a) v_dot = (rho V+a) w_dot + F_other`. Brennen gives a sphere's ideal added mass as `a = rho V/2`. For an unforced, neutral-density sphere initially moving with uniform, horizontally accelerating air, this yields **body acceleration equal to air acceleration**. Omitting the displaced-fluid pressure-gradient term gives one third of the air acceleration. This is an independent analytical discriminator for a fixed-radius sphere in an unbounded inviscid incompressible fluid, with no drag or horizontal gravity, not a measured gust response or target hull. Buoyancy and ambient acceleration arise from different components of the pressure field; neither should be silently doubled.

In body coordinates, `w_dot_B = −omega × w_B + Rᵀ d(w_W)/dt`. For spatially varying flow, differentiation along the vehicle uses `∂t w + (v_W·∇)w`, whereas fluid material acceleration uses `∂t w + (w_W·∇)w`; they are not interchangeable. A discontinuous gust has no ordinary derivative at its jump.

**Plan change and discriminator.** Admit calm/steady uniform wind first; at BL-14 require a deterministic, stage-pure field returning velocity and the separately defined time derivative/gradient, or a converged pure differentiation adapter. Reject unsupported jumps, rotating/sheared-flow and varying-density cases until separately derived. For a constant inertial boost `U` of both craft and air, compare world acceleration and relative states: with rotation, `Δv_dot,B = −omega × RᵀU`, so raw body derivatives must not be asserted equal. Exercise nonzero yaw rate and checkpoint replay. Spatial gust physics remains unvalidated.

## I08 — What can flight data actually identify, and what is free?

**Question.** Can free-flight tracking alone determine physical mass, added mass, propulsion and damping separately?

**Method and source.** Inspected [Tao et al., §III and Fig. 5](https://par.nsf.gov/servlets/purl/10212088), [Sky Probe-J constrained-flight identification, §§4–5](https://www.jstage.jst.go.jp/article/tjsass/46/153/46_153_195/_pdf), and the [UIUC propeller database, Volume 1](https://m-selig.ae.illinois.edu/props/volume-1/propDB-volume-1.html). Tao used 21 releases per translation axis, 120 Hz tracking, 20 fit datasets and one held out; the papers report their models and figures rather than a matching target blimp's complete input tapes.

**Finding.** In the simplified horizontal equation `(m+a) u_dot = T - d u|u|`, scaling `(m+a)`, `T` and `d` by the same positive factor leaves the velocity trajectory unchanged. One trajectory therefore cannot identify their absolute values. Real constrained tests also measure support compliance and envelope flexibility: Sky Probe-J's authors observed slowly decaying constraint oscillations and added a virtual spring to their identification model. The UIUC collection supplies downloadable, corrected static and wind-tunnel measurements for named propellers and RPMs; use a matched item within its tested domain, not an assumed installed/reverse thrust curve. NACA hull figures and Tao's published fits are comparators or method examples, not measured coefficients or raw recordings for this 5 m model.

**Plan change.** BL-T01–08/BL-13 should prescribe independent mass/ballast/geometry measurements, bench thrust and current at actual voltage, axis-isolated coast/release tests, plus separately excited yaw, pitch, reverse and combined maneuvers. Record time alignment, actual commands, wind and measurement uncertainty. Predeclare calibration, repeatability and held-out trials; examine sensitivity/rank and parameter correlations before claiming each parameter identified.

**Discriminator/acceptance.** Demonstrate the scale ambiguity with the synthetic equation, then break it with independently measured thrust, a known applied force or an effective-mass measurement, and confirm predictions on a different held-out maneuver and ballast state. A known rigid mass alone does not fix this scale ambiguity if the added mass remains free; it is needed to separate physical from effective mass once the latter is identified. No raw target-specific force, wind or six-axis flight dataset has been located; until it exists the result remains a generic engineering estimate.
