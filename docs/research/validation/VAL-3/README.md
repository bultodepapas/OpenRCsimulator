# VAL-3 — Reproducible modal comparisons

**Status:** ✅ implemented and verified, 2026-10-07. Scope: offline research tooling; M2 and the running simulator are unchanged. This does not close Gate 2 or validate the owner's airplane.

[Dashboard](../../../../research/validation/dashboard.md) · [Contract and commands](../../../../research/validation/README.md) · [Snapshot](../../../../research/validation/snapshot.json) · [Tests](../../../../research/validation/test_dashboard.py)

## Result and interpretation

Ten rows compare the current Stik modes with two related airframes. One frequency is inside its estimated band, five frequency/rate comparisons are outside, and four damping rows have no assigned band. These are diagnostic screens (frequency ±15%, roll rate ±10%), not source error bars or accepted RC tolerances. Unknown uncertainty and tuning history remain explicit.

| Roll decay rate | Baseline sim/reference | Clp × 2 sim/reference | Result |
| --- | ---: | ---: | --- |
| US120, inherited scaled reference | 2.074 | 4.152 | Already outside; discrepancy increases |
| 25e, reduced at equal nominal CL | 2.374 | 4.729 | Already outside; discrepancy increases |

The original roadmap proof said Clp × 2 would turn both real roll rows red. That precondition is false: they were already red. The implementation tests the real worsening discrepancy and separately proves green-to-red classification with a synthetic matching reference. Neither test edits aircraft data or fits a coefficient.

## Source audit

- **US120:** [Lie, Synthetic Air Data Estimation Method](https://conservancy.umn.edu/server/api/core/bitstreams/3eaa84c3-81fc-41ed-ae56-65f3ea700347/content), Appendix D, printed pp. 85–86: airframe/trim properties checked. Modal numbers are inherited rounded calculations from the repository's D8b investigation, not directly printed measurements. Their matrix extraction and scaling have not been independently reproduced here. Keep them provisional. The retained 13.8 m/s comparison is not a new equal-CL solve.
- **25e:** [Dorobantu et al., System Identification for Small, Low-Cost, Fixed-Wing Unmanned Aircraft](https://dept.aem.umn.edu/~mettler/Courses/AEM%205333%20(spring%202013)/AEM5333%20CourseDropbox/Week%207%20Identification/Ultrastick%20Identification/2012_AIAA_JA_SYSID.pdf), Table 1, section IV and Tables 4–5: geometry, flight condition and identified modes checked. Table 5's roll entry 12.53 is consistent with the lateral matrix's real pole near −12.537 s⁻¹. Its conflicting 0.50 s time constant is not used; the roll interpretation is marked derived.

The existing D11a sensitivity report remains historical evidence. VAL-3 recomputes the current diagonal modal projections, including the tail lag, with controls/engine frozen. It does not remove cross-axis, airfoil, mass/inertia or actuation differences between aircraft.

## Verification

- Python contract/integration suite: malformed references, complete row/airframe roster, dimensional normalization, inclusive band limits, unstable mode classification, unknown evidence flags, stale/tampered reports, engine failures, timeouts, concurrent source edits and failed replacement preserving the old file.
- Actual pinned Godot: nine 15 m/s mode values checked against the existing software regression; ten comparison rows; equal nominal CL; baseline and doubled-Clp runs; unchanged model/source hashes. Synthetic green-to-red proof is separate from physical evidence.
- `dashboard.py --check` recomputes samples and checks both generated artifacts. Scientific red rows do not fail this check.

Recorded command outcomes and the in-memory mutation values are in [verification.json](verification.json). Re-run the commands from the tooling README after a deliberate physics/reference change. Source corrections invalidate the hashes but still require a human to review and update inherited reference values before regeneration.
