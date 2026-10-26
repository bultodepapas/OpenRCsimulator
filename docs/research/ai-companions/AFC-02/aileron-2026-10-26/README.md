# AFC-02 — Current-source qualification after D11-R1 / D6e-R5

2026-10-26. The revised Stik data and current source pass the existing narrow
companion circuit gates on Godot `4.8.beta1.official.4d10419ca`. No controller,
route, gate, population, weather or activity is broadened.

The [pilot matrix](scenario_metrics.csv) passes **148 checks, zero failures**:
six calm/gentle-practice cases, 1–3 aircraft, 28,800 ticks each. Both three-aircraft
calm repeats finish and are bit-identical in the sampled states and commands.
Maximum radial error is 4.047822 m (gate 40 m); minimum terrain clearance is
34.310643 m (gate 20 m). [One-second samples](flight_samples_1hz.csv) and
[checked output](matrix.log) retain the results.

The [production manager check](production.json) also completes 28,800 ticks with
three companions, the real Club collision inventory and lake context, seed 1,
with minimum clearance 34.567785 m. Admission was staged in a disposable app copy
before updating accepted profile pins. [Output](production.log).

[Source identity](source-identity.json) binds the normalized physics/sim/failures
files, corrected aircraft bytes and committed source revision. The pre-task
source already disagreed with the old `5df257b3` solver pin; its old accepted
revision was absent locally. This is a **new current-source qualification**, not
a claim of parity with that unavailable source or the old 4.7.2 encounter tapes.
The unchanged pilot/field scope is retained, and field observations are refreshed
from the new matrix CSV. Current player input defaults do not reshape the
companions' technical full-rate sessions.

These checks do not establish physical realism, encounter-wide tape equivalence,
target-hardware performance or long-session resource stability. Parent repair:
[D11-R1 / D6e-R5](../../../aero-consistency/D11-R1/README.md).

The renewed profile, pilot, manager, airspace and recording regression groups all pass, as do the companion rebind tool tests. Their logs and [artifact manifest](manifest.json) are retained here.
