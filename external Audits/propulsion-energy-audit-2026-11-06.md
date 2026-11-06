# Propulsion and energy audit — 2026-11-06

## Confirmed: a fuel event can erase a pre-exhaustion glow firing from the accepted count

**Scope and consequence.** A stock finite-fuel 55AX Stik can complete a 240 Hz flight tick in which a crank opportunity occurs while the engine is still burning, but the accepted `fire_count` does not increase. Its trace derives `glow_fire_events` from that counter (`app/sim/trace.gd:1464` and `:1647`); the audio voice also consumes the accepted opportunity and fire counters (`app/audio/glow_voice.gd:208`–`:241`). This is a lifecycle/counter error. It does **not** establish that continuous shaft torque, fuel mass, aircraft trajectory, or an audible waveform is wrong in this witness.

**Cause.** `app/physics/glow/flight.gd:321`–`:344` transitions the main tank to a stopped, starved source on exhaustion. `GlowFlight.step` first integrates and locates that event (`app/physics/glow/flight.gd:717`–`:723`), then evaluates only the end-of-tick source and passes its `firing_fraction` to `Life.accepted_prepared` or `Life.accepted` for the entire tick (`:734`–`:743`). The stopped source's firing fraction is zero (`app/physics/glow/lifecycle.gd:324`–`:328`). The lifecycle then applies that single value to each opportunity over the entire tick (`:487`–`:515`), including opportunities that preceded the stop.

**Production-session witness.** `audit_glow_fill_fire.gd` uses the stock `stik_glow_55ax_2t` aircraft, public `set_fuel_start_fill()` and `reset()`, and two normal `Simulation.step()` calls; it does not inject phase, RPM, fuel state, or an event. At the selected accepted fill `0.01428833552836` of the 0.299922 kg / 350 mL tank, the launch contains approximately 0.00428538616834 kg (5.000917435 mL), of which 0.0042846 kg (5 mL) is the specified unusable residue. Thus only 0.000000786168 kg of usable fuel remains. This is deliberately just above the API's minimum, not a claim about an ordinary Home-menu fill.

At tick 1, phase advances from 0 to 0.5629616301 revolutions. At tick 2, phase advances to 0.1258863845, the opportunity counter increases by 1, the firing counter increases by **0**, and the engine stops for fuel exhaustion without a simulator fault. Tick 2 begins at 0.0041666667 s with firing fraction 1.0 and chemical power 1076.67 W; it accumulates 3.984254 J of chemical work. A speed-interpolation estimate puts the opportunity at 0.0074020 s; the located exhaustion event is reported at 0.0081907 s. No natural, long-duration full-tank flight was run, and this comparison of event order is not an independent qualification of exact fuel-event timing.

**Discriminating control.** `audit_glow_event_fire.gd` takes an independently constructed, valid state of the same stock installation: 8113.948 relative RPM, phase 0.9, firing fraction 1.0, with a small amount of usable fuel. One full production 240 Hz `GlowFlight.step` reports one opportunity and zero fires. Two 480 Hz half steps from the same state report one opportunity and one fire. The opportunity is already recorded on the event-free first half; at its endpoint (2.0833 ms), firing fraction remains 1.0 and chemical power is 1101.82 W. A phase/speed estimate places the opportunity at 0.7395 ms, before the fuel event in either path. Each path records approximately 3.679 J of chemical work. This observed counter difference is not inferred from the separate prior fuel-boundary-rounding issue.

The same probe then runs the **identical bounded continuous candidate** through the production lifecycle acceptance function twice, changing only its `firing_fraction` argument from the stopped endpoint's 0 to the pre-event sample's 1. Fire count changes from 0 to 1; all non-counter lifecycle fields and the bounded input bytes remain identical. Substituting the initial sample is a *diagnostic*, not a general repair: it could create fires after an earlier stop or misrepresent changing firing fractions.

**Suggested correction.** Account for crank opportunities on their actual accepted event segments, applying the source/running state and an appropriately defined firing fraction at each opportunity; carry the deterministic accumulator across segments and stop awarding fires after fuel starvation. Preserve the already accepted continuous solution and transactional rollback. Add cases for an opportunity before, at, and after fuel loss; multiple opportunities if allowed; and an event-free control. Establish expected tie ordering explicitly. Do not merely replace the endpoint fraction with the initial fraction.

**Evidence and limits.** The following checked-runner receipts all report `ok: true`, zero engine errors, and their required completion markers:

- `checks/glow-fill-fire-final-2b57tyi5/{report.json,engine.log}` — public-API reset and real session ticks.
- `checks/glow-event-fire-isolation-eusbtkbz/{report.json,engine.log}` — constructed-state split-step and identical-candidate counter controls.
- `checks/energy-import-cifyj0rq/{report.json,engine.log}` — isolated project import; two unrelated CSV translation-import warnings, no errors.

The earlier `roll-power-8_iqjz9_` receipt is a **failed diagnostic draft** with unsupported formatting in its probe; the corrected rerun is identified below. All probes and logs are retained. The existing fuel-boundary-rounding finding is excluded from this result.

## Separately observed, disclosed model limitation — not a new headline defect

For the stock Extra glow installation, `audit_propeller_roll.gd` constructs an accepted stopped-source stage with zero hub-relative flow, 30 RPM relative shaft speed, and body roll of −400°/s along the shaft. The stage gives +5.777973 µN·m of propeller load torque. The absolute shaft speed is −36.6667 RPM, so summing external body-wrench power and the local torque times relative shaft speed gives **+22.185824 µW** to the mechanical system. A zero-roll control instead gives **−18.152038 µW**. The independent power identities agree to displayed precision, and `checks/roll-power-final-ubv7kj98/{report.json,engine.log}` has `ok: true`.

This is a constructed, very-low-power sample; no actual flown trajectory is demonstrated. The repository explicitly retains a mean axial-propeller/relative-shaft convention and does not resolve blade-by-blade body-rate inflow (`docs/research/glow-engines/NITRO-02/README.md:104`–`:110`). Treat the result as a quantified consequence of that disclosed approximation, not an undisclosed software regression or a physical-calibration result.

## Identity

Reviewed source: `3df2791752fe2c1faad132fcb11febbb0ae788d1`. Godot `4.8.beta2.official.cafc17a19`, Linux x86-64, SHA-256 `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`. Probes use an isolated project copy with a minimal 240 Hz project configuration and isolated XDG paths. Source, parameters, and golden flights were not modified. Software verification is not physical or hardware validation.
