# Audit completed: five substantial findings

I audited **[bultodepapas/OpenRCsimulator](https://github.com/bultodepapas/OpenRCsimulator)** at commit **[`45d86d250f6e38a3d9b60d30c01bdc2396571efe`](https://github.com/bultodepapas/OpenRCsimulator/tree/45d86d250f6e38a3d9b60d30c01bdc2396571efe)**, using the repository’s pinned **Godot 4.8.beta2.official.cafc17a19**.

**The strongest physics finding is a finite aerodynamic force discontinuity in the stock Extra 300S.** A velocity difference of just \(2\times10^{-10}\,\mathrm{m/s}\) produces a roll-acceleration difference of approximately **425°/s²** in a controlled reverse-flow test.

Separately, I reproduced a gameplay consequence of graphics settings: **the same collision sweep passes through without contact on Low and Medium, but hits a terminal obstacle on High.**

The completed deliverables are:

- OpenRC_Simulator_Audit_45d86d2.pdf[OpenRC_Simulator_Audit_45d86d2.pdf](sandbox:/workspace/scratch/30a3be555435/audit_deliverables/OpenRC_Simulator_Audit_45d86d2.pdf) — the **12-page audit**, including causes, measurements, corrections, acceptance criteria, and source links.
- OpenRC_Simulator_Audit_Evidence_45d86d2.zip[OpenRC_Simulator_Audit_Evidence_45d86d2.zip](sandbox:/workspace/scratch/30a3be555435/audit_deliverables/OpenRC_Simulator_Audit_Evidence_45d86d2.zip) — probes, original execution logs, commands, source identities, verification scripts, and portable reproduction instructions.

I used three specialist investigation tracks and a separate adversarial reviewer. The retained evidence includes **nine checked executions**, with verified log hashes and **69 packaged production source copies verified against the pinned Git tree**. No tracked repository source was modified.

## Findings at a glance

| # | Finding | Strongest evidence | Classification |
|---|---|---|---|
| **1** | Wing strip progression breaks reverse-flow continuity | A near-identical state pair produces **3.60 N** of force difference and **1.25 N·m** of roll-moment difference | Confirmed numerical physics defect |
| **2** | Graphics quality changes the physical obstacle course | Identical sweep: **no contact on Low/Medium; terminal bench collision on High** | Confirmed architectural design problem |
| **3** | Stale statistics locks cannot recover correctly | A production-format lock with a verified exited PID causes repeated read-only opens | Confirmed recovery defect; already documented |
| **4** | Disabled-feature guards run after heavy resource loading | Loading an unconfigured material module caches six 2K textures and increases Godot-tracked memory by **21.66 MiB** | Measured loading problem; full-app savings require measurement |
| **5** | Layered clouds bypass their intended relief cache | Six weather presets use layer seeds that cannot match the bound sky-cache seed | Confirmed rendering integration defect; GPU-time impact unmeasured |

These findings have different consequences and priorities. The first two directly affect simulated behavior. The third affects persistence after interruption. The final two expose concrete failures in the intended resource and rendering optimizations.

---

## 1. The Extra 300S has an aerodynamic discontinuity at reverse flow

### What is wrong

The wing model uses a progression factor for each strip to vary where different parts of the wing stall. That is a reasonable modeling objective.

The problem is that the progression factor also scales the angle passed into the **fully separated, reverse-flow polar**. A parameter intended to control stall progression therefore changes the angular representation of the physical force law.

The relevant implementation is in:

- [`aero.gd`, lines 515–527](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/aero.gd#L515-L527), which passes `effective * strip_factor[i]` into the polar.
- [`wing_polar.gd`, lines 84–94](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/wing_polar.gd#L84-L94), which evaluates the separated lift law.

In that separated branch:

\[
C_L(\alpha)=\frac{1}{2}C_{D90}\sin(2\alpha)
\]

But the caller supplies \(f\alpha\), where \(f\) is the strip progression factor. The mismatch between the two representations of the reverse direction becomes:

\[
C_L(f\pi)-C_L(-f\pi)
=
C_{D90}\sin(2\pi f)
\]

For the stock Extra’s progression factors, this expression is nonzero.

The six factors are approximately:

\[
[1.011550,\ 1.024268,\ 0.964182,\ 0.964182,\ 1.024268,\ 1.011550]
\]

A physical flow direction should not acquire a different lift coefficient simply because its angular representation crosses a wrap boundary. The factor multiplication breaks that consistency.

### What I reproduced

The probe loads the **unchanged stock Extra model** and evaluates production aerodynamic functions using:

- Body velocity \((-20,0,w)\,\mathrm{m/s}\).
- Body angular velocity \((1,0,0)\,\mathrm{rad/s}\).
- Identity attitude, neutral controls, no wind.
- Air density \(1.225\,\mathrm{kg/m^3}\).
- The same held wake input for both neighboring states.

The roll rate lets individual wing strips cross the boundary separately.

Two representative results are:

| Zero-based strip index | Velocity difference between states | Force difference \(\Delta F_z\) | Roll-moment difference \(\Delta M_x\) | Roll-acceleration difference |
|---|---:|---:|---:|---:|
| 1 | \(2\times10^{-10}\,\mathrm{m/s}\) | \(+3.598791785\,\mathrm N\) | \(-1.246610997\,\mathrm{N\,m}\) | \(-7.413622794\,\mathrm{rad/s^2}\) |
| 2 | \(2\times10^{-10}\,\mathrm{m/s}\) | \(-5.289152788\,\mathrm N\) | \(+0.570106181\,\mathrm{N\,m}\) | \(+3.390433676\,\mathrm{rad/s^2}\) |

The first roll-acceleration difference has magnitude approximately **425°/s²**.

For the second case, dividing the body-axis force difference by the aircraft’s **3.8195476 kg** mass gives an acceleration-difference magnitude of approximately **0.141 g**. The rotational calculation uses the full inverse inertia tensor, including its nonzero \(xz\) coupling.

### Why this is a discontinuity

I reduced the perturbation on each side of the boundary from \(10^{-4}\) to \(10^{-10}\,\mathrm{m/s}\):

| Perturbation on each side | Strip 1 force difference |
|---:|---:|
| \(10^{-4}\,\mathrm{m/s}\) | 3.597166506 N |
| \(10^{-6}\,\mathrm{m/s}\) | 3.598775534 N |
| \(10^{-8}\,\mathrm{m/s}\) | 3.598791624 N |
| \(10^{-10}\,\mathrm{m/s}\) | 3.598791785 N |

The difference converges to a finite value.

Then I changed **only the loaded progression factors to one in memory**, without modifying the repository. The same comparison dropped to approximately **0.0007445 N**, about **4,834 times smaller**.

That isolates the progression-factor interaction as the cause of the large jump.

There is a numerical qualification: Godot’s wrap operation snaps a small interval below \(+\pi\) to \(-\pi\). The measured boundary is slightly displaced from the ideal endpoint. These are therefore measured implementation branch jumps, with a residual wrap effect, rather than exact numerical evaluations at mathematical \(\pm\pi\).

### Why it matters

Reverse-flow states matter to tailslides, tumbles, and other nonlinear aerobatic maneuvers. A discontinuous force law can introduce abrupt accelerations precisely in regimes where smooth local behavior and consistent wake modeling are difficult and important.

The executed probe establishes the local defect. It does **not** establish a particular visible flight failure, ordinary-cruise instability, or an accumulated trajectory error.

The same scaled-angle pattern appears in wake generation and in the native source mirror. The native path was inspected but was not compiled or executed in this audit. See [`aero.gd`, lines 945–953](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/physics/aero.gd#L945-L953) and [`nk_aero.hpp`, lines 766–777](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/research/native-kernel/src/nk_aero.hpp#L766-L777).

### What should change

Separate the coordinate controlling **stall progression** from the geometric angle controlling **fully separated force direction**.

The corrected law should preserve the intended stall transition, then converge smoothly to a continuation based on the true physical angle. The force calculation, wake calculation, and native implementation must agree.

Acceptance should include independent strip-boundary sweeps under nonzero rates, perturbation refinement, held-wake comparisons, ordinary-flight regressions, and an integrated reverse-flow maneuver.

**Archive reproduction:** `strip-seam-held-wake`.

---

## 2. A graphics setting changes whether the aircraft hits an obstacle

### What is wrong

Scene detail filters ornament placements **before the authoritative collision world is built**. Automatic scene detail is derived from GPU information.

The consequence is that a graphics preference changes the physical scenario.

This chain is explicit in [`scene_detail.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/scene_detail.gd#L1-L34) and [`collision_setup.gd`, lines 23–41](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/scenery/collision_setup.gd#L23-L41). The resulting world is installed into the flight session in [`main.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/main.gd#L963-L967).

### What I reproduced

I first counted the selected collidable ornament placements. I then strengthened that analysis by building the **complete production collision worlds** and calling the actual collision API.

| Default-field result | Low | Medium | High |
|---|---:|---:|---:|
| Collidable ornament placements | 0 | 25 | 38 |
| Complete collision proxy count | 6,050 | 6,078 | 6,092 |
| Proxies for the target bench | 0 | 0 | 2 |
| Contact for identical motion | None | None | **Terminal bench collision** |

All three physical world identifiers differ.

The 38 collidable ornament placements on High comprise:

- Four benches.
- Eighteen bushes.
- Thirteen people.
- Three tractors.

Seven flower ornaments were excluded because they do not have a collision implementation. Standard hazards and field trees remain on Low.

### The decisive collision witness

The controlled test uses a point hull, a 2 kg body, and identical state inputs in each world. It moves north by 0.1 m over \(1/240\) second at **24 m/s**, crossing the target bench seat.

On High, the production collision API reports:

```text
obstacle_id: equipment:benches:02:bench_seat
response_class: hard_terminal
terminal: true
time_fraction: 0.499999990000009
normal_speed_mps: 24.0
impact_energy_j: 576.0
```

Low and Medium return no contact for the same motion.

This is a controlled collision-kernel experiment using complete production worlds. It is not a full aircraft playthrough.

### Why this deserves architectural attention

Graphics settings now affect what can physically stop or damage the aircraft. Automatic hardware selection can therefore place two users in different physical environments before either explicitly chooses a different scenario.

The related **RC car circuit** option has the same architectural coupling: its automatic choice depends on a dedicated GPU and High/Extreme detail, while feeding both rendering and wheel terrain/collision. That behavior is documented in [`rc_track_option.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/scenery/rc_track_option.gd#L1-L17) and its [automatic-selection function](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/scenery/rc_track_option.gd#L42-L61).

**This behavior is deliberate and documented.** The project also hashes collision inventories, records world identity, and preserves the installed world during a session. Those are meaningful safeguards, so the evidence does not support calling this silent replay corruption.

The design problem is that the physical scenario is partly controlled by graphics policy.

### What should change

Define physical hazards and terrain through an explicit scenario. Let graphics settings select cheaper representations of those same hazards.

For weak hardware, use simpler visible meshes, cards, or proxies. If removing obstacles is a desired mode, expose it as a scenario choice with a separate identity.

Acceptance is concrete: the same scenario should produce identical collision identities, terrain samples, and contact results across every graphics preset and simulated GPU recommendation.

**Archive reproduction:** `collision-quality-full-world`.

---

## 3. A stale statistics lock can prevent future recording after an interruption

### What is wrong

The statistics store writes its PID as an integer in JSON. When Godot parses that JSON, the number becomes a floating-point value. The validator then insists that the PID has `TYPE_INT`.

The store rejects its own owner-record format before reaching the stale-process recovery logic. The mismatch is visible in [`store.gd`, lines 854–885](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/statistics/store.gd#L854-L885). Godot documents this JSON numeric conversion. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_json.html?utm_source=chatgpt.com)

The failing sequence is:

1. Serialize an integer PID.
2. Parse the JSON owner record.
3. Obtain a floating-point PID.
4. Reject it because it is not `TYPE_INT`.
5. Open the statistics store read-only.

### What I reproduced

The isolated project uses byte-identical production store code and its dependencies.

The probe:

1. Opens a new writable store.
2. Closes it normally.
3. Starts a short-lived child process and verifies that it exits.
4. Writes a production-format owner record containing that exited PID.
5. Reopens the store twice.

Both reopens report:

```text
opened: true
writable: false
note: Statistics writer lock owner is malformed; opened read-only.
```

The original snapshot remains readable.

This fixture synthesizes the production-format stale owner record; it does not claim to be a recorded GUI crash or a force-killed store writer.

### Why it matters

An actual crash or forced termination can leave the writer’s owner record behind. The demonstrated validation path then prevents automatic recovery on subsequent launches.

The effect propagates into gameplay statistics: the service skips recovery when the store is read-only and refuses to begin a persistent activity. See [`service.gd`, lines 61–73](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/statistics/service.gd#L61-L73) and [lines 114–116](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/statistics/service.gd#L114-L116).

**Previously committed history is not shown to be deleted.** The demonstrated problem is that future persistent recording remains blocked until the lock is safely repaired.

The repository already discloses stale-lock recovery as unresolved in [`FLIGHT-STATISTICS.md`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/docs/FLIGHT-STATISTICS.md#L43-L49). This audit independently confirms that the concrete defect remains in the audited commit.

### Why an existing test can miss it

A test that starts a second writer and checks only that it becomes read-only can pass for the wrong reason.

Both of these paths produce the same result:

- Correctly detecting that another live process owns the store.
- Incorrectly declaring its valid owner record malformed.

The test needs to verify the reason and exercise recovery after abrupt process death.

### What should change

Correct the PID codec with finite, integral, and range validation. Then validate the entire ownership protocol.

A cast alone is insufficient: Godot documents `is_process_running` for a valid child PID returned by `create_process`, whereas a separate application instance is normally an independent process. That distinction matters when choosing a reliable cross-process locking design. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/classes/class_os.html?utm_source=chatgpt.com)

Acceptance should cover a force-killed real writer, successful relaunch and recording, protection of a live independent writer, simultaneous reclaim attempts, and process-identity/PID-reuse concerns.

**Archive reproduction:** `statistics-lock-isolated`.

---

## 4. Optional resources load before their disabled-feature guards run

### What is wrong

The project preloads optional scene-builder scripts through constants. Those scripts preload heavy assets of their own.

By the time a build function checks whether the feature is disabled, the dependency chain has already been loaded.

For the RC track, the relevant chain is:

**Main → Field → RcTrackField → RcGroundMaterial → six textures**

`RcTrackField` preloads the material module at the top of the script, then checks for an empty track inside `build()`. See [`rc_track_field.gd`, lines 6–24](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/rc_track_field.gd#L6-L24) and [`rc_ground_material.gd`, lines 4–19](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/rc_ground_material.gd#L4-L19).

This behavior is consistent with Godot’s documented distinction between loading and preloading. [Godot Engine (latest) documentation in English](https://docs.godotengine.org/en/latest/tutorials/best_practices/logic_preferences.html?utm_source=chatgpt.com)

### What I measured

In a fresh headless process, I loaded the unchanged material script without calling either configuration function.

| Observation | Result |
|---|---:|
| Texture paths cached before script load | 0 of 6 |
| Texture paths cached afterward | 6 of 6 |
| Texture dimensions | Each 2048 × 2048 |
| Godot-tracked static memory before | 54,931,562 bytes |
| Godot-tracked static memory afterward | 77,644,145 bytes |
| Increase during the load | **22,712,583 bytes — 21.66 MiB** |

That is a measured allocation consequence before the material is configured.

The figure includes the script, shader, and dependencies. It is **not** texture-only memory, process RSS, VRAM, or a guaranteed 21.66 MiB saving in a complete flight. Several textures have other consumers in countryside, grass, or lake code.

### Why this is broader than one material

The reproducible static dependency walk from `main.gd` found:

- **428 GDScript resources**.
- **126 non-GDScript resources**.
- **137.75 MiB of encoded source assets** across the 77 asset paths represented in the exact-commit size metadata.

That is a dependency inventory, not a runtime memory estimate or a claim that all those resources are unnecessary.

Specific optional chains include approximately **12.38 MB of lake audio** before lake applicability/off checks and a **9.37 MB Ugly Stik engine GLB** reachable through the aircraft builder. The relevant sources include [`lake_world.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/lake/lake_world.gd#L7-L24), [`water_effects.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/lake/water_effects.gd#L8-L10), and [`ugly_stik_equipment.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/aircraft/ugly_stik_equipment.gd#L309).

The architectural opportunity is to make feature and aircraft selection control when heavy dependencies become resident.

### What should change

Keep lightweight manifests and catalogs available early. Load heavy modules and assets after the selected activity, aircraft, and features are known.

Use the controlled loading phase and a bounded cache. Replacing every preload blindly could move synchronous loading into flight and create a different problem.

Acceptance should measure actual off/default/full scene combinations, account for shared consumers, and compare cold/warm startup and memory. Only then should the project claim a specific application-wide saving.

**Archive reproduction:** `rc-material-load`; dependency inventory included separately.

---

## 5. Layered weather defeats the intended cloud-relief cache

### What is wrong

Each nonclassic cloud layer gets a derived seed:

\[
s_i=(s_{\text{base}}+(i+1)\times104729)\ \&\ 0x7fffffff
\]

The sky’s cache request still uses the base seed.

The relief shader explicitly falls back to analytical density when the tile’s seed differs from the requested layer seed.

With base seed **1253**, the first layer seeds are **105982** and **210711**. A cached tile for 1253 cannot satisfy either layer’s lookup.

The chain is in:

- [`sky_appearance.gd`, lines 13–20](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/weather/sky_appearance.gd#L13-L20).
- [`atmosphere.gd`, lines 687–714](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/atmosphere.gd#L687-L714).
- [`cloud_shadow_map.gdshaderinc`, lines 37–51](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/render/cloud_shadow_map.gdshaderinc#L37-L51).

### What I reproduced

The controlled fixture uses **30 byte-identical production source/data files** and synthetic ready textures to exercise actual material-binding logic.

With caching requested and the base-seed tile published:

| Weather preset | Eligible relief-layer seeds | Result |
|---|---|---|
| Classic — application default | 1253 | Matching cache available |
| Fair cumulus | 105982 | Fallback |
| Broken | 105982, 210711 | Both fall back |
| Overcast | 105982, 210711 | Both fall back |
| Prestorm | 105982, 315440, 210711 | All fall back |
| Distant storm | 105982 | Eligible layer falls back |
| Electrical storm | 315440, 105982 | Eligible layers fall back |

Clear and Cirrus have no eligible relief layer in this comparison, yet the fixture still binds the base relief tile.

### What work is being repeated

An active relief evaluation performs three density samples.

In the ordinary production shader variant:

- The analytical fallback computes **five noise octaves** per sample.
- The hybrid cached path computes **two octaves plus a texture lookup**.

The source-level difference is:

\[
3(5-2)=9
\]

That is **nine additional value-noise evaluations**, containing **36 corner-hash calls before compiler optimization**, per eligible pixel and layer.

This count is conditional on the relief branch actually running. It does not apply to every screen pixel, and it is not a measurement of GPU instructions, milliseconds, or FPS.

### Why the qualification matters

Default Classic works. Ground materials bind their selected layer seed correctly. A shared base-seed tile can also remain useful to another consumer.

The defect is specific: **a ready cache does not accelerate the intended layered-sky relief consumer because its key does not match the consumer’s key.**

### What should change

Request and bind tiles for the actual relief-layer seeds. Multi-layer skies need explicit per-layer selection, with bounded residency and analytical fallback retained.

Tests should verify the seeds used by the shader consumers against published cache bindings. Checking only that a requested tile was generated successfully is insufficient.

Then measure representative cold/warm rendering on target GPUs, including visual parity.

**Archive reproduction:** `cloud-seed-ready-fixture`.

---

## A further substantial opportunity: resolve the known local-wing validation gap

I also reran the strict yaw-damping test without its allowance flags.

It completed with **19 checks, one failure, and zero pending allowances**. At \(11^\circ\) angle of attack, the largest difference from the repository’s retained fin-plus-wing-profile approximation is **7.573%**, against a **7%** screen.

However, the independent derivative checks pass:

- Central difference at \(h=0.05\): \(C_{nr}=-0.125403408\).
- Refined difference at \(h=0.0125\): \(C_{nr}=-0.125398381\).
- Independent derivative of the current law: \(C_{nr}=-0.125396872\).

That establishes an unresolved comparison gate. It does not establish a measured 7.573% error against the real aircraft.

The deeper issue is already described in the project’s [local-wing research record](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/docs/research/flight-dynamics/stik-lateral-directional-2026-10-18/README.md#L62-L81): how circulation, nonuniform local flow, and force closure are represented in the nonlinear wing law. Its historical matched-wing comparison reports a much larger wing-only damping discrepancy. I did not rerun that AVL comparison.

This deserves a separate research workstream. The existing record also explains why the superficially easy speed-ratio correction becomes unsafe near a stagnant strip. The solution needs a bounded formulation and coherent wake behavior, followed by fleet qualification.

I have kept this separate from the five headline findings because the evidence supports **an open modeling and validation problem**, with existing ownership and research, rather than another newly demonstrated implementation defect.

## Claims I rejected

A rigorous audit also needs to discard allegations that do not survive verification.

The historical excessive-rudder-sideslip claim does not reproduce at this commit. The clean strict run reports:

| Metric | Right-first doublet | Left-first doublet | Limit |
|---|---:|---:|---:|
| Peak sideslip | 24.88° | 24.08° | 25° |
| Peak yaw rate | 85.03°/s | 79.82°/s | 120°/s |
| Recovery yaw envelope | 6.3% | 6.4% | 10% |

Those flight-handling screens pass.

The test still finishes with one failure because its synthetic radio fixture creates an unconfigured device and expects it to arm. Production deliberately keeps that device unarmed. The relevant mismatch is between the [test fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/tests/test_rudder_authority.gd#L475-L490) and the [unconfigured-radio behavior](https://github.com/bultodepapas/OpenRCsimulator/blob/45d86d250f6e38a3d9b60d30c01bdc2396571efe/app/input/rc_input.gd#L373-L384). It needs test maintenance; it does not establish that configured radios are broken.

I also found no basis for converting repository size into a runtime-memory allegation, converting shader arithmetic into an FPS claim, or claiming that the whole aerodynamic system creates energy.

## Recommended implementation order

1. **Repair the reverse-flow force law.** Preserve intended stall progression and verify force/wake/native consistency.
2. **Repair statistics recovery.** Demonstrate safe recovery after abrupt process death and successful subsequent recording.
3. **Separate physical scenarios from graphics policy.** Keep hazard and terrain identity stable for the same scenario.
4. **Refactor heavy resource acquisition around actual selection.** Measure complete scene combinations before promising savings.
5. **Correct cloud-cache consumer bindings.** Validate every weather preset, then profile on target hardware.
6. **Run the local-wing closure redesign as a dedicated physics research effort.**

The evidence supports concrete changes with measurable completion criteria. The two strongest immediate targets are the **reverse-flow discontinuity** and **stale-lock recovery**; the graphics-to-physics coupling requires an explicit product decision, and the resource/cache findings provide focused optimization work that can be verified without speculative performance claims.