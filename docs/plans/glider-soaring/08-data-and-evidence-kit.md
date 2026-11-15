# Glider data and evidence kit

**Status:** proposed collection and reporting templates; no aircraft, line, simulator, device, performance or learner test has been performed by this document. **Owners:** aircraft/data and flight test, with the relevant SG, M5, FL, input, performance and release owners. **Runtime baseline:** `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`.

The [master plan](../glider-soaring.md) owns SG status; [aircraft and weather](03-aircraft-and-weather.md) owns their recommendations; [acceptance and delivery](04-acceptance-and-delivery.md) owns gates and thresholds. The [GI-01…24 index](../../research/glider-soaring/2026-11-15-investigations.md) links the rationale and exact primary sources. These are human evidence records, **not new runtime schemas**. Existing aircraft authoring and [flight-log rules](../../FLIGHT-LOGGING.md) still apply.

Select collection for the declared mode and claim. Every claim needs identity, scope, applicable software/numerical evidence, assumptions and failures. Solo airborne physical qualification needs its actual build, flight, controls and landing evidence, not a tug or rope dossier. Hand-release and tow measurements apply when those capabilities are claimed. A bounded experimental prototype may use identified estimates or synthetic fixtures while physical claims stay open; applicable software, usability and distribution gates still apply. For synthetic-only work mark physical measurements, physical sensor synchronization and the physical measurement split `not applicable: synthetic-only`. Apply the physical split when claiming fidelity or using physical measurements for a model claim. A practice exercise needs an objective, achievable scenario, honest outcomes and usable controls, not an efficacy study unless a learning effect is claimed.

## Record conventions

Copy applicable cards. Give each build, configuration, run, specimen, artifact and claim a stable ID; link them in both directions. Retain raw immutable files, reduction scripts/settings, derived outputs, and hashes or other exact identities in accessible evidence storage. Record retention and sharing restrictions. Corrections create a dated revision with its predecessor and reason, preserving original data and failures.

Replace every placeholder with a value or one of `unknown: reason`, `pending: owner / next action`, or `not applicable: reason`. Missing is not zero, pass, no wind, no uncertainty or permission. Use UTC and precision for observation dates; identify each sensor clock, sample time and its synchronization uncertainty. State units and frames/datums where meaningful; measured or estimated values need method and uncertainty or an explicit unknown. Mark an exactly configured value as such. For estimates without justified probabilities give defensible conditional bounds and assumptions; specify interval construction and coverage factor if known. Keep measured, manual, borrowed, estimated, derived and synthetic origins distinct. A logged fixture, truth channel or model output is not an independent measurement.

The simulator convention is local **NED** (north/east/down) and body **FRD** (forward/right/down); record transformations from sensor and asset frames, including handedness, origin, orientation, sign and calibration. Preserve full precision; round for display only.

## 1. Build, source and asset dossier — GI-02…06, GI-23; SG-02/03/05/17

```text
Dossier ID / revision / owner / date:
Claimed aircraft, kit/model revision, build and configuration IDs:
Purpose and intended modes / supported domain / exclusions:
Airframe condition, repairs, surface finish and free play:
Component inventory ID and raw evidence (mass, location, method, uncertainty):
Ready-to-fly mass / independent weighing / CG datum, axes and method:
Inertia tensor and origin / independent rig, suspension and fixture correction:
Wing-only reference area and planform method / span / chord / tail arms:
Controls, hinge signs, throws, timing, mixes and measured achieved surfaces:
Installed receiver, servos, release, battery, ballast, wiring and supply assumption:
Instrumented versus flight configuration / reweigh and revised CG/inertia:
Hook and landing-contact geometry if installed / datum / measurement method:
Rigid-airframe evidence and observed deformation / unqualified structural limits:
Authored source and generator identities / generated data and manifest hashes:
Aircraft loader, visual binding and package verification evidence IDs:
Open gaps, condition changes and owner:
```

Inventory each installed component once, including payload and release hardware. Positions use the declared fixed aircraft datum. Compare inventory total and predicted CG/inertia against independent measurements; record rig cross-coupling, fixture effects and correlations. The manufacturer's FAI wing-plus-tail area is not wing-only aerodynamic reference area. A powered or instrumented configuration is not evidence for a different unpowered build. Receiver power is separate from propulsion. See the [documented EG4 configuration and caveats](03-aircraft-and-weather.md#1-first-aircraft-and-tow-pair).

For a claimed spoileron mix, sweep simultaneous brake and roll through saturation; retain applied commands, both achieved aileron angles and resulting pitch, yaw and drag observations and limitations.

Complete one asset row **per actual file** before intake; reference the owning source-delivery process. Public access and a repository-wide license do not settle file-specific intended use. Record the owner's review; this card imports nothing.

| File ID / role (mesh, texture, polar, code, etc.) | Exact original URL, author, revision and file hash | File-specific terms/notices and intended-use review | Editable source, scale/axes, datums, hinges and physical applicability | Conversion/generator and output hashes | Decision, reviewer, date, gaps |
| --- | --- | --- | --- | --- | --- |
| `<ID>` | `<origin>` | `<terms / review>` | `<fit>` | `<pipeline>` | `<admitted / pending / rejected + reason>` |

### Parameter register

Use one row per quantity and configuration, including aerodynamic source dimensionality, Reynolds-number and transition/roughness domain where relevant. Record wing section versus finite-wing versus whole-aircraft data; an airfoil coordinate or a full-scale polar is not a measured RC whole-aircraft polar.

| Parameter / configuration ID | Value and SI unit | Frame, origin, direction / convention | Source category | Raw source ID, method, version and dependencies | Uncertainty / correlation / validity domain | Authoring and generated artifact IDs |
| --- | --- | --- | --- | --- | --- | --- |
| `<name / build>` | `<value unit>` | `<frame / datum>` | `<manual / measured / borrowed / estimated / derived / synthetic>` | `<source>` | `<interval or unknown>` | `<IDs>` |

`manual` is a published statement for its specified configuration; `measured` names the actual article and instrument; `borrowed` states the mismatch; `estimated` states basis and bounds; `derived` names the equation, inputs and propagated uncertainty. Mark synthetic fixture values separately even if derived from other synthetic values. These evidence labels do not themselves extend the current aircraft v2 `kind` vocabulary. Parameter dependence matters: do not infer independently identifiable drag, inertia or damping from one equally well-fit response.

## 2. Experiment split and exclusion receipt — GI-01/02/03/06/22; SG-03/09/16

Before collecting or inspecting final results, define intended use, observable, units, metric, justified acceptance limits, measurement resolution, sample plan and treatment of vertical air, timing, transients and missing data. Assign **whole flights/runs or complete line loading histories** by ID to calibration, model-selection/development and final validation; record grouping by day, pilot, specimen and conditions to avoid correlated leakage. Preserve rejected and failed runs. Freeze the candidate, selection rules, reduction, comparison metrics and uncertainty treatment before the final holdout. If final data influence model choice or revision, reclassify them as development and reserve a fresh independent final set.

```text
Experiment / claim / owner / revision / frozen-at UTC:
Build, scenario and instrument IDs / declared use and domain:
Question / independent observable / units / metric and acceptance limit with rationale:
Predeclared steady-window, wind-quality and exclusion rules:
Calibration run IDs / parameter fitting and assumptions:
Selection run IDs / candidates, selection rule and result:
Final independent run IDs / separation rationale / frozen model and reducer hashes:
Measurement uncertainty / numerical reference and refinement / model discrepancy:
Sensitivity and correlated parameters / residual bias, spread and interval method:
Result, limitations, artifacts and reviewer / next discriminating measurement:
```

| Run or interval ID and original artifact | Planned rule or discovered issue | Exclude / retain with flag and reason | Effect on sample count and result | Decider / date / replacement or fresh holdout |
| --- | --- | --- | --- | --- |
| `<ID and time range>` | `<rule or issue>` | `<decision>` | `<effect>` | `<receipt>` |

For a polar, synchronize air-relative and ground-relative motion with independently located wind observations; bound vertical-air bias sufficiently for the claim or leave it unsupported. Opposite headings alone do not remove a changing updraft. Compare held-out sink, glide angle, trim and control response across the claimed domain. Report measurement uncertainty, numerical error and model discrepancy separately; an exact replay or a tuned fit is not physical validation. The research methods include [small-UAV glide experiments](https://www.cambridge.org/core/journals/aeronautical-journal/article/experimental-evaluation-of-the-drag-curves-of-small-fixed-wing-uavs/453B48240E5861B1360B9D33288C5C88) and [NIST uncertainty reporting guidance](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-7-reporting-uncertainty); neither supplies a threshold or measurement for this aircraft.

## 3. Synchronized hand-release card — GI-05/06; SG-05/16

```text
Release ID / flight ID / pilot and technique / build, payload and condition IDs:
Raw multi-view video or motion streams / camera geometry and calibration IDs:
Sensor clocks, sample rates, synchronization markers, offsets/drift and uncertainty:
Release instant definition, time interval and uncertainty / visibility or occlusion:
Marker layout, camera-to-world transform / marker-to-CG lever arm and uncertainty:
At separation: CG position and height datum / 3-D ground velocity / frame:
Body-to-NED attitude representation and ordering / body angular rate in FRD:
Simultaneous local 3-D wind and source / derived air velocity and uncertainty:
Requested input / applied actuator command / achieved surfaces and sample timing:
Raw correlated state samples and covariance or bounded timing/measurement errors:
Held-out subsequent trajectory, attitude/rates and comparison artifacts:
```

Preserve each release as a correlated sample, including pilot, technique, build and conditions; do not assemble an artificial release from separately observed maxima. Express marker velocity, angular rate and lever arm in one frame before applying `v_CG = v_marker − omega × r_CG_to_marker`; then transform to the required frame. Derive air velocity as ground velocity minus local wind in that same frame. Distinguish terrain-relative height from the NED datum and account for rotation, marker occlusion, flexible motion and sensor mass. Compare the initial trajectory and rates with held-out synchronized observations and uncertainty, without adding hand energy after separation. Unsupported wind or lever-arm measurements remain unknown, not silent zeros. [Optical reconstruction research](https://www.cambridge.org/core/journals/aeronautical-journal/article/offboard-aerodynamic-measurements-of-smalluavs-in-glide-flight-using-motion-tracking/4F2CB54FF6A9C3DF9870305D0EA92044) describes a method, not this build's result.

## 4. Installed line and independent break evidence — GI-07…12; SG-07…12/14/16

Complete only for a claimed tow installation. Identify the exact line, material, construction, length, batch, age and prior use, knots/splices, hooks and weak link, plus the actual glider/tug attachment geometry. Preserve a separate synthetic solver-fixture identity. The cyclic rig must record its boundary conditions, calibration and synchronized tensile force and gauge extension, not just nominal line ratings.

```text
Installation / specimen / build and termination IDs / prior loading or damage:
Rig and load-cell/extension-sensor IDs, gauge length, zero, calibration and uncertainty:
Temperature and other relevant conditions / clocks, sampling, synchronization:
Preconditioning / full load-unload histories, mean load, amplitude, rate and cycles:
Raw force-extension-time streams / reduction and fitted law/version/domain:
Calibration histories / independent held-out histories / exclusions and reasons:
Force residual, loop work and orientation, rate dependence, permanent set and timing:
Release-actuator installation, command, actual separation and measured delay:
```

Reserve complete histories, including different loading paths, to assess the fitted line law. A static point does not separately identify stiffness and damping. If hysteresis or conditioning exceeds predeclared accuracy, narrow the domain or evaluate a separately identified law. [Cyclic twine experiments](https://www.jstage.jst.go.jp/article/suisan1932/44/12/44_12_1295/_article/-char/en) illustrate the issue; their specimen is not the selected line.

```text
Break evidence ID / separate representative specimen(s) and rig / installation match:
Weak-link, knots and prior-use identities / force calibration and uncertainty:
Predeclared loading protocol and failure definition / full force-time records:
Observed failure location, mode and peak or censored result / exclusions:
Independent repeats, variability and supported domain / missing evidence:
Decision: physical break claim supported / unsupported / outside scope, with reason:
```

Commanded release, load-induced failure and a simulated threshold are different events. If independent installed break evidence is absent, do not claim a physical break law. For pair-model receipts retain per-hook force, point velocity, moment and work; stored/dissipated energy, independent numerical reference, timestep/event refinement and cost. Record joint-trim surface and power margins, swept-aircraft clearance and its oracle, slack-line uncertainty, release/abort ordering and wake omission. A separated, contact-disabled feasibility fixture establishes none of those physical installation or interactive-clearance claims.

## 5. Weather, scenario, instrument and observation card — GI-13…20; SG-06/07/09…15

```text
Scenario ID, mode, objective and aircraft/build IDs / intended conditions:
Physical field and date/time / terrain datum and actual wind observation locations/heights:
Instrument IDs, calibration, uncertainty, sampling, clocks and synchronization:
Pressure, temperature, humidity, density and method, or explicit unknowns:
Simulator weather/atmosphere and polar law versions, full config and hashes:
Seed, RNG state or resolved agenda / world epoch and offset / remaining horizon:
Spatial bounds, terrain and all wing/tail station queries / start pose and trim:
Cell lifecycle, drift, gusts and turbulence identity / pair shared-field identity:
Sensor type, mount, sample/filter/anti-alias settings, warmup, dropout and reset state:
Assistance, camera/FOV, controller/profile, acceptance and abort/refusal rules:
Raw, reduced and replay artifact IDs / known bias, omissions and limitations:
```

Separate observed physical weather from a simulator recipe. State whether pressure, temperature, density and wind are observed, calculated or modeled and where they apply. For relevant weather claims retain provider boundary and density-weighted flux tests; for shared encounters retain multi-point covariance and coherence/phase, analytic and query-order controls. For thermal lessons compare bank, speed, offset and drift with banked sink and remaining return/cell-life margin; retain weak-lift controls. Wake omission is separate from collision clearance; an upstream measurement's extent is not a wake-free distance.

Choose channels needed by the claim; the table is a proposed observation checklist, not a statement that current logs expose them.

| Channel | Required interpretation |
| --- | --- |
| Position, height, attitude and rates | NED position with datum; AGL separately from `−down`; body-to-world orientation with convention and FRD rates; each with time and units. |
| Motion and air | Ground velocity, local 3-D wind and air velocity in the same frame; TAS is air-relative, groundspeed is ground-relative. Use independent wind observations for a physical claim; mark estimated or missing components. |
| Controls | Actor/owner, requested intent, post-limit/arbiter applied command, achieved actuator position and timing; include trims, modes, saturation and handoff. |
| Pair and energy | Each hook's force and material-point velocity in a stated frame, moment/work, line state, stored/dissipated energy and ordered events. |
| Instruments | Label simulation truth, sensor-derived values and assisted cues separately; retain unrounded inputs, units, filter state, sampling and latency. |

## 6. Claim receipts — GI-19…24; SG-13/15…17

Use the common header for **each** claim, then the applicable receipt. Link actual artifacts and failures rather than entering a bare pass. Missing evidence needed for a claim leaves it unsupported; it need not block a narrower, honestly described claim.

```text
Claim ID / exact wording and intended use / owner and date:
Aircraft, mode, weather, controls, platform and limits:
Evidence and source/data/package identities / assumptions and acceptance criteria:
Applicable software and numerical method, checks and evidence IDs:
Observed result and failed/refused cases / uncertainty or unknown / reviewer:
Disposition: supported / unsupported / outside scope; rationale and next action:
```

```text
Physical — build/parameter IDs / split, exclusions, measurements and raw IDs:
Final independent residuals and uncertainty / numerical refinement / supported domain:
Release or installed-line evidence IDs when claimed / missing physical evidence:

Device — OS/version, actual hardware, connection and profile/hash:
Calibration, polarity, deadband/rates/expo, trims, modes, aids and outcome IDs:
Focus loss, reconnect, pickup/transfer and release evidence per advertised combination:
View claim: native viewport, renderer, camera/FOV, scene, task and response timing:

Performance — source/package, host CPU/GPU/RAM, OS/power, renderer and viewport:
Quality, complete activity, observers, warmup and measurement window:
Tick/frame p50/p95/p99/max / wall-time ratio, catch-up, memory and sustained result:
Observer costs / applicable owner-approved budget and comparison / result artifacts:

Replay — engine, backend, law/layout and source/executable/package identities:
Aircraft, weather/epoch/agenda, ownership, state and ordered events:
Original log, matching CSV/report, replay IDs / complete / solver_changed:
Replay type and checked state/events / mismatch or incomplete-prefix disposition:

Release — exact package/build and installed-resource IDs / notices and limitations:
Required CI/export, target-platform, backend/fallback and device evidence IDs:
Advertised scope / unresolved failures / rollback or compatibility evidence:
```

A geometry or replay does not alone validate a polar, wake, strength or flight behavior. Mocked inputs do not qualify a radio. Evaluate complete-activity performance at native 1920×1080 first; report other resolutions separately. A changed solver or recovered prefix is not exact complete replay. A final-command physics replay needs the complete initial checkpoint, accepted command tape and timed external interventions, recomputes endogenous physical events, and checks only its declared physics/event projection; bypassing AI does not establish reproduction of controller or pickup memory. Full decision replay additionally needs the inputs, algorithms, controller/ownership memories and sampled holds required to re-execute decisions. The [record/replay contract](06-interface-contracts.md#7-checkpoint-tapes-and-replay) defines the required distinctions. Candidate replay is open-loop: it does not re-trim or reproduce changed device conditioning or pilot adaptation. Pair replay remains proposed until its whole-pair record is implemented and qualified.

**Lesson:** record objective, prerequisites, admitted scenario, assistance, accepted success, assisted completion, deliberate abort, refusal and reset rules; score accepted events only. A causal learning or real-RC transfer claim additionally needs a separately designed study with held-out scenarios and an appropriate comparison or repeated baseline. Describe a result as descriptive when that causal design is absent.
