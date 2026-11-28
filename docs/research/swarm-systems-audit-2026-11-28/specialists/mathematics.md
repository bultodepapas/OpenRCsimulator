# Mathematical review of moving water and oblique race-gate crossings

Production revision `8d4169f8febfd7d78a028eaa817414217a54f24b`. Both investigations use float64 positions and a 1/240 s tick. The checked engine was Godot `4.8.beta2.official.cafc17a19`. The paths are prescribed, so the observations qualify the collision and scoring queries, independent of vehicle integration. No FPS, pilot-impact frequency or native-backend result was measured.

## Moving water can enter and leave an aircraft probe between negative samples

**Confirmed collision defect, P2.** With the two wave components and polygons from the shipped lake, the full-tick query returned no event for the stock Avanti hull and extended gear. Its right main gear penetrated the moving surface by 0.100 mm. Checking the first half of exactly the same motion selected that gear and produced the normal terminal water event. This is an executed detector result using stock geometry and a constructed pose, rather than a recorded flight. The existing CR-AUD-34 correction computes the normal speed of a detected moving-interface contact. Here the detector never publishes a contact for the full chord.

The prescribed rigid body translates 0.24 m at 57.6 m/s, heading −120° with 3° roll and constant altitude. Its lowest point passes through north 106.6487798441 m, east 128.0210815711 m and down 0.395100 m at the middle of tick 1. The location sets each stock phase to π/2 modulo 2π. Both crests coincide there. The point is 23.38 m inside the shoreline, so the wave amplitudes are constant over the chord. The reference surface is 0.395000 m down at the midpoint and 0.395194763 m down at either endpoint. At the endpoints the probe clears the surface by 94.763 µm. Each clearance exceeds the configured contact tolerance by a factor of 947.

The actual signed penetration of this straight point path is

\[
g(f)=0.3951-0.45+0.03\cos(\omega_1 T(f-1/2))+0.025\cos(\omega_2 T(f-1/2)),
\]

with \(T=1/240\), \(\omega_1=-22.6435239014\) and \(\omega_2=-54.5702719339\) rad/s. The independent oracle computes both phase rates directly from the shipped file and the prescribed velocity. The positive interval spans tick fractions 0.141805272 to 0.858194728. Over each half the penetration varies monotonically, giving one entry and one exit.

The production subdivision rule chooses one interval. Its sample tests both ends, sees neither reach the detection threshold and returns a clean miss. Bisection runs only after a qualifying sample. Splitting the prescribed motion at the midpoint supplies a known-penetrating endpoint. That control located first entry at fraction 0.141805291 on the point sweep and 0.141803503 on the aircraft detector, which applies a small rotational padding even for fixed attitude. The clear-throughout and wet-at-start controls also passed. The two half intervals are diagnostic detector queries and do not change the simulation's fixed timestep.

Source locations are `app/data/fields/lake.json:58–68`, `app/physics/lake_surface.gd:241–265,452–467,521–534`, `app/sim/lake_collision.gd:154–160,183–197,224–230` and `app/sim/flight_session.gd:4078–4094`. Probe `lake_crest.gd` passed 12 checks, including the public first-hit function for the stock Avanti. Its measured midpoint immersion exceeds the 0.1 µm contact tolerance by a factor of 1,000. The incidence of similar two-root contacts in ordinary flight remains unmeasured.

**Repair direction.** Establish a one-sided upper bound on signed penetration before pruning an interval with two clear endpoints. For constant-amplitude wave components on a linear chord, a usable interpolation envelope is \(\Delta t^2\sum_j A_j\omega_j^2/8\). Where shore fade varies, include its variation or use a separately conservative amplitude bound. Split any unresolved interval earliest-first, retaining the existing root tolerance. Give budget exhaustion an explicit result. Test the stock case, known misses, monotone entries and one/two-wave shore cases. A single additional midpoint sample fixes this example without certifying arbitrary phases.

## An oblique race-gate chord can overstate the physical aperture certainty

**Quantified limitation of the declared chord policy.** The practice-oval race director awarded the first gate to a prescribed chord whose point trajectory crossed 0.334335 mm outside the aperture. Its named rule scores accepted chords. The decision record already acknowledges near-grazing curved-path limits. The fresh result is a counterexample to using the synchronous chord-error band as a physical aperture margin, even when the acceleration bound holds throughout the whole tick. It establishes no scoring-rule violation or recorded racing incident.

Let \(s=t-T/2\) for one 240 Hz tick. In gate-local metres take \(n(s)=2s+25(s^2-T^2/4)\), \(u(s)=1.49925+20s\), with zero vertical offset. Normal velocity rises from 1.895833 to 2.104167 m/s, so forward crossing is unique. True acceleration is constantly 50 m/s², below the 250 m/s² envelope. The chord satisfies the 1 m/s normal-speed gate and crosses 0.750000 mm inside the 1.5 m half aperture. The production band is only 0.542535 mm. The actual root occurs 54.216729 µs later, during which the tangential velocity of 20 m/s adds 1.084335 mm. The point crosses at 1.500334335 m.

The pinned director awarded both this chord and a straight trajectory with the same endpoints. Removing tangential velocity or moving sufficiently far inside restores agreement. Reversing the tangential velocity and placing the chord 0.750 mm outside reverses the disagreement. The low-normal-speed and edge-band controls remained unresolved as intended. All seven checked signatures passed. Source locations are `app/sim/race/gate_crossing.gd:22–24,43–56,67–71`, `app/sim/race/race_director.gd:282–295,311–325`, `app/sim/race/race_model.gd:313–321` and `app/sim/race/track.gd:66–69`. The governing decision is `docs/DECISIONS.md:230`.

**Options for a future ruleset.** For a genuine vector acceleration bound, suppose the true point differs from the chord at the same time by a vector \(e\), with \(\|e\|\le\epsilon=A T^2/8\). At a true plane crossing the chord-time shift contributes a tangential displacement. The resulting one-axis error is \(e_u-(v_u/v_n)e_n\), at most \(\epsilon\sqrt{1+(v_u/v_n)^2}\). The production example gives a sufficient 5.452406 mm horizontal half-band under that assumption. The existing endpoint velocity-difference check alone cannot prove a bound on instantaneous acceleration. Retaining the explicit chord rule with its documented interpretation is also coherent. A ruleset change would require appropriate race identity and record compatibility treatment.

Run `python3 numerical_oracles.py /path/to/OpenRCsimulator` for the independent numerical results. The Python script reads the production lake data and obtains the midpoint from a two-equation phase intersection.
