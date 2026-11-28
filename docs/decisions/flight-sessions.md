# Flight session ownership and observation

Scope: the decisions, alternatives and evidence behind flight session ownership and observation. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## Launch from a supported physical initial condition

**UI-06d-R3 / D6e-R4 / X8-07.** Interactive geared aircraft prefer a qualified runway start; supported gearless aircraft use hand launch, with airborne selection still available. Valid, supported saved choices take precedence, and a refused selected start does not silently become another start. The interactive level-flight trim is an operating-point choice separate from the low-level reference trim. Release position, throw speed and trim parameters belong in the implementation/evidence, not a second defaults table. [Runway decision](../research/menu-investigations/UI-06b/README.md#2026-10-16--fleet-runway-default-ui-06d-r3), [hand launch](../research/skywalker-x8/X8-07/README.md), [interactive trim](../research/flight-dynamics/power-climb-2026-10-19/README.md#d6e-r4-every-launch-trimmed-for-50--throttle).

## Distinguish device ownership, input shaping and aircraft mechanics

**D6 / F3 / UI-GP.** Radio and gamepad calibration/readiness are separate from menu navigation and physical servo travel. Device detection does not silently transfer an active flight. Radios retain fresh low-throttle arming and disconnect protection; standard gamepads use verified live-poll readiness rather than the superseded centered-dwell gesture. Device-specific shaping must not become an aircraft force correction. [Controller contract and gates](../plans/controller-support.md), [F3-GP-02-R2](../research/controller-support-2026-10-14/README.md#gamepad-readiness-2026-10-15-f3-gp-02-r2).

**UI-15-UX / D6-UX-01.** Controls setup is a graphical layer over the existing draft, capture and calibration contracts, not a second state machine: every visual (device picture, overlay, Setup assistant) edits only the draft through the screen's own paths, and Save stays transactional. The Setup assistant is offered, never auto-opened, and its Reverse means "opposite to the correct setup" (preset default for gamepads); a radio's directions come only from calibration, so Reverse is locked for radios. The FPV quad gets explicit `arm` and `flight_mode` AUX channels; profiles that armed from the `gear` AUX keep doing so, rather than being migrated. Keyboard keys stay fixed and are shown read-only until keyboard remapping (D6-UX-02) is built. [Plan](../plans/controls-setup-ux.md), [evidence](../research/controls-ux-2026-11-12/README.md#implementation-2026-11-12).

**AV-17-R5 / input.** Flap-to-elevator compensation belongs explicitly to the simulator or the transmitter profile. Preserve simulator ownership for missing fields and non-radio command sources; do not infer a transmitter mix from a device name. Keep compensation before failure/servo mechanics, bind transmitter ownership into checkpoints and record it per interval so replay is independent of live devices. This preserves existing flights while allowing pre-mixed channels without duplicate compensation. [Control contract and evidence](../research/avanti-realism/AV-17-R5/README.md).

**D6-ETX (2026-11-17, owner decision).** An EdgeTX radio is a radio by its USB pair `1209:4F54` unless SDL already reports a known gamepad; family names only choose a draft. Its airplane functions are bound by moving each switch (the OpenRC layout is a recommendation), because CH7/CH8 order and Linux gamepad remapping are not reliable indices. One profile serves airplane and FPV quad: an AUX control may carry one quad channel (`arm`, `flight_mode`) and one airplane channel (`gear`, `flaps`, `smoke`, `rates`), as each EdgeTX model gives a channel its own meaning; two channels of one vehicle never share a control, and a derived quad binding keeps the quad's own endpoints. Dual rates have an explicit `rates_owner`: `transmitter` (default for every radio, so EdgeTX's native rates are never doubled) or `simulator`, where the radio sends linear sticks and OpenRC applies the flown aircraft's manual rates, selected by a rate switch (low normal, middle sport, high full) that owns the choice. This narrows the earlier exclusion of simulator shaping for radios to the aircraft's own rate profiles; curves and mixes stay on the radio. [Plan](../plans/edgetx-airplane-controls.md), [audit](../research/radio-input/D6-ETX-00/README.md), [implementation](../research/radio-input/D6-ETX-01/README.md).

## Rigging offsets and loaded servos are different models

**D6-TRIM-01 / D6-SRV-00.** Optional trim practice adds equivalent rigging angles at actual servo deflection, leaving input commands and the start trim solver distinct; the selected first-flight mode preserves its airframe and pilot trims. Loaded torque, heat and causal servo failure are a separate approved design that remains planned, with aircraft-by-aircraft admission and sourced limits. They must not be inferred from random-failure probability or presented as already installed. [Trim-practice decision](../research/radio-input/D6-TRIM-01/README.md), [servo plan](../plans/servo-dynamics.md).

## Resolve random scenarios and failures before advancing physics

**NR / EM.** Version and freeze the selected episode, seed, onset and severity so restart/replay preserves the same scenario. Stage physical effects through supported actuator/source capabilities, commit only after an accepted tick, and keep notices outside physical identity. New mechanisms do not redraw old versioned lists. Wing separation remains gated because an intact oracle can mask removed strips; hiding geometry cannot implement structural loss. [Failure contract](../plans/failure-mode.md#implementation-checkpoint--current-scope), [EM-29](../research/failure-mode/EM-29/README.md), [EM-31](../research/failure-mode/EM-31/README.md).

## Reuse flight logs for factual analysis

**FL-01…05 / UI-FS.** Bounded recording observes accepted state without driving physics. Offline replay, CSV and existing plotting tools support analysis; marker debriefs reuse those artifacts instead of introducing another campaign runner or unvalidated coaching score. UI statistics and retained flight history have their own lifecycle, not checkpoint authority. [Flight logging](../FLIGHT-LOGGING.md), [FL-05](../research/flight-logging/FL-05/README.md), [flight statistics](../FLIGHT-STATISTICS.md).

## Companions need their own admission, scheduling and replay proof

**AFC-01/02/03.** Preserve the player's tick driver and advance admitted independent companion sessions through a validated command seam after accepted player ticks. Qualify source/controller/field identity and actual corridor geometry rather than assuming every flyable aircraft is AI-ready. Diagnostic manifests can link existing aircraft logs without claiming fleet restore or shared-world replay. This bounds the first integration and keeps AI outside the single-model kernel. [Companion guide and limits](../AI-FLIGHT-COMPANIONS.md), [AFC-02 evidence](../research/ai-companions/AFC-02/README.md).

**AFC-02-R6 / AFC-05-R2 (2026-11-09).** Bind an explicit reviewed behavior-source set in addition to solver/data identity; changed mixed-purpose files conservatively require renewal. Keep requested settings, accepted launch configuration and actual airborne count distinct. Resolve turbulence seeds in a versioned fixed-roster domain, reserving the player's and earlier actors' actual initial RNG states and retaining collision nonces. Distinct starting states do not establish independent stochastic streams or fleet continuation. [Contract and evidence](../research/ai-companions/AFC-02-R6/README.md).

## Separate damage evidence, repair assessment and prices

**CR-28…39.** Accepted incidents supply observations; component resolution, repair/salvage estimates and dated commercial prices remain distinct. Unknown structural damage is not silently priced as zero or promoted to measured failure. Coverage groups avoid double-counting variants, and provisional bounds remain labeled. Godot wreck presentation does not feed unqualified state back into flight. [Crash contract](../CRASH-DAMAGE-PLAN.md), [economics decisions and limits](../plans/crash-damage-economics.md).

**CR-40 (2026-11-09).** Admit deterministic local game assessment through a separately generated v3 companion / v2 financial dossier, with exact reviewed installation hashes and a frozen legacy-price-catalog digest. Keep v1 schemas and historical readers closed. Disjoint financial children replace inclusive legacy allocations without changing mass; missing vendor fit may use a labeled authored USD game allowance. The default quote covers assessed local parts/service cash and excludes DIY time. Optional shop labor and package choices bind frozen replayable estimate receipts; automatic estimates stay current-only so render cadence cannot manufacture purchase history. Scoped no-charge rules do not certify reuse or salvage. Whole-build comparisons cannot certify an unresolved incident ceiling. Timed hazards, physical serviceability and the separate X-Cell installation retain their gates. [Contract, evidence and remaining work](../research/crash-damage-investigations/CR-40/README.md).

## The accident ledger samples gear support once per frame

**F1, 2026-11-26; explicit owner decision.** The accident ledger (`economy/incident.gd`) holds ticks whose only events
are persistent gear-support samples and observes them once per frame with each wheel's peak compression. It observes
every other event, a crash or a restore at its own tick, after the held samples. A checkpoint, an evaluation, an
archive flush or a ledger action releases the held samples first. Per tick, the bound, revalidation and SHA-256 of
every sample cost about 0.36 ms of each rolling 240 Hz tick.

Peaks, recommendations and assessed components equal per-tick observation
([test](../../app/tests/test_accident_ledger_hold.gd)). The evidence tick of a held sample and the internal revision
counts are per frame. `has_damage()` can lag by up to one frame. Persistent hull contacts remain per tick. Revisit if
a gear damage rule needs per-tick sample timing.
