# EL1a-R2 — Twelve implementation investigations for electric propulsion

2026-10-10 · **Status: research and isolated tool verification complete; incorporated into Electric Propulsion Plan revision 3.** Step prefix: EL. No application physics, aircraft data, or runtime dependencies changed in this round.

The owner requested at least ten Internet investigations focused on code, Godot, tools, theory, and physics. These twelve complement [R1's hardware and measurement research](../EL1a-R1/README.md). Each question connects inspected primary sources to existing code, an implementation decision, and a rejecting test. Source facts, local observations, derivations, and proposed tests are identified separately. The [owning plan](../../../ELECTRIC-PROPULSION-PLAN.md) remains the source of step status; this research does not close EL1 integration.

## Questions, code, and acceptance

| # | Investigation / primary basis | Concrete plan change and rejecting evidence |
| --- | --- | --- |
| 01 | [Clock, catch-up, input and pause](01-godot-runtime.md#01--who-owns-the-240-hz-clock-and-what-happens-during-a-hitch) — Godot Node/Engine | Keep `Simulation._physics_process` as the single clock; input precedes it. Electric 30/60/144 FPS, pause and hitch checks; no second accumulator. EL1d/e. |
| 02 | [Float64 and render boundaries](01-godot-runtime.md#02--which-values-stay-double-precision-at-godot-boundaries) — Godot float/packed arrays/Vector3 | Keep scalar doubles and detached `PackedFloat64Array` state; never feed render transforms back into physics. Precision and checkpoint fixtures. EL1b/d. |
| 03 | [Profiling and native-code threshold](01-godot-runtime.md#03--when-does-profiling-justify-native-code-for-electric-flight) — Godot CPU optimization | Extend whole-session fleet benchmarks with warm-up and defined distributions; retain 500 µs/tick target and fingerprints. No native rewrite based on kernel timing. EL1d/e, Gate P. |
| 04 | [Schema/loader branch parity](02-data-state.md#04--can-the-electric-branch-be-strict-in-both-schema-and-loader) — JSON Schema 2020-12 / Godot JSON | Replace the turbine/else-glow fork with explicit electric dispatch; close only new electric objects, preserving legacy inputs. Valid/invalid parity, units, overflow and mixed-field probes. EL1b. |
| 05 | [Multiple sessions and ownership](02-data-state.md#05--which-state-may-be-shared-by-multiple-aircraft-sessions) — Godot Dictionary/Resource | Definition data stays immutable; battery/controller state belongs to each simulation. Advance one of two same-model sessions and prove the other unchanged. EL1b, EL2/3. |
| 06 | [Checkpoint identity and precision](02-data-state.md#06--what-makes-an-electric-checkpoint-identifiable-and-restorable) — Godot native serialization/JSON/FileAccess | Extend versioned state/identity, preserving exact input-file SHA separately from legacy normalized digest. Fresh-session continuation, mutation, layout and rollback checks. EL1d, EL2/3. |
| 07 | [Electrical versus mechanical timescales](03-numerical-physics.md#07--when-is-an-algebraic-motor-current-accurate-enough) — UCSD/Purdue motor equations | Keep averaged algebraic current within a declared bandwidth; the existing RPM exponential does not validate inductance. Bound timesteps/configurations before adding current state. EL1c/d. |
| 08 | [Rotor frame, momentum and work](03-numerical-physics.md#08--how-should-rotor-momentum-body-rate-and-motor-work-be-counted) — NASA equations / G2 derivation | Reuse relative-spin/locked-inertia coupling; independent axial equations reject duplicated reaction torque or an incorrect speed frame. EL1d. |
| 09 | [Interpolation and data coverage](03-numerical-physics.md#09--should-propulsion-and-battery-curves-stay-linear-or-become-pchip) — original monotone interpolation papers, SciPy, UIUC/APC | Keep linear lookup initially, preserve signed Ct/Cp and explicit data gaps/domains. Smoothing cannot supply missing propeller or pack evidence. EL1f, EL2. |
| 10 | [Headless CI and exported data](04-verification-tools.md#10--what-makes-a-headless-or-exported-electric-test-credible) — Godot CLI/export docs | Combine exit/log/completion/timeout gates; prove electric dataset identity and advancing flight in a clean package. Six isolated runner controls executed. EL1b–f. |
| 11 | [Independent numerical references](04-verification-tools.md#11--how-should-an-independent-solver-verify-the-fixed-step-implementation) — SciPy DOP853/Radau/events | Compare real session refinements against separate reference equations; control internal steps and event identity, not just output density. Smooth and event counterexamples executed. EL1d, EL2. |
| 12 | [Calibration and identifiability](04-verification-tools.md#12--can-a-successful-fit-still-leave-the-powertrain-unidentified) — SciPy fitting / NumPy SVD | Require scaled physical sensitivities, independent observations and held-out validation. Synthetic rank-deficient fit demonstrates why optimizer success is insufficient. EL2/5/6. |

## Integration order and scope

**EL1b remains next:** implement and test the explicit schema/loader branch with two synthetic configurations, preserving legacy fleet data and per-session ownership. **EL1c/d** then connect the source to steady trim and the existing coupled stages, followed by zero-speed handling, electrical sampling, checkpoint/replay, and independent numerical comparison. **EL1e/f** prove synthetic flight and packaging before the Timber handoff. **EL2/3/5/6** add measured battery/controller behavior and physical validation. Research tooling does not become an app dependency.

The aircraft reference remains **Turbo Timber Evolution BNF Basic B EFL105250B, 4S 3200 mAh pack class**. No additional sales-ranking, hardware-default, fitted-motor, stock-propeller-map, or flight-accuracy claim is made. [Hardware identity and missing measurements](../EL1a/timber-reference.md)

## Reproduce the bounded tool evidence

Use the repository-pinned Godot. Python research requirements are explicitly pinned in [requirements.txt](../../../../research/propulsion/el1a-r2/requirements.txt): NumPy 1.26.4 and SciPy 1.11.4. They were already installed in the research environment; no dependencies were installed or upgraded. In a new environment, install that file into an isolated virtual environment.

```bash
python3 research/propulsion/el1a-r2/probe_tools.py \
  --godot "$(app/get-godot.sh)" \
  --output /tmp/openrc-el1a-r2-tools.json
```

[Recorded tool evidence](tools-proof.json) includes exact versions, probe and protected-file SHA-256 hashes, diagnostics, solver errors, event times, and sensitivity ranks:

- **Godot 4.7.2:** all six runner cases behave as expected. Only the valid control passes; a runtime error can coexist with exit zero and a completion marker.
- **Numerical reference:** DOP853 and Radau match the analytic smooth fixture within `2.18e-9 rad/s`; a dense output grid still misses events at large internal steps. A root at a shared endpoint can also be reported twice.
- **Parameter fit:** speed-only data admits different resistance/inertia pairs with rank-one sensitivity; adding an independent synthetic resistance observation restores rank two for this fixture.

Broken GDScript probes exist only inside a temporary standalone project, deleted on exit. The script checks that EL1a kernel/test bytes remain unchanged. It neither imports the app nor simulates a Timber flight. [Documentation verification](verification.json) records local links/anchors, the twelve questions, source inventory, file hashes, and whitespace checks. R1's verification remains a historical record of revision 2.

## Limits and source use

The reports use versioned Godot 4.7, JSON Schema Draft 2020-12, SciPy 1.11.4 and NumPy 1.26 references, plus named university, NASA and original numerical-method sources. External works are linked and paraphrased; their text, figures, and datasets are not redistributed. Their publishers' licenses and dataset terms continue to apply; citing an APC/UIUC source does not incorporate or relicense its data. Synthetic experiments are original project fixtures.

No new full-app regression, package smoke, target-machine performance measurement, electric in-flight integration or hardware calibration was performed. Those remain explicit acceptance work in the plan. No GDExtension, new physics clock, schema framework, interpolation library, or inductance state is selected by this research.
