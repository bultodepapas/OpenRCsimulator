# Ugly Stik: flight feel, aerodynamics, physics and variant audit

**Date:** 2026-11-15. **Audited application:** [`ad21070798bfb9658785576a9c0b8bfc9a71fc7f`](https://github.com/bultodepapas/OpenRCsimulator/tree/ad21070798bfb9658785576a9c0b8bfc9a71fc7f). **Delivery branch:** `audit/ugly-stik-flight-physics-2026-11-15`. The requested “Ogli Stick” is the Ugly Stik family in this repository. This is an engineering audit with reproducible software evidence and a physical-validation plan; it is not certification of a real aircraft or a claim of exhaustive defect absence.

## Assessment

The current product already has the intended **two stock Stiks**, in the first two stock positions: the basic reference and the experimental Electric 6S. The .61 FX, .55 AX and FS-64V installations are hidden technical aircraft. They remain necessary for explicit research routes, compatibility, generated descriptors, economic records and tests. No unexplained duplicate with a safe deletion path was found. The visible confusion was reinforced by stale documentation: the top-level inventory still advertised the three glow alternatives and omitted the stock electric. This branch corrects that documentation and clarifies historical media coverage. It does not reimplement a stock policy that already exists or remove recorded aircraft identities. The user's actual installed build and screen were not supplied, so this audit cannot identify which older executable or technical route produced the observed extra choices.

The flight model has substantial deterministic infrastructure, but several mechanisms capable of changing Stik feel remain absent or estimated. Particularly material are the electric propeller's missing stopped drag/self-windmilling branch, absent Stik propeller wash, the transition between global and local lateral-force laws, a known local induced-flow inconsistency, and unmeasured mass/CG/inertia and control-response assumptions. Reproduced raw-input conditions can also change the command before aerodynamics receives it. Changing coefficients to compensate would obscure the cause.

Two audit-tool defects were fixed while generating the evidence: empty/incomplete requested cards could be reported as successful, and an arbitrary aircraft argument could make the Python wrapper overwrite a `run.log` outside its output directory even after the child rejected the aircraft. The fixes validate inputs before work, use one ordered maneuver roster, verify output completeness and exclude failed runs from successful summaries. The complete original maneuver order and callables are retained, and a recognized baseline card produced identical result content with timing fields removed. No application physics, aircraft coefficients, generated aircraft data, stock catalog, golden trajectory or recorded user configuration was changed.

## Read the dossier

**Latest continuation:** [Research round 02](research-round-02/README.md) completes 24 investigations planned before research and two targeted follow-ups, with 107 indexed source records, an ordered integration backlog and independently reviewed evidence-tool fixes. Its [verification](research-round-02/verification.md) records 48 focused Python tests and the precise limits of those results. This updates the evidence-tool closure status below without rewriting the earlier reports as if their original counterexamples had never existed.

**Continuation:** [Follow-up 01](follow-up-01/README.md) adds deeper input-contract analysis, FS-64V eigenvalue/trim diagnosis, a checked Electric statistics candidate, report-integrity reproductions and implementation plans. It retains the exact execution baseline and explicitly bounds the later upstream changes.

| Report | Purpose |
| --- | --- |
| [Research round 02: planned investigations and integration](research-round-02/README.md) | 24 investigations, two focused follow-ups, primary sources, implementation backlog, delivered tooling fixes and verification. |
| [Follow-up 01: deeper external audit](follow-up-01/README.md) | New counterexamples, independent analyses, concrete repair scopes and acceptance criteria; proposals remain open. |
| [Findings register](findings-register.md) | Priorities, evidence strength, delivered fixes and remaining closure criteria. |
| [Physics and aerodynamics](physics-and-aerodynamics.md) | Production equations, propulsion, wake, side force, stall, induced flow, inertia and coefficient provenance. |
| [Variants and routes](variants-and-routes.md) | Catalog, Home, Workshop, CLI, debug, saves, generators, economy, statistics and media. |
| [Controls, feel and performance](controls-feel-and-performance.md) | Raw-axis readiness and calibration reproductions; shaping, servos, timing and profiling candidates. |
| [Fleet comparison](fleet-comparison.md) | Eleven-aircraft static comparison and five selected dynamic configurations, with interpretation limits. |
| [Research sources and validation](research-sources-and-validation.md) | Primary studies/manufacturer evidence, applicability, measurement priorities and acceptance program. |
| [Verification](verification.md) | Exact software scope, commands, retained receipts, failed attempts, identity and limitations. |
| [Independent review](independent-review.md) | Separate review of the runner changes and the disposable path-overwrite reproduction. |
| [Probe sources](../../../research/ugly-stik-audit-2026-11-15/README.md) | Small production-law and production-input reproductions. |

The [evidence directory](evidence/) contains checked engine records, probe outputs, individual flight profiles, campaign manifests and the runner's before/after regression output. Interpret `ok` in a receipt with its stated check: an engine-clean execution of the *old* invalid-selection reproduction is evidence of the defect, not evidence that a valid card ran. Absolute paths in receipts identify the original execution workspace; retained relative links in these reports identify the published evidence.

## Stock and technical identities

| Configuration | Technical ID | Current purpose |
| --- | --- | --- |
| Basic Ugly Stik | `jensen-das-ugly-stik-60` | Stock reference; fixed half-tank mass, prescribed RPM response. |
| Electric 6S | `stik-electric-6s` | Stock experimental conversion; normal flight defaults to a finite pack, Workshop uses explicitly labeled ideal supply. |
| MAX-61FX | `stik-glow-61fx-2t` | Hidden finite-glow research/compatibility installation. |
| MAX-55AX | `stik-glow-55ax-2t` | Hidden finite-glow research/compatibility installation. |
| FS-64V | `stik-glow-fs64v-4t` | Hidden four-stroke research/compatibility installation. |

The full technical catalog contains twelve aircraft, eleven of them fixed-wing. Stock selection contains nine aircraft including the helicopter, or eight fixed-wing. Synthetic electric and alternate-prop data outside this list are test/research fixtures, not additional stock Stiks. Ideal and finite-pack electric files are energy-source representations of one catalog aircraft, not duplicate menu choices. See the [route matrix](variants-and-routes.md) before changing any enumeration.

## What the numerical comparison establishes

The pinned Linux headless engine is `4.8.beta2.official.cafc17a19`. Every technical fixed-wing aircraft completed the selected `trim_sweep`, `aero_sweep` and `modes` roster. Basic Stik, ideal Electric 6S, 61FX and Extra also completed eight selected maneuvers; the finite-pack Electric 6S completed the same roster separately. Every requested result was present and its card validity check passed. These checks establish model behavior under a scripted pilot. They do not establish real-aircraft speeds, pilot-rated feel, complete forty-test coverage, or native hardware performance.

| Model/source | Simulated power-off break, m/s | Controlled level-speed result, m/s | Full-aileron roll at each model's start speed, °/s | Start speed, m/s |
| --- | ---: | ---: | ---: | ---: |
| Basic Stik | 9.67 | 32.8 | 187 | 15 |
| Electric, ideal 22.2 V | 9.06 | 33.9 | 179 | 15 |
| Electric, initially full estimated finite pack | 9.06 | 35.4 | 179 | 15 |
| MAX-61FX technical Stik | 9.98 | 38.1 | 192 | 20 |
| Extra 300S | 11.12 | 41.2 | 306 | 22 |

Source: the retained [dynamic profiles](evidence/dynamic/) and [finite-pack profile](evidence/electric-pack/), interpreted in the [fleet report](fleet-comparison.md). Roll values use different aircraft start speeds, so they are not a matched-speed ranking. Break detection depends on the card's criteria and controls. The initially full finite pack supplied more than the ideal source's 22.2 V during the compared acceleration; the speed difference does not demonstrate a battery-model bug. Simulated 61FX RPM reaches 17,720 in the controlled level-speed test, above its declared engine and prop recommendations; the runtime already has an overspeed flag. This is an installation/domain review item, not physical propeller-failure evidence or a reason to insert an arbitrary RPM clamp.

The static modal labels `1.3Vs` and `0.8Vmax` use an analytic stall estimate and the trim-sweep fallback in that campaign, because no stall or level-speed flight preceded them. The four-aircraft dynamic campaign does not include `modes`. Do not combine those records as if the modal solver had been rerun at dynamically measured speeds. The card's `inverted_at_s` power-step field marks an orientation threshold while lateral controls remain active; the trace shows roll saturation near some crossings. It does not by itself prove a sustained inverted flight or a pure pitch instability.

## What matters most for feel

**Establish the commands first.** In an injected production-reader scenario, a fresh low-throttle event arms a raw radio despite no roll event; a startup poll of zero combined with calibrated center 0.2 produces roll −0.1667. In the production calibration class, three polls of a retained outlier can permanently change an endpoint and reduce real full-travel command by 20% in the constructed example. Both are reproducible software conditions. Their occurrence on particular transmitters/drivers is unmeasured. Radio, generic joystick, gamepad and keyboard use different deliberate shaping paths; transmitter expo and rates must be recorded alongside simulator shaping and trims.

**Establish the installation next.** The basic Stik has a prescribed RPM law and fixed fuel mass; the 6S and hidden glow models have different shaft/energy behavior and inventories. Basic and electric authored pitch inertia differ substantially. One explicitly virtual aft balance item's longitudinal lever term accounts for about 37% of the basic model's computed pitch inertia. That is a reason to measure the actual build, not evidence that a real Stik contains that ballast. Full/half/empty fuel and battery position matter to CG and inertia as well as weight.

**Then discriminate the aerodynamic omissions.** At zero aircraft speed and rates, a prescribed 10,000 RPM gives the Stiks thrust but no rudder force increment from propwash; Extra's opt-in implementation does produce an increment. At forward speed and zero RPM, the electric propeller produces no aerodynamic wrench. At large sideslip the Stik's production law adopts a local branch with much lower side force than its global donor law, but neither branch is established as the real Jensen's measured truth. These observations identify experiments to perform; they do not supply physically calibrated replacement coefficients.

## Delivery and follow-through

Delivered changes are restricted to the research runner, its regressions and operating documentation, the corrected stock documentation, and this dossier/probes/evidence. The [register](findings-register.md) explicitly leaves runtime input repairs, aerodynamic extensions, installation calibration and measurement-dependent claims open. Each has a concrete closure route. Existing physical-model limitations are preserved rather than silently retuned to make a card or subjective description look better.

The first follow-up should resolve raw-axis readiness and calibration report cadence with native-device evidence while measuring the target aircraft's mass, CG, inertias, actual throws and servo timing. Next establish the propeller/motor/ESC and glow operating envelopes, then evaluate wake and power-off propeller behavior in isolated shared-kernel candidates. Sideslip closure and post-stall modeling need separate coupled-force and held-out-maneuver evidence. Profile input and simulation costs on target hardware only after the correctness and identity boundaries are protected. The [research plan](research-sources-and-validation.md) provides the measurement and acceptance details.
