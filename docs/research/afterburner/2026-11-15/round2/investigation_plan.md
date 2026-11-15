# Planned research round 2 — 28 engineering investigations

**Date:** 15 November 2026 (America/Bogota).
**Purpose:** strengthen the existing OpenRC afterburner handoff through decisions grounded in source inspection, primary references, calculations and counterexamples.

The investigation scope was divided before detailed execution into four workstreams: propulsion I01–I07, graphics I08–I14, audio I15–I21, and simulator integration I22–I28. This register records those questions and their completed disposition. “Completed” means the research has produced a finding and a plan amendment; it does not mean the proposed product feature or acceptance test has passed.

## Method and priority

Each investigation contains: a specific question; an inspection/calculation method; evidence and limitations; a concrete change to the plan; and a proposed acceptance criterion. Sources are primary project/manufacturer/engine/research documents. Candidate sound pages establish metadata only. Numerical examples with invented inputs are identified as such.

**P0:** resolve before integrating the first physical slice. **P1:** required before claiming release quality or physical realism. **P2:** optional enhancement after the baseline is qualified. Research ran in parallel; implementation follows the dependencies below.

| ID | Planned question | Method | Completed decision | Priority |
| --- | --- | --- | --- | --- |
| I01 | Which actual P100 variant and accessories support a physical AB claim? | JetCat catalog/manual/product cross-check | Keep physical AB experimental; separate LED/smoke | P0 |
| I02 | Where do gross thrust, inlet momentum and fuel mass enter? | NASA equation and numerical bookkeeping counterexample | Add only the nozzle increment; prevent double counting | P0 |
| I03 | What nozzle matching limits a simple augmentation map? | Ideal choking/continuity calculation and primary nozzle references | Declare map domain and area/matching assumptions | P0 |
| I04 | Which atmosphere and operating variables must the map consume? | Current weather code and NACA test comparison | Reuse stage-local standard column; no universal density exponent | P0 |
| I05 | How do ignition timing and exhaustion conserve fuel/impulse? | Exact synthetic event case versus quantized stepping | Disclose tick ignition; compose located events deliberately | P0 |
| I06 | How do augmentation and live CG change moments? | FRD cross products and source transform audit | One physical thrust line and one live-CG transfer | P0 |
| I07 | What measurements identify wet force and flow independently? | Identifiability counterexample and uncertainty propagation | Paired data, uncertainty and held-out validation | P1 |
| I08 | Which material/renderer details can break the core plume? | Shader/material APIs and actual project profiles | Depth-tested mesh baseline with per-renderer qualification | P0 |
| I09 | Is shock detail resolvable at RC viewing distances? | Projected internal-pixel and cell-width calculations | Filter fine terms and simplify by footprint | P0 |
| I10 | Can phase stay aligned through interpolation and long runs? | Actual clocks, wrap counterexample, float spacing | Compute bounded phase from pose-aligned float64 time | P0 |
| I11 | What do mesh layers, sorting and Effects Off actually cost? | Mesh/resource ownership and Godot transparency contracts | Bounds/LOD/cold-Off lifecycle and comparative profiling | P1 |
| I12 | How should particles inherit moving-nozzle motion? | Existing swept smoke births and translation/rotation examples | Swept births; one carrier-velocity owner; reset discontinuities | P1 |
| I13 | Can optional heat haze avoid foreground contamination? | Depth/screen-copy documentation and conflict check | Displaced-depth rejection; pinned-renderer depth probe | P2 |
| I14 | What establishes native visual/performance success? | Current capture tools and timing methodology | Paired same-tape 1080p measurements with complete provenance | P1 |
| I15 | What sound changes independently of shaft RPM? | Installed-bank inspection and primary jet-noise studies | Keep one dry loop; add independently controlled wet layer | P0 |
| I16 | Which audio candidates have actionable provenance? | Creator metadata and installed manifest audit | Rank for later audition; avoid unsupported recording claims | P1 |
| I17 | Do loop fades preserve level and headroom? | Correlation arithmetic and existing guard/limiter inspection | Choose fade from material; measure true peak and seams | P1 |
| I18 | When does an ignition reach a moving listener? | Retarded-time equation and startup/interpolation counterexamples | Causal queue, prehistory policy, one Doppler owner | P0 |
| I19 | Which stream format and bounded resources fit Godot? | PCM/import/voice-path source and API review | Guarded mono sustain plus bounded transient; whole-scene count | P1 |
| I20 | How can listening quality and alerts be evaluated? | Project native-capture tools and controlled listening design | Repeatable captures and separate perceptual acceptance | P1 |
| I21 | How does variation survive seek, reset and multiple sources? | Event identity, RNG API and observer lifecycle analysis | Stable variants plus independent delivery cursor | P0 |
| I22 | How do controls recover without accidental AB demand? | Actions/AUX/hold release and generation trace | Symmetric cancel routing and existing OFF-evidence policy | P0 |
| I23 | Which state/layout/callback owners must change together? | Runtime, fuel locator, VehicleModel and session trace | Closed layout manifest and one callback protocol | P0 |
| I24 | How can dry no-op behavior coexist with a new solver hash? | Replay hashing and typed checkpoint carrier inspection | Three replay fixtures; truthful identity and exact state | P0 |
| I25 | How does installation survive schema/generator/Workshop? | Strict schema, normalization, classification and descriptor trace | Dedicated AB capability; regenerate variant/descriptor | P0 |
| I26 | Can native preparation silently omit AB behavior? | Native whitelist, admission and backend identity audit | Explicit reference fallback until native qualification | P0 |
| I27 | Can several outlets share one physical engine? | Existing installation identity and conservation example | One physical ledger; explicit visual outlet bindings | P1 |
| I28 | Which old evidence remains valid on the changed source? | 39-path hash comparison, test policy and receipt audit | Current pin, historical receipts and staged qualification | P0 |

## Dependency order

1. Identify and admit the installation and its data: I01–I04, I07, I25, I26.
2. Close physical state, event, fuel and replay ownership: I05–I06, I23–I24, I27.
3. Wire controls and accepted presentation: I10, I15, I18, I21–I22.
4. Qualify the readable mesh and audio baseline: I08–I09, I16–I17, I19–I20.
5. Measure cost and lifecycle before adding optional complexity: I11–I14, I28.

The ordering is a development dependency, not a claim that every real-engine measurement must precede an explicitly estimated experimental prototype.

## Evidence and outputs

- [Propulsion I01–I07](physics.md), with [executed analytical cases](../../../../../research/afterburner/round2/physics_evidence/analytic_cases_output.txt).
- [Graphics I08–I14](graphics.md), with [preserved numerical calculations](../../../../../research/afterburner/round2/graphics_evidence/projected_size_phase.json).
- [Audio I15–I21](audio.md), with [executed arithmetic probe](../../../../../research/afterburner/round2/audio_evidence/probe-results.txt).
- [Integration I22–I28](integration.md), with [selected-source drift](source_drift.json).
- [Independent adversarial review](independent_review.md), recording corrections and remaining limits.

The revised main Markdown incorporates all 28 full investigations and the material decisions in its active implementation sections. The development package retains the original standalone prototype and historical test receipts, and adds this complete research round. No production code or new sound asset is introduced by the research.
