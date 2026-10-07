# H10 — Load-contributor extraction decision

2026-10-06 · **Status: assessed; conditional extraction not triggered.** Main-line ROADMAP H10.

The concrete consumers still fit the existing interfaces: FlightSession evaluates `Dynamics.loads` plus gear forces; trim and linearization use the same dynamics path; aircraft-specific shaft/turbine and tail-slipstream choices remain explicit data options. H8 state ownership and H9 replay do not require another load-contributor abstraction.

The performance investigation targets redundant calculations inside these existing evaluators. Moving the same calculations behind a generic contributor interface would not remove that duplication and would introduce dispatch/configuration work without a demonstrated consumer. Keep the current shared evaluator. This resolves the conditional decision; it does not claim a new interface was implemented or measured.

Reopen H10 when a real second implementation cannot express its loads through Dynamics without duplicating the force/moment assembly, or when a demonstrated coupling prevents isolated testing. Name the blocked consumer, extract the smallest seam, retain the existing oracle and measure numerical agreement and overhead then.

Sources: [Dynamics](../../../../app/physics/dynamics.gd), [FlightSession](../../../../app/sim/flight_session.gd), [trim](../../../../app/physics/trim.gd), [linearization](../../../../app/physics/linearize.gd), [H4/H5 evidence](../H4-H5/README.md). Repository MIT analysis.

Commit message: `H10: record that current load consumers do not trigger interface extraction`
