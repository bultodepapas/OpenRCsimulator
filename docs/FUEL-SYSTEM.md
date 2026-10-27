# Fuel system engineering standard

Checked 2026-10-19. This guide defines the software contract for liquid fuel in current and future aircraft. It covers authored stores, finite consumption, fixed-datum mass properties, depletion, restoration and presentation. The aircraft schema and [aircraft contract](AIRCRAFT_CONTRACT.md) define accepted fields. Fuel chemistry and density belong to the registry, engine calibration to the owning propulsion track, and measurements to VAL.

Software verification, evidence constraints and physical validation are separate acceptance results. A numerical regression cannot establish installed tank geometry, engine consumption or flight realism. Capacities from manuals constrain a configuration; estimated placements and borrowed engine curves remain estimates.

## Authoring and identity

Use `openrc-aircraft v2` quantities with value, unit, kind and source. Generate accepted aircraft data through its source pipeline. Bind each tank to stable liquid and shell inventory IDs and a registry blend. Display names and array order never select a resource. Keep shell, liquid, accessories and battery mass distinct. An empty smoke tank does not imply an invented smoke-liquid load or a supported smoke-consumption law.

Capacity and authored reference contents are different quantities. The liquid mass comes from registry density and the selected authored volume. Its fixed geometry must hold the declared capacity. Unusable liquid remains onboard when the engine starves. Reserve is an authored quantity when available; otherwise the normalized estimate is explicitly labelled. Never present an estimated reserve as a manufacturer limit.

The registry owns blend composition, reference density, temperature and provenance. Glow installation rejects a profile/registry mismatch. Checkpoint configuration includes the normalized aircraft and installation identities. Exact source bytes and generator outputs stay reproducible across checkouts; hashed text has an explicit line-ending rule.

The base Stik remains an explicit prescribed-fuel reference specimen. Finite Stiks, Extra, P-51 and Vantage use their declared finite adapters. A tank declaration alone does not activate consumption. Synthetic electric donor fixtures are identified as synthetic ballast; they do not establish a physical electric installation.

## Datum mass and balance

The body datum O is the CG of the authored reference inventory. It stays fixed throughout the loaded model's life. `plan_cg` is a balance target at its declared fuel state and can differ from O. Session fill, burn and restart do not rebase geometry or state.

At every RK stage, the prepared inventory yields total mass, live CG offset from O, the full inertia tensor about that CG and its inverse. Moments move from O to the live CG exactly once. `FixedDatumBody` converts the resulting CG acceleration to datum acceleration. Rotor coupling and contacts use the same live inertia. Simulation state remains float64.

The current law assumes co-moving efflux and fixed resource geometry. Departing liquid creates no extra thrust or artificial spin-up term. Slosh, temperature-dependent density, foaming and non-co-moving discharge require separately declared laws and validation.

Check manual CG limits at the declared balance state. Check positive static margin across the permitted fill envelope against the disclosed neutral-point estimate. For one fixed-centroid tank, longitudinal endpoints bound the CG; independent stores need envelope vertices or an equivalent bound. Never rebalance dry hardware for each fill. Missing neutral-point or range evidence remains visible in the fleet report.

## Consumption and delivery

Glow uses the versioned mean-cycle lifecycle and its per-engine profile. The gasoline adapter uses `gasoline_bsfc_v1`: an explicit idle flow plus nonnegative delivered shaft power above the idle-power reference times BSFC. A stopped source consumes zero. Negative or windmilling shaft power does not produce negative fuel flow. The current P-51 BSFC and idle flow are disclosed estimates, not installed DA-120 measurements.

The turbine adapter uses `turbine_map_v1` with the existing continuous RPM/flow map. Exhaustion disables combustion thrust and fuel flow; rotor deceleration uses an explicitly estimated continuation of the existing schedule. A measured hot-shutdown or passive inlet map is not claimed. The current Vantage adapter consumes the main tank directly. Unknown hopper capacity, placement and transfer dynamics remain an aircraft-evidence limit; dry UAT hardware is not liquid inventory.

Fuel depletion is located inside the integration step. Accepted resources remain nonnegative, the source latches off, and the remainder of the step follows the stopped-source law. Residuals carry mass units. RK queries are pure; a failed stage or final projection rolls back the whole transaction. The shared Simulation kernel receives layouts and evaluators through VehicleModel and contains no fuel-family branch.

Apparent acceleration at a pickup is gravity minus point acceleration. The angular-acceleration and centrifugal point terms therefore enter with negative signs. Needling uses a fixed standard-gravity calibration, while the live apparent acceleration comes from the actual stage forces and rotation. Level acceleration, free fall and steady rotation have independent sign fixtures.

The optional glow pickup/line extension uses `glow-mean-cycle-finite-tank-line-pickup-v3`. An authored pickup plane controls wet access to the main tank. A separately identified, pre-primed line has a finite liquid capacity and its own mass/centroid. With wet pickup, main fuel passes through; with dry pickup or exhausted main supply, the line drains until starvation. Located events retain unreachable main liquid and unusable residue. The current law does not refill or re-prime the line automatically. Reset restores its authored reference contents; a starter cannot refill it.

Line liquid is counted once in mass and consumption. The main-tank launch selector does not multiply line contents. A transport time constant is not stored fuel volume. Unsupported delivery combinations are rejected. Current aircraft without source-backed line geometry retain the explicit line-free model; no hopper capacity or transfer map is invented.

## Launch restoration and observation

Finite aircraft launch full by default. Home offers 25, 50, 75 and 100 percent main-tank fill. The API accepts a finite fraction in `(0, 1]` above the unusable amount. Reset reloads that selection and recalculates airborne trim or runway equilibrium using its mass and CG.

Checkpoints store actual continuous resources separately from the selected launch fill. Restoring an older compatible boundary without fill metadata preserves the destination reset preference and marks the source selection unknown; it never infers launch fill from fuel remaining. Unsupported laws and identities are rejected. Rejected restore cannot partly change a session.

The JSON checkpoint carrier preserves native float64 and int64 bits in a bounded, hashed payload. It uses object-disabled Variant decoding. Source, layout and physics validation still run after decoding; a matching hash alone does not authorize a restore.

`mass_properties()` publishes a detached `openrc-mass-sample v1` at the accepted tick/time: total mass, CG, tensor/inverse, per-store identity, blend/family, capacity, remaining and usable mass, volume, fill and reserve status. Law and registry identities accompany finite samples. Sampling cannot advance state or change query-order results.

Swept contacts use mass and typed fuel from one interpolated inventory at the crossing fraction. `sample_boundary=swept_contact_linear_inventory` identifies the within-tick interpolation approximation. Endpoint samples are not relabelled as exact impact-time samples.

HUD, crash report, effects, wreck/economy, audio and diagnostic tools consume accepted source/store state. Ignition command and accepted combustion state are distinct: a depleted source can retain an ignition command while producing no combustion. Low-fuel cues use the declared reserve, pause/mute policy and one edge crossing; reset or refuel rearms them.

## Workshop and diagnostic tools

Dry mass policy does not change fuel density or multiply liquid mass. Geometric airframe scale transforms lengths by s and capacities/volumes by s³. The independent tank-capacity multiplier resizes the main tank and its liquid geometry, preserving density and authored fill. Fixed feed-line hardware remains separate from that multiplier. Home owns launch fill; it does not rewrite the authored reference inventory.

Installed finite-glow profiles refuse generic airframe, dry-weight and virtual-power scaling because the installation calibration is tied to its geometry. The UI explains that restriction. Independent tank-capacity changes and compatible control travel remain available through validation. The Extra uses a 22 m/s estimated airborne start because the old 17 m/s launch lies outside the bounded installed-engine trim solution. This changes the declared start, not the engine calibration.

Workshop compiles through the same closed module registry, aircraft validation and frozen-source identities as production aircraft. Descriptor hashes are regenerated from their source pipeline after an aircraft's bytes change. A compiled model that cannot validate or establish its launch condition cannot fly.

CSV mass traces use their declared wrapper schema and retain the base propulsion/atmosphere format identity. Finite liquid traces additionally carry validated store and source-latch channels. Readers reject unknown layouts and malformed metadata. `.orfl` retains complete state, source identities, markers and the command tape for exact replay.

Use the [flight logging workflow](FLIGHT-LOGGING.md). Preserve a baseline before changing physics, verify exact replay, then compare a named candidate on the same tick/input tape. Report `complete`, `solver_changed`, initial-condition differences and every unsupported comparison. Recovered prefixes and candidate runs never establish exact equivalence.

## Admission and completion gates

Before adding a finite aircraft, supply:

1. A reproducible generator, stable inventory/store IDs, exact source identities and schema/loader/module agreement.
2. Blend, capacity, unusable amount, liquid/shell geometry, declared balance state and sourced or explicitly estimated placements and limits.
3. A supported finite source/delivery law with stopped, idle, loaded, negative-power, exhaustion and reset behavior.
4. Independent mass/CG/full-tensor oracles, conservation/refinement tests, transactional failure tests and exact checkpoint continuation.
5. Real-session full/low-fill launch, trim, contact, depletion and consumer tests; matched-tape logs with complete identities.
6. Generator, schema, offline and application checks. Target-machine cost evidence is separate from headless plumbing tests.

Physical acceptance additionally requires empty/full weighing and CG, timed fuel burn, configuration identity, calibrated instruments and uncertainty. Source estimates remain labelled until replaced by those observations. Helicopter and ground-vehicle adoption use the shared inventory contracts but retain their own model and backend gates.

## Evidence and maintenance

The [initial audit](research/fuel-systems/FUEL-00-R1/README.md) records the original defects and preserved reproductions. The [completion evidence](research/fuel-systems/FUEL-12/README.md) records the implementation, current commands, measured software results and remaining physical limits. Historical evidence is not silently rewritten as a current calibration result.

Update accepted fields in AIRCRAFT_CONTRACT, enduring architecture in STACK, design choices in DECISIONS, and reproducible evidence under its owning research step. The [remaining qualification plan](plans/fuel-mass-balance.md) owns unresolved aircraft evidence, physical measurement and future delivery/vehicle extensions. The Word document is a generated snapshot of this guide, not a second editable standard.

The [Word snapshot](research/fuel-systems/FUEL-12/fuel-system-standard.docx) is generated from this Markdown source. Regenerate it with `research/fuel-systems/build_standard_document.py` using the managed document runtime and render every page before delivery.
