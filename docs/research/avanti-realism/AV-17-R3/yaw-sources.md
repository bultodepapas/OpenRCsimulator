# AV-17-R3 — Rudder feel and yaw-response sources

Reviewed 2026-10-14. Scope is the SebArt Avanti S A200, 2.00 m span / 2.22 m length, with the P100 RX turbine. This is not the Mini, XS, EDF, or Krill airframe. SebArt’s product listing gives these dimensions and identifies the P100 RX as its beginner turbine setup. [Manufacturer listing](https://www.sebart.it/jets-L.html)

## Manufacturer rudder setup

SebArt’s Avanti S Jet 2.2 m manual recommends ±30° rudder at high rate. Its transmitter settings are 80% D/R and 60% Expo for normal/pattern, 100%/80% for start and landing, and 100%/60% for 3D. If D/R scales the stated high-rate throw linearly, normal/pattern maximum rudder is 24° (30° × 0.8); that is a calculation from the recommendation, not a separately specified throw. The manual’s Expo percentages are radio setup guidance, not a universal mathematical curve or an aerodynamic coefficient. A SebArt USA manual copy notes the Expo sign differs between JR and Futaba systems. [SebArt manual, p. 4](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) · [SebArt USA manual](https://www.sebartusa.com/uploads/1/4/3/1/143147227/avanti_s-_manual.pdf)

These settings establish a practical transmitter baseline only. They do not specify yaw-rate damping, Dutch-roll period or damping ratio, rudder-release behavior, or a gamepad transfer curve. I found no published Avanti-specific measured yaw-response time history or stability derivatives.

## What the stability references support

The FAA’s Pilot’s Handbook describes Dutch roll as an out-of-phase coupled yaw-and-roll oscillation and says its damping varies with the aircraft. Static directional stability (the fin’s weathercock response to sideslip) and dynamic yaw damping are separate parts of the response; lateral stability and rate effects determine how yaw couples into roll. [FAA PHAK, chapter 5](https://www.faa.gov/sites/faa.gov/files/07_phak_ch5_0.pdf)

Primary NACA/NASA work treats Dutch-roll response using the lateral equations of motion and measures directional stability after vertical-tail changes. A later NASA wind-tunnel study explicitly distinguishes (C_{n_\beta}) (static directional stability) from (C_{n_r}) (yaw damping), and reports that vertical-tail damage affected both while sideslip also produced rolling motion through effective dihedral. These studies support the mechanisms, not numerical transfer to this RC jet: the configurations are full-size aircraft or transport models, not the Avanti. [NACA-TN-3754](https://ntrs.nasa.gov/citations/19930084655) · [NACA-TR-973 flight investigation](https://ntrs.nasa.gov/citations/19930092035) · [NASA vertical-tail wind-tunnel study](https://ntrs.nasa.gov/api/citations/20080034656/downloads/20080034656.pdf)

## Current model provenance and limits

The AV-06 generator derives fin sideforce and (C_{n_\beta}) from estimated fin slope, area, and lever arm (`research/avanti-s/av06/derive_physics.py:513–534`). It derives (C_{n_r}) from the fin term plus an assumed wing-profile term and a stated −0.02 estimated fuselage term (`:532`, `:671`). It explicitly omits fuselage (C_{n_\beta}) under the current data contract (`:521–523`, `:669`). These are geometry-based estimates, not Avanti measurements.

At runtime, `app/physics/aero.gd` computes local surface flow using body angular rates and each surface’s moment arm, then accumulates force and moment. `app/tests/test_yaw_damping.gd` checks consistency between those local loads and the model’s fin-based estimate; that test does not validate the Avanti against measured flight data. No Avanti-specific (C_{n_r}), Dutch-roll time history, or gamepad rudder policy was found in manufacturer material.

## Use for the “rebound” report

Treat short-stick gamepad sensitivity as input mapping: a smaller gamepad rudder gain, centered Expo curve, and calibrated deadzone can improve thumb control while leaving the aircraft’s yaw dynamics unchanged. Do not map “60% Expo” directly to a simulator parameter without matching the radio’s curve convention. After shaping, the same commanded rudder angle should produce the same aircraft response across controller types.

To distinguish input rebound from airframe response, inspect a short release trace of commanded rudder, yaw rate, sideslip, and bank. A command that reverses or oscillates as the stick returns to center points to controller mapping/filtering. With rudder command at zero, a decaying yaw/roll oscillation is airframe response and should be assessed through the lateral-directional derivatives and geometry. The cited evidence does not support adding a blanket yaw damper; a yaw damper is feedback control that uses sensed motion to command rudder, not a substitute for calibrated natural damping.
